-- m74: Liga Pokémon (torneio de eliminatória simples, uma sessão online, regras normais e motor do Showdown).
-- Fluxo: Mestre abre inscrições (comunicado) → jogadores com 8 insígnias se inscrevem num Centro Pokémon → Mestre fecha e sorteia o
-- chaveamento (jogadores + NPCs especiais do Mestre + NPCs aleatórios até completar o tamanho) → Mestre inicia cada rodada →
-- jogador × jogador usa o duelo ao vivo amistoso (sem PA, HP/PP cheios); jogador × NPC usa a batalha de treinador (sem XP, sem dinheiro);
-- NPC × NPC é resolvido no servidor. Time curado entre as rodadas. Campeão, vice e semifinalistas ganham prêmio e título (configuráveis).
-- Substitui a antiga Liga de 4 salões + Campeão como "final de jogo"; os salões continuam como locais de treino.

alter table public.batalhas add column if not exists liga_partida uuid;

-- ---------- tabelas ----------
create table if not exists public.liga_npcs_especiais (
  id uuid primary key default gen_random_uuid(),
  nome text not null check (char_length(nome) between 2 and 30),
  classe text not null default 'Campeão',
  aparencia smallint not null default 12,
  falas jsonb not null default '{}'::jsonb,
  equipe jsonb not null,
  criado timestamptz not null default now()
);

create table if not exists public.liga_edicoes (
  id uuid primary key default gen_random_uuid(),
  nome text not null default 'Liga Pokémon',
  estado text not null default 'inscricoes' check (estado in ('inscricoes', 'fechada', 'sorteada', 'andamento', 'finalizada', 'cancelada')),
  tamanho int not null default 32 check (tamanho in (8, 16, 32, 64)),
  inscricoes_ate timestamptz,
  inicio_em timestamptz,
  rodada int not null default 0,
  prazo_min int not null default 10 check (prazo_min between 1 and 120),
  premios jsonb not null default '{}'::jsonb,
  especiais uuid[] not null default '{}',
  campeao_nome text, vice_nome text,
  criado timestamptz not null default now(),
  criado_por uuid references public.jogadores (id) on delete set null
);
create unique index if not exists liga_uma_ativa on public.liga_edicoes ((true)) where estado in ('inscricoes', 'fechada', 'sorteada', 'andamento');

create table if not exists public.liga_inscricoes (
  edicao uuid not null references public.liga_edicoes (id) on delete cascade,
  jogador uuid not null references public.jogadores (id) on delete cascade,
  em timestamptz not null default now(),
  primary key (edicao, jogador)
);

create table if not exists public.liga_participantes (
  id uuid primary key default gen_random_uuid(),
  edicao uuid not null references public.liga_edicoes (id) on delete cascade,
  pos int not null default 0,
  tipo text not null check (tipo in ('jogador', 'especial', 'aleatorio')),
  jogador uuid references public.jogadores (id) on delete set null,
  nome text not null, classe text, aparencia smallint,
  treinador text,
  equipe jsonb, falas jsonb,
  ref int not null default 5,
  eliminado boolean not null default false
);
create index if not exists liga_part_edicao on public.liga_participantes (edicao, pos);

create table if not exists public.liga_partidas (
  id uuid primary key default gen_random_uuid(),
  edicao uuid not null references public.liga_edicoes (id) on delete cascade,
  rodada int not null, slot int not null,
  a uuid references public.liga_participantes (id) on delete cascade,
  b uuid references public.liga_participantes (id) on delete cascade,
  vencedor uuid references public.liga_participantes (id) on delete set null,
  estado text not null default 'aguardando' check (estado in ('aguardando', 'em_curso', 'encerrada')),
  motivo text, prazo timestamptz,
  pronto_a boolean not null default false, pronto_b boolean not null default false,
  batalha uuid,
  unique (edicao, rodada, slot)
);

create table if not exists public.liga_resultados (
  id bigint generated always as identity primary key,
  edicao uuid not null references public.liga_edicoes (id) on delete cascade,
  jogador uuid not null references public.jogadores (id) on delete cascade,
  colocacao text not null, premio jsonb not null default '{}'::jsonb,
  visto boolean not null default false, criado_em timestamptz not null default now()
);
create index if not exists liga_res_jogador on public.liga_resultados (jogador, visto);

alter table public.liga_npcs_especiais enable row level security;
alter table public.liga_edicoes enable row level security;
alter table public.liga_inscricoes enable row level security;
alter table public.liga_participantes enable row level security;
alter table public.liga_partidas enable row level security;
alter table public.liga_resultados enable row level security;

insert into public.cosmeticos_catalogo (id, tipo, nome, estilo) values
  ('campeao_liga', 'titulo', 'Campeão da Liga', '{}'),
  ('vice_liga', 'titulo', 'Vice-campeão da Liga', '{}'),
  ('semi_liga', 'titulo', 'Semifinalista da Liga', '{}')
on conflict (id) do nothing;

-- ---------- ajudantes internos ----------
create or replace function public._liga_rodadas(p_tam int) returns int language sql immutable as $$
  select case p_tam when 8 then 3 when 16 then 4 when 32 then 5 else 6 end $$;

create or replace function public._liga_curar(p_j uuid) returns void language plpgsql security definer set search_path = public as $$
begin
  update public.pokemons p set hp_atual = hp_max,
    golpes = coalesce((select jsonb_agg(jsonb_build_object('id', (g->>'id')::int, 'pp', (select pp from public.golpes where id = (g->>'id')::int)))
                         from jsonb_array_elements(p.golpes) g), '[]'::jsonb)
   where dono = p_j;
end $$;

