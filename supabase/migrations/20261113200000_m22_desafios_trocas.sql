-- m22: desafios entre jogadores (1 PA para cada) e trocas de itens/Pokémon
create table if not exists public.desafios (
  id uuid primary key default gen_random_uuid(),
  de uuid not null references public.jogadores (id) on delete cascade,
  para uuid not null references public.jogadores (id) on delete cascade,
  estado text not null default 'pendente' check (estado in ('pendente', 'aceito', 'recusado', 'expirado')),
  batalha uuid references public.batalhas (id) on delete set null,
  criado timestamptz not null default now(), check (de <> para)
);
create table if not exists public.trocas (
  id uuid primary key default gen_random_uuid(),
  de uuid not null references public.jogadores (id) on delete cascade,
  para uuid not null references public.jogadores (id) on delete cascade,
  oferta jsonb not null default '{"pokemons":[],"itens":[]}'::jsonb,
  pedido jsonb not null default '{"pokemons":[],"itens":[]}'::jsonb,
  estado text not null default 'pendente' check (estado in ('pendente', 'aceita', 'recusada', 'cancelada')),
  criado timestamptz not null default now(), check (de <> para)
);
alter table public.desafios enable row level security; alter table public.trocas enable row level security;
drop policy if exists "des_partes" on public.desafios; create policy "des_partes" on public.desafios for select to authenticated using (de = auth.uid() or para = auth.uid());
drop policy if exists "tro_partes" on public.trocas; create policy "tro_partes" on public.trocas for select to authenticated using (de = auth.uid() or para = auth.uid());
grant select on public.desafios, public.trocas to authenticated;

create or replace function public.jogadores_lista() returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', j.id, 'nome', j.nome, 'aparencia', j.aparencia, 'mapa_id', j.mapa_id) order by j.nome), '[]'::jsonb)
    from public.jogadores j where j.id <> auth.uid() and auth.uid() is not null $$;
grant execute on function public.jogadores_lista() to authenticated;

-- Pokémon e itens de outro jogador, para montar uma troca
create or replace function public.perfil_troca(p_jogador uuid) returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'pokemons', coalesce((select jsonb_agg(jsonb_build_object('id', p.id, 'especie_id', p.especie_id, 'nome', coalesce(p.apelido, e.nome), 'nivel', p.nivel, 'brilhante', p.brilhante) order by p.nivel desc)
                            from public.pokemons p join public.especies e on e.id = p.especie_id where p.dono = p_jogador), '[]'::jsonb),
    'itens', coalesce((select jsonb_agg(jsonb_build_object('item', i.item, 'qtd', i.qtd) order by i.item) from public.inventario i where i.jogador = p_jogador and i.qtd > 0 and i.item not like '%ball'), '[]'::jsonb)) $$;
grant execute on function public.perfil_troca(uuid) to authenticated;

