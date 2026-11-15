-- m38: Ranking de Treinadores (períodos, pontos, rivais NPC, prêmios) + revanche diária contra NPCs.
-- Pontos só são gravados por funções do servidor. Rivais NPC são calculados na leitura da tabela.

alter table public.batalhas add column if not exists revanche boolean not null default false;

create table if not exists public.ranking_periodos (
  id int generated always as identity primary key,
  inicio date not null,
  fim date not null,                       -- primeiro dia FORA do período
  estado text not null default 'ativo' check (estado in ('ativo', 'fechado')),
  criado_em timestamptz not null default now()
);
create unique index if not exists ranking_periodo_ativo_unico on public.ranking_periodos ((true)) where estado = 'ativo';
create table if not exists public.ranking_pontos (
  periodo int not null references public.ranking_periodos (id) on delete cascade,
  jogador uuid not null references public.jogadores (id) on delete cascade,
  pontos int not null default 0,
  primary key (periodo, jogador)
);
create table if not exists public.ranking_eventos (
  id bigint generated always as identity primary key,
  periodo int not null references public.ranking_periodos (id) on delete cascade,
  jogador uuid not null references public.jogadores (id) on delete cascade,
  grupo text not null,                      -- npc | selv | duelo | mestre
  motivo text not null,
  ref text,
  pontos int not null,
  dia_jogo date not null,
  criado_em timestamptz not null default now()
);
create index if not exists ranking_eventos_dia on public.ranking_eventos (jogador, dia_jogo, grupo);
create table if not exists public.ranking_rivais (
  id text primary key,
  nome text not null,
  fator numeric not null default 0.5,       -- fração dos pontos do líder
  ativo boolean not null default true
);
create table if not exists public.ranking_rivais_pontos (
  periodo int not null references public.ranking_periodos (id) on delete cascade,
  rival text not null references public.ranking_rivais (id) on delete cascade,
  pontos int not null default 0,
  primary key (periodo, rival)
);
create table if not exists public.ranking_premios_jogador (
  id bigint generated always as identity primary key,
  jogador uuid not null references public.jogadores (id) on delete cascade,
  periodo int not null references public.ranking_periodos (id) on delete cascade,
  posicao int,                              -- 1..3 pódio; null = participação
  pontos int not null default 0,
  premio jsonb not null default '{}'::jsonb,
  avisado boolean not null default false,
  criado_em timestamptz not null default now()
);
create table if not exists public.treinadores_revanche (
  jogador uuid not null references public.jogadores (id) on delete cascade,
  treinador text not null references public.treinadores (id) on delete cascade,
  dia_jogo date not null,
  primary key (jogador, treinador)
);
do $$ declare t text; begin
  foreach t in array array['ranking_periodos', 'ranking_pontos', 'ranking_eventos', 'ranking_rivais', 'ranking_rivais_pontos', 'ranking_premios_jogador', 'treinadores_revanche'] loop
    execute format('alter table public.%I enable row level security', t);
  end loop;
end $$;
drop policy if exists rk_ev_dono on public.ranking_eventos;
create policy rk_ev_dono on public.ranking_eventos for select to authenticated using (jogador = auth.uid() or public.eh_mestre());
drop policy if exists rk_pr_dono on public.ranking_premios_jogador;
create policy rk_pr_dono on public.ranking_premios_jogador for select to authenticated using (jogador = auth.uid() or public.eh_mestre());
grant select on public.ranking_eventos, public.ranking_premios_jogador to authenticated;

