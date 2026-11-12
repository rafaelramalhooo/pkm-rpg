-- m20: o jogador escolhe qual golpe esquecer (ou recusa o novo golpe)
create table if not exists public.golpes_pendentes (
  id uuid primary key default gen_random_uuid(),
  pokemon uuid not null references public.pokemons (id) on delete cascade,
  golpe int not null references public.golpes (id),
  criado timestamptz not null default now(),
  unique (pokemon, golpe)
);
alter table public.golpes_pendentes enable row level security;
drop policy if exists "gp_dono" on public.golpes_pendentes;
create policy "gp_dono" on public.golpes_pendentes for select to authenticated
  using (exists (select 1 from public.pokemons p where p.id = pokemon and p.dono = auth.uid()));
grant select on public.golpes_pendentes to authenticated;

create or replace function public._dar_exp(p_pk public.pokemons, p_sel jsonb, p_ev jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare ganho int := floor((p_sel->>'exp_base')::int * (p_sel->>'nivel')::int / 7.0 * public._ev('xp', 1)); e public.especies; novo public.pokemons := p_pk;
  g record; hpmax_ant int; evo record; r record; nome_ant text; de_ant int;
begin
  select * into e from public.especies where id = novo.especie_id;
  if p_pk.nivel >= 1000 then ganho := 0; end if;
  novo.exp := p_pk.exp + ganho;
  p_ev := p_ev || jsonb_build_array(jsonb_build_object('t', 'exp', 'valor', ganho, 'nome', coalesce(p_pk.apelido, e.nome)));
  while novo.nivel < 1000 and novo.exp >= public.exp_para(novo.nivel + 1) loop
    novo.nivel := novo.nivel + 1;
    hpmax_ant := novo.hp_max;
    novo.hp_max := public.calc_hp(e.hp, novo.iv_hp, novo.nivel);
    novo.atk := public.calc_stat(e.atk, novo.iv_atk, novo.nivel, public.mult_nat(novo.natureza, 'attack'));
    novo.def := public.calc_stat(e.def, novo.iv_def, novo.nivel, public.mult_nat(novo.natureza, 'defense'));
    novo.spa := public.calc_stat(e.spa, novo.iv_spa, novo.nivel, public.mult_nat(novo.natureza, 'sp_attack'));
    novo.spd := public.calc_stat(e.spd, novo.iv_spd, novo.nivel, public.mult_nat(novo.natureza, 'sp_defense'));
    novo.spe := public.calc_stat(e.spe, novo.iv_spe, novo.nivel, public.mult_nat(novo.natureza, 'speed'));
    novo.hp_atual := novo.hp_atual + (novo.hp_max - hpmax_ant);
    p_ev := p_ev || jsonb_build_array(jsonb_build_object('t', 'nivel', 'nome', coalesce(p_pk.apelido, e.nome), 'nivel', novo.nivel));
    -- evolução por nível (vale também para quem já passou do nível mínimo)
    select * into evo from public.evolucoes where de = novo.especie_id and nivel is not null and nivel <= novo.nivel order by nivel desc limit 1;
    if found then
      nome_ant := coalesce(p_pk.apelido, e.nome); de_ant := novo.especie_id;
      novo := public._aplicar_evolucao(novo, evo.para);
      select * into e from public.especies where id = novo.especie_id;
      p_ev := p_ev || jsonb_build_array(jsonb_build_object('t', 'evolucao', 'nome', nome_ant, 'para', e.nome, 'especie_id', e.id, 'de_id', de_ant));
    end if;
    -- golpes que a espécie atual aprende neste nível
    for g in select a.golpe_id, gg.nome from public.aprende a join public.golpes gg on gg.id = a.golpe_id
              where a.especie_id = novo.especie_id and a.nivel = novo.nivel and coalesce(gg.poder, 0) > 0 loop
      if exists (select 1 from jsonb_array_elements(novo.golpes) x where (x->>'id')::int = g.golpe_id) then continue; end if;
      if jsonb_array_length(novo.golpes) < 4 then
        novo.golpes := novo.golpes || jsonb_build_array(jsonb_build_object('id', g.golpe_id, 'pp', (select pp from public.golpes where id = g.golpe_id)));
        p_ev := p_ev || jsonb_build_array(jsonb_build_object('t', 'aprendeu', 'nome', coalesce(p_pk.apelido, e.nome), 'golpe', g.nome, 'esqueceu', null));
      else
        -- já sabe 4 golpes: fica pendente até o jogador escolher (esquecer um ou recusar)
        insert into public.golpes_pendentes (pokemon, golpe) values (p_pk.id, g.golpe_id) on conflict do nothing;
        p_ev := p_ev || jsonb_build_array(jsonb_build_object('t', 'aprender', 'pokemon', p_pk.id, 'nome', coalesce(p_pk.apelido, e.nome), 'golpe', g.nome, 'golpe_id', g.golpe_id));
      end if;
    end loop;
  end loop;
  update public.pokemons set especie_id = novo.especie_id, nivel = novo.nivel, exp = novo.exp, hp_max = novo.hp_max, atk = novo.atk, def = novo.def, spa = novo.spa,
    spd = novo.spd, spe = novo.spe, hp_atual = novo.hp_atual, golpes = novo.golpes where id = p_pk.id;
  return p_ev;
end $$;


create or replace function public.golpes_pendentes_lista() returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', gp.id, 'pokemon', p.id, 'nome', coalesce(p.apelido, e.nome), 'especie_id', e.id,
           'golpe_id', gp.golpe, 'golpe', g.nome, 'golpes', p.golpes) order by gp.criado), '[]'::jsonb)
    from public.golpes_pendentes gp join public.pokemons p on p.id = gp.pokemon join public.especies e on e.id = p.especie_id
    join public.golpes g on g.id = gp.golpe where p.dono = auth.uid() $$;
grant execute on function public.golpes_pendentes_lista() to authenticated;

-- p_esquecer = id do golpe a esquecer; null = recusar o novo golpe
create or replace function public.resolver_golpe(p_pendente uuid, p_esquecer int default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare gp public.golpes_pendentes; pk public.pokemons; g public.golpes; novos jsonb;
begin
  if auth.uid() is null then raise exception 'Faça login primeiro.'; end if;
  select * into gp from public.golpes_pendentes where id = p_pendente;
  if not found then raise exception 'Esta escolha não existe mais.'; end if;
  select * into pk from public.pokemons where id = gp.pokemon and dono = auth.uid() for update;
  if not found then raise exception 'Pokémon não encontrado.'; end if;
  select * into g from public.golpes where id = gp.golpe;
  if p_esquecer is null then
    delete from public.golpes_pendentes where id = gp.id;
    return jsonb_build_object('aprendeu', false, 'golpe', g.nome);
  end if;
  if not exists (select 1 from jsonb_array_elements(pk.golpes) x where (x->>'id')::int = p_esquecer) then raise exception 'Este Pokémon não conhece esse golpe.'; end if;
  select coalesce(jsonb_agg(case when (t.x->>'id')::int = p_esquecer then jsonb_build_object('id', g.id, 'pp', g.pp) else t.x end order by t.ord), '[]'::jsonb)
    into novos from jsonb_array_elements(pk.golpes) with ordinality t(x, ord);
  update public.pokemons set golpes = novos where id = pk.id;
  delete from public.golpes_pendentes where id = gp.id;
  return jsonb_build_object('aprendeu', true, 'golpe', g.nome);
end $$;
grant execute on function public.resolver_golpe(uuid, int) to authenticated;
