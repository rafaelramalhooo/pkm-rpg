-- m66 (Lote D): 6 classes x 15 habilidades, arvore em tiers, classe secundaria, pontos mais dificeis.
-- Acesso: classe principal libera as 15; secundaria (nivel de treinador 5) libera so os Tiers I e II;
-- Mestria (Tier IV) exige 1 habilidade de outra classe no rank 2. Custo do proximo rank = (tier-1) + rank.
alter table public.jogadores drop constraint if exists jogadores_classe_rpg_check;
alter table public.jogadores add constraint jogadores_classe_rpg_check check (classe_rpg in ('Treinador','Criador','Pesquisador','Comerciante','Ranger','Estrategista'));
alter table public.jogadores add column if not exists classe_sec text;
alter table public.jogadores drop constraint if exists jogadores_classe_sec_check;
alter table public.jogadores add constraint jogadores_classe_sec_check check (classe_sec is null or classe_sec in ('Treinador','Criador','Pesquisador','Comerciante','Ranger','Estrategista'));
alter table public.habilidades_catalogo add column if not exists tier smallint not null default 1;

update public.habilidades_catalogo set classe = 'Treinador', ordem = 1, req = '[]'::jsonb, tier = 1 where id = 'instinto';
update public.habilidades_catalogo set classe = 'Treinador', ordem = 2, req = '[]'::jsonb, tier = 1 where id = 'resistencia';
update public.habilidades_catalogo set classe = 'Treinador', ordem = 3, req = '[]'::jsonb, tier = 1 where id = 'foco';
update public.habilidades_catalogo set classe = 'Treinador', ordem = 4, req = '[]'::jsonb, tier = 1 where id = 'recompensa';
update public.habilidades_catalogo set classe = 'Treinador', ordem = 5, req = '[]'::jsonb, tier = 1 where id = 'mestre_treino';
update public.habilidades_catalogo set classe = 'Treinador', ordem = 6, req = '[{"id": "resistencia", "rank": 2}]'::jsonb, tier = 2 where id = 'cura_rapida';
update public.habilidades_catalogo set classe = 'Treinador', ordem = 7, req = '[{"id": "recompensa", "rank": 2}]'::jsonb, tier = 2 where id = 'lideranca';
update public.habilidades_catalogo set classe = 'Treinador', ordem = 8, req = '[{"id": "instinto", "rank": 2}]'::jsonb, tier = 2 where id = 'provocacao';
update public.habilidades_catalogo set classe = 'Treinador', ordem = 9, req = '[{"id": "mestre_treino", "rank": 2}]'::jsonb, tier = 2 where id = 'veterano';
insert into public.habilidades_catalogo (id, classe, ordem, nome, descricao, bonus, req, ativo, tier) values ('golpe_certeiro','Treinador',10,'Golpe Certeiro','+1% de chance de acerto crítico por rank (em breve).',1,'[{"id": "foco", "rank": 2}]'::jsonb,true,2) on conflict (id) do update set classe = excluded.classe, ordem = excluded.ordem, req = excluded.req, tier = excluded.tier;
insert into public.habilidades_catalogo (id, classe, ordem, nome, descricao, bonus, req, ativo, tier) values ('vigor','Treinador',11,'Vigor','+2% de HP máximo dos seus Pokémon por rank (em breve).',2,'[{"id": "cura_rapida", "rank": 2}, {"id": "provocacao", "rank": 2}]'::jsonb,true,3) on conflict (id) do update set classe = excluded.classe, ordem = excluded.ordem, req = excluded.req, tier = excluded.tier;
insert into public.habilidades_catalogo (id, classe, ordem, nome, descricao, bonus, req, ativo, tier) values ('duelista','Treinador',12,'Duelista','+5% de experiência e dinheiro em duelos contra treinadores por rank (em breve).',5,'[{"id": "lideranca", "rank": 2}, {"id": "veterano", "rank": 2}]'::jsonb,true,3) on conflict (id) do update set classe = excluded.classe, ordem = excluded.ordem, req = excluded.req, tier = excluded.tier;
insert into public.habilidades_catalogo (id, classe, ordem, nome, descricao, bonus, req, ativo, tier) values ('contra_ataque','Treinador',13,'Contra-ataque','+2% de chance de revidar com um golpe extra por rank (em breve).',2,'[{"id": "provocacao", "rank": 2}, {"id": "golpe_certeiro", "rank": 2}]'::jsonb,true,3) on conflict (id) do update set classe = excluded.classe, ordem = excluded.ordem, req = excluded.req, tier = excluded.tier;
insert into public.habilidades_catalogo (id, classe, ordem, nome, descricao, bonus, req, ativo, tier) values ('pressao','Treinador',14,'Pressão','O adversário gasta +1 PP a mais por golpe, a cada rank (em breve).',1,'[{"id": "veterano", "rank": 2}, {"id": "golpe_certeiro", "rank": 2}]'::jsonb,true,3) on conflict (id) do update set classe = excluded.classe, ordem = excluded.ordem, req = excluded.req, tier = excluded.tier;
update public.habilidades_catalogo set classe = 'Treinador', ordem = 15, req = '[{"id": "vigor", "rank": 2}, {"id": "duelista", "rank": 2}]'::jsonb, tier = 4 where id = 'campeao';
update public.habilidades_catalogo set classe = 'Criador', ordem = 1, req = '[]'::jsonb, tier = 1 where id = 'afeto';
update public.habilidades_catalogo set classe = 'Criador', ordem = 2, req = '[]'::jsonb, tier = 1 where id = 'alimentador';
update public.habilidades_catalogo set classe = 'Criador', ordem = 3, req = '[]'::jsonb, tier = 1 where id = 'espaco';
update public.habilidades_catalogo set classe = 'Criador', ordem = 4, req = '[]'::jsonb, tier = 1 where id = 'banco_dados';
update public.habilidades_catalogo set classe = 'Criador', ordem = 5, req = '[]'::jsonb, tier = 1 where id = 'mao_amiga';
update public.habilidades_catalogo set classe = 'Criador', ordem = 6, req = '[{"id": "afeto", "rank": 2}]'::jsonb, tier = 2 where id = 'laco';
update public.habilidades_catalogo set classe = 'Criador', ordem = 7, req = '[{"id": "alimentador", "rank": 2}]'::jsonb, tier = 2 where id = 'treino_intenso';
update public.habilidades_catalogo set classe = 'Criador', ordem = 8, req = '[{"id": "espaco", "rank": 2}]'::jsonb, tier = 2 where id = 'ovos';
update public.habilidades_catalogo set classe = 'Criador', ordem = 9, req = '[{"id": "banco_dados", "rank": 2}]'::jsonb, tier = 2 where id = 'olho_brilhante';
insert into public.habilidades_catalogo (id, classe, ordem, nome, descricao, bonus, req, ativo, tier) values ('veterinario','Criador',10,'Veterinário','Cuidar também cura condições de status; cada rank aumenta a chance em 20% (em breve).',20,'[{"id": "mao_amiga", "rank": 2}]'::jsonb,true,2) on conflict (id) do update set classe = excluded.classe, ordem = excluded.ordem, req = excluded.req, tier = excluded.tier;
insert into public.habilidades_catalogo (id, classe, ordem, nome, descricao, bonus, req, ativo, tier) values ('chocadeira','Criador',11,'Chocadeira','Ovos chocam 10% mais rápido por rank (em breve).',10,'[{"id": "ovos", "rank": 2}, {"id": "laco", "rank": 2}]'::jsonb,true,3) on conflict (id) do update set classe = excluded.classe, ordem = excluded.ordem, req = excluded.req, tier = excluded.tier;
insert into public.habilidades_catalogo (id, classe, ordem, nome, descricao, bonus, req, ativo, tier) values ('bercario','Criador',12,'Berçário','+1 espaço de ovo por rank (em breve).',1,'[{"id": "ovos", "rank": 2}, {"id": "veterinario", "rank": 2}]'::jsonb,true,3) on conflict (id) do update set classe = excluded.classe, ordem = excluded.ordem, req = excluded.req, tier = excluded.tier;
insert into public.habilidades_catalogo (id, classe, ordem, nome, descricao, bonus, req, ativo, tier) values ('linhagem','Criador',13,'Linhagem','Filhotes herdam +1 IV dos pais por rank (em breve).',1,'[{"id": "olho_brilhante", "rank": 2}, {"id": "ovos", "rank": 2}]'::jsonb,true,3) on conflict (id) do update set classe = excluded.classe, ordem = excluded.ordem, req = excluded.req, tier = excluded.tier;
insert into public.habilidades_catalogo (id, classe, ordem, nome, descricao, bonus, req, ativo, tier) values ('seguidor_forte','Criador',14,'Seguidor Forte','Seu Pokémon seguidor ganha +5% de experiência por rank (em breve).',5,'[{"id": "laco", "rank": 2}, {"id": "treino_intenso", "rank": 2}]'::jsonb,true,3) on conflict (id) do update set classe = excluded.classe, ordem = excluded.ordem, req = excluded.req, tier = excluded.tier;
update public.habilidades_catalogo set classe = 'Criador', ordem = 15, req = '[{"id": "chocadeira", "rank": 2}, {"id": "linhagem", "rank": 2}]'::jsonb, tier = 4 where id = 'criador_mestre';
update public.habilidades_catalogo set classe = 'Pesquisador', ordem = 1, req = '[]'::jsonb, tier = 1 where id = 'olhar_atento';
update public.habilidades_catalogo set classe = 'Pesquisador', ordem = 2, req = '[]'::jsonb, tier = 1 where id = 'exploracao';
update public.habilidades_catalogo set classe = 'Pesquisador', ordem = 3, req = '[]'::jsonb, tier = 1 where id = 'mochila';
update public.habilidades_catalogo set classe = 'Pesquisador', ordem = 4, req = '[]'::jsonb, tier = 1 where id = 'mapa_mental';
update public.habilidades_catalogo set classe = 'Pesquisador', ordem = 5, req = '[]'::jsonb, tier = 1 where id = 'captura';
update public.habilidades_catalogo set classe = 'Pesquisador', ordem = 6, req = '[{"id": "exploracao", "rank": 2}]'::jsonb, tier = 2 where id = 'rede_pesca';
update public.habilidades_catalogo set classe = 'Pesquisador', ordem = 7, req = '[{"id": "olhar_atento", "rank": 2}]'::jsonb, tier = 2 where id = 'pokedex_viva';
update public.habilidades_catalogo set classe = 'Pesquisador', ordem = 8, req = '[{"id": "captura", "rank": 2}]'::jsonb, tier = 2 where id = 'intuicao';
insert into public.habilidades_catalogo (id, classe, ordem, nome, descricao, bonus, req, ativo, tier) values ('naturalista','Pesquisador',9,'Naturalista','+10 XP de treinador ao registrar uma espécie nova por rank (em breve).',10,'[{"id": "olhar_atento", "rank": 2}]'::jsonb,true,2) on conflict (id) do update set classe = excluded.classe, ordem = excluded.ordem, req = excluded.req, tier = excluded.tier;
insert into public.habilidades_catalogo (id, classe, ordem, nome, descricao, bonus, req, ativo, tier) values ('cartografo','Pesquisador',10,'Cartógrafo','Revela mais detalhes dos mapas visitados (em breve).',1,'[{"id": "mapa_mental", "rank": 2}]'::jsonb,true,2) on conflict (id) do update set classe = excluded.classe, ordem = excluded.ordem, req = excluded.req, tier = excluded.tier;
insert into public.habilidades_catalogo (id, classe, ordem, nome, descricao, bonus, req, ativo, tier) values ('farejador','Pesquisador',11,'Farejador','+2% de chance de encontrar Pokémon raro por rank (em breve).',2,'[{"id": "intuicao", "rank": 2}, {"id": "naturalista", "rank": 2}]'::jsonb,true,3) on conflict (id) do update set classe = excluded.classe, ordem = excluded.ordem, req = excluded.req, tier = excluded.tier;
insert into public.habilidades_catalogo (id, classe, ordem, nome, descricao, bonus, req, ativo, tier) values ('binoculos','Pesquisador',12,'Binóculos','+3% de chance de encontro em qualquer piso por rank (em breve).',3,'[{"id": "cartografo", "rank": 2}, {"id": "rede_pesca", "rank": 2}]'::jsonb,true,3) on conflict (id) do update set classe = excluded.classe, ordem = excluded.ordem, req = excluded.req, tier = excluded.tier;
insert into public.habilidades_catalogo (id, classe, ordem, nome, descricao, bonus, req, ativo, tier) values ('isca_especial','Pesquisador',13,'Isca Especial','+5% de chance de fisgar Pokémon ao pescar por rank (em breve).',5,'[{"id": "rede_pesca", "rank": 2}, {"id": "pokedex_viva", "rank": 2}]'::jsonb,true,3) on conflict (id) do update set classe = excluded.classe, ordem = excluded.ordem, req = excluded.req, tier = excluded.tier;
insert into public.habilidades_catalogo (id, classe, ordem, nome, descricao, bonus, req, ativo, tier) values ('enciclopedia','Pesquisador',14,'Enciclopédia','Pesquisar uma espécie rende +₽50 por rank (em breve).',50,'[{"id": "pokedex_viva", "rank": 2}, {"id": "naturalista", "rank": 2}]'::jsonb,true,3) on conflict (id) do update set classe = excluded.classe, ordem = excluded.ordem, req = excluded.req, tier = excluded.tier;
update public.habilidades_catalogo set classe = 'Pesquisador', ordem = 15, req = '[{"id": "farejador", "rank": 2}, {"id": "enciclopedia", "rank": 2}]'::jsonb, tier = 4 where id = 'cientista';
update public.habilidades_catalogo set classe = 'Comerciante', ordem = 1, req = '[]'::jsonb, tier = 1 where id = 'economia';
insert into public.habilidades_catalogo (id, classe, ordem, nome, descricao, bonus, req, ativo, tier) values ('bolso_fundo','Comerciante',2,'Bolso Fundo','+5% de dinheiro ganho em batalhas por rank (em breve).',5,'[]'::jsonb,true,1) on conflict (id) do update set classe = excluded.classe, ordem = excluded.ordem, req = excluded.req, tier = excluded.tier;
insert into public.habilidades_catalogo (id, classe, ordem, nome, descricao, bonus, req, ativo, tier) values ('barganha','Comerciante',3,'Barganha','A ação Barganhar rende +3% de desconto por rank (em breve).',3,'[]'::jsonb,true,1) on conflict (id) do update set classe = excluded.classe, ordem = excluded.ordem, req = excluded.req, tier = excluded.tier;
insert into public.habilidades_catalogo (id, classe, ordem, nome, descricao, bonus, req, ativo, tier) values ('feirante','Comerciante',4,'Feirante','+2% de chance de achar um item extra ao explorar por rank (em breve).',2,'[]'::jsonb,true,1) on conflict (id) do update set classe = excluded.classe, ordem = excluded.ordem, req = excluded.req, tier = excluded.tier;
insert into public.habilidades_catalogo (id, classe, ordem, nome, descricao, bonus, req, ativo, tier) values ('estoque','Comerciante',5,'Estoque','+10 no limite de compra por item por rank (em breve).',10,'[]'::jsonb,true,1) on conflict (id) do update set classe = excluded.classe, ordem = excluded.ordem, req = excluded.req, tier = excluded.tier;
insert into public.habilidades_catalogo (id, classe, ordem, nome, descricao, bonus, req, ativo, tier) values ('faro_negocios','Comerciante',6,'Faro para Negócios','Mostra o melhor preço entre as lojas visitadas (em breve).',1,'[{"id": "economia", "rank": 2}]'::jsonb,true,2) on conflict (id) do update set classe = excluded.classe, ordem = excluded.ordem, req = excluded.req, tier = excluded.tier;
insert into public.habilidades_catalogo (id, classe, ordem, nome, descricao, bonus, req, ativo, tier) values ('venda_premium','Comerciante',7,'Venda Premium','Vende itens por +5% a mais por rank (em breve).',5,'[{"id": "feirante", "rank": 2}]'::jsonb,true,2) on conflict (id) do update set classe = excluded.classe, ordem = excluded.ordem, req = excluded.req, tier = excluded.tier;
insert into public.habilidades_catalogo (id, classe, ordem, nome, descricao, bonus, req, ativo, tier) values ('cliente_fiel','Comerciante',8,'Cliente Fiel','+2% de desconto na cidade onde você mais compra, por rank (em breve).',2,'[{"id": "barganha", "rank": 2}]'::jsonb,true,2) on conflict (id) do update set classe = excluded.classe, ordem = excluded.ordem, req = excluded.req, tier = excluded.tier;
insert into public.habilidades_catalogo (id, classe, ordem, nome, descricao, bonus, req, ativo, tier) values ('renda_passiva','Comerciante',9,'Renda Passiva','Rende ₽100 por rank uma vez por dia (em breve).',100,'[{"id": "bolso_fundo", "rank": 2}]'::jsonb,true,2) on conflict (id) do update set classe = excluded.classe, ordem = excluded.ordem, req = excluded.req, tier = excluded.tier;
insert into public.habilidades_catalogo (id, classe, ordem, nome, descricao, bonus, req, ativo, tier) values ('cofre','Comerciante',10,'Cofre','Protege parte do dinheiro de perdas em derrotas (em breve).',10,'[{"id": "estoque", "rank": 2}]'::jsonb,true,2) on conflict (id) do update set classe = excluded.classe, ordem = excluded.ordem, req = excluded.req, tier = excluded.tier;
insert into public.habilidades_catalogo (id, classe, ordem, nome, descricao, bonus, req, ativo, tier) values ('importador','Comerciante',11,'Importador','Libera itens raros nas lojas (em breve).',1,'[{"id": "faro_negocios", "rank": 2}, {"id": "venda_premium", "rank": 2}]'::jsonb,true,3) on conflict (id) do update set classe = excluded.classe, ordem = excluded.ordem, req = excluded.req, tier = excluded.tier;
insert into public.habilidades_catalogo (id, classe, ordem, nome, descricao, bonus, req, ativo, tier) values ('leilao','Comerciante',12,'Leilão','Chance de vender um item por até o dobro (em breve).',5,'[{"id": "venda_premium", "rank": 2}, {"id": "cliente_fiel", "rank": 2}]'::jsonb,true,3) on conflict (id) do update set classe = excluded.classe, ordem = excluded.ordem, req = excluded.req, tier = excluded.tier;
insert into public.habilidades_catalogo (id, classe, ordem, nome, descricao, bonus, req, ativo, tier) values ('magnata','Comerciante',13,'Magnata','+₽200 por rank na renda diária (em breve).',200,'[{"id": "renda_passiva", "rank": 2}, {"id": "cofre", "rank": 2}]'::jsonb,true,3) on conflict (id) do update set classe = excluded.classe, ordem = excluded.ordem, req = excluded.req, tier = excluded.tier;
insert into public.habilidades_catalogo (id, classe, ordem, nome, descricao, bonus, req, ativo, tier) values ('mercador_itinerante','Comerciante',14,'Mercador Itinerante','O mercador itinerante aparece com mais frequência (em breve).',1,'[{"id": "cliente_fiel", "rank": 2}, {"id": "faro_negocios", "rank": 2}]'::jsonb,true,3) on conflict (id) do update set classe = excluded.classe, ordem = excluded.ordem, req = excluded.req, tier = excluded.tier;
insert into public.habilidades_catalogo (id, classe, ordem, nome, descricao, bonus, req, ativo, tier) values ('barao_comercio','Comerciante',15,'Barão do Comércio','Descontos e rendas em dobro no seu dia de sorte (em breve).',1,'[{"id": "importador", "rank": 2}, {"id": "magnata", "rank": 2}]'::jsonb,true,4) on conflict (id) do update set classe = excluded.classe, ordem = excluded.ordem, req = excluded.req, tier = excluded.tier;
insert into public.habilidades_catalogo (id, classe, ordem, nome, descricao, bonus, req, ativo, tier) values ('mira_captura','Ranger',1,'Mira de Captura','+2% de chance de captura por rank (em breve).',2,'[]'::jsonb,true,1) on conflict (id) do update set classe = excluded.classe, ordem = excluded.ordem, req = excluded.req, tier = excluded.tier;
insert into public.habilidades_catalogo (id, classe, ordem, nome, descricao, bonus, req, ativo, tier) values ('isca','Ranger',2,'Isca','+3% de chance de fisgar algo ao pescar por rank (em breve).',3,'[]'::jsonb,true,1) on conflict (id) do update set classe = excluded.classe, ordem = excluded.ordem, req = excluded.req, tier = excluded.tier;
insert into public.habilidades_catalogo (id, classe, ordem, nome, descricao, bonus, req, ativo, tier) values ('pescador','Ranger',3,'Pescador','Pescar rende +5 XP de treinador por rank (em breve).',5,'[]'::jsonb,true,1) on conflict (id) do update set classe = excluded.classe, ordem = excluded.ordem, req = excluded.req, tier = excluded.tier;
insert into public.habilidades_catalogo (id, classe, ordem, nome, descricao, bonus, req, ativo, tier) values ('rastreador','Ranger',4,'Rastreador','+2% de chance de encontro em grama e floresta por rank (em breve).',2,'[]'::jsonb,true,1) on conflict (id) do update set classe = excluded.classe, ordem = excluded.ordem, req = excluded.req, tier = excluded.tier;
insert into public.habilidades_catalogo (id, classe, ordem, nome, descricao, bonus, req, ativo, tier) values ('camuflagem','Ranger',5,'Camuflagem','Pokémon selvagens fogem menos (em breve).',3,'[]'::jsonb,true,1) on conflict (id) do update set classe = excluded.classe, ordem = excluded.ordem, req = excluded.req, tier = excluded.tier;
insert into public.habilidades_catalogo (id, classe, ordem, nome, descricao, bonus, req, ativo, tier) values ('redes_reforcadas','Ranger',6,'Redes Reforçadas','Pesca: +5% de chance de Pokémon raro por rank (em breve).',5,'[{"id": "isca", "rank": 2}]'::jsonb,true,2) on conflict (id) do update set classe = excluded.classe, ordem = excluded.ordem, req = excluded.req, tier = excluded.tier;
insert into public.habilidades_catalogo (id, classe, ordem, nome, descricao, bonus, req, ativo, tier) values ('brilho_caca','Ranger',7,'Brilho de Caça','+0,1% de chance de brilhante em selvagens por rank (em breve).',0.1,'[{"id": "rastreador", "rank": 2}]'::jsonb,true,2) on conflict (id) do update set classe = excluded.classe, ordem = excluded.ordem, req = excluded.req, tier = excluded.tier;
insert into public.habilidades_catalogo (id, classe, ordem, nome, descricao, bonus, req, ativo, tier) values ('domador','Ranger',8,'Domador','Selvagens começam com -3% de HP por rank (em breve).',3,'[{"id": "mira_captura", "rank": 2}]'::jsonb,true,2) on conflict (id) do update set classe = excluded.classe, ordem = excluded.ordem, req = excluded.req, tier = excluded.tier;
insert into public.habilidades_catalogo (id, classe, ordem, nome, descricao, bonus, req, ativo, tier) values ('pesca_noturna','Ranger',9,'Pesca Noturna','Pesca rende mais à noite (em breve).',5,'[{"id": "pescador", "rank": 2}]'::jsonb,true,2) on conflict (id) do update set classe = excluded.classe, ordem = excluded.ordem, req = excluded.req, tier = excluded.tier;
insert into public.habilidades_catalogo (id, classe, ordem, nome, descricao, bonus, req, ativo, tier) values ('explorador_rotas','Ranger',10,'Explorador de Rotas','Explorar em rotas rende +5% de recompensa por rank (em breve).',5,'[{"id": "camuflagem", "rank": 2}]'::jsonb,true,2) on conflict (id) do update set classe = excluded.classe, ordem = excluded.ordem, req = excluded.req, tier = excluded.tier;
insert into public.habilidades_catalogo (id, classe, ordem, nome, descricao, bonus, req, ativo, tier) values ('armadilha','Ranger',11,'Armadilha','Pode prender o selvagem antes da luta (em breve).',1,'[{"id": "domador", "rank": 2}, {"id": "redes_reforcadas", "rank": 2}]'::jsonb,true,3) on conflict (id) do update set classe = excluded.classe, ordem = excluded.ordem, req = excluded.req, tier = excluded.tier;
insert into public.habilidades_catalogo (id, classe, ordem, nome, descricao, bonus, req, ativo, tier) values ('isca_rara','Ranger',12,'Isca Rara','Aumenta a chance de selvagens raros em qualquer ação (em breve).',3,'[{"id": "redes_reforcadas", "rank": 2}, {"id": "brilho_caca", "rank": 2}]'::jsonb,true,3) on conflict (id) do update set classe = excluded.classe, ordem = excluded.ordem, req = excluded.req, tier = excluded.tier;
insert into public.habilidades_catalogo (id, classe, ordem, nome, descricao, bonus, req, ativo, tier) values ('mestre_pesca','Ranger',13,'Mestre da Pesca','+10% de chance de Pokémon ao pescar por rank (em breve).',10,'[{"id": "pesca_noturna", "rank": 2}, {"id": "explorador_rotas", "rank": 2}]'::jsonb,true,3) on conflict (id) do update set classe = excluded.classe, ordem = excluded.ordem, req = excluded.req, tier = excluded.tier;
insert into public.habilidades_catalogo (id, classe, ordem, nome, descricao, bonus, req, ativo, tier) values ('instinto_selvagem','Ranger',14,'Instinto Selvagem','Selvagens têm -2% de precisão por rank (em breve).',2,'[{"id": "domador", "rank": 2}, {"id": "explorador_rotas", "rank": 2}]'::jsonb,true,3) on conflict (id) do update set classe = excluded.classe, ordem = excluded.ordem, req = excluded.req, tier = excluded.tier;
insert into public.habilidades_catalogo (id, classe, ordem, nome, descricao, bonus, req, ativo, tier) values ('guardiao_selvagem','Ranger',15,'Guardião Selvagem','A primeira bola de cada captura nunca falha no primeiro balanço (em breve).',1,'[{"id": "mestre_pesca", "rank": 2}, {"id": "instinto_selvagem", "rank": 2}]'::jsonb,true,4) on conflict (id) do update set classe = excluded.classe, ordem = excluded.ordem, req = excluded.req, tier = excluded.tier;
insert into public.habilidades_catalogo (id, classe, ordem, nome, descricao, bonus, req, ativo, tier) values ('tatico','Estrategista',1,'Tático','+1% de chance de agir primeiro por rank (em breve).',1,'[]'::jsonb,true,1) on conflict (id) do update set classe = excluded.classe, ordem = excluded.ordem, req = excluded.req, tier = excluded.tier;
insert into public.habilidades_catalogo (id, classe, ordem, nome, descricao, bonus, req, ativo, tier) values ('curandeiro','Estrategista',2,'Curandeiro','Itens de cura em batalha curam +5% por rank (em breve).',5,'[]'::jsonb,true,1) on conflict (id) do update set classe = excluded.classe, ordem = excluded.ordem, req = excluded.req, tier = excluded.tier;
insert into public.habilidades_catalogo (id, classe, ordem, nome, descricao, bonus, req, ativo, tier) values ('maestria_itens','Estrategista',3,'Maestria de Itens','Itens segurados ficam 5% mais fortes por rank (em breve).',5,'[]'::jsonb,true,1) on conflict (id) do update set classe = excluded.classe, ordem = excluded.ordem, req = excluded.req, tier = excluded.tier;
insert into public.habilidades_catalogo (id, classe, ordem, nome, descricao, bonus, req, ativo, tier) values ('analista','Estrategista',4,'Analista','Mostra os golpes mais fortes do adversário (em breve).',1,'[]'::jsonb,true,1) on conflict (id) do update set classe = excluded.classe, ordem = excluded.ordem, req = excluded.req, tier = excluded.tier;
insert into public.habilidades_catalogo (id, classe, ordem, nome, descricao, bonus, req, ativo, tier) values ('veneno_lento','Estrategista',5,'Veneno Lento','Veneno e queimadura causam +10% de dano por rank (em breve).',10,'[]'::jsonb,true,1) on conflict (id) do update set classe = excluded.classe, ordem = excluded.ordem, req = excluded.req, tier = excluded.tier;
insert into public.habilidades_catalogo (id, classe, ordem, nome, descricao, bonus, req, ativo, tier) values ('controle_status','Estrategista',6,'Controle de Status','+3% de chance de aplicar status por rank (em breve).',3,'[{"id": "veneno_lento", "rank": 2}]'::jsonb,true,2) on conflict (id) do update set classe = excluded.classe, ordem = excluded.ordem, req = excluded.req, tier = excluded.tier;
insert into public.habilidades_catalogo (id, classe, ordem, nome, descricao, bonus, req, ativo, tier) values ('resist_status','Estrategista',7,'Resistência a Status','-5% de chance de sofrer status por rank (em breve).',5,'[{"id": "curandeiro", "rank": 2}]'::jsonb,true,2) on conflict (id) do update set classe = excluded.classe, ordem = excluded.ordem, req = excluded.req, tier = excluded.tier;
insert into public.habilidades_catalogo (id, classe, ordem, nome, descricao, bonus, req, ativo, tier) values ('combo','Estrategista',8,'Combo','Golpes em sequência ganham +2% de dano por rank (em breve).',2,'[{"id": "tatico", "rank": 2}]'::jsonb,true,2) on conflict (id) do update set classe = excluded.classe, ordem = excluded.ordem, req = excluded.req, tier = excluded.tier;
insert into public.habilidades_catalogo (id, classe, ordem, nome, descricao, bonus, req, ativo, tier) values ('troca_rapida','Estrategista',9,'Troca Rápida','Trocar de Pokémon tem +5% de chance de não gastar o turno por rank (em breve).',5,'[{"id": "analista", "rank": 2}]'::jsonb,true,2) on conflict (id) do update set classe = excluded.classe, ordem = excluded.ordem, req = excluded.req, tier = excluded.tier;
insert into public.habilidades_catalogo (id, classe, ordem, nome, descricao, bonus, req, ativo, tier) values ('mao_ferro','Estrategista',10,'Mão de Ferro','Itens Escolha deixam de travar o golpe no último rank (em breve).',1,'[{"id": "maestria_itens", "rank": 2}]'::jsonb,true,2) on conflict (id) do update set classe = excluded.classe, ordem = excluded.ordem, req = excluded.req, tier = excluded.tier;
insert into public.habilidades_catalogo (id, classe, ordem, nome, descricao, bonus, req, ativo, tier) values ('mestre_itens','Estrategista',11,'Mestre de Itens','Pode segurar um segundo item (em breve).',1,'[{"id": "mao_ferro", "rank": 2}, {"id": "resist_status", "rank": 2}]'::jsonb,true,3) on conflict (id) do update set classe = excluded.classe, ordem = excluded.ordem, req = excluded.req, tier = excluded.tier;
insert into public.habilidades_catalogo (id, classe, ordem, nome, descricao, bonus, req, ativo, tier) values ('xadrez','Estrategista',12,'Xadrez','Antecipa o próximo golpe do adversário (em breve).',1,'[{"id": "combo", "rank": 2}, {"id": "troca_rapida", "rank": 2}]'::jsonb,true,3) on conflict (id) do update set classe = excluded.classe, ordem = excluded.ordem, req = excluded.req, tier = excluded.tier;
insert into public.habilidades_catalogo (id, classe, ordem, nome, descricao, bonus, req, ativo, tier) values ('imprevisivel','Estrategista',13,'Imprevisível','+3% de chance de esquivar por rank (em breve).',3,'[{"id": "controle_status", "rank": 2}, {"id": "combo", "rank": 2}]'::jsonb,true,3) on conflict (id) do update set classe = excluded.classe, ordem = excluded.ordem, req = excluded.req, tier = excluded.tier;
insert into public.habilidades_catalogo (id, classe, ordem, nome, descricao, bonus, req, ativo, tier) values ('cirurgiao','Estrategista',14,'Cirurgião','Itens de cura de status também curam 10% do HP por rank (em breve).',10,'[{"id": "resist_status", "rank": 2}, {"id": "controle_status", "rank": 2}]'::jsonb,true,3) on conflict (id) do update set classe = excluded.classe, ordem = excluded.ordem, req = excluded.req, tier = excluded.tier;
insert into public.habilidades_catalogo (id, classe, ordem, nome, descricao, bonus, req, ativo, tier) values ('grande_estrategista','Estrategista',15,'Grande Estrategista','+3% em todos os atributos quando está em desvantagem (em breve).',3,'[{"id": "mestre_itens", "rank": 2}, {"id": "xadrez", "rank": 2}]'::jsonb,true,4) on conflict (id) do update set classe = excluded.classe, ordem = excluded.ordem, req = excluded.req, tier = excluded.tier;

