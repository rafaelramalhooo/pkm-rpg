-- m21: sistema de missões (dados em tabelas) + missão de teste "A Carta de Alvorada"
create table if not exists public.npcs_missao (
  id text primary key, mapa_id text not null, x int not null, y int not null, direcao text not null default 'baixo',
  nome text not null, classe text not null default 'Morador', aparencia smallint not null default 0,
  falas jsonb not null default '{}'::jsonb
);
create table if not exists public.missoes (
  id text primary key, nome text not null, descricao text not null, etapas jsonb not null, recompensa jsonb not null default '{}'::jsonb, ativa boolean not null default true
);
create table if not exists public.missao_jogador (
  jogador uuid not null references public.jogadores (id) on delete cascade,
  missao text not null references public.missoes (id) on delete cascade,
  etapa int not null default 1, estado text not null default 'ativa' check (estado in ('ativa', 'concluida')),
  atualizado timestamptz not null default now(), primary key (jogador, missao)
);
alter table public.npcs_missao enable row level security; alter table public.missoes enable row level security; alter table public.missao_jogador enable row level security;
drop policy if exists "npcm_leitura" on public.npcs_missao; create policy "npcm_leitura" on public.npcs_missao for select to authenticated using (true);
drop policy if exists "mis_leitura" on public.missoes; create policy "mis_leitura" on public.missoes for select to authenticated using (true);
drop policy if exists "mj_dono" on public.missao_jogador; create policy "mj_dono" on public.missao_jogador for select to authenticated using (jogador = auth.uid() or public.eh_mestre());
grant select on public.npcs_missao, public.missoes, public.missao_jogador to authenticated;

insert into public.npcs_missao (id, mapa_id, x, y, direcao, nome, classe, aparencia, falas) values
 ('q_lia',  'pallet', 15, 3,  'baixo',    'Dona Lia',  'Moradora',   5, '{"livre":"Bom dia! Que dia bonito em Vila Alvorada.","espera":"Já voltou? Ainda faltam coisas na lista, querido.","pos":"A carta chegou direitinho ao destino! Obrigada de novo."}'),
 ('q_beto', 'rota1',  20, 50, 'esquerda', 'Beto',      'Andarilho',  2, '{"livre":"Ando por esta rota há anos. Cuidado com a grama alta!","espera":"Já falou com a Nina, no Porto Turquesa?","pos":"Aquela Potion foi providencial. Boa viagem!"}'),
 ('q_nina', 'porto',  24, 35, 'baixo',    'Nina',      'Marinheira', 7, '{"livre":"O mar de Porto Turquesa nunca me cansa.","espera":"Agora procure o Gil, na Rota 2.","pos":"Voltou a me ver? Que bom! O mar agradece."}'),
 ('q_gil',  'rota2',  38, 8,  'baixo',    'Gil',       'Pesquisador',3, '{"livre":"Estudo os Pokémon desta rota há semanas.","espera":"Quando estiver tudo pronto, volte para Vila Alvorada.","pos":"Que bela captura aquele Mankey! Obrigado."}')
on conflict (id) do update set mapa_id = excluded.mapa_id, x = excluded.x, y = excluded.y, direcao = excluded.direcao, nome = excluded.nome,
  classe = excluded.classe, aparencia = excluded.aparencia, falas = excluded.falas;

insert into public.missoes (id, nome, descricao, etapas, recompensa) values
 ('carta_alvorada', 'A Carta de Alvorada',
  'Dona Lia perdeu o contato com o neto marinheiro e precisa de ajuda para reunir quatro pessoas e enviar a carta.',
  '[
    {"npc":"q_lia","objetivo":"Fale com Dona Lia, em Vila Alvorada","texto":"Ah, que bom ver alguém disposto! Escrevi uma carta para o meu neto, que trabalha no mar, mas o cartero sumiu. Se você falar com quatro pessoas por mim, a carta chega. Pode me ajudar?"},
    {"npc":"q_beto","objetivo":"Leve 1 Potion ao Beto, na Rota 1","exigir":{"tipo":"item","item":"potion","qtd":1},"antes":"Dona Lia mandou você? Estou com o Pokémon ferido... Se tivesse uma Potion, eu agradeceria muito.","depois":"Que alívio! Obrigado pela Potion. Fale com a Nina, no Porto Turquesa. Ela conhece o seu neto."},
    {"npc":"q_nina","objetivo":"Mostre um Pidgey no seu time à Nina, no Porto Turquesa","exigir":{"tipo":"time","especie":16},"antes":"Conheço o neto da Dona Lia! Mas só confio em quem cuida bem dos Pokémon. Traga um Pidgey no seu time para eu ver.","depois":"Que Pidgey bem cuidado! Pode confiar. O Gil, na Rota 2, é quem sabe do paradeiro dele. Vá lá."},
    {"npc":"q_gil","objetivo":"Capture um Mankey e entregue ao Gil, na Rota 2","exigir":{"tipo":"entregar_pokemon","especie":56},"antes":"Sei onde ele está, mas preciso de ajuda: capture um Mankey (nas rotas 1 e 2) e me traga. Eu o estudo em troca da informação.","depois":"Que beleza de Mankey! Em troca: o neto da Dona Lia está bem e já recebeu a notícia. Volte para contar a ela."},
    {"npc":"q_lia","objetivo":"Volte a Vila Alvorada e conte tudo à Dona Lia","depois":"Meu neto está bem! Você foi incansável. Aceite esta recompensa, e que a estrada seja boa para você!"}
  ]'::jsonb,
  '{"dinheiro":1500,"xp_treinador":150,"xp_pokemon":300,"itens":[{"item":"great-ball","qtd":5},{"item":"super-potion","qtd":3}]}'::jsonb)
