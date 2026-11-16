-- m70: chat global e privado (só entre amigos), sistema de amigos, perfil público e moderação do Mestre.
alter table public.jogadores add column if not exists visto_em timestamptz;
alter table public.jogadores add column if not exists chat_silenciado_ate timestamptz;

create table if not exists public.amizades (
  id uuid primary key default gen_random_uuid(),
  de uuid not null references public.jogadores (id) on delete cascade,
  para uuid not null references public.jogadores (id) on delete cascade,
  estado text not null default 'pendente' check (estado in ('pendente', 'aceita')),
  criado timestamptz not null default now(),
  check (de <> para)
);
create unique index if not exists amizades_par on public.amizades (least(de, para), greatest(de, para));
create index if not exists amizades_para on public.amizades (para);

create table if not exists public.mensagens_chat (
  id bigint generated always as identity primary key,
  canal text not null check (canal in ('global', 'privado')),
  de uuid not null references public.jogadores (id) on delete cascade,
  de_nome text not null,
  para uuid references public.jogadores (id) on delete cascade,
  texto text not null check (char_length(texto) between 1 and 200),
  criado timestamptz not null default now(),
  check ((canal = 'global' and para is null) or (canal = 'privado' and para is not null))
);
create index if not exists mensagens_chat_canal on public.mensagens_chat (canal, id desc);
create index if not exists mensagens_chat_privado on public.mensagens_chat (de, para, id desc);

alter table public.amizades enable row level security;
alter table public.mensagens_chat enable row level security;
drop policy if exists amizades_partes on public.amizades;
create policy amizades_partes on public.amizades for select to authenticated using (de = auth.uid() or para = auth.uid());
drop policy if exists chat_ler on public.mensagens_chat;
create policy chat_ler on public.mensagens_chat for select to authenticated using (canal = 'global' or de = auth.uid() or para = auth.uid());
grant select on public.amizades, public.mensagens_chat to authenticated;

do $$ begin
  alter publication supabase_realtime add table public.mensagens_chat;
exception when duplicate_object then null; when undefined_object then null;
end $$;

create or replace function public._sao_amigos(a uuid, b uuid) returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.amizades where estado = 'aceita' and ((de = a and para = b) or (de = b and para = a))) $$;
revoke all on function public._sao_amigos(uuid, uuid) from public, anon, authenticated;

create or replace function public.ping_online() returns void language sql security definer set search_path = public as $$
  update public.jogadores set visto_em = now() where id = auth.uid() $$;

create or replace function public.chat_enviar(p_canal text, p_para uuid, p_texto text) returns jsonb language plpgsql security definer set search_path = public as $$
declare j public.jogadores; t text := btrim(regexp_replace(coalesce(p_texto, ''), '\s+', ' ', 'g')); v_id bigint;
begin
  if auth.uid() is null then raise exception 'Faça login primeiro.'; end if;
  select * into j from public.jogadores where id = auth.uid();
  if not found then raise exception 'Crie seu personagem primeiro.'; end if;
  if j.chat_silenciado_ate is not null and j.chat_silenciado_ate > now() then raise exception 'Você está silenciado no chat até %.', to_char(j.chat_silenciado_ate at time zone 'America/Sao_Paulo', 'DD/MM HH24:MI'); end if;
  if p_canal not in ('global', 'privado') then raise exception 'Canal inválido.'; end if;
  if char_length(t) < 1 then raise exception 'Escreva algo.'; end if;
  if char_length(t) > 200 then raise exception 'Mensagem longa demais (máx. 200).'; end if;
  if t ~* '(https?://|www\.|\.(com|net|org|br|gg|io)(/|\y))' then raise exception 'Links não são permitidos no chat.'; end if;
  if exists (select 1 from public.mensagens_chat where de = j.id and criado > now() - interval '2 seconds') then raise exception 'Calma! Espere um pouquinho entre as mensagens.'; end if;
  if p_canal = 'privado' then
    if p_para is null or not public._sao_amigos(j.id, p_para) then raise exception 'Só é possível conversar em privado com amigos.'; end if;
    insert into public.mensagens_chat (canal, de, de_nome, para, texto) values ('privado', j.id, j.nome, p_para, t) returning id into v_id;
  else
    insert into public.mensagens_chat (canal, de, de_nome, para, texto) values ('global', j.id, j.nome, null, t) returning id into v_id;
  end if;
  update public.jogadores set visto_em = now() where id = j.id;
  return jsonb_build_object('id', v_id);
