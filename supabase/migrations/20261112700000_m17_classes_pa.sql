-- m17: Classes, habilidades do treinador e ações de PA.
-- Números ficam em tabelas/config editáveis (habilidades_catalogo.bonus, config 'nivel_treino_max', 'mapas_pesca').
alter table public.jogadores
  add column if not exists classe_rpg text check (classe_rpg in ('Treinador','Criador','Pesquisador')),
  add column if not exists xp_treino int not null default 0,
  add column if not exists habilidades jsonb not null default '{}'::jsonb,
  add column if not exists desconto_barganha smallint not null default 0;
alter table public.pokemons add column if not exists amizade smallint not null default 70 check (amizade between 0 and 255);
alter table public.pokedex add column if not exists pesquisado boolean not null default false;

create table if not exists public.acoes_dia (
  jogador uuid not null references public.jogadores (id) on delete cascade,
  dia date not null default current_date, chave text not null, n int not null default 0,
  primary key (jogador, dia, chave)
);
alter table public.acoes_dia enable row level security;

create table if not exists public.habilidades_catalogo (
  id text primary key, classe text not null, ordem smallint not null, nome text not null, descricao text not null,
  bonus numeric not null default 0,            -- efeito por rank (unidade na descrição)
  req jsonb not null default '[]'::jsonb,      -- [{"id":"x","rank":3}]
  ativo boolean not null default true          -- false = ainda sem efeito no jogo ("em breve")
);
alter table public.habilidades_catalogo enable row level security;
drop policy if exists "hab_leitura" on public.habilidades_catalogo;
create policy "hab_leitura" on public.habilidades_catalogo for select to authenticated using (true);
grant select on public.habilidades_catalogo to authenticated;

insert into public.habilidades_catalogo (id, classe, ordem, nome, descricao, bonus, req, ativo) values
 ('instinto','Treinador',1,'Instinto de Combate','+2% de dano dos seus Pokémon por rank (em breve).',2,'[]',false),
 ('recompensa','Treinador',2,'Recompensa de Batalha','+10% de dinheiro ganho em batalhas por rank (em breve).',10,'[]',false),
 ('mestre_treino','Treinador',3,'Mestre de Treino','Treinar rende +8 de experiência por rank.',8,'[]',true),
 ('resistencia','Treinador',4,'Resistência','+2 de PA máximo por rank (em breve).',2,'[]',false),
 ('foco','Treinador',5,'Foco','+3% de precisão nos golpes por rank (em breve).',3,'[]',false),
 ('cura_rapida','Treinador',6,'Cura Rápida','Cura 5% de HP por rank após cada vitória (em breve).',5,'[]',false),
 ('lideranca','Treinador',7,'Liderança','+1 de amizade ganha ao Cuidar por rank (em breve).',1,'[]',false),
 ('provocacao','Treinador',8,'Provocação','+3 de PA máximo por rank (em breve).',3,'[]',false),
 ('veterano','Treinador',9,'Veterano','+5% de experiência de batalha por rank (em breve).',5,'[]',false),
 ('campeao','Treinador',10,'Campeão','+3% em todos os atributos dos Pokémon (em breve).',3,'[{"id":"instinto","rank":3},{"id":"resistencia","rank":3}]',false),
 ('afeto','Criador',1,'Afeto','Cuidar pode ser usado +1 vez por dia por rank em cada Pokémon.',1,'[]',true),
 ('mao_amiga','Criador',2,'Mão Amiga','Cuidar também cura 10% de HP por rank (em breve).',10,'[]',false),
 ('olho_brilhante','Criador',3,'Olho Brilhante','+0,1% de chance de brilhante por rank (em breve).',0.1,'[]',false),
 ('ovos','Criador',4,'Ovos','Libera o sistema de ovos quando ele existir (em breve).',1,'[]',false),
 ('alimentador','Criador',5,'Alimentador','Cuidar rende +5 de experiência ao Pokémon por rank.',5,'[]',true),
 ('laco','Criador',6,'Laço Forte','Pokémon com amizade alta ganham mais experiência (em breve).',2,'[]',false),
 ('espaco','Criador',7,'Espaço Extra','+5 espaços de caixa por rank (em breve).',5,'[]',false),
 ('treino_intenso','Criador',8,'Treino Intenso','Treinar rende +10% de experiência por rank.',10,'[]',true),
 ('banco_dados','Criador',9,'Banco de Dados','Mostra mais informações dos Pokémon capturados (em breve).',1,'[]',false),
 ('criador_mestre','Criador',10,'Criador Mestre','Treinar e Cuidar custam 0 PA a cada 3 usos (em breve).',1,'[{"id":"afeto","rank":3},{"id":"laco","rank":3}]',false),
 ('olhar_atento','Pesquisador',1,'Olhar Atento','Pesquisar rende +10 de experiência de treinador e +₽25 por rank.',10,'[]',true),
 ('exploracao','Pesquisador',2,'Exploração','Explorar rende +25% de recompensa por rank.',25,'[]',true),
 ('rede_pesca','Pesquisador',3,'Rede de Pesca','+10% de chance de pesca bem-sucedida por rank.',10,'[]',true),
 ('captura','Pesquisador',4,'Captura Eficiente','+3% de chance de captura por rank (em breve).',3,'[]',false),
 ('mochila','Pesquisador',5,'Mochila Leve','+10 de limite por item na mochila por rank (em breve).',10,'[]',false),
 ('mapa_mental','Pesquisador',6,'Mapa Mental','Viagens rápidas mais baratas (em breve).',1,'[]',false),
 ('economia','Pesquisador',7,'Economia','Lojas cobram 3% menos por rank.',3,'[]',true),
 ('pokedex_viva','Pesquisador',8,'Pokédex Viva','Novas espécies capturadas rendem +5 de experiência de treinador por rank.',5,'[]',true),
 ('intuicao','Pesquisador',9,'Intuição','+3 de PA máximo por rank (em breve).',3,'[]',false),
 ('cientista','Pesquisador',10,'Cientista','Pesquisar e Explorar rendem o dobro às vezes (em breve).',1,'[{"id":"olhar_atento","rank":3},{"id":"exploracao","rank":3}]',false)
