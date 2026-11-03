-- M1: mapas, jogadores, posição, auditoria e canal em tempo real.
-- Regra de ouro: o navegador só LÊ estas tabelas; toda escrita passa por funções do servidor.

create table public.mapas (
  id text primary key,
  nome text not null,
  largura int not null check (largura > 0),
  altura int not null check (altura > 0),
  spawn_x int not null,
  spawn_y int not null
);

insert into public.mapas (id, nome, largura, altura, spawn_x, spawn_y)
values ('pallet', 'Pallet Town', 24, 20, 11, 8);

create table public.jogadores (
  id uuid primary key references auth.users (id) on delete cascade,
  nome text not null check (char_length(nome) between 2 and 12),
  papel text not null default 'jogador' check (papel in ('jogador', 'mestre')),
  aparencia smallint not null default 0 check (aparencia between 0 and 3),
  mapa_id text not null default 'pallet' references public.mapas (id),
  x int not null,
  y int not null,
  direcao text not null default 'baixo' check (direcao in ('cima', 'baixo', 'esquerda', 'direita')),
  posicao_em timestamptz not null default now(),
  criado_em timestamptz not null default now()
);

create unique index jogadores_nome_unico on public.jogadores (lower(nome));

create table public.config (
  chave text primary key,
  valor jsonb not null
);

create table public.auditoria (
  id bigint generated always as identity primary key,
  quando timestamptz not null default now(),
  ator uuid references auth.users (id) on delete set null,
  acao text not null,
  detalhe jsonb not null default '{}'::jsonb
);

alter table public.mapas enable row level security;
alter table public.jogadores enable row level security;
alter table public.config enable row level security;
alter table public.auditoria enable row level security;

-- Papel de Mestre, decidido no servidor (nunca pelo navegador).
create or replace function public.eh_mestre()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (select 1 from public.jogadores where id = auth.uid() and papel = 'mestre');
$$;

-- Leitura: só usuários logados. Nenhuma política de escrita: ninguém escreve direto.
create policy "mapas_leitura" on public.mapas for select to authenticated using (true);
create policy "jogadores_leitura" on public.jogadores for select to authenticated using (true);
create policy "config_leitura" on public.config for select to authenticated using (true);
create policy "auditoria_leitura_mestre" on public.auditoria for select to authenticated using (public.eh_mestre());

grant select on public.mapas, public.jogadores, public.config, public.auditoria to authenticated;

-- Cria o personagem do próprio usuário logado (uma vez só).
create or replace function public.criar_personagem(p_nome text, p_aparencia smallint)
returns public.jogadores
language plpgsql
security definer
set search_path = public
as $$
declare
  v_nome text := btrim(coalesce(p_nome, ''));
  v_mapa public.mapas;
  v_jogador public.jogadores;
begin
  if auth.uid() is null then
    raise exception 'Faça login primeiro.';
  end if;
  if exists (select 1 from public.jogadores where id = auth.uid()) then
    raise exception 'Você já tem um personagem.';
  end if;
  if char_length(v_nome) not between 2 and 12 or v_nome !~ '^[A-Za-zÀ-ÿ0-9 ]+$' then
    raise exception 'O nome deve ter de 2 a 12 letras, números ou espaços.';
  end if;
  if p_aparencia is null or p_aparencia not between 0 and 3 then
    raise exception 'Aparência inválida.';
  end if;
  if exists (select 1 from public.jogadores where lower(nome) = lower(v_nome)) then
    raise exception 'Esse nome já está em uso.';
  end if;

  select * into v_mapa from public.mapas where id = 'pallet';

  insert into public.jogadores (id, nome, aparencia, mapa_id, x, y)
  values (auth.uid(), v_nome, p_aparencia, v_mapa.id, v_mapa.spawn_x, v_mapa.spawn_y)
  returning * into v_jogador;

  insert into public.auditoria (ator, acao, detalhe)
  values (auth.uid(), 'criar_personagem', jsonb_build_object('nome', v_nome));

  return v_jogador;
end;
$$;

-- Guarda a posição do próprio jogador, com validação leve (distância x tempo).
create or replace function public.salvar_posicao(p_x int, p_y int, p_dir text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_j public.jogadores;
  v_mapa public.mapas;
  v_dist int;
  v_max int;
begin
  if auth.uid() is null then
    raise exception 'Faça login primeiro.';
  end if;
  select * into v_j from public.jogadores where id = auth.uid() for update;
  if not found then
    raise exception 'Crie seu personagem primeiro.';
  end if;
  select * into v_mapa from public.mapas where id = v_j.mapa_id;

  if p_x is null or p_y is null or p_x not between 0 and v_mapa.largura - 1
     or p_y not between 0 and v_mapa.altura - 1 then
    raise exception 'Posição fora do mapa.';
  end if;
  if p_dir not in ('cima', 'baixo', 'esquerda', 'direita') then
    raise exception 'Direção inválida.';
  end if;

  v_dist := abs(p_x - v_j.x) + abs(p_y - v_j.y);
  v_max := ceil(extract(epoch from (now() - v_j.posicao_em)) * 6)::int + 2;
  if v_dist > v_max then
    raise exception 'Movimento rápido demais.';
  end if;

  update public.jogadores
     set x = p_x, y = p_y, direcao = p_dir, posicao_em = now()
   where id = v_j.id;
end;
$$;

revoke all on function public.criar_personagem(text, smallint) from public, anon;
revoke all on function public.salvar_posicao(int, int, text) from public, anon;
revoke all on function public.eh_mestre() from public, anon;
grant execute on function public.criar_personagem(text, smallint) to authenticated;
grant execute on function public.salvar_posicao(int, int, text) to authenticated;
grant execute on function public.eh_mestre() to authenticated;

-- Canal em tempo real privado por mapa (tópicos "mapa:<id>"): só usuários logados.
create policy "realtime_mapa_ler" on realtime.messages
  for select to authenticated
  using ((select realtime.topic()) like 'mapa:%');
create policy "realtime_mapa_enviar" on realtime.messages
  for insert to authenticated
  with check ((select realtime.topic()) like 'mapa:%');