insert into public.config (chave, valor) values
  ('ranking_duracao_dias', '14'::jsonb),
  ('ranking_pontos', '{"selvagem":1,"captura":2,"treinador":5,"lider":15,"duelo_vitoria":20,"duelo_derrota":5}'::jsonb),
  ('ranking_tetos', '{"npc":150,"selv":30}'::jsonb),
  ('ranking_pares', '[1,0.6,0.3]'::jsonb),
  ('ranking_premios', '{"minimo":30,"podio":[{"dinheiro":5000,"xp_treinador":500,"titulo":"campeao_temporada","itens":[{"item":"rare-candy","qtd":3}]},{"dinheiro":3000,"xp_treinador":300,"titulo":"vice_temporada","itens":[{"item":"rare-candy","qtd":2}]},{"dinheiro":2000,"xp_treinador":200,"titulo":"terceiro_temporada","itens":[{"item":"rare-candy","qtd":1}]}],"participacao":{"dinheiro":500,"xp_treinador":50}}'::jsonb)
on conflict (chave) do nothing;

insert into public.ranking_rivais (id, nome, fator) values
  ('rv_blue', 'Blue', 0.85), ('rv_red', 'Red', 0.7), ('rv_misty', 'Misty', 0.55),
  ('rv_brock', 'Brock', 0.45), ('rv_erika', 'Erika', 0.3), ('rv_koga', 'Koga', 0.2)
on conflict (id) do nothing;

-- ---------- período ----------
create or replace function public._ranking_fechar(p_id int) returns void language plpgsql security definer set search_path = public as $$
declare pr jsonb := coalesce((select valor from public.config where chave = 'ranking_premios'), '{}'::jsonb); minimo int := coalesce((pr ->> 'minimo')::int, 0);
  r record; pos int := 0; prem jsonb;
begin
  update public.ranking_periodos set estado = 'fechado' where id = p_id and estado = 'ativo';
  if not found then return; end if;
  for r in select rp.jogador, rp.pontos from public.ranking_pontos rp join public.jogadores j on j.id = rp.jogador
            where rp.periodo = p_id and rp.pontos >= greatest(minimo, 1) order by rp.pontos desc, rp.jogador loop
    pos := pos + 1;
    prem := case when pos <= 3 then coalesce(pr -> 'podio' -> (pos - 1), '{}'::jsonb) else coalesce(pr -> 'participacao', '{}'::jsonb) end;
    insert into public.ranking_premios_jogador (jogador, periodo, posicao, pontos, premio, avisado)
    values (r.jogador, p_id, case when pos <= 3 then pos end, r.pontos, public._conceder(r.jogador, prem), false);
  end loop;
end $$;
revoke all on function public._ranking_fechar(int) from public, anon, authenticated;

-- devolve o id do período ativo; fecha o vencido e abre outro quando necessário
create or replace function public._ranking_periodo() returns int language plpgsql security definer set search_path = public as $$
declare a public.ranking_periodos; d date := public._dia_jogo(); dur int := greatest(1, public._cfg_int('ranking_duracao_dias', 14)); novo int;
begin
  select * into a from public.ranking_periodos where estado = 'ativo';
  if found and d < a.fim then return a.id; end if;
  perform pg_advisory_xact_lock(7702);
  select * into a from public.ranking_periodos where estado = 'ativo';
  if found then
    if d < a.fim then return a.id; end if;
    perform public._ranking_fechar(a.id);
  end if;
  insert into public.ranking_periodos (inicio, fim) values (d, d + dur) returning id into novo;
  return novo;
end $$;
revoke all on function public._ranking_periodo() from public, anon, authenticated;

