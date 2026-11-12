-- m28: quem está online (10 s), manutenção com mensagem, derrubar todos, eventos simultâneos e agendados, classe obrigatória
create table if not exists public.presenca (
  jogador uuid primary key,
  visto_em timestamptz not null default now()
);
alter table public.presenca enable row level security;   -- sem políticas: só as funções (security definer) mexem

insert into public.config (chave, valor) values
  ('manutencao', '{"ativo": false, "mensagem": ""}'::jsonb),
  ('derrubar_em', '"1970-01-01T00:00:00Z"'::jsonb)
on conflict (chave) do nothing;

-- ===== eventos: vários ao mesmo tempo (inclusive do mesmo tipo: vale o criado mais recentemente) e com data de início
alter table public.eventos add column if not exists criado_em timestamptz not null default now();

create or replace function public._ev(p_tipo text, p_padrao numeric default 1) returns numeric
language sql stable security definer set search_path = public as $$
  select coalesce((select valor from public.eventos where tipo = p_tipo and not encerrado and now() >= inicio and now() < fim
                    order by criado_em desc, id limit 1), p_padrao) $$;

drop function if exists public.criar_evento(text, numeric, int, text, timestamptz);
create or replace function public.criar_evento(p_tipo text, p_valor numeric, p_minutos int default null, p_mensagem text default null, p_fim timestamptz default null, p_inicio timestamptz default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_j public.jogadores; v_e public.eventos; v_ini timestamptz; v_fim timestamptz;
begin
  if auth.uid() is null then raise exception 'Faça login primeiro.'; end if;
  select * into v_j from public.jogadores where id = auth.uid();
  if not found or v_j.papel <> 'mestre' then raise exception 'Só o Mestre cria eventos.'; end if;
  if p_tipo not in ('xp', 'dinheiro', 'brilhante', 'encontro', 'pa_gratis', 'loja_desconto', 'pa_extra') then raise exception 'Tipo de evento inválido.'; end if;
  if p_valor is null or p_valor <= 0 or p_valor > 1000 then raise exception 'Valor inválido (use um número entre 0,1 e 1000).'; end if;
  if p_tipo = 'loja_desconto' and p_valor > 90 then raise exception 'O desconto máximo é 90%%.'; end if;
  v_ini := case when p_inicio is null or p_inicio < now() + interval '1 minute' then now() else p_inicio end;
  if v_ini > now() + interval '90 days' then raise exception 'O início pode ser no máximo daqui a 90 dias.'; end if;
  if p_tipo = 'pa_extra' and v_ini > now() then raise exception 'PA extra é entregue na hora: não pode ser agendado.'; end if;
  v_fim := coalesce(p_fim, v_ini + make_interval(mins => coalesce(p_minutos, 0)));
  if v_fim <= v_ini then raise exception 'O fim do evento precisa ser depois do início.'; end if;
  if v_fim > v_ini + interval '30 days' then raise exception 'Duração máxima: 30 dias.'; end if;
  insert into public.eventos (tipo, valor, mensagem, inicio, fim, criado_por)
  values (p_tipo, p_valor, nullif(btrim(coalesce(p_mensagem, '')), ''), v_ini, v_fim, v_j.id) returning * into v_e;
  if p_tipo = 'pa_extra' then update public.jogadores set pa = least(32000, pa + floor(p_valor)::int) where conta is null; end if;
  return to_jsonb(v_e);
end $$;
grant execute on function public.criar_evento(text, numeric, int, text, timestamptz, timestamptz) to authenticated;

create or replace function public.eventos_agendados() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.eh_mestre() then raise exception 'Só o Mestre.'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', id, 'tipo', tipo, 'valor', valor, 'mensagem', mensagem, 'inicio', inicio, 'fim', fim) order by inicio)
                     from public.eventos where not encerrado and inicio > now()), '[]'::jsonb);
end $$;
grant execute on function public.eventos_agendados() to authenticated;

create or replace function public.eventos_ativos() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'tipo', tipo, 'valor', valor, 'mensagem', mensagem, 'inicio', inicio, 'fim', fim) order by fim), '[]'::jsonb)
    from public.eventos where not encerrado and now() >= inicio and now() < fim $$;

-- ===== presença, manutenção, derrubar todos
create or replace function public.estado_acesso() returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'manutencao', coalesce((select (valor->>'ativo')::boolean from public.config where chave = 'manutencao'), false),
    'mensagem', coalesce((select valor->>'mensagem' from public.config where chave = 'manutencao'), ''),
    'agora', now()) $$;
grant execute on function public.estado_acesso() to anon, authenticated;

