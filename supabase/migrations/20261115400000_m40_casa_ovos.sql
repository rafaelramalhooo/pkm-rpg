-- m40: Casa do jogador (níveis, incubadoras) + Ovos que chocam andando.

create table if not exists public.casa_nivel_catalogo (
  nivel int primary key,
  nome text not null,
  incubadoras int not null default 1,
  custo int not null default 0,
  descricao text not null default ''
);
create table if not exists public.casas (
  jogador uuid primary key references public.jogadores (id) on delete cascade,
  nivel int not null default 1 references public.casa_nivel_catalogo (nivel),
  criado_em timestamptz not null default now()
);
create table if not exists public.ovos (
  id uuid primary key default gen_random_uuid(),
  jogador uuid not null references public.jogadores (id) on delete cascade,
  especie_id int not null references public.especies (id),
  passos_total int not null check (passos_total > 0),
  passos int not null default 0,
  incubando boolean not null default false,
  origem text,
  criado_em timestamptz not null default now()
);
create index if not exists ovos_jogador on public.ovos (jogador);
alter table public.casa_nivel_catalogo enable row level security;
alter table public.casas enable row level security;
alter table public.ovos enable row level security;
drop policy if exists cnc_leitura on public.casa_nivel_catalogo;
create policy cnc_leitura on public.casa_nivel_catalogo for select to authenticated using (true);
drop policy if exists casas_dono on public.casas;
create policy casas_dono on public.casas for select to authenticated using (jogador = auth.uid() or public.eh_mestre());
grant select on public.casa_nivel_catalogo, public.casas to authenticated;

insert into public.casa_nivel_catalogo (nivel, nome, incubadoras, custo, descricao) values
  (1, 'Casinha', 1, 0, 'Uma incubadora para um ovo por vez.'),
  (2, 'Casa com quintal', 2, 3000, 'Duas incubadoras.'),
  (3, 'Casarão', 3, 8000, 'Três incubadoras.')
on conflict (nivel) do nothing;
insert into public.config (chave, valor) values ('ovo_nivel', '5'::jsonb), ('ovo_passos_dia_max', '600'::jsonb) on conflict (chave) do nothing;

-- passos andados (validados pelo servidor, pois a posição só muda por mover()) avançam os ovos incubando
create or replace function public._tg_passos_ovo() returns trigger language plpgsql security definer set search_path = public as $$
declare dist int; usado bigint; add int; d date := public._dia_jogo(); teto int := public._cfg_int('ovo_passos_dia_max', 600);
begin
  begin
    if old.mapa_id = new.mapa_id and (old.x <> new.x or old.y <> new.y) and public._modulo('casa')
       and exists (select 1 from public.ovos where jogador = new.id and incubando) then
      dist := least(greatest(abs(new.x - old.x), abs(new.y - old.y)), 12);
      select coalesce(valor, 0) into usado from public.contadores where jogador = new.id and chave = 'passos_ovo' and periodo = 'd:' || d;
      add := least(dist, greatest(teto - coalesce(usado, 0), 0));
      if add > 0 then
        update public.ovos set passos = least(passos_total, passos + add) where jogador = new.id and incubando;
        insert into public.contadores (jogador, chave, periodo, valor) values (new.id, 'passos_ovo', 'd:' || d, add)
        on conflict (jogador, chave, periodo) do update set valor = public.contadores.valor + excluded.valor;
      end if;
    end if;
  exception when others then
    raise warning 'tg_passos_ovo falhou: %', sqlerrm;
  end;
  return new;
end $$;
drop trigger if exists tg_passos_ovo on public.jogadores;
create trigger tg_passos_ovo after update of x, y on public.jogadores for each row execute function public._tg_passos_ovo();

