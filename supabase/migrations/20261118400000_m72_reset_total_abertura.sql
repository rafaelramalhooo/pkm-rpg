-- m72: reset TOTAL (nome, visual, classe e tudo), zerar mundo, conquistas novas e balanceamento de abertura

-- 1) reset total de um personagem/conta: apaga a linha (as tabelas filhas caem em cascata) e guarda o papel (Mestre)
create or replace function public._reiniciar(p_jogador uuid) returns text
language plpgsql security definer set search_path = public as $$
declare v_nome text; v_conta uuid; v_papel text;
begin
  select nome, coalesce(conta, id) into v_nome, v_conta from public.jogadores where id = p_jogador;
  if not found then raise exception 'Jogador não encontrado.'; end if;
  select papel into v_papel from public.jogadores where id = v_conta;
  if v_papel is not null and v_papel <> 'jogador' then
    insert into public.papel_guardado (conta, papel) values (v_conta, v_papel) on conflict (conta) do update set papel = excluded.papel;
  end if;
  delete from public.presenca where jogador = v_conta;
  delete from public.jogadores where id = v_conta or conta = v_conta;
  return v_nome;
end $$;
revoke all on function public._reiniciar(uuid) from public, anon, authenticated;

-- 2) estado global do mundo (ranking, rivais, Mundo vivo, desafios da semana, início do check-in)
create or replace function public._zerar_mundo() returns void
language plpgsql security definer set search_path = public as $$
begin
  delete from public.ranking_eventos;
  delete from public.ranking_premios_jogador;
  delete from public.ranking_pontos;
  delete from public.ranking_rivais_pontos;
  delete from public.ranking_periodos;
  delete from public.miniquests_semana;
  delete from public.mv_premios;
  delete from public.mv_quests;
  delete from public.mv_usos;
  delete from public.mv_pokemon_tentativas;
  delete from public.mv_pokemon_dia;
  delete from public.mv_npcs;
  delete from public.mv_geracoes;
  insert into public.config (chave, valor) values ('checkin_inicio', to_jsonb(public._dia_jogo()::text))
  on conflict (chave) do update set valor = excluded.valor;
end $$;
revoke all on function public._zerar_mundo() from public, anon, authenticated;

-- 3) reset geral: todos os jogadores (menos o Mestre) recomeçam do zero e criam o personagem de novo
create or replace function public.mestre_resetar_todos(p_codigo text) returns int
language plpgsql security definer set search_path = public as $$
declare cfg jsonb; r record; n int := 0;
begin
  if not public.eh_mestre() then raise exception 'Só o Mestre.'; end if;
  select valor into cfg from public.config where chave = 'reset_codigo';
  if cfg is null or (cfg->>'por')::uuid is distinct from auth.uid() or (cfg->>'ate')::timestamptz < now() or upper(btrim(coalesce(p_codigo, ''))) <> cfg->>'codigo' then
    raise exception 'Código incorreto ou expirado. Peça um novo código.';
  end if;
  delete from public.config where chave = 'reset_codigo';
  insert into public.config (chave, valor) values ('manutencao', jsonb_build_object('ativo', true, 'mensagem', 'O mundo de Rafar foi reiniciado. Voltamos já!'))
  on conflict (chave) do update set valor = excluded.valor;
  insert into public.config (chave, valor) values ('derrubar_em', to_jsonb(now())) on conflict (chave) do update set valor = excluded.valor;
  for r in select j.id from public.jogadores j where j.conta is null and j.papel <> 'mestre' loop
    perform public._reiniciar(r.id);
    n := n + 1;
  end loop;
  -- personagens reserva órfãos (conta sem personagem ativo), exceto os do Mestre
  delete from public.jogadores x where x.conta is not null and not exists (select 1 from public.jogadores m where m.id = x.conta and m.papel = 'mestre');
  perform public._zerar_mundo();
  insert into public.auditoria (ator, acao, detalhe) values (auth.uid(), 'resetar_todos', jsonb_build_object('jogadores', n));
  return n;