create or replace function public._liga_liberar(p_j uuid, p_partida uuid) returns void language plpgsql security definer set search_path = public as $$
begin
  update public.batalhas set estado = case when tipo = 'selvagem' then 'fuga' else 'derrota' end
   where jogador = p_j and estado = 'ativa' and liga_partida is distinct from p_partida;
  perform public._liga_curar(p_j);
end $$;

create or replace function public._liga_equipe_aleatoria(p_ref int, p_n int) returns jsonb language plpgsql security definer set search_path = public as $$
declare r jsonb := '[]'::jsonb; l record; cur int; nxt int; lvl int; i int; dif int := public._dificuldade();
begin
  for l in select e.id from public.especies e
            where e.id <= 151 and e.id not in (144, 145, 146, 150, 151)
              and not exists (select 1 from public.evolucoes v where v.para = e.id)
            order by random() limit greatest(1, least(6, p_n)) loop
    lvl := least(1000, greatest(1, p_ref + dif - 2 + floor(random() * 4)::int));
    cur := l.id;
    for i in 1 .. 3 loop
      nxt := null;
      select v.para into nxt from public.evolucoes v
       where v.de = cur and ((v.nivel is not null and v.nivel <= lvl) or (v.nivel is null and v.item is not null and lvl >= 36))
       order by random() limit 1;
      exit when nxt is null;
      cur := nxt;
    end loop;
    r := r || public._equipe_treinador(jsonb_build_array(jsonb_build_object('especie', cur, 'nivel', lvl)));
  end loop;
  return r;
end $$;

create or replace function public._liga_forca(p public.liga_participantes) returns numeric language sql stable security definer set search_path = public as $$
  select case when p.tipo = 'especial' and p.equipe is not null then
           coalesce((select sum((x->>'nivel')::numeric * (e.hp + e.atk + e.def + e.spa + e.spd + e.spe) / 100.0)
                       from jsonb_array_elements(p.equipe) x join public.especies e on e.id = (x->>'especie')::int), 1)
         else 6 * greatest(1, p.ref + public._dificuldade() - 0.5) * 4.2 end $$;

create or replace function public._liga_chave(p_e uuid) returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'participantes', coalesce((select jsonb_agg(jsonb_build_object('id', x.id, 'pos', x.pos, 'tipo', x.tipo, 'nome', x.nome, 'classe', x.classe, 'aparencia', x.aparencia,
                       'eliminado', x.eliminado, 'eu', x.jogador is not null and x.jogador = auth.uid(),
                       'presente', case when x.jogador is null then null else (select jj.mapa_id = 'plato' from public.jogadores jj where jj.id = x.jogador) end) order by x.pos)
                     from public.liga_participantes x where x.edicao = p_e), '[]'::jsonb),
    'partidas', coalesce((select jsonb_agg(jsonb_build_object('id', q.id, 'rodada', q.rodada, 'slot', q.slot, 'a', q.a, 'b', q.b, 'vencedor', q.vencedor,
                       'estado', q.estado, 'motivo', q.motivo, 'prazo', q.prazo, 'pa', q.pronto_a, 'pb', q.pronto_b) order by q.rodada, q.slot)
                     from public.liga_partidas q where q.edicao = p_e), '[]'::jsonb)) $$;

-- ---------- fim de partida, chaveamento e premiação ----------
create or replace function public._liga_finalizar(p_e uuid, p public.liga_partidas, w public.liga_participantes, l public.liga_participantes) returns void language plpgsql security definer set search_path = public as $$
declare e public.liga_edicoes; r jsonb; q record; x public.liga_participantes;
begin
  select * into e from public.liga_edicoes where id = p_e;
  update public.liga_edicoes set estado = 'finalizada', campeao_nome = w.nome, vice_nome = l.nome where id = p_e;
  if w.jogador is not null then
    r := public._conceder(w.jogador, coalesce(e.premios -> 'campeao', '{}'::jsonb));
    update public.jogadores set campeao = true where id = w.jogador;
    insert into public.liga_resultados (edicao, jogador, colocacao, premio) values (p_e, w.jogador, 'Campeão', r);
  end if;
  if l.jogador is not null then
    r := public._conceder(l.jogador, coalesce(e.premios -> 'vice', '{}'::jsonb));
    insert into public.liga_resultados (edicao, jogador, colocacao, premio) values (p_e, l.jogador, 'Vice-campeão', r);
  end if;
  for q in select case when s.vencedor = s.a then s.b else s.a end as perd from public.liga_partidas s where s.edicao = p_e and s.rodada = p.rodada - 1 loop
    select * into x from public.liga_participantes where id = q.perd;
    if x.jogador is not null then
      r := public._conceder(x.jogador, coalesce(e.premios -> 'semi', '{}'::jsonb));
      insert into public.liga_resultados (edicao, jogador, colocacao, premio) values (p_e, x.jogador, 'Semifinalista', r);
    end if;
  end loop;
  if coalesce(e.premios -> 'participacao', '{}'::jsonb) <> '{}'::jsonb then
    for q in select pp.jogador from public.liga_participantes pp where pp.edicao = p_e and pp.jogador is not null
               and not exists (select 1 from public.liga_resultados rr where rr.edicao = p_e and rr.jogador = pp.jogador) loop
      r := public._conceder(q.jogador, e.premios -> 'participacao');
      insert into public.liga_resultados (edicao, jogador, colocacao, premio) values (p_e, q.jogador, 'Participante', r);
    end loop;
  end if;
  delete from public.treinadores where id like 'lgn\_' || left(replace(p_e::text, '-', ''), 8) || '\_%';
end $$;

