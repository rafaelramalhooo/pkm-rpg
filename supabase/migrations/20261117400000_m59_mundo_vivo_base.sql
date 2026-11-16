-- m59: Mundo vivo — Lote 1 (base).
-- Turnos do dia (6h/12h/18h/0h), NPCs especiais por turno (sem repetição simultânea), desafiantes das rotas (por dia),
-- Pokémon do dia (4 aparições, uma tentativa por jogador), Fofoqueiro e Mural (pistas), painel do Mestre.
-- Aditiva e idempotente: só cria tabelas/funções novas e substitui 3 funções (desafiar_treinador, _equipe_escalada, _tg_batalha_ranking).
-- Interruptor: config.modulos_ativos.mundo_vivo (true/false) — desligado, nada novo aparece nem é gerado.

-- ---------- configuração ----------
insert into public.config (chave, valor) values ('mundo_vivo', '{
  "esp_cidade": [1, 2],
  "esp_outro": [1, 3],
  "desafiantes": [3, 6],
  "raro_chance": 0.15,
  "semanal_chance": 0.35,
  "desafiante_pa": 2,
  "pokemon_dia_aparicoes": 4,
  "brilhante_mult": 3,
  "recompensa_desafiante": [60, 180],
  "chance_item_desafiante": 0.2,
  "itens_desafiante": [{"item": "poke-ball", "qtd": 3}, {"item": "potion", "qtd": 2}, {"item": "great-ball", "qtd": 1}, {"item": "antidote", "qtd": 2}],
  "quest_max": 3,
  "quest_pa": 1
}'::jsonb) on conflict (chave) do nothing;
update public.config set valor = valor || '{"mundo_vivo": true}'::jsonb where chave = 'modulos_ativos' and not (valor ? 'mundo_vivo');

-- ---------- tabelas ----------
create table if not exists public.mv_pontos (
  mapa_id text not null references public.mapas (id) on delete cascade,
  x int not null, y int not null,
  direcao text not null default 'baixo' check (direcao in ('cima','baixo','esquerda','direita')),
  tipo_mapa text not null check (tipo_mapa in ('cidade','rota','local')),
  primary key (mapa_id, x, y)
);
create table if not exists public.mv_fixos (
  id text primary key,
  mapa_id text not null references public.mapas (id) on delete cascade,
  x int not null, y int not null,
  tipo text not null check (tipo in ('fofoqueiro','mural')),
  direcao text not null default 'baixo',
  nome text not null, aparencia smallint not null default 0
);
create table if not exists public.mv_arquetipos (
  id text primary key,
  nome text not null,
  classe text not null,
  categoria text not null default 'servico' check (categoria in ('servico','quest','troca','batalha')),
  raridade text not null default 'comum' check (raridade in ('comum','incomum','raro')),
  peso int not null default 10 check (peso >= 0),
  max_simultaneo int not null default 2 check (max_simultaneo >= 0),
  semanal boolean not null default false,
  custo_pa int not null default 0 check (custo_pa >= 0),
  lote smallint not null default 1,
  ativo boolean not null default true,
  falas jsonb not null default '{}'::jsonb,
  cfg jsonb not null default '{}'::jsonb
);
create table if not exists public.mv_nomes (nome text primary key);
create table if not exists public.mv_geracoes (dia date not null, turno smallint not null, criado_em timestamptz not null default now(), primary key (dia, turno));
create table if not exists public.mv_npcs (
  id text primary key,
  dia date not null, turno smallint not null,
  mapa_id text not null references public.mapas (id) on delete cascade,
  x int not null, y int not null,
  direcao text not null default 'baixo',
  arquetipo text not null references public.mv_arquetipos (id) on delete cascade,
  nome text not null, classe text not null, aparencia smallint not null default 12,
  dados jsonb not null default '{}'::jsonb,
  treinador text,                      -- NPCs de batalha: id da linha em public.treinadores (desenhada como treinador)
  criado_em timestamptz not null default now()
);
create index if not exists mv_npcs_turno on public.mv_npcs (dia, turno);
create table if not exists public.mv_pokemon_dia (
  dia date not null, turno smallint not null,
  especie_id int not null references public.especies (id),
  mapa_id text not null references public.mapas (id) on delete cascade,
  x int not null, y int not null, direcao text not null default 'baixo',
  primary key (dia, turno)
);
create table if not exists public.mv_pokemon_tentativas (
  jogador uuid not null references public.jogadores (id) on delete cascade,
  dia date not null, turno smallint not null,
  em timestamptz not null default now(),
  primary key (jogador, dia, turno)
);
create table if not exists public.mv_usos (
  jogador uuid not null references public.jogadores (id) on delete cascade,
  chave text not null, dia date not null,
  n int not null default 1,
  primary key (jogador, chave, dia)
);
create table if not exists public.mv_premios (
  id bigint generated always as identity primary key,
  jogador uuid not null references public.jogadores (id) on delete cascade,
  titulo text not null, payload jsonb not null default '{}'::jsonb,
  visto boolean not null default false, criado_em timestamptz not null default now()
);
create index if not exists mv_premios_jogador on public.mv_premios (jogador, visto);
-- tudo isto só é lido/escrito por funções do servidor (sem política = sem acesso direto do navegador)
alter table public.mv_pontos enable row level security;
alter table public.mv_fixos enable row level security;
alter table public.mv_arquetipos enable row level security;
alter table public.mv_nomes enable row level security;
alter table public.mv_geracoes enable row level security;
alter table public.mv_npcs enable row level security;
alter table public.mv_pokemon_dia enable row level security;
alter table public.mv_pokemon_tentativas enable row level security;
alter table public.mv_usos enable row level security;
alter table public.mv_premios enable row level security;