-- texto legível de um lado da troca
create or replace function public._lado_txt(p_lado jsonb) returns text language sql stable security definer set search_path = public as $$
  select coalesce(nullif(concat_ws(', ',
    (select string_agg(coalesce(p.apelido, e.nome) || ' Nv ' || p.nivel, ', ') from jsonb_array_elements(coalesce(p_lado -> 'pokemons', '[]'::jsonb)) x
       join public.pokemons p on p.id = (x #>> '{}')::uuid join public.especies e on e.id = p.especie_id),
    (select string_agg((x ->> 'qtd') || '× ' || (x ->> 'item'), ', ') from jsonb_array_elements(coalesce(p_lado -> 'itens', '[]'::jsonb)) x)), ''), 'nada') $$;
revoke all on function public._lado_txt(jsonb) from public, anon, authenticated;

-- ===== desafios
create or replace function public.desafio_enviar(p_alvo uuid) returns uuid language plpgsql security definer set search_path = public as $$
declare d uuid;
begin
  if auth.uid() is null then raise exception 'Faça login primeiro.'; end if;
  if p_alvo = auth.uid() or not exists (select 1 from public.jogadores where id = p_alvo) then raise exception 'Jogador inválido.'; end if;
  if not exists (select 1 from public.pokemons where dono = auth.uid() and posicao is not null and hp_atual > 0) then raise exception 'Você precisa de um Pokémon saudável no time.'; end if;
  if (select pa from public.jogadores where id = auth.uid()) < 1 and public._ev('pa_gratis', 0) = 0 then raise exception 'PA insuficiente: um desafio custa 1 PA.'; end if;
  update public.desafios set estado = 'expirado' where estado = 'pendente' and criado < now() - interval '10 minutes';
  if exists (select 1 from public.desafios where de = auth.uid() and para = p_alvo and estado = 'pendente') then raise exception 'Você já desafiou este jogador. Aguarde a resposta.'; end if;
  insert into public.desafios (de, para) values (auth.uid(), p_alvo) returning id into d;
  return d;
end $$;
grant execute on function public.desafio_enviar(uuid) to authenticated;

create or replace function public.desafio_responder(p_desafio uuid, p_aceitar boolean) returns jsonb language plpgsql security definer set search_path = public as $$
declare d public.desafios; eu public.jogadores; adv public.jogadores; b public.batalhas; ativo uuid; equipe jsonb;
begin
  if auth.uid() is null then raise exception 'Faça login primeiro.'; end if;
  select * into d from public.desafios where id = p_desafio and para = auth.uid() and estado = 'pendente' for update;
  if not found then raise exception 'Este desafio não está mais disponível.'; end if;
  if d.criado < now() - interval '10 minutes' then update public.desafios set estado = 'expirado' where id = d.id; raise exception 'O desafio expirou.'; end if;
  if not p_aceitar then update public.desafios set estado = 'recusado' where id = d.id; return jsonb_build_object('aceito', false); end if;
  if not exists (select 1 from public.pokemons where dono = d.para and posicao is not null and hp_atual > 0) then raise exception 'Você precisa de um Pokémon saudável no time.'; end if;
  select id into ativo from public.pokemons where dono = d.de and posicao is not null and hp_atual > 0 order by posicao limit 1;
  if ativo is null then raise exception 'O desafiante está sem Pokémon saudáveis.'; end if;
  perform public._gastar_pa(d.de);      -- 1 PA de cada um
  perform public._gastar_pa(d.para);
  -- o Pokémon do defensor luta controlado pelo sistema, com o time dele no estado atual (HP cheio)
  select coalesce(jsonb_agg(jsonb_build_object('especie_id', e.id, 'nome', coalesce(p.apelido, e.nome), 'nivel', p.nivel, 'natureza', p.natureza, 'exp_base', floor(e.exp_base),
           'golpes', (select jsonb_agg(jsonb_build_object('id', (x ->> 'id')::int, 'pp', g.pp) order by o) from jsonb_array_elements(p.golpes) with ordinality t(x, o) join public.golpes g on g.id = (t.x ->> 'id')::int))
           order by p.posicao), '[]'::jsonb)
    into equipe from public.pokemons p join public.especies e on e.id = p.especie_id where p.dono = d.para and p.posicao is not null;
  insert into public.batalhas (jogador, selvagem, ativo, tipo, treinador, adversarios) values (d.de, '{}'::jsonb, ativo, 'treinador', null, equipe) returning * into b;
  update public.desafios set estado = 'aceito', batalha = b.id where id = d.id;
  return jsonb_build_object('aceito', true);
end $$;
grant execute on function public.desafio_responder(uuid, boolean) to authenticated;

-- o desafiante inicia a luta depois que o outro aceitou: devolve a batalha ativa
create or replace function public.desafio_pendencias() returns jsonb language plpgsql security definer set search_path = public as $$
declare rec jsonb; env jsonb; tro jsonb; bat jsonb; his jsonb;
begin
  if auth.uid() is null then return null; end if;
  update public.desafios set estado = 'expirado' where estado = 'pendente' and criado < now() - interval '10 minutes';
  select coalesce(jsonb_agg(jsonb_build_object('id', d.id, 'de', d.de, 'nome', j.nome) order by d.criado), '[]'::jsonb) into rec
    from public.desafios d join public.jogadores j on j.id = d.de where d.para = auth.uid() and d.estado = 'pendente';
  select coalesce(jsonb_agg(jsonb_build_object('id', d.id, 'para', d.para, 'nome', j.nome, 'estado', d.estado) order by d.criado), '[]'::jsonb) into env
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

create or replace function public.desafio_cancelar(p_desafio uuid) returns void language sql security definer set search_path = public as $$
  update public.desafios set estado = 'expirado' where id = p_desafio and de = auth.uid() and estado = 'pendente' $$;
grant execute on function public.desafio_cancelar(uuid) to authenticated;

-- ===== trocas
create or replace function public._transferir_pokemon(p_pk uuid, p_novo uuid) returns void language plpgsql security definer set search_path = public as $$
declare slot int; vc int; vs int;
begin
  select min(s) into slot from generate_series(1, 6) s where not exists (select 1 from public.pokemons where dono = p_novo and posicao = s);
  if slot is null then
    select o_caixa, o_slot into vc, vs from public._vaga_caixa(p_novo);
    if vc is null then raise exception 'As caixas do outro jogador estão cheias.'; end if;
  end if;
  update public.jogadores set seguidor = null where seguidor = p_pk;
  update public.pokemons set dono = p_novo, posicao = slot, caixa = vc, slot_caixa = vs where id = p_pk;
  insert into public.pokedex (jogador, especie_id, capturado) select p_novo, especie_id, true from public.pokemons where id = p_pk
  on conflict (jogador, especie_id) do update set capturado = true;
end $$;
revoke all on function public._transferir_pokemon(uuid, uuid) from public, anon, authenticated;

create or replace function public._validar_lado(p_dono uuid, p_lado jsonb) returns void language plpgsql security definer set search_path = public as $$
declare x jsonb;
begin
  for x in select * from jsonb_array_elements(coalesce(p_lado -> 'pokemons', '[]'::jsonb)) loop
    if not exists (select 1 from public.pokemons where id = (x #>> '{}')::uuid and dono = p_dono) then raise exception 'Um dos Pokémon da troca não pertence mais ao dono.'; end if;
  end loop;
  for x in select * from jsonb_array_elements(coalesce(p_lado -> 'itens', '[]'::jsonb)) loop
    if (x ->> 'qtd')::int < 1 or not exists (select 1 from public.inventario where jogador = p_dono and item = x ->> 'item' and qtd >= (x ->> 'qtd')::int) then
      raise exception 'Falta quantidade de um dos itens da troca.';
    end if;
  end loop;
end $$;
revoke all on function public._validar_lado(uuid, jsonb) from public, anon, authenticated;

create or replace function public.troca_propor(p_para uuid, p_oferta jsonb, p_pedido jsonb) returns uuid language plpgsql security definer set search_path = public as $$
declare t uuid;
begin
  if auth.uid() is null then raise exception 'Faça login primeiro.'; end if;
  if p_para = auth.uid() or not exists (select 1 from public.jogadores where id = p_para) then raise exception 'Jogador inválido.'; end if;
  if jsonb_array_length(coalesce(p_oferta -> 'pokemons', '[]')) + jsonb_array_length(coalesce(p_oferta -> 'itens', '[]'))
   + jsonb_array_length(coalesce(p_pedido -> 'pokemons', '[]')) + jsonb_array_length(coalesce(p_pedido -> 'itens', '[]')) = 0 then raise exception 'A troca está vazia.'; end if;
  perform public._validar_lado(auth.uid(), p_oferta);
  perform public._validar_lado(p_para, p_pedido);
  insert into public.trocas (de, para, oferta, pedido) values (auth.uid(), p_para, p_oferta, p_pedido) returning id into t;
  return t;
end $$;
grant execute on function public.troca_propor(uuid, jsonb, jsonb) to authenticated;

create or replace function public.troca_responder(p_troca uuid, p_aceitar boolean) returns void language plpgsql security definer set search_path = public as $$
declare t public.trocas; x jsonb;
begin
  if auth.uid() is null then raise exception 'Faça login primeiro.'; end if;
  select * into t from public.trocas where id = p_troca and estado = 'pendente' and (para = auth.uid() or de = auth.uid()) for update;
  if not found then raise exception 'Esta troca não está mais disponível.'; end if;
  if not p_aceitar then update public.trocas set estado = case when de = auth.uid() then 'cancelada' else 'recusada' end where id = t.id; return; end if;
  if t.para <> auth.uid() then raise exception 'Só quem recebeu a proposta pode aceitar.'; end if;
  if exists (select 1 from public.batalhas where jogador in (t.de, t.para) and estado = 'ativa') then raise exception 'Termine as batalhas antes de trocar.'; end if;
  perform public._validar_lado(t.de, t.oferta);
  perform public._validar_lado(t.para, t.pedido);
  -- cada um precisa ficar com ao menos um Pokémon
  if (select count(*) from public.pokemons where dono = t.de) - jsonb_array_length(coalesce(t.oferta -> 'pokemons', '[]')) + jsonb_array_length(coalesce(t.pedido -> 'pokemons', '[]')) < 1
     or (select count(*) from public.pokemons where dono = t.para) - jsonb_array_length(coalesce(t.pedido -> 'pokemons', '[]')) + jsonb_array_length(coalesce(t.oferta -> 'pokemons', '[]')) < 1 then
    raise exception 'Cada jogador precisa ficar com ao menos um Pokémon.';
  end if;
  for x in select * from jsonb_array_elements(coalesce(t.oferta -> 'pokemons', '[]')) loop perform public._transferir_pokemon((x #>> '{}')::uuid, t.para); end loop;
  for x in select * from jsonb_array_elements(coalesce(t.pedido -> 'pokemons', '[]')) loop perform public._transferir_pokemon((x #>> '{}')::uuid, t.de); end loop;
  for x in select * from jsonb_array_elements(coalesce(t.oferta -> 'itens', '[]')) loop
    update public.inventario set qtd = qtd - (x ->> 'qtd')::int where jogador = t.de and item = x ->> 'item';
    insert into public.inventario (jogador, item, qtd) values (t.para, x ->> 'item', (x ->> 'qtd')::int) on conflict (jogador, item) do update set qtd = public.inventario.qtd + excluded.qtd;
  end loop;
  for x in select * from jsonb_array_elements(coalesce(t.pedido -> 'itens', '[]')) loop
    update public.inventario set qtd = qtd - (x ->> 'qtd')::int where jogador = t.para and item = x ->> 'item';
    insert into public.inventario (jogador, item, qtd) values (t.de, x ->> 'item', (x ->> 'qtd')::int) on conflict (jogador, item) do update set qtd = public.inventario.qtd + excluded.qtd;
  end loop;
  update public.trocas set estado = 'aceita' where id = t.id;
end $$;
grant execute on function public.troca_responder(uuid, boolean) to authenticated;