end $$;
revoke all on function public.mestre_resetar_todos(text) from public, anon;
grant execute on function public.mestre_resetar_todos(text) to authenticated;

-- 4) novas métricas de conquistas (calculadas ao vivo)
create or replace function public._progresso(p_j uuid, c public.conquistas_catalogo) returns integer
language plpgsql stable security definer set search_path = public as $$
declare d date := public._dia_jogo(); s date := public._semana_inicio(public._dia_jogo()); v bigint;
begin
  if c.metrica = 'time_dia' then return (select count(*) from public.participacao_dia where jogador = p_j and dia_jogo = d); end if;
  if c.metrica = 'duelo_oponentes' then return (select count(distinct ref) from public.atividades where jogador = p_j and tipo = 'duelo' and dia_jogo between s and s + 6 and ref is not null); end if;
  if c.metrica = 'dex' then return (select count(*) from public.pokedex where jogador = p_j and capturado); end if;
  if c.metrica = 'shiny' then return (select count(*) from public.pokemons where dono = p_j and brilhante); end if;
  if c.metrica = 'reserva' then return (select count(*) from public.reserva_visitas where jogador = p_j); end if;
  if c.metrica = 'mundo_vivo' then return coalesce((select sum(n) from public.mv_usos where jogador = p_j), 0)::int; end if;
  if c.metrica = 'ranking' then return (select count(*) from public.ranking_premios_jogador where jogador = p_j); end if;
  if c.metrica = 'ranking_podio' then return (select count(*) from public.ranking_premios_jogador where jogador = p_j and posicao is not null); end if;
  if c.metrica = 'nivel' then return coalesce((select max(nivel) from public.pokemons where dono = p_j), 0)::int; end if;
  select valor into v from public.contadores where jogador = p_j and chave = c.metrica and periodo = case c.periodo when 'total' then 'total' when 'dia' then 'd:' || d else 'w:' || s end;
  return least(coalesce(v, 0), 2000000000)::int;
end $$;

insert into public.conquistas_catalogo (id, categoria, nome, descricao, metrica, meta, periodo, recompensa, ordem, grupo, ativa) values
 ('dex_25',   'Pokédex',   'Pesquisador de campo', 'Capture 25 espécies diferentes.',  'dex', 25,  'total', '{"itens":[{"qtd":5,"item":"great-ball"}]}', 110, 'dex', true),
 ('dex_50',   'Pokédex',   'Naturalista',          'Capture 50 espécies diferentes.',  'dex', 50,  'total', '{"itens":[{"qtd":5,"item":"ultra-ball"}],"dinheiro":1000}', 111, 'dex', true),
 ('dex_100',  'Pokédex',   'Quase lá',             'Capture 100 espécies diferentes.', 'dex', 100, 'total', '{"itens":[{"qtd":2,"item":"rare-candy"}],"xp_treinador":200}', 112, 'dex', true),
 ('dex_151',  'Pokédex',   'Pokédex completa',     'Capture as 151 espécies.',         'dex', 151, 'total', '{"itens":[{"qtd":3,"item":"rare-candy"}],"dinheiro":5000,"xp_treinador":500}', 113, 'dex', true),
 ('shiny_1',  'Pokédex',   'Brilho raro',          'Tenha um Pokémon brilhante.',      'shiny', 1, 'total', '{"itens":[{"qtd":1,"item":"rare-candy"}],"dinheiro":2000}', 114, 'shiny', true),
 ('shiny_3',  'Pokédex',   'Olho de águia',        'Tenha 3 Pokémon brilhantes.',      'shiny', 3, 'total', '{"itens":[{"qtd":2,"item":"rare-candy"}],"xp_treinador":200}', 115, 'shiny', true),
 ('safari_1', 'Exploração','Primeiro safári',      'Visite a Reserva Dourada.',        'reserva', 1, 'total', '{"itens":[{"qtd":3,"item":"great-ball"}]}', 120, 'reserva', true),
 ('safari_7', 'Exploração','Guarda da Reserva',    'Visite a Reserva Dourada 7 vezes.','reserva', 7, 'total', '{"itens":[{"qtd":5,"item":"ultra-ball"}],"dinheiro":1000}', 121, 'reserva', true),
 ('mv_10',    'Exploração','Conversa fiada',       'Interaja 10 vezes com viajantes.', 'mundo_vivo', 10, 'total', '{"dinheiro":500}', 122, 'mundo_vivo', true),
 ('mv_50',    'Exploração','Amigo de Rafar',       'Interaja 50 vezes com viajantes.', 'mundo_vivo', 50, 'total', '{"itens":[{"qtd":1,"item":"rare-candy"}]}', 123, 'mundo_vivo', true),
 ('rank_1',   'Ranking',   'Na disputa',           'Receba um prêmio de temporada.',   'ranking', 1, 'total', '{"xp_treinador":100}', 130, 'ranking', true),
 ('rank_podio','Ranking',  'No pódio',             'Termine uma temporada no pódio.',  'ranking_podio', 1, 'total', '{"itens":[{"qtd":1,"item":"rare-candy"}],"xp_treinador":100}', 131, 'ranking', true),
 ('nivel_30', 'Treino',    'Pokémon forte',        'Tenha um Pokémon no nível 30.',    'nivel', 30, 'total', '{"dinheiro":1000}', 140, 'nivel', true),
 ('nivel_50', 'Treino',    'Pokémon veterano',     'Tenha um Pokémon no nível 50.',    'nivel', 50, 'total', '{"itens":[{"qtd":1,"item":"rare-candy"}],"xp_treinador":200}', 141, 'nivel', true)
