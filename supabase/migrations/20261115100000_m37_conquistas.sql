-- m37: Conquistas (progresso por contadores) + gatilho que registra o fim das batalhas.

create table if not exists public.conquistas_catalogo (
  id text primary key,
  categoria text not null default 'geral',
  nome text not null,
  descricao text not null default '',
  metrica text not null,              -- captura, vitoria_selvagem, vitoria_treinador, vitoria_lider, duelo, duelo_vitoria, evolucao, missao, checkin, cura, time_dia, duelo_oponentes
  meta int not null check (meta > 0),
  periodo text not null default 'total' check (periodo in ('total', 'dia', 'semana')),
  recompensa jsonb not null default '{}'::jsonb,
  ordem int not null default 0,
  grupo text,
  ativa boolean not null default true
);
create table if not exists public.conquistas_jogador (
  jogador uuid not null references public.jogadores (id) on delete cascade,
  conquista text not null references public.conquistas_catalogo (id) on delete cascade,
  ref_periodo text not null default 'total',   -- 'total' | 'd:AAAA-MM-DD' | 'w:AAAA-MM-DD'
  concluida_em timestamptz not null default now(),
  avisada boolean not null default false,
  primary key (jogador, conquista, ref_periodo)
);
alter table public.conquistas_catalogo enable row level security;
alter table public.conquistas_jogador enable row level security;
drop policy if exists cq_leitura on public.conquistas_catalogo;
create policy cq_leitura on public.conquistas_catalogo for select to authenticated using (true);
drop policy if exists cqj_dono on public.conquistas_jogador;
create policy cqj_dono on public.conquistas_jogador for select to authenticated using (jogador = auth.uid() or public.eh_mestre());
grant select on public.conquistas_catalogo, public.conquistas_jogador to authenticated;

