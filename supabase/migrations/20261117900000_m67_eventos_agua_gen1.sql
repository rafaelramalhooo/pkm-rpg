-- m67: eventos novos do Mestre, beira d'água, vara melhor e Pokémon da Geração 1 que faltavam.
-- ===== eventos: coluna alvo (tipo, clima, mapa, item) e novos tipos
alter table public.eventos add column if not exists alvo text;
alter table public.eventos drop constraint if exists eventos_tipo_check;
alter table public.eventos drop constraint if exists eventos_valor_check;
alter table public.eventos add constraint eventos_valor_check check (valor > 0 and valor <= 100000);

create or replace function public._ev_alvo(p_tipo text) returns text language sql stable security definer set search_path = public as $$
  select (select alvo from public.eventos where tipo = p_tipo and not encerrado and now() >= inicio and now() < fim order by criado_em desc, id limit 1) $$;

create or replace function public.eventos_ativos() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'tipo', tipo, 'valor', valor, 'alvo', alvo, 'mensagem', mensagem, 'inicio', inicio, 'fim', fim) order by fim), '[]'::jsonb)
    from public.eventos where not encerrado and now() >= inicio and now() < fim $$;

drop function if exists public.criar_evento(text, numeric, int, text, timestamptz, timestamptz);
create or replace function public.criar_evento(p_tipo text, p_valor numeric, p_minutos int default null, p_mensagem text default null, p_fim timestamptz default null, p_inicio timestamptz default null, p_alvo text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_j public.jogadores; v_e public.eventos; v_ini timestamptz; v_fim timestamptz; v_alvo text := nullif(btrim(coalesce(p_alvo, '')), '');
begin
  if auth.uid() is null then raise exception 'Faça login primeiro.'; end if;
  select * into v_j from public.jogadores where id = auth.uid();
  if not found or v_j.papel <> 'mestre' then raise exception 'Só o Mestre cria eventos.'; end if;
  if p_tipo not in ('xp', 'dinheiro', 'brilhante', 'encontro', 'pa_gratis', 'loja_desconto', 'pa_extra', 'captura', 'pesca', 'tipo_destaque', 'presente', 'clima', 'duelo_dobro', 'torneio', 'mapa_destaque', 'xp_treino') then raise exception 'Tipo de evento inválido.'; end if;
  if p_valor is null or p_valor <= 0 or p_valor > (case when p_tipo = 'presente' then 50000 else 1000 end) then raise exception 'Valor inválido.'; end if;
  if p_tipo = 'loja_desconto' and p_valor > 90 then raise exception 'O desconto máximo é 90%%.'; end if;
  if p_tipo = 'tipo_destaque' and (v_alvo is null or v_alvo not in ('normal','fire','water','electric','grass','ice','fighting','poison','ground','flying','psychic','bug','rock','ghost','dragon','dark','steel','fairy')) then raise exception 'Escolha um tipo de Pokémon.'; end if;
  if p_tipo = 'clima' and (v_alvo is null or v_alvo not in ('rain','sun','sand','snow')) then raise exception 'Escolha o clima (chuva, sol, areia ou neve).'; end if;
  if p_tipo = 'mapa_destaque' and not exists (select 1 from public.mapas where id = v_alvo) then raise exception 'Escolha um mapa válido.'; end if;
  if p_tipo = 'presente' and (v_alvo is null or (v_alvo <> 'dinheiro' and not exists (select 1 from public.itens where slug = v_alvo))) then raise exception 'Escolha o presente: dinheiro ou um item.'; end if;
  v_ini := case when p_inicio is null or p_inicio < now() + interval '1 minute' then now() else p_inicio end;
  if v_ini > now() + interval '90 days' then raise exception 'O início pode ser no máximo daqui a 90 dias.'; end if;
  if p_tipo in ('pa_extra', 'presente') and v_ini > now() then raise exception 'Este evento é entregue na hora: não pode ser agendado.'; end if;
  v_fim := coalesce(p_fim, v_ini + make_interval(mins => coalesce(p_minutos, case when p_tipo in ('pa_extra', 'presente') then 10 else 0 end)));
  if v_fim <= v_ini then raise exception 'O fim do evento precisa ser depois do início.'; end if;
  if v_fim > v_ini + interval '30 days' then raise exception 'Duração máxima: 30 dias.'; end if;
  insert into public.eventos (tipo, valor, alvo, mensagem, inicio, fim, criado_por)
  values (p_tipo, p_valor, v_alvo, nullif(btrim(coalesce(p_mensagem, '')), ''), v_ini, v_fim, v_j.id) returning * into v_e;
  if p_tipo = 'pa_extra' then update public.jogadores set pa = least(32000, pa + floor(p_valor)::int + public._pa_bonus(id)) where conta is null; end if;
  if p_tipo = 'presente' then
    if v_alvo = 'dinheiro' then update public.jogadores set dinheiro = dinheiro + floor(p_valor)::int where conta is null;
    else insert into public.inventario (jogador, item, qtd) select id, v_alvo, floor(p_valor)::int from public.jogadores where conta is null
         on conflict (jogador, item) do update set qtd = public.inventario.qtd + excluded.qtd; end if;
  end if;
  return to_jsonb(v_e);
end $$;
grant execute on function public.criar_evento(text, numeric, int, text, timestamptz, timestamptz, text) to authenticated;

-- dados do evento para a Edge Function da batalha (captura e clima)
create or replace function public.evento_batalha() returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object('captura', public._ev('captura', 1), 'clima', public._ev_alvo('clima')) $$;
revoke all on function public.evento_batalha() from public, anon, authenticated;
grant execute on function public.evento_batalha() to service_role;

-- ===== beira d'água
create or replace function public._beira(p_m public.mapas, p_x int, p_y int) returns boolean language sql immutable as $$
  select p_m.bioma is not null and exists (select 1 from (values (1, 0), (-1, 0), (0, 1), (0, -1)) d(dx, dy)
    where p_x + dx >= 0 and p_x + dx < p_m.largura and p_y + dy >= 0 and substr(p_m.bioma, (p_y + dy) * p_m.largura + p_x + dx + 1, 1) = 'A') $$;
insert into public.config (chave, valor) values ('chance_beira', '50'::jsonb) on conflict (chave) do nothing;

create or replace function public._pt(d text, a text, b text) returns text language plpgsql as $$
begin
  if position(a in d) = 0 then raise exception 'Trecho não encontrado: %', left(a, 60); end if;
  return replace(d, a, b);
end $$;

do $$
declare d text;
begin
  -- gerar_oferta: beira d'água, mapa em destaque, tipo em destaque / clima
  select pg_get_functiondef('public.gerar_oferta()'::regprocedure) into d;
  d := public._pt(d, 'v_chance int;', 'v_chance int; v_tipo text; v_e2 record;');
  d := public._pt(d, 'if v_bioma is null then return null; end if;', 'if v_bioma is null then return null; end if;
  if v_bioma <> ''agua'' and public._beira(v_m, v_j.x, v_j.y) and random() * 100 < coalesce((select (valor #>> ''{}'')::numeric from public.config where chave = ''chance_beira''), 50) then v_bioma := ''agua''; end if;');
  d := public._pt(d, 'round(v_chance * public._ev(''encontro'', 1))', 'round(v_chance * public._ev(''encontro'', 1) * case when v_j.mapa_id = public._ev_alvo(''mapa_destaque'') then public._ev(''mapa_destaque'', 1) else 1 end)');
  d := public._pt(d, 'if v_nivel > public._nivel_ref(v_j.id) + 8 then return null; end if;', 'v_tipo := public._ev_alvo(''tipo_destaque'');
  if v_tipo is null then v_tipo := case public._ev_alvo(''clima'') when ''rain'' then ''water'' when ''sun'' then ''fire'' when ''sand'' then ''rock'' when ''snow'' then ''ice'' else null end; end if;
  if v_tipo is not null and not exists (select 1 from public.especies where id = v_e.especie_id and v_tipo = any(tipos))
     and random() < least(0.85, 1 - 1 / greatest(1.0001, case when public._ev_alvo(''tipo_destaque'') is not null then public._ev(''tipo_destaque'', 2) else 2 end)) then
    select e2.especie_id, e2.nivel_min, e2.nivel_max into v_e2 from public.encontros e2 join public.especies s on s.id = e2.especie_id
     where e2.mapa_id = v_j.mapa_id and e2.bioma = v_bioma and v_tipo = any(s.tipos) order by -ln(random()) / e2.peso limit 1;
    if v_e2.especie_id is not null then v_e := v_e2; v_nivel := greatest(v_e2.nivel_min, least(v_e2.nivel_max, v_nivel)); end if;
  end if;
  if v_nivel > public._nivel_ref(v_j.id) + 8 then return null; end if;');
  execute d;
  -- pesca: vara mais efetiva, raros em dobro de chance e evento de pesca
  select pg_get_functiondef('public.acao_pescar()'::regprocedure) into d;
  d := public._pt(d, 'r < 0.40 + v_b + 0.25', 'r < (0.45 + v_b + 0.25) * public._ev(''pesca'', 1)');
  d := public._pt(d, 'r < 0.40 + v_b', 'r < (0.45 + v_b) * public._ev(''pesca'', 1)');
  d := public._pt(d, 'sum(peso)', 'sum(peso * case when peso <= 10 then 2 else 1 end)');
  d := public._pt(d, 'v_acc := v_acc + v_e.peso;', 'v_acc := v_acc + v_e.peso * case when v_e.peso <= 10 then 2 else 1 end;');
  execute d;
  -- XP de treinador em dobro
  select pg_get_functiondef('public._ganhar_xp_treino(uuid,integer)'::regprocedure) into d;
  d := public._pt(d, 'greatest(0, p_qtd)', 'greatest(0, floor(p_qtd * public._ev(''xp_treino'', 1))::int)');
  execute d;
  -- duelos contra treinadores com recompensa em dobro
  select pg_get_functiondef('public.sim_gravar(uuid,integer,jsonb,jsonb,integer,jsonb,text,jsonb)'::regprocedure) into d;
  d := replace(d, 'public._ev(''dinheiro'', 1)', 'public._ev(''dinheiro'', 1) * public._ev(''duelo_dobro'', 1)');
  execute d;
  -- torneio: vitória em duelo valendo rende dinheiro extra
  select pg_get_functiondef('public.duelo_aplicar(uuid,jsonb,boolean,jsonb,jsonb)'::regprocedure) into d;
  d := public._pt(d, 'if p_ganhou and jsonb_array_length', 'if p_ganhou and public._ev(''torneio'', 0) > 0 then update public.jogadores set dinheiro = dinheiro + floor(public._ev(''torneio'', 0))::int where id = b.jogador; end if;
  if p_ganhou and jsonb_array_length');
  execute d;
end $$;
drop function public._pt(text, text, text);

-- ===== Geração 1: espécies que não apareciam (sem lendários); raras (peso baixo)
insert into public.encontros (mapa_id, bioma, especie_id, peso, nivel_min, nivel_max) values
  ('reserva','campo',143,1,1,100), ('costa2','agua',131,1,1,100), ('rota10','agua',131,1,1,100), ('azurana','agua',131,1,1,100),
  ('rota8','campo',106,1,1,100), ('rota9','campo',107,1,1,100), ('rota6','grama',108,2,1,100), ('caminho_va','floresta',114,2,1,100),
  ('vale','floresta',124,1,1,100), ('gruta','grama',124,1,1,100), ('obsidiana','campo',137,1,1,100), ('rota10','estrada',137,1,1,100),
  ('gruta','agua',138,1,1,100), ('gruta','campo',140,1,1,100), ('gruta','estrada',142,1,1,100)
on conflict do nothing;