-- ---------- arquétipos (os 3 lotes; só aparecem os que já têm função de interação ou são de batalha) ----------
insert into public.mv_arquetipos (id, nome, classe, categoria, raridade, peso, max_simultaneo, semanal, custo_pa, lote, falas, cfg) values
 ('mercador', 'Mercador ambulante', 'Mercador', 'servico', 'comum', 14, 2, false, 0, 2,
   '{"abertura": "Tenho umas raridades que a loja da cidade não vende. Dê uma olhada!"}',
   '{"limite_por_item": 3, "catalogo": [{"item":"max-potion","preco":1500},{"item":"full-restore","preco":2500},{"item":"max-revive","preco":3000},{"item":"full-heal","preco":450},{"item":"ultra-ball","preco":1000},{"item":"super-repel","preco":350},{"item":"max-repel","preco":500},{"item":"escape-rope","preco":300},{"item":"hyper-potion","preco":650}]}'),
 ('enfermeira', 'Enfermeira de campo', 'Enfermeira', 'servico', 'comum', 12, 2, false, 1, 2,
   '{"abertura": "Seus Pokémon parecem cansados. Posso cuidar deles aqui mesmo, rapidinho."}', '{}'),
 ('vidente', 'Vidente', 'Vidente', 'servico', 'comum', 8, 1, false, 1, 2,
   '{"abertura": "Feche os olhos... eu vejo o que este turno reserva para você."}',
   '{"premios": [{"dinheiro": 120}, {"dinheiro": 200}, {"itens": [{"item": "great-ball", "qtd": 2}]}, {"itens": [{"item": "super-potion", "qtd": 2}]}, {"xp_treinador": 40}, {"itens": [{"item": "revive", "qtd": 1}]}]}'),
 ('contador', 'Contador de histórias', 'Contador', 'servico', 'comum', 10, 2, false, 0, 2,
   '{"abertura": "Sente-se um pouco e ouça. Rafar guarda muitas histórias."}',
   '{"historias": ["Dizem que as vilas de Rafar nasceram quando o primeiro treinador atravessou a trilha com um único Pokémon e uma Poké Bola.", "Os pescadores do cais juram que, nas noites de névoa, o mar devolve o canto de um Pokémon que ninguém nunca viu.", "As insígnias de Rafar têm cores de pedras preciosas porque os primeiros líderes eram, antes de tudo, garimpeiros.", "Quem passa a noite na Gruta Prisma conta que as paredes mudam de cor quando alguém ri dentro dela.", "Há um Pokémon que só aparece para quem já perdeu e levantou três vezes seguidas. Pelo menos é o que dizem em Obsidiana.", "O antigo campeão treinou, durante um ano, apenas caminhando. O segredo dele? Ouvir os Pokémon respirando.", "Na Reserva Dourada, a grama é tão alta que um Pokémon pequeno pode viver anos sem ver o céu."]}'),
 ('pesquisador', 'Pesquisador', 'Pesquisador', 'quest', 'comum', 12, 2, false, 1, 2,
   '{"abertura": "Preciso de dados novos para a minha pesquisa. Pode me ajudar hoje?"}', '{}'),
 ('naturalista', 'Naturalista', 'Naturalista', 'quest', 'comum', 10, 2, false, 1, 2,
   '{"abertura": "Estou catalogando as espécies da região. Quer fazer parte do estudo?"}', '{}'),
 ('entregador', 'Entregador', 'Entregador', 'quest', 'comum', 10, 2, false, 1, 2,
   '{"abertura": "Tenho uma encomenda urgente, mas não posso largar meu posto. Você leva?"}', '{}'),
 ('colecionador', 'Colecionador', 'Colecionador', 'troca', 'incomum', 7, 1, false, 1, 2,
   '{"abertura": "Procuro uns itens para a minha coleção. Em troca, tenho algo bom."}',
   '{"trocas": [{"pede": {"item": "potion", "qtd": 3}, "da": {"item": "great-ball", "qtd": 2}}, {"pede": {"item": "antidote", "qtd": 3}, "da": {"item": "super-potion", "qtd": 1}}, {"pede": {"item": "super-potion", "qtd": 2}, "da": {"item": "ultra-ball", "qtd": 1}}, {"pede": {"item": "great-ball", "qtd": 3}, "da": {"item": "revive", "qtd": 1}}, {"pede": {"item": "awakening", "qtd": 2}, "da": {"item": "hyper-potion", "qtd": 1}}, {"pede": {"item": "poke-ball", "qtd": 6}, "da": {"item": "great-ball", "qtd": 3}}]}'),
 ('troca', 'Treinador de trocas', 'Trocador', 'troca', 'incomum', 6, 1, false, 1, 3,
   '{"abertura": "Procuro um Pokémon específico. Troco por outro, no mesmo nível!"}',
   '{"da": [37, 58, 63, 66, 83, 95, 108, 122, 123, 127, 128, 131], "nivel_min": 5}'),
 ('ovos', 'Criador de ovos', 'Criador', 'servico', 'incomum', 5, 1, false, 1, 3,
   '{"abertura": "Este ovo foi chocado com carinho. Posso deixar com você, por um preço justo."}',
   '{"preco": 1500, "especies": [37, 58, 63, 66, 74, 79, 96, 102, 104, 108, 109, 111, 113, 123, 127, 128]}'),
 ('arqueologo', 'Arqueólogo', 'Arqueólogo', 'servico', 'incomum', 6, 1, false, 1, 3,
   '{"abertura": "Há algo enterrado por aqui. Quer ajudar a cavar? Quem sabe o que sai."}',
   '{"premios": [{"dinheiro": 80}, {"dinheiro": 250}, {"itens": [{"item": "super-repel", "qtd": 2}]}, {"itens": [{"item": "hyper-potion", "qtd": 1}]}, {"itens": [{"item": "revive", "qtd": 1}]}, {"itens": [{"item": "ultra-ball", "qtd": 2}]}, {"xp_treinador": 50}, {"itens": [{"item": "moon-stone", "qtd": 1}]}], "pesos": [30, 20, 14, 12, 10, 8, 4, 2]}'),
 ('cozinheiro', 'Cozinheiro de viagem', 'Cozinheiro', 'servico', 'incomum', 6, 1, false, 1, 3,
   '{"abertura": "Nada como uma refeição quente para quem vive na estrada. Seus Pokémon vão adorar."}',
   '{"preco": 150, "amizade": 5}'),
 ('veterano', 'Veterano de ginásio', 'Veterano', 'batalha', 'raro', 3, 1, false, 2, 3,
   '{"antes": "Já enfrentei campeões. Mostre o que você aprendeu!", "derrota": "Hmpf... Você tem estofo. Leve isto como lembrança."}',
   '{"prefixo": "dv", "time": 4, "recompensa": [400, 700], "premio": "mt"}'),
 ('rival', 'Rival errante', 'Rival', 'batalha', 'raro', 3, 1, false, 2, 3,
   '{"antes": "Ei! Fico encontrando você pelo caminho. Hoje a gente resolve isso!", "derrota": "Da próxima vez eu venço. Anote isso."}',
   '{"prefixo": "dr", "time": 4, "recompensa": [300, 600], "premio": {"xp_treinador": 60}}'),
 ('encapuzada', 'Figura encapuzada', 'Encapuzada', 'batalha', 'raro', 2, 1, true, 2, 3,
   '{"antes": "Poucos me encontram. Menos ainda me derrotam. Prove seu valor.", "derrota": "...Faz tempo que ninguém me surpreendia. Leve isto."}',
   '{"prefixo": "de", "time": 5, "recompensa": [700, 1200], "premio": "mt_forte"}')
on conflict (id) do nothing;