insert into public.conquistas_catalogo (id, categoria, nome, descricao, metrica, meta, periodo, recompensa, ordem, grupo) values
  ('cap_10', 'Captura', 'Primeiras capturas', 'Capture 10 Pokémon.', 'captura', 10, 'total', '{"itens":[{"item":"great-ball","qtd":3}]}', 10, 'captura'),
  ('cap_20', 'Captura', 'Colecionador iniciante', 'Capture 20 Pokémon.', 'captura', 20, 'total', '{"itens":[{"item":"great-ball","qtd":5}]}', 11, 'captura'),
  ('cap_30', 'Captura', 'Treinador de campo', 'Capture 30 Pokémon.', 'captura', 30, 'total', '{"dinheiro":1000}', 12, 'captura'),
  ('cap_50', 'Captura', 'Caçador dedicado', 'Capture 50 Pokémon.', 'captura', 50, 'total', '{"itens":[{"item":"ultra-ball","qtd":5}]}', 13, 'captura'),
  ('cap_100', 'Captura', 'Colecionador', 'Capture 100 Pokémon.', 'captura', 100, 'total', '{"titulo":"colecionador","itens":[{"item":"ultra-ball","qtd":10}]}', 14, 'captura'),
  ('selv_25', 'Combate', 'Domador da grama', 'Vença 25 batalhas selvagens.', 'vitoria_selvagem', 25, 'total', '{"xp_treinador":50}', 20, 'selvagem'),
  ('selv_100', 'Combate', 'Veterano da grama', 'Vença 100 batalhas selvagens.', 'vitoria_selvagem', 100, 'total', '{"xp_treinador":200}', 21, 'selvagem'),
  ('trein_5', 'Combate', 'Desafiante', 'Vença 5 treinadores.', 'vitoria_treinador', 5, 'total', '{"dinheiro":500}', 30, 'treinador'),
  ('trein_20', 'Combate', 'Rival de respeito', 'Vença 20 treinadores.', 'vitoria_treinador', 20, 'total', '{"dinheiro":2000,"xp_treinador":100}', 31, 'treinador'),
  ('trein_50', 'Combate', 'Lenda das trilhas', 'Vença 50 treinadores.', 'vitoria_treinador', 50, 'total', '{"itens":[{"item":"rare-candy","qtd":2}]}', 32, 'treinador'),
  ('lider_1', 'Combate', 'Primeiro líder', 'Vença um líder de ginásio.', 'vitoria_lider', 1, 'total', '{"itens":[{"item":"super-potion","qtd":3}]}', 40, 'lider'),
  ('lider_4', 'Combate', 'Quatro ginásios', 'Vença 4 vezes líderes de ginásio.', 'vitoria_lider', 4, 'total', '{"itens":[{"item":"hyper-potion","qtd":3}]}', 41, 'lider'),
  ('lider_8', 'Combate', 'Mestre dos ginásios', 'Vença 8 vezes líderes de ginásio.', 'vitoria_lider', 8, 'total', '{"itens":[{"item":"rare-candy","qtd":1}],"xp_treinador":300}', 42, 'lider'),
  ('evo_1', 'Evolução', 'Evolução', 'Evolua um Pokémon.', 'evolucao', 1, 'total', '{"xp_treinador":50}', 50, 'evolucao'),
  ('evo_10', 'Evolução', 'Criador de campeões', 'Evolua 10 Pokémon.', 'evolucao', 10, 'total', '{"itens":[{"item":"fire-stone","qtd":1}]}', 51, 'evolucao'),
  ('miss_1', 'Missões', 'Ajudante', 'Conclua uma missão.', 'missao', 1, 'total', '{"dinheiro":300}', 60, 'missao'),
  ('miss_5', 'Missões', 'Faz-tudo', 'Conclua 5 missões.', 'missao', 5, 'total', '{"titulo":"explorador"}', 61, 'missao'),
  ('duelo_1', 'Duelos', 'Primeiro duelo', 'Termine um duelo contra outro jogador.', 'duelo', 1, 'total', '{"xp_treinador":30}', 70, 'duelo'),
  ('duelo_10', 'Duelos', 'Arena aberta', 'Termine 10 duelos.', 'duelo', 10, 'total', '{"titulo":"duelista"}', 71, 'duelo'),
  ('duelov_5', 'Duelos', 'Em alta', 'Vença 5 duelos.', 'duelo_vitoria', 5, 'total', '{"dinheiro":1500}', 72, 'duelov'),
  ('duelov_25', 'Duelos', 'Campeão da roda', 'Vença 25 duelos.', 'duelo_vitoria', 25, 'total', '{"itens":[{"item":"rare-candy","qtd":2}]}', 73, 'duelov'),
  ('semana_todos', 'Duelos', 'Encare todo mundo', 'Duele com 3 jogadores diferentes na mesma semana.', 'duelo_oponentes', 3, 'semana', '{"xp_treinador":80}', 74, null),
  ('semana_2x', 'Duelos', 'Duas vezes na semana', 'Termine 2 duelos na mesma semana.', 'duelo', 2, 'semana', '{"dinheiro":400}', 75, null),
  ('dia_time', 'Diário', 'Time completo', 'Use todos os 6 Pokémon do time em batalhas no mesmo dia.', 'time_dia', 6, 'dia', '{"xp_treinador":40}', 80, null),
  ('dia_cura', 'Diário', 'Cuidado de treinador', 'Cure o time 3 vezes no mesmo dia.', 'cura', 3, 'dia', '{"dinheiro":200}', 81, null),
  ('check_7', 'Check-in', 'Uma semana', 'Faça check-in em 7 dias.', 'checkin', 7, 'total', '{"itens":[{"item":"great-ball","qtd":3}]}', 90, 'checkin'),
  ('check_30', 'Check-in', 'Um mês de rotina', 'Faça check-in em 30 dias.', 'checkin', 30, 'total', '{"titulo":"veterano_checkin","itens":[{"item":"ultra-ball","qtd":5}]}', 91, 'checkin'),
  ('check_56', 'Check-in', 'Ciclo completo', 'Faça check-in em 56 dias.', 'checkin', 56, 'total', '{"moldura":"moldura_prata","itens":[{"item":"rare-candy","qtd":2}]}', 92, 'checkin')
on conflict (id) do nothing;

