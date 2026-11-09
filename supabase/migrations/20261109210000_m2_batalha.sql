-- M2: Pokémon, encontros na grama, batalha por turnos e captura. Tudo decidido no servidor.
-- Dados de referência (espécies, golpes, tipos, naturezas, encontros) entram por importar_dados (Mestre).

create table public.especies (
  id int primary key, nome text not null, tipos text[] not null,
  hp smallint not null, atk smallint not null, def smallint not null, spa smallint not null, spd smallint not null, spe smallint not null,
  taxa_captura smallint not null default 45, exp_base smallint not null default 50, arco smallint not null default 1
);
create table public.golpes (
  id int primary key, slug text unique not null, nome text not null, tipo text not null, categoria text not null,
  poder smallint, precisao smallint, pp smallint not null default 10, prioridade smallint not null default 0, arco smallint not null default 1
);
create table public.aprende (
  especie_id int not null references public.especies (id) on delete cascade,
  golpe_id int not null references public.golpes (id) on delete cascade,
  nivel smallint not null,
  primary key (especie_id, golpe_id, nivel)
);
create table public.eficacia (atacante text not null, defensor text not null, mult numeric not null, primary key (atacante, defensor));
create table public.naturezas (nome text primary key, aumenta text, diminui text);
create table public.encontros (
  mapa_id text not null references public.mapas (id) on delete cascade,
  especie_id int not null references public.especies (id) on delete cascade,
  peso int not null check (peso > 0), nivel_min smallint not null, nivel_max smallint not null,
  primary key (mapa_id, especie_id)
);
create table public.itens (slug text primary key, nome text not null, categoria text, efeito text, arco smallint not null default 1);

create table public.pokemons (
  id uuid primary key default gen_random_uuid(),
  dono uuid not null references public.jogadores (id) on delete cascade,
  especie_id int not null references public.especies (id),
  apelido text,
  nivel smallint not null check (nivel between 1 and 100),
  exp int not null default 0,
  natureza text not null default 'hardy',
  iv_hp smallint not null, iv_atk smallint not null, iv_def smallint not null, iv_spa smallint not null, iv_spd smallint not null, iv_spe smallint not null,
  hp_max int not null, atk int not null, def int not null, spa int not null, spd int not null, spe int not null,
  hp_atual int not null,
  golpes jsonb not null default '[]'::jsonb,       -- [{id, pp}]
  posicao smallint check (posicao between 1 and 6),  -- slot do time; null = box
  criado_em timestamptz not null default now()
);
create unique index pokemons_slot_unico on public.pokemons (dono, posicao) where posicao is not null;
create index pokemons_dono on public.pokemons (dono);

create table public.inventario (
  jogador uuid not null references public.jogadores (id) on delete cascade,
  item text not null references public.itens (slug),
  qtd int not null check (qtd >= 0),
  primary key (jogador, item)
);
create table public.pokedex (
  jogador uuid not null references public.jogadores (id) on delete cascade,
  especie_id int not null references public.especies (id),
  capturado boolean not null default false,
  primary key (jogador, especie_id)
);
create table public.batalhas (
  id uuid primary key default gen_random_uuid(),
  jogador uuid not null references public.jogadores (id) on delete cascade,
  estado text not null default 'ativa' check (estado in ('ativa','vitoria','derrota','fuga','captura')),
  selvagem jsonb not null,
  ativo uuid references public.pokemons (id) on delete set null,
  trocar boolean not null default false,
  turno int not null default 1,
  criado_em timestamptz not null default now()
);
create unique index batalha_ativa_unica on public.batalhas (jogador) where estado = 'ativa';

alter table public.especies enable row level security;  alter table public.golpes enable row level security;
alter table public.aprende enable row level security;   alter table public.eficacia enable row level security;
alter table public.naturezas enable row level security; alter table public.encontros enable row level security;
alter table public.itens enable row level security;     alter table public.pokemons enable row level security;
alter table public.inventario enable row level security; alter table public.pokedex enable row level security;
alter table public.batalhas enable row level security;

create policy "especies_leitura" on public.especies for select to authenticated using (true);
create policy "golpes_leitura" on public.golpes for select to authenticated using (true);
create policy "aprende_leitura" on public.aprende for select to authenticated using (true);
create policy "eficacia_leitura" on public.eficacia for select to authenticated using (true);
create policy "naturezas_leitura" on public.naturezas for select to authenticated using (true);
create policy "encontros_leitura" on public.encontros for select to authenticated using (true);
create policy "itens_leitura" on public.itens for select to authenticated using (true);
create policy "pokemons_dono" on public.pokemons for select to authenticated using (dono = auth.uid() or public.eh_mestre());
create policy "inventario_dono" on public.inventario for select to authenticated using (jogador = auth.uid() or public.eh_mestre());
create policy "pokedex_dono" on public.pokedex for select to authenticated using (jogador = auth.uid() or public.eh_mestre());
create policy "batalhas_dono" on public.batalhas for select to authenticated using (jogador = auth.uid());
grant select on public.especies, public.golpes, public.aprende, public.eficacia, public.naturezas, public.encontros, public.itens,
  public.pokemons, public.inventario, public.pokedex, public.batalhas to authenticated;

