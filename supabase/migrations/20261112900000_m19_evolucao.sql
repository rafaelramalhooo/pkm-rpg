-- m19: evolução (por nível ou pedra), golpes ao evoluir, e Pokémon evoluídos entram na Pokédex.
-- Fonte: PokéAPI (pokemon_evolution). Evoluções por troca viram nível 36 (não há troca entre jogadores).
create table if not exists public.evolucoes (
  de int not null references public.especies (id), para int not null references public.especies (id),
  nivel int, item text, unique (de, para)
);
alter table public.evolucoes enable row level security;
drop policy if exists "evolucoes_leitura" on public.evolucoes;
create policy "evolucoes_leitura" on public.evolucoes for select to authenticated using (true);
grant select on public.evolucoes to authenticated;
insert into public.evolucoes (de, para, nivel, item) values
(1,2,16,null),
(2,3,32,null),
(4,5,16,null),
(5,6,36,null),
(7,8,16,null),
(8,9,36,null),
(10,11,7,null),
(11,12,10,null),
(13,14,7,null),
(14,15,10,null),
(16,17,18,null),
(17,18,36,null),
(19,20,20,null),
(21,22,20,null),
(23,24,22,null),
(25,26,null,'thunder-stone'),
(27,28,22,null),
(29,30,16,null),
(30,31,null,'moon-stone'),
(32,33,16,null),
(33,34,null,'moon-stone'),
(35,36,null,'moon-stone'),
(37,38,null,'fire-stone'),
(39,40,null,'moon-stone'),
(41,42,22,null),
(43,44,21,null),
(44,45,null,'leaf-stone'),
(46,47,24,null),
(48,49,31,null),
(50,51,26,null),
(52,53,28,null),
(54,55,33,null),
(56,57,28,null),
(58,59,null,'fire-stone'),
(60,61,25,null),
(61,62,null,'water-stone'),
(63,64,16,null),
(64,65,36,null),
(66,67,28,null),
(67,68,36,null),
(69,70,21,null),
(70,71,null,'leaf-stone'),
(72,73,30,null),
(74,75,25,null),
(75,76,36,null),
(77,78,40,null),
(79,80,37,null),
(81,82,30,null),
(84,85,31,null),
(86,87,34,null),
(88,89,38,null),
(90,91,null,'water-stone'),
(92,93,25,null),
(93,94,36,null),
(96,97,26,null),
(98,99,28,null),
(100,101,null,'leaf-stone'),
(102,103,null,'leaf-stone'),
(104,105,28,null),
(109,110,35,null),
(111,112,42,null),
(116,117,32,null),
(118,119,33,null),
(120,121,null,'water-stone'),
(129,130,20,null),
(133,134,null,'water-stone'),
(133,135,null,'thunder-stone'),
(133,136,null,'fire-stone'),
(138,139,40,null),
(140,141,40,null),
(147,148,30,null),
(148,149,55,null)
on conflict (de, para) do update set nivel = excluded.nivel, item = excluded.item;

-- recalcula os atributos de um Pokémon ao mudar de espécie (preserva o HP perdido)
create or replace function public._aplicar_evolucao(p public.pokemons, p_para int) returns public.pokemons
language plpgsql security definer set search_path = public as $$
declare e public.especies; n public.pokemons := p; ant int := p.hp_max;
begin
  select * into e from public.especies where id = p_para;
  n.especie_id := p_para;
  n.hp_max := public.calc_hp(e.hp, n.iv_hp, n.nivel);
  n.atk := public.calc_stat(e.atk, n.iv_atk, n.nivel, public.mult_nat(n.natureza, 'attack'));
  n.def := public.calc_stat(e.def, n.iv_def, n.nivel, public.mult_nat(n.natureza, 'defense'));
  n.spa := public.calc_stat(e.spa, n.iv_spa, n.nivel, public.mult_nat(n.natureza, 'sp_attack'));
  n.spd := public.calc_stat(e.spd, n.iv_spd, n.nivel, public.mult_nat(n.natureza, 'sp_defense'));
  n.spe := public.calc_stat(e.spe, n.iv_spe, n.nivel, public.mult_nat(n.natureza, 'speed'));
  n.hp_atual := greatest(case when p.hp_atual > 0 then 1 else 0 end, p.hp_atual + (n.hp_max - ant));
  insert into public.pokedex (jogador, especie_id, capturado) values (p.dono, p_para, true)
  on conflict (jogador, especie_id) do update set capturado = true;
  return n;
end $$;
revoke all on function public._aplicar_evolucao(public.pokemons, int) from public, anon, authenticated;

-- aprender um golpe: se há vaga, entra; senão substitui o mais fraco quando o novo é mais forte
create or replace function public._aprender_golpe(p_golpes jsonb, p_golpe int, out o_golpes jsonb, out o_esqueceu text)
language plpgsql security definer set search_path = public as $$
declare g public.golpes; fraco record;
begin
  o_golpes := p_golpes; o_esqueceu := null;
  select * into g from public.golpes where id = p_golpe;
  if not found or exists (select 1 from jsonb_array_elements(p_golpes) x where (x->>'id')::int = p_golpe) then o_golpes := null; return; end if;
  if jsonb_array_length(p_golpes) < 4 then
    o_golpes := p_golpes || jsonb_build_array(jsonb_build_object('id', g.id, 'pp', g.pp)); return;
  end if;
  select (t.x->>'id')::int as id, coalesce(gg.poder, 0) as poder, gg.nome into fraco
    from jsonb_array_elements(p_golpes) with ordinality t(x, ord) join public.golpes gg on gg.id = (t.x->>'id')::int
   order by coalesce(gg.poder, 0), t.ord limit 1;
  if coalesce(g.poder, 0) <= fraco.poder then o_golpes := null; return; end if;
  o_golpes := (select coalesce(jsonb_agg(case when (t.x->>'id')::int = fraco.id then jsonb_build_object('id', g.id, 'pp', g.pp) else t.x end order by t.ord), '[]'::jsonb)
                 from jsonb_array_elements(p_golpes) with ordinality t(x, ord));
  o_esqueceu := fraco.nome;
