-- m60: Mundo vivo — Lote 2: Mercador, Enfermeira de campo, Vidente, Contador de histórias e as quests (Pesquisador, Naturalista, Entregador, Colecionador).
-- Requer m59 e m59b. Aditiva e idempotente. Os NPCs só passam a aparecer porque agora existem as funções _mv_h_<arquétipo>.

create table if not exists public.mv_quests (
  id bigint generated always as identity primary key,
  jogador uuid not null references public.jogadores (id) on delete cascade,
  npc text not null, arquetipo text not null,
  tipo text not null check (tipo in ('captura', 'dex_visto', 'chegar')),
  alvo text, progresso int not null default 0, meta int not null check (meta > 0),
  texto text not null, premio jsonb not null default '{}'::jsonb,
  expira_dia date not null,
  estado text not null default 'ativa' check (estado in ('ativa', 'concluida', 'expirada')),
  criado_em timestamptz not null default now()
);
create index if not exists mv_quests_jogador on public.mv_quests (jogador, estado);
alter table public.mv_quests enable row level security;

-- progresso das quests (captura, Pokédex vista, chegada a um mapa); a recompensa sai na hora, sem precisar voltar ao NPC
create or replace function public._mv_quest_progredir(p_j uuid, p_tipo text, p_alvo text default null, p_n int default 1) returns void
language plpgsql security definer set search_path = public as $$
declare q public.mv_quests; d date := public._dia_jogo();
begin
  for q in select * from public.mv_quests where jogador = p_j and estado = 'ativa' and tipo = p_tipo and (alvo is null or alvo = p_alvo) for update loop
    if q.expira_dia < d then update public.mv_quests set estado = 'expirada' where id = q.id; continue; end if;
    if q.progresso + p_n >= q.meta then
      update public.mv_quests set progresso = meta, estado = 'concluida' where id = q.id;
      perform public._conceder(p_j, q.premio);
      insert into public.mv_premios (jogador, titulo, payload) values (p_j, 'Tarefa concluída: ' || q.texto, q.premio);
    else
      update public.mv_quests set progresso = progresso + p_n where id = q.id;
    end if;
  end loop;
end $$;
revoke all on function public._mv_quest_progredir(uuid, text, text, int) from public, anon, authenticated;

create or replace function public._tg_mv_quest_atividade() returns trigger language plpgsql security definer set search_path = public as $$
begin
  begin
    if new.tipo = 'captura' and exists (select 1 from public.mv_quests where jogador = new.jogador and estado = 'ativa' and tipo = 'captura') then
      perform public._mv_quest_progredir(new.jogador, 'captura', null, 1);
    end if;
  exception when others then raise warning 'tg_mv_quest_atividade: %', sqlerrm; end;
  return new;
end $$;
drop trigger if exists tg_mv_quest_atividade on public.atividades;
create trigger tg_mv_quest_atividade after insert on public.atividades for each row execute function public._tg_mv_quest_atividade();

create or replace function public._tg_mv_quest_dex() returns trigger language plpgsql security definer set search_path = public as $$
begin
  begin perform public._mv_quest_progredir(new.jogador, 'dex_visto', null, 1); exception when others then raise warning 'tg_mv_quest_dex: %', sqlerrm; end;
  return new;
end $$;
drop trigger if exists tg_mv_quest_dex on public.pokedex;
create trigger tg_mv_quest_dex after insert on public.pokedex for each row execute function public._tg_mv_quest_dex();

create or replace function public._tg_mv_quest_mapa() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.mapa_id is distinct from old.mapa_id then
    begin perform public._mv_quest_progredir(new.id, 'chegar', new.mapa_id, 1); exception when others then raise warning 'tg_mv_quest_mapa: %', sqlerrm; end;
  end if;
  return new;
end $$;
drop trigger if exists tg_mv_quest_mapa on public.jogadores;
create trigger tg_mv_quest_mapa after update of mapa_id on public.jogadores for each row execute function public._tg_mv_quest_mapa();

