-- m43: o Mestre fica fora do ranking e dos prêmios; recálculo retroativo do período ativo a partir das batalhas.

create or replace function public._ranking_pontuar(p_j uuid, p_grupo text, p_motivo text, p_ref text, p_base numeric) returns int
language plpgsql security definer set search_path = public as $$
declare per int; d date := public._dia_jogo(); teto int; usado int; pts int; pares jsonb; fator numeric := 1; n int;
begin
  if not public._modulo('ranking') or p_base is null or p_base <= 0 or exists (select 1 from public.jogadores where id = p_j and papel = 'mestre') then return 0; end if;
  per := public._ranking_periodo();
  if p_grupo = 'duelo' and p_ref is not null then
    pares := coalesce((select valor from public.config where chave = 'ranking_pares'), '[1]'::jsonb);
    select count(*) into n from public.ranking_eventos where jogador = p_j and dia_jogo = d and grupo = 'duelo' and ref = p_ref;
    fator := case when n < jsonb_array_length(pares) then (pares ->> n)::numeric else 0 end;
  end if;
  pts := round(p_base * fator);
  teto := (select (valor ->> p_grupo)::int from public.config where chave = 'ranking_tetos');
  if teto is not null then
    select coalesce(sum(pontos), 0) into usado from public.ranking_eventos where jogador = p_j and dia_jogo = d and grupo = p_grupo;
    pts := least(pts, greatest(teto - usado, 0));
  end if;
  if pts <= 0 then return 0; end if;
  insert into public.ranking_eventos (periodo, jogador, grupo, motivo, ref, pontos, dia_jogo) values (per, p_j, p_grupo, p_motivo, p_ref, pts, d);
  insert into public.ranking_pontos (periodo, jogador, pontos) values (per, p_j, pts)
  on conflict (periodo, jogador) do update set pontos = public.ranking_pontos.pontos + excluded.pontos;
  return pts;
end $$;

create or replace function public.ranking_tabela() returns jsonb language plpgsql security definer set search_path = public as $$
declare per public.ranking_periodos; lider int; r record; d date := public._dia_jogo(); jit numeric; novo int; linhas jsonb;
begin
  if auth.uid() is null or not public._modulo('ranking') then return jsonb_build_object('ativo', false); end if;
  select * into per from public.ranking_periodos where id = public._ranking_periodo();
  select coalesce(max(rp.pontos), 0) into lider from public.ranking_pontos rp join public.jogadores j on j.id = rp.jogador where rp.periodo = per.id and j.papel <> 'mestre';
  -- os rivais NPC orbitam o líder (com variação diária estável) e nunca diminuem
  for r in select * from public.ranking_rivais where ativo loop
    jit := ((abs(hashtext(r.id || d::text)) % 21) - 10) / 100.0;
    novo := round(lider * r.fator * (1 + jit));
    insert into public.ranking_rivais_pontos (periodo, rival, pontos) values (per.id, r.id, novo)
    on conflict (periodo, rival) do update set pontos = greatest(public.ranking_rivais_pontos.pontos, excluded.pontos);
  end loop;
  select coalesce(jsonb_agg(x order by (x ->> 'pontos')::int desc, x ->> 'nome'), '[]'::jsonb) into linhas from (
    select jsonb_build_object('nome', j.nome, 'pontos', rp.pontos, 'npc', false, 'eu', j.id = auth.uid(), 'titulo', (select c.nome from public.cosmeticos_catalogo c where c.id = j.titulo_ativo),
             'moldura', (select c.estilo from public.cosmeticos_catalogo c where c.id = j.moldura_ativa)) as x
      from public.ranking_pontos rp join public.jogadores j on j.id = rp.jogador where rp.periodo = per.id and rp.pontos > 0 and j.papel <> 'mestre'
    union all
    select jsonb_build_object('nome', rv.nome, 'pontos', rvp.pontos, 'npc', true, 'eu', false)
      from public.ranking_rivais_pontos rvp join public.ranking_rivais rv on rv.id = rvp.rival where rvp.periodo = per.id and rv.ativo and rvp.pontos > 0
  ) t;
  return jsonb_build_object('ativo', true, 'periodo', jsonb_build_object('id', per.id, 'inicio', per.inicio, 'fim', per.fim, 'dias_restantes', greatest(per.fim - d, 0)),
    'meus_pontos', coalesce((select pontos from public.ranking_pontos where periodo = per.id and jogador = auth.uid()), 0),
    'premios', coalesce((select valor from public.config where chave = 'ranking_premios'), '{}'::jsonb), 'linhas', linhas);
end $$;

create or replace function public._ranking_fechar(p_id int) returns void language plpgsql security definer set search_path = public as $$
declare pr jsonb := coalesce((select valor from public.config where chave = 'ranking_premios'), '{}'::jsonb); minimo int := coalesce((pr ->> 'minimo')::int, 0);
  r record; pos int := 0; prem jsonb;
