-- m41: esqueleto de Capítulos (eventos narrativos com regras temporárias). Pronto, mas DESLIGADO:
-- config.modulos_ativos.capitulos = false e nenhuma função existente consulta estas tabelas.

create table if not exists public.capitulos (
  id text primary key check (id ~ '^[a-z0-9_]{2,40}$'),
  nome text not null,
  descricao text not null default '',
  estado text not null default 'rascunho' check (estado in ('rascunho', 'ativo', 'encerrado')),
  inicio timestamptz,
  fim timestamptz,
  criado_em timestamptz not null default now()
);
create table if not exists public.capitulo_efeitos (
  id bigint generated always as identity primary key,
  capitulo text not null references public.capitulos (id) on delete cascade,
  tipo text not null,                         -- ex.: multiplicador_xp, bloquear_mapa, evento_npc (a interpretar no futuro)
  params jsonb not null default '{}'::jsonb,
  ativo boolean not null default true
);
create table if not exists public.capitulo_objetivos (
  id bigint generated always as identity primary key,
  capitulo text not null references public.capitulos (id) on delete cascade,
  descricao text not null,
  metrica text,
  meta int not null default 1,
  recompensa jsonb not null default '{}'::jsonb
);
create table if not exists public.capitulo_progresso (
  jogador uuid not null references public.jogadores (id) on delete cascade,
  objetivo bigint not null references public.capitulo_objetivos (id) on delete cascade,
  progresso int not null default 0,
  concluido_em timestamptz,
  primary key (jogador, objetivo)
);
create table if not exists public.capitulo_penalidades (
  id bigint generated always as identity primary key,
  capitulo text not null references public.capitulos (id) on delete cascade,
  descricao text not null,
  params jsonb not null default '{}'::jsonb
);
do $$ declare t text; begin
  foreach t in array array['capitulos', 'capitulo_efeitos', 'capitulo_objetivos', 'capitulo_progresso', 'capitulo_penalidades'] loop
    execute format('alter table public.%I enable row level security', t);
  end loop;
end $$;
drop policy if exists capp_dono on public.capitulo_progresso;
create policy capp_dono on public.capitulo_progresso for select to authenticated using (jogador = auth.uid() or public.eh_mestre());
grant select on public.capitulo_progresso to authenticated;

-- Ponto único por onde as regras de um capítulo ativo poderão alterar o jogo no futuro. Hoje não faz nada.
create or replace function public._efeito(p_tipo text, p_ctx jsonb default '{}'::jsonb) returns jsonb language sql stable security definer set search_path = public as $$
  select null::jsonb $$;
revoke all on function public._efeito(text, jsonb) from public, anon, authenticated;

-- Mestre: rascunho de capítulos (somente leitura e edição de texto; sem efeito no jogo)
create or replace function public.mestre_capitulos_obter() returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public.eh_mestre() then raise exception 'Só o Mestre.'; end if;
  return jsonb_build_object('ativo', public._modulo('capitulos'),
    'lista', coalesce((select jsonb_agg(to_jsonb(c) order by c.criado_em) from public.capitulos c), '[]'::jsonb));
end $$;

create or replace function public.mestre_capitulo_salvar(p jsonb) returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.eh_mestre() then raise exception 'Só o Mestre.'; end if;
  if (p ->> 'id') !~ '^[a-z0-9_]{2,40}$' then raise exception 'O id deve ter 2 a 40 letras minúsculas, números ou _.'; end if;
  insert into public.capitulos (id, nome, descricao) values (p ->> 'id', coalesce(nullif(p ->> 'nome', ''), p ->> 'id'), coalesce(p ->> 'descricao', ''))
  on conflict (id) do update set nome = excluded.nome, descricao = excluded.descricao;
end $$;

do $$ declare f text; begin
  foreach f in array array['mestre_capitulos_obter()', 'mestre_capitulo_salvar(jsonb)'] loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;