create or replace function public._pontos_total(p_j uuid) returns int language sql stable security definer set search_path = public as $$
  select floor((public._nivel_treino(coalesce((select xp_treino from public.jogadores where id = p_j), 0)) - 1) / 2.0)::int
       + coalesce((select floor(sum(n) / 10)::int from (select nivel::int as n from public.pokemons where dono = p_j order by nivel desc limit 6) s), 0) $$;
create or replace function public._pontos_gastos(p_j uuid) returns int language sql stable security definer set search_path = public as $$
  select coalesce((select sum(s.r * (coalesce(c.tier, 1) - 1) + s.r * (s.r + 1) / 2)
                     from (select key as id, value::int as r from public.jogadores, jsonb_each_text(habilidades) where jogadores.id = p_j) s
                     left join public.habilidades_catalogo c on c.id = s.id), 0)::int $$;

create or replace function public.estado_treino() returns jsonb language plpgsql security definer stable set search_path = public as $$
declare j public.jogadores; nv int;
begin
  select * into j from public.jogadores where id = auth.uid();
  if not found then raise exception 'Crie seu personagem primeiro.'; end if;
  nv := public._nivel_treino(j.xp_treino);
  return jsonb_build_object('classe', j.classe_rpg, 'classe_sec', j.classe_sec, 'nivel', nv, 'xp', j.xp_treino, 'xp_atual_nivel', public._xp_para_nivel(nv),
    'xp_prox', case when nv >= public._cfg_int('nivel_treino_max', 30) then null else public._xp_para_nivel(nv + 1) end,
    'pontos_total', public._pontos_total(j.id), 'pontos_gastos', public._pontos_gastos(j.id), 'habilidades', j.habilidades,
    'pesquisadas', (select count(*) from public.pokedex where jogador = j.id and pesquisado));