-- grupo: npc | selv | duelo | mestre. Aplica teto diário por grupo e fator de repetição de duelo com o mesmo oponente.
create or replace function public._ranking_pontuar(p_j uuid, p_grupo text, p_motivo text, p_ref text, p_base numeric) returns int
language plpgsql security definer set search_path = public as $$
declare per int; d date := public._dia_jogo(); teto int; usado int; pts int; pares jsonb; fator numeric := 1; n int;
begin
  if not public._modulo('ranking') or p_base is null or p_base <= 0 then return 0; end if;
  per := public._ranking_periodo();
  if p_grupo = 'duelo' and p_ref is not null then
    pares := coalesce((select valor from public.config where chave = 'ranking_pares'), '[1]'::jsonb);
    select count(*) into n from public.ranking_eventos where jogador = p_j and dia_jogo = d and grupo = 'duelo' and ref = p_ref;
    fator := case when n < jsonb_array_length(pares) then (pares ->> n)::numeric else 0 end;
  end if;
  pts := round(p_base * fator);
  teto := (select (valor ->> p_grupo)::int from public.config where chave = 'ranking_tetos');
  if teto is not null then
    select coalesce(sum(pontos), 0) into usado from public.ranking_eventos where jogador = p_j and dia_jogo = d and grupo = p_grupo;
    pts := least(pts, greatest(teto - usado, 0));
  end if;
  if pts <= 0 then return 0; end if;
  insert into public.ranking_eventos (periodo, jogador, grupo, motivo, ref, pontos, dia_jogo) values (per, p_j, p_grupo, p_motivo, p_ref, pts, d);
  insert into public.ranking_pontos (periodo, jogador, pontos) values (per, p_j, pts)
  on conflict (periodo, jogador) do update set pontos = public.ranking_pontos.pontos + excluded.pontos;
  return pts;
end $$;
revoke all on function public._ranking_pontuar(uuid, text, text, text, numeric) from public, anon, authenticated;

-- gatilho separado do de conquistas: um erro aqui nunca afeta batalha nem conquistas
create or replace function public._tg_batalha_ranking() returns trigger language plpgsql security definer set search_path = public as $$
declare cfg jsonb := coalesce((select valor from public.config where chave = 'ranking_pontos'), '{}'::jsonb); lid boolean; opp uuid;
begin
  if old.estado = 'ativa' and new.estado <> 'ativa' then
    begin
      if new.tipo = 'selvagem' then
        if new.estado = 'captura' then perform public._ranking_pontuar(new.jogador, 'selv', 'captura', null, coalesce((cfg ->> 'captura')::numeric, 2));
        elsif new.estado = 'vitoria' then perform public._ranking_pontuar(new.jogador, 'selv', 'selvagem', null, coalesce((cfg ->> 'selvagem')::numeric, 1)); end if;
      elsif new.tipo = 'treinador' and new.estado = 'vitoria' then
        select coalesce(t.lider, false) into lid from public.treinadores t where t.id = new.treinador;
        perform public._ranking_pontuar(new.jogador, 'npc', case when new.revanche then 'revanche' else 'treinador' end, new.treinador,
                  case when lid then coalesce((cfg ->> 'lider')::numeric, 15) else coalesce((cfg ->> 'treinador')::numeric, 5) end);
      elsif new.tipo = 'duelo' and new.estado in ('vitoria', 'derrota') and not new.amistoso then
        select b.jogador into opp from public.batalhas b where b.id = new.par;
        perform public._ranking_pontuar(new.jogador, 'duelo', case when new.estado = 'vitoria' then 'duelo_vitoria' else 'duelo_derrota' end, opp::text,
                  coalesce((cfg ->> case when new.estado = 'vitoria' then 'duelo_vitoria' else 'duelo_derrota' end)::numeric, 5));
      end if;
    exception when others then
      raise warning 'tg_batalha_ranking falhou: %', sqlerrm;
    end;
  end if;
  return new;
end $$;
drop trigger if exists tg_batalha_ranking on public.batalhas;
create trigger tg_batalha_ranking after update of estado on public.batalhas for each row execute function public._tg_batalha_ranking();