insert into public.mv_nomes (nome) values
 ('Tião'),('Dona Cida'),('Zé Roberto'),('Marlene'),('Nilton'),('Rosa'),('Edu'),('Vânia'),('Otto'),('Lia Mara'),('Bruno'),('Telma'),('Caetano'),('Dani'),('Gui'),
 ('Sônia'),('Rui'),('Cléo'),('Pedrinho'),('Alzira'),('Felipe'),('Nair'),('Ivo'),('Bete'),('Heitor'),('Yara'),('Lauro'),('Marta Lú'),('Valdo'),('Pietra'),
 ('Tomás'),('Eunice'),('Duda'),('Mauro'),('Glória'),('Jonas'),('Celina'),('Dirceu'),('Aurora'),('Renan'),('Isadora'),('Wagner'),('Cássia'),('Osvaldo'),('Lívia'),
 ('Murilo'),('Neuza'),('Ícaro'),('Zuleica'),('Abel'),('Carol'),('Ademir'),('Nina Flor'),('Silvio'),('Tereza'),('Matias'),('Elisa'),('Jorge Luís'),('Bárbara'),('Cláudio Reis')
on conflict do nothing;

-- ---------- utilitários ----------
create or replace function public._mv_v(p_chave text) returns jsonb language sql stable security definer set search_path = public as $$
  select (select valor from public.config where chave = 'mundo_vivo') -> p_chave $$;
create or replace function public._mv_n(p_chave text, p_padrao numeric) returns numeric language sql stable security definer set search_path = public as $$
  select coalesce(((select valor from public.config where chave = 'mundo_vivo') ->> p_chave)::numeric, p_padrao) $$;
create or replace function public._mv_faixa(p_chave text, p_min int, p_max int) returns int language plpgsql stable security definer set search_path = public as $$
declare v jsonb := public._mv_v(p_chave); a int; b int;
begin
  a := coalesce((v ->> 0)::int, p_min); b := coalesce((v ->> 1)::int, p_max);
  if b < a then b := a; end if;
  return a + floor(random() * (b - a + 1))::int;