end $$;
grant execute on function public.estado_treino() to authenticated;

create or replace function public.escolher_classe(p_classe text) returns void language plpgsql security definer set search_path = public as $$
begin
  if p_classe not in ('Treinador','Criador','Pesquisador','Comerciante','Ranger','Estrategista') then raise exception 'Classe inválida.'; end if;
  if exists (select 1 from public.jogadores where id = auth.uid() and classe_rpg is not null) then raise exception 'Você já escolheu uma classe. Peça ao Mestre para redefinir.'; end if;
  update public.jogadores set classe_rpg = p_classe where id = auth.uid();
end $$;
grant execute on function public.escolher_classe(text) to authenticated;

create or replace function public.escolher_classe_secundaria(p_classe text) returns void language plpgsql security definer set search_path = public as $$
declare j public.jogadores;
begin
  select * into j from public.jogadores where id = auth.uid() for update;
  if not found then raise exception 'Crie seu personagem primeiro.'; end if;
  if p_classe not in ('Treinador','Criador','Pesquisador','Comerciante','Ranger','Estrategista') then raise exception 'Classe inválida.'; end if;
  if j.classe_rpg is null then raise exception 'Escolha primeiro a classe principal.'; end if;
  if j.classe_sec is not null then raise exception 'Você já escolheu a classe secundária. Peça ao Mestre para redefinir.'; end if;
  if p_classe = j.classe_rpg then raise exception 'A secundária precisa ser diferente da principal.'; end if;
  if public._nivel_treino(j.xp_treino) < 5 then raise exception 'A classe secundária libera no nível de treinador 5.'; end if;
  update public.jogadores set classe_sec = p_classe where id = j.id;