-- o Mestre envia sprites para o bucket privado
drop policy if exists "sprites_envio_mestre" on storage.objects;
create policy "sprites_envio_mestre" on storage.objects for insert to authenticated with check (bucket_id = 'sprites' and public.eh_mestre());
drop policy if exists "sprites_troca_mestre" on storage.objects;
create policy "sprites_troca_mestre" on storage.objects for update to authenticated using (bucket_id = 'sprites' and public.eh_mestre());

-- ===================== utilidades =====================
create or replace function public.calc_hp(b int, iv int, n int) returns int language sql immutable as
$$ select (floor((2*b+iv)*n/100.0) + n + 10)::int $$;
create or replace function public.calc_stat(b int, iv int, n int, nat numeric) returns int language sql immutable as
$$ select floor((floor((2*b+iv)*n/100.0) + 5) * nat)::int $$;
create or replace function public.mult_nat(p_nat text, p_stat text) returns numeric language sql stable as
$$ select case when (select aumenta from public.naturezas where nome = p_nat) = p_stat then 1.1
               when (select diminui from public.naturezas where nome = p_nat) = p_stat then 0.9 else 1.0 end $$;
create or replace function public.exp_para(n int) returns int language sql immutable as $$ select (n*n*n)::int $$;

create or replace function public.mult_tipo(p_atk text, p_def text[]) returns numeric language sql stable as
$$ select coalesce(exp(sum(ln(greatest(coalesce((select mult from public.eficacia where atacante = p_atk and defensor = d), 1), 0.0001)))), 1)
     * case when exists (select 1 from unnest(p_def) d2 where coalesce((select mult from public.eficacia where atacante = p_atk and defensor = d2), 1) = 0) then 0 else 1 end
   from unnest(p_def) d $$;

-- golpes iniciais: os 4 últimos que causam dano e são aprendidos até o nível
create or replace function public.golpes_do_nivel(p_esp int, p_nivel int) returns jsonb language sql stable as
$$ select coalesce(jsonb_agg(jsonb_build_object('id', t.golpe_id, 'pp', t.pp)), '[]'::jsonb) from (
     select a.golpe_id, g.pp, row_number() over (order by a.nivel desc, a.golpe_id) rn
       from public.aprende a join public.golpes g on g.id = a.golpe_id
      where a.especie_id = p_esp and a.nivel <= p_nivel and coalesce(g.poder, 0) > 0
      group by a.golpe_id, g.pp, a.nivel
   ) t where t.rn <= 4 $$;

-- cria um Pokémon (sem escolher slot); stats calculados
create or replace function public._novo_pokemon(p_dono uuid, p_esp int, p_nivel int, p_golpes jsonb default null)
returns public.pokemons language plpgsql security definer set search_path = public as $$
declare
  e public.especies; nat text; v public.pokemons;
  ih int := floor(random()*32); ia int := floor(random()*32); id_ int := floor(random()*32);
  isa int := floor(random()*32); isd int := floor(random()*32); ise int := floor(random()*32);
  slot int;
begin
  select * into e from public.especies where id = p_esp;
  if not found then raise exception 'Espécie desconhecida.'; end if;
  select nome into nat from public.naturezas order by random() limit 1;
  nat := coalesce(nat, 'hardy');
  select min(s) into slot from generate_series(1,6) s where not exists (select 1 from public.pokemons where dono = p_dono and posicao = s);
  insert into public.pokemons (dono, especie_id, nivel, exp, natureza, iv_hp, iv_atk, iv_def, iv_spa, iv_spd, iv_spe,
      hp_max, atk, def, spa, spd, spe, hp_atual, golpes, posicao)
  values (p_dono, p_esp, p_nivel, public.exp_para(p_nivel), nat, ih, ia, id_, isa, isd, ise,
      public.calc_hp(e.hp, ih, p_nivel),
      public.calc_stat(e.atk, ia, p_nivel, public.mult_nat(nat, 'attack')),
      public.calc_stat(e.def, id_, p_nivel, public.mult_nat(nat, 'defense')),
      public.calc_stat(e.spa, isa, p_nivel, public.mult_nat(nat, 'sp_attack')),
      public.calc_stat(e.spd, isd, p_nivel, public.mult_nat(nat, 'sp_defense')),
      public.calc_stat(e.spe, ise, p_nivel, public.mult_nat(nat, 'speed')),
      public.calc_hp(e.hp, ih, p_nivel),
      coalesce(p_golpes, public.golpes_do_nivel(p_esp, p_nivel)), slot)
  returning * into v;
  insert into public.pokedex (jogador, especie_id, capturado) values (p_dono, p_esp, true)
  on conflict (jogador, especie_id) do update set capturado = true;
  return v;
end $$;