on conflict (id) do nothing;

-- 5) balanceamento de abertura
-- desafios da semana: recompensa pela progressão do mapa (5 níveis)
update public.miniquests_catalogo c set recompensa = t.r::jsonb
from (values
 ('pallet','1'),('rota1','1'),('porto','1'),('rota2','1'),('caminho_va','1'),
 ('rota3','2'),('rota4','2'),('rota5','2'),('argila','2'),('verdelume','2'),('azurana','2'),
 ('rota6','3'),('rota7a','3'),('rota8','3'),('quartzo','3'),('ambar','3'),('costa1','3'),('costa2','3'),
 ('carmesim','4'),('ametista','4'),('rota9','4'),('rota10','4'),('vale','4'),('reserva','4'),('gruta','4'),
 ('obsidiana','5'),('cromatica','5'),('plato','5')
) as m(mapa, n)
join (values
 ('1','{"itens":[{"qtd":2,"item":"great-ball"}],"dinheiro":400,"xp_treinador":40}'),
 ('2','{"itens":[{"qtd":2,"item":"super-potion"}],"dinheiro":500,"xp_treinador":50}'),
 ('3','{"itens":[{"qtd":1,"item":"ultra-ball"}],"dinheiro":600,"xp_treinador":60}'),
 ('4','{"itens":[{"qtd":2,"item":"hyper-potion"}],"dinheiro":700,"xp_treinador":70}'),
 ('5','{"itens":[{"qtd":1,"item":"revive"}],"dinheiro":800,"xp_treinador":80}')
) as t(n, r) on t.n = m.n
where c.mapa_id = m.mapa;

-- Criador de Ovos: tira os Pokémon que a Reserva Dourada já oferece
update public.mv_arquetipos set cfg = jsonb_set(cfg, '{especies}', coalesce((select jsonb_agg(e) from jsonb_array_elements(cfg -> 'especies') e where (e #>> '{}')::int not in (102, 111, 113, 123, 127, 128)), '[]'::jsonb))
where id = 'ovos';

-- rivais do topo: ritmo máximo 50 pontos por dia
update public.ranking_rivais set ritmo = 50 where ritmo > 55;