-- progresso atual de uma conquista para um jogador (já no período certo)
create or replace function public._progresso(p_j uuid, c public.conquistas_catalogo) returns int language plpgsql stable security definer set search_path = public as $$
declare d date := public._dia_jogo(); s date := public._semana_inicio(public._dia_jogo()); v bigint;
begin
  if c.metrica = 'time_dia' then
    return (select count(*) from public.participacao_dia where jogador = p_j and dia_jogo = d);
  end if;
  if c.metrica = 'duelo_oponentes' then
    return (select count(distinct ref) from public.atividades where jogador = p_j and tipo = 'duelo' and dia_jogo between s and s + 6 and ref is not null);
  end if;
  select valor into v from public.contadores where jogador = p_j and chave = c.metrica
     and periodo = case c.periodo when 'total' then 'total' when 'dia' then 'd:' || d else 'w:' || s end;
  return least(coalesce(v, 0), 2000000000)::int;
end $$;
revoke all on function public._progresso(uuid, public.conquistas_catalogo) from public, anon, authenticated;

create or replace function public._conquistas_verificar(p_j uuid) returns void language plpgsql security definer set search_path = public as $$
declare c public.conquistas_catalogo; ref text; d date := public._dia_jogo(); s date := public._semana_inicio(public._dia_jogo());
begin
  for c in select * from public.conquistas_catalogo where ativa loop
    ref := case c.periodo when 'total' then 'total' when 'dia' then 'd:' || d else 'w:' || s end;
    if not exists (select 1 from public.conquistas_jogador where jogador = p_j and conquista = c.id and ref_periodo = ref)
       and public._progresso(p_j, c) >= c.meta then
      insert into public.conquistas_jogador (jogador, conquista, ref_periodo) values (p_j, c.id, ref) on conflict do nothing;
      perform public._conceder(p_j, c.recompensa);
    end if;
  end loop;
end $$;
revoke all on function public._conquistas_verificar(uuid) from public, anon, authenticated;

-- lista para a tela de Conquistas
create or replace function public.conquistas_listar() returns jsonb language plpgsql stable security definer set search_path = public as $$
declare d date := public._dia_jogo(); s date := public._semana_inicio(public._dia_jogo());
begin
  if auth.uid() is null or not public._modulo('conquistas') then return '[]'::jsonb; end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
      'id', c.id, 'categoria', c.categoria, 'nome', c.nome, 'descricao', c.descricao, 'meta', c.meta, 'periodo', c.periodo,
      'recompensa', c.recompensa, 'progresso', least(public._progresso(auth.uid(), c), c.meta),
      'concluida', exists (select 1 from public.conquistas_jogador cj where cj.jogador = auth.uid() and cj.conquista = c.id
                            and cj.ref_periodo = case c.periodo when 'total' then 'total' when 'dia' then 'd:' || d else 'w:' || s end),
      'vezes', (select count(*) from public.conquistas_jogador cj where cj.jogador = auth.uid() and cj.conquista = c.id)
    ) order by c.ordem, c.nome) from public.conquistas_catalogo c where c.ativa), '[]'::jsonb);
end $$;

-- conquistas recém-concluídas (aviso na tela); marca como avisadas
create or replace function public.conquistas_novas() returns jsonb language plpgsql security definer set search_path = public as $$
declare r jsonb;
begin
  if auth.uid() is null then return '[]'::jsonb; end if;
  with u as (update public.conquistas_jogador set avisada = true where jogador = auth.uid() and not avisada returning conquista)
  select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'nome', c.nome, 'recompensa', c.recompensa)), '[]'::jsonb)
    into r from u join public.conquistas_catalogo c on c.id = u.conquista;
  return r;
end $$;

create or replace function public.mestre_conquistas_obter() returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public.eh_mestre() then raise exception 'Só o Mestre.'; end if;
  return coalesce((select jsonb_agg(to_jsonb(c) order by c.ordem, c.nome) from public.conquistas_catalogo c), '[]'::jsonb);
end $$;

