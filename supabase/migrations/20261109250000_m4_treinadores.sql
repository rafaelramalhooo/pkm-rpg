-- M4: treinadores NPC (batalhas contra equipes, recompensa em dinheiro, uma vez por jogador).

create table if not exists public.treinadores (
  id text primary key,
  mapa_id text not null references public.mapas (id) on delete cascade,
  x int not null, y int not null,
  direcao text not null default 'baixo' check (direcao in ('cima','baixo','esquerda','direita')),
  visao int not null default 3 check (visao between 1 and 8),
  nome text not null,
  classe text not null default 'Treinador',
  aparencia smallint not null default 0,
  recompensa int not null default 0 check (recompensa >= 0),
  falas jsonb not null default '{}'::jsonb,      -- {antes, derrota}
  equipe jsonb not null,                          -- [{especie, nivel}]
  arco smallint not null default 1
);
create table if not exists public.treinadores_vencidos (
  jogador uuid not null references public.jogadores (id) on delete cascade,
  treinador text not null references public.treinadores (id) on delete cascade,
  em timestamptz not null default now(),
  primary key (jogador, treinador)
);
alter table public.treinadores enable row level security;
alter table public.treinadores_vencidos enable row level security;
drop policy if exists "treinadores_leitura" on public.treinadores;
create policy "treinadores_leitura" on public.treinadores for select to authenticated using (true);
drop policy if exists "vencidos_dono" on public.treinadores_vencidos;
create policy "vencidos_dono" on public.treinadores_vencidos for select to authenticated using (jogador = auth.uid() or public.eh_mestre());
grant select on public.treinadores, public.treinadores_vencidos to authenticated;

alter table public.batalhas add column if not exists treinador text references public.treinadores (id) on delete set null;

-- importação pelo Mestre: acrescenta "treinadores"
create or replace function public.importar_treinadores(p_linhas jsonb) returns int
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if not public.eh_mestre() then raise exception 'Só o Mestre importa dados.'; end if;
  insert into public.treinadores (id, mapa_id, x, y, direcao, visao, nome, classe, aparencia, recompensa, falas, equipe, arco)
  select id, mapa_id, x, y, coalesce(direcao, 'baixo'), coalesce(visao, 3), nome, coalesce(classe, 'Treinador'), coalesce(aparencia, 0),
         coalesce(recompensa, 0), coalesce(falas, '{}'::jsonb), equipe, coalesce(arco, 1)
    from jsonb_populate_recordset(null::public.treinadores, p_linhas)
  on conflict (id) do update set mapa_id = excluded.mapa_id, x = excluded.x, y = excluded.y, direcao = excluded.direcao, visao = excluded.visao,
    nome = excluded.nome, classe = excluded.classe, aparencia = excluded.aparencia, recompensa = excluded.recompensa, falas = excluded.falas,
    equipe = excluded.equipe, arco = excluded.arco;
  get diagnostics n = row_count;
  insert into public.auditoria (ator, acao, detalhe) values (auth.uid(), 'importar_dados', jsonb_build_object('tabela', 'treinadores', 'linhas', n));
  return n;
end $$;
revoke all on function public.importar_treinadores(jsonb) from public, anon;
grant execute on function public.importar_treinadores(jsonb) to authenticated;