end $$;
-- turno do dia: 0 = 6h–12h, 1 = 12h–18h, 2 = 18h–24h, 3 = 0h–6h (horário de São Paulo)
create or replace function public._mv_turno() returns smallint language sql stable security definer set search_path = public as $$
  select ((((extract(hour from (now() at time zone coalesce((select valor #>> '{}' from public.config where chave = 'fuso'), 'America/Sao_Paulo')))::int
            - public._cfg_int('hora_virada', 6) + 24) % 24) / 6))::smallint $$;
create or replace function public._mv_periodo(p_t int) returns text language sql immutable as $$
  select (array['manhã', 'tarde', 'noite', 'madrugada'])[p_t + 1] $$;
create or replace function public._mv_codigo(p_d date, p_t int) returns text language sql immutable as $$
  select to_char(p_d, 'YYMMDD') || p_t::text $$;

-- há alguém (treinador, NPC fixo, NPC do turno, Pokémon do dia) a menos de 2 tiles?
create or replace function public._mv_ocupado(p_mapa text, p_x int, p_y int, p_d date, p_t int) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.treinadores o where o.mapa_id = p_mapa and greatest(abs(o.x - p_x), abs(o.y - p_y)) <= 1)
      or exists (select 1 from public.npcs_missao o where o.mapa_id = p_mapa and greatest(abs(o.x - p_x), abs(o.y - p_y)) <= 1)
      or exists (select 1 from public.pedra_etapas o where o.mapa_id = p_mapa and greatest(abs(o.x - p_x), abs(o.y - p_y)) <= 1)
      or exists (select 1 from public.mv_fixos o where o.mapa_id = p_mapa and greatest(abs(o.x - p_x), abs(o.y - p_y)) <= 1)
      or exists (select 1 from public.mv_npcs o where o.dia = p_d and o.turno = p_t and o.mapa_id = p_mapa and greatest(abs(o.x - p_x), abs(o.y - p_y)) <= 1)
      or exists (select 1 from public.mv_pokemon_dia o where o.dia = p_d and o.turno = p_t and o.mapa_id = p_mapa and greatest(abs(o.x - p_x), abs(o.y - p_y)) <= 1) $$;

-- equipe-base de um mapa: as espécies de lá (com a evolução por nível, se houver)
create or replace function public._mv_pool_mapa(p_mapa text) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare r record; ev record; res jsonb := '[]'::jsonb;
begin
  for r in select distinct especie_id from public.encontros where mapa_id = p_mapa loop
    select * into ev from public.evolucoes where de = r.especie_id and nivel is not null order by nivel limit 1;
    if found then
      res := res || jsonb_build_array(jsonb_build_object('e', r.especie_id, 'de', 1, 'ate', greatest(ev.nivel - 1, 1), 'linha', r.especie_id),
                                      jsonb_build_object('e', ev.para, 'de', ev.nivel, 'ate', 100, 'linha', r.especie_id));
    else
      res := res || jsonb_build_array(jsonb_build_object('e', r.especie_id, 'de', 1, 'ate', 100, 'linha', r.especie_id));
    end if;
  end loop;
  if jsonb_array_length(res) = 0 then
    for r in select distinct especie_id from public.encontros where especie_id <= 143 order by especie_id limit 8 loop
      res := res || jsonb_build_array(jsonb_build_object('e', r.especie_id, 'de', 1, 'ate', 100, 'linha', r.especie_id));
    end loop;
  end if;
  return res;
end $$;

-- cria um treinador dinâmico (desafiante, veterano, rival...) que usa todo o motor de batalha dos treinadores
create or replace function public._mv_criar_treinador(p_id text, p_mapa text, p_x int, p_y int, p_dir text, p_nome text, p_classe text, p_ap int,
                                                      p_rec int, p_falas jsonb, p_time int) returns void
language plpgsql security definer set search_path = public as $$
begin
  insert into public.treinadores (id, mapa_id, x, y, direcao, visao, nome, classe, aparencia, recompensa, falas, equipe, escala, arco)
  values (p_id, p_mapa, p_x, p_y, p_dir, 1, p_nome, p_classe, p_ap, greatest(p_rec, 0), p_falas, '[]'::jsonb,
          jsonb_build_object('time', greatest(least(p_time, 6), 1), 'bonus', 0, 'pool', public._mv_pool_mapa(p_mapa)), 1)
  on conflict (id) do nothing;
end $$;

-- dados próprios de cada NPC, sorteados na criação (valem durante o turno)
create or replace function public._mv_dados(p_arq text, p_mapa text) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare cfg jsonb; meta int; alvo record; par jsonb; esp int; quer int; r record;
begin
  select a.cfg into cfg from public.mv_arquetipos a where a.id = p_arq;
  cfg := coalesce(cfg, '{}'::jsonb);
  if p_arq = 'mercador' then
    return jsonb_build_object('estoque', coalesce((select jsonb_agg(e) from (select e from jsonb_array_elements(cfg -> 'catalogo') e order by random() limit 4) s), '[]'::jsonb));
  elsif p_arq = 'pesquisador' then
    meta := 2 + floor(random() * 3)::int;
    return jsonb_build_object('tipo', 'captura', 'meta', meta, 'texto', format('Capture %s Pokémon', meta),
      'premio', jsonb_build_object('dinheiro', 150 * meta, 'xp_treinador', 20 * meta, 'itens', jsonb_build_array(jsonb_build_object('item', 'great-ball', 'qtd', 1))));
  elsif p_arq = 'naturalista' then
    meta := 3 + floor(random() * 3)::int;
    return jsonb_build_object('tipo', 'dex_visto', 'meta', meta, 'texto', format('Veja %s espécies novas na Pokédex', meta),
      'premio', jsonb_build_object('dinheiro', 100 * meta, 'xp_treinador', 15 * meta, 'itens', jsonb_build_array(jsonb_build_object('item', 'potion', 'qtd', 2))));
  elsif p_arq = 'entregador' then
    select m.mapa_id, mp.nome into alvo from (select distinct mapa_id from public.mv_pontos where tipo_mapa = 'cidade' and mapa_id <> p_mapa order by random() limit 1) m join public.mapas mp on mp.id = m.mapa_id;
    return jsonb_build_object('tipo', 'chegar', 'meta', 1, 'alvo', alvo.mapa_id, 'alvo_nome', alvo.nome, 'texto', format('Leve a encomenda até %s', alvo.nome),
      'premio', jsonb_build_object('dinheiro', 300, 'xp_treinador', 30, 'itens', jsonb_build_array(jsonb_build_object('item', 'super-potion', 'qtd', 2))));
  elsif p_arq = 'colecionador' then
    select e into par from jsonb_array_elements(cfg -> 'trocas') e order by random() limit 1;
    return jsonb_build_object('troca', par);
  elsif p_arq = 'troca' then
    select (e #>> '{}')::int into esp from jsonb_array_elements(cfg -> 'da') e order by random() limit 1;
    select especie_id into quer from public.encontros where especie_id <= 143 and especie_id <> coalesce(esp, 0) group by especie_id order by random() limit 1;
    return jsonb_build_object('quer', quer, 'da', esp, 'nivel_min', coalesce((cfg ->> 'nivel_min')::int, 5));
  elsif p_arq = 'ovos' then
    select (e #>> '{}')::int into esp from jsonb_array_elements(cfg -> 'especies') e order by random() limit 1;
    return jsonb_build_object('especie', esp, 'preco', coalesce((cfg ->> 'preco')::int, 1500), 'passos', 1500 + floor(random() * 2000)::int);
  elsif p_arq = 'contador' then
    return jsonb_build_object('indice', floor(random() * greatest(jsonb_array_length(cfg -> 'historias'), 1))::int);
  end if;
  return '{}'::jsonb;
end $$;

-- ---------- geração ----------
create or replace function public._mv_aparencia() returns int language sql volatile as $$
  select case when x = 13 then 14 else x end from (select 12 + floor(random() * 37)::int as x) s $$;

create or replace function public._mv_nome_livre(p_d date, p_t int) returns text language sql volatile security definer set search_path = public as $$
  select coalesce((select n.nome from public.mv_nomes n
                    where not exists (select 1 from public.mv_npcs o where o.dia = p_d and o.turno = p_t and o.nome = n.nome)
                    order by random() limit 1), 'Viajante') $$;

-- desafiantes das rotas: 3 a 6 por rota, por dia; ao lado da trilha (pontos pré-validados), parados
create or replace function public._mv_gerar_desafiantes(p_d date) returns void language plpgsql security definer set search_path = public as $$
declare
  m record; p record; n int; i int; v_code text := to_char(p_d, 'YYMMDD'); v_nome text;
  v_cls text[] := array['Andarilho', 'Mochileiro', 'Campista', 'Jovem treinador', 'Aventureiro', 'Explorador'];
  v_antes text[] := array['Opa! Faz tempo que ninguém passa por aqui. Vamos lutar?', 'Minha equipe está afiada hoje. Topa um duelo?', 'Você parece forte. Quero ver na prática!', 'Estava treinando sozinho... aceita uma batalha?'];
  v_der text[] := array['Perdi hoje, mas amanhã eu volto!', 'Boa batalha! Você tem talento.', 'Hmm, preciso treinar mais.'];
  v_rec int; lo int := coalesce((public._mv_v('recompensa_desafiante') ->> 0)::int, 60); hi int := coalesce((public._mv_v('recompensa_desafiante') ->> 1)::int, 180);
begin
  delete from public.treinadores where id ~ '^dc_' and id not like 'dc\_' || v_code || '\_%';
  if exists (select 1 from public.treinadores where id like 'dc\_' || v_code || '\_%') then return; end if;
  for m in select distinct mapa_id from public.mv_pontos where tipo_mapa = 'rota' loop
    n := public._mv_faixa('desafiantes', 3, 6); i := 0;
    for p in select * from public.mv_pontos where mapa_id = m.mapa_id and tipo_mapa = 'rota' order by random() loop
      exit when i >= n;
      if public._mv_ocupado(p.mapa_id, p.x, p.y, p_d, -1) then continue; end if;
      i := i + 1;
      select nome into v_nome from public.mv_nomes order by random() limit 1;
      v_rec := lo + floor(random() * (greatest(hi, lo) - lo + 1))::int;
      perform public._mv_criar_treinador('dc_' || v_code || '_' || m.mapa_id || '_' || i, p.mapa_id, p.x, p.y, p.direcao, coalesce(v_nome, 'Viajante'),
        v_cls[1 + floor(random() * array_length(v_cls, 1))::int], public._mv_aparencia(), v_rec,
        jsonb_build_object('antes', v_antes[1 + floor(random() * array_length(v_antes, 1))::int], 'derrota', v_der[1 + floor(random() * array_length(v_der, 1))::int]), 3);
    end loop;
  end loop;
end $$;

-- NPCs especiais do turno: 1–2 por cidade, 1–3 nos demais mapas; nunca o mesmo arquétipo duas vezes no mesmo mapa
create or replace function public._mv_gerar_especiais(p_d date, p_t int) returns void language plpgsql security definer set search_path = public as $$
declare
  m record; a public.mv_arquetipos; p record; n int; k int; seq int := 0; v_nome text; v_ap int; v_id text; v_tid text;
  v_code text := public._mv_codigo(p_d, p_t); v_raro numeric := public._mv_n('raro_chance', 0.15); v_sem numeric := public._mv_n('semanal_chance', 0.35);
  v_rec int; lo int; hi int;
begin
  delete from public.treinadores where id ~ '^d[ver]_';
  for m in select x.mapa_id, x.tipo_mapa from (select distinct on (mapa_id) mapa_id, tipo_mapa from public.mv_pontos order by mapa_id) x order by random() loop
    n := case when m.tipo_mapa = 'cidade' then public._mv_faixa('esp_cidade', 1, 2) else public._mv_faixa('esp_outro', 1, 3) end;
    for k in 1 .. n loop
      a := null;
      select r.* into a from public.mv_arquetipos r
       where r.ativo and r.peso > 0
         and (r.categoria = 'batalha' or to_regprocedure('public._mv_h_' || r.id || '(uuid,public.mv_npcs,text,jsonb)') is not null)
         and (r.categoria <> 'batalha' or m.tipo_mapa <> 'cidade')
         and (r.raridade <> 'raro' or random() < v_raro)
         and (not r.semanal or (extract(isodow from p_d) = 7 and random() < v_sem))
         and (select count(*) from public.mv_npcs o where o.dia = p_d and o.turno = p_t and o.arquetipo = r.id) < r.max_simultaneo
         and not exists (select 1 from public.mv_npcs o where o.dia = p_d and o.turno = p_t and o.mapa_id = m.mapa_id and o.arquetipo = r.id)
       order by power(random(), 1.0 / greatest(r.peso, 1)) desc limit 1;
      if a.id is null then continue; end if;
      select * into p from public.mv_pontos q where q.mapa_id = m.mapa_id and not public._mv_ocupado(q.mapa_id, q.x, q.y, p_d, p_t) order by random() limit 1;
      if not found then continue; end if;
      seq := seq + 1;
      v_nome := public._mv_nome_livre(p_d, p_t); v_ap := public._mv_aparencia(); v_id := 'mv_' || v_code || '_' || seq;
      insert into public.mv_npcs (id, dia, turno, mapa_id, x, y, direcao, arquetipo, nome, classe, aparencia, dados)
      values (v_id, p_d, p_t, m.mapa_id, p.x, p.y, p.direcao, a.id, v_nome, a.classe, v_ap, public._mv_dados(a.id, m.mapa_id));
      if a.categoria = 'batalha' then
        v_tid := coalesce(a.cfg ->> 'prefixo', 'dv') || '_' || v_code || '_' || seq;
        lo := coalesce((a.cfg -> 'recompensa' ->> 0)::int, 300); hi := coalesce((a.cfg -> 'recompensa' ->> 1)::int, 600);
        v_rec := lo + floor(random() * (greatest(hi, lo) - lo + 1))::int;
        perform public._mv_criar_treinador(v_tid, m.mapa_id, p.x, p.y, p.direcao, v_nome, a.classe, v_ap, v_rec, a.falas, coalesce((a.cfg ->> 'time')::int, 4));
        update public.mv_npcs set treinador = v_tid where id = v_id;
      end if;
    end loop;
  end loop;
end $$;

-- Pokémon do dia: 1 espécie por dia (tendendo às mais raras), uma aparição por turno em rotas diferentes
create or replace function public._mv_gerar_pokemon(p_d date, p_t int) returns void language plpgsql security definer set search_path = public as $$
declare v_esp int; v_mapa text; p record;
begin
  if p_t >= public._mv_n('pokemon_dia_aparicoes', 4) then return; end if;
  select especie_id into v_esp from public.mv_pokemon_dia where dia = p_d limit 1;
  if v_esp is null then
    select e.especie_id into v_esp from public.encontros e
      join (select distinct mapa_id from public.mv_pontos where tipo_mapa = 'rota') r on r.mapa_id = e.mapa_id
     where e.especie_id <= 143
       and e.especie_id not in (select especie_id from public.mv_pokemon_dia where dia >= p_d - 1)
     group by e.especie_id order by power(random(), greatest(avg(e.peso), 1)) desc limit 1;
  end if;
  if v_esp is null then return; end if;
  select q.* into p from public.mv_pontos q
   where q.tipo_mapa = 'rota' and q.mapa_id not in (select mapa_id from public.mv_pokemon_dia where dia = p_d and turno <> p_t)
     and not public._mv_ocupado(q.mapa_id, q.x, q.y, p_d, p_t)
   order by random() limit 1;
  if not found then return; end if;
  insert into public.mv_pokemon_dia (dia, turno, especie_id, mapa_id, x, y, direcao) values (p_d, p_t, v_esp, p.mapa_id, p.x, p.y, p.direcao)
  on conflict (dia, turno) do update set especie_id = excluded.especie_id, mapa_id = excluded.mapa_id, x = excluded.x, y = excluded.y, direcao = excluded.direcao;
end $$;

create or replace function public._mv_gerar(p_forcar boolean default false) returns void language plpgsql security definer set search_path = public as $$
declare d date := public._dia_jogo(); t int := public._mv_turno();
begin
  if not public._modulo('mundo_vivo') then return; end if;
  perform pg_advisory_xact_lock(7710);
  if not p_forcar and exists (select 1 from public.mv_geracoes where dia = d and turno = t) then return; end if;
  delete from public.mv_npcs where p_forcar or dia <> d or turno <> t;
  delete from public.mv_pokemon_dia where dia < d - 1 or (p_forcar and dia = d and turno = t);
  delete from public.mv_pokemon_tentativas where dia < d - 1;
  delete from public.mv_usos where dia < d - 7;
  delete from public.mv_premios where visto and criado_em < now() - interval '14 days';
  perform public._mv_gerar_desafiantes(d);
  perform public._mv_gerar_especiais(d, t);
  perform public._mv_gerar_pokemon(d, t);
  insert into public.mv_geracoes (dia, turno) values (d, t) on conflict do nothing;
  delete from public.mv_geracoes where dia < d - 2;
end $$;
revoke all on function public._mv_gerar(boolean) from public, anon, authenticated;

do $$ begin
  begin perform cron.unschedule('mv_turno'); exception when others then null; end;
  perform cron.schedule('mv_turno', '0 3,9,15,21 * * *', 'select public._mv_gerar(false)');
exception when others then raise notice 'pg_cron indisponível para mv_turno: %', sqlerrm;
end $$;

-- ---------- RPCs do jogador ----------
create or replace function public.mv_garantir() returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then return '{}'::jsonb; end if;
  perform public._mv_gerar(false);
  return jsonb_build_object('ativo', public._modulo('mundo_vivo'), 'turno', public._mv_turno());
end $$;

create or replace function public.mv_mapa(p_mapa text) returns jsonb language plpgsql security definer set search_path = public as $$
declare d date; t int;
begin
  if auth.uid() is null then return '{"ativo": false}'::jsonb; end if;
  if not public._modulo('mundo_vivo') then return '{"ativo": false}'::jsonb; end if;
  perform public._mv_gerar(false);
  d := public._dia_jogo(); t := public._mv_turno();
  return jsonb_build_object('ativo', true, 'turno', t, 'periodo', public._mv_periodo(t), 'desafiante_pa', public._mv_n('desafiante_pa', 2),
    'npcs', coalesce((select jsonb_agg(jsonb_build_object('id', n.id, 'x', n.x, 'y', n.y, 'direcao', n.direcao, 'nome', n.nome, 'classe', n.classe, 'aparencia', n.aparencia, 'arquetipo', n.arquetipo))
                        from public.mv_npcs n where n.dia = d and n.turno = t and n.mapa_id = p_mapa and n.treinador is null), '[]'::jsonb),
    'fixos', coalesce((select jsonb_agg(jsonb_build_object('id', f.id, 'x', f.x, 'y', f.y, 'direcao', f.direcao, 'nome', f.nome, 'aparencia', f.aparencia, 'tipo', f.tipo))
                        from public.mv_fixos f where f.mapa_id = p_mapa), '[]'::jsonb),
    'pokemon', coalesce((select jsonb_agg(jsonb_build_object('especie_id', pd.especie_id, 'x', pd.x, 'y', pd.y, 'direcao', pd.direcao,
                          'tentou', exists (select 1 from public.mv_pokemon_tentativas tt where tt.jogador = auth.uid() and tt.dia = d and tt.turno = t)))
                          from public.mv_pokemon_dia pd where pd.dia = d and pd.turno = t and pd.mapa_id = p_mapa), '[]'::jsonb));
end $$;

-- rumores automáticos: Fofoqueiro (NPCs vistos) e Mural (Pokémon raro + desafiantes que restam)
create or replace function public.mv_pistas() returns jsonb language plpgsql security definer set search_path = public as $$
declare d date := public._dia_jogo(); t int := public._mv_turno(); v_f jsonb := '[]'::jsonb; v_m jsonb := '[]'::jsonb; r record; v_code text := to_char(public._dia_jogo(), 'YYMMDD'); v_tot int; v_rest int; v_pk record;
begin
  if auth.uid() is null or not public._modulo('mundo_vivo') then return '{"fofoca": [], "mural": []}'::jsonb; end if;
  perform public._mv_gerar(false);
  for r in select n.nome, n.classe, mp.nome as mapa from public.mv_npcs n join public.mapas mp on mp.id = n.mapa_id
            where n.dia = d and n.turno = t order by random() limit 6 loop
    v_f := v_f || to_jsonb(format('Dizem que %s (%s) está em %s agora de %s.', r.nome, lower(r.classe), r.mapa, public._mv_periodo(t)));
  end loop;
  if jsonb_array_length(v_f) = 0 then v_f := to_jsonb(array['Por aqui está tudo calmo hoje... por enquanto.']); end if;
  select pd.especie_id, mp.nome as mapa into v_pk from public.mv_pokemon_dia pd join public.mapas mp on mp.id = pd.mapa_id where pd.dia = d and pd.turno = t;
  if v_pk.mapa is not null then
    v_m := v_m || to_jsonb(format('Avistamento raro: um Pokémon incomum foi visto em %s nesta %s.', v_pk.mapa, public._mv_periodo(t)));
  end if;
  select count(*), count(*) filter (where not exists (select 1 from public.treinadores_vencidos tv where tv.jogador = auth.uid() and tv.treinador = tr.id))
    into v_tot, v_rest from public.treinadores tr where tr.id like 'dc\_' || v_code || '\_%';
  v_m := v_m || to_jsonb(format('Desafiantes nas rotas hoje: restam %s de %s para você.', coalesce(v_rest, 0), coalesce(v_tot, 0)));
  for r in select mp.nome, count(*) as n from public.treinadores tr join public.mapas mp on mp.id = tr.mapa_id
            where tr.id like 'dc\_' || v_code || '\_%' and not exists (select 1 from public.treinadores_vencidos tv where tv.jogador = auth.uid() and tv.treinador = tr.id)
            group by mp.nome order by count(*) desc, random() limit 3 loop
    v_m := v_m || to_jsonb(format('%s: %s desafiante(s) esperando.', r.nome, r.n));
  end loop;
  return jsonb_build_object('fofoca', v_f, 'mural', v_m, 'turno', t);
end $$;

-- tentar capturar o Pokémon do dia (1 tentativa por jogador em cada aparição; 1 PA)
create or replace function public.mv_pokemon_buscar() returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_j public.jogadores; v_b public.batalhas; v_ativo uuid; v_sel jsonb; v_pd public.mv_pokemon_dia; d date := public._dia_jogo(); t int := public._mv_turno(); v_nv int; v_chance numeric;
begin
  if auth.uid() is null then raise exception 'Faça login primeiro.'; end if;
  if not public._modulo('mundo_vivo') then raise exception 'Este recurso está desligado.'; end if;
  select * into v_j from public.jogadores where id = auth.uid() for update;
  if not found then raise exception 'Crie seu personagem primeiro.'; end if;
  select * into v_b from public.batalhas where jogador = v_j.id and estado = 'ativa';
  if found then return public._resultado(v_b.id, jsonb_build_array(jsonb_build_object('t', 'retomada'))); end if;
  select * into v_pd from public.mv_pokemon_dia where dia = d and turno = t and mapa_id = v_j.mapa_id;
  if not found then raise exception 'Não há nada de raro por aqui agora.'; end if;
  if abs(v_pd.x - v_j.x) + abs(v_pd.y - v_j.y) <> 1 then raise exception 'Chegue bem pertinho para observar.'; end if;
  if exists (select 1 from public.mv_pokemon_tentativas where jogador = v_j.id and dia = d and turno = t) then raise exception 'Você já tentou esta aparição. Ela some na virada do turno.'; end if;
  select id into v_ativo from public.pokemons where dono = v_j.id and posicao is not null and hp_atual > 0 order by posicao limit 1;
  if v_ativo is null then raise exception 'Você precisa de um Pokémon de pé para encarar isso. Cure-os no Centro Pokémon ou em casa.'; end if;
  perform public._gastar_pa(v_j.id);
  insert into public.mv_pokemon_tentativas (jogador, dia, turno) values (v_j.id, d, t);
  v_nv := greatest(1, public._nivel_ref(v_j.id) + 2 + floor(random() * 4)::int + public._dificuldade());
  v_sel := public._selvagem(v_pd.especie_id, v_nv);
  v_chance := least(1, (coalesce((select (valor #>> '{}')::numeric from public.config where chave = 'chance_brilhante'), 0.004) + public._bonus(v_j.id, 'olho_brilhante') / 100.0)
                      * public._ev('brilhante', 1) * public._mv_n('brilhante_mult', 3));
  v_sel := v_sel || jsonb_build_object('brilhante', random() < v_chance);
  insert into public.batalhas (jogador, selvagem, ativo) values (v_j.id, v_sel, v_ativo) returning * into v_b;
  insert into public.pokedex (jogador, especie_id) values (v_j.id, v_pd.especie_id) on conflict do nothing;
  return public._resultado(v_b.id, jsonb_build_array(jsonb_build_object('t', 'apareceu', 'nome', v_sel->>'nome', 'nivel', v_nv)));
end $$;

create or replace function public.mv_premios_novos() returns jsonb language plpgsql security definer set search_path = public as $$
declare r jsonb;
begin
  if auth.uid() is null then return '[]'::jsonb; end if;
  with u as (update public.mv_premios set visto = true where jogador = auth.uid() and not visto returning titulo, payload, criado_em)
  select coalesce(jsonb_agg(jsonb_build_object('titulo', titulo, 'payload', payload) order by criado_em), '[]'::jsonb) into r from u;
  return r;
end $$;

-- ---------- recompensas dos desafiantes/NPCs de batalha (o dinheiro já vem do treinador.recompensa) ----------
create or replace function public._tg_mv_batalha() returns trigger language plpgsql security definer set search_path = public as $$
declare v_pre text; v_pay jsonb := '{}'::jsonb; v_it jsonb; v_num int; v_txt text := ''; v_cfg jsonb; v_mt boolean;
begin
  if old.estado = 'ativa' and new.estado = 'vitoria' and new.tipo = 'treinador' and new.treinador ~ '^d[cver]_' then
    begin
      v_pre := substr(new.treinador, 1, 2);
      if v_pre = 'dc' then
        if random() < public._mv_n('chance_item_desafiante', 0.2) then
          select e into v_it from jsonb_array_elements(coalesce(public._mv_v('itens_desafiante'), '[]'::jsonb)) e order by random() limit 1;
          if v_it is not null then v_pay := jsonb_build_object('itens', jsonb_build_array(v_it)); end if;
        end if;
      elsif v_pre in ('dv', 'de') then
        select m.num into v_num from public.mt_catalogo m
         where m.ativa and m.arco <= public._cfg_int('arco_atual', 1)
           and not exists (select 1 from public.mt_jogador j where j.jogador = new.jogador and j.num = m.num)
         order by (case when v_pre = 'de' then m.preco else -m.preco end) desc, random() limit 1;
        if v_num is not null then
          v_mt := public._dar_mt(new.jogador, v_num);
          v_txt := format('MT%s', lpad(v_num::text, 2, '0'));
        end if;
        if v_pre = 'de' then v_pay := jsonb_build_object('xp_treinador', 80, 'itens', jsonb_build_array(jsonb_build_object('item', 'max-revive', 'qtd', 1))); end if;
      elsif v_pre = 'dr' then
        v_pay := jsonb_build_object('xp_treinador', 60);
      end if;
      if v_pay <> '{}'::jsonb then perform public._conceder(new.jogador, v_pay); end if;
      if v_pay <> '{}'::jsonb or v_txt <> '' then
        insert into public.mv_premios (jogador, titulo, payload) values (new.jogador, case v_pre when 'dc' then 'Presente de um desafiante' when 'dv' then 'Prêmio do Veterano' when 'de' then 'Prêmio da Figura encapuzada' else 'Prêmio do Rival' end,
                                          v_pay || case when v_txt <> '' then jsonb_build_object('mt', v_txt) else '{}'::jsonb end);
      end if;
    exception when others then
      raise warning 'tg_mv_batalha falhou: %', sqlerrm;
    end;
  end if;
  return new;
end $$;
drop trigger if exists tg_mv_batalha on public.batalhas;
create trigger tg_mv_batalha after update of estado on public.batalhas for each row execute function public._tg_mv_batalha();

-- ---------- funções existentes reescritas (cópias fiéis + ajustes mínimos) ----------
create or replace function public.desafiar_treinador(p_treinador text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_j public.jogadores; v_t public.treinadores; v_b public.batalhas; v_ativo uuid; v_falta int; v_rev boolean := false; v_custo int; v_i int;
  begin
  if auth.uid() is null then raise exception 'Faça login primeiro.'; end if;
  select * into v_j from public.jogadores where id = auth.uid() for update;
  if not found then raise exception 'Crie seu personagem primeiro.'; end if;
  select * into v_b from public.batalhas where jogador = v_j.id and estado = 'ativa';
  if found then return jsonb_build_object('batalha', to_jsonb(v_b) - 'sim' - 'meta'); end if;
  select * into v_t from public.treinadores where id = p_treinador and mapa_id = v_j.mapa_id;
  if not found then raise exception 'Não há esse treinador por aqui.'; end if;
  if v_t.id like 'mq\_%' then
    if not public._modulo('miniquests') or not public._miniquest_disponivel(v_j.id, v_t.id) then
      raise exception '% não está desafiando ninguém agora.', v_t.nome;
    end if;
  elsif v_t.id ~ '^d[cver]_' then
    if exists (select 1 from public.treinadores_vencidos where jogador = v_j.id and treinador = v_t.id) then
      raise exception 'Você já derrotou % hoje.', v_t.nome;
    end if;
  elsif exists (select 1 from public.treinadores_vencidos where jogador = v_j.id and treinador = v_t.id) then
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
  if v_t.id ~ '^d[cver]_' then
    v_custo := public._mv_n('desafiante_pa', 2)::int;
    for v_i in 1 .. v_custo loop perform public._gastar_pa(v_j.id); end loop;
  end if;
  insert into public.batalhas (jogador, selvagem, ativo, tipo, treinador, adversarios, revanche)
  values (v_j.id, '{}'::jsonb, v_ativo, 'treinador', v_t.id, case when v_t.escala is not null then public._equipe_escalada(v_t, public._nivel_ref(v_j.id)) else public._equipe_treinador(v_t.equipe) end, v_rev) returning * into v_b;
  if v_rev then
    insert into public.treinadores_revanche (jogador, treinador, dia_jogo) values (v_j.id, v_t.id, public._dia_jogo())
    on conflict (jogador, treinador) do update set dia_jogo = excluded.dia_jogo;
  end if;
  return jsonb_build_object('batalha', to_jsonb(v_b) - 'sim' - 'meta', 'treinador', jsonb_build_object('nome', v_t.nome, 'classe', v_t.classe));
end $$;
create or replace function public._equipe_escalada(t public.treinadores, p_ref int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  esc jsonb := t.escala; n int := coalesce((esc->>'time')::int, 3); bonus int := coalesce((esc->>'bonus')::int, 0);
  piso int := coalesce((esc->>'piso')::int, 1); dif int := public._dificuldade();
  lo int := case when t.id like 'liga\_%' then 4 when t.lider then 2 when t.id like 'mq\_%' then 0 when t.id like 'dc\_%' then -1 when t.id like 'dv\_%' then 2 when t.id like 'dr\_%' then 1 when t.id like 'de\_%' then 3 else -2 end;
  hi int := case when t.id like 'liga\_%' then 6 when t.lider then 4 when t.id like 'mq\_%' then 2 when t.id like 'dc\_%' then 2 when t.id like 'dv\_%' then 4 when t.id like 'dr\_%' then 3 when t.id like 'de\_%' then 5 else 1 end;
  ace jsonb := esc->'ace'; pool jsonb := esc->'pool'; k int; total int; lvl int; ent jsonb; usadas int[] := '{}'; res jsonb := '[]'::jsonb;
  menos int := 0; off int;
begin
  total := n - case when ace is not null then 1 else 0 end;
  for k in 1 .. total loop
    off := lo + floor(random() * (hi - lo + 1))::int;
    lvl := least(1000, greatest(1, p_ref + dif + off));
    ent := null;
    select e into ent from jsonb_array_elements(pool) e
     where (e->>'de')::int <= lvl and (e->>'ate')::int >= lvl and not ((e->>'linha')::int = any(usadas)) order by random() limit 1;
    if ent is null then
      select e into ent from jsonb_array_elements(pool) e where (e->>'de')::int <= lvl and (e->>'ate')::int >= lvl order by random() limit 1;
    end if;
    if ent is null then
      select e into ent from jsonb_array_elements(pool) e order by (e->>'de')::int, random() limit 1;
    end if;
    usadas := usadas || (ent->>'linha')::int;
    res := res || public._equipe_treinador(jsonb_build_array(jsonb_build_object('especie', (ent->>'e')::int, 'nivel', lvl)));
  end loop;
  if ace is not null then
    lvl := least(1000, greatest(1, p_ref + hi + dif));
    res := res || public._equipe_treinador(jsonb_build_array(jsonb_build_object('especie', (ace->>'e')::int, 'nivel', lvl)));
  end if;
  return res;
end $$;
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
                  case when lid then coalesce((cfg ->> 'lider')::numeric, 15) when new.treinador like 'dc\_%' then coalesce((cfg ->> 'desafiante')::numeric, 3) else coalesce((cfg ->> 'treinador')::numeric, 5) end);
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

-- ---------- painel do Mestre ----------
create or replace function public.mestre_mundo_obter() returns jsonb language plpgsql stable security definer set search_path = public as $$
declare d date := public._dia_jogo(); t int := public._mv_turno();
begin
  if not public.eh_mestre() then raise exception 'Só o Mestre.'; end if;
  return jsonb_build_object(
    'ativo', public._modulo('mundo_vivo'), 'turno', t, 'periodo', public._mv_periodo(t),
    'cfg', coalesce((select valor from public.config where chave = 'mundo_vivo'), '{}'::jsonb),
    'arquetipos', coalesce((select jsonb_agg(to_jsonb(a) - 'cfg' order by a.lote, a.nome) from public.mv_arquetipos a), '[]'::jsonb),
    'nomes', coalesce((select jsonb_agg(nome order by nome) from public.mv_nomes), '[]'::jsonb),
    'agora', coalesce((select jsonb_agg(jsonb_build_object('nome', n.nome, 'arquetipo', n.arquetipo, 'mapa', n.mapa_id) order by n.mapa_id) from public.mv_npcs n where n.dia = d and n.turno = t), '[]'::jsonb),
    'pokemon', coalesce((select jsonb_agg(jsonb_build_object('turno', p.turno, 'especie_id', p.especie_id, 'mapa', p.mapa_id) order by p.turno) from public.mv_pokemon_dia p where p.dia = d), '[]'::jsonb),
    'desafiantes', (select count(*) from public.treinadores where id like 'dc\_' || to_char(d, 'YYMMDD') || '\_%'));
end $$;

create or replace function public.mestre_mundo_salvar(p jsonb) returns void language plpgsql security definer set search_path = public as $$
declare k text; v jsonb; a jsonb; n text; atual jsonb;
begin
  if not public.eh_mestre() then raise exception 'Só o Mestre.'; end if;
  if p ? 'cfg' then
    atual := coalesce((select valor from public.config where chave = 'mundo_vivo'), '{}'::jsonb);
    for k, v in select * from jsonb_each(p -> 'cfg') loop
      if k not in ('esp_cidade', 'esp_outro', 'desafiantes', 'raro_chance', 'semanal_chance', 'desafiante_pa', 'pokemon_dia_aparicoes', 'brilhante_mult', 'recompensa_desafiante', 'chance_item_desafiante', 'quest_max', 'quest_pa') then continue; end if;
      if k in ('esp_cidade', 'esp_outro', 'desafiantes', 'recompensa_desafiante') then
        if jsonb_typeof(v) <> 'array' or jsonb_array_length(v) <> 2 or (v ->> 0)::numeric < 0 or (v ->> 1)::numeric < (v ->> 0)::numeric or (v ->> 1)::numeric > 5000 then raise exception 'Faixa inválida em %.', k; end if;
      elsif jsonb_typeof(v) <> 'number' or (v #>> '{}')::numeric < 0 or (v #>> '{}')::numeric > 1000 then raise exception 'Valor inválido em %.', k;
      end if;
      if k in ('raro_chance', 'semanal_chance', 'chance_item_desafiante') and (v #>> '{}')::numeric > 1 then raise exception '% deve ficar entre 0 e 1.', k; end if;
      atual := atual || jsonb_build_object(k, v);
    end loop;
    update public.config set valor = atual where chave = 'mundo_vivo';
  end if;
  if p ? 'arquetipos' then
    for a in select * from jsonb_array_elements(p -> 'arquetipos') loop
      update public.mv_arquetipos set
        peso = coalesce(least(greatest((a ->> 'peso')::int, 0), 1000), peso),
        max_simultaneo = coalesce(least(greatest((a ->> 'max_simultaneo')::int, 0), 50), max_simultaneo),
        ativo = coalesce((a ->> 'ativo')::boolean, ativo),
        raridade = coalesce(case when a ->> 'raridade' in ('comum', 'incomum', 'raro') then a ->> 'raridade' end, raridade),
        custo_pa = coalesce(least(greatest((a ->> 'custo_pa')::int, 0), 20), custo_pa)
       where id = a ->> 'id';
    end loop;
  end if;
  if p ? 'nomes' then
    delete from public.mv_nomes where nome <> all (select jsonb_array_elements_text(p -> 'nomes'));
    for n in select jsonb_array_elements_text(p -> 'nomes') loop
      if length(trim(n)) between 2 and 30 then insert into public.mv_nomes (nome) values (trim(n)) on conflict do nothing; end if;
    end loop;
  end if;
  if p ? 'ativo' then
    update public.config set valor = valor || jsonb_build_object('mundo_vivo', (p ->> 'ativo')::boolean) where chave = 'modulos_ativos';
  end if;
  if coalesce((p ->> 'regerar')::boolean, false) then perform public._mv_gerar(true); end if;
end $$;

do $$ declare f text; begin
  foreach f in array array['mv_garantir()', 'mv_mapa(text)', 'mv_pistas()', 'mv_pokemon_buscar()', 'mv_premios_novos()', 'mestre_mundo_obter()', 'mestre_mundo_salvar(jsonb)'] loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;
