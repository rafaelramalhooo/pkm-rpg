-- m25: duelo valendo (padrão) ou amistoso, aplicação do resultado, desistir/remover missão
alter table public.desafios add column if not exists amistoso boolean not null default false;
alter table public.batalhas add column if not exists amistoso boolean not null default false;
alter table public.batalhas add column if not exists aplicado boolean not null default false;

-- ===== desafio: quem desafia escolhe se é amistoso (HP/PP intactos, sem XP) ou valendo (HP/PP reais, vencedor ganha XP)
drop function if exists public.desafio_enviar(uuid);
create or replace function public.desafio_enviar(p_alvo uuid, p_amistoso boolean default false) returns uuid language plpgsql security definer set search_path = public as $$
declare d uuid;
begin
  if auth.uid() is null then raise exception 'Faça login primeiro.'; end if;
  if p_alvo = auth.uid() or not exists (select 1 from public.jogadores where id = p_alvo) then raise exception 'Jogador inválido.'; end if;
  if not exists (select 1 from public.pokemons where dono = auth.uid() and posicao is not null and (p_amistoso or hp_atual > 0)) then
    raise exception 'Você precisa de um Pokémon saudável no time (ou escolha duelo amistoso).';
  end if;
  if exists (select 1 from public.batalhas where jogador = auth.uid() and estado = 'ativa') then raise exception 'Termine a batalha primeiro.'; end if;
  if (select pa from public.jogadores where id = auth.uid()) < 1 and public._ev('pa_gratis', 0) = 0 then raise exception 'PA insuficiente: um desafio custa 1 PA.'; end if;
  update public.desafios set estado = 'expirado' where estado = 'pendente' and criado < now() - interval '10 minutes';
  if exists (select 1 from public.desafios where de = auth.uid() and para = p_alvo and estado = 'pendente') then raise exception 'Você já desafiou este jogador. Aguarde a resposta.'; end if;
  insert into public.desafios (de, para, amistoso) values (auth.uid(), p_alvo, coalesce(p_amistoso, false)) returning id into d;
  return d;
end $$;
grant execute on function public.desafio_enviar(uuid, boolean) to authenticated;

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
  select id into c from public.pokemons where dono = d.para and posicao is not null and (d.amistoso or hp_atual > 0) order by posicao limit 1;
  select id into a from public.pokemons where dono = d.de and posicao is not null and (d.amistoso or hp_atual > 0) order by posicao limit 1;
  if c is null then raise exception 'Você precisa de um Pokémon saudável no time (ou peça um duelo amistoso).'; end if;
  if a is null then raise exception 'O desafiante está sem Pokémon saudáveis.'; end if;
  perform public._gastar_pa(d.de);      -- 1 PA de cada um
  perform public._gastar_pa(d.para);
  insert into public.batalhas (jogador, selvagem, ativo, tipo, lado, amistoso, meta) values (d.de, '{}'::jsonb, a, 'duelo', 0, d.amistoso,
    jsonb_build_object('visto', jsonb_build_object('0', (extract(epoch from now()) * 1000)::bigint, '1', (extract(epoch from now()) * 1000)::bigint))) returning * into ra;
  insert into public.batalhas (jogador, selvagem, ativo, tipo, lado, par, amistoso) values (d.para, '{}'::jsonb, c, 'duelo', 1, ra.id, d.amistoso) returning * into rc;
  update public.batalhas set par = rc.id where id = ra.id;
  update public.desafios set estado = 'aceito', batalha = ra.id where id = d.id;
  return jsonb_build_object('aceito', true, 'batalha', to_jsonb(rc) - 'sim' - 'meta');
end $$;
grant execute on function public.desafio_responder(uuid, boolean) to authenticated;

create or replace function public.desafio_pendencias() returns jsonb language plpgsql security definer set search_path = public as $$
declare rec jsonb; env jsonb; tro jsonb; bat jsonb; his jsonb;
begin
  if auth.uid() is null then return null; end if;
  update public.desafios set estado = 'expirado' where estado = 'pendente' and criado < now() - interval '10 minutes';
  select coalesce(jsonb_agg(jsonb_build_object('id', d.id, 'de', d.de, 'nome', j.nome, 'amistoso', d.amistoso) order by d.criado), '[]'::jsonb) into rec
    from public.desafios d join public.jogadores j on j.id = d.de where d.para = auth.uid() and d.estado = 'pendente';
  select coalesce(jsonb_agg(jsonb_build_object('id', d.id, 'para', d.para, 'nome', j.nome, 'estado', d.estado, 'amistoso', d.amistoso) order by d.criado), '[]'::jsonb) into env
    from public.desafios d join public.jogadores j on j.id = d.para where d.de = auth.uid() and d.estado = 'pendente';
  select coalesce(jsonb_agg(jsonb_build_object('id', t.id, 'de', t.de, 'nome', j.nome, 'oferta', public._lado_txt(t.oferta), 'pedido', public._lado_txt(t.pedido)) order by t.criado), '[]'::jsonb) into tro
    from public.trocas t join public.jogadores j on j.id = t.de where t.para = auth.uid() and t.estado = 'pendente';
  select coalesce(jsonb_agg(q.h2 order by q.criado desc), '[]'::jsonb) into his from (
    select d.criado, jsonb_build_object('de', a.nome, 'para', c.nome, 'estado', b.estado, 'eu_desafiei', d.de = auth.uid()) as h2
      from public.desafios d join public.jogadores a on a.id = d.de join public.jogadores c on c.id = d.para left join public.batalhas b on b.id = d.batalha
     where d.estado = 'aceito' and (d.de = auth.uid() or d.para = auth.uid()) order by d.criado desc limit 5) q;
  select to_jsonb(b) - 'sim' - 'meta' into bat from public.batalhas b where b.jogador = auth.uid() and b.estado = 'ativa' limit 1;
  return jsonb_build_object('desafios_recebidos', rec, 'desafios_enviados', env, 'trocas_recebidas', tro, 'batalha', bat, 'historico', his);