-- ===================== importação (Mestre) =====================
create or replace function public.importar_dados(p_tabela text, p_linhas jsonb)
returns int language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if not public.eh_mestre() then raise exception 'Só o Mestre importa dados.'; end if;
  if jsonb_typeof(p_linhas) <> 'array' then raise exception 'Formato inválido.'; end if;
  if p_tabela = 'especies' then
    insert into public.especies select * from jsonb_populate_recordset(null::public.especies, p_linhas)
    on conflict (id) do update set nome=excluded.nome, tipos=excluded.tipos, hp=excluded.hp, atk=excluded.atk, def=excluded.def,
      spa=excluded.spa, spd=excluded.spd, spe=excluded.spe, taxa_captura=excluded.taxa_captura, exp_base=excluded.exp_base, arco=excluded.arco;
  elsif p_tabela = 'golpes' then
    insert into public.golpes select * from jsonb_populate_recordset(null::public.golpes, p_linhas)
    on conflict (id) do update set slug=excluded.slug, nome=excluded.nome, tipo=excluded.tipo, categoria=excluded.categoria, poder=excluded.poder,
      precisao=excluded.precisao, pp=excluded.pp, prioridade=excluded.prioridade, arco=excluded.arco;
  elsif p_tabela = 'aprende' then
    insert into public.aprende select * from jsonb_populate_recordset(null::public.aprende, p_linhas) on conflict do nothing;
  elsif p_tabela = 'eficacia' then
    insert into public.eficacia select * from jsonb_populate_recordset(null::public.eficacia, p_linhas)
    on conflict (atacante, defensor) do update set mult = excluded.mult;
  elsif p_tabela = 'naturezas' then
    insert into public.naturezas select * from jsonb_populate_recordset(null::public.naturezas, p_linhas)
    on conflict (nome) do update set aumenta = excluded.aumenta, diminui = excluded.diminui;
  elsif p_tabela = 'mapas' then
    insert into public.mapas (id, nome, largura, altura, spawn_x, spawn_y, tipo, solido, grama, portais, pois)
    select id, nome, largura, altura, spawn_x, spawn_y, coalesce(tipo, 'andavel'), solido, grama, coalesce(portais, '[]'::jsonb), coalesce(pois, '[]'::jsonb)
      from jsonb_populate_recordset(null::public.mapas, p_linhas)
    on conflict (id) do update set nome = excluded.nome, largura = excluded.largura, altura = excluded.altura, spawn_x = excluded.spawn_x,
      spawn_y = excluded.spawn_y, tipo = excluded.tipo, solido = excluded.solido, grama = excluded.grama, portais = excluded.portais, pois = excluded.pois;
  elsif p_tabela = 'itens' then
    insert into public.itens select * from jsonb_populate_recordset(null::public.itens, p_linhas)
    on conflict (slug) do update set nome = excluded.nome, categoria = excluded.categoria, efeito = excluded.efeito, arco = excluded.arco;
  elsif p_tabela = 'encontros' then
    insert into public.encontros select * from jsonb_populate_recordset(null::public.encontros, p_linhas)
    on conflict (mapa_id, especie_id) do update set peso = excluded.peso, nivel_min = excluded.nivel_min, nivel_max = excluded.nivel_max;
  else
    raise exception 'Tabela não permitida.';
  end if;
  get diagnostics n = row_count;
  insert into public.auditoria (ator, acao, detalhe) values (auth.uid(), 'importar_dados', jsonb_build_object('tabela', p_tabela, 'linhas', n));
  return n;
end $$;

-- ===================== ações do jogo =====================
create or replace function public._poi_aqui(p_j public.jogadores, p_tipo text) returns boolean language sql stable as
$$ select exists (select 1 from public.mapas m, jsonb_array_elements(m.pois) p
    where m.id = p_j.mapa_id and p->>'tipo' = p_tipo and (p->>'x')::int = p_j.x and (p->>'y')::int = p_j.y) $$;

create or replace function public.escolher_inicial(p_especie int)
returns public.pokemons language plpgsql security definer set search_path = public as $$
declare v_j public.jogadores; v public.pokemons;
begin
  if auth.uid() is null then raise exception 'Faça login primeiro.'; end if;
  select * into v_j from public.jogadores where id = auth.uid() for update;
  if not found then raise exception 'Crie seu personagem primeiro.'; end if;
  if not public._poi_aqui(v_j, 'lab') then raise exception 'Vá até o laboratório do Professor Carvalho.'; end if;
  if p_especie not in (1, 4, 7) then raise exception 'Escolha Bulbasaur, Charmander ou Squirtle.'; end if;
  if exists (select 1 from public.pokemons where dono = v_j.id) then raise exception 'Você já tem um Pokémon.'; end if;
  v := public._novo_pokemon(v_j.id, p_especie, 5);
  insert into public.inventario (jogador, item, qtd) values (v_j.id, 'poke-ball', 10)
  on conflict (jogador, item) do update set qtd = public.inventario.qtd + 10;
  insert into public.auditoria (ator, acao, detalhe) values (v_j.id, 'escolher_inicial', jsonb_build_object('especie', p_especie));
  return v;
end $$;