create or replace function public.casa_estado() returns jsonb language plpgsql security definer set search_path = public as $$
declare n int; cat public.casa_nivel_catalogo; prox public.casa_nivel_catalogo; d date := public._dia_jogo();
begin
  if auth.uid() is null or not public._modulo('casa') then return jsonb_build_object('ativo', false); end if;
  insert into public.casas (jogador) values (auth.uid()) on conflict do nothing;
  select c.nivel into n from public.casas c where c.jogador = auth.uid();
  select * into cat from public.casa_nivel_catalogo where nivel = n;
  select * into prox from public.casa_nivel_catalogo where nivel = n + 1;
  return jsonb_build_object('ativo', true, 'nivel', n, 'nome', cat.nome, 'incubadoras', cat.incubadoras,
    'proximo', case when prox.nivel is null then null else jsonb_build_object('nivel', prox.nivel, 'nome', prox.nome, 'custo', prox.custo, 'incubadoras', prox.incubadoras, 'descricao', prox.descricao) end,
    'passos_hoje', coalesce((select valor from public.contadores where jogador = auth.uid() and chave = 'passos_ovo' and periodo = 'd:' || d), 0),
    'passos_max_dia', public._cfg_int('ovo_passos_dia_max', 600),
    'dinheiro', (select dinheiro from public.jogadores where id = auth.uid()),
    'aqui', (select public._poi_aqui(j, 'casa_jogador') from public.jogadores j where j.id = auth.uid()),
    'ovos', coalesce((select jsonb_agg(jsonb_build_object('id', o.id, 'passos', o.passos, 'passos_total', o.passos_total, 'incubando', o.incubando, 'pronto', o.passos >= o.passos_total, 'origem', o.origem) order by o.criado_em)
                        from public.ovos o where o.jogador = auth.uid()), '[]'::jsonb));
end $$;

create or replace function public.casa_melhorar() returns void language plpgsql security definer set search_path = public as $$
declare v_j public.jogadores; n int; prox public.casa_nivel_catalogo;
begin
  if auth.uid() is null then raise exception 'Faça login primeiro.'; end if;
  if not public._modulo('casa') then raise exception 'A casa não está ativa.'; end if;
  select * into v_j from public.jogadores where id = auth.uid() for update;
  if not public._poi_aqui(v_j, 'casa_jogador') then raise exception 'Só dá para reformar a casa estando nela.'; end if;
  insert into public.casas (jogador) values (v_j.id) on conflict do nothing;
  select nivel into n from public.casas where jogador = v_j.id;
  select * into prox from public.casa_nivel_catalogo where nivel = n + 1;
  if prox.nivel is null then raise exception 'Sua casa já está no nível máximo.'; end if;
  if v_j.dinheiro < prox.custo then raise exception 'Faltam % de dinheiro.', prox.custo - v_j.dinheiro; end if;
  update public.jogadores set dinheiro = dinheiro - prox.custo where id = v_j.id;
  update public.casas set nivel = prox.nivel where jogador = v_j.id;
end $$;

create or replace function public.ovo_incubar(p_ovo uuid, p_ligar boolean) returns void language plpgsql security definer set search_path = public as $$
declare n int; lim int; ativos int;
begin
  if auth.uid() is null then raise exception 'Faça login primeiro.'; end if;
  if not exists (select 1 from public.ovos where id = p_ovo and jogador = auth.uid()) then raise exception 'Ovo não encontrado.'; end if;
  if p_ligar then
    insert into public.casas (jogador) values (auth.uid()) on conflict do nothing;
    select c.nivel into n from public.casas c where c.jogador = auth.uid();
    select incubadoras into lim from public.casa_nivel_catalogo where nivel = n;
    select count(*) into ativos from public.ovos where jogador = auth.uid() and incubando and id <> p_ovo;
    if ativos >= lim then raise exception 'Todas as incubadoras estão ocupadas (%).', lim; end if;
  end if;
  update public.ovos set incubando = p_ligar where id = p_ovo;
end $$;

create or replace function public.ovo_chocar(p_ovo uuid) returns jsonb language plpgsql security definer set search_path = public as $$
declare o public.ovos; pk public.pokemons; nome text;
begin
  if auth.uid() is null then raise exception 'Faça login primeiro.'; end if;
  select * into o from public.ovos where id = p_ovo and jogador = auth.uid() for update;
  if not found then raise exception 'Ovo não encontrado.'; end if;
  if o.passos < o.passos_total then raise exception 'O ovo ainda não está pronto. Continue andando!'; end if;
  pk := public._novo_pokemon(auth.uid(), o.especie_id, public._cfg_int('ovo_nivel', 5));
  delete from public.ovos where id = o.id;
  select e.nome into nome from public.especies e where e.id = o.especie_id;
  perform public._atividade(auth.uid(), 'ovo', o.especie_id::text);
  return jsonb_build_object('nome', nome, 'pokemon', pk.id, 'time', pk.posicao is not null);