end $$;
grant execute on function public.desafio_pendencias() to authenticated;

-- ===== aplica o resultado de um duelo valendo em UM dos lados: HP/PP reais e, para o vencedor, XP.
-- p_time: [{id, hp, pp:[...]}]; p_exp: [{exp_base, nivel}] (Pokémon do outro lado que caíram); p_part: ids dos participantes.
create or replace function public.duelo_aplicar(p_row uuid, p_time jsonb, p_ganhou boolean, p_exp jsonb, p_part jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare b public.batalhas; m jsonb; pk public.pokemons; pk2 public.pokemons; novo jsonb; k int; ev jsonb := '[]'::jsonb; sel jsonb; part uuid[]; n int; x jsonb;
begin
  select * into b from public.batalhas where id = p_row for update;
  if not found or b.amistoso or b.aplicado then return '[]'::jsonb; end if;
  update public.batalhas set aplicado = true where id = b.id;
  for m in select * from jsonb_array_elements(p_time) loop
    select * into pk from public.pokemons where id = (m->>'id')::uuid and dono = b.jogador;
    if found then
      novo := '[]'::jsonb;
      for k in 0 .. jsonb_array_length(pk.golpes) - 1 loop
        novo := novo || jsonb_build_array((pk.golpes->k) || jsonb_build_object('pp', coalesce((m->'pp'->>k)::int, (pk.golpes->k->>'pp')::int)));
      end loop;
      update public.pokemons set hp_atual = greatest(0, least((m->>'hp')::int, hp_max)), golpes = novo where id = pk.id;
    end if;
  end loop;
  if p_ganhou and jsonb_array_length(coalesce(p_exp, '[]'::jsonb)) > 0 then
    select array_agg(distinct (e)::uuid) into part from jsonb_array_elements_text(coalesce(p_part, '[]'::jsonb)) e;
    n := coalesce(array_length(part, 1), 1);
    for pk in select * from public.pokemons where id = any(coalesce(part, '{}')) and dono = b.jogador and hp_atual > 0 loop
      for x in select * from jsonb_array_elements(p_exp) loop
        sel := jsonb_build_object('exp_base', greatest(1, floor((x->>'exp_base')::numeric / n)), 'nivel', (x->>'nivel')::int);
        select * into pk2 from public.pokemons where id = pk.id;
        ev := public._dar_exp(pk2, sel, ev);
      end loop;
    end loop;
  end if;
  return ev;
end $$;
revoke all on function public.duelo_aplicar(uuid, jsonb, boolean, jsonb, jsonb) from public, anon, authenticated;
grant execute on function public.duelo_aplicar(uuid, jsonb, boolean, jsonb, jsonb) to service_role;

-- ===== missões: o jogador desiste da missão ativa; o Mestre remove missões de jogadores
create or replace function public.missao_desistir() returns boolean language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if auth.uid() is null then raise exception 'Faça login primeiro.'; end if;
  delete from public.missao_jogador where jogador = auth.uid() and estado = 'ativa';
  get diagnostics n = row_count;
  return n > 0;
end $$;
grant execute on function public.missao_desistir() to authenticated;

create or replace function public.mestre_missoes_jogadores() returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public.eh_mestre() then raise exception 'Só o Mestre.'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('jogador', mj.jogador, 'nome', j.nome, 'missao', mj.missao, 'missao_nome', m.nome, 'estado', mj.estado, 'etapa', mj.etapa, 'total', jsonb_array_length(m.etapas) - 1)
                                    order by j.nome, m.nome)
                     from public.missao_jogador mj join public.jogadores j on j.id = mj.jogador join public.missoes m on m.id = mj.missao), '[]'::jsonb);
end $$;
grant execute on function public.mestre_missoes_jogadores() to authenticated;

create or replace function public.mestre_remover_missao(p_jogador uuid, p_missao text) returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.eh_mestre() then raise exception 'Só o Mestre.'; end if;
  delete from public.missao_jogador where jogador = p_jogador and missao = p_missao;
end $$;
grant execute on function public.mestre_remover_missao(uuid, text) to authenticated;