on conflict (id) do update set classe = excluded.classe, ordem = excluded.ordem, nome = excluded.nome, descricao = excluded.descricao,
  bonus = excluded.bonus, req = excluded.req, ativo = excluded.ativo;

insert into public.config (chave, valor) values ('nivel_treino_max', '30'::jsonb), ('mapas_pesca', '["costa1","costa2","argila","reserva","vale"]'::jsonb)
on conflict (chave) do nothing;

-- ---------- núcleo ----------
create or replace function public._rank(p_j uuid, p_hab text) returns int language sql stable security definer set search_path = public as $$
  select coalesce((select (habilidades ->> p_hab)::int from public.jogadores where id = p_j), 0) $$;
create or replace function public._bonus(p_j uuid, p_hab text) returns numeric language sql stable security definer set search_path = public as $$
  select public._rank(p_j, p_hab) * coalesce((select bonus from public.habilidades_catalogo where id = p_hab and ativo), 0) $$;
create or replace function public._xp_para_nivel(n int) returns int language sql immutable as $$ select 25 * n * (n - 1) $$;
create or replace function public._nivel_treino(p_xp int) returns int language plpgsql stable security definer set search_path = public as $$
declare mx int := public._cfg_int('nivel_treino_max', 30); n int := 1;
begin while n < mx and p_xp >= public._xp_para_nivel(n + 1) loop n := n + 1; end loop; return n; end $$;
create or replace function public._ganhar_xp_treino(p_j uuid, p_qtd int) returns void language sql security definer set search_path = public as $$
  update public.jogadores set xp_treino = xp_treino + greatest(0, p_qtd) where id = p_j $$;
create or replace function public._pontos_total(p_j uuid) returns int language sql stable security definer set search_path = public as $$
  select (public._nivel_treino(coalesce((select xp_treino from public.jogadores where id = p_j), 0)) - 1)
       + coalesce((select floor(sum(n) / 5)::int from (select nivel::int as n from public.pokemons where dono = p_j order by nivel desc limit 6) s), 0) $$;
create or replace function public._pontos_gastos(p_j uuid) returns int language sql stable security definer set search_path = public as $$
  select coalesce((select sum(case when r >= 1 then 1 else 0 end + case when r >= 2 then 2 else 0 end + case when r >= 3 then 3 else 0 end)
                     from (select value::int as r from public.jogadores, jsonb_each_text(habilidades) where id = p_j) s), 0)::int $$;
revoke all on function public._rank(uuid, text), public._bonus(uuid, text), public._nivel_treino(int), public._ganhar_xp_treino(uuid, int),
  public._pontos_total(uuid), public._pontos_gastos(uuid) from public, anon, authenticated;