end $$;
revoke all on function public._aprender_golpe(jsonb, int) from public, anon, authenticated;

create or replace function public._dar_exp(p_pk public.pokemons, p_sel jsonb, p_ev jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare ganho int := floor((p_sel->>'exp_base')::int * (p_sel->>'nivel')::int / 7.0 * public._ev('xp', 1)); e public.especies; novo public.pokemons := p_pk;
  g record; hpmax_ant int; evo record; r record; nome_ant text;
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
      nome_ant := coalesce(p_pk.apelido, e.nome);
      novo := public._aplicar_evolucao(novo, evo.para);
      select * into e from public.especies where id = novo.especie_id;
      p_ev := p_ev || jsonb_build_array(jsonb_build_object('t', 'evolucao', 'nome', nome_ant, 'para', e.nome, 'especie_id', e.id));
    end if;
    -- golpes que a espécie atual aprende neste nível
    for g in select a.golpe_id, gg.nome from public.aprende a join public.golpes gg on gg.id = a.golpe_id
              where a.especie_id = novo.especie_id and a.nivel = novo.nivel and coalesce(gg.poder, 0) > 0 loop
      select * into r from public._aprender_golpe(novo.golpes, g.golpe_id);
      if r.o_golpes is not null then
        novo.golpes := r.o_golpes;
        p_ev := p_ev || jsonb_build_array(jsonb_build_object('t', 'aprendeu', 'nome', coalesce(p_pk.apelido, e.nome), 'golpe', g.nome, 'esqueceu', r.o_esqueceu));
      end if;
    end loop;
  end loop;
  update public.pokemons set especie_id = novo.especie_id, nivel = novo.nivel, exp = novo.exp, hp_max = novo.hp_max, atk = novo.atk, def = novo.def, spa = novo.spa,
    spd = novo.spd, spe = novo.spe, hp_atual = novo.hp_atual, golpes = novo.golpes where id = p_pk.id;
  return p_ev;
end $$;

-- itens da mochila fora de batalha: curas + pedras de evolução
create or replace function public.usar_item_fora(p_item text, p_pokemon uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare pk public.pokemons; cura int; novo int; evo record; n public.pokemons; nome_ant text; e public.especies;
begin
  if auth.uid() is null then raise exception 'Faça login primeiro.'; end if;
  if exists (select 1 from public.batalhas where jogador = auth.uid() and estado = 'ativa') then raise exception 'Use os itens pelo menu da batalha.'; end if;
  select * into pk from public.pokemons where id = p_pokemon and dono = auth.uid() for update;
  if not found then raise exception 'Pokémon não encontrado.'; end if;
  if not exists (select 1 from public.inventario where jogador = auth.uid() and item = p_item and qtd > 0) then raise exception 'Você não tem este item.'; end if;
  if p_item like '%-stone' then
    select * into evo from public.evolucoes where de = pk.especie_id and item = p_item;
    if not found then raise exception 'Isto não surte efeito neste Pokémon.'; end if;
    select nome into nome_ant from public.especies where id = pk.especie_id;
    n := public._aplicar_evolucao(pk, evo.para);
    update public.pokemons set especie_id = n.especie_id, hp_max = n.hp_max, atk = n.atk, def = n.def, spa = n.spa, spd = n.spd, spe = n.spe, hp_atual = n.hp_atual where id = pk.id;
    update public.inventario set qtd = qtd - 1 where jogador = auth.uid() and item = p_item;
    select * into e from public.especies where id = evo.para;
    return jsonb_build_object('evolucao', jsonb_build_object('nome', coalesce(pk.apelido, nome_ant), 'para', e.nome));
  end if;
  cura := case p_item when 'potion' then 20 when 'super-potion' then 50 when 'hyper-potion' then 200 when 'max-potion' then 99999
                      when 'full-restore' then 99999 when 'revive' then -1 when 'max-revive' then -2 else null end;
  if cura is null then raise exception 'Este item não pode ser usado aqui.'; end if;
  if cura < 0 then
    if pk.hp_atual > 0 then raise exception 'Este Pokémon não está desmaiado.'; end if;
    novo := case when cura = -1 then greatest(1, pk.hp_max / 2) else pk.hp_max end;
  else
    if pk.hp_atual <= 0 then raise exception 'Use uma Revive neste Pokémon.'; end if;
    if pk.hp_atual >= pk.hp_max then raise exception 'O HP já está cheio.'; end if;
    novo := least(pk.hp_max, pk.hp_atual + cura);
  end if;
  update public.pokemons set hp_atual = novo where id = pk.id;
  update public.inventario set qtd = qtd - 1 where jogador = auth.uid() and item = p_item;
  return jsonb_build_object('hp', novo, 'hp_max', pk.hp_max);
end $$;
grant execute on function public.usar_item_fora(text, uuid) to authenticated;