create or replace function public._liga_encerrar(p_partida uuid, p_vencedor uuid, p_motivo text) returns void language plpgsql security definer set search_path = public as $$
declare p public.liga_partidas; nxt public.liga_partidas; w public.liga_participantes; l public.liga_participantes; perd uuid;
begin
  select * into p from public.liga_partidas where id = p_partida for update;
  if p.id is null or p.estado = 'encerrada' then return; end if;
  if p_vencedor is distinct from p.a and p_vencedor is distinct from p.b then return; end if;
  perd := case when p.a = p_vencedor then p.b else p.a end;
  select * into w from public.liga_participantes where id = p_vencedor;
  select * into l from public.liga_participantes where id = perd;
  update public.liga_partidas set vencedor = p_vencedor, estado = 'encerrada', motivo = p_motivo where id = p.id;
  update public.liga_participantes set eliminado = true where id = perd;
  update public.batalhas set estado = case when jogador is not distinct from l.jogador then 'derrota' else 'fuga' end
   where liga_partida = p.id and estado = 'ativa';
  if w.jogador is not null then perform public._liga_curar(w.jogador); end if;
  if l.jogador is not null then perform public._liga_curar(l.jogador); end if;
  select * into nxt from public.liga_partidas where edicao = p.edicao and rodada = p.rodada + 1 and slot = (p.slot + 1) / 2;
  if nxt.id is not null then
    if p.slot % 2 = 1 then update public.liga_partidas set a = p_vencedor where id = nxt.id;
    else update public.liga_partidas set b = p_vencedor where id = nxt.id; end if;
  else
    perform public._liga_finalizar(p.edicao, p, w, l);
  end if;
end $$;

create or replace function public._liga_resolver_npc(p_partida uuid) returns void language plpgsql security definer set search_path = public as $$
declare p public.liga_partidas; a public.liga_participantes; b public.liga_participantes; fa numeric; fb numeric;
begin
  select * into p from public.liga_partidas where id = p_partida;
  select * into a from public.liga_participantes where id = p.a;
  select * into b from public.liga_participantes where id = p.b;
  fa := power(greatest(1, public._liga_forca(a)), 3); fb := power(greatest(1, public._liga_forca(b)), 3);
  perform public._liga_encerrar(p.id, case when random() < fa / (fa + fb) then p.a else p.b end, 'simulada');
end $$;

create or replace function public._liga_prazos(p_e uuid) returns void language plpgsql security definer set search_path = public as $$
declare p public.liga_partidas; pa_ public.liga_participantes; pb_ public.liga_participantes; win uuid;
begin
  for p in select * from public.liga_partidas where edicao = p_e and estado = 'em_curso' and prazo is not null and prazo < now() order by rodada, slot loop
    select * into pa_ from public.liga_participantes where id = p.a;
    select * into pb_ from public.liga_participantes where id = p.b;
    if pa_.tipo = 'jogador' and pb_.tipo = 'jogador' then
      if p.pronto_a and p.pronto_b then continue; end if;
      win := case when p.pronto_a then p.a when p.pronto_b then p.b when random() < 0.5 then p.a else p.b end;
      perform public._liga_encerrar(p.id, win, 'wo');
    elsif pa_.tipo = 'jogador' or pb_.tipo = 'jogador' then
      if (pa_.tipo = 'jogador' and p.pronto_a) or (pb_.tipo = 'jogador' and p.pronto_b) then continue; end if;
      perform public._liga_encerrar(p.id, case when pa_.tipo = 'jogador' then p.b else p.a end, 'wo');
    end if;
  end loop;
end $$;

create or replace function public._liga_fim_batalha(b public.batalhas) returns void language plpgsql security definer set search_path = public as $$
declare p public.liga_partidas; mine uuid;
begin
  select * into p from public.liga_partidas where id = b.liga_partida;
  if p.id is null or p.estado = 'encerrada' then return; end if;
  select id into mine from public.liga_participantes where edicao = p.edicao and jogador = b.jogador;
  if mine is null then return; end if;
  perform public._liga_encerrar(p.id, case when b.estado = 'vitoria' then mine when p.a = mine then p.b else p.a end, 'luta');
end $$;

create or replace function public._tg_liga_batalha() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.liga_partida is not null and old.estado = 'ativa' and new.estado <> 'ativa' then
    begin
      perform public._liga_fim_batalha(new);
    exception when others then
      raise warning 'tg_liga_batalha falhou: %', sqlerrm;
    end;
  end if;
  return new;
end $$;
drop trigger if exists tg_liga_batalha on public.batalhas;
create trigger tg_liga_batalha after update of estado on public.batalhas for each row execute function public._tg_liga_batalha();

revoke all on function public._liga_rodadas(int), public._liga_curar(uuid), public._liga_liberar(uuid, uuid), public._liga_equipe_aleatoria(int, int),
  public._liga_forca(public.liga_participantes), public._liga_chave(uuid), public._liga_finalizar(uuid, public.liga_partidas, public.liga_participantes, public.liga_participantes),
  public._liga_encerrar(uuid, uuid, text), public._liga_resolver_npc(uuid), public._liga_prazos(uuid), public._liga_fim_batalha(public.batalhas), public._tg_liga_batalha()
  from public, anon, authenticated;

-- ---------- jogador ----------
create or replace function public.liga_estado() returns jsonb language plpgsql security definer set search_path = public as $$
declare e public.liga_edicoes; j public.jogadores; mina public.liga_participantes; p public.liga_partidas; opp public.liga_participantes;
        rs jsonb; minha jsonb := null; ins jsonb; inscrito boolean := false; ativa boolean;