-- monta a equipe (com golpes, natureza e experiência) a partir do JSON do treinador
create or replace function public._equipe_treinador(p_equipe jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare x jsonb; e public.especies; nat text; res jsonb := '[]'::jsonb; gj jsonb;
begin
  for x in select * from jsonb_array_elements(p_equipe) loop
    select * into e from public.especies where id = (x->>'especie')::int;
    if not found then raise exception 'Espécie % inexistente na equipe.', x->>'especie'; end if;
    select nome into nat from public.naturezas order by random() limit 1;
    gj := public.golpes_do_nivel(e.id, (x->>'nivel')::int);
    if jsonb_array_length(gj) = 0 then
      gj := (select jsonb_build_array(jsonb_build_object('id', g.id, 'pp', g.pp)) from public.golpes g where g.slug = 'tackle');
    end if;
    res := res || jsonb_build_array(jsonb_build_object('especie_id', e.id, 'nome', e.nome, 'nivel', (x->>'nivel')::int,
        'natureza', coalesce(nat, 'hardy'), 'exp_base', floor(e.exp_base * 1.5), 'golpes', gj));
  end loop;
  return res;
end $$;
revoke all on function public._equipe_treinador(jsonb) from public, anon, authenticated;

-- o jogador entra na linha de visão (ou fala com) o treinador: começa a batalha
create or replace function public.desafiar_treinador(p_treinador text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_j public.jogadores; v_t public.treinadores; v_b public.batalhas; v_m public.mapas; v_ativo uuid;
  dx int := 0; dy int := 0; k int; tx int; ty int; visto boolean := false;
begin
  if auth.uid() is null then raise exception 'Faça login primeiro.'; end if;
  select * into v_j from public.jogadores where id = auth.uid() for update;
  if not found then raise exception 'Crie seu personagem primeiro.'; end if;
  select * into v_b from public.batalhas where jogador = v_j.id and estado = 'ativa';
  if found then return jsonb_build_object('batalha', to_jsonb(v_b) - 'sim' - 'meta'); end if;
  select * into v_t from public.treinadores where id = p_treinador and mapa_id = v_j.mapa_id;
  if not found then raise exception 'Não há esse treinador por aqui.'; end if;
  if exists (select 1 from public.treinadores_vencidos where jogador = v_j.id and treinador = v_t.id) then
    raise exception 'Você já derrotou % .', v_t.nome;
  end if;
  select * into v_m from public.mapas where id = v_j.mapa_id;
  if v_t.direcao = 'cima' then dy := -1; elsif v_t.direcao = 'baixo' then dy := 1; elsif v_t.direcao = 'esquerda' then dx := -1; else dx := 1; end if;
  for k in 1 .. v_t.visao loop
    tx := v_t.x + dx * k; ty := v_t.y + dy * k;
    if tx < 0 or ty < 0 or tx >= v_m.largura or ty >= v_m.altura then exit; end if;
    if tx = v_j.x and ty = v_j.y then visto := true; exit; end if;
    if substr(v_m.solido, ty * v_m.largura + tx + 1, 1) = '1' then exit; end if;
  end loop;
  if not visto then raise exception 'Você não está na linha de visão de %.', v_t.nome; end if;
  select id into v_ativo from public.pokemons where dono = v_j.id and posicao is not null and hp_atual > 0 order by posicao limit 1;
  if v_ativo is null then
    if exists (select 1 from public.pokemons where dono = v_j.id) then raise exception 'Seus Pokémon estão desmaiados. Cure-os no Centro Pokémon ou em casa.';
    else raise exception 'Você ainda não tem Pokémon. Fale com o Professor Carvalho no laboratório.'; end if;
  end if;
  insert into public.batalhas (jogador, selvagem, ativo, tipo, treinador, adversarios)
  values (v_j.id, '{}'::jsonb, v_ativo, 'treinador', v_t.id, public._equipe_treinador(v_t.equipe)) returning * into v_b;
  return jsonb_build_object('batalha', to_jsonb(v_b) - 'sim' - 'meta', 'treinador', jsonb_build_object('nome', v_t.nome, 'classe', v_t.classe));
end $$;
revoke all on function public.desafiar_treinador(text) from public, anon;
grant execute on function public.desafiar_treinador(text) to authenticated;

-- ===== grava o resultado de um turno =====
-- p_time: [{id, hp, pp:[...]}]; p_exp: [{exp_base, nivel}] (adversários derrotados) ; p_fim: null|vitoria|derrota|fuga
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
      if t.recompensa > 0 then
        update public.jogadores set dinheiro = dinheiro + t.recompensa where id = b.jogador;
        ev := ev || jsonb_build_array(jsonb_build_object('t', 'dinheiro', 'valor', t.recompensa, 'nome', t.nome));
      end if;
      if coalesce(t.falas->>'derrota', '') <> '' then
        ev := ev || jsonb_build_array(jsonb_build_object('t', 'fala', 'nome', t.nome, 'texto', t.falas->>'derrota'));
      end if;
    end if;
    if p_fim = 'vitoria' and jsonb_array_length(p_exp) > 0 then
      select array_agg(distinct (e)::uuid) into part from jsonb_array_elements_text(p_meta->'participantes') e;
      n := coalesce(array_length(part, 1), 1);
      for pk in select * from public.pokemons where id = any(coalesce(part, '{}')) and dono = b.jogador and hp_atual > 0 loop
        for x in select * from jsonb_array_elements(p_exp) loop
          sel := jsonb_build_object('exp_base', greatest(1, floor((x->>'exp_base')::numeric / n)), 'nivel', (x->>'nivel')::int);
          select * into pk2 from public.pokemons where id = pk.id;
          ev := public._dar_exp(pk2, sel, ev);
        end loop;
      end loop;
    end if;
  end if;
  return ev;
end $$;


revoke all on function public.sim_gravar(uuid,int,jsonb,jsonb,int,jsonb,text,jsonb) from public, anon, authenticated;
grant execute on function public.sim_gravar(uuid,int,jsonb,jsonb,int,jsonb,text,jsonb) to service_role;

-- resetar_jogador também apaga os treinadores vencidos
create or replace function public.resetar_jogador(p_jogador uuid)
returns text language plpgsql security definer set search_path = public as $$
declare v_nome text; v_m public.mapas;
begin
  if not public.eh_mestre() then raise exception 'Só o Mestre pode resetar jogadores.'; end if;
  select nome into v_nome from public.jogadores where id = p_jogador;
  if not found then raise exception 'Jogador não encontrado.'; end if;
  select * into v_m from public.mapas where id = 'pallet';
  delete from public.batalhas where jogador = p_jogador;
  delete from public.treinadores_vencidos where jogador = p_jogador;
  delete from public.pokemons where dono = p_jogador;
  delete from public.inventario where jogador = p_jogador;
  delete from public.pokedex where jogador = p_jogador;
  update public.jogadores
     set mapa_id = 'pallet', x = coalesce(v_m.spawn_x, 16), y = coalesce(v_m.spawn_y, 21), direcao = 'baixo',
         pa = coalesce((select (valor #>> '{}')::smallint from public.config where chave = 'pa_por_dia'), 30),
         dinheiro = 1000, posicao_em = now()
   where id = p_jogador;
  insert into public.auditoria (ator, acao, detalhe) values (auth.uid(), 'resetar_jogador', jsonb_build_object('jogador', p_jogador, 'nome', v_nome));
  return v_nome;
end $$;
