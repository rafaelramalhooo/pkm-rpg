-- m14: líder só após os treinadores do ginásio, eventos v2, brilhante no encontro, time/seguidor e Gestão do Mestre
alter table public.jogadores add column if not exists seguidor uuid;   -- Pokémon que acompanha o treinador (sem FK de propósito: a troca de personagem copia colunas)

-- ===== eventos v2: novas regras, valor livre, fim por data/hora
alter table public.eventos drop constraint if exists eventos_tipo_check;
alter table public.eventos add constraint eventos_tipo_check check (tipo in ('xp', 'dinheiro', 'brilhante', 'encontro', 'pa_gratis', 'loja_desconto', 'pa_extra'));
drop function if exists public.criar_evento(text, numeric, int, text);
create or replace function public.criar_evento(p_tipo text, p_valor numeric, p_minutos int default null, p_mensagem text default null, p_fim timestamptz default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_j public.jogadores; v_e public.eventos; v_fim timestamptz;
begin
  if auth.uid() is null then raise exception 'Faça login primeiro.'; end if;
  select * into v_j from public.jogadores where id = auth.uid();
  if not found or v_j.papel <> 'mestre' then raise exception 'Só o Mestre cria eventos.'; end if;
  if p_tipo not in ('xp', 'dinheiro', 'brilhante', 'encontro', 'pa_gratis', 'loja_desconto', 'pa_extra') then raise exception 'Tipo de evento inválido.'; end if;
  if p_valor is null or p_valor <= 0 or p_valor > 1000 then raise exception 'Valor inválido (use um número entre 0,1 e 1000).'; end if;
  if p_tipo = 'loja_desconto' and p_valor > 90 then raise exception 'O desconto máximo é 90%%.'; end if;
  v_fim := coalesce(p_fim, now() + make_interval(mins => coalesce(p_minutos, 0)));
  if v_fim <= now() then raise exception 'O fim do evento precisa estar no futuro.'; end if;
  if v_fim > now() + interval '30 days' then raise exception 'Duração máxima: 30 dias.'; end if;
  update public.eventos set encerrado = true where tipo = p_tipo and not encerrado;
  insert into public.eventos (tipo, valor, mensagem, fim, criado_por)
  values (p_tipo, p_valor, nullif(btrim(coalesce(p_mensagem, '')), ''), v_fim, v_j.id) returning * into v_e;
  if p_tipo = 'pa_extra' then update public.jogadores set pa = least(32000, pa + floor(p_valor)::int) where conta is null; end if;
  return to_jsonb(v_e);
end $$;
grant execute on function public.criar_evento(text, numeric, int, text, timestamptz) to authenticated;


drop function if exists public._novo_pokemon(uuid,int,int,jsonb);
create or replace function public._novo_pokemon(p_dono uuid, p_esp int, p_nivel int, p_golpes jsonb default null, p_brilhante boolean default null)
returns public.pokemons language plpgsql security definer set search_path = public as $$
declare
  e public.especies; nat text; v public.pokemons;
  ih int := floor(random()*32); ia int := floor(random()*32); id_ int := floor(random()*32);
  isa int := floor(random()*32); isd int := floor(random()*32); ise int := floor(random()*32);
  slot int;
  br boolean := coalesce(p_brilhante, random() < least(1, coalesce((select (valor #>> '{}')::numeric from public.config where chave = 'chance_brilhante'), 0.004) * public._ev('brilhante', 1)));
begin
  select * into e from public.especies where id = p_esp;
  if not found then raise exception 'Espécie desconhecida.'; end if;
  select nome into nat from public.naturezas order by random() limit 1;
  nat := coalesce(nat, 'hardy');
  select min(s) into slot from generate_series(1,6) s where not exists (select 1 from public.pokemons where dono = p_dono and posicao = s);
  insert into public.pokemons (dono, especie_id, nivel, exp, natureza, iv_hp, iv_atk, iv_def, iv_spa, iv_spd, iv_spe,
      hp_max, atk, def, spa, spd, spe, hp_atual, golpes, posicao, brilhante)
  values (p_dono, p_esp, p_nivel, public.exp_para(p_nivel), nat, ih, ia, id_, isa, isd, ise,
      public.calc_hp(e.hp, ih, p_nivel),
      public.calc_stat(e.atk, ia, p_nivel, public.mult_nat(nat, 'attack')),
      public.calc_stat(e.def, id_, p_nivel, public.mult_nat(nat, 'defense')),
      public.calc_stat(e.spa, isa, p_nivel, public.mult_nat(nat, 'sp_attack')),
      public.calc_stat(e.spd, isd, p_nivel, public.mult_nat(nat, 'sp_defense')),
      public.calc_stat(e.spe, ise, p_nivel, public.mult_nat(nat, 'speed')),
      public.calc_hp(e.hp, ih, p_nivel),
      coalesce(p_golpes, public.golpes_do_nivel(p_esp, p_nivel)), slot, br)
  returning * into v;
  insert into public.pokedex (jogador, especie_id, capturado) values (p_dono, p_esp, true)
  on conflict (jogador, especie_id) do update set capturado = true;
  return v;
end $$;
revoke all on function public._novo_pokemon(uuid,int,int,jsonb,boolean) from public, anon, authenticated;

create or replace function public.desafiar_treinador(p_treinador text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_j public.jogadores; v_t public.treinadores; v_b public.batalhas; v_ativo uuid; v_falta int;
  begin
  if auth.uid() is null then raise exception 'Faça login primeiro.'; end if;
  select * into v_j from public.jogadores where id = auth.uid() for update;
  if not found then raise exception 'Crie seu personagem primeiro.'; end if;
  select * into v_b from public.batalhas where jogador = v_j.id and estado = 'ativa';
  if found then return jsonb_build_object('batalha', to_jsonb(v_b) - 'sim' - 'meta'); end if;
  select * into v_t from public.treinadores where id = p_treinador and mapa_id = v_j.mapa_id;
  if not found then raise exception 'Não há esse treinador por aqui.'; end if;
  if exists (select 1 from public.treinadores_vencidos where jogador = v_j.id and treinador = v_t.id) then
    raise exception 'Você já derrotou % .', v_t.nome;
  end if;
  -- líder (ginásio/Liga): antes é preciso vencer todos os outros treinadores do mesmo local
  if v_t.lider then
    select count(*) into v_falta from public.treinadores o
     where o.mapa_id = v_t.mapa_id and o.id <> v_t.id and not o.lider
       and not exists (select 1 from public.treinadores_vencidos tv where tv.jogador = v_j.id and tv.treinador = o.id);
    if v_falta > 0 then
      raise exception '% só aceita o desafio de quem venceu antes todos os treinadores do ginásio (faltam %).', v_t.nome, v_falta;
    end if;
  end if;
  -- o treinador só desafia quando o jogador puxa conversa: precisa estar num tile ao lado dele
  if abs(v_t.x - v_j.x) + abs(v_t.y - v_j.y) <> 1 then raise exception 'Chegue ao lado de % para conversar.', v_t.nome; end if;
  select id into v_ativo from public.pokemons where dono = v_j.id and posicao is not null and hp_atual > 0 order by posicao limit 1;
  if v_ativo is null then
    if exists (select 1 from public.pokemons where dono = v_j.id) then raise exception 'Seus Pokémon estão desmaiados. Cure-os no Centro Pokémon ou em casa.';
    else raise exception 'Você ainda não tem Pokémon. Fale com o Professor Carvalho no laboratório.'; end if;
  end if;
  insert into public.batalhas (jogador, selvagem, ativo, tipo, treinador, adversarios)
  values (v_j.id, '{}'::jsonb, v_ativo, 'treinador', v_t.id, case when v_t.escala is not null then public._equipe_escalada(v_t, public._nivel_ref(v_j.id)) else public._equipe_treinador(v_t.equipe) end) returning * into v_b;
  return jsonb_build_object('batalha', to_jsonb(v_b) - 'sim' - 'meta', 'treinador', jsonb_build_object('nome', v_t.nome, 'classe', v_t.classe));
end $$;
grant execute on function public.desafiar_treinador(text) to authenticated;

create or replace function public.comprar_item(p_poi text, p_item text, p_qtd int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_j public.jogadores; v_p jsonb; v_e jsonb; v_total int;
begin
  if auth.uid() is null then raise exception 'Faça login primeiro.'; end if;
  if p_qtd is null or p_qtd < 1 or p_qtd > 99 then raise exception 'Quantidade inválida.'; end if;
  select * into v_j from public.jogadores where id = auth.uid() for update;
  if not found then raise exception 'Crie seu personagem primeiro.'; end if;
  v_p := public._poi_do_jogador(v_j, p_poi);
  if v_p is null or v_p->>'acao' <> 'loja' then raise exception 'Chegue ao balcão da loja.'; end if;
  select e into v_e from jsonb_array_elements(v_p->'estoque') e where e->>'item' = p_item limit 1;
  if v_e is null then raise exception 'Esta loja não vende isso.'; end if;
  v_total := floor((v_e->>'preco')::int * p_qtd * (1 - least(90, public._ev('loja_desconto', 0)) / 100.0));
  if v_j.dinheiro < v_total then raise exception 'Dinheiro insuficiente (precisa de %).', v_total; end if;
  update public.jogadores set dinheiro = dinheiro - v_total where id = v_j.id;
  insert into public.inventario (jogador, item, qtd) values (v_j.id, p_item, p_qtd)
  on conflict (jogador, item) do update set qtd = public.inventario.qtd + p_qtd;
  return jsonb_build_object('item', p_item, 'qtd', p_qtd, 'total', v_total, 'dinheiro', v_j.dinheiro - v_total);
end $$;
grant execute on function public.comprar_item(text, text, int) to authenticated;

create or replace function public.procurar_pokemon()
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_j public.jogadores; v_b public.batalhas; v_o public.ofertas; v_ativo uuid; v_sel jsonb;
begin
  if auth.uid() is null then raise exception 'Faça login primeiro.'; end if;
  select * into v_j from public.jogadores where id = auth.uid() for update;
  if not found then raise exception 'Crie seu personagem primeiro.'; end if;
  select * into v_b from public.batalhas where jogador = v_j.id and estado = 'ativa';
  if found then return public._resultado(v_b.id, jsonb_build_array(jsonb_build_object('t', 'retomada'))); end if;
  select * into v_o from public.ofertas where jogador = v_j.id and mapa_id = v_j.mapa_id and x = v_j.x and y = v_j.y;
  if not found then raise exception 'Não há Pokémon à vista aqui. Ande um pouco e pare de novo.'; end if;
  select id into v_ativo from public.pokemons where dono = v_j.id and posicao is not null and hp_atual > 0 order by posicao limit 1;
  if v_ativo is null then
    if exists (select 1 from public.pokemons where dono = v_j.id) then raise exception 'Seus Pokémon estão desmaiados. Cure-os em casa ou no Centro Pokémon.';
    else raise exception 'Você ainda não tem Pokémon. Fale com o Professor Carvalho no laboratório.'; end if;
  end if;
  if v_j.pa < 1 and public._ev('pa_gratis', 0) = 0 then raise exception 'PA insuficiente: buscar Pokémon custa 1 PA.'; end if;
  v_sel := public._selvagem(v_o.especie_id, v_o.nivel);
  v_sel := v_sel || jsonb_build_object('brilhante', random() < least(1, coalesce((select (valor #>> '{}')::numeric from public.config where chave = 'chance_brilhante'), 0.004) * public._ev('brilhante', 1)));
  delete from public.ofertas where jogador = v_j.id;
  update public.jogadores set pa = pa - case when public._ev('pa_gratis', 0) > 0 then 0 else 1 end where id = v_j.id;
  insert into public.batalhas (jogador, selvagem, ativo) values (v_j.id, v_sel, v_ativo) returning * into v_b;
  insert into public.pokedex (jogador, especie_id) values (v_j.id, v_o.especie_id) on conflict do nothing;
  return public._resultado(v_b.id, jsonb_build_array(jsonb_build_object('t', 'apareceu', 'nome', v_sel->>'nome', 'nivel', v_o.nivel)));
end $$;
grant execute on function public.procurar_pokemon() to authenticated;

create or replace function public.sim_capturar(p_batalha uuid, p_turno int, p_sim jsonb, p_meta jsonb, p_log_len int, p_time jsonb, p_especie int, p_nivel int, p_golpes jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare b public.batalhas; novo public.pokemons; esp public.especies;
begin
  perform public.sim_gravar(p_batalha, p_turno, p_sim, p_meta, p_log_len, p_time, null);
  select * into b from public.batalhas where id = p_batalha;
  select * into esp from public.especies where id = p_especie;
  novo := public._novo_pokemon(b.jogador, p_especie, p_nivel, p_golpes, (b.selvagem->>'brilhante')::boolean);
  update public.batalhas set estado = 'captura' where id = b.id;
  return jsonb_build_object('nome', esp.nome, 'time', novo.posicao is not null);
end $$;
revoke all on function public.sim_capturar(uuid,int,jsonb,jsonb,int,jsonb,int,int,jsonb) from public, anon, authenticated;
grant execute on function public.sim_capturar(uuid,int,jsonb,jsonb,int,jsonb,int,int,jsonb) to service_role;

-- ===== time e seguidor
create or replace function public.organizar_time(p_ordem uuid[]) returns void
language plpgsql security definer set search_path = public as $$
declare v_id uuid; i int := 0;
begin
  if auth.uid() is null then raise exception 'Faça login primeiro.'; end if;
  if p_ordem is null or array_length(p_ordem, 1) is null or array_length(p_ordem, 1) > 6 then raise exception 'O time tem de 1 a 6 Pokémon.'; end if;
  if (select count(distinct x) from unnest(p_ordem) x) <> array_length(p_ordem, 1) then raise exception 'Pokémon repetido.'; end if;
  if (select count(*) from public.pokemons where dono = auth.uid() and id = any(p_ordem)) <> array_length(p_ordem, 1) then raise exception 'Pokémon inválido.'; end if;
  if exists (select 1 from public.batalhas where jogador = auth.uid() and estado = 'ativa') then raise exception 'Termine a batalha primeiro.'; end if;
  update public.pokemons set posicao = null where dono = auth.uid();
  foreach v_id in array p_ordem loop
    i := i + 1;
    update public.pokemons set posicao = i where id = v_id;
  end loop;
end $$;
grant execute on function public.organizar_time(uuid[]) to authenticated;

create or replace function public.definir_seguidor(p_pokemon uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Faça login primeiro.'; end if;
  if p_pokemon is not null and not exists (select 1 from public.pokemons where id = p_pokemon and dono = auth.uid()) then raise exception 'Pokémon inválido.'; end if;
  update public.jogadores set seguidor = p_pokemon where id = auth.uid();
end $$;
grant execute on function public.definir_seguidor(uuid) to authenticated;

create or replace function public.meu_seguidor() returns jsonb
language sql stable security definer set search_path = public as $$
  select to_jsonb(r) from (select p.id, p.especie_id, p.brilhante, p.apelido from public.jogadores j join public.pokemons p on p.id = j.seguidor and p.dono = j.id where j.id = auth.uid()) r $$;
grant execute on function public.meu_seguidor() to authenticated;

-- ===== Gestão do Mestre
create or replace function public._recalcular_pokemon(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare pk public.pokemons; e public.especies; novo_hp int;
begin
  select * into pk from public.pokemons where id = p_id;
  select * into e from public.especies where id = pk.especie_id;
  novo_hp := public.calc_hp(e.hp, pk.iv_hp, pk.nivel);
  update public.pokemons set hp_max = novo_hp, hp_atual = least(hp_atual, novo_hp),
    atk = public.calc_stat(e.atk, pk.iv_atk, pk.nivel, public.mult_nat(pk.natureza, 'attack')),
    def = public.calc_stat(e.def, pk.iv_def, pk.nivel, public.mult_nat(pk.natureza, 'defense')),
    spa = public.calc_stat(e.spa, pk.iv_spa, pk.nivel, public.mult_nat(pk.natureza, 'sp_attack')),
    spd = public.calc_stat(e.spd, pk.iv_spd, pk.nivel, public.mult_nat(pk.natureza, 'sp_defense')),
    spe = public.calc_stat(e.spe, pk.iv_spe, pk.nivel, public.mult_nat(pk.natureza, 'speed')),
    exp = greatest(exp, public.exp_para(pk.nivel))
  where id = p_id;
end $$;
revoke all on function public._recalcular_pokemon(uuid) from public, anon, authenticated;

create or replace function public.mestre_jogadores() returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public.eh_mestre() then raise exception 'Só o Mestre.'; end if;
  return coalesce((select jsonb_agg(to_jsonb(r) order by r.nome) from (
    select j.id, j.nome, j.papel, j.pa, j.dinheiro, j.mapa_id, j.insignias, j.campeao, u.email,
           (select count(*) from public.pokemons p where p.dono = j.id) as pokemons,
           (select coalesce(max(p.nivel), 0) from public.pokemons p where p.dono = j.id) as maior_nivel
      from public.jogadores j left join auth.users u on u.id = coalesce(j.conta, j.id)
     where j.conta is null) r), '[]'::jsonb);
end $$;
grant execute on function public.mestre_jogadores() to authenticated;

create or replace function public.mestre_ficha(p_id uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v jsonb;
begin
  if not public.eh_mestre() then raise exception 'Só o Mestre.'; end if;
  select jsonb_build_object(
    'jogador', (select to_jsonb(j) - 'rolagem' - 'rolagem_em' from public.jogadores j where j.id = p_id),
    'email', (select u.email from auth.users u where u.id = p_id),
    'pokemons', coalesce((select jsonb_agg(to_jsonb(p) order by p.posicao nulls last, p.criado_em) from public.pokemons p where p.dono = p_id), '[]'::jsonb),
    'itens', coalesce((select jsonb_agg(jsonb_build_object('item', i.item, 'qtd', i.qtd) order by i.item) from public.inventario i where i.jogador = p_id and i.qtd > 0), '[]'::jsonb),
    'treinadores', (select count(*) from public.treinadores_vencidos where jogador = p_id),
    'pokedex', (select count(*) from public.pokedex where jogador = p_id and capturado)
  ) into v;
  return v;
end $$;
grant execute on function public.mestre_ficha(uuid) to authenticated;

create or replace function public.mestre_editar_jogador(p_id uuid, p_campos jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare v_mapa text;
begin
  if not public.eh_mestre() then raise exception 'Só o Mestre.'; end if;
  if not exists (select 1 from public.jogadores where id = p_id) then raise exception 'Jogador não encontrado.'; end if;
  if p_campos ? 'nome' and length(btrim(p_campos->>'nome')) between 2 and 24 then update public.jogadores set nome = btrim(p_campos->>'nome') where id = p_id; end if;
  if p_campos ? 'pa' then update public.jogadores set pa = greatest(0, least(32000, (p_campos->>'pa')::int)) where id = p_id; end if;
  if p_campos ? 'dinheiro' then update public.jogadores set dinheiro = greatest(0, least(99999999, (p_campos->>'dinheiro')::int)) where id = p_id; end if;
  if p_campos ? 'papel' and p_campos->>'papel' in ('jogador', 'mestre') then update public.jogadores set papel = p_campos->>'papel' where id = p_id; end if;
  if p_campos ? 'campeao' then update public.jogadores set campeao = (p_campos->>'campeao')::boolean where id = p_id; end if;
  if p_campos ? 'insignias' then update public.jogadores set insignias = coalesce((select array_agg(distinct x) from jsonb_array_elements_text(p_campos->'insignias') x), '{}') where id = p_id; end if;
  if p_campos ? 'mapa_id' then
    v_mapa := p_campos->>'mapa_id';
    if not exists (select 1 from public.mapas where id = v_mapa) then raise exception 'Mapa inexistente.'; end if;
    update public.jogadores set mapa_id = v_mapa, x = coalesce((p_campos->>'x')::int, x), y = coalesce((p_campos->>'y')::int, y) where id = p_id;
    delete from public.ofertas where jogador = p_id;
  end if;
  insert into public.auditoria (ator, acao, detalhe) values (auth.uid(), 'mestre_editar_jogador', jsonb_build_object('jogador', p_id, 'campos', p_campos));
end $$;
grant execute on function public.mestre_editar_jogador(uuid, jsonb) to authenticated;

create or replace function public.mestre_editar_pokemon(p_id uuid, p_campos jsonb) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.eh_mestre() then raise exception 'Só o Mestre.'; end if;
  if not exists (select 1 from public.pokemons where id = p_id) then raise exception 'Pokémon não encontrado.'; end if;
  if p_campos ? 'apelido' then update public.pokemons set apelido = nullif(btrim(p_campos->>'apelido'), '') where id = p_id; end if;
  if p_campos ? 'brilhante' then update public.pokemons set brilhante = (p_campos->>'brilhante')::boolean where id = p_id; end if;
  if p_campos ? 'nivel' then
    update public.pokemons set nivel = greatest(1, least(100, (p_campos->>'nivel')::int)), exp = public.exp_para(greatest(1, least(100, (p_campos->>'nivel')::int))) where id = p_id;
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
  v := public._novo_pokemon(p_jogador, p_especie, greatest(1, least(100, p_nivel)), null, coalesce(p_brilhante, false));
  insert into public.auditoria (ator, acao, detalhe) values (auth.uid(), 'mestre_dar_pokemon', jsonb_build_object('jogador', p_jogador, 'especie', p_especie, 'nivel', p_nivel));
  return v.id;
end $$;
grant execute on function public.mestre_dar_pokemon(uuid, int, int, boolean) to authenticated;

create or replace function public.mestre_remover_pokemon(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.eh_mestre() then raise exception 'Só o Mestre.'; end if;
  delete from public.pokemons where id = p_id;
  insert into public.auditoria (ator, acao, detalhe) values (auth.uid(), 'mestre_remover_pokemon', jsonb_build_object('pokemon', p_id));
end $$;
grant execute on function public.mestre_remover_pokemon(uuid) to authenticated;

create or replace function public.mestre_definir_item(p_jogador uuid, p_item text, p_qtd int) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.eh_mestre() then raise exception 'Só o Mestre.'; end if;
  if not exists (select 1 from public.itens where slug = p_item) then raise exception 'Item inexistente.'; end if;
  insert into public.inventario (jogador, item, qtd) values (p_jogador, p_item, greatest(0, least(999, p_qtd)))
  on conflict (jogador, item) do update set qtd = greatest(0, least(999, p_qtd));
  insert into public.auditoria (ator, acao, detalhe) values (auth.uid(), 'mestre_definir_item', jsonb_build_object('jogador', p_jogador, 'item', p_item, 'qtd', p_qtd));
end $$;
grant execute on function public.mestre_definir_item(uuid, text, int) to authenticated;
