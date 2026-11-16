-- m68: liga efeitos de habilidades que estavam "em breve" (economia, exploração, pesca, captura, ovos, duelos).
-- Os efeitos de batalha (engine) vão no deploy da Edge Function batalha + engine.js.
create or replace function public._pt(d text, a text, b text) returns text language plpgsql as $$
begin
  if position(a in d) = 0 then raise exception 'Trecho não encontrado: %', left(a, 70); end if;
  return replace(d, a, b);
end $$;

do $$
declare d text;
begin
  -- Barganha: +3% de desconto por rank
  d := pg_get_functiondef('public.acao_barganhar()'::regprocedure);
  d := public._pt(d, 'case when ok then 10 else', 'case when ok then 10 + 3 * public._rank(auth.uid(), ''barganha'') else');
  execute d;

  -- Enciclopédia: +₽50 por rank ao pesquisar
  d := pg_get_functiondef('public.acao_pesquisar(integer)'::regprocedure);
  d := public._pt(d, 'if n % 10 = 0 then extra := 500; end if;', 'if n % 10 = 0 then extra := 500; end if; din := din + 50 * public._rank(auth.uid(), ''enciclopedia'');');
  execute d;

  -- Explorar: Feirante (item extra) e Explorador de Rotas (+5%/rank em rotas)
  d := pg_get_functiondef('public.acao_explorar()'::regprocedure);
  d := public._pt(d, 'mult := (1 + public._bonus(j.id, ''exploracao'') / 100.0)', 'mult := (1 + public._bonus(j.id, ''exploracao'') / 100.0 + case when j.mapa_id like ''rota%'' then 0.05 * public._rank(j.id, ''explorador_rotas'') else 0 end)');
  d := public._pt(d, 'perform public._ganhar_xp_treino(j.id, 10);', 'perform public._ganhar_xp_treino(j.id, 10);
  if random() < 0.02 * public._rank(j.id, ''feirante'') then
    insert into public.inventario (jogador, item, qtd) values (j.id, ''potion'', 1) on conflict (jogador, item) do update set qtd = public.inventario.qtd + 1;
  end if;');
  execute d;

  -- Loja: Estoque (+10 no limite por item por rank)
  d := pg_get_functiondef('public.comprar_item(text,text,integer)'::regprocedure);
  d := public._pt(d, '99 + floor(public._bonus(auth.uid(), ''mochila''))::int', '99 + floor(public._bonus(auth.uid(), ''mochila''))::int + 10 * public._rank(auth.uid(), ''estoque'')');
  execute d;

  -- Pesca: Isca, Isca Especial, Mestre da Pesca, Pescador, Redes Reforçadas
  d := pg_get_functiondef('public.acao_pescar()'::regprocedure);
  d := public._pt(d, 'v_b := public._bonus(j.id, ''rede_pesca'') / 100.0;', 'v_b := least(0.45, public._bonus(j.id, ''rede_pesca'') / 100.0 + 0.03 * public._rank(j.id, ''isca'') + 0.05 * public._rank(j.id, ''isca_especial'') + 0.10 * public._rank(j.id, ''mestre_pesca''));');
  d := public._pt(d, 'perform public._ganhar_xp_treino(j.id, 10);', 'perform public._ganhar_xp_treino(j.id, 10 + 5 * public._rank(j.id, ''pescador''));');
  d := public._pt(d, 'then 2 else 1 end', 'then 2 + public._rank(j.id, ''redes_reforcadas'') else 1 end');
  execute d;

  -- Encontros: Binóculos, Rastreador, Farejador, Isca Rara
  d := pg_get_functiondef('public.gerar_oferta()'::regprocedure);
  d := public._pt(d, 'public._ev(''encontro'', 1) *', 'public._ev(''encontro'', 1) * (1 + 0.03 * public._rank(v_j.id, ''binoculos'') + case when v_bioma in (''grama'', ''floresta'') then 0.02 * public._rank(v_j.id, ''rastreador'') else 0 end) *');
  d := public._pt(d, 'v_tipo := public._ev_alvo(''tipo_destaque'');', 'if random() < 0.02 * public._rank(v_j.id, ''farejador'') + 0.05 * public._rank(v_j.id, ''isca_rara'') then
    select e3.especie_id, e3.nivel_min, e3.nivel_max into v_e2 from public.encontros e3 where e3.mapa_id = v_j.mapa_id and e3.bioma = v_bioma and e3.peso <= 10 order by random() limit 1;
    if v_e2.especie_id is not null then v_e := v_e2; v_nivel := greatest(v_e2.nivel_min, least(v_e2.nivel_max, v_nivel)); end if;
  end if;
  v_tipo := public._ev_alvo(''tipo_destaque'');');
  execute d;

  -- Captura: Mira (+2%/rank) soma ao bônus de captura enviado à batalha
  d := pg_get_functiondef('public.sim_bonus(uuid)'::regprocedure);
  d := public._pt(d, '''captura'', public._bonus(p_jogador, ''captura'')', '''captura'', public._bonus(p_jogador, ''captura'') + 2 * public._rank(p_jogador, ''mira_captura'')');
  execute d;

  -- Duelos/dinheiro: Bolso Fundo e Duelista (+5%/rank no prêmio); Duelista também +5% de XP em duelos
  d := pg_get_functiondef('public.sim_gravar(uuid,integer,jsonb,jsonb,integer,jsonb,text,jsonb)'::regprocedure);
  d := public._pt(d, '(1 + public._bonus(b.jogador, ''recompensa'') / 100.0)', '(1 + (public._bonus(b.jogador, ''recompensa'') + 5 * public._rank(b.jogador, ''bolso_fundo'') + 5 * public._rank(b.jogador, ''duelista'')) / 100.0)');
  d := public._pt(d, 'public._xp_mult_time() / n', 'public._xp_mult_time() * (1 + case when b.tipo = ''treinador'' then 0.05 * public._rank(b.jogador, ''duelista'') else 0 end) / n');
  execute d;

  -- Check-in: Renda Passiva e Magnata (renda diária)
  d := pg_get_functiondef('public.fazer_checkin()'::regprocedure);
  d := public._pt(d, 'ent := public._conceder(v_j.id, rec);', 'update public.jogadores set dinheiro = dinheiro + 100 * public._rank(v_j.id, ''renda_passiva'') + 200 * public._rank(v_j.id, ''magnata'') where id = v_j.id;
  ent := public._conceder(v_j.id, rec);');
  execute d;

  -- Pokédex: Naturalista (+10 XP de treinador por rank na espécie nova)
  d := pg_get_functiondef('public._tg_xp_dex()'::regprocedure);
  d := public._pt(d, 'floor(public._bonus(new.jogador, ''pokedex_viva''))::int', 'floor(public._bonus(new.jogador, ''pokedex_viva''))::int + 10 * public._rank(new.jogador, ''naturalista'')');
  execute d;

  -- Ovos: Berçário (+1 incubadora por rank) e Chocadeira (+10% de passos por rank)
  d := pg_get_functiondef('public.ovo_incubar(uuid,boolean)'::regprocedure);
  d := public._pt(d, 'select incubadoras into lim', 'select incubadoras + public._rank(auth.uid(), ''bercario'') into lim');
  execute d;
  d := pg_get_functiondef('public._tg_passos_ovo()'::regprocedure);
  d := public._pt(d, 'add := least(dist,', 'add := least(ceil(dist * (1 + 0.1 * public._rank(new.id, ''chocadeira'')))::int,');
  execute d;
  -- Corrige "column reference item is ambiguous" em Explorar (a variavel item colidia com a coluna do inventario)
  d := pg_get_functiondef('public.acao_explorar()'::regprocedure);
  d := public._pt(d, 'item text;', 'v_item text;');
  d := public._pt(d, 'item := case', 'v_item := case');
  d := public._pt(d, 'slug = item)', 'slug = v_item)');
  d := public._pt(d, 'then item := ', 'then v_item := ');
  d := public._pt(d, 'values (j.id, item,', 'values (j.id, v_item,');
  d := public._pt(d, '''item'', item,', '''item'', v_item,');
  execute d;
end $$;

drop function public._pt(text, text, text);

-- Catálogo: tira o "(em breve)" do que passou a funcionar
update public.habilidades_catalogo set descricao = trim(regexp_replace(descricao, ' ?\((ainda )?em breve\)', ''))
 where id in ('bolso_fundo','barganha','feirante','estoque','renda_passiva','magnata','naturalista','farejador','binoculos','isca_especial','enciclopedia',
  'mira_captura','isca','pescador','rastreador','redes_reforcadas','explorador_rotas','isca_rara','mestre_pesca','duelista','chocadeira','bercario');
update public.habilidades_catalogo set descricao = 'Ovos e a Casa estão liberados: a habilidade abre o uso das habilidades de ovos do Criador.' where id = 'ovos';
update public.habilidades_catalogo set descricao = 'Pesca: Pokémon raros ficam mais comuns a cada rank.' where id = 'redes_reforcadas';
update public.habilidades_catalogo set descricao = '+10% de passos nos ovos incubando por rank.' where id = 'chocadeira';
update public.habilidades_catalogo set descricao = '+1 incubadora por rank.' where id = 'bercario';
update public.habilidades_catalogo set descricao = 'Rende ₽100 por rank uma vez por dia, no check-in.' where id = 'renda_passiva';
update public.habilidades_catalogo set descricao = '+₽200 por rank na renda diária (check-in).' where id = 'magnata';
update public.habilidades_catalogo set descricao = 'Explorar em rotas rende +5% de recompensa por rank.' where id = 'explorador_rotas';
update public.habilidades_catalogo set descricao = '+5% de dinheiro ganho em duelos por rank.' where id = 'bolso_fundo';
update public.habilidades_catalogo set descricao = '+5% de experiência e de dinheiro em duelos contra treinadores por rank.' where id = 'duelista';

-- Domador e Guardião Selvagem: ranks enviados à Edge Function batalha via sim_bonus
do $$
declare d text;
begin
  d := pg_get_functiondef('public.sim_bonus(uuid)'::regprocedure);
  if position('''instinto'', public._bonus(p_jogador, ''instinto'')' in d) = 0 then raise exception 'trecho'; end if;
  d := replace(d, '''instinto'', public._bonus(p_jogador, ''instinto'')', '''domador'', public._rank(p_jogador, ''domador''), ''guardiao'', public._rank(p_jogador, ''guardiao_selvagem''), ''instinto'', public._bonus(p_jogador, ''instinto'')');
  execute d;
end $$;
update public.habilidades_catalogo set descricao = trim(regexp_replace(descricao, ' ?\((ainda )?em breve\)', '')) where id in ('domador','guardiao_selvagem');