begin
  if auth.uid() is null then return null; end if;
  select * into j from public.jogadores where id = auth.uid();
  select coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'colocacao', r.colocacao, 'premio', r.premio) order by r.id), '[]'::jsonb) into rs
    from public.liga_resultados r where r.jogador = auth.uid() and not r.visto;
  select * into e from public.liga_edicoes where estado in ('inscricoes', 'fechada', 'sorteada', 'andamento');
  if e.id is not null then
    perform public._liga_prazos(e.id);
  else
    select * into e from public.liga_edicoes where estado = 'finalizada' order by criado desc limit 1;
  end if;
  if e.id is null then return jsonb_build_object('ativa', false, 'edicao', null, 'resultados', rs, 'na_arena', j.mapa_id = 'plato'); end if;
  select * into e from public.liga_edicoes where id = e.id;
  ativa := e.estado in ('inscricoes', 'fechada', 'sorteada', 'andamento');
  select coalesce(jsonb_agg(jj.nome order by i.em), '[]'::jsonb) into ins from public.liga_inscricoes i join public.jogadores jj on jj.id = i.jogador where i.edicao = e.id;
  inscrito := exists (select 1 from public.liga_inscricoes where edicao = e.id and jogador = auth.uid());
  select * into mina from public.liga_participantes where edicao = e.id and jogador = auth.uid();
  if mina.id is not null and e.estado = 'andamento' and not mina.eliminado then
    select * into p from public.liga_partidas where edicao = e.id and rodada = e.rodada and estado = 'em_curso' and (a = mina.id or b = mina.id);
    if p.id is not null then
      select * into opp from public.liga_participantes where id = case when p.a = mina.id then p.b else p.a end;
      minha := jsonb_build_object('partida', p.id, 'rodada', p.rodada, 'oponente', opp.nome, 'oponente_tipo', opp.tipo, 'prazo', p.prazo,
        'eu_pronto', case when p.a = mina.id then p.pronto_a else p.pronto_b end, 'op_pronto', case when p.a = mina.id then p.pronto_b else p.pronto_a end,
        'em_batalha', exists (select 1 from public.batalhas where jogador = auth.uid() and estado = 'ativa' and liga_partida = p.id));
    end if;
  end if;
  return jsonb_build_object('ativa', ativa, 'agora', now(), 'na_arena', j.mapa_id = 'plato', 'inscrito', inscrito, 'participa', mina.id is not null,
    'eliminado', coalesce(mina.eliminado, false), 'resultados', rs, 'minha', minha, 'inscritos', ins,
    'edicao', jsonb_build_object('id', e.id, 'nome', e.nome, 'estado', e.estado, 'tamanho', e.tamanho, 'rodadas', public._liga_rodadas(e.tamanho), 'rodada', e.rodada,
      'inscricoes_ate', e.inscricoes_ate, 'inicio_em', e.inicio_em, 'prazo_min', e.prazo_min, 'premios', e.premios, 'campeao_nome', e.campeao_nome, 'vice_nome', e.vice_nome,
      'especiais_n', coalesce(array_length(e.especiais, 1), 0)),
    'chave', public._liga_chave(e.id));
end $$;
grant execute on function public.liga_estado() to authenticated;

create or replace function public.liga_resultados_vistos() returns void language sql security definer set search_path = public as $$
  update public.liga_resultados set visto = true where jogador = auth.uid() and not visto $$;
grant execute on function public.liga_resultados_vistos() to authenticated;

create or replace function public.liga_inscrever() returns jsonb language plpgsql security definer set search_path = public as $$
declare j public.jogadores; e public.liga_edicoes; n int;
begin
  if auth.uid() is null then raise exception 'Faça login primeiro.'; end if;
  select * into j from public.jogadores where id = auth.uid() for update;
  if j.id is null then raise exception 'Crie seu personagem primeiro.'; end if;
  select * into e from public.liga_edicoes where estado = 'inscricoes' for update;
  if e.id is null then raise exception 'Não há inscrições abertas para a Liga.'; end if;
  if e.inscricoes_ate is not null and now() > e.inscricoes_ate then raise exception 'As inscrições da Liga já terminaram.'; end if;
  if not public._poi_aqui(j, 'centro') then raise exception 'A inscrição é feita no balcão de um Centro Pokémon.'; end if;
  if coalesce(array_length(j.insignias, 1), 0) < 8 then raise exception 'Para se inscrever você precisa das 8 insígnias.'; end if;
  if exists (select 1 from public.liga_inscricoes where edicao = e.id and jogador = j.id) then raise exception 'Você já está inscrito na Liga.'; end if;
  if not exists (select 1 from public.pokemons where dono = j.id and posicao is not null) then raise exception 'Você precisa de Pokémon no time.'; end if;
  select count(*) into n from public.liga_inscricoes where edicao = e.id;
  if n + coalesce(array_length(e.especiais, 1), 0) >= e.tamanho then raise exception 'Todas as vagas da Liga já foram preenchidas.'; end if;
  insert into public.liga_inscricoes (edicao, jogador) values (e.id, j.id);
  return jsonb_build_object('ok', true, 'nome', e.nome);
end $$;
grant execute on function public.liga_inscrever() to authenticated;

create or replace function public.liga_desinscrever() returns void language plpgsql security definer set search_path = public as $$
declare e public.liga_edicoes;
begin
  if auth.uid() is null then raise exception 'Faça login primeiro.'; end if;
  select * into e from public.liga_edicoes where estado in ('inscricoes', 'fechada');
  if e.id is null then raise exception 'Não há inscrição para cancelar.'; end if;
  delete from public.liga_inscricoes where edicao = e.id and jogador = auth.uid();
end $$;
grant execute on function public.liga_desinscrever() to authenticated;

create or replace function public.liga_pronto() returns jsonb language plpgsql security definer set search_path = public as $$
declare j public.jogadores; e public.liga_edicoes; mina public.liga_participantes; opp public.liga_participantes; p public.liga_partidas; sou_a boolean;
        b public.batalhas; ra public.batalhas; rc public.batalhas; ativo_a uuid; ativo_b uuid; k int; equipe jsonb; ja uuid; jb uuid;
