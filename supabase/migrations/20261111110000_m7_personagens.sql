-- M7: até 2 personagens independentes por conta + reiniciar o jogo.
-- Desenho: a linha ATIVA da conta continua sendo jogadores.id = auth.uid() (nada do resto do jogo muda: RLS, funções, Edge Function).
-- O outro personagem fica "guardado" em outra linha de `jogadores` com conta = auth.uid(). Trocar de personagem troca o CONTEÚDO
-- das duas linhas e reaponta todos os dados filhos (Pokémon, mochila, Pokédex, vitórias...), descobertos pelas chaves estrangeiras.

alter table public.jogadores add column if not exists conta uuid;   -- null = linha ativa; preenchido = personagem guardado (dono = conta)
create index if not exists jogadores_conta_idx on public.jogadores (conta) where conta is not null;

-- colunas copiadas na troca (tudo menos id, conta e papel)
create or replace function public._cols_personagem(p_nome_expr text default null) returns text language sql stable set search_path = public as $$
  select string_agg(case when attname = 'nome' and p_nome_expr is not null then p_nome_expr else quote_ident(attname) end, ', ' order by attnum)
    from pg_attribute where attrelid = 'public.jogadores'::regclass and attnum > 0 and not attisdropped and attname not in ('id', 'conta', 'papel') $$;

create or replace function public._filhos_mover(p_de uuid, p_para uuid) returns void language plpgsql security definer set search_path = public as $$
declare r record;
begin
  for r in
    select c.conrelid::regclass::text as tabela, a.attname::text as coluna
      from pg_constraint c join pg_attribute a on a.attrelid = c.conrelid and a.attnum = c.conkey[1]
     where c.contype = 'f' and c.confrelid = 'public.jogadores'::regclass and array_length(c.conkey, 1) = 1
  loop
    execute format('update %s set %I = $1 where %I = $2', r.tabela, r.coluna, r.coluna) using p_para, p_de;
  end loop;
end $$;

create or replace function public._nome_tmp(p_id uuid) returns text language sql immutable as $$ select 'tmp' || substr(replace(p_id::text, '-', ''), 1, 8) $$;

-- troca o conteúdo da linha ativa (p_a) com o da linha guardada (p_b)
create or replace function public._trocar(p_a uuid, p_b uuid) returns void language plpgsql security definer set search_path = public as $$
declare v_p uuid := gen_random_uuid(); v_na text; v_nb text; v_cols text := public._cols_personagem();
begin
  select nome into v_na from public.jogadores where id = p_a;
  select nome into v_nb from public.jogadores where id = p_b;
  delete from public.ofertas where jogador in (p_a, p_b);
  update public.jogadores set rolagem = null where id in (p_a, p_b);
  -- cópia temporária do ativo
  execute format('insert into public.jogadores (id, conta, %s) select $1, $2, %s from public.jogadores where id = $3',
                 v_cols, public._cols_personagem($q$('tmp' || substr(replace($1::text, '-', ''), 1, 8))$q$)) using v_p, p_b, p_a;
  perform public._filhos_mover(p_a, v_p);
  update public.jogadores set nome = public._nome_tmp(p_b) where id = p_b;
  execute format('update public.jogadores t set (%s) = (select %s from public.jogadores s where s.id = $1) where t.id = $2', v_cols, v_cols) using p_b, p_a;
  update public.jogadores set nome = v_nb where id = p_a;
  perform public._filhos_mover(p_b, p_a);
  execute format('update public.jogadores t set (%s) = (select %s from public.jogadores s where s.id = $1) where t.id = $2', v_cols, v_cols) using v_p, p_b;
  update public.jogadores set nome = v_na where id = p_b;
  perform public._filhos_mover(v_p, p_b);
  delete from public.jogadores where id = v_p;
end $$;

create or replace function public._novo_nome_ok(p_nome text) returns text language plpgsql set search_path = public as $$
declare v text := btrim(coalesce(p_nome, ''));
begin
  if char_length(v) not between 2 and 12 or v !~ '^[A-Za-zÀ-ÿ0-9 ]+$' then raise exception 'O nome deve ter de 2 a 12 letras, números ou espaços.'; end if;
  if exists (select 1 from public.jogadores where lower(nome) = lower(v)) then raise exception 'Esse nome já está em uso.'; end if;
  return v;
end $$;