create or replace function public.curar_time()
returns int language plpgsql security definer set search_path = public as $$
declare v_j public.jogadores; n int;
begin
  if auth.uid() is null then raise exception 'Faça login primeiro.'; end if;
  select * into v_j from public.jogadores where id = auth.uid() for update;
  if not (public._poi_aqui(v_j, 'centro') or public._poi_aqui(v_j, 'casa_jogador')) then
    raise exception 'Só dá para curar no Centro Pokémon ou na sua casa.';
  end if;
  if exists (select 1 from public.batalhas where jogador = v_j.id and estado = 'ativa') then raise exception 'Termine a batalha primeiro.'; end if;
  update public.pokemons p set hp_atual = hp_max,
    golpes = coalesce((select jsonb_agg(jsonb_build_object('id', (g->>'id')::int, 'pp', (select pp from public.golpes where id = (g->>'id')::int)))
                         from jsonb_array_elements(p.golpes) g), '[]'::jsonb)
   where dono = v_j.id;
  get diagnostics n = row_count;
  return n;
end $$;

-- monta o objeto "lado" (jsonb) de um Pokémon para a batalha
create or replace function public._selvagem(p_esp int, p_nivel int) returns jsonb language plpgsql set search_path = public as $$
declare e public.especies; ih int := floor(random()*32); nat text; gj jsonb; mv jsonb := '[]'::jsonb; g public.golpes; x jsonb;
  hpm int;
begin
  select * into e from public.especies where id = p_esp;
  select nome into nat from public.naturezas order by random() limit 1; nat := coalesce(nat, 'hardy');
  gj := public.golpes_do_nivel(p_esp, p_nivel);
  if jsonb_array_length(gj) = 0 then
    select * into g from public.golpes where slug = 'tackle';
    gj := jsonb_build_array(jsonb_build_object('id', g.id, 'pp', g.pp));
  end if;
  for x in select * from jsonb_array_elements(gj) loop
    select * into g from public.golpes where id = (x->>'id')::int;
    mv := mv || jsonb_build_array(jsonb_build_object('id', g.id, 'nome', g.nome, 'tipo', g.tipo, 'categoria', g.categoria,
        'poder', coalesce(g.poder, 0), 'precisao', g.precisao, 'prioridade', g.prioridade, 'pp', g.pp));
  end loop;
  hpm := public.calc_hp(e.hp, ih, p_nivel);
  return jsonb_build_object('especie_id', e.id, 'nome', e.nome, 'nivel', p_nivel, 'tipos', to_jsonb(e.tipos),
    'hp_max', hpm, 'hp', hpm,
    'atk', public.calc_stat(e.atk, floor(random()*32)::int, p_nivel, public.mult_nat(nat, 'attack')),
    'def', public.calc_stat(e.def, floor(random()*32)::int, p_nivel, public.mult_nat(nat, 'defense')),
    'spa', public.calc_stat(e.spa, floor(random()*32)::int, p_nivel, public.mult_nat(nat, 'sp_attack')),
    'spd', public.calc_stat(e.spd, floor(random()*32)::int, p_nivel, public.mult_nat(nat, 'sp_defense')),
    'spe', public.calc_stat(e.spe, floor(random()*32)::int, p_nivel, public.mult_nat(nat, 'speed')),
    'natureza', nat, 'golpes', mv, 'taxa_captura', e.taxa_captura, 'exp_base', e.exp_base);
end $$;

create or replace function public._resultado(p_b uuid, p_ev jsonb) returns jsonb language sql security definer set search_path = public as $$
  select jsonb_build_object('batalha', to_jsonb(b), 'ativo', (select to_jsonb(p) from public.pokemons p where p.id = b.ativo), 'eventos', p_ev)
    from public.batalhas b where b.id = p_b $$;

create or replace function public.procurar_pokemon()
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_j public.jogadores; v_m public.mapas; v_b public.batalhas; v_total int; v_r int; v_acc int := 0; v_e record;
  v_nivel int; v_ativo uuid; v_sel jsonb;
begin
  if auth.uid() is null then raise exception 'Faça login primeiro.'; end if;
  select * into v_j from public.jogadores where id = auth.uid() for update;
  if not found then raise exception 'Crie seu personagem primeiro.'; end if;
  select * into v_b from public.batalhas where jogador = v_j.id and estado = 'ativa';
  if found then return public._resultado(v_b.id, jsonb_build_array(jsonb_build_object('t', 'retomada'))); end if;
  select * into v_m from public.mapas where id = v_j.mapa_id;
  if substr(v_m.grama, v_j.y * v_m.largura + v_j.x + 1, 1) is distinct from '1' then
    raise exception 'Só dá para procurar Pokémon na grama alta.';
  end if;
  select id into v_ativo from public.pokemons where dono = v_j.id and posicao is not null and hp_atual > 0 order by posicao limit 1;
  if v_ativo is null then
    if exists (select 1 from public.pokemons where dono = v_j.id) then raise exception 'Seus Pokémon estão desmaiados. Cure-os no Centro Pokémon ou em casa.';
    else raise exception 'Você ainda não tem Pokémon. Fale com o Professor Carvalho no laboratório.'; end if;
  end if;
  if v_j.pa < 1 then raise exception 'PA insuficiente: procurar Pokémon custa 1 PA.'; end if;
  select coalesce(sum(peso), 0) into v_total from public.encontros where mapa_id = v_j.mapa_id;
  if v_total = 0 then raise exception 'Não há Pokémon selvagens por aqui.'; end if;
  v_r := floor(random() * v_total);
  for v_e in select * from public.encontros where mapa_id = v_j.mapa_id order by especie_id loop
    v_acc := v_acc + v_e.peso;
    if v_r < v_acc then exit; end if;
  end loop;
  v_nivel := v_e.nivel_min + floor(random() * (v_e.nivel_max - v_e.nivel_min + 1));
  v_sel := public._selvagem(v_e.especie_id, v_nivel);
  update public.jogadores set pa = pa - 1 where id = v_j.id;
  insert into public.batalhas (jogador, selvagem, ativo) values (v_j.id, v_sel, v_ativo) returning * into v_b;
  insert into public.pokedex (jogador, especie_id) values (v_j.id, v_e.especie_id) on conflict do nothing;
  return public._resultado(v_b.id, jsonb_build_array(jsonb_build_object('t', 'apareceu', 'nome', v_sel->>'nome', 'nivel', v_nivel)));