on conflict (id) do update set nome = excluded.nome, descricao = excluded.descricao, etapas = excluded.etapas, recompensa = excluded.recompensa;

-- estado da missão para o HUD e o Mapa Mundi (null = sem missão ativa)
create or replace function public.missao_estado() returns jsonb language plpgsql stable security definer set search_path = public as $$
declare mj public.missao_jogador; m public.missoes; et jsonb; n public.npcs_missao; mp public.mapas; tot int;
begin
  if auth.uid() is null then return null; end if;
  select * into mj from public.missao_jogador where jogador = auth.uid() order by estado, atualizado desc limit 1;
  if not found then return null; end if;
  select * into m from public.missoes where id = mj.missao;
  tot := jsonb_array_length(m.etapas) - 1;
  if mj.estado = 'concluida' then return jsonb_build_object('id', m.id, 'nome', m.nome, 'estado', 'concluida', 'feitas', tot, 'total', tot); end if;
  et := m.etapas -> mj.etapa;
  select * into n from public.npcs_missao where id = et->>'npc';
  select * into mp from public.mapas where id = n.mapa_id;
  return jsonb_build_object('id', m.id, 'nome', m.nome, 'estado', 'ativa', 'feitas', mj.etapa - 1, 'total', tot, 'objetivo', et->>'objetivo',
    'npc', n.nome, 'mapa_id', n.mapa_id, 'mapa_nome', mp.nome);
end $$;
grant execute on function public.missao_estado() to authenticated;

create or replace function public._npc_adjacente(p_npc public.npcs_missao) returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.jogadores j where j.id = auth.uid() and j.mapa_id = p_npc.mapa_id and abs(j.x - p_npc.x) + abs(j.y - p_npc.y) = 1) $$;
revoke all on function public._npc_adjacente(public.npcs_missao) from public, anon, authenticated;

create or replace function public.missao_aceitar(p_npc text) returns jsonb language plpgsql security definer set search_path = public as $$
declare n public.npcs_missao; m public.missoes;
begin
  if auth.uid() is null then raise exception 'Faça login primeiro.'; end if;
  select * into n from public.npcs_missao where id = p_npc;
  if not found or not public._npc_adjacente(n) then raise exception 'Chegue perto do personagem para conversar.'; end if;
  select * into m from public.missoes where ativa and etapas -> 0 ->> 'npc' = n.id limit 1;
  if not found then raise exception 'Este personagem não tem missão para você.'; end if;
  if exists (select 1 from public.missao_jogador where jogador = auth.uid() and missao = m.id) then raise exception 'Você já aceitou esta missão.'; end if;
  insert into public.missao_jogador (jogador, missao, etapa) values (auth.uid(), m.id, 1);
  return public.missao_estado();
end $$;
grant execute on function public.missao_aceitar(text) to authenticated;

create or replace function public.npc_interagir(p_npc text) returns jsonb language plpgsql security definer set search_path = public as $$
declare n public.npcs_missao; m public.missoes; mj public.missao_jogador; et jsonb; ex jsonb; pk public.pokemons; rec jsonb; ev jsonb := '[]'::jsonb;
  it jsonb; concluida boolean := false; nome_m text; ganho int;
