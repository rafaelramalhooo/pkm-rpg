-- m16: remove o limite de nível dos Pokémon (nível dos adversários continua em função do time).
-- Único teto: 1000 (técnico: a experiência é inteira; nível^3 cabe em int até 1290).
do $$ declare c text; begin
  for c in select conname from pg_constraint where conrelid = 'public.pokemons'::regclass and contype = 'c' and pg_get_constraintdef(oid) ilike '%nivel%' loop
    execute format('alter table public.pokemons drop constraint %I', c);
  end loop;
end $$;
alter table public.pokemons add constraint pokemons_nivel_check check (nivel between 1 and 1000);

-- compatibilidade: o antigo teto por insígnias deixa de existir
create or replace function public._teto_nivel(p_j uuid) returns int language sql stable security definer set search_path = public as $$ select 1000 $$;

create or replace function public._dar_exp(p_pk public.pokemons, p_sel jsonb, p_ev jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare ganho int := floor((p_sel->>'exp_base')::int * (p_sel->>'nivel')::int / 7.0 * public._ev('xp', 1)); e public.especies; novo public.pokemons := p_pk;
  g record; hpmax_ant int;
begin
  select * into e from public.especies where id = p_pk.especie_id;
  if p_pk.nivel >= 1000 then ganho := 0; end if; -- teto técnico (exp é int)
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
    for g in select a.golpe_id, gg.nome, gg.pp from public.aprende a join public.golpes gg on gg.id = a.golpe_id
              where a.especie_id = p_pk.especie_id and a.nivel = novo.nivel and coalesce(gg.poder, 0) > 0 loop
      if jsonb_array_length(novo.golpes) < 4 and not exists (select 1 from jsonb_array_elements(novo.golpes) x where (x->>'id')::int = g.golpe_id) then
        novo.golpes := novo.golpes || jsonb_build_array(jsonb_build_object('id', g.golpe_id, 'pp', g.pp));
        p_ev := p_ev || jsonb_build_array(jsonb_build_object('t', 'aprendeu', 'nome', coalesce(p_pk.apelido, e.nome), 'golpe', g.nome));
      end if;
    end loop;
  end loop;
  update public.pokemons set nivel = novo.nivel, exp = novo.exp, hp_max = novo.hp_max, atk = novo.atk, def = novo.def, spa = novo.spa,
    spd = novo.spd, spe = novo.spe, hp_atual = novo.hp_atual, golpes = novo.golpes where id = p_pk.id;
  return p_ev;
end $$;

create or replace function public._equipe_escalada(t public.treinadores, p_ref int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  esc jsonb := t.escala; n int := coalesce((esc->>'time')::int, 3); bonus int := coalesce((esc->>'bonus')::int, 0);
  piso int := coalesce((esc->>'piso')::int, 1); var int := coalesce((esc->>'var')::int, 2); dif int := public._dificuldade();
  ace jsonb := esc->'ace'; pool jsonb := esc->'pool'; k int; total int; lvl int; ent jsonb; usadas int[] := '{}'; res jsonb := '[]'::jsonb;
begin
  total := n - case when ace is not null then 1 else 0 end;
  for k in 1 .. total loop
    lvl := least(1000, greatest(piso, p_ref + bonus + dif + floor(random() * (var + 1))::int));
    ent := null;
    select e into ent from jsonb_array_elements(pool) e
     where (e->>'de')::int <= lvl and (e->>'ate')::int >= lvl and not ((e->>'linha')::int = any(usadas)) order by random() limit 1;
    if ent is null then
      select e into ent from jsonb_array_elements(pool) e where (e->>'de')::int <= lvl and (e->>'ate')::int >= lvl order by random() limit 1;
    end if;
    if ent is null then
      select e into ent from jsonb_array_elements(pool) e order by least(abs((e->>'de')::int - lvl), abs((e->>'ate')::int - lvl)) limit 1;
      lvl := greatest((ent->>'de')::int, least((ent->>'ate')::int, lvl));
    end if;
    usadas := usadas || (ent->>'linha')::int;
    res := res || public._equipe_treinador(jsonb_build_array(jsonb_build_object('especie', (ent->>'e')::int, 'nivel', lvl)));
  end loop;
  if ace is not null then
    lvl := least(1000, greatest(piso, p_ref + (ace->>'bonus')::int + dif));
    res := res || public._equipe_treinador(jsonb_build_array(jsonb_build_object('especie', (ace->>'e')::int, 'nivel', lvl)));
  end if;
  return res;
end $$;

create or replace function public.mestre_editar_pokemon(p_id uuid, p_campos jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare v_n int;
begin
  if not public.eh_mestre() then raise exception 'Só o Mestre.'; end if;
  if not exists (select 1 from public.pokemons where id = p_id) then raise exception 'Pokémon não encontrado.'; end if;
  if p_campos ? 'apelido' then update public.pokemons set apelido = nullif(btrim(p_campos->>'apelido'), '') where id = p_id; end if;
  if p_campos ? 'brilhante' then update public.pokemons set brilhante = (p_campos->>'brilhante')::boolean where id = p_id; end if;
  if p_campos ? 'nivel' then
    v_n := greatest(1, least(1000, (p_campos->>'nivel')::int));
    update public.pokemons set nivel = v_n, exp = public.exp_para(v_n) where id = p_id;
    perform public._recalcular_pokemon(p_id);
    update public.pokemons set hp_atual = hp_max where id = p_id;
  end if;
  if p_campos ? 'curar' and (p_campos->>'curar')::boolean then update public.pokemons set hp_atual = hp_max where id = p_id; end if;
  insert into public.auditoria (ator, acao, detalhe) values (auth.uid(), 'mestre_editar_pokemon', jsonb_build_object('pokemon', p_id, 'campos', p_campos));
end $$;
grant execute on function public.mestre_editar_pokemon(uuid, jsonb) to authenticated;

create or replace function public.mestre_dar_pokemon(p_jogador uuid, p_especie int, p_nivel int, p_brilhante boolean default false) returns uuid
language plpgsql security definer set search_path = public as $$
declare v public.pokemons;
begin
  if not public.eh_mestre() then raise exception 'Só o Mestre.'; end if;
  if not exists (select 1 from public.jogadores where id = p_jogador) then raise exception 'Jogador não encontrado.'; end if;
  v := public._novo_pokemon(p_jogador, p_especie, greatest(1, least(1000, p_nivel)), null, coalesce(p_brilhante, false));
  insert into public.auditoria (ator, acao, detalhe) values (auth.uid(), 'mestre_dar_pokemon', jsonb_build_object('jogador', p_jogador, 'especie', p_especie, 'nivel', p_nivel));
  return v.id;
end $$;
grant execute on function public.mestre_dar_pokemon(uuid, int, int, boolean) to authenticated;