begin
  if auth.uid() is null then raise exception 'Faça login primeiro.'; end if;
  select * into j from public.jogadores where id = auth.uid() for update;
  if j.id is null then raise exception 'Crie seu personagem primeiro.'; end if;
  select * into e from public.liga_edicoes where estado = 'andamento';
  if e.id is null then raise exception 'A Liga não está em andamento agora.'; end if;
  perform public._liga_prazos(e.id);
  select * into mina from public.liga_participantes where edicao = e.id and jogador = j.id and not eliminado;
  if mina.id is null then raise exception 'Você não está mais na disputa desta Liga.'; end if;
  select * into p from public.liga_partidas where edicao = e.id and rodada = e.rodada and estado = 'em_curso' and (a = mina.id or b = mina.id) for update;
  if p.id is null then raise exception 'Sua partida desta rodada não está disponível (não começou ou já terminou).'; end if;
  select * into b from public.batalhas where jogador = j.id and estado = 'ativa' and liga_partida = p.id;
  if b.id is not null then return jsonb_build_object('batalha', true); end if;
  if j.mapa_id <> 'plato' then raise exception 'Vá até a arena da Liga (Platô Prisma) para lutar.'; end if;
  if not exists (select 1 from public.pokemons where dono = j.id and posicao is not null) then raise exception 'Você precisa de Pokémon no time.'; end if;
  sou_a := (p.a = mina.id);
  select * into opp from public.liga_participantes where id = case when sou_a then p.b else p.a end;
  if sou_a then update public.liga_partidas set pronto_a = true where id = p.id; p.pronto_a := true;
  else update public.liga_partidas set pronto_b = true where id = p.id; p.pronto_b := true; end if;

  if opp.tipo <> 'jogador' then
    perform public._liga_liberar(j.id, p.id);
    select count(*) into k from public.pokemons where dono = j.id and posicao is not null;
    equipe := case when opp.tipo = 'especial' then public._equipe_treinador(opp.equipe) else public._liga_equipe_aleatoria(opp.ref, k) end;
    select id into ativo_a from public.pokemons where dono = j.id and posicao is not null and hp_atual > 0 order by posicao limit 1;
    insert into public.batalhas (jogador, selvagem, ativo, tipo, treinador, adversarios, revanche, liga_partida)
    values (j.id, '{}'::jsonb, ativo_a, 'treinador', opp.treinador, equipe, true, p.id) returning * into b;
    update public.liga_partidas set batalha = b.id where id = p.id;
    return jsonb_build_object('batalha', true);
  end if;

  if not (p.pronto_a and p.pronto_b) then return jsonb_build_object('espera', true); end if;
  select jogador into ja from public.liga_participantes where id = p.a;
  select jogador into jb from public.liga_participantes where id = p.b;
  perform public._liga_liberar(ja, p.id); perform public._liga_liberar(jb, p.id);
  select id into ativo_a from public.pokemons where dono = ja and posicao is not null order by posicao limit 1;
  select id into ativo_b from public.pokemons where dono = jb and posicao is not null order by posicao limit 1;
  if ativo_a is null or ativo_b is null then raise exception 'Um dos lutadores está sem Pokémon no time.'; end if;
  insert into public.batalhas (jogador, selvagem, ativo, tipo, lado, amistoso, liga_partida, meta)
  values (ja, '{}'::jsonb, ativo_a, 'duelo', 0, true, p.id,
          jsonb_build_object('visto', jsonb_build_object('0', (extract(epoch from now()) * 1000)::bigint, '1', (extract(epoch from now()) * 1000)::bigint))) returning * into ra;
  insert into public.batalhas (jogador, selvagem, ativo, tipo, lado, par, amistoso, liga_partida)
  values (jb, '{}'::jsonb, ativo_b, 'duelo', 1, ra.id, true, p.id) returning * into rc;
  update public.batalhas set par = rc.id where id = ra.id;
  update public.liga_partidas set batalha = ra.id where id = p.id;
  return jsonb_build_object('batalha', true);
end $$;
grant execute on function public.liga_pronto() to authenticated;

-- ---------- Mestre ----------
create or replace function public.mestre_liga_obter() returns jsonb language plpgsql security definer set search_path = public as $$
declare e public.liga_edicoes;
begin
  if not public.eh_mestre() then raise exception 'Só o Mestre.'; end if;
  select * into e from public.liga_edicoes where estado in ('inscricoes', 'fechada', 'sorteada', 'andamento');
  if e.id is not null then
    perform public._liga_prazos(e.id);
    select * into e from public.liga_edicoes where id = e.id;
  end if;
  return jsonb_build_object(
    'edicao', case when e.id is null then null else to_jsonb(e) || jsonb_build_object('rodadas', public._liga_rodadas(e.tamanho)) end,
    'inscritos', coalesce((select jsonb_agg(jsonb_build_object('id', jj.id, 'nome', jj.nome, 'insignias', coalesce(array_length(jj.insignias, 1), 0), 'presente', jj.mapa_id = 'plato') order by i.em)
                             from public.liga_inscricoes i join public.jogadores jj on jj.id = i.jogador where i.edicao = e.id), '[]'::jsonb),
    'chave', public._liga_chave(e.id),
    'npcs', coalesce((select jsonb_agg(to_jsonb(n) order by n.nome) from public.liga_npcs_especiais n), '[]'::jsonb),
    'ultima', (select jsonb_build_object('nome', x.nome, 'campeao', x.campeao_nome, 'vice', x.vice_nome) from public.liga_edicoes x where x.estado = 'finalizada' order by x.criado desc limit 1));
end $$;
grant execute on function public.mestre_liga_obter() to authenticated;

