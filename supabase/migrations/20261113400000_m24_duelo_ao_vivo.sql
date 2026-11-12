-- m24: duelo ao vivo entre dois jogadores.
-- Cada jogador tem a sua própria linha em "batalhas" (tipo 'duelo'), então todas as travas existentes ("termine a batalha primeiro")
-- continuam valendo. A simulação compartilhada fica na linha do desafiante (lado 0); a do desafiado (lado 1) aponta para ela em "par".
-- Duelo amistoso: não altera HP/PP dos Pokémon, não dá XP nem dinheiro. Cada jogador paga 1 PA ao aceitar (regra da m22).
alter table public.batalhas drop constraint if exists batalhas_tipo_check;
alter table public.batalhas add constraint batalhas_tipo_check check (tipo in ('selvagem', 'treinador', 'duelo'));
alter table public.batalhas add column if not exists par uuid references public.batalhas (id) on delete set null;
alter table public.batalhas add column if not exists lado smallint not null default 0;
alter table public.batalhas add column if not exists versao int not null default 0;  -- concorrência otimista do duelo (linha do lado 0)

-- grava o resultado de uma rodada do duelo. p_fim0/p_fim1: null (segue) | 'vitoria' | 'derrota' para cada lado.
create or replace function public.duelo_gravar(
  p_mestre uuid, p_versao int, p_sim jsonb, p_meta jsonb, p_log_len int, p_fim0 text, p_fim1 text
) returns void language plpgsql security definer set search_path = public as $$
declare m public.batalhas; n int;
begin
  select * into m from public.batalhas where id = p_mestre for update;
  if not found or m.estado <> 'ativa' then raise exception 'Batalha encerrada.'; end if;
  if m.versao <> p_versao then raise exception 'CONFLITO'; end if;
  update public.batalhas set sim = p_sim, meta = p_meta, log_len = p_log_len, versao = versao + 1 where id = m.id;
  if p_fim0 is not null then
    update public.batalhas set estado = p_fim0 where id = m.id;
    update public.batalhas set estado = coalesce(p_fim1, 'derrota') where id = m.par;
  end if;
end $$;
revoke all on function public.duelo_gravar(uuid, int, jsonb, jsonb, int, text, text) from public, anon, authenticated;
grant execute on function public.duelo_gravar(uuid, int, jsonb, jsonb, int, text, text) to service_role;

-- o desafiado aceita: cria as duas linhas e já entra na luta
create or replace function public.desafio_responder(p_desafio uuid, p_aceitar boolean) returns jsonb language plpgsql security definer set search_path = public as $$
declare d public.desafios; a uuid; c uuid; ra public.batalhas; rc public.batalhas;
begin
  if auth.uid() is null then raise exception 'Faça login primeiro.'; end if;
  select * into d from public.desafios where id = p_desafio and para = auth.uid() and estado = 'pendente' for update;
  if not found then raise exception 'Este desafio não está mais disponível.'; end if;
  if d.criado < now() - interval '10 minutes' then update public.desafios set estado = 'expirado' where id = d.id; raise exception 'O desafio expirou.'; end if;
  if not p_aceitar then update public.desafios set estado = 'recusado' where id = d.id; return jsonb_build_object('aceito', false); end if;
  if exists (select 1 from public.batalhas where jogador in (d.de, d.para) and estado = 'ativa') then
    raise exception 'Um dos dois jogadores está em outra batalha. Tente de novo em instantes.';
  end if;
  select id into c from public.pokemons where dono = d.para and posicao is not null order by posicao limit 1;
  select id into a from public.pokemons where dono = d.de and posicao is not null order by posicao limit 1;
  if c is null then raise exception 'Você precisa de um Pokémon no time.'; end if;
  if a is null then raise exception 'O desafiante está sem Pokémon no time.'; end if;
  perform public._gastar_pa(d.de);      -- 1 PA de cada um
  perform public._gastar_pa(d.para);
  insert into public.batalhas (jogador, selvagem, ativo, tipo, lado, meta) values (d.de, '{}'::jsonb, a, 'duelo', 0,
    jsonb_build_object('visto', jsonb_build_object('0', (extract(epoch from now()) * 1000)::bigint, '1', (extract(epoch from now()) * 1000)::bigint))) returning * into ra;
  insert into public.batalhas (jogador, selvagem, ativo, tipo, lado, par) values (d.para, '{}'::jsonb, c, 'duelo', 1, ra.id) returning * into rc;
  update public.batalhas set par = rc.id where id = ra.id;
  update public.desafios set estado = 'aceito', batalha = ra.id where id = d.id;
  return jsonb_build_object('aceito', true, 'batalha', to_jsonb(rc) - 'sim' - 'meta');
end $$;
grant execute on function public.desafio_responder(uuid, boolean) to authenticated;

-- desistir de um duelo que não começou ou abandonar: encerra os dois lados (quem sai perde)
create or replace function public.duelo_sair() returns void language plpgsql security definer set search_path = public as $$
declare m public.batalhas;
begin
  select * into m from public.batalhas where jogador = auth.uid() and estado = 'ativa' and tipo = 'duelo';
  if not found then return; end if;
  update public.batalhas set estado = 'derrota' where id = m.id;
  update public.batalhas set estado = 'vitoria' where id = m.par and estado = 'ativa';
end $$;
grant execute on function public.duelo_sair() to authenticated;

-- histórico: resultado visto pelo desafiante vem da linha dele
-- (desafio_pendencias da m22 já lê batalhas.estado da linha do desafiante)

-- desafiar só exige ter Pokémon no time (o duelo começa com HP e PP cheios)
create or replace function public.desafio_enviar(p_alvo uuid) returns uuid language plpgsql security definer set search_path = public as $$
declare d uuid;
begin
  if auth.uid() is null then raise exception 'Faça login primeiro.'; end if;
  if p_alvo = auth.uid() or not exists (select 1 from public.jogadores where id = p_alvo) then raise exception 'Jogador inválido.'; end if;
  if not exists (select 1 from public.pokemons where dono = auth.uid() and posicao is not null) then raise exception 'Você precisa de um Pokémon no time.'; end if;
  if exists (select 1 from public.batalhas where jogador = auth.uid() and estado = 'ativa') then raise exception 'Termine a batalha primeiro.'; end if;
  if (select pa from public.jogadores where id = auth.uid()) < 1 and public._ev('pa_gratis', 0) = 0 then raise exception 'PA insuficiente: um desafio custa 1 PA.'; end if;
  update public.desafios set estado = 'expirado' where estado = 'pendente' and criado < now() - interval '10 minutes';
  if exists (select 1 from public.desafios where de = auth.uid() and para = p_alvo and estado = 'pendente') then raise exception 'Você já desafiou este jogador. Aguarde a resposta.'; end if;
  insert into public.desafios (de, para) values (auth.uid(), p_alvo) returning id into d;
  return d;
end $$;
grant execute on function public.desafio_enviar(uuid) to authenticated;