create or replace function public.mestre_conquista_salvar(p jsonb) returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.eh_mestre() then raise exception 'Só o Mestre.'; end if;
  if (p ->> 'id') !~ '^[a-z0-9_]{2,40}$' then raise exception 'O id deve ter 2 a 40 letras minúsculas, números ou _.'; end if;
  if coalesce(p ->> 'metrica', '') not in ('captura', 'vitoria_selvagem', 'vitoria_treinador', 'vitoria_lider', 'duelo', 'duelo_vitoria', 'evolucao', 'missao', 'checkin', 'cura', 'time_dia', 'duelo_oponentes', 'miniquest', 'ovo') then
    raise exception 'Métrica inválida.';
  end if;
  if coalesce(p ->> 'periodo', 'total') not in ('total', 'dia', 'semana') then raise exception 'Período inválido.'; end if;
  if coalesce((p ->> 'meta')::int, 0) < 1 then raise exception 'A meta precisa ser ao menos 1.'; end if;
  perform public._payload_ok(p -> 'recompensa');
  insert into public.conquistas_catalogo (id, categoria, nome, descricao, metrica, meta, periodo, recompensa, ordem, grupo, ativa)
  values (p ->> 'id', coalesce(nullif(p ->> 'categoria', ''), 'geral'), coalesce(nullif(p ->> 'nome', ''), p ->> 'id'), coalesce(p ->> 'descricao', ''), p ->> 'metrica',
          (p ->> 'meta')::int, coalesce(p ->> 'periodo', 'total'), coalesce(p -> 'recompensa', '{}'::jsonb), coalesce((p ->> 'ordem')::int, 0), nullif(p ->> 'grupo', ''), coalesce((p ->> 'ativa')::boolean, true))
  on conflict (id) do update set categoria = excluded.categoria, nome = excluded.nome, descricao = excluded.descricao, metrica = excluded.metrica,
    meta = excluded.meta, periodo = excluded.periodo, recompensa = excluded.recompensa, ordem = excluded.ordem, grupo = excluded.grupo, ativa = excluded.ativa;
end $$;

-- ---------- gatilho: fim de batalha vira atividade ----------
create or replace function public._tg_batalha_fim() returns trigger language plpgsql security definer set search_path = public as $$
declare lid boolean; opp uuid; d date := public._dia_jogo();
begin
  if old.estado = 'ativa' and new.estado <> 'ativa' then
    begin
      begin
        insert into public.participacao_dia (jogador, dia_jogo, pokemon)
        select new.jogador, d, x::uuid from jsonb_array_elements_text(coalesce(new.meta -> 'participantes', '[]'::jsonb)) x
         where x ~ '^[0-9a-fA-F-]{36}$' and exists (select 1 from public.pokemons p where p.id = x::uuid and p.dono = new.jogador)
        on conflict do nothing;
      exception when others then null;
      end;
      if new.tipo = 'selvagem' then
        if new.estado = 'captura' then perform public._atividade(new.jogador, 'captura', new.selvagem ->> 'especie');
        elsif new.estado = 'vitoria' then perform public._atividade(new.jogador, 'vitoria_selvagem'); end if;
      elsif new.tipo = 'treinador' and new.estado = 'vitoria' then
        select coalesce(t.lider, false) into lid from public.treinadores t where t.id = new.treinador;
        perform public._atividade(new.jogador, 'vitoria_treinador', new.treinador);
        if coalesce(lid, false) then perform public._atividade(new.jogador, 'vitoria_lider', new.treinador); end if;
      elsif new.tipo = 'duelo' and new.estado in ('vitoria', 'derrota') then
        select b.jogador into opp from public.batalhas b where b.id = new.par;
        perform public._atividade(new.jogador, 'duelo', opp::text);
        if new.estado = 'vitoria' then perform public._atividade(new.jogador, 'duelo_vitoria', opp::text); end if;
      end if;
    exception when others then
      raise warning 'tg_batalha_fim falhou: %', sqlerrm;
    end;
  end if;
  return new;
end $$;
drop trigger if exists tg_batalha_fim on public.batalhas;
create trigger tg_batalha_fim after update of estado on public.batalhas for each row execute function public._tg_batalha_fim();

do $$ declare f text; begin
  foreach f in array array['conquistas_listar()', 'conquistas_novas()', 'mestre_conquistas_obter()', 'mestre_conquista_salvar(jsonb)'] loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;