end $$;

create or replace function public.mestre_ovo_dar(p_jogador uuid, p_especie int, p_passos int default 1000) returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.eh_mestre() then raise exception 'Só o Mestre.'; end if;
  if not exists (select 1 from public.especies where id = p_especie) then raise exception 'Espécie inexistente.'; end if;
  if p_passos < 1 or p_passos > 100000 then raise exception 'Passos inválidos.'; end if;
  insert into public.ovos (jogador, especie_id, passos_total, origem) values (p_jogador, p_especie, p_passos, 'Mestre');
end $$;

do $$ declare f text; begin
  foreach f in array array['casa_estado()', 'casa_melhorar()', 'ovo_incubar(uuid,boolean)', 'ovo_chocar(uuid)', 'mestre_ovo_dar(uuid,int,int)'] loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;

-- ---------- prêmios podem incluir um ovo: {"ovo":{"especie":25,"passos":1500}} ----------

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
  if p ? 'ovo' and exists (select 1 from public.especies where id = (p -> 'ovo' ->> 'especie')::int) then
    insert into public.ovos (jogador, especie_id, passos_total, origem) values (p_j, (p -> 'ovo' ->> 'especie')::int, greatest(coalesce((p -> 'ovo' ->> 'passos')::int, 1000), 1), 'Prêmio');
    res := res || jsonb_build_object('ovo', p -> 'ovo');
  end if;
  return res;
end $$;

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
  if p ? 'ovo' and (not exists (select 1 from public.especies where id = (p -> 'ovo' ->> 'especie')::int) or coalesce((p -> 'ovo' ->> 'passos')::int, 0) < 1) then raise exception 'Ovo inválido (precisa de especie e passos).'; end if;
  foreach t in array array['titulo', 'moldura'] loop
    if coalesce(p ->> t, '') <> '' and not exists (select 1 from public.cosmeticos_catalogo where id = p ->> t) then raise exception 'Cosmético inexistente: %.', p ->> t; end if;
  end loop;
end $$;

-- reiniciar personagem também zera o progresso de engajamento
create or replace function public._reiniciar(p_jogador uuid) returns text language plpgsql security definer set search_path = public as $$
declare v_nome text; s record;
begin
  select nome into v_nome from public.jogadores where id = p_jogador;
  if not found then raise exception 'Jogador não encontrado.'; end if;
  select * into s from public._spawn_inicial();
  delete from public.ofertas where jogador = p_jogador;
  delete from public.batalhas where jogador = p_jogador;
  delete from public.treinadores_vencidos where jogador = p_jogador;
  delete from public.pokemons where dono = p_jogador;
  delete from public.inventario where jogador = p_jogador;
  delete from public.pokedex where jogador = p_jogador;
  delete from public.poi_usos where jogador = p_jogador;
  delete from public.checkin_jogador where jogador = p_jogador;
  delete from public.checkin_semana_resgate where jogador = p_jogador;
  delete from public.atividades where jogador = p_jogador;
  delete from public.contadores where jogador = p_jogador;
  delete from public.participacao_dia where jogador = p_jogador;
  delete from public.conquistas_jogador where jogador = p_jogador;
  delete from public.cosmeticos_jogador where jogador = p_jogador;
  delete from public.ranking_pontos where jogador = p_jogador;
  delete from public.ranking_eventos where jogador = p_jogador;
  delete from public.ranking_premios_jogador where jogador = p_jogador;
  delete from public.treinadores_revanche where jogador = p_jogador;
  delete from public.miniquests_jogador where jogador = p_jogador;
  delete from public.ovos where jogador = p_jogador;
  delete from public.casas where jogador = p_jogador;
  update public.jogadores set insignias = '{}', campeao = false, titulo_ativo = null, moldura_ativa = null where id = p_jogador;
  update public.jogadores
     set mapa_id = s.p_mapa, x = s.p_x, y = s.p_y, direcao = 'baixo', rolagem = null,
         pa = coalesce((select (valor #>> '{}')::smallint from public.config where chave = 'pa_por_dia'), 30),
         dinheiro = 1000, posicao_em = now()
   where id = p_jogador;
  return v_nome;
end $$;