create or replace function public.rafar_ping() returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_m jsonb; v_j public.jogadores;
begin
  if auth.uid() is null then raise exception 'Faça login primeiro.'; end if;
  insert into public.presenca (jogador, visto_em) values (auth.uid(), now())
  on conflict (jogador) do update set visto_em = now();
  select valor into v_m from public.config where chave = 'manutencao';
  select * into v_j from public.jogadores where id = auth.uid();
  return jsonb_build_object(
    'agora', now(),
    'manutencao', coalesce((v_m->>'ativo')::boolean, false),
    'mensagem', coalesce(v_m->>'mensagem', ''),
    'derrubar_em', (select valor #>> '{}' from public.config where chave = 'derrubar_em'),
    'mestre', coalesce(v_j.papel = 'mestre', false),
    'personagem', v_j.id is not null,
    'classe', v_j.classe_rpg,
    'em_batalha', exists (select 1 from public.batalhas where jogador = auth.uid() and estado = 'ativa'));
end $$;
grant execute on function public.rafar_ping() to authenticated;

create or replace function public.mestre_manutencao(p_ativo boolean, p_mensagem text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_msg text;
begin
  if not public.eh_mestre() then raise exception 'Só o Mestre.'; end if;
  v_msg := left(btrim(coalesce(p_mensagem, '')), 200);
  if p_ativo and v_msg = '' then v_msg := 'Estamos em manutenção. Voltamos já!'; end if;
  insert into public.config (chave, valor) values ('manutencao', jsonb_build_object('ativo', p_ativo, 'mensagem', v_msg))
  on conflict (chave) do update set valor = excluded.valor;
  insert into public.auditoria (ator, acao, detalhe) values (auth.uid(), 'manutencao', jsonb_build_object('ativo', p_ativo, 'mensagem', v_msg));
  return jsonb_build_object('ativo', p_ativo, 'mensagem', v_msg);
end $$;
grant execute on function public.mestre_manutencao(boolean, text) to authenticated;

create or replace function public.mestre_derrubar_todos() returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.eh_mestre() then raise exception 'Só o Mestre.'; end if;
  insert into public.config (chave, valor) values ('derrubar_em', to_jsonb(now()))
  on conflict (chave) do update set valor = excluded.valor;
  insert into public.auditoria (ator, acao, detalhe) values (auth.uid(), 'derrubar_todos', '{}'::jsonb);
end $$;
grant execute on function public.mestre_derrubar_todos() to authenticated;

create or replace function public.mestre_jogadores() returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public.eh_mestre() then raise exception 'Só o Mestre.'; end if;
  return coalesce((select jsonb_agg(to_jsonb(r) order by r.nome) from (
    select j.id, j.nome, j.papel, j.pa, j.dinheiro, j.mapa_id, j.insignias, j.campeao, u.email, j.classe_rpg,
           (pr.visto_em is not null and pr.visto_em > now() - interval '10 seconds') as online,
           case when pr.visto_em is null then null else extract(epoch from now() - pr.visto_em)::int end as visto_ha,
           (select count(*) from public.pokemons p where p.dono = j.id) as pokemons,
           (select coalesce(max(p.nivel), 0) from public.pokemons p where p.dono = j.id) as maior_nivel
      from public.jogadores j
      left join auth.users u on u.id = coalesce(j.conta, j.id)
      left join public.presenca pr on pr.jogador = coalesce(j.conta, j.id)
     where j.conta is null) r), '[]'::jsonb);
end $$;
grant execute on function public.mestre_jogadores() to authenticated;

-- ===== porteiro da API: manutenção (quem está em batalha termina) e classe obrigatória
create or replace function public._pre_req() returns void
language plpgsql security definer set search_path = public as $$
declare v_uid uuid; v_path text; v_bloq text := null; v_man jsonb; v_mestre boolean;
begin
  begin
    v_uid := nullif(current_setting('request.jwt.claims', true)::jsonb ->> 'sub', '')::uuid;
    v_path := coalesce(current_setting('request.path', true), '');
    if v_uid is not null and v_path !~ '/rpc/(rafar_ping|estado_acesso)$' then
      select (papel = 'mestre') into v_mestre from public.jogadores where id = v_uid;
      if not coalesce(v_mestre, false) then
        select valor into v_man from public.config where chave = 'manutencao';
        if coalesce((v_man->>'ativo')::boolean, false) and not exists (select 1 from public.batalhas where jogador = v_uid and estado = 'ativa') then
          v_bloq := 'MANUTENCAO: ' || coalesce(nullif(v_man->>'mensagem', ''), 'Estamos em manutenção.');
        elsif v_path ~ '/rpc/(andar|viajar|procurar_pokemon|gerar_oferta|usar_poi|npc_interagir|desafiar_treinador|desafio_enviar|desafio_responder|troca_propor|troca_responder|comprar_item|comprar_habilidade|usar_item_fora|curar_time|missao_aceitar|organizar_time|definir_seguidor|acao_[a-z_]+)$'
              and exists (select 1 from public.jogadores where id = v_uid and classe_rpg is null) then
          v_bloq := 'Escolha a sua classe primeiro: ela é obrigatória para jogar.';
        end if;
      end if;
    end if;
  exception when others then
    v_bloq := null;   -- na dúvida, nunca trava o jogo por erro do porteiro
  end;
  if v_bloq is not null then raise exception '%', v_bloq; end if;
end $$;
grant execute on function public._pre_req() to anon, authenticated, service_role;
alter role authenticator set pgrst.db_pre_request = 'public._pre_req';
notify pgrst, 'reload config';