end $$;

-- um golpe: atacante/defensor em jsonb (stats), devolve {dano, errou, crit, efic}
create or replace function public._golpe(p_nivel int, p_atk int, p_def int, p_mv jsonb, p_tipos_atk text[], p_tipos_def text[])
returns jsonb language plpgsql set search_path = public as $$
declare poder int := coalesce((p_mv->>'poder')::int, 0); prec int := (p_mv->>'precisao')::int; ef numeric; crit boolean := false;
  base numeric; dano int;
begin
  if prec is not null and floor(random()*100) >= prec then return jsonb_build_object('errou', true); end if;
  ef := public.mult_tipo(p_mv->>'tipo', p_tipos_def);
  if ef = 0 then return jsonb_build_object('dano', 0, 'efic', 0, 'crit', false); end if;
  crit := random() < 1.0/16;
  base := floor(floor(floor(2.0*p_nivel/5 + 2) * poder * greatest(p_atk,1) / greatest(p_def,1)) / 50) + 2;
  if crit then base := base * 1.5; end if;
  base := base * (85 + floor(random()*16)) / 100.0;
  if (p_mv->>'tipo') = any(p_tipos_atk) then base := base * 1.5; end if;
  dano := greatest(1, floor(base * ef))::int;
  return jsonb_build_object('dano', dano, 'efic', ef, 'crit', crit);
end $$;