begin
  update public.ranking_periodos set estado = 'fechado' where id = p_id and estado = 'ativo';
  if not found then return; end if;
  for r in select rp.jogador, rp.pontos from public.ranking_pontos rp join public.jogadores j on j.id = rp.jogador
            where rp.periodo = p_id and j.papel <> 'mestre' and rp.pontos >= greatest(minimo, 1) order by rp.pontos desc, rp.jogador loop
    pos := pos + 1;
    prem := case when pos <= 3 then coalesce(pr -> 'podio' -> (pos - 1), '{}'::jsonb) else coalesce(pr -> 'participacao', '{}'::jsonb) end;
    insert into public.ranking_premios_jogador (jogador, periodo, posicao, pontos, premio, avisado)
    values (r.jogador, p_id, case when pos <= 3 then pos end, r.pontos, public._conceder(r.jogador, prem), false);
  end loop;
end $$;

-- ---------- recálculo retroativo do período ativo (uma vez), sem o Mestre ----------
do $$
declare per public.ranking_periodos; cfg jsonb := coalesce((select valor from public.config where chave = 'ranking_pontos'), '{}'::jsonb);
  pares jsonb := coalesce((select valor from public.config where chave = 'ranking_pares'), '[1]'::jsonb);
  tetos jsonb := coalesce((select valor from public.config where chave = 'ranking_tetos'), '{}'::jsonb);
  b record; lid boolean; opp uuid; g_ text; m_ text; r_ text; base numeric; d date; fator numeric; n int; teto int; usado int; pts int;
begin
  select * into per from public.ranking_periodos where estado = 'ativo' order by id desc limit 1;
  if not found then return; end if;
  delete from public.ranking_eventos where periodo = per.id and ranking_eventos.grupo <> 'mestre';
  for b in select x.* from public.batalhas x join public.jogadores j on j.id = x.jogador
            where x.estado <> 'ativa' and j.papel <> 'mestre' and public._dia_jogo(x.criado_em) >= per.inicio order by x.criado_em loop
    g_ := null; m_ := null; r_ := null; base := null; opp := null;
    if b.tipo = 'selvagem' then
      if b.estado = 'captura' then g_ := 'selv'; m_ := 'captura'; base := coalesce((cfg ->> 'captura')::numeric, 2);
      elsif b.estado = 'vitoria' then g_ := 'selv'; m_ := 'selvagem'; base := coalesce((cfg ->> 'selvagem')::numeric, 1); end if;
    elsif b.tipo = 'treinador' and b.estado = 'vitoria' then
      select coalesce(t.lider, false) into lid from public.treinadores t where t.id = b.treinador;
      g_ := 'npc'; m_ := case when b.revanche then 'revanche' else 'treinador' end; r_ := b.treinador;
      base := case when coalesce(lid, false) then coalesce((cfg ->> 'lider')::numeric, 15) else coalesce((cfg ->> 'treinador')::numeric, 5) end;
    elsif b.tipo = 'duelo' and b.estado in ('vitoria', 'derrota') and not b.amistoso then
      select b2.jogador into opp from public.batalhas b2 where b2.id = b.par;
      g_ := 'duelo'; m_ := case when b.estado = 'vitoria' then 'duelo_vitoria' else 'duelo_derrota' end; r_ := opp::text;
      base := coalesce((cfg ->> case when b.estado = 'vitoria' then 'duelo_vitoria' else 'duelo_derrota' end)::numeric, 5);
    end if;
    continue when g_ is null or base is null or base <= 0;
    d := public._dia_jogo(b.criado_em); fator := 1;
    if g_ = 'duelo' and r_ is not null then
      select count(*) into n from public.ranking_eventos where jogador = b.jogador and dia_jogo = d and ranking_eventos.grupo = 'duelo' and ranking_eventos.ref = r_ and periodo = per.id;
      fator := case when n < jsonb_array_length(pares) then (pares ->> n)::numeric else 0 end;
    end if;
    pts := round(base * fator);
    teto := (tetos ->> g_)::int;
    if teto is not null then
      select coalesce(sum(pontos), 0) into usado from public.ranking_eventos where jogador = b.jogador and dia_jogo = d and ranking_eventos.grupo = g_ and periodo = per.id;
      pts := least(pts, greatest(teto - usado, 0));
    end if;
    if pts <= 0 then continue; end if;
    insert into public.ranking_eventos (periodo, jogador, grupo, motivo, ref, pontos, dia_jogo, criado_em) values (per.id, b.jogador, g_, m_, r_, pts, d, b.criado_em);
  end loop;
  delete from public.ranking_pontos where periodo = per.id;
  insert into public.ranking_pontos (periodo, jogador, pontos)
    select per.id, jogador, greatest(sum(pontos), 0) from public.ranking_eventos where periodo = per.id group by jogador;
  delete from public.ranking_pontos rp using public.jogadores j where j.id = rp.jogador and j.papel = 'mestre' and rp.periodo = per.id;
  delete from public.ranking_rivais_pontos where periodo = per.id;
end $$;