create or replace function public.estado_treino() returns jsonb language plpgsql security definer stable set search_path = public as $$
declare j public.jogadores; nv int;
begin
  select * into j from public.jogadores where id = auth.uid();
  if not found then raise exception 'Crie seu personagem primeiro.'; end if;
  nv := public._nivel_treino(j.xp_treino);
  return jsonb_build_object('classe', j.classe_rpg, 'nivel', nv, 'xp', j.xp_treino, 'xp_atual_nivel', public._xp_para_nivel(nv),
    'xp_prox', case when nv >= public._cfg_int('nivel_treino_max', 30) then null else public._xp_para_nivel(nv + 1) end,
    'pontos_total', public._pontos_total(j.id), 'pontos_gastos', public._pontos_gastos(j.id), 'habilidades', j.habilidades,
    'pesquisadas', (select count(*) from public.pokedex where jogador = j.id and pesquisado));
end $$;
grant execute on function public.estado_treino() to authenticated;

create or replace function public.escolher_classe(p_classe text) returns void language plpgsql security definer set search_path = public as $$
begin
  if p_classe not in ('Treinador','Criador','Pesquisador') then raise exception 'Classe inválida.'; end if;
  if exists (select 1 from public.jogadores where id = auth.uid() and classe_rpg is not null) then raise exception 'Você já escolheu uma classe. Peça ao Mestre para redefinir.'; end if;
  update public.jogadores set classe_rpg = p_classe where id = auth.uid();
end $$;
grant execute on function public.escolher_classe(text) to authenticated;

create or replace function public.comprar_habilidade(p_hab text) returns jsonb language plpgsql security definer set search_path = public as $$
declare j public.jogadores; h public.habilidades_catalogo; r int; custo int; q jsonb;
begin
  select * into j from public.jogadores where id = auth.uid() for update;
  if not found then raise exception 'Crie seu personagem primeiro.'; end if;
  select * into h from public.habilidades_catalogo where id = p_hab;
  if not found then raise exception 'Habilidade inexistente.'; end if;
  if j.classe_rpg is null or h.classe <> j.classe_rpg then raise exception 'Esta habilidade é de outra classe.'; end if;
  r := coalesce((j.habilidades ->> p_hab)::int, 0);
  if r >= 3 then raise exception 'Habilidade já está no nível máximo.'; end if;
  for q in select * from jsonb_array_elements(h.req) loop
    if coalesce((j.habilidades ->> (q ->> 'id'))::int, 0) < (q ->> 'rank')::int then
      raise exception 'Requisito: % no rank %.', (select nome from public.habilidades_catalogo where id = q ->> 'id'), q ->> 'rank';
    end if;
  end loop;
  custo := r + 1;
  if public._pontos_total(j.id) - public._pontos_gastos(j.id) < custo then raise exception 'Pontos insuficientes (custa %).', custo; end if;
  update public.jogadores set habilidades = habilidades || jsonb_build_object(p_hab, r + 1) where id = j.id;
  return public.estado_treino();
end $$;
grant execute on function public.comprar_habilidade(text) to authenticated;

-- XP de treinador automático: vencer treinador e registrar nova espécie capturada
create or replace function public._tg_xp_vencido() returns trigger language plpgsql security definer set search_path = public as $$
begin perform public._ganhar_xp_treino(new.jogador, 40); return new; end $$;
drop trigger if exists tg_xp_vencido on public.treinadores_vencidos;
create trigger tg_xp_vencido after insert on public.treinadores_vencidos for each row execute function public._tg_xp_vencido();
create or replace function public._tg_xp_dex() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.capturado and (tg_op = 'INSERT' or not old.capturado) then
    perform public._ganhar_xp_treino(new.jogador, 30 + floor(public._bonus(new.jogador, 'pokedex_viva'))::int);
  end if;
  return new;
end $$;
drop trigger if exists tg_xp_dex on public.pokedex;
create trigger tg_xp_dex after insert or update of capturado on public.pokedex for each row execute function public._tg_xp_dex();

-- ---------- ações de PA ----------
create or replace function public._gastar_pa(p_j uuid) returns public.jogadores language plpgsql security definer set search_path = public as $$
declare j public.jogadores;
begin
  select * into j from public.jogadores where id = p_j for update;
  if not found then raise exception 'Crie seu personagem primeiro.'; end if;
  if exists (select 1 from public.batalhas where jogador = p_j and estado = 'ativa') then raise exception 'Termine a batalha primeiro.'; end if;
  if j.pa < 1 and public._ev('pa_gratis', 0) = 0 then raise exception 'PA insuficiente: esta ação custa 1 PA.'; end if;
  update public.jogadores set pa = pa - case when public._ev('pa_gratis', 0) > 0 then 0 else 1 end where id = p_j returning * into j;
  return j;