begin
  if auth.uid() is null then raise exception 'Faça login primeiro.'; end if;
  select * into n from public.npcs_missao where id = p_npc;
  if not found or not public._npc_adjacente(n) then raise exception 'Chegue perto do personagem para conversar.'; end if;
  select * into m from public.missoes where ativa order by id limit 1;
  select * into mj from public.missao_jogador where jogador = auth.uid() and missao = m.id for update;
  if not found then
    if m.etapas -> 0 ->> 'npc' = n.id then
      return jsonb_build_object('tipo', 'oferta', 'nome', n.nome, 'texto', m.etapas -> 0 ->> 'texto', 'missao', m.nome, 'descricao', m.descricao);
    end if;
    return jsonb_build_object('tipo', 'fala', 'nome', n.nome, 'texto', n.falas ->> 'livre');
  end if;
  if mj.estado = 'concluida' then return jsonb_build_object('tipo', 'fala', 'nome', n.nome, 'texto', coalesce(n.falas ->> 'pos', n.falas ->> 'livre')); end if;
  et := m.etapas -> mj.etapa;
  if et ->> 'npc' <> n.id then return jsonb_build_object('tipo', 'fala', 'nome', n.nome, 'texto', coalesce(n.falas ->> 'espera', n.falas ->> 'livre')); end if;
  ex := et -> 'exigir';
  if ex is not null then
    if ex ->> 'tipo' = 'item' then
      if not exists (select 1 from public.inventario where jogador = auth.uid() and item = ex ->> 'item' and qtd >= (ex ->> 'qtd')::int) then
        return jsonb_build_object('tipo', 'pendente', 'nome', n.nome, 'texto', et ->> 'antes');
      end if;
      update public.inventario set qtd = qtd - (ex ->> 'qtd')::int where jogador = auth.uid() and item = ex ->> 'item';
    elsif ex ->> 'tipo' = 'time' then
      if not exists (select 1 from public.pokemons where dono = auth.uid() and posicao is not null and especie_id = (ex ->> 'especie')::int) then
        return jsonb_build_object('tipo', 'pendente', 'nome', n.nome, 'texto', et ->> 'antes');
      end if;
    elsif ex ->> 'tipo' = 'entregar_pokemon' then
      -- prefere um Pokémon da caixa; do time só se sobrar outro no time
      select * into pk from public.pokemons where dono = auth.uid() and especie_id = (ex ->> 'especie')::int
         and (posicao is null or (select count(*) from public.pokemons where dono = auth.uid() and posicao is not null) > 1)
       order by (posicao is not null), nivel limit 1;
      if not found then return jsonb_build_object('tipo', 'pendente', 'nome', n.nome, 'texto', et ->> 'antes'); end if;
      update public.jogadores set seguidor = null where id = auth.uid() and seguidor = pk.id;
      delete from public.pokemons where id = pk.id;
    end if;
  end if;
  if mj.etapa + 1 >= jsonb_array_length(m.etapas) then
    concluida := true;
    rec := m.recompensa;
    update public.missao_jogador set estado = 'concluida', etapa = mj.etapa + 1, atualizado = now() where jogador = auth.uid() and missao = m.id;
    update public.jogadores set dinheiro = dinheiro + coalesce((rec ->> 'dinheiro')::int, 0) where id = auth.uid();
    perform public._ganhar_xp_treino(auth.uid(), coalesce((rec ->> 'xp_treinador')::int, 0));
    for it in select * from jsonb_array_elements(coalesce(rec -> 'itens', '[]'::jsonb)) loop
      insert into public.inventario (jogador, item, qtd) values (auth.uid(), it ->> 'item', (it ->> 'qtd')::int)
      on conflict (jogador, item) do update set qtd = public.inventario.qtd + excluded.qtd;
    end loop;
    ganho := coalesce((rec ->> 'xp_pokemon')::int, 0);
    if ganho > 0 then
      for pk in select * from public.pokemons where dono = auth.uid() and posicao is not null order by posicao loop
        ev := public._dar_exp(pk, jsonb_build_object('exp_base', ceil(ganho * 7.0 / greatest(1, pk.nivel)), 'nivel', pk.nivel), ev);
      end loop;
    end if;
  else
    update public.missao_jogador set etapa = mj.etapa + 1, atualizado = now() where jogador = auth.uid() and missao = m.id;
  end if;
  return jsonb_build_object('tipo', 'avanca', 'nome', n.nome, 'texto', et ->> 'depois', 'concluida', concluida, 'recompensa', case when concluida then rec end,
    'eventos', ev, 'missao', m.nome);
end $$;
grant execute on function public.npc_interagir(text) to authenticated;
