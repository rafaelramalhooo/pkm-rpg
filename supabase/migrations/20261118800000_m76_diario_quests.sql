-- m76: Diário de Quests (lista unificada) e marcas "!" / "?" sobre os NPCs

-- Lista unificada das quests do jogador: missão com NPC, busca de Pedra, tarefas do Mundo vivo e desafios da semana.
create or replace function public.quests_diario() returns jsonb language plpgsql security definer set search_path = public as $$
declare r jsonb := '[]'::jsonb; m jsonb; x record; j uuid := auth.uid(); l jsonb;
begin
  if j is null then return r; end if;
  m := public.missao_estado();
  if m is not null and m ->> 'estado' = 'ativa' then
    r := r || jsonb_build_array(jsonb_build_object('tipo', 'missao', 'id', m ->> 'id', 'titulo', m ->> 'nome', 'passo', m ->> 'objetivo', 'npc', m ->> 'npc',
      'mapa_id', m ->> 'mapa_id', 'mapa', m ->> 'mapa_nome', 'progresso', (m ->> 'feitas') || '/' || (m ->> 'total')));
  end if;
  for x in
    select c.id, c.nome, c.preco, e.nome enome, e.tipo, e.mapa_id, mp.nome mapa, p.etapa,
           (select count(*) from public.pedra_etapas z where z.cadeia = c.id) total
      from public.pedra_progresso p
      join public.pedra_cadeias c on c.id = p.cadeia and c.ativa
      join public.pedra_etapas e on e.cadeia = c.id and e.ordem = p.etapa + 1
      join public.mapas mp on mp.id = e.mapa_id
     where p.jogador = j and p.etapa > 0
  loop
    r := r || jsonb_build_array(jsonb_build_object('tipo', 'pedra', 'id', x.id, 'titulo', 'Busca: ' || x.nome,
      'passo', case when x.tipo = 'final' then format('Leve ₽ %s a %s para receber a pedra.', x.preco, x.enome) else format('Procure %s.', x.enome) end,
      'npc', x.enome, 'mapa_id', x.mapa_id, 'mapa', x.mapa, 'progresso', x.etapa || '/' || x.total));
  end loop;
  for x in
    select q.id, q.texto, q.progresso, q.meta, q.premio, q.expira_dia, n.nome npc, n.mapa_id, mp.nome mapa
      from public.mv_quests q
      left join public.mv_npcs n on n.id = q.npc
      left join public.mapas mp on mp.id = n.mapa_id
     where q.jogador = j and q.estado = 'ativa' and q.expira_dia >= public._dia_jogo()
     order by q.id
  loop
    r := r || jsonb_build_array(jsonb_build_object('tipo', 'mv', 'id', x.id::text, 'titulo', 'Tarefa do dia', 'passo', x.texto || ' (vale até as 6h)',
      'npc', x.npc, 'mapa_id', x.mapa_id, 'mapa', x.mapa, 'progresso', x.progresso || '/' || x.meta, 'recompensa', x.premio));
  end loop;
  l := public.miniquests_listar();
  if l is not null and coalesce((l ->> 'ativo')::boolean, false) then
    for x in select e as q from jsonb_array_elements(l -> 'lista') e where not coalesce((e ->> 'feita')::boolean, false) loop
      r := r || jsonb_build_array(jsonb_build_object('tipo', 'semana', 'id', x.q ->> 'id', 'titulo', 'Desafio: ' || (x.q ->> 'nome'), 'passo', x.q ->> 'dica',
        'mapa_id', x.q ->> 'mapa_id', 'mapa', x.q ->> 'mapa', 'recompensa', x.q -> 'recompensa'));
    end loop;
  end if;
  return r;
end $$;
revoke all on function public.quests_diario() from public, anon;
grant execute on function public.quests_diario() to authenticated;

-- Marcas sobre os NPCs: "!" = tem quest para você; "?" = você precisa falar com ele para avançar. Devolve {id_do_npc: "!"|"?"}.
create or replace function public.quests_marcas() returns jsonb language plpgsql stable security definer set search_path = public as $$
declare r jsonb := '{}'::jsonb; j uuid := auth.uid(); m public.missoes; mj public.missao_jogador; x record; d date := public._dia_jogo(); npc text;
begin
  if j is null then return r; end if;
  for m in select * from public.missoes where ativa loop
    select * into mj from public.missao_jogador where jogador = j and missao = m.id;
    if not found then
      npc := m.etapas -> 0 ->> 'npc';
      if npc is not null then r := r || jsonb_build_object(npc, '!'); end if;
    elsif mj.estado = 'ativa' then
      npc := m.etapas -> mj.etapa ->> 'npc';
      if npc is not null then r := r || jsonb_build_object(npc, '?'); end if;
    end if;
  end loop;
  for x in
    select e.id, e.ordem, coalesce(p.etapa, 0) pr
      from public.pedra_etapas e
      join public.pedra_cadeias c on c.id = e.cadeia and c.ativa
      left join public.pedra_progresso p on p.jogador = j and p.cadeia = e.cadeia
  loop
    if x.ordem = 1 and x.pr = 0 then r := r || jsonb_build_object(x.id, '!');
    elsif x.pr > 0 and x.ordem = x.pr + 1 then r := r || jsonb_build_object(x.id, '?'); end if;
  end loop;
  for x in
    select n.id from public.mv_npcs n join public.mv_arquetipos a on a.id = n.arquetipo and a.categoria = 'quest'
     where n.dia = d and not exists (select 1 from public.mv_quests q where q.jogador = j and q.npc = n.id and q.expira_dia = d)
  loop
    r := r || jsonb_build_object(x.id, '!');
  end loop;
  return r;
end $$;
revoke all on function public.quests_marcas() from public, anon;
grant execute on function public.quests_marcas() to authenticated;