end $$;
create or replace function public._uso_dia(p_j uuid, p_chave text, p_max int) returns void language plpgsql security definer set search_path = public as $$
declare n int;
begin
  insert into public.acoes_dia (jogador, chave, n) values (p_j, p_chave, 1) on conflict (jogador, dia, chave) do update set n = public.acoes_dia.n + 1 returning acoes_dia.n into n;
  if n > p_max then raise exception 'Limite diário desta ação atingido.'; end if;
end $$;
revoke all on function public._gastar_pa(uuid), public._uso_dia(uuid, text, int) from public, anon, authenticated;

create or replace function public.acao_treinar(p_pokemon uuid) returns jsonb language plpgsql security definer set search_path = public as $$
declare pk public.pokemons; ev jsonb; xp int; ant int;
begin
  select * into pk from public.pokemons where id = p_pokemon and dono = auth.uid();
  if not found then raise exception 'Pokémon não encontrado.'; end if;
  perform public._gastar_pa(auth.uid());
  xp := floor((25 + public._bonus(auth.uid(), 'mestre_treino')) * (1 + public._bonus(auth.uid(), 'treino_intenso') / 100.0))::int;
  ant := pk.nivel;
  ev := public._dar_exp(pk, jsonb_build_object('exp_base', 7, 'nivel', xp), '[]'::jsonb);  -- _dar_exp aplica o multiplicador de evento
  return jsonb_build_object('eventos', ev, 'pa', (select pa from public.jogadores where id = auth.uid()));
end $$;
grant execute on function public.acao_treinar(uuid) to authenticated;

create or replace function public.acao_cuidar(p_pokemon uuid) returns jsonb language plpgsql security definer set search_path = public as $$
declare pk public.pokemons; ev jsonb := '[]'::jsonb; xp int;
begin
  select * into pk from public.pokemons where id = p_pokemon and dono = auth.uid();
  if not found then raise exception 'Pokémon não encontrado.'; end if;
  perform public._uso_dia(auth.uid(), 'cuidar:' || p_pokemon, 3 + floor(public._bonus(auth.uid(), 'afeto'))::int);
  perform public._gastar_pa(auth.uid());
  update public.pokemons set amizade = least(255, amizade + 1) where id = p_pokemon;
  xp := floor(public._bonus(auth.uid(), 'alimentador'))::int;
  if xp > 0 then ev := public._dar_exp(pk, jsonb_build_object('exp_base', 7, 'nivel', xp), '[]'::jsonb); end if;
  return jsonb_build_object('amizade', least(255, pk.amizade + 1), 'eventos', ev, 'pa', (select pa from public.jogadores where id = auth.uid()));
end $$;
grant execute on function public.acao_cuidar(uuid) to authenticated;

create or replace function public.acao_pesquisar(p_especie int) returns jsonb language plpgsql security definer set search_path = public as $$
declare n int; xp int; din int; extra int := 0;
begin
  if not exists (select 1 from public.pokedex where jogador = auth.uid() and especie_id = p_especie) then raise exception 'Você ainda não viu esta espécie.'; end if;
  if exists (select 1 from public.pokedex where jogador = auth.uid() and especie_id = p_especie and pesquisado) then raise exception 'Você já pesquisou esta espécie.'; end if;
  perform public._gastar_pa(auth.uid());
  update public.pokedex set pesquisado = true where jogador = auth.uid() and especie_id = p_especie;
  select count(*) into n from public.pokedex where jogador = auth.uid() and pesquisado;
  xp := 40 + floor(public._bonus(auth.uid(), 'olhar_atento'))::int;
  din := 150 + floor(public._rank(auth.uid(), 'olhar_atento') * 25)::int;
  if n % 10 = 0 then extra := 500; end if;
  perform public._ganhar_xp_treino(auth.uid(), xp);
  update public.jogadores set dinheiro = dinheiro + din + extra where id = auth.uid();
  return jsonb_build_object('xp', xp, 'dinheiro', din + extra, 'pesquisadas', n, 'bonus', extra > 0);
end $$;
grant execute on function public.acao_pesquisar(int) to authenticated;

