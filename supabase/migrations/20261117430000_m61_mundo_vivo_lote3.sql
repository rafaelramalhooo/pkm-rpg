-- m61: Mundo vivo — Lote 3: Treinador de trocas (Pokémon), Criador de ovos, Arqueólogo e Cozinheiro de viagem.
-- (Veterano, Rival errante e Figura encapuzada já nascem na m59, pois usam o motor de batalha dos treinadores.)
-- Requer m59 e m60. Aditiva e idempotente.

-- ---------- Troca de Pokémon: entrega a espécie pedida (nível mínimo) e recebe outra, no mesmo nível ----------
create or replace function public._mv_h_troca(p_j uuid, p_n public.mv_npcs, p_acao text, p_arg jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_quer int := (p_n.dados ->> 'quer')::int; v_da int := (p_n.dados ->> 'da')::int; v_min int := coalesce((p_n.dados ->> 'nivel_min')::int, 5);
  v_pk public.pokemons; v_novo public.pokemons; v_nq text; v_nd text; ops jsonb := '[]'::jsonb; usada boolean := public._mv_uso(p_j, 'troca:' || p_n.id) > 0;
begin
  select nome into v_nq from public.especies where id = v_quer;
  select nome into v_nd from public.especies where id = v_da;
  if p_acao like 'trocar:%' then
    if usada then raise exception 'Você já fez esta troca.'; end if;
    select * into v_pk from public.pokemons where id = substr(p_acao, 8)::uuid and dono = p_j and especie_id = v_quer and nivel >= v_min;
    if not found then raise exception 'Esse Pokémon não serve para a troca.'; end if;
    perform public._gastar_pa(p_j);
    delete from public.pokemons where id = v_pk.id;
    v_novo := public._novo_pokemon(p_j, v_da, v_pk.nivel);
    insert into public.pokedex (jogador, especie_id, capturado) values (p_j, v_da, true) on conflict (jogador, especie_id) do update set capturado = true;
    perform public._mv_uso_somar(p_j, 'troca:' || p_n.id);
    return jsonb_build_object('texto', format('Troca feita! Cuide bem de %s.', v_nd), 'mensagem', format('Você trocou %s por %s (nível %s).', v_nq, v_nd, v_pk.nivel), 'opcoes', '[]'::jsonb);
  end if;
  if not usada then
    select coalesce(jsonb_agg(jsonb_build_object('id', 'trocar:' || p.id, 'rotulo', format('Trocar %s (nível %s) por %s', coalesce(p.apelido, v_nq), p.nivel, v_nd), 'custo_pa', 1) order by p.nivel desc), '[]'::jsonb)
      into ops from public.pokemons p where p.dono = p_j and p.especie_id = v_quer and p.nivel >= v_min;
  end if;
  return jsonb_build_object('texto', format('Procuro um %s (a partir do nível %s). Troco por um %s, no mesmo nível!', v_nq, v_min, v_nd),
    'mensagem', case when usada then 'Você já fez a troca com esta pessoa.' when jsonb_array_length(ops) = 0 then format('Você não tem um %s no nível pedido.', v_nq) end,
    'opcoes', ops);
end $$;

-- ---------- Criador de ovos ----------
create or replace function public._mv_h_ovos(p_j uuid, p_n public.mv_npcs, p_acao text, p_arg jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_esp int := (p_n.dados ->> 'especie')::int; v_preco int := (p_n.dados ->> 'preco')::int; v_passos int := (p_n.dados ->> 'passos')::int; usada boolean := public._mv_uso(p_j, 'ovo:' || p_n.id) > 0;
begin
  if p_acao = 'comprar' then
    if usada then raise exception 'Você já levou o ovo desta pessoa.'; end if;
    perform public._gastar_pa(p_j);
    update public.jogadores set dinheiro = dinheiro - v_preco where id = p_j and dinheiro >= v_preco;
    if not found then raise exception 'Dinheiro insuficiente (₽ %).', v_preco; end if;
    perform public._conceder(p_j, jsonb_build_object('ovo', jsonb_build_object('especie', v_esp, 'passos', v_passos)));
    perform public._mv_uso_somar(p_j, 'ovo:' || p_n.id);
    return jsonb_build_object('texto', 'Ele está quentinho. Leve para a sua casa e incube andando bastante!', 'mensagem', 'Você recebeu um ovo misterioso.', 'opcoes', '[]'::jsonb);
  end if;
  return jsonb_build_object('texto', public._mv_fala('ovos'),
    'opcoes', case when usada then '[]'::jsonb else jsonb_build_array(jsonb_build_object('id', 'comprar', 'rotulo', format('Levar o ovo por ₽ %s', v_preco), 'custo_pa', 1, 'detalhe', 'Não dá para saber qual Pokémon vai nascer. Incube na sua casa.')) end);
end $$;

-- ---------- Arqueólogo ----------
create or replace function public._mv_h_arqueologo(p_j uuid, p_n public.mv_npcs, p_acao text, p_arg jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_cfg jsonb := (select a.cfg from public.mv_arquetipos a where a.id = 'arqueologo'); v_pr jsonb; usada boolean := public._mv_uso(p_j, 'arq:' || p_n.id) > 0;
begin
  if p_acao = 'cavar' then
    if usada then raise exception 'Você já escavou aqui.'; end if;
    perform public._gastar_pa(p_j);
    select x into v_pr from jsonb_array_elements(v_cfg -> 'premios') with ordinality as t(x, i)
     order by power(random(), 1.0 / greatest(coalesce((v_cfg -> 'pesos' ->> (i::int - 1))::numeric, 1), 1)) desc limit 1;
    perform public._conceder(p_j, v_pr);
    perform public._mv_uso_somar(p_j, 'arq:' || p_n.id);
    return jsonb_build_object('texto', 'Olha só o que apareceu debaixo da terra!', 'premio', v_pr, 'opcoes', '[]'::jsonb);
  end if;
  return jsonb_build_object('texto', public._mv_fala('arqueologo'),
    'opcoes', case when usada then '[]'::jsonb else jsonb_build_array(jsonb_build_object('id', 'cavar', 'rotulo', 'Ajudar a escavar', 'custo_pa', 1)) end);
end $$;

-- ---------- Cozinheiro de viagem: refeição que aumenta a amizade do time ----------
create or replace function public._mv_h_cozinheiro(p_j uuid, p_n public.mv_npcs, p_acao text, p_arg jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_cfg jsonb := (select a.cfg from public.mv_arquetipos a where a.id = 'cozinheiro'); v_preco int := coalesce((v_cfg ->> 'preco')::int, 150); v_am int := coalesce((v_cfg ->> 'amizade')::int, 5);
  usada boolean := public._mv_uso(p_j, 'coz:' || p_n.id) > 0;
begin
  if p_acao = 'cozinhar' then
    if usada then raise exception 'Seus Pokémon já comeram aqui.'; end if;
    perform public._gastar_pa(p_j);
    update public.jogadores set dinheiro = dinheiro - v_preco where id = p_j and dinheiro >= v_preco;
    if not found then raise exception 'Dinheiro insuficiente (₽ %).', v_preco; end if;
    update public.pokemons set amizade = least(255, amizade + v_am) where dono = p_j and posicao is not null;
    perform public._mv_uso_somar(p_j, 'coz:' || p_n.id);
    return jsonb_build_object('texto', 'Ah, que alegria ver todo mundo comendo bem!', 'mensagem', format('Todo o seu time ganhou +%s de amizade.', v_am), 'opcoes', '[]'::jsonb);
  end if;
  return jsonb_build_object('texto', public._mv_fala('cozinheiro'),
    'opcoes', case when usada then '[]'::jsonb else jsonb_build_array(jsonb_build_object('id', 'cozinhar', 'rotulo', format('Servir uma refeição ao time (₽ %s)', v_preco), 'custo_pa', 1, 'detalhe', format('+%s de amizade para cada Pokémon do time.', v_am))) end);
end $$;

do $$ declare f text; begin
  foreach f in array array['_mv_h_troca', '_mv_h_ovos', '_mv_h_arqueologo', '_mv_h_cozinheiro'] loop
    execute format('revoke all on function public.%I(uuid, public.mv_npcs, text, jsonb) from public, anon, authenticated', f);
  end loop;
end $$;
