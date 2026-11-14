-- m30: Rare Candy cadastrada (corrige o erro do presente), uso de itens fora de batalha revisado,
-- evolução com distribuição livre dos pontos ganhos (regra: maior atributo <= 2x o menor).

insert into public.itens (slug, nome, categoria, efeito, arco)
values ('rare-candy', 'Rare Candy', 'medicine', 'Sobe um nível do Pokémon na hora.', 1)
on conflict (slug) do update set nome = excluded.nome, efeito = excluded.efeito;

alter table public.pokemons add column if not exists ajuste jsonb not null default '{}'::jsonb;   -- pontos distribuídos pelo jogador (somados à fórmula)
alter table public.pokemons add column if not exists evo_pend jsonb;                              -- {gain:{atk,def,spa,spd,spe}, pool:int} a distribuir

create or replace function public._aj(p public.pokemons, k text) returns int language sql immutable as $$ select coalesce((p.ajuste->>k)::int, 0) $$;

-- recalcula atributos mantendo os pontos distribuídos
create or replace function public._recalcular_pokemon(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare pk public.pokemons; e public.especies; novo_hp int;
begin
  select * into pk from public.pokemons where id = p_id;
  select * into e from public.especies where id = pk.especie_id;
  novo_hp := public.calc_hp(e.hp, pk.iv_hp, pk.nivel);
  update public.pokemons set hp_max = novo_hp, hp_atual = least(hp_atual, novo_hp),
    atk = public.calc_stat(e.atk, pk.iv_atk, pk.nivel, public.mult_nat(pk.natureza, 'attack')) + public._aj(pk, 'atk'),
    def = public.calc_stat(e.def, pk.iv_def, pk.nivel, public.mult_nat(pk.natureza, 'defense')) + public._aj(pk, 'def'),
    spa = public.calc_stat(e.spa, pk.iv_spa, pk.nivel, public.mult_nat(pk.natureza, 'sp_attack')) + public._aj(pk, 'spa'),
    spd = public.calc_stat(e.spd, pk.iv_spd, pk.nivel, public.mult_nat(pk.natureza, 'sp_defense')) + public._aj(pk, 'spd'),
    spe = public.calc_stat(e.spe, pk.iv_spe, pk.nivel, public.mult_nat(pk.natureza, 'speed')) + public._aj(pk, 'spe'),
    exp = greatest(exp, public.exp_para(pk.nivel))
  where id = p_id;
end $$;
revoke all on function public._recalcular_pokemon(uuid) from public, anon, authenticated;

-- evolução: aplica a espécie nova e guarda os pontos ganhos para o jogador redistribuir
create or replace function public._aplicar_evolucao(p public.pokemons, p_para int) returns public.pokemons
language plpgsql security definer set search_path = public as $$
declare eo public.especies; e public.especies; n public.pokemons := p; ant int := p.hp_max;
  go jsonb; gn jsonb := '{}'::jsonb; k text; vo int; vn int; g int; pool int := 0; pend jsonb;
begin
  select * into eo from public.especies where id = p.especie_id;
  select * into e from public.especies where id = p_para;
  n.especie_id := p_para;
  n.hp_max := public.calc_hp(e.hp, n.iv_hp, n.nivel);
  foreach k in array array['atk','def','spa','spd','spe'] loop
    vo := public.calc_stat((to_jsonb(eo)->>k)::int, (to_jsonb(p)->>('iv_' || k))::int, p.nivel, public.mult_nat(p.natureza, case k when 'atk' then 'attack' when 'def' then 'defense' when 'spa' then 'sp_attack' when 'spd' then 'sp_defense' else 'speed' end));
    vn := public.calc_stat((to_jsonb(e)->>k)::int, (to_jsonb(p)->>('iv_' || k))::int, p.nivel, public.mult_nat(p.natureza, case k when 'atk' then 'attack' when 'def' then 'defense' when 'spa' then 'sp_attack' when 'spd' then 'sp_defense' else 'speed' end));
    g := greatest(0, vn - vo);
    gn := gn || jsonb_build_object(k, g);
    pool := pool + g;
    n := jsonb_populate_record(n, jsonb_build_object(k, vn + coalesce((p.ajuste->>k)::int, 0)));
  end loop;
  n.hp_atual := greatest(case when p.hp_atual > 0 then 1 else 0 end, p.hp_atual + (n.hp_max - ant));
  -- soma aos pontos que já estavam pendentes (evolução em sequência)
  select evo_pend into pend from public.pokemons where id = p.id;
  if pend is not null then
    foreach k in array array['atk','def','spa','spd','spe'] loop
      gn := gn || jsonb_build_object(k, (gn->>k)::int + coalesce((pend->'gain'->>k)::int, 0));
    end loop;
    pool := pool + coalesce((pend->>'pool')::int, 0);
  end if;
  if pool > 0 then update public.pokemons set evo_pend = jsonb_build_object('gain', gn, 'pool', pool) where id = p.id; end if;
  insert into public.pokedex (jogador, especie_id, capturado) values (p.dono, p_para, true)
  on conflict (jogador, especie_id) do update set capturado = true;
  return n;
end $$;
revoke all on function public._aplicar_evolucao(public.pokemons, int) from public, anon, authenticated;

-- ganho de experiência: a subida de nível respeita os pontos distribuídos (ajuste)
create or replace function public._dar_exp(p_pk public.pokemons, p_sel jsonb, p_ev jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare ganho int := floor((p_sel->>'exp_base')::int * (p_sel->>'nivel')::int / 7.0 * public._ev('xp', 1)
    * (1 + (public._bonus(p_pk.dono, 'veterano') + case when p_pk.amizade >= 150 then public._bonus(p_pk.dono, 'laco') else 0 end) / 100.0)); e public.especies; novo public.pokemons := p_pk;
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
    novo.atk := public.calc_stat(e.atk, novo.iv_atk, novo.nivel, public.mult_nat(novo.natureza, 'attack')) + public._aj(novo, 'atk');
    novo.def := public.calc_stat(e.def, novo.iv_def, novo.nivel, public.mult_nat(novo.natureza, 'defense')) + public._aj(novo, 'def');
    novo.spa := public.calc_stat(e.spa, novo.iv_spa, novo.nivel, public.mult_nat(novo.natureza, 'sp_attack')) + public._aj(novo, 'spa');
    novo.spd := public.calc_stat(e.spd, novo.iv_spd, novo.nivel, public.mult_nat(novo.natureza, 'sp_defense')) + public._aj(novo, 'spd');
    novo.spe := public.calc_stat(e.spe, novo.iv_spe, novo.nivel, public.mult_nat(novo.natureza, 'speed')) + public._aj(novo, 'spe');
    novo.hp_atual := novo.hp_atual + (novo.hp_max - hpmax_ant);
    p_ev := p_ev || jsonb_build_array(jsonb_build_object('t', 'nivel', 'nome', coalesce(p_pk.apelido, e.nome), 'nivel', novo.nivel));
    select * into evo from public.evolucoes where de = novo.especie_id and nivel is not null and nivel <= novo.nivel order by nivel desc limit 1;
    if found then
      nome_ant := coalesce(p_pk.apelido, e.nome); de_ant := novo.especie_id;
      novo := public._aplicar_evolucao(novo, evo.para);
      select * into e from public.especies where id = novo.especie_id;
      p_ev := p_ev || jsonb_build_array(jsonb_build_object('t', 'evolucao', 'nome', nome_ant, 'para', e.nome, 'especie_id', e.id, 'de_id', de_ant, 'pontos', true));
    end if;
    for g in select a.golpe_id, gg.nome from public.aprende a join public.golpes gg on gg.id = a.golpe_id
              where a.especie_id = novo.especie_id and a.nivel = novo.nivel loop
      if exists (select 1 from jsonb_array_elements(novo.golpes) x where (x->>'id')::int = g.golpe_id) then continue; end if;
      if jsonb_array_length(novo.golpes) < 4 then
        novo.golpes := novo.golpes || jsonb_build_array(jsonb_build_object('id', g.golpe_id, 'pp', (select pp from public.golpes where id = g.golpe_id)));
        p_ev := p_ev || jsonb_build_array(jsonb_build_object('t', 'aprendeu', 'nome', coalesce(p_pk.apelido, e.nome), 'golpe', g.nome, 'esqueceu', null));
      else
        insert into public.golpes_pendentes (pokemon, golpe) values (p_pk.id, g.golpe_id) on conflict do nothing;
        p_ev := p_ev || jsonb_build_array(jsonb_build_object('t', 'aprender', 'pokemon', p_pk.id, 'nome', coalesce(p_pk.apelido, e.nome), 'golpe', g.nome, 'golpe_id', g.golpe_id));
      end if;
    end loop;
  end loop;
  update public.pokemons set especie_id = novo.especie_id, nivel = novo.nivel, exp = novo.exp, hp_max = novo.hp_max, atk = novo.atk, def = novo.def, spa = novo.spa,
    spd = novo.spd, spe = novo.spe, hp_atual = novo.hp_atual, golpes = novo.golpes where id = p_pk.id;
  return p_ev;
end $$;
revoke all on function public._dar_exp(public.pokemons, jsonb, jsonb) from public, anon, authenticated;

-- o jogador distribui livremente os pontos que a evolução deu (só esses). Regra: maior atributo <= 2x o menor.
create or replace function public.distribuir_evolucao(p_pokemon uuid, p_aloc jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare pk public.pokemons; k text; a int; soma int := 0; pool int; g int; nv jsonb := '{}'::jsonb; aut jsonb := '{}'::jsonb; mx int; mn int; amx int; amn int; novo_aj jsonb;
begin
  if auth.uid() is null then raise exception 'Faça login primeiro.'; end if;
  select * into pk from public.pokemons where id = p_pokemon and dono = auth.uid() for update;
  if not found then raise exception 'Pokémon não encontrado.'; end if;
  if pk.evo_pend is null then raise exception 'Este Pokémon não tem pontos para distribuir.'; end if;
  pool := (pk.evo_pend->>'pool')::int;
  novo_aj := pk.ajuste;
  foreach k in array array['atk','def','spa','spd','spe'] loop
    a := coalesce((p_aloc->>k)::int, 0);
    if a < 0 then raise exception 'Pontos inválidos.'; end if;
    soma := soma + a;
    g := coalesce((pk.evo_pend->'gain'->>k)::int, 0);
    aut := aut || jsonb_build_object(k, (to_jsonb(pk)->>k)::int);
    nv := nv || jsonb_build_object(k, (to_jsonb(pk)->>k)::int - g + a);
    novo_aj := novo_aj || jsonb_build_object(k, coalesce((pk.ajuste->>k)::int, 0) - g + a);
  end loop;
  if soma <> pool then raise exception 'Distribua exatamente % pontos (você usou %).', pool, soma; end if;
  select max(v::int), min(v::int) into mx, mn from jsonb_each_text(nv) t(k, v);
  select max(v::int), min(v::int) into amx, amn from jsonb_each_text(aut) t(k, v);
  -- maior <= 2x o menor (se a ficha automática já fugia disso, não pode piorar)
  if mx > greatest(2.0, amx::numeric / greatest(1, amn)) * greatest(1, mn) then
    raise exception 'O maior atributo (%) não pode ser mais que o dobro do menor (%).', mx, mn;
  end if;
  update public.pokemons set atk = (nv->>'atk')::int, def = (nv->>'def')::int, spa = (nv->>'spa')::int, spd = (nv->>'spd')::int, spe = (nv->>'spe')::int,
    ajuste = novo_aj, evo_pend = null where id = pk.id;
  return nv;
end $$;
revoke all on function public.distribuir_evolucao(uuid, jsonb) from public, anon;
grant execute on function public.distribuir_evolucao(uuid, jsonb) to authenticated;

-- itens fora de batalha: curas, reviver, pedras e Rare Candy; mensagens claras para o resto
create or replace function public.usar_item_fora(p_item text, p_pokemon uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare pk public.pokemons; cura int; novo int; evo record; n public.pokemons; nome_ant text; e public.especies; ev jsonb := '[]'::jsonb; nome_pk text;
begin
  if auth.uid() is null then raise exception 'Faça login primeiro.'; end if;
  if exists (select 1 from public.batalhas where jogador = auth.uid() and estado = 'ativa') then raise exception 'Use os itens pelo menu da batalha.'; end if;
  select * into pk from public.pokemons where id = p_pokemon and dono = auth.uid() for update;
  if not found then raise exception 'Pokémon não encontrado.'; end if;
  if not exists (select 1 from public.inventario where jogador = auth.uid() and item = p_item and qtd > 0) then raise exception 'Você não tem este item.'; end if;
  select coalesce(pk.apelido, nome) into nome_pk from public.especies where id = pk.especie_id;
  if p_item like '%-stone' then
    select * into evo from public.evolucoes where de = pk.especie_id and item = p_item;
    if not found then raise exception 'Isto não surte efeito em %.', nome_pk; end if;
    select nome into nome_ant from public.especies where id = pk.especie_id;
    n := public._aplicar_evolucao(pk, evo.para);
    update public.pokemons set especie_id = n.especie_id, hp_max = n.hp_max, atk = n.atk, def = n.def, spa = n.spa, spd = n.spd, spe = n.spe, hp_atual = n.hp_atual where id = pk.id;
    update public.inventario set qtd = qtd - 1 where jogador = auth.uid() and item = p_item;
    select * into e from public.especies where id = evo.para;
    return jsonb_build_object('evolucao', jsonb_build_object('nome', coalesce(pk.apelido, nome_ant), 'para', e.nome, 'pontos', true));
  end if;
  if p_item = 'rare-candy' then
    if pk.nivel >= 1000 then raise exception '% já está no nível máximo.', nome_pk; end if;
    update public.pokemons set exp = greatest(exp, public.exp_para(nivel + 1)) where id = pk.id;
    select * into pk from public.pokemons where id = pk.id;
    ev := public._dar_exp(pk, jsonb_build_object('exp_base', 0, 'nivel', 1), '[]'::jsonb);
    update public.inventario set qtd = qtd - 1 where jogador = auth.uid() and item = p_item;
    return jsonb_build_object('eventos', ev, 'rare', true);
  end if;
  cura := case p_item when 'potion' then 20 when 'super-potion' then 50 when 'hyper-potion' then 200 when 'max-potion' then 99999
                      when 'full-restore' then 99999 when 'revive' then -1 when 'max-revive' then -2 else null end;
  if cura is null then
    if p_item in ('antidote','burn-heal','ice-heal','awakening','paralyze-heal','full-heal') then
      raise exception 'Condições (veneno, queimadura, sono…) só existem durante a batalha. Use este item pelo menu da batalha.';
    end if;
    raise exception 'Este item não tem efeito fora de batalha ainda.';
  end if;
  if cura < 0 then
    if pk.hp_atual > 0 then raise exception '% não está desmaiado.', nome_pk; end if;
    novo := case when cura = -1 then greatest(1, pk.hp_max / 2) else pk.hp_max end;
  else
    if pk.hp_atual <= 0 then raise exception '% está desmaiado: use uma Revive.', nome_pk; end if;
    if pk.hp_atual >= pk.hp_max then raise exception 'O HP de % já está cheio.', nome_pk; end if;
    novo := least(pk.hp_max, pk.hp_atual + cura);
  end if;
  update public.pokemons set hp_atual = novo where id = pk.id;
  update public.inventario set qtd = qtd - 1 where jogador = auth.uid() and item = p_item;
  return jsonb_build_object('hp', novo, 'hp_max', pk.hp_max, 'curou', novo - pk.hp_atual);
end $$;
revoke all on function public.usar_item_fora(text, uuid) from public, anon;
grant execute on function public.usar_item_fora(text, uuid) to authenticated;