create or replace function public._dar_exp(p_pk public.pokemons, p_sel jsonb, p_ev jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare ganho int := floor((p_sel->>'exp_base')::int * (p_sel->>'nivel')::int / 7.0); e public.especies; novo public.pokemons := p_pk;
  g record; hpmax_ant int;
begin
  select * into e from public.especies where id = p_pk.especie_id;
  novo.exp := p_pk.exp + ganho;
  p_ev := p_ev || jsonb_build_array(jsonb_build_object('t', 'exp', 'valor', ganho, 'nome', coalesce(p_pk.apelido, e.nome)));
  while novo.nivel < 100 and novo.exp >= public.exp_para(novo.nivel + 1) loop
    novo.nivel := novo.nivel + 1;
    hpmax_ant := novo.hp_max;
    novo.hp_max := public.calc_hp(e.hp, novo.iv_hp, novo.nivel);
    novo.atk := public.calc_stat(e.atk, novo.iv_atk, novo.nivel, public.mult_nat(novo.natureza, 'attack'));
    novo.def := public.calc_stat(e.def, novo.iv_def, novo.nivel, public.mult_nat(novo.natureza, 'defense'));
    novo.spa := public.calc_stat(e.spa, novo.iv_spa, novo.nivel, public.mult_nat(novo.natureza, 'sp_attack'));
    novo.spd := public.calc_stat(e.spd, novo.iv_spd, novo.nivel, public.mult_nat(novo.natureza, 'sp_defense'));
    novo.spe := public.calc_stat(e.spe, novo.iv_spe, novo.nivel, public.mult_nat(novo.natureza, 'speed'));
    novo.hp_atual := novo.hp_atual + (novo.hp_max - hpmax_ant);
    p_ev := p_ev || jsonb_build_array(jsonb_build_object('t', 'nivel', 'nome', coalesce(p_pk.apelido, e.nome), 'nivel', novo.nivel));
    for g in select a.golpe_id, gg.nome, gg.pp from public.aprende a join public.golpes gg on gg.id = a.golpe_id
              where a.especie_id = p_pk.especie_id and a.nivel = novo.nivel and coalesce(gg.poder, 0) > 0 loop
      if jsonb_array_length(novo.golpes) < 4 and not exists (select 1 from jsonb_array_elements(novo.golpes) x where (x->>'id')::int = g.golpe_id) then
        novo.golpes := novo.golpes || jsonb_build_array(jsonb_build_object('id', g.golpe_id, 'pp', g.pp));
        p_ev := p_ev || jsonb_build_array(jsonb_build_object('t', 'aprendeu', 'nome', coalesce(p_pk.apelido, e.nome), 'golpe', g.nome));
      end if;
    end loop;
  end loop;
  update public.pokemons set nivel = novo.nivel, exp = novo.exp, hp_max = novo.hp_max, atk = novo.atk, def = novo.def, spa = novo.spa,
    spd = novo.spd, spe = novo.spe, hp_atual = novo.hp_atual, golpes = novo.golpes where id = p_pk.id;
  return p_ev;
end $$;

-- resolve um ataque (quem: 'jogador' ou 'selvagem')
create or replace function public._turno_ataque(p_quem text, p_b public.batalhas, p_slot int, p_ev jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  pk public.pokemons; sel jsonb := p_b.selvagem; e public.especies; mv jsonb; r jsonb; tipos_j text[]; tipos_s text[]; dano int; nomej text;
  mvs jsonb; idx int; gol public.golpes; hp int;
begin
  select * into pk from public.pokemons where id = p_b.ativo;
  select * into e from public.especies where id = pk.especie_id;
  nomej := coalesce(pk.apelido, e.nome);
  tipos_j := e.tipos;
  select array_agg(x) into tipos_s from jsonb_array_elements_text(sel->'tipos') x;
  if p_quem = 'jogador' then
    mv := pk.golpes -> p_slot;
    select * into gol from public.golpes where id = (mv->>'id')::int;
    p_ev := p_ev || jsonb_build_array(jsonb_build_object('t', 'usou', 'quem', 'jogador', 'nome', nomej, 'golpe', gol.nome, 'tipo', gol.tipo));
    update public.pokemons set golpes = jsonb_set(golpes, array[p_slot::text, 'pp'], to_jsonb(greatest((mv->>'pp')::int - 1, 0))) where id = pk.id;
    r := public._golpe(pk.nivel, case when gol.categoria = 'physical' then pk.atk else pk.spa end,
                       case when gol.categoria = 'physical' then (sel->>'def')::int else (sel->>'spd')::int end,
                       jsonb_build_object('poder', gol.poder, 'precisao', gol.precisao, 'tipo', gol.tipo), tipos_j, tipos_s);
    if (r->>'errou')::boolean is true then
      p_ev := p_ev || jsonb_build_array(jsonb_build_object('t', 'errou', 'quem', 'jogador'));
    else
      dano := (r->>'dano')::int; hp := greatest((sel->>'hp')::int - dano, 0);
      sel := jsonb_set(sel, '{hp}', to_jsonb(hp));
      p_ev := p_ev || jsonb_build_array(jsonb_build_object('t', 'dano', 'alvo', 'selvagem', 'valor', dano, 'hp', hp, 'hp_max', (sel->>'hp_max')::int,
              'efic', (r->>'efic')::numeric, 'crit', (r->>'crit')::boolean));
    end if;
    update public.batalhas set selvagem = sel where id = p_b.id;
  else
    mvs := sel->'golpes';
    idx := floor(random() * jsonb_array_length(mvs));
    mv := mvs -> idx;
    p_ev := p_ev || jsonb_build_array(jsonb_build_object('t', 'usou', 'quem', 'selvagem', 'nome', sel->>'nome', 'golpe', mv->>'nome', 'tipo', mv->>'tipo'));
    r := public._golpe((sel->>'nivel')::int, case when mv->>'categoria' = 'physical' then (sel->>'atk')::int else (sel->>'spa')::int end,
                       case when mv->>'categoria' = 'physical' then pk.def else pk.spd end, mv, tipos_s, tipos_j);
    if (r->>'errou')::boolean is true then
      p_ev := p_ev || jsonb_build_array(jsonb_build_object('t', 'errou', 'quem', 'selvagem'));
    else
      dano := (r->>'dano')::int; hp := greatest(pk.hp_atual - dano, 0);
      update public.pokemons set hp_atual = hp where id = pk.id;
      p_ev := p_ev || jsonb_build_array(jsonb_build_object('t', 'dano', 'alvo', 'jogador', 'valor', dano, 'hp', hp, 'hp_max', pk.hp_max,
              'efic', (r->>'efic')::numeric, 'crit', (r->>'crit')::boolean));
    end if;
  end if;
  return p_ev;
end $$;

-- depois de um golpe: verifica desmaios, exp, fim de batalha
create or replace function public._fechar_turno(p_id uuid, p_ev jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare b public.batalhas; pk public.pokemons; e public.especies; prox uuid;
begin
  select * into b from public.batalhas where id = p_id for update;
  select * into pk from public.pokemons where id = b.ativo;
  select * into e from public.especies where id = pk.especie_id;
  if (b.selvagem->>'hp')::int <= 0 then
    p_ev := p_ev || jsonb_build_array(jsonb_build_object('t', 'desmaiou', 'alvo', 'selvagem', 'nome', b.selvagem->>'nome'));
    p_ev := public._dar_exp(pk, b.selvagem, p_ev);
    update public.batalhas set estado = 'vitoria' where id = p_id;
    p_ev := p_ev || jsonb_build_array(jsonb_build_object('t', 'fim', 'estado', 'vitoria'));
  elsif pk.hp_atual <= 0 then
    p_ev := p_ev || jsonb_build_array(jsonb_build_object('t', 'desmaiou', 'alvo', 'jogador', 'nome', coalesce(pk.apelido, e.nome)));
    select id into prox from public.pokemons where dono = b.jogador and posicao is not null and hp_atual > 0 order by posicao limit 1;
    if prox is null then
      update public.batalhas set estado = 'derrota' where id = p_id;
      p_ev := p_ev || jsonb_build_array(jsonb_build_object('t', 'fim', 'estado', 'derrota'));
    else
      update public.batalhas set trocar = true where id = p_id;
      p_ev := p_ev || jsonb_build_array(jsonb_build_object('t', 'trocar'));
    end if;
  end if;
  return p_ev;
end $$;

create or replace function public._batalha_do_jogador(p_id uuid) returns public.batalhas language plpgsql security definer set search_path = public as $$
declare b public.batalhas;
begin
  if auth.uid() is null then raise exception 'Faça login primeiro.'; end if;
  select * into b from public.batalhas where id = p_id and jogador = auth.uid() for update;
  if not found then raise exception 'Batalha não encontrada.'; end if;
  if b.estado <> 'ativa' then raise exception 'Essa batalha já terminou.'; end if;
  return b;
end $$;

create or replace function public.batalha_atacar(p_batalha uuid, p_slot int)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  b public.batalhas; pk public.pokemons; ev jsonb := '[]'::jsonb; mv jsonb; pj int; ps int; primeiro text;
  gol public.golpes; sel jsonb;
begin
  b := public._batalha_do_jogador(p_batalha);
  if b.trocar then raise exception 'Escolha outro Pokémon primeiro.'; end if;
  select * into pk from public.pokemons where id = b.ativo;
  mv := pk.golpes -> p_slot;
  if mv is null then raise exception 'Golpe inválido.'; end if;
  if (mv->>'pp')::int <= 0 then raise exception 'Esse golpe está sem PP.'; end if;
  select * into gol from public.golpes where id = (mv->>'id')::int;
  sel := b.selvagem;
  -- ordem: prioridade, depois velocidade (empate: sorteio)
  pj := coalesce(gol.prioridade, 0); ps := 0;
  if pj > ps then primeiro := 'jogador';
  elsif pj < ps then primeiro := 'selvagem';
  elsif pk.spe > (sel->>'spe')::int then primeiro := 'jogador';
  elsif pk.spe < (sel->>'spe')::int then primeiro := 'selvagem';
  else primeiro := case when random() < 0.5 then 'jogador' else 'selvagem' end; end if;

  if primeiro = 'jogador' then
    ev := public._turno_ataque('jogador', b, p_slot, ev);
    select * into b from public.batalhas where id = b.id;
    if (b.selvagem->>'hp')::int > 0 then
      ev := public._turno_ataque('selvagem', b, 0, ev);
    end if;
  else
    ev := public._turno_ataque('selvagem', b, 0, ev);
    select * into pk from public.pokemons where id = b.ativo;
    if pk.hp_atual > 0 then
      select * into b from public.batalhas where id = b.id;
      ev := public._turno_ataque('jogador', b, p_slot, ev);
    end if;
  end if;
  ev := public._fechar_turno(b.id, ev);
  update public.batalhas set turno = turno + 1 where id = b.id and estado = 'ativa';
  return public._resultado(b.id, ev);
end $$;

create or replace function public.batalha_trocar(p_batalha uuid, p_pokemon uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare b public.batalhas; pk public.pokemons; ev jsonb := '[]'::jsonb; e public.especies;
begin
  b := public._batalha_do_jogador(p_batalha);
  select * into pk from public.pokemons where id = p_pokemon and dono = auth.uid() and posicao is not null;
  if not found then raise exception 'Pokémon inválido.'; end if;
  if pk.hp_atual <= 0 then raise exception 'Esse Pokémon está desmaiado.'; end if;
  if pk.id = b.ativo and not b.trocar then raise exception 'Ele já está em campo.'; end if;
  select * into e from public.especies where id = pk.especie_id;
  ev := ev || jsonb_build_array(jsonb_build_object('t', 'troca', 'nome', coalesce(pk.apelido, e.nome)));
  update public.batalhas set ativo = pk.id where id = b.id;
  if not b.trocar then
    select * into b from public.batalhas where id = b.id;
    ev := public._turno_ataque('selvagem', b, 0, ev);
    ev := public._fechar_turno(b.id, ev);
  else
    update public.batalhas set trocar = false where id = b.id;
  end if;
  update public.batalhas set turno = turno + 1 where id = b.id and estado = 'ativa';
  return public._resultado(b.id, ev);
end $$;

create or replace function public.batalha_fugir(p_batalha uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare b public.batalhas;
begin
  b := public._batalha_do_jogador(p_batalha);
  if b.trocar then raise exception 'Escolha outro Pokémon primeiro.'; end if;
  update public.batalhas set estado = 'fuga' where id = b.id;
  return public._resultado(b.id, jsonb_build_array(jsonb_build_object('t', 'fuga'), jsonb_build_object('t', 'fim', 'estado', 'fuga')));
end $$;

create or replace function public.batalha_capturar(p_batalha uuid, p_bola text default 'poke-ball')
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  b public.batalhas; ev jsonb := '[]'::jsonb; mult numeric; v_qtd int; sel jsonb; hpm numeric; hp numeric; a numeric; bb numeric; shakes int := 0; i int; novo public.pokemons;
  chance numeric; esp public.especies;
begin
  b := public._batalha_do_jogador(p_batalha);
  if b.trocar then raise exception 'Escolha outro Pokémon primeiro.'; end if;
  mult := case p_bola when 'poke-ball' then 1 when 'great-ball' then 1.5 when 'ultra-ball' then 2 when 'master-ball' then 255 else null end;
  if mult is null then raise exception 'Bola desconhecida.'; end if;
  select inv.qtd into v_qtd from public.inventario inv where inv.jogador = b.jogador and inv.item = p_bola for update;
  if coalesce(v_qtd, 0) <= 0 then raise exception 'Você não tem essa bola.'; end if;
  update public.inventario inv set qtd = inv.qtd - 1 where inv.jogador = b.jogador and inv.item = p_bola;
  sel := b.selvagem; hpm := (sel->>'hp_max')::numeric; hp := (sel->>'hp')::numeric;
  a := greatest(1, floor((3*hpm - 2*hp) * (sel->>'taxa_captura')::numeric * mult / (3*hpm)));
  if a >= 255 then bb := 65536; else bb := 1048560.0 / sqrt(sqrt(16711680.0 / a)); end if;
  chance := power(least(bb, 65535) / 65535.0, 4);
  ev := ev || jsonb_build_array(jsonb_build_object('t', 'bola', 'bola', p_bola, 'chance', round(chance * 100)));
  for i in 1..4 loop
    if bb >= 65536 or floor(random() * 65536) < bb then shakes := shakes + 1; else exit; end if;
  end loop;
  if shakes >= 4 then
    select * into esp from public.especies where id = (sel->>'especie_id')::int;
    novo := public._novo_pokemon(b.jogador, esp.id, (sel->>'nivel')::int, (select jsonb_agg(jsonb_build_object('id', (m->>'id')::int, 'pp', (m->>'pp')::int)) from jsonb_array_elements(sel->'golpes') m));
    update public.batalhas set estado = 'captura' where id = b.id;
    ev := ev || jsonb_build_array(jsonb_build_object('t', 'balanco', 'n', 3), jsonb_build_object('t', 'capturado', 'nome', esp.nome, 'time', novo.posicao is not null),
                                  jsonb_build_object('t', 'fim', 'estado', 'captura'));
  else
    ev := ev || jsonb_build_array(jsonb_build_object('t', 'balanco', 'n', shakes), jsonb_build_object('t', 'escapou', 'nome', sel->>'nome'));
    ev := public._turno_ataque('selvagem', b, 0, ev);
    ev := public._fechar_turno(b.id, ev);
    update public.batalhas set turno = turno + 1 where id = b.id and estado = 'ativa';
  end if;
  return public._resultado(b.id, ev);
end $$;

create or replace function public.dar_item(p_jogador uuid, p_item text, p_qtd int)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.eh_mestre() then raise exception 'Só o Mestre.'; end if;
  if p_qtd is null or p_qtd = 0 then raise exception 'Quantidade inválida.'; end if;
  insert into public.inventario (jogador, item, qtd) values (p_jogador, p_item, greatest(p_qtd, 0))
  on conflict (jogador, item) do update set qtd = greatest(public.inventario.qtd + p_qtd, 0);
  insert into public.auditoria (ator, acao, detalhe) values (auth.uid(), 'dar_item', jsonb_build_object('jogador', p_jogador, 'item', p_item, 'qtd', p_qtd));
end $$;

-- permissões: só as ações públicas; as funções internas (_*) ficam fechadas
revoke all on function public.importar_dados(text, jsonb), public.escolher_inicial(int), public.curar_time(), public.procurar_pokemon(),
  public.batalha_atacar(uuid, int), public.batalha_trocar(uuid, uuid), public.batalha_fugir(uuid), public.batalha_capturar(uuid, text),
  public.dar_item(uuid, text, int) from public, anon;
grant execute on function public.importar_dados(text, jsonb), public.escolher_inicial(int), public.curar_time(), public.procurar_pokemon(),
  public.batalha_atacar(uuid, int), public.batalha_trocar(uuid, uuid), public.batalha_fugir(uuid), public.batalha_capturar(uuid, text),
  public.dar_item(uuid, text, int) to authenticated;
revoke all on function public._novo_pokemon(uuid,int,int,jsonb), public._selvagem(int,int), public._resultado(uuid,jsonb), public._golpe(int,int,int,jsonb,text[],text[]),
  public._dar_exp(public.pokemons,jsonb,jsonb), public._turno_ataque(text,public.batalhas,int,jsonb), public._fechar_turno(uuid,jsonb),
  public._batalha_do_jogador(uuid), public._poi_aqui(public.jogadores,text) from public, anon, authenticated;