-- ---------- leitura ----------
create or replace function public.ranking_tabela() returns jsonb language plpgsql security definer set search_path = public as $$
declare per public.ranking_periodos; lider int; r record; d date := public._dia_jogo(); jit numeric; novo int; linhas jsonb;
begin
  if auth.uid() is null or not public._modulo('ranking') then return jsonb_build_object('ativo', false); end if;
  select * into per from public.ranking_periodos where id = public._ranking_periodo();
  select coalesce(max(pontos), 0) into lider from public.ranking_pontos where periodo = per.id;
  -- os rivais NPC orbitam o líder (com variação diária estável) e nunca diminuem
  for r in select * from public.ranking_rivais where ativo loop
    jit := ((abs(hashtext(r.id || d::text)) % 21) - 10) / 100.0;
    novo := round(lider * r.fator * (1 + jit));
    insert into public.ranking_rivais_pontos (periodo, rival, pontos) values (per.id, r.id, novo)
    on conflict (periodo, rival) do update set pontos = greatest(public.ranking_rivais_pontos.pontos, excluded.pontos);
  end loop;
  select coalesce(jsonb_agg(x order by (x ->> 'pontos')::int desc, x ->> 'nome'), '[]'::jsonb) into linhas from (
    select jsonb_build_object('nome', j.nome, 'pontos', rp.pontos, 'npc', false, 'eu', j.id = auth.uid(), 'titulo', (select c.nome from public.cosmeticos_catalogo c where c.id = j.titulo_ativo),
             'moldura', (select c.estilo from public.cosmeticos_catalogo c where c.id = j.moldura_ativa)) as x
      from public.ranking_pontos rp join public.jogadores j on j.id = rp.jogador where rp.periodo = per.id and rp.pontos > 0
    union all
    select jsonb_build_object('nome', rv.nome, 'pontos', rvp.pontos, 'npc', true, 'eu', false)
      from public.ranking_rivais_pontos rvp join public.ranking_rivais rv on rv.id = rvp.rival where rvp.periodo = per.id and rv.ativo and rvp.pontos > 0
  ) t;
  return jsonb_build_object('ativo', true, 'periodo', jsonb_build_object('id', per.id, 'inicio', per.inicio, 'fim', per.fim, 'dias_restantes', greatest(per.fim - d, 0)),
    'meus_pontos', coalesce((select pontos from public.ranking_pontos where periodo = per.id and jogador = auth.uid()), 0),
    'premios', coalesce((select valor from public.config where chave = 'ranking_premios'), '{}'::jsonb), 'linhas', linhas);
end $$;

-- prêmios que ainda não foram mostrados ao jogador (marca como avisados)
create or replace function public.ranking_meus_premios() returns jsonb language plpgsql security definer set search_path = public as $$
declare r jsonb;
begin
  if auth.uid() is null then return '[]'::jsonb; end if;
  with u as (update public.ranking_premios_jogador set avisado = true where jogador = auth.uid() and not avisado returning posicao, pontos, premio, periodo)
  select coalesce(jsonb_agg(jsonb_build_object('posicao', posicao, 'pontos', pontos, 'premio', premio, 'periodo', periodo)), '[]'::jsonb) into r from u;
  return r;
end $$;

-- ids de NPCs que aceitam revanche hoje (já vencidos e ainda não reenfrentados neste dia de jogo)
create or replace function public.revanche_disponivel() returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if auth.uid() is null or not public._modulo('ranking') then return '[]'::jsonb; end if;
  return coalesce((select jsonb_agg(tv.treinador) from public.treinadores_vencidos tv
                    where tv.jogador = auth.uid() and not exists (select 1 from public.treinadores_revanche r where r.jogador = tv.jogador and r.treinador = tv.treinador and r.dia_jogo >= public._dia_jogo())), '[]'::jsonb);
end $$;

-- ---------- Mestre ----------
create or replace function public.mestre_ranking_obter() returns jsonb language plpgsql security definer set search_path = public as $$
declare per int;
begin
  if not public.eh_mestre() then raise exception 'Só o Mestre.'; end if;
  per := public._ranking_periodo();
  return jsonb_build_object(
    'periodo', (select to_jsonb(p) from public.ranking_periodos p where p.id = per),
    'duracao', public._cfg_int('ranking_duracao_dias', 14),
    'pontos', (select valor from public.config where chave = 'ranking_pontos'),
    'tetos', (select valor from public.config where chave = 'ranking_tetos'),
    'pares', (select valor from public.config where chave = 'ranking_pares'),
    'premios', (select valor from public.config where chave = 'ranking_premios'),
    'rivais', coalesce((select jsonb_agg(to_jsonb(r) order by r.nome) from public.ranking_rivais r), '[]'::jsonb),
    'jogadores', coalesce((select jsonb_agg(jsonb_build_object('id', j.id, 'nome', j.nome, 'pontos', rp.pontos) order by rp.pontos desc)
                             from public.ranking_pontos rp join public.jogadores j on j.id = rp.jogador where rp.periodo = per), '[]'::jsonb));