-- ponto inicial: dentro do Laboratório do Professor Carvalho
create or replace function public._spawn_inicial(out p_mapa text, out p_x int, out p_y int) language sql stable set search_path = public as $$
  select coalesce(m.id, 'pallet'), coalesce(m.spawn_x, 16), coalesce(m.spawn_y, 21)
    from (select 1) d left join public.mapas m on m.id = 'lab' and m.solido is not null $$;

create or replace function public.criar_personagem(p_nome text, p_aparencia smallint)
returns public.jogadores language plpgsql security definer set search_path = public as $$
declare v_nome text; v_jogador public.jogadores; s record;
begin
  if auth.uid() is null then raise exception 'Faça login primeiro.'; end if;
  if exists (select 1 from public.jogadores where id = auth.uid()) then raise exception 'Você já tem um personagem.'; end if;
  v_nome := public._novo_nome_ok(p_nome);
  if p_aparencia is null or p_aparencia not between 0 and 11 then raise exception 'Aparência inválida.'; end if;
  select * into s from public._spawn_inicial();
  insert into public.jogadores (id, nome, aparencia, mapa_id, x, y, pa)
  values (auth.uid(), v_nome, p_aparencia, s.p_mapa, s.p_x, s.p_y, coalesce((select (valor #>> '{}')::smallint from public.config where chave = 'pa_por_dia'), 30))
  returning * into v_jogador;
  insert into public.auditoria (ator, acao, detalhe) values (auth.uid(), 'criar_personagem', jsonb_build_object('nome', v_nome));
  return v_jogador;
end $$;

-- limpa o progresso de um personagem e o coloca no Laboratório
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
  update public.jogadores
     set mapa_id = s.p_mapa, x = s.p_x, y = s.p_y, direcao = 'baixo', rolagem = null,
         pa = coalesce((select (valor #>> '{}')::smallint from public.config where chave = 'pa_por_dia'), 30),
         dinheiro = 1000, posicao_em = now()
   where id = p_jogador;
  return v_nome;
end $$;

create or replace function public.resetar_jogador(p_jogador uuid)
returns text language plpgsql security definer set search_path = public as $$
declare v_nome text;
begin
  if not public.eh_mestre() then raise exception 'Só o Mestre pode resetar jogadores.'; end if;
  v_nome := public._reiniciar(p_jogador);
  insert into public.auditoria (ator, acao, detalhe) values (auth.uid(), 'resetar_jogador', jsonb_build_object('jogador', p_jogador, 'nome', v_nome));
  return v_nome;
end $$;

create or replace function public.reiniciar_meu_jogo() returns text language plpgsql security definer set search_path = public as $$
declare v_nome text;
begin
  if auth.uid() is null then raise exception 'Faça login primeiro.'; end if;
  if not exists (select 1 from public.jogadores where id = auth.uid()) then raise exception 'Crie seu personagem primeiro.'; end if;
  v_nome := public._reiniciar(auth.uid());
  insert into public.auditoria (ator, acao, detalhe) values (auth.uid(), 'reiniciar_meu_jogo', jsonb_build_object('nome', v_nome));
  return v_nome;
end $$;

create or replace function public.corrigir_posicoes() returns int language plpgsql security definer set search_path = public as $$
declare n int; s record;
begin
  if not public.eh_mestre() then raise exception 'Só o Mestre.'; end if;
  select * into s from public._spawn_inicial();
  update public.jogadores j
     set mapa_id = s.p_mapa, x = s.p_x, y = s.p_y, direcao = 'baixo', posicao_em = now()
   where not exists (select 1 from public.mapas m where m.id = j.mapa_id and m.solido is not null)
      or exists (select 1 from public.mapas m where m.id = j.mapa_id
           and (j.x < 0 or j.y < 0 or j.x >= m.largura or j.y >= m.altura or substr(m.solido, j.y * m.largura + j.x + 1, 1) = '1'));
  get diagnostics n = row_count;
  return n;
end $$;

-- lista os personagens da conta (ativo primeiro)
create or replace function public.meus_personagens() returns jsonb language sql security definer stable set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', j.id, 'nome', j.nome, 'aparencia', j.aparencia, 'ativo', j.id = auth.uid(),
           'dinheiro', j.dinheiro, 'pokemons', (select count(*) from public.pokemons p where p.dono = j.id),
           'pokedex', (select count(*) from public.pokedex d where d.jogador = j.id), 'mapa', j.mapa_id) order by (j.id = auth.uid()) desc, j.nome), '[]'::jsonb)
    from public.jogadores j where j.id = auth.uid() or j.conta = auth.uid() $$;

create or replace function public.criar_novo_personagem(p_nome text, p_aparencia smallint)
returns public.jogadores language plpgsql security definer set search_path = public as $$
declare v_nome text; v_novo uuid := gen_random_uuid(); v_j public.jogadores; s record;
begin
  if auth.uid() is null then raise exception 'Faça login primeiro.'; end if;
  select * into v_j from public.jogadores where id = auth.uid() for update;
  if not found then raise exception 'Crie seu primeiro personagem primeiro.'; end if;
  if exists (select 1 from public.jogadores where conta = auth.uid()) then raise exception 'Você já tem 2 personagens. Exclua o reserva para criar outro.'; end if;
  if exists (select 1 from public.batalhas where jogador = auth.uid() and estado = 'ativa') then raise exception 'Termine a batalha primeiro.'; end if;
  v_nome := public._novo_nome_ok(p_nome);
  if p_aparencia is null or p_aparencia not between 0 and 11 then raise exception 'Aparência inválida.'; end if;
  select * into s from public._spawn_inicial();
  insert into public.jogadores (id, conta, nome, aparencia, mapa_id, x, y, pa)
  values (v_novo, auth.uid(), v_nome, p_aparencia, s.p_mapa, s.p_x, s.p_y, coalesce((select (valor #>> '{}')::smallint from public.config where chave = 'pa_por_dia'), 30));
  perform public._trocar(auth.uid(), v_novo);
  insert into public.auditoria (ator, acao, detalhe) values (auth.uid(), 'criar_novo_personagem', jsonb_build_object('nome', v_nome));
  select * into v_j from public.jogadores where id = auth.uid();
  return v_j;
end $$;

create or replace function public.trocar_personagem(p_id uuid)
returns public.jogadores language plpgsql security definer set search_path = public as $$
declare v_j public.jogadores;
begin
  if auth.uid() is null then raise exception 'Faça login primeiro.'; end if;
  perform 1 from public.jogadores where id = auth.uid() for update;
  if not exists (select 1 from public.jogadores where id = p_id and conta = auth.uid()) then raise exception 'Personagem não encontrado.'; end if;
  if exists (select 1 from public.batalhas where jogador = auth.uid() and estado = 'ativa') then raise exception 'Termine a batalha primeiro.'; end if;
  perform public._trocar(auth.uid(), p_id);
  select * into v_j from public.jogadores where id = auth.uid();
  return v_j;
end $$;

create or replace function public.excluir_personagem_reserva(p_id uuid) returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Faça login primeiro.'; end if;
  delete from public.jogadores where id = p_id and conta = auth.uid();
  if not found then raise exception 'Personagem reserva não encontrado.'; end if;
  insert into public.auditoria (ator, acao, detalhe) values (auth.uid(), 'excluir_personagem_reserva', jsonb_build_object('id', p_id));
end $$;

-- dashboard: números gerais do treinador ativo
create or replace function public.meu_painel() returns jsonb language sql security definer stable set search_path = public as $$
  select jsonb_build_object(
    'pokemons', (select count(*) from public.pokemons where dono = auth.uid()),
    'pokedex', (select count(*) from public.pokedex where jogador = auth.uid()),
    'treinadores', (select count(*) from public.treinadores_vencidos where jogador = auth.uid()),
    'itens', coalesce((select sum(qtd) from public.inventario where jogador = auth.uid()), 0),
    'maior_nivel', coalesce((select max(nivel) from public.pokemons where dono = auth.uid()), 0)) $$;

revoke all on function public._trocar(uuid, uuid), public._filhos_mover(uuid, uuid), public._reiniciar(uuid), public._novo_nome_ok(text), public._spawn_inicial(), public._cols_personagem(text) from public, anon, authenticated;
revoke all on function public.reiniciar_meu_jogo(), public.meus_personagens(), public.criar_novo_personagem(text, smallint), public.trocar_personagem(uuid), public.excluir_personagem_reserva(uuid), public.meu_painel() from public, anon;
grant execute on function public.reiniciar_meu_jogo(), public.meus_personagens(), public.criar_novo_personagem(text, smallint), public.trocar_personagem(uuid),
  public.excluir_personagem_reserva(uuid), public.meu_painel(), public.criar_personagem(text, smallint), public.resetar_jogador(uuid), public.corrigir_posicoes() to authenticated;