create or replace function public._liga_premios_ok(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare k text; r jsonb := '{}'::jsonb;
begin
  foreach k in array array['campeao', 'vice', 'semi', 'participacao'] loop
    if p ? k then perform public._payload_ok(coalesce(p -> k, '{}'::jsonb)); r := r || jsonb_build_object(k, coalesce(p -> k, '{}'::jsonb)); end if;
  end loop;
  return r;
end $$;
revoke all on function public._liga_premios_ok(jsonb) from public, anon, authenticated;

create or replace function public.mestre_liga_criar(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare e public.liga_edicoes; n int; esp uuid[]; v_def jsonb := '{"campeao":{"dinheiro":10000,"titulo":"campeao_liga"},"vice":{"dinheiro":4000,"titulo":"vice_liga"},"semi":{"dinheiro":1500},"participacao":{}}';
begin
  if not public.eh_mestre() then raise exception 'Só o Mestre.'; end if;
  if exists (select 1 from public.liga_edicoes where estado in ('inscricoes', 'fechada', 'sorteada', 'andamento')) then raise exception 'Já existe uma Liga em curso. Conclua ou cancele antes de criar outra.'; end if;
  n := coalesce(nullif(p ->> 'tamanho', '')::int, 32);
  if n not in (8, 16, 32, 64) then raise exception 'O tamanho da chave deve ser 8, 16, 32 ou 64.'; end if;
  esp := array(select x::uuid from jsonb_array_elements_text(coalesce(p -> 'especiais', '[]'::jsonb)) x);
  if exists (select 1 from unnest(esp) u where not exists (select 1 from public.liga_npcs_especiais where id = u)) then raise exception 'NPC especial inexistente.'; end if;
  if coalesce(array_length(esp, 1), 0) > n - 1 then raise exception 'NPCs especiais demais para o tamanho da chave.'; end if;
  insert into public.liga_edicoes (nome, tamanho, inscricoes_ate, inicio_em, prazo_min, premios, especiais, criado_por)
  values (coalesce(nullif(trim(p ->> 'nome'), ''), 'Liga Pokémon'), n, nullif(p ->> 'inscricoes_ate', '')::timestamptz, nullif(p ->> 'inicio_em', '')::timestamptz,
          coalesce(nullif(p ->> 'prazo_min', '')::int, 10), v_def || public._liga_premios_ok(coalesce(p -> 'premios', '{}'::jsonb)), esp, auth.uid()) returning * into e;
  return to_jsonb(e);
end $$;
grant execute on function public.mestre_liga_criar(jsonb) to authenticated;

create or replace function public.mestre_liga_atualizar(p jsonb) returns void language plpgsql security definer set search_path = public as $$
declare e public.liga_edicoes; n int; esp uuid[]; ninsc int;
begin
  if not public.eh_mestre() then raise exception 'Só o Mestre.'; end if;
  select * into e from public.liga_edicoes where estado in ('inscricoes', 'fechada', 'sorteada', 'andamento') for update;
  if e.id is null then raise exception 'Não há Liga em curso.'; end if;
  if p ? 'nome' and coalesce(trim(p ->> 'nome'), '') <> '' then update public.liga_edicoes set nome = trim(p ->> 'nome') where id = e.id; end if;
  if p ? 'inscricoes_ate' then update public.liga_edicoes set inscricoes_ate = nullif(p ->> 'inscricoes_ate', '')::timestamptz where id = e.id; end if;
  if p ? 'inicio_em' then update public.liga_edicoes set inicio_em = nullif(p ->> 'inicio_em', '')::timestamptz where id = e.id; end if;
  if p ? 'prazo_min' then
    if coalesce((p ->> 'prazo_min')::int, 0) not between 1 and 120 then raise exception 'O prazo deve ficar entre 1 e 120 minutos.'; end if;
    update public.liga_edicoes set prazo_min = (p ->> 'prazo_min')::int where id = e.id;
  end if;
  if p ? 'premios' then update public.liga_edicoes set premios = premios || public._liga_premios_ok(p -> 'premios') where id = e.id; end if;
  if e.estado in ('inscricoes', 'fechada') then
    n := coalesce(nullif(p ->> 'tamanho', '')::int, e.tamanho);
    if n not in (8, 16, 32, 64) then raise exception 'O tamanho da chave deve ser 8, 16, 32 ou 64.'; end if;
    esp := case when p ? 'especiais' then array(select x::uuid from jsonb_array_elements_text(p -> 'especiais') x) else e.especiais end;
    if exists (select 1 from unnest(esp) u where not exists (select 1 from public.liga_npcs_especiais where id = u)) then raise exception 'NPC especial inexistente.'; end if;
    select count(*) into ninsc from public.liga_inscricoes where edicao = e.id;
    if ninsc + coalesce(array_length(esp, 1), 0) > n then raise exception 'Há inscritos e NPCs especiais demais para esse tamanho de chave.'; end if;
    update public.liga_edicoes set tamanho = n, especiais = esp where id = e.id;
  end if;
end $$;
grant execute on function public.mestre_liga_atualizar(jsonb) to authenticated;

create or replace function public.mestre_liga_inscricoes(p_abrir boolean) returns void language plpgsql security definer set search_path = public as $$
declare e public.liga_edicoes;
begin
  if not public.eh_mestre() then raise exception 'Só o Mestre.'; end if;
  select * into e from public.liga_edicoes where estado in ('inscricoes', 'fechada') for update;
  if e.id is null then raise exception 'Só dá para abrir ou fechar inscrições antes do sorteio.'; end if;
  update public.liga_edicoes set estado = case when p_abrir then 'inscricoes' else 'fechada' end where id = e.id;
end $$;
grant execute on function public.mestre_liga_inscricoes(boolean) to authenticated;

create or replace function public.mestre_liga_remover_inscrito(p_jogador uuid) returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.eh_mestre() then raise exception 'Só o Mestre.'; end if;
  delete from public.liga_inscricoes where jogador = p_jogador and edicao in (select id from public.liga_edicoes where estado in ('inscricoes', 'fechada'));
end $$;
grant execute on function public.mestre_liga_remover_inscrito(uuid) to authenticated;

create or replace function public.mestre_liga_sortear() returns jsonb language plpgsql security definer set search_path = public as $$
declare e public.liga_edicoes; np int; ne int; na int; ref int; pref text; mapa text; M int; ocup boolean[]; perm int[]; i int; k int; pos_ int; r record; s int; seq int := 0;
        nome_ text; esp record; rodadas int;
begin
  if not public.eh_mestre() then raise exception 'Só o Mestre.'; end if;
  select * into e from public.liga_edicoes where estado in ('inscricoes', 'fechada', 'sorteada') for update;
  if e.id is null then raise exception 'Não há Liga pronta para sortear.'; end if;
  pref := left(replace(e.id::text, '-', ''), 8);
  if e.estado = 'sorteada' then
    delete from public.treinadores where id like 'lgn\_' || pref || '\_%';
    delete from public.liga_partidas where edicao = e.id;
    delete from public.liga_participantes where edicao = e.id;
  end if;
  select count(*) into np from public.liga_inscricoes where edicao = e.id;
  ne := coalesce(array_length(e.especiais, 1), 0);
  if np < 1 then raise exception 'Nenhum jogador inscrito.'; end if;
  if np + ne > e.tamanho then raise exception 'Inscritos + NPCs especiais (%) passam do tamanho da chave (%).', np + ne, e.tamanho; end if;
  na := e.tamanho - np - ne;
  select greatest(1, round(avg(public._nivel_ref(i.jogador)))::int) into ref from public.liga_inscricoes i where i.edicao = e.id;
  mapa := coalesce((select id from public.mapas where id = 'plato'), (select id from public.mapas order by id limit 1));
  if mapa is null then raise exception 'Os mapas do jogo ainda não foram importados.'; end if;

  insert into public.liga_participantes (edicao, tipo, jogador, nome, aparencia, ref)
  select e.id, 'jogador', jj.id, jj.nome, jj.aparencia, ref from public.liga_inscricoes i join public.jogadores jj on jj.id = i.jogador where i.edicao = e.id;
  for esp in select n.* from public.liga_npcs_especiais n where n.id = any (e.especiais) loop
    seq := seq + 1;
    insert into public.liga_participantes (edicao, tipo, nome, classe, aparencia, treinador, equipe, falas, ref)
    values (e.id, 'especial', esp.nome, esp.classe, esp.aparencia, 'lgn_' || pref || '_' || seq, esp.equipe, esp.falas, ref);
  end loop;
  for k in 1 .. na loop
    seq := seq + 1;
    nome_ := coalesce((select n.nome from public.mv_nomes n where n.nome not in (select x.nome from public.liga_participantes x where x.edicao = e.id) order by random() limit 1), 'Treinador ' || k);
    insert into public.liga_participantes (edicao, tipo, nome, classe, aparencia, treinador, ref)
    values (e.id, 'aleatorio', nome_, (array['Treinador', 'Veterano', 'Ás', 'Estrategista', 'Domador', 'Aventureiro'])[1 + floor(random() * 6)::int], public._mv_aparencia(), 'lgn_' || pref || '_' || seq, ref);
  end loop;
  insert into public.treinadores (id, mapa_id, x, y, nome, classe, aparencia, recompensa, falas, equipe, arco, lider)
  select treinador, mapa, -1, -1, nome, coalesce(classe, 'Treinador'), coalesce(aparencia, 12), 0, coalesce(falas, '{}'::jsonb), coalesce(equipe, '[]'::jsonb), 99, false
    from public.liga_participantes where edicao = e.id and treinador is not null;

  M := e.tamanho / 2;
  ocup := array_fill(false, array[e.tamanho]);
  perm := array(select g from generate_series(1, M) g order by random());
  i := 0;
  for r in select id from public.liga_participantes where edicao = e.id and tipo = 'jogador' order by random() loop
    i := i + 1; k := perm[((i - 1) % M) + 1];
    if not ocup[2 * k - 1] and not ocup[2 * k] then pos_ := 2 * k - 1 + floor(random() * 2)::int;
    elsif not ocup[2 * k - 1] then pos_ := 2 * k - 1; else pos_ := 2 * k; end if;
    ocup[pos_] := true;
    update public.liga_participantes set pos = pos_ where id = r.id;
  end loop;
  pos_ := 0;
  for r in select id from public.liga_participantes where edicao = e.id and tipo <> 'jogador' order by random() loop
    loop pos_ := pos_ + 1; exit when not ocup[pos_]; end loop;
    ocup[pos_] := true;
    update public.liga_participantes set pos = pos_ where id = r.id;
  end loop;

  rodadas := public._liga_rodadas(e.tamanho);
  for i in 1 .. rodadas loop
    for s in 1 .. (e.tamanho >> i) loop
      insert into public.liga_partidas (edicao, rodada, slot, a, b) values (e.id, i, s,
        case when i = 1 then (select id from public.liga_participantes where edicao = e.id and pos = 2 * s - 1) end,
        case when i = 1 then (select id from public.liga_participantes where edicao = e.id and pos = 2 * s) end);
    end loop;
  end loop;
  update public.liga_edicoes set estado = 'sorteada', rodada = 0 where id = e.id;
  return jsonb_build_object('jogadores', np, 'especiais', ne, 'aleatorios', na);
end $$;
grant execute on function public.mestre_liga_sortear() to authenticated;

create or replace function public.mestre_liga_iniciar_rodada() returns jsonb language plpgsql security definer set search_path = public as $$
declare e public.liga_edicoes; r int; p public.liga_partidas; pa_ public.liga_participantes; pb_ public.liga_participantes;
begin
  if not public.eh_mestre() then raise exception 'Só o Mestre.'; end if;
  select * into e from public.liga_edicoes where estado in ('sorteada', 'andamento') for update;
  if e.id is null then raise exception 'A Liga precisa estar sorteada.'; end if;
  r := e.rodada + 1;
  if r > public._liga_rodadas(e.tamanho) then raise exception 'A Liga já terminou.'; end if;
  if r > 1 and exists (select 1 from public.liga_partidas where edicao = e.id and rodada = r - 1 and estado <> 'encerrada') then raise exception 'Termine a rodada anterior antes de iniciar a próxima.'; end if;
  update public.liga_edicoes set rodada = r, estado = 'andamento' where id = e.id;
  for p in select * from public.liga_partidas where edicao = e.id and rodada = r and estado = 'aguardando' order by slot loop
    if p.a is null or p.b is null then continue; end if;
    select * into pa_ from public.liga_participantes where id = p.a;
    select * into pb_ from public.liga_participantes where id = p.b;
    if pa_.tipo <> 'jogador' and pb_.tipo <> 'jogador' then
      perform public._liga_resolver_npc(p.id);
    else
      update public.liga_partidas set estado = 'em_curso', prazo = now() + make_interval(mins => e.prazo_min) where id = p.id;
    end if;
  end loop;
  return jsonb_build_object('rodada', r);
end $$;
grant execute on function public.mestre_liga_iniciar_rodada() to authenticated;

create or replace function public.mestre_liga_vencedor(p_partida uuid, p_participante uuid) returns void language plpgsql security definer set search_path = public as $$
declare p public.liga_partidas;
begin
  if not public.eh_mestre() then raise exception 'Só o Mestre.'; end if;
  select * into p from public.liga_partidas where id = p_partida;
  if p.id is null or p.estado = 'encerrada' then raise exception 'Essa partida já terminou.'; end if;
  if p.a is null or p.b is null then raise exception 'A partida ainda não tem os dois lados.'; end if;
  if p_participante not in (p.a, p.b) then raise exception 'Participante inválido.'; end if;
  perform public._liga_encerrar(p.id, p_participante, 'mestre');
end $$;
grant execute on function public.mestre_liga_vencedor(uuid, uuid) to authenticated;

create or replace function public.mestre_liga_cancelar() returns void language plpgsql security definer set search_path = public as $$
declare e public.liga_edicoes;
begin
  if not public.eh_mestre() then raise exception 'Só o Mestre.'; end if;
  select * into e from public.liga_edicoes where estado in ('inscricoes', 'fechada', 'sorteada', 'andamento') for update;
  if e.id is null then return; end if;
  update public.liga_edicoes set estado = 'cancelada' where id = e.id;
  update public.batalhas set estado = 'fuga' where estado = 'ativa' and liga_partida in (select id from public.liga_partidas where edicao = e.id);
  delete from public.treinadores where id like 'lgn\_' || left(replace(e.id::text, '-', ''), 8) || '\_%';
end $$;
grant execute on function public.mestre_liga_cancelar() to authenticated;

create or replace function public.mestre_liga_npc_salvar(p jsonb) returns uuid language plpgsql security definer set search_path = public as $$
declare x jsonb; v_id uuid; v_falas jsonb;
begin
  if not public.eh_mestre() then raise exception 'Só o Mestre.'; end if;
  if char_length(coalesce(trim(p ->> 'nome'), '')) not between 2 and 30 then raise exception 'O nome deve ter de 2 a 30 letras.'; end if;
  if jsonb_typeof(p -> 'equipe') <> 'array' or jsonb_array_length(p -> 'equipe') not between 1 and 6 then raise exception 'O time precisa ter de 1 a 6 Pokémon.'; end if;
  for x in select * from jsonb_array_elements(p -> 'equipe') loop
    if not exists (select 1 from public.especies where id = (x ->> 'especie')::int) then raise exception 'Espécie inválida no time.'; end if;
    if coalesce((x ->> 'nivel')::int, 0) not between 1 and 1000 then raise exception 'Nível inválido no time (1 a 1000).'; end if;
  end loop;
  v_falas := jsonb_build_object('antes', left(coalesce(p -> 'falas' ->> 'antes', ''), 160), 'derrota', left(coalesce(p -> 'falas' ->> 'derrota', ''), 160));
  v_id := nullif(p ->> 'id', '')::uuid;
  if v_id is not null and exists (select 1 from public.liga_npcs_especiais where id = v_id) then
    update public.liga_npcs_especiais set nome = trim(p ->> 'nome'), classe = coalesce(nullif(trim(p ->> 'classe'), ''), 'Campeão'),
      aparencia = coalesce(nullif(p ->> 'aparencia', '')::smallint, 12), falas = v_falas, equipe = p -> 'equipe' where id = v_id;
  else
    insert into public.liga_npcs_especiais (nome, classe, aparencia, falas, equipe)
    values (trim(p ->> 'nome'), coalesce(nullif(trim(p ->> 'classe'), ''), 'Campeão'), coalesce(nullif(p ->> 'aparencia', '')::smallint, 12), v_falas, p -> 'equipe') returning id into v_id;
  end if;
  return v_id;
end $$;
grant execute on function public.mestre_liga_npc_salvar(jsonb) to authenticated;

create or replace function public.mestre_liga_npc_remover(p_id uuid) returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.eh_mestre() then raise exception 'Só o Mestre.'; end if;
  if exists (select 1 from public.liga_edicoes where estado in ('inscricoes', 'fechada', 'sorteada', 'andamento') and p_id = any (especiais)) then
    raise exception 'Esse NPC está na Liga em curso. Tire-o da lista antes de remover.';
  end if;
  delete from public.liga_npcs_especiais where id = p_id;
end $$;
grant execute on function public.mestre_liga_npc_remover(uuid) to authenticated;