end $$;

create or replace function public.mestre_ranking_salvar(p jsonb) returns void language plpgsql security definer set search_path = public as $$
declare k text; r jsonb; pd jsonb;
begin
  if not public.eh_mestre() then raise exception 'Só o Mestre.'; end if;
  if p ? 'duracao' then
    if (p ->> 'duracao')::int not between 1 and 120 then raise exception 'A duração vai de 1 a 120 dias.'; end if;
    insert into public.config (chave, valor) values ('ranking_duracao_dias', to_jsonb((p ->> 'duracao')::int)) on conflict (chave) do update set valor = excluded.valor;
    if coalesce((p ->> 'aplicar_atual')::boolean, false) then
      update public.ranking_periodos set fim = inicio + (p ->> 'duracao')::int where estado = 'ativo';
    end if;
  end if;
  if p ? 'premios' then
    for pd in select * from jsonb_array_elements(coalesce(p -> 'premios' -> 'podio', '[]'::jsonb)) loop perform public._payload_ok(pd); end loop;
    perform public._payload_ok(p -> 'premios' -> 'participacao');
  end if;
  foreach k in array array['pontos', 'tetos', 'pares', 'premios'] loop
    if p ? k then
      insert into public.config (chave, valor) values ('ranking_' || k, p -> k) on conflict (chave) do update set valor = excluded.valor;
    end if;
  end loop;
  for r in select * from jsonb_array_elements(coalesce(p -> 'rivais', '[]'::jsonb)) loop
    update public.ranking_rivais set fator = coalesce((r ->> 'fator')::numeric, fator), ativo = coalesce((r ->> 'ativo')::boolean, ativo), nome = coalesce(nullif(r ->> 'nome', ''), nome)
     where id = r ->> 'id';
  end loop;
end $$;

create or replace function public.mestre_ranking_fechar() returns void language plpgsql security definer set search_path = public as $$
declare a int;
begin
  if not public.eh_mestre() then raise exception 'Só o Mestre.'; end if;
  select id into a from public.ranking_periodos where estado = 'ativo';
  if a is not null then perform public._ranking_fechar(a); end if;
  perform public._ranking_periodo();
end $$;

create or replace function public.mestre_ranking_ajustar(p_jogador uuid, p_delta int, p_motivo text) returns void language plpgsql security definer set search_path = public as $$
declare per int := public._ranking_periodo();
begin
  if not public.eh_mestre() then raise exception 'Só o Mestre.'; end if;
  if p_delta = 0 or abs(p_delta) > 100000 then raise exception 'Valor inválido.'; end if;
  insert into public.ranking_eventos (periodo, jogador, grupo, motivo, pontos, dia_jogo) values (per, p_jogador, 'mestre', coalesce(nullif(p_motivo, ''), 'ajuste do Mestre'), p_delta, public._dia_jogo());
  insert into public.ranking_pontos (periodo, jogador, pontos) values (per, p_jogador, greatest(p_delta, 0))
  on conflict (periodo, jogador) do update set pontos = greatest(public.ranking_pontos.pontos + p_delta, 0);
end $$;

do $$ declare f text; begin
  foreach f in array array['ranking_tabela()', 'ranking_meus_premios()', 'revanche_disponivel()', 'mestre_ranking_obter()', 'mestre_ranking_salvar(jsonb)', 'mestre_ranking_fechar()', 'mestre_ranking_ajustar(uuid,int,text)'] loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;