end $$;

create or replace function public.chat_historico(p_canal text, p_com uuid default null, p_limite int default 50) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare r jsonb; lim int := least(greatest(coalesce(p_limite, 50), 1), 100);
begin
  if auth.uid() is null then return '[]'::jsonb; end if;
  if p_canal = 'privado' then
    if p_com is null or not public._sao_amigos(auth.uid(), p_com) then return '[]'::jsonb; end if;
    select coalesce(jsonb_agg(to_jsonb(q) order by q.id), '[]'::jsonb) into r from (
      select m.id, m.canal, m.de, m.de_nome, m.para, m.texto, m.criado from public.mensagens_chat m
       where m.canal = 'privado' and ((m.de = auth.uid() and m.para = p_com) or (m.de = p_com and m.para = auth.uid())) order by m.id desc limit lim) q;
  else
    select coalesce(jsonb_agg(to_jsonb(q) order by q.id), '[]'::jsonb) into r from (
      select m.id, m.canal, m.de, m.de_nome, m.para, m.texto, m.criado from public.mensagens_chat m where m.canal = 'global' order by m.id desc limit lim) q;
  end if;
  return r;
end $$;

create or replace function public._rank_pos(p_j uuid) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare per int; pts int; pos int;
begin
  begin per := public._ranking_periodo(); exception when others then return null; end;
  select rp.pontos into pts from public.ranking_pontos rp where rp.periodo = per and rp.jogador = p_j;
  if pts is null then return null; end if;
  select count(*) + 1 into pos from public.ranking_pontos rp join public.jogadores j on j.id = rp.jogador
   where rp.periodo = per and j.papel <> 'mestre' and rp.pontos > pts;
  return jsonb_build_object('pos', pos, 'pontos', pts);
end $$;
revoke all on function public._rank_pos(uuid) from public, anon, authenticated;

create or replace function public.jogador_perfil_publico(p_jogador uuid) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare j public.jogadores; a public.amizades; rel text := 'nenhuma';
begin
  if auth.uid() is null then return null; end if;
  select * into j from public.jogadores where id = p_jogador;
  if not found then return null; end if;
  if p_jogador = auth.uid() then rel := 'eu';
  else
    select * into a from public.amizades where (de = auth.uid() and para = p_jogador) or (de = p_jogador and para = auth.uid());
    if found then rel := case when a.estado = 'aceita' then 'amigo' when a.de = auth.uid() then 'enviado' else 'recebido' end; end if;
  end if;
  return jsonb_build_object('id', j.id, 'nome', j.nome, 'aparencia', j.aparencia, 'mestre', j.papel = 'mestre',
    'online', coalesce(j.visto_em > now() - interval '3 minutes', false), 'visto_em', j.visto_em,
    'mapa', (select nome from public.mapas where id = j.mapa_id), 'ranking', public._rank_pos(j.id),
    'nivel', public._nivel_treino(coalesce(j.xp_treino, 0)), 'titulo', j.titulo_ativo, 'moldura', j.moldura_ativa,
    'vistos', (select count(*) from public.pokedex where jogador = j.id), 'capturados', (select count(*) from public.pokedex where jogador = j.id and capturado),
    'insignias', coalesce(array_length(j.insignias, 1), 0), 'campeao', j.campeao,
    'relacao', rel, 'amizade', a.id);
end $$;

create or replace function public.amigo_pedir(p_jogador uuid) returns jsonb language plpgsql security definer set search_path = public as $$
declare a public.amizades;
begin
  if auth.uid() is null then raise exception 'Faça login primeiro.'; end if;
  if p_jogador is null or p_jogador = auth.uid() then raise exception 'Escolha outro jogador.'; end if;
  if not exists (select 1 from public.jogadores where id = p_jogador) then raise exception 'Jogador não encontrado.'; end if;
  select * into a from public.amizades where (de = auth.uid() and para = p_jogador) or (de = p_jogador and para = auth.uid());
  if found then
    if a.estado = 'aceita' then raise exception 'Vocês já são amigos.'; end if;
    if a.de = auth.uid() then raise exception 'Pedido já enviado. Aguarde a resposta.'; end if;
    update public.amizades set estado = 'aceita' where id = a.id;
    return jsonb_build_object('estado', 'aceita');
  end if;
  if (select count(*) from public.amizades where de = auth.uid() and estado = 'pendente') >= 20 then raise exception 'Você já tem muitos pedidos pendentes.'; end if;
  insert into public.amizades (de, para) values (auth.uid(), p_jogador);
  return jsonb_build_object('estado', 'pendente');
