-- m44: período ativo passa a valer desde 12/11 (primeiras batalhas do jogo) e o ranking é recalculado de novo (Mestre fora).
update public.ranking_periodos set inicio = date '2026-11-12' where estado = 'ativo' and inicio > date '2026-11-12';

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