create or replace function public.acao_explorar() returns jsonb language plpgsql security definer set search_path = public as $$
declare j public.jogadores; r numeric := random(); mult numeric; din int; item text; res jsonb;
begin
  select * into j from public.jogadores where id = auth.uid();
  if not found then raise exception 'Crie seu personagem primeiro.'; end if;
  if j.mapa_id in ('lab') then raise exception 'Não há o que explorar aqui.'; end if;
  perform public._uso_dia(j.id, 'explorar:' || j.mapa_id || ':' || j.x || ':' || j.y, 1);
  perform public._gastar_pa(j.id);
  mult := 1 + public._bonus(j.id, 'exploracao') / 100.0;
  if r < 0.6 then
    din := floor((100 + random() * 300) * mult)::int;
    update public.jogadores set dinheiro = dinheiro + din where id = j.id;
    res := jsonb_build_object('tipo', 'dinheiro', 'valor', din);
  else
    item := case when r < 0.85 then 'potion' else 'poke-ball' end;
    if not exists (select 1 from public.itens where slug = item) then item := 'poke-ball'; end if;
    insert into public.inventario (jogador, item, qtd) values (j.id, item, greatest(1, round(mult)::int))
    on conflict (jogador, item) do update set qtd = public.inventario.qtd + greatest(1, round(mult)::int);
    res := jsonb_build_object('tipo', 'item', 'item', item, 'qtd', greatest(1, round(mult)::int));
  end if;
  perform public._ganhar_xp_treino(j.id, 10);
  return res;
end $$;
grant execute on function public.acao_explorar() to authenticated;

create or replace function public.acao_pescar() returns jsonb language plpgsql security definer set search_path = public as $$
declare j public.jogadores; chance numeric; item text; din int;
begin
  select * into j from public.jogadores where id = auth.uid();
  if not found then raise exception 'Crie seu personagem primeiro.'; end if;
  if not exists (select 1 from public.config where chave = 'mapas_pesca' and valor ? j.mapa_id) then raise exception 'Não há onde pescar por aqui. Procure a costa ou um rio.'; end if;
  perform public._gastar_pa(j.id);
  chance := 0.15 + public._bonus(j.id, 'rede_pesca') / 100.0;
  if random() >= chance then return jsonb_build_object('tipo', 'nada'); end if;
  item := (array['potion', 'poke-ball', 'great-ball'])[1 + floor(random() * 3)::int];
  if not exists (select 1 from public.itens where slug = item) then din := 200; update public.jogadores set dinheiro = dinheiro + din where id = j.id; return jsonb_build_object('tipo', 'dinheiro', 'valor', din); end if;
  insert into public.inventario (jogador, item, qtd) values (j.id, item, 1) on conflict (jogador, item) do update set qtd = public.inventario.qtd + 1;
  perform public._ganhar_xp_treino(j.id, 10);
  return jsonb_build_object('tipo', 'item', 'item', item, 'qtd', 1);
end $$;
grant execute on function public.acao_pescar() to authenticated;

create or replace function public.acao_barganhar() returns jsonb language plpgsql security definer set search_path = public as $$
declare ok boolean;
begin
  perform public._gastar_pa(auth.uid());
  ok := random() < 0.4;
  update public.jogadores set desconto_barganha = case when ok then 10 else desconto_barganha end where id = auth.uid();
  return jsonb_build_object('ok', ok);
end $$;
grant execute on function public.acao_barganhar() to authenticated;

-- compras: desconto de evento + Economia + barganha (consumida na compra)
create or replace function public.comprar_item(p_poi text, p_item text, p_qtd int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_j public.jogadores; v_p jsonb; v_e jsonb; v_total int; v_desc numeric;
begin
  if auth.uid() is null then raise exception 'Faça login primeiro.'; end if;
  if p_qtd is null or p_qtd < 1 or p_qtd > 99 then raise exception 'Quantidade inválida.'; end if;
  select * into v_j from public.jogadores where id = auth.uid() for update;
  if not found then raise exception 'Crie seu personagem primeiro.'; end if;
  v_p := public._poi_do_jogador(v_j, p_poi);
  if v_p is null or v_p->>'acao' <> 'loja' then raise exception 'Chegue ao balcão da loja.'; end if;
  select e into v_e from jsonb_array_elements(v_p->'estoque') e where e->>'item' = p_item limit 1;
  if v_e is null then raise exception 'Esta loja não vende isso.'; end if;
  v_desc := least(90, public._ev('loja_desconto', 0) + public._bonus(v_j.id, 'economia') + v_j.desconto_barganha);
  v_total := floor((v_e->>'preco')::int * p_qtd * (1 - v_desc / 100.0));
  if v_j.dinheiro < v_total then raise exception 'Dinheiro insuficiente (precisa de %).', v_total; end if;
  update public.jogadores set dinheiro = dinheiro - v_total, desconto_barganha = 0 where id = v_j.id;
  insert into public.inventario (jogador, item, qtd) values (v_j.id, p_item, p_qtd)
  on conflict (jogador, item) do update set qtd = public.inventario.qtd + p_qtd;
  return jsonb_build_object('item', p_item, 'qtd', p_qtd, 'total', v_total, 'dinheiro', v_j.dinheiro - v_total);
end $$;
grant execute on function public.comprar_item(text, text, int) to authenticated;