-- ---------- patches nas funções de batalha (revanche contra NPC) ----------

create or replace function public.desafiar_treinador(p_treinador text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_j public.jogadores; v_t public.treinadores; v_b public.batalhas; v_ativo uuid; v_falta int; v_rev boolean := false;
  begin
  if auth.uid() is null then raise exception 'Faça login primeiro.'; end if;
  select * into v_j from public.jogadores where id = auth.uid() for update;
  if not found then raise exception 'Crie seu personagem primeiro.'; end if;
  select * into v_b from public.batalhas where jogador = v_j.id and estado = 'ativa';
  if found then return jsonb_build_object('batalha', to_jsonb(v_b) - 'sim' - 'meta'); end if;
  select * into v_t from public.treinadores where id = p_treinador and mapa_id = v_j.mapa_id;
  if not found then raise exception 'Não há esse treinador por aqui.'; end if;
  if exists (select 1 from public.treinadores_vencidos where jogador = v_j.id and treinador = v_t.id) then
    if public._modulo('ranking') and not exists (select 1 from public.treinadores_revanche r where r.jogador = v_j.id and r.treinador = v_t.id and r.dia_jogo >= public._dia_jogo()) then
      v_rev := true;
    elsif public._modulo('ranking') then
      raise exception '% só aceita nova revanche a partir da virada do dia.', v_t.nome;
    else
      raise exception 'Você já derrotou % .', v_t.nome;
    end if;
  end if;
  -- líder (ginásio/Liga): antes é preciso vencer todos os outros treinadores do mesmo local
  if v_t.lider then
    select count(*) into v_falta from public.treinadores o
     where o.mapa_id = v_t.mapa_id and o.id <> v_t.id and not o.lider
       and not exists (select 1 from public.treinadores_vencidos tv where tv.jogador = v_j.id and tv.treinador = o.id);
    if v_falta > 0 then
      raise exception '% só aceita o desafio de quem venceu antes todos os treinadores do ginásio (faltam %).', v_t.nome, v_falta;
    end if;
  end if;
  -- o treinador só desafia quando o jogador puxa conversa: precisa estar num tile ao lado dele
  if abs(v_t.x - v_j.x) + abs(v_t.y - v_j.y) <> 1 then raise exception 'Chegue ao lado de % para conversar.', v_t.nome; end if;
  select id into v_ativo from public.pokemons where dono = v_j.id and posicao is not null and hp_atual > 0 order by posicao limit 1;
  if v_ativo is null then
    if exists (select 1 from public.pokemons where dono = v_j.id) then raise exception 'Seus Pokémon estão desmaiados. Cure-os no Centro Pokémon ou em casa.';
    else raise exception 'Você ainda não tem Pokémon. Fale com o Professor Carvalho no laboratório.'; end if;
  end if;
  insert into public.batalhas (jogador, selvagem, ativo, tipo, treinador, adversarios, revanche)
  values (v_j.id, '{}'::jsonb, v_ativo, 'treinador', v_t.id, case when v_t.escala is not null then public._equipe_escalada(v_t, public._nivel_ref(v_j.id)) else public._equipe_treinador(v_t.equipe) end, v_rev) returning * into v_b;
  if v_rev then
    insert into public.treinadores_revanche (jogador, treinador, dia_jogo) values (v_j.id, v_t.id, public._dia_jogo())
    on conflict (jogador, treinador) do update set dia_jogo = excluded.dia_jogo;
  end if;
  return jsonb_build_object('batalha', to_jsonb(v_b) - 'sim' - 'meta', 'treinador', jsonb_build_object('nome', v_t.nome, 'classe', v_t.classe));
end $$;

create or replace function public.sim_gravar(
  p_batalha uuid, p_turno int, p_sim jsonb, p_meta jsonb, p_log_len int, p_time jsonb, p_fim text, p_exp jsonb default '[]'::jsonb
) returns jsonb language plpgsql security definer set search_path = public as $$
declare
  b public.batalhas; t public.treinadores; m jsonb; ev jsonb := '[]'::jsonb; pk public.pokemons; pk2 public.pokemons; novo jsonb; i int; k int; sel jsonb; part uuid[]; n int; x jsonb;
begin
  select * into b from public.batalhas where id = p_batalha for update;
  if not found or b.estado <> 'ativa' then raise exception 'Batalha encerrada.'; end if;
  if b.turno <> p_turno then raise exception 'Outra ação já foi processada. Tente de novo.'; end if;
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
  update public.batalhas set sim = p_sim, meta = p_meta, log_len = p_log_len, turno = turno + 1,
         ativo = coalesce((p_meta->>'ativo')::uuid, ativo) where id = b.id;
  if p_fim is not null then
    update public.batalhas set estado = p_fim where id = b.id;
    if p_fim = 'vitoria' and b.tipo = 'treinador' and b.treinador is not null then
      select * into t from public.treinadores where id = b.treinador;
      insert into public.treinadores_vencidos (jogador, treinador) values (b.jogador, b.treinador) on conflict do nothing;
      if t.insignia is not null then
        update public.jogadores set insignias = (select array_agg(distinct s) from unnest(insignias || t.insignia) s) where id = b.jogador;
        ev := ev || jsonb_build_array(jsonb_build_object('t', 'insignia', 'nome', t.insignia, 'lider', t.nome));
      end if;
      if t.id = 'liga_campeao_chefe' then
        update public.jogadores set campeao = true where id = b.jogador;
        ev := ev || jsonb_build_array(jsonb_build_object('t', 'campeao', 'nome', t.nome));
      end if;
      if t.recompensa > 0 and not coalesce(b.revanche, false) then
        update public.jogadores set dinheiro = dinheiro + floor(t.recompensa * public._ev('dinheiro', 1) * (1 + public._bonus(b.jogador, 'recompensa') / 100.0)) where id = b.jogador;
        ev := ev || jsonb_build_array(jsonb_build_object('t', 'dinheiro', 'valor', floor(t.recompensa * public._ev('dinheiro', 1) * (1 + public._bonus(b.jogador, 'recompensa') / 100.0)), 'nome', t.nome));
      end if;
      if coalesce(t.falas->>'derrota', '') <> '' then
        ev := ev || jsonb_build_array(jsonb_build_object('t', 'fala', 'nome', t.nome, 'texto', t.falas->>'derrota'));
      end if;
    end if;
    if p_fim = 'vitoria' and jsonb_array_length(p_exp) > 0 and not coalesce(b.revanche, false) then
      select array_agg(distinct (e)::uuid) into part from jsonb_array_elements_text(p_meta->'participantes') e;
      n := coalesce(array_length(part, 1), 1);
      n := greatest(1, (select count(*) from public.pokemons where dono = b.jogador and posicao is not null and hp_atual > 0));
      for pk in select * from public.pokemons where dono = b.jogador and posicao is not null and hp_atual > 0 loop
        for x in select * from jsonb_array_elements(p_exp) loop
          sel := jsonb_build_object('exp_base', greatest(1, round((x->>'exp_base')::numeric * public._xp_mult_time() / n)), 'nivel', (x->>'nivel')::int);
          select * into pk2 from public.pokemons where id = pk.id;
          ev := public._dar_exp(pk2, sel, ev);
        end loop;
      end loop;
      -- Cura Rápida: recupera uma parte do HP de quem lutou
      if public._bonus(b.jogador, 'cura_rapida') > 0 then
        update public.pokemons set hp_atual = least(hp_max, hp_atual + ceil(hp_max * public._bonus(b.jogador, 'cura_rapida') / 100.0)::int)
         where id = any(coalesce(part, '{}')) and dono = b.jogador and hp_atual > 0;
      end if;
    end if;
  end if;
  return ev;
end $$;
