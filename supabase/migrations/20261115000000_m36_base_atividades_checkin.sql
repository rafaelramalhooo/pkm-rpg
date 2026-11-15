-- m36: base de engajamento (dia de jogo, atividades, prêmios, cosméticos) + Check-in diário.
-- Regra de ouro: tudo aqui é escrito só por funções do servidor; o navegador apenas lê.

-- ---------- configuração e módulos ----------
insert into public.config (chave, valor) values
  ('fuso', '"America/Sao_Paulo"'::jsonb),
  ('hora_virada', '6'::jsonb),
  ('dia_offset_debug', '0'::jsonb),
  ('modulos_ativos', '{"checkin":true,"conquistas":true,"ranking":true,"miniquests":true,"casa":true,"capitulos":false}'::jsonb)
on conflict (chave) do nothing;

create or replace function public._modulo(p text) returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select (valor ->> p)::boolean from public.config where chave = 'modulos_ativos'), p <> 'capitulos') $$;
revoke all on function public._modulo(text) from public, anon, authenticated;

-- dia de jogo: vira às 6h (config hora_virada) no fuso de São Paulo. dia_offset_debug serve só para o Mestre testar.
create or replace function public._dia_jogo(p_ts timestamptz default now()) returns date language sql stable security definer set search_path = public as $$
  select ((p_ts at time zone coalesce((select valor #>> '{}' from public.config where chave = 'fuso'), 'America/Sao_Paulo'))
          - make_interval(hours => public._cfg_int('hora_virada', 6)))::date + public._cfg_int('dia_offset_debug', 0) $$;
revoke all on function public._dia_jogo(timestamptz) from public, anon, authenticated;

create or replace function public._semana_inicio(p_dia date) returns date language sql immutable as $$
  select p_dia - (extract(isodow from p_dia)::int - 1) $$;
revoke all on function public._semana_inicio(date) from public, anon, authenticated;

create or replace function public._proxima_virada() returns timestamptz language sql stable security definer set search_path = public as $$
  select (((public._dia_jogo() + 1)::timestamp + make_interval(hours => public._cfg_int('hora_virada', 6)))
           at time zone coalesce((select valor #>> '{}' from public.config where chave = 'fuso'), 'America/Sao_Paulo')) $$;
revoke all on function public._proxima_virada() from public, anon, authenticated;

-- ---------- cosméticos (títulos e molduras) ----------
create table if not exists public.cosmeticos_catalogo (
  id text primary key,
  tipo text not null check (tipo in ('titulo', 'moldura')),
  nome text not null,
  estilo jsonb not null default '{}'::jsonb
);
create table if not exists public.cosmeticos_jogador (
  jogador uuid not null references public.jogadores (id) on delete cascade,
  cosmetico text not null references public.cosmeticos_catalogo (id) on delete cascade,
  ganho_em timestamptz not null default now(),
  primary key (jogador, cosmetico)
);
alter table public.jogadores add column if not exists titulo_ativo text, add column if not exists moldura_ativa text;
alter table public.cosmeticos_catalogo enable row level security;
alter table public.cosmeticos_jogador enable row level security;
drop policy if exists cosm_leitura on public.cosmeticos_catalogo;
create policy cosm_leitura on public.cosmeticos_catalogo for select to authenticated using (true);
drop policy if exists cosmj_dono on public.cosmeticos_jogador;
create policy cosmj_dono on public.cosmeticos_jogador for select to authenticated using (jogador = auth.uid() or public.eh_mestre());
grant select on public.cosmeticos_catalogo, public.cosmeticos_jogador to authenticated;

insert into public.cosmeticos_catalogo (id, tipo, nome, estilo) values
  ('observador', 'titulo', 'Observador', '{}'),
  ('duelista', 'titulo', 'Duelista', '{}'),
  ('veterano_checkin', 'titulo', 'Veterano do Check-in', '{}'),
  ('colecionador', 'titulo', 'Colecionador', '{}'),
  ('explorador', 'titulo', 'Explorador', '{}'),
  ('campeao_temporada', 'titulo', 'Campeão da Temporada', '{}'),
  ('vice_temporada', 'titulo', 'Vice-campeão da Temporada', '{}'),
  ('terceiro_temporada', 'titulo', 'Pódio da Temporada', '{}'),
  ('moldura_simples', 'moldura', 'Moldura simples', '{"cor":"#7a8aa0"}'),
  ('moldura_bronze', 'moldura', 'Moldura de bronze', '{"cor":"#b87333"}'),
  ('moldura_prata', 'moldura', 'Moldura de prata', '{"cor":"#c0c8d4"}'),
  ('moldura_ouro', 'moldura', 'Moldura de ouro', '{"cor":"#e6b800"}')
on conflict (id) do nothing;

create or replace function public.cosmeticos_meus() returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if auth.uid() is null then return '{}'::jsonb; end if;
  return jsonb_build_object(
    'titulo', (select titulo_ativo from public.jogadores where id = auth.uid()),
    'moldura', (select moldura_ativa from public.jogadores where id = auth.uid()),
    'itens', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'tipo', c.tipo, 'nome', c.nome, 'estilo', c.estilo) order by c.tipo, c.nome)
                         from public.cosmeticos_jogador cj join public.cosmeticos_catalogo c on c.id = cj.cosmetico where cj.jogador = auth.uid()), '[]'::jsonb));
end $$;

create or replace function public.cosmetico_equipar(p_tipo text, p_id text) returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Faça login primeiro.'; end if;
  if p_tipo not in ('titulo', 'moldura') then raise exception 'Tipo inválido.'; end if;
  if p_id is not null and not exists (select 1 from public.cosmeticos_jogador cj join public.cosmeticos_catalogo c on c.id = cj.cosmetico
                                       where cj.jogador = auth.uid() and cj.cosmetico = p_id and c.tipo = p_tipo) then
    raise exception 'Você ainda não tem este item.';
  end if;
  if p_tipo = 'titulo' then update public.jogadores set titulo_ativo = p_id where id = auth.uid();
  else update public.jogadores set moldura_ativa = p_id where id = auth.uid(); end if;
end $$;

-- ---------- registro de atividades e contadores ----------
create table if not exists public.atividades (
  id bigint generated always as identity primary key,
  jogador uuid not null references public.jogadores (id) on delete cascade,
  tipo text not null,
  ref text,
  qtd int not null default 1,
  dia_jogo date not null,
  criado_em timestamptz not null default now()
);
create index if not exists atividades_jogador_dia on public.atividades (jogador, dia_jogo);
create index if not exists atividades_jogador_tipo on public.atividades (jogador, tipo, criado_em);
create table if not exists public.contadores (
  jogador uuid not null references public.jogadores (id) on delete cascade,
  chave text not null,
  periodo text not null,           -- 'total' | 'd:AAAA-MM-DD' | 'w:AAAA-MM-DD' (segunda-feira da semana)
  valor bigint not null default 0,
  primary key (jogador, chave, periodo)
);
create table if not exists public.participacao_dia (
  jogador uuid not null references public.jogadores (id) on delete cascade,
  dia_jogo date not null,
  pokemon uuid not null references public.pokemons (id) on delete cascade,
  primary key (jogador, dia_jogo, pokemon)
);
alter table public.atividades enable row level security;
alter table public.contadores enable row level security;
alter table public.participacao_dia enable row level security;
drop policy if exists ativ_dono on public.atividades;
create policy ativ_dono on public.atividades for select to authenticated using (jogador = auth.uid() or public.eh_mestre());
drop policy if exists cont_dono on public.contadores;
create policy cont_dono on public.contadores for select to authenticated using (jogador = auth.uid() or public.eh_mestre());
grant select on public.atividades, public.contadores to authenticated;

-- Entrega qualquer prêmio no formato {dinheiro, xp_treinador, pa, itens:[{item,qtd}], titulo, moldura}.
-- Itens ou cosméticos inexistentes são ignorados (um erro de digitação do Mestre nunca trava o jogador).
create or replace function public._conceder(p_j uuid, p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare it jsonb; q int; res jsonb := '{}'::jsonb; lista jsonb := '[]'::jsonb; t text;
begin
  if p is null or jsonb_typeof(p) <> 'object' then return res; end if;
  q := coalesce((p ->> 'dinheiro')::int, 0);
  if q > 0 then update public.jogadores set dinheiro = dinheiro + q where id = p_j; res := res || jsonb_build_object('dinheiro', q); end if;
  q := coalesce((p ->> 'xp_treinador')::int, 0);
  if q > 0 then perform public._ganhar_xp_treino(p_j, q); res := res || jsonb_build_object('xp_treinador', q); end if;
  q := coalesce((p ->> 'pa')::int, 0);
  if q > 0 then update public.jogadores set pa = least(32000, pa + q) where id = p_j; res := res || jsonb_build_object('pa', q); end if;
  for it in select * from jsonb_array_elements(coalesce(p -> 'itens', '[]'::jsonb)) loop
    q := coalesce((it ->> 'qtd')::int, 1);
    if q > 0 and exists (select 1 from public.itens where slug = it ->> 'item') then
      insert into public.inventario (jogador, item, qtd) values (p_j, it ->> 'item', q)
      on conflict (jogador, item) do update set qtd = public.inventario.qtd + excluded.qtd;
      lista := lista || jsonb_build_array(jsonb_build_object('item', it ->> 'item', 'qtd', q));
    end if;
  end loop;
  if jsonb_array_length(lista) > 0 then res := res || jsonb_build_object('itens', lista); end if;
  foreach t in array array['titulo', 'moldura'] loop
    if coalesce(p ->> t, '') <> '' and exists (select 1 from public.cosmeticos_catalogo where id = p ->> t) then
      insert into public.cosmeticos_jogador (jogador, cosmetico) values (p_j, p ->> t) on conflict do nothing;
      res := res || jsonb_build_object(t, p ->> t);
    end if;
  end loop;
  return res;
end $$;
revoke all on function public._conceder(uuid, jsonb) from public, anon, authenticated;

-- Valida um prêmio digitado pelo Mestre (ele recebe o erro na hora).
create or replace function public._payload_ok(p jsonb) returns void language plpgsql security definer set search_path = public as $$
declare it jsonb; t text;
begin
  if p is null or p = '{}'::jsonb then return; end if;
  if jsonb_typeof(p) <> 'object' then raise exception 'Prêmio inválido.'; end if;
  foreach t in array array['dinheiro', 'xp_treinador', 'pa'] loop
    if p ? t and (coalesce((p ->> t)::int, -1) < 0 or (p ->> t)::int > 1000000) then raise exception 'Valor inválido em "%".', t; end if;
  end loop;
  for it in select * from jsonb_array_elements(coalesce(p -> 'itens', '[]'::jsonb)) loop
    if not exists (select 1 from public.itens where slug = it ->> 'item') then raise exception 'Item inexistente: %.', it ->> 'item'; end if;
    if coalesce((it ->> 'qtd')::int, 0) < 1 or (it ->> 'qtd')::int > 999 then raise exception 'Quantidade inválida para %.', it ->> 'item'; end if;
  end loop;
  foreach t in array array['titulo', 'moldura'] loop
    if coalesce(p ->> t, '') <> '' and not exists (select 1 from public.cosmeticos_catalogo where id = p ->> t) then raise exception 'Cosmético inexistente: %.', p ->> t; end if;
  end loop;
end $$;
revoke all on function public._payload_ok(jsonb) from public, anon, authenticated;

-- Registra uma atividade, atualiza contadores e confere conquistas. Nunca derruba quem chamou.
create or replace function public._atividade(p_j uuid, p_tipo text, p_ref text default null, p_qtd int default 1) returns void
language plpgsql security definer set search_path = public as $$
declare d date := public._dia_jogo(); s date := public._semana_inicio(public._dia_jogo()); k text;
begin
  begin
    insert into public.atividades (jogador, tipo, ref, qtd, dia_jogo) values (p_j, p_tipo, p_ref, p_qtd, d);
    foreach k in array array['total', 'd:' || d, 'w:' || s] loop
      insert into public.contadores (jogador, chave, periodo, valor) values (p_j, p_tipo, k, p_qtd)
      on conflict (jogador, chave, periodo) do update set valor = public.contadores.valor + excluded.valor;
    end loop;
    delete from public.contadores where jogador = p_j and periodo like 'd:%' and periodo < 'd:' || (d - 8);
    delete from public.contadores where jogador = p_j and periodo like 'w:%' and periodo < 'w:' || (s - 35);
    delete from public.participacao_dia where jogador = p_j and dia_jogo < d - 2;
    if public._modulo('conquistas') then perform public._conquistas_verificar(p_j); end if;
  exception when others then
    raise warning '_atividade falhou (%): %', p_tipo, sqlerrm;
  end;
end $$;
revoke all on function public._atividade(uuid, text, text, int) from public, anon, authenticated;

-- Gatilhos que alimentam as atividades sem mexer nas funções de batalha
create or replace function public._tg_evolucao() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.especie_id is distinct from old.especie_id then perform public._atividade(new.dono, 'evolucao', new.especie_id::text); end if;
  return new;
end $$;
drop trigger if exists tg_evolucao on public.pokemons;
create trigger tg_evolucao after update of especie_id on public.pokemons for each row execute function public._tg_evolucao();

create or replace function public._tg_missao_concluida() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.estado = 'concluida' and (tg_op = 'INSERT' or old.estado is distinct from 'concluida') then perform public._atividade(new.jogador, 'missao', new.missao); end if;
  return new;
end $$;
drop trigger if exists tg_missao_concluida on public.missao_jogador;
create trigger tg_missao_concluida after insert or update of estado on public.missao_jogador for each row execute function public._tg_missao_concluida();

-- ---------- Check-in diário ----------
create table if not exists public.checkin_calendario (
  semana int not null check (semana between 1 and 8),
  dia int not null check (dia between 1 and 7),
  rotulo text,
  recompensa jsonb not null default '{}'::jsonb,
  primary key (semana, dia)
);
create table if not exists public.checkin_semana_premio (
  semana int primary key check (semana between 1 and 8),
  tema text,
  recompensa jsonb not null default '{}'::jsonb
);
create table if not exists public.checkin_jogador (
  jogador uuid not null references public.jogadores (id) on delete cascade,
  dia_jogo date not null,
  ciclo int not null,
  semana int not null,
  dia int not null,
  recompensa jsonb not null default '{}'::jsonb,
  criado_em timestamptz not null default now(),
  primary key (jogador, dia_jogo)
);
create table if not exists public.checkin_semana_resgate (
  jogador uuid not null references public.jogadores (id) on delete cascade,
  ciclo int not null,
  semana int not null,
  resgatado_em timestamptz not null default now(),
  primary key (jogador, ciclo, semana)
);
alter table public.checkin_calendario enable row level security;
alter table public.checkin_semana_premio enable row level security;
alter table public.checkin_jogador enable row level security;
alter table public.checkin_semana_resgate enable row level security;
drop policy if exists cc_leitura on public.checkin_calendario;
create policy cc_leitura on public.checkin_calendario for select to authenticated using (true);
drop policy if exists csp_leitura on public.checkin_semana_premio;
create policy csp_leitura on public.checkin_semana_premio for select to authenticated using (true);
drop policy if exists cj_dono on public.checkin_jogador;
create policy cj_dono on public.checkin_jogador for select to authenticated using (jogador = auth.uid() or public.eh_mestre());
drop policy if exists csr_dono on public.checkin_semana_resgate;
create policy csr_dono on public.checkin_semana_resgate for select to authenticated using (jogador = auth.uid() or public.eh_mestre());
grant select on public.checkin_calendario, public.checkin_semana_premio, public.checkin_jogador, public.checkin_semana_resgate to authenticated;

insert into public.config (chave, valor) values
  ('checkin_inicio', to_jsonb(public._dia_jogo()::text)),
  ('checkin_meta', '5'::jsonb),
  ('checkin_modo', '"repetir"'::jsonb)
on conflict (chave) do nothing;

-- Calendário inicial sugerido (o Mestre edita tudo na tela "Check-in"). Só entra se a tabela estiver vazia.
insert into public.checkin_semana_premio (semana, tema, recompensa)
select * from (values
  (1, 'Boas-vindas', '{"itens":[{"item":"great-ball","qtd":5}]}'::jsonb),
  (2, 'Captura', '{"titulo":"observador"}'::jsonb),
  (3, 'Cura', '{"itens":[{"item":"super-potion","qtd":5},{"item":"hyper-potion","qtd":2}]}'::jsonb),
  (4, 'Treino', '{"moldura":"moldura_bronze","xp_treinador":100}'::jsonb),
  (5, 'Exploração', '{"itens":[{"item":"fire-stone","qtd":1}]}'::jsonb),
  (6, 'Duelos', '{"titulo":"duelista"}'::jsonb),
  (7, 'Raridade', '{"itens":[{"item":"ultra-ball","qtd":5},{"item":"rare-candy","qtd":1}]}'::jsonb),
  (8, 'Gran finale', '{"moldura":"moldura_ouro","titulo":"veterano_checkin"}'::jsonb)
) v(semana, tema, recompensa)
where not exists (select 1 from public.checkin_semana_premio);

insert into public.checkin_calendario (semana, dia, recompensa)
select * from (values
  (1,1,'{"itens":[{"item":"potion","qtd":2}]}'::jsonb), (1,2,'{"itens":[{"item":"poke-ball","qtd":3}]}'), (1,3,'{"dinheiro":300}'), (1,4,'{"itens":[{"item":"potion","qtd":3}]}'),
  (1,5,'{"itens":[{"item":"great-ball","qtd":1}]}'), (1,6,'{"itens":[{"item":"antidote","qtd":2}]}'), (1,7,'{"itens":[{"item":"super-potion","qtd":2}]}'),
  (2,1,'{"itens":[{"item":"poke-ball","qtd":5}]}'), (2,2,'{"itens":[{"item":"great-ball","qtd":2}]}'), (2,3,'{"dinheiro":400}'), (2,4,'{"itens":[{"item":"repel","qtd":2}]}'),
  (2,5,'{"itens":[{"item":"great-ball","qtd":3}]}'), (2,6,'{"dinheiro":500}'), (2,7,'{"itens":[{"item":"ultra-ball","qtd":1}]}'),
  (3,1,'{"itens":[{"item":"potion","qtd":3}]}'), (3,2,'{"itens":[{"item":"super-potion","qtd":2}]}'), (3,3,'{"itens":[{"item":"antidote","qtd":2}]}'), (3,4,'{"itens":[{"item":"paralyze-heal","qtd":2}]}'),
  (3,5,'{"itens":[{"item":"hyper-potion","qtd":1}]}'), (3,6,'{"itens":[{"item":"revive","qtd":1}]}'), (3,7,'{"itens":[{"item":"super-potion","qtd":3}]}'),
  (4,1,'{"dinheiro":500}'), (4,2,'{"pa":3}'), (4,3,'{"itens":[{"item":"great-ball","qtd":3}]}'), (4,4,'{"xp_treinador":40}'),
  (4,5,'{"itens":[{"item":"super-potion","qtd":2}]}'), (4,6,'{"pa":3}'), (4,7,'{"xp_treinador":80}'),
  (5,1,'{"itens":[{"item":"escape-rope","qtd":1}]}'), (5,2,'{"itens":[{"item":"repel","qtd":3}]}'), (5,3,'{"itens":[{"item":"great-ball","qtd":3}]}'), (5,4,'{"itens":[{"item":"super-repel","qtd":2}]}'),
  (5,5,'{"dinheiro":700}'), (5,6,'{"itens":[{"item":"hyper-potion","qtd":1}]}'), (5,7,'{"itens":[{"item":"water-stone","qtd":1}]}'),
  (6,1,'{"itens":[{"item":"hyper-potion","qtd":1}]}'), (6,2,'{"itens":[{"item":"revive","qtd":1}]}'), (6,3,'{"itens":[{"item":"great-ball","qtd":4}]}'), (6,4,'{"itens":[{"item":"full-heal","qtd":1}]}'),
  (6,5,'{"dinheiro":800}'), (6,6,'{"itens":[{"item":"hyper-potion","qtd":2}]}'), (6,7,'{"itens":[{"item":"max-potion","qtd":1}]}'),
  (7,1,'{"itens":[{"item":"ultra-ball","qtd":2}]}'), (7,2,'{"dinheiro":1000}'), (7,3,'{"itens":[{"item":"max-potion","qtd":1}]}'), (7,4,'{"itens":[{"item":"revive","qtd":2}]}'),
  (7,5,'{"itens":[{"item":"ultra-ball","qtd":3}]}'), (7,6,'{"itens":[{"item":"full-restore","qtd":1}]}'), (7,7,'{"itens":[{"item":"rare-candy","qtd":1}]}'),
  (8,1,'{"itens":[{"item":"hyper-potion","qtd":2}]}'), (8,2,'{"dinheiro":1000}'), (8,3,'{"itens":[{"item":"ultra-ball","qtd":3}]}'), (8,4,'{"itens":[{"item":"max-revive","qtd":1}]}'),
  (8,5,'{"pa":5}'), (8,6,'{"itens":[{"item":"full-restore","qtd":1}]}'), (8,7,'{"itens":[{"item":"rare-candy","qtd":2}]}')
) v(semana, dia, recompensa)
where not exists (select 1 from public.checkin_calendario);

-- onde estamos no calendário (dia 1 = checkin_inicio)
create or replace function public._checkin_pos(p_dia date) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare ini date := coalesce((select (valor #>> '{}')::date from public.config where chave = 'checkin_inicio'), p_dia); n int;
  modo text := coalesce((select valor #>> '{}' from public.config where chave = 'checkin_modo'), 'repetir');
begin
  n := p_dia - ini;
  if n < 0 then return jsonb_build_object('estado', 'aguardando', 'inicio', ini); end if;
  if modo = 'parar' and n >= 56 then return jsonb_build_object('estado', 'encerrado', 'inicio', ini); end if;
  return jsonb_build_object('estado', 'ok', 'ciclo', n / 56 + 1, 'semana', (n % 56) / 7 + 1, 'dia', n % 7 + 1, 'inicio', ini);
end $$;
revoke all on function public._checkin_pos(date) from public, anon, authenticated;

create or replace function public.checkin_estado() returns jsonb language plpgsql stable security definer set search_path = public as $$
declare pos jsonb; d date := public._dia_jogo(); meta int := public._cfg_int('checkin_meta', 5); feitos int; premio jsonb; resg boolean; hoje boolean; dias jsonb;
begin
  if auth.uid() is null or not public._modulo('checkin') then return jsonb_build_object('ativo', false); end if;
  pos := public._checkin_pos(d);
  hoje := exists (select 1 from public.checkin_jogador where jogador = auth.uid() and dia_jogo = d);
  if pos ->> 'estado' <> 'ok' then
    return jsonb_build_object('ativo', true, 'estado', pos ->> 'estado', 'inicio', pos -> 'inicio', 'ja_fez_hoje', hoje, 'proxima_virada', public._proxima_virada());
  end if;
  feitos := (select count(*) from public.checkin_jogador where jogador = auth.uid() and ciclo = (pos ->> 'ciclo')::int and semana = (pos ->> 'semana')::int);
  select coalesce(jsonb_agg(jsonb_build_object('dia', g.dia, 'recompensa', coalesce(c.recompensa, '{}'::jsonb), 'rotulo', c.rotulo,
           'feito', exists (select 1 from public.checkin_jogador cj where cj.jogador = auth.uid() and cj.ciclo = (pos ->> 'ciclo')::int and cj.semana = (pos ->> 'semana')::int and cj.dia = g.dia)) order by g.dia), '[]'::jsonb)
    into dias from generate_series(1, 7) g(dia) left join public.checkin_calendario c on c.semana = (pos ->> 'semana')::int and c.dia = g.dia;
  select jsonb_build_object('tema', tema, 'recompensa', recompensa) into premio from public.checkin_semana_premio where semana = (pos ->> 'semana')::int;
  resg := exists (select 1 from public.checkin_semana_resgate where jogador = auth.uid() and ciclo = (pos ->> 'ciclo')::int and semana = (pos ->> 'semana')::int);
  return jsonb_build_object('ativo', true, 'estado', 'ok', 'ja_fez_hoje', hoje, 'ciclo', pos -> 'ciclo', 'semana', pos -> 'semana', 'dia', pos -> 'dia',
    'feitos', feitos, 'meta', meta, 'dias', dias, 'premio_semana', premio, 'semana_resgatada', resg, 'proxima_virada', public._proxima_virada());
end $$;

create or replace function public.fazer_checkin() returns jsonb language plpgsql security definer set search_path = public as $$
declare v_j public.jogadores; d date := public._dia_jogo(); pos jsonb; rec jsonb; ent jsonb; feitos int; meta int := public._cfg_int('checkin_meta', 5);
  v_ciclo int; v_semana int; v_dia int; premio jsonb; sem_ent jsonb := null; rot text;
begin
  if auth.uid() is null then raise exception 'Faça login primeiro.'; end if;
  if not public._modulo('checkin') then raise exception 'O check-in diário não está ativo.'; end if;
  select * into v_j from public.jogadores where id = auth.uid() for update;
  if not found then raise exception 'Crie seu personagem primeiro.'; end if;
  if exists (select 1 from public.batalhas where jogador = v_j.id and estado = 'ativa') then raise exception 'Termine a batalha primeiro.'; end if;
  if not public._poi_aqui(v_j, 'centro') then raise exception 'O check-in é feito no balcão de um Centro Pokémon.'; end if;
  pos := public._checkin_pos(d);
  if pos ->> 'estado' = 'aguardando' then raise exception 'O calendário de check-in ainda não começou.'; end if;
  if pos ->> 'estado' = 'encerrado' then raise exception 'O calendário de check-in terminou. Aguarde o próximo.'; end if;
  if exists (select 1 from public.checkin_jogador where jogador = v_j.id and dia_jogo = d) then
    raise exception 'Você já fez o check-in de hoje. O próximo abre às %h.', public._cfg_int('hora_virada', 6);
  end if;
  v_ciclo := (pos ->> 'ciclo')::int; v_semana := (pos ->> 'semana')::int; v_dia := (pos ->> 'dia')::int;
  select c.recompensa, c.rotulo into rec, rot from public.checkin_calendario c where c.semana = v_semana and c.dia = v_dia;
  rec := coalesce(rec, '{}'::jsonb);
  insert into public.checkin_jogador (jogador, dia_jogo, ciclo, semana, dia, recompensa) values (v_j.id, d, v_ciclo, v_semana, v_dia, rec);
  ent := public._conceder(v_j.id, rec);
  perform public._atividade(v_j.id, 'checkin', v_semana::text || ':' || v_dia::text);
  select count(*) into feitos from public.checkin_jogador cj where cj.jogador = v_j.id and cj.ciclo = v_ciclo and cj.semana = v_semana;
  if feitos >= meta and not exists (select 1 from public.checkin_semana_resgate r where r.jogador = v_j.id and r.ciclo = v_ciclo and r.semana = v_semana) then
    insert into public.checkin_semana_resgate (jogador, ciclo, semana) values (v_j.id, v_ciclo, v_semana);
    select p.recompensa into premio from public.checkin_semana_premio p where p.semana = v_semana;
    sem_ent := public._conceder(v_j.id, coalesce(premio, '{}'::jsonb));
    perform public._atividade(v_j.id, 'checkin_semana', v_semana::text);
  end if;
  return jsonb_build_object('semana', v_semana, 'dia', v_dia, 'rotulo', rot, 'entregue', ent, 'feitos', feitos, 'meta', meta, 'premio_semana', sem_ent);
end $$;

-- Mestre: ler e salvar o calendário inteiro
create or replace function public.mestre_checkin_obter() returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public.eh_mestre() then raise exception 'Só o Mestre.'; end if;
  return jsonb_build_object(
    'inicio', (select valor #>> '{}' from public.config where chave = 'checkin_inicio'),
    'meta', public._cfg_int('checkin_meta', 5),
    'modo', coalesce((select valor #>> '{}' from public.config where chave = 'checkin_modo'), 'repetir'),
    'hoje', public._dia_jogo(),
    'calendario', coalesce((select jsonb_agg(jsonb_build_object('semana', semana, 'dia', dia, 'rotulo', rotulo, 'recompensa', recompensa) order by semana, dia) from public.checkin_calendario), '[]'::jsonb),
    'semanas', coalesce((select jsonb_agg(jsonb_build_object('semana', semana, 'tema', tema, 'recompensa', recompensa) order by semana) from public.checkin_semana_premio), '[]'::jsonb));
end $$;

create or replace function public.mestre_checkin_salvar(p jsonb) returns void language plpgsql security definer set search_path = public as $$
declare c jsonb;
begin
  if not public.eh_mestre() then raise exception 'Só o Mestre.'; end if;
  if p ? 'inicio' then
    insert into public.config (chave, valor) values ('checkin_inicio', to_jsonb(((p ->> 'inicio')::date)::text)) on conflict (chave) do update set valor = excluded.valor;
  end if;
  if p ? 'meta' then
    if (p ->> 'meta')::int not between 1 and 7 then raise exception 'A meta da semana vai de 1 a 7 dias.'; end if;
    insert into public.config (chave, valor) values ('checkin_meta', to_jsonb((p ->> 'meta')::int)) on conflict (chave) do update set valor = excluded.valor;
  end if;
  if p ? 'modo' then
    if p ->> 'modo' not in ('repetir', 'parar') then raise exception 'Modo inválido.'; end if;
    insert into public.config (chave, valor) values ('checkin_modo', to_jsonb(p ->> 'modo')) on conflict (chave) do update set valor = excluded.valor;
  end if;
  for c in select * from jsonb_array_elements(coalesce(p -> 'calendario', '[]'::jsonb)) loop
    perform public._payload_ok(c -> 'recompensa');
    insert into public.checkin_calendario (semana, dia, rotulo, recompensa) values ((c ->> 'semana')::int, (c ->> 'dia')::int, nullif(c ->> 'rotulo', ''), coalesce(c -> 'recompensa', '{}'::jsonb))
    on conflict (semana, dia) do update set rotulo = excluded.rotulo, recompensa = excluded.recompensa;
  end loop;
  for c in select * from jsonb_array_elements(coalesce(p -> 'semanas', '[]'::jsonb)) loop
    perform public._payload_ok(c -> 'recompensa');
    insert into public.checkin_semana_premio (semana, tema, recompensa) values ((c ->> 'semana')::int, nullif(c ->> 'tema', ''), coalesce(c -> 'recompensa', '{}'::jsonb))
    on conflict (semana) do update set tema = excluded.tema, recompensa = excluded.recompensa;
  end loop;
end $$;

create or replace function public.mestre_catalogo_premios() returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public.eh_mestre() then raise exception 'Só o Mestre.'; end if;
  return jsonb_build_object(
    'itens', coalesce((select jsonb_agg(jsonb_build_object('slug', slug, 'nome', nome) order by nome) from public.itens), '[]'::jsonb),
    'cosmeticos', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'tipo', tipo, 'nome', nome) order by tipo, nome) from public.cosmeticos_catalogo), '[]'::jsonb));
end $$;

create or replace function public.mestre_cosmetico_salvar(p_id text, p_tipo text, p_nome text, p_estilo jsonb default '{}'::jsonb) returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.eh_mestre() then raise exception 'Só o Mestre.'; end if;
  if p_tipo not in ('titulo', 'moldura') or coalesce(trim(p_nome), '') = '' or p_id !~ '^[a-z0-9_]{2,40}$' then raise exception 'Dados do cosmético inválidos.'; end if;
  insert into public.cosmeticos_catalogo (id, tipo, nome, estilo) values (p_id, p_tipo, trim(p_nome), coalesce(p_estilo, '{}'::jsonb))
  on conflict (id) do update set nome = excluded.nome, estilo = excluded.estilo;
end $$;

create or replace function public.mestre_modulos_salvar(p jsonb) returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.eh_mestre() then raise exception 'Só o Mestre.'; end if;
  insert into public.config (chave, valor) values ('modulos_ativos', coalesce((select valor from public.config where chave = 'modulos_ativos'), '{}'::jsonb) || p)
  on conflict (chave) do update set valor = public.config.valor || p;
end $$;

create or replace function public.modulos_estado() returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce((select valor from public.config where chave = 'modulos_ativos'), '{}'::jsonb) $$;

do $$ declare f text; begin
  foreach f in array array['cosmeticos_meus()', 'cosmetico_equipar(text,text)', 'checkin_estado()', 'fazer_checkin()', 'mestre_checkin_obter()', 'mestre_checkin_salvar(jsonb)',
                           'mestre_catalogo_premios()', 'mestre_cosmetico_salvar(text,text,text,jsonb)', 'mestre_modulos_salvar(jsonb)', 'modulos_estado()'] loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;