end $$;

create or replace function public.amigo_responder(p_id uuid, p_aceitar boolean) returns void language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from public.amizades where id = p_id and para = auth.uid() and estado = 'pendente') then raise exception 'Pedido não encontrado.'; end if;
  if p_aceitar then update public.amizades set estado = 'aceita' where id = p_id; else delete from public.amizades where id = p_id; end if;
end $$;

create or replace function public.amigo_remover(p_jogador uuid) returns void language sql security definer set search_path = public as $$
  delete from public.amizades where (de = auth.uid() and para = p_jogador) or (de = p_jogador and para = auth.uid()) $$;

create or replace function public.amigo_lista() returns jsonb language plpgsql stable security definer set search_path = public as $$
declare r jsonb;
begin
  if auth.uid() is null then return null; end if;
  select jsonb_build_object(
    'amigos', coalesce((select jsonb_agg(jsonb_build_object('id', j.id, 'nome', j.nome, 'aparencia', j.aparencia, 'online', coalesce(j.visto_em > now() - interval '3 minutes', false),
        'visto_em', j.visto_em, 'mapa', (select nome from public.mapas where id = j.mapa_id), 'ranking', public._rank_pos(j.id)) order by (j.visto_em > now() - interval '3 minutes') desc nulls last, j.nome)
      from public.amizades a join public.jogadores j on j.id = case when a.de = auth.uid() then a.para else a.de end
      where a.estado = 'aceita' and (a.de = auth.uid() or a.para = auth.uid())), '[]'::jsonb),
    'recebidos', coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'de', a.de, 'nome', j.nome) order by a.criado) from public.amizades a join public.jogadores j on j.id = a.de where a.para = auth.uid() and a.estado = 'pendente'), '[]'::jsonb),
    'enviados', coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'para', a.para, 'nome', j.nome) order by a.criado) from public.amizades a join public.jogadores j on j.id = a.para where a.de = auth.uid() and a.estado = 'pendente'), '[]'::jsonb)) into r;
  return r;
end $$;

create or replace function public.jogadores_online() returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', j.id, 'nome', j.nome, 'aparencia', j.aparencia) order by j.nome), '[]'::jsonb)
    from public.jogadores j where auth.uid() is not null and j.id <> auth.uid() and j.visto_em > now() - interval '3 minutes' $$;

create or replace function public.mestre_chat_apagar(p_id bigint) returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.eh_mestre() then raise exception 'Apenas o Mestre.'; end if;
  delete from public.mensagens_chat where id = p_id;
end $$;

create or replace function public.mestre_chat_silenciar(p_jogador uuid, p_minutos int) returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.eh_mestre() then raise exception 'Apenas o Mestre.'; end if;
  update public.jogadores set chat_silenciado_ate = case when coalesce(p_minutos, 0) <= 0 then null else now() + make_interval(mins => least(p_minutos, 10080)) end where id = p_jogador;
end $$;

revoke all on function public.ping_online(), public.chat_enviar(text, uuid, text), public.chat_historico(text, uuid, int), public.jogador_perfil_publico(uuid),
  public.amigo_pedir(uuid), public.amigo_responder(uuid, boolean), public.amigo_remover(uuid), public.amigo_lista(), public.jogadores_online(),
  public.mestre_chat_apagar(bigint), public.mestre_chat_silenciar(uuid, int) from public, anon;
grant execute on function public.ping_online(), public.chat_enviar(text, uuid, text), public.chat_historico(text, uuid, int), public.jogador_perfil_publico(uuid),
  public.amigo_pedir(uuid), public.amigo_responder(uuid, boolean), public.amigo_remover(uuid), public.amigo_lista(), public.jogadores_online(),
  public.mestre_chat_apagar(bigint), public.mestre_chat_silenciar(uuid, int) to authenticated;