end $$;
grant execute on function public.escolher_classe_secundaria(text) to authenticated;

create or replace function public.comprar_habilidade(p_hab text) returns jsonb language plpgsql security definer set search_path = public as $$
declare j public.jogadores; h public.habilidades_catalogo; r int; custo int; q jsonb;
begin
  select * into j from public.jogadores where id = auth.uid() for update;
  if not found then raise exception 'Crie seu personagem primeiro.'; end if;
  select * into h from public.habilidades_catalogo where id = p_hab;
  if not found then raise exception 'Habilidade inexistente.'; end if;
  if j.classe_rpg is null then raise exception 'Escolha sua classe primeiro.'; end if;
  if h.classe <> j.classe_rpg then
    if j.classe_sec is null or h.classe <> j.classe_sec then raise exception 'Esta habilidade é de outra classe.'; end if;
    if h.tier > 2 then raise exception 'A classe secundária libera só os Tiers I e II.'; end if;
  end if;
  r := coalesce((j.habilidades ->> p_hab)::int, 0);
  if r >= 3 then raise exception 'Habilidade já está no nível máximo.'; end if;
  for q in select * from jsonb_array_elements(h.req) loop
    if coalesce((j.habilidades ->> (q ->> 'id'))::int, 0) < (q ->> 'rank')::int then
      raise exception 'Requisito: % no rank %.', (select nome from public.habilidades_catalogo where id = q ->> 'id'), q ->> 'rank';
    end if;
  end loop;
  if h.tier = 4 and not exists (select 1 from jsonb_each_text(j.habilidades) e join public.habilidades_catalogo c on c.id = e.key where c.classe <> h.classe and e.value::int >= 2) then
    raise exception 'Mestria: exige também 1 habilidade de outra classe no rank 2.';
  end if;
  custo := (h.tier - 1) + r + 1;
  if public._pontos_total(j.id) - public._pontos_gastos(j.id) < custo then raise exception 'Pontos insuficientes (custa %).', custo; end if;
  update public.jogadores set habilidades = habilidades || jsonb_build_object(p_hab, r + 1) where id = j.id;
  if p_hab in ('resistencia', 'provocacao', 'intuicao') then
    update public.jogadores set pa = least(32000, pa + (select bonus::int from public.habilidades_catalogo where id = p_hab)) where id = j.id;
  end if;
  return public.estado_treino();
end $$;
grant execute on function public.comprar_habilidade(text) to authenticated;