-- ---------- despachante ----------
create or replace function public.mv_interagir(p_npc text, p_acao text default null, p_arg jsonb default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_j public.jogadores; v_n public.mv_npcs; v_r jsonb; d date := public._dia_jogo(); t int := public._mv_turno();
begin
  if auth.uid() is null then raise exception 'Faça login primeiro.'; end if;
  if not public._modulo('mundo_vivo') then raise exception 'Este recurso está desligado.'; end if;
  select * into v_j from public.jogadores where id = auth.uid() for update;
  if not found then raise exception 'Crie seu personagem primeiro.'; end if;
  if exists (select 1 from public.batalhas where jogador = v_j.id and estado = 'ativa') then raise exception 'Termine a batalha primeiro.'; end if;
  select * into v_n from public.mv_npcs where id = p_npc and dia = d and turno = t and mapa_id = v_j.mapa_id;
  if not found then raise exception 'Essa pessoa já seguiu viagem.'; end if;
  if abs(v_n.x - v_j.x) + abs(v_n.y - v_j.y) <> 1 then raise exception 'Chegue ao lado de % para conversar.', v_n.nome; end if;
  if to_regprocedure('public._mv_h_' || v_n.arquetipo || '(uuid,public.mv_npcs,text,jsonb)') is null then raise exception 'Essa pessoa não tem nada a oferecer agora.'; end if;
  execute format('select public._mv_h_%I($1, $2, $3, $4)', v_n.arquetipo) into v_r using v_j.id, v_n, p_acao, p_arg;
  return v_r;
end $$;
revoke all on function public.mv_interagir(text, text, jsonb) from public, anon;
grant execute on function public.mv_interagir(text, text, jsonb) to authenticated;

create or replace function public._mv_uso(p_j uuid, p_chave text) returns int language sql stable security definer set search_path = public as $$
  select coalesce((select n from public.mv_usos where jogador = p_j and chave = p_chave and dia = public._dia_jogo()), 0) $$;
create or replace function public._mv_uso_somar(p_j uuid, p_chave text) returns void language sql security definer set search_path = public as $$
  insert into public.mv_usos (jogador, chave, dia, n) values (p_j, p_chave, public._dia_jogo(), 1)
  on conflict (jogador, chave, dia) do update set n = public.mv_usos.n + 1 $$;
revoke all on function public._mv_uso(uuid, text), public._mv_uso_somar(uuid, text) from public, anon, authenticated;

create or replace function public._mv_fala(p_arq text) returns text language sql stable security definer set search_path = public as $$
  select coalesce((select falas ->> 'abertura' from public.mv_arquetipos where id = p_arq), '...') $$;

-- ---------- Mercador ----------
create or replace function public._mv_h_mercador(p_j uuid, p_n public.mv_npcs, p_acao text, p_arg jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare e jsonb; v_item text; v_preco int; lim int := coalesce((select (cfg ->> 'limite_por_item')::int from public.mv_arquetipos where id = 'mercador'), 3); din int; ops jsonb := '[]'::jsonb; msg text;
begin
  if p_acao like 'comprar:%' then
    v_item := substr(p_acao, 9);
    select x into e from jsonb_array_elements(p_n.dados -> 'estoque') x where x ->> 'item' = v_item;
    if e is null then raise exception 'O mercador não tem isso.'; end if;
    v_preco := (e ->> 'preco')::int;
    if public._mv_uso(p_j, 'merc:' || p_n.id || ':' || v_item) >= lim then raise exception 'O mercador só vende % unidades disso para você.', lim; end if;
    update public.jogadores set dinheiro = dinheiro - v_preco where id = p_j and dinheiro >= v_preco;
    if not found then raise exception 'Dinheiro insuficiente (₽ %).', v_preco; end if;
    perform public._conceder(p_j, jsonb_build_object('itens', jsonb_build_array(jsonb_build_object('item', v_item, 'qtd', 1))));
    perform public._mv_uso_somar(p_j, 'merc:' || p_n.id || ':' || v_item);
    msg := format('Comprou 1× %s por ₽ %s.', (select nome from public.itens where slug = v_item), v_preco);
  end if;
  select dinheiro into din from public.jogadores where id = p_j;
  select coalesce(jsonb_agg(jsonb_build_object('id', 'comprar:' || (x ->> 'item'),
           'rotulo', format('%s — ₽ %s', coalesce((select nome from public.itens where slug = x ->> 'item'), x ->> 'item'), x ->> 'preco'),
           'detalhe', format('Você tem ₽ %s. Restam %s unidade(s) para você.', din, greatest(0, lim - public._mv_uso(p_j, 'merc:' || p_n.id || ':' || (x ->> 'item')))))), '[]'::jsonb)
    into ops from jsonb_array_elements(p_n.dados -> 'estoque') x;
  return jsonb_build_object('texto', public._mv_fala('mercador'), 'mensagem', msg, 'opcoes', ops);
end $$;

-- ---------- Enfermeira de campo ----------
create or replace function public._mv_h_enfermeira(p_j uuid, p_n public.mv_npcs, p_acao text, p_arg jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare n int; msg text;
begin
  if p_acao = 'curar' then
    perform public._gastar_pa(p_j);
    update public.pokemons p set hp_atual = hp_max,
      golpes = coalesce((select jsonb_agg(jsonb_build_object('id', (g ->> 'id')::int, 'pp', (select pp from public.golpes where id = (g ->> 'id')::int))) from jsonb_array_elements(p.golpes) g), '[]'::jsonb)
     where dono = p_j;
    get diagnostics n = row_count;
    perform public._atividade(p_j, 'cura', null);
    msg := format('Pronto! %s Pokémon curados.', n);
  end if;
  return jsonb_build_object('texto', public._mv_fala('enfermeira'), 'mensagem', msg,
    'opcoes', jsonb_build_array(jsonb_build_object('id', 'curar', 'rotulo', 'Curar meu time', 'custo_pa', 1)));
end $$;

-- ---------- Vidente ----------
create or replace function public._mv_h_vidente(p_j uuid, p_n public.mv_npcs, p_acao text, p_arg jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_pk record; v_pr jsonb; msg text; v_cfg jsonb; d date := public._dia_jogo(); t int := public._mv_turno(); usada boolean;
begin
  usada := public._mv_uso(p_j, 'vid:' || p_n.id) > 0;
  if p_acao = 'ver' then
    if usada then raise exception 'A vidente já leu o seu destino neste turno.'; end if;
    perform public._gastar_pa(p_j);
    select pd.turno, e.nome as esp, mp.nome as mapa into v_pk from public.mv_pokemon_dia pd join public.especies e on e.id = pd.especie_id join public.mapas mp on mp.id = pd.mapa_id
     where pd.dia = d and pd.turno >= t order by pd.turno limit 1;
    if v_pk.esp is not null then
      msg := format('Eu vejo %s em %s %s.', v_pk.esp, v_pk.mapa, case when v_pk.turno = t then 'agora mesmo' else 'no próximo turno' end);
    else
      msg := 'Hoje não há mais nenhum Pokémon raro à vista.';
    end if;
    select a.cfg into v_cfg from public.mv_arquetipos a where a.id = 'vidente';
    select x into v_pr from jsonb_array_elements(coalesce(v_cfg -> 'premios', '[]'::jsonb)) x order by random() limit 1;
    if v_pr is not null then perform public._conceder(p_j, v_pr); end if;
    perform public._mv_uso_somar(p_j, 'vid:' || p_n.id);
    usada := true;
    return jsonb_build_object('texto', msg, 'premio', v_pr, 'opcoes', '[]'::jsonb);
  end if;
  return jsonb_build_object('texto', public._mv_fala('vidente'),
    'opcoes', case when usada then '[]'::jsonb else jsonb_build_array(jsonb_build_object('id', 'ver', 'rotulo', 'Pedir uma leitura', 'custo_pa', 1, 'detalhe', 'Revela o Pokémon raro do dia e dá um pequeno presente.')) end);
end $$;

-- ---------- Contador de histórias (grátis) ----------
create or replace function public._mv_h_contador(p_j uuid, p_n public.mv_npcs, p_acao text, p_arg jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare h jsonb := (select cfg -> 'historias' from public.mv_arquetipos where id = 'contador'); n int := greatest(coalesce(jsonb_array_length(h), 0), 1);
begin
  return jsonb_build_object('texto', coalesce(h ->> (((p_n.dados ->> 'indice')::int + case when p_acao = 'outra' then 1 + floor(random() * (n - 1))::int else 0 end) % n), public._mv_fala('contador')),
    'opcoes', jsonb_build_array(jsonb_build_object('id', 'outra', 'rotulo', 'Contar outra história')));
end $$;

-- ---------- quests: Pesquisador, Naturalista, Entregador ----------
create or replace function public._mv_h_quest(p_j uuid, p_n public.mv_npcs, p_acao text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare q public.mv_quests; d date := public._dia_jogo(); ativas int; msg text; pa int := public._mv_n('quest_pa', 1)::int; mx int := public._mv_n('quest_max', 3)::int; i int;
begin
  update public.mv_quests set estado = 'expirada' where jogador = p_j and estado = 'ativa' and expira_dia < d;
  select * into q from public.mv_quests where jogador = p_j and npc = p_n.id and expira_dia = d order by id desc limit 1;
  if p_acao = 'aceitar' then
    if found then raise exception 'Você já pegou esta tarefa hoje.'; end if;
    select count(*) into ativas from public.mv_quests where jogador = p_j and estado = 'ativa';
    if ativas >= mx then raise exception 'Você já tem % tarefas ativas. Conclua alguma antes.', mx; end if;
    for i in 1 .. pa loop perform public._gastar_pa(p_j); end loop;
    insert into public.mv_quests (jogador, npc, arquetipo, tipo, alvo, meta, texto, premio, expira_dia)
    values (p_j, p_n.id, p_n.arquetipo, p_n.dados ->> 'tipo', p_n.dados ->> 'alvo', (p_n.dados ->> 'meta')::int, p_n.dados ->> 'texto', p_n.dados -> 'premio', d) returning * into q;
    msg := 'Tarefa aceita! Vale até a virada do dia (6h) e a recompensa vem sozinha quando você cumprir.';
  end if;
  return jsonb_build_object('texto', public._mv_fala(p_n.arquetipo), 'mensagem',
    coalesce(msg, case when q.id is null then null when q.estado = 'concluida' then 'Tarefa concluída — a recompensa já foi entregue!' else format('Progresso: %s/%s (%s)', q.progresso, q.meta, q.texto) end),
    'premio', case when q.id is null then p_n.dados -> 'premio' else null end,
    'opcoes', case when q.id is null then jsonb_build_array(jsonb_build_object('id', 'aceitar', 'rotulo', 'Aceitar: ' || (p_n.dados ->> 'texto'), 'custo_pa', pa)) else '[]'::jsonb end);
end $$;
create or replace function public._mv_h_pesquisador(p_j uuid, p_n public.mv_npcs, p_acao text, p_arg jsonb) returns jsonb language sql security definer set search_path = public as $$ select public._mv_h_quest(p_j, p_n, p_acao) $$;
create or replace function public._mv_h_naturalista(p_j uuid, p_n public.mv_npcs, p_acao text, p_arg jsonb) returns jsonb language sql security definer set search_path = public as $$ select public._mv_h_quest(p_j, p_n, p_acao) $$;
create or replace function public._mv_h_entregador(p_j uuid, p_n public.mv_npcs, p_acao text, p_arg jsonb) returns jsonb language sql security definer set search_path = public as $$ select public._mv_h_quest(p_j, p_n, p_acao) $$;

-- ---------- Colecionador (troca de itens) ----------
create or replace function public._mv_h_colecionador(p_j uuid, p_n public.mv_npcs, p_acao text, p_arg jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare tr jsonb := p_n.dados -> 'troca'; pede jsonb := tr -> 'pede'; da jsonb := tr -> 'da'; tem int; msg text; usada boolean := public._mv_uso(p_j, 'col:' || p_n.id) > 0;
  nome_p text := coalesce((select nome from public.itens where slug = tr -> 'pede' ->> 'item'), 'item');
  nome_d text := coalesce((select nome from public.itens where slug = tr -> 'da' ->> 'item'), 'item');
begin
  if p_acao = 'trocar' then
    if usada then raise exception 'Você já fez esta troca.'; end if;
    select coalesce(qtd, 0) into tem from public.inventario where jogador = p_j and item = pede ->> 'item';
    if coalesce(tem, 0) < (pede ->> 'qtd')::int then raise exception 'Faltam itens: preciso de % × %.', pede ->> 'qtd', nome_p; end if;
    perform public._gastar_pa(p_j);
    update public.inventario set qtd = qtd - (pede ->> 'qtd')::int where jogador = p_j and item = pede ->> 'item';
    perform public._conceder(p_j, jsonb_build_object('itens', jsonb_build_array(da)));
    perform public._mv_uso_somar(p_j, 'col:' || p_n.id);
    return jsonb_build_object('texto', 'Negócio fechado! Peça de ótimo gosto.', 'premio', jsonb_build_object('itens', jsonb_build_array(da)), 'opcoes', '[]'::jsonb);
  end if;
  return jsonb_build_object('texto', public._mv_fala('colecionador'),
    'opcoes', case when usada then '[]'::jsonb else jsonb_build_array(jsonb_build_object('id', 'trocar', 'rotulo', format('Dar %s× %s e receber %s× %s', pede ->> 'qtd', nome_p, da ->> 'qtd', nome_d), 'custo_pa', 1)) end);
end $$;

do $$ declare f text; begin
  foreach f in array array['_mv_h_mercador', '_mv_h_enfermeira', '_mv_h_vidente', '_mv_h_contador', '_mv_h_pesquisador', '_mv_h_naturalista', '_mv_h_entregador', '_mv_h_colecionador'] loop
    execute format('revoke all on function public.%I(uuid, public.mv_npcs, text, jsonb) from public, anon, authenticated', f);
  end loop;
end $$;
revoke all on function public._mv_h_quest(uuid, public.mv_npcs, text), public._mv_fala(text) from public, anon, authenticated;
