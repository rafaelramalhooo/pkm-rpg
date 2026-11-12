-- M11: mundo aberto "Rafar" — níveis escalonados, insígnias, lojas/presentes/trocas, Liga. Substitui Viridian pelo novo mundo.


alter table public.mapas add column if not exists nivel_piso smallint, add column if not exists nivel_teto smallint, add column if not exists nivel_bonus smallint;
alter table public.jogadores add column if not exists insignias text[] not null default '{}', add column if not exists campeao boolean not null default false;
alter table public.treinadores alter column equipe drop not null;
alter table public.treinadores add column if not exists escala jsonb, add column if not exists insignia text, add column if not exists lider boolean not null default false;
create table if not exists public.poi_usos (
  jogador uuid not null references public.jogadores (id) on delete cascade,
  mapa_id text not null, poi text not null, em timestamptz not null default now(),
  primary key (jogador, mapa_id, poi)
);
alter table public.poi_usos enable row level security;
drop policy if exists "poi_usos_dono" on public.poi_usos;
create policy "poi_usos_dono" on public.poi_usos for select to authenticated using (jogador = auth.uid() or public.eh_mestre());
grant select on public.poi_usos to authenticated;
insert into public.config (chave, valor) values ('dificuldade', '0'::jsonb) on conflict (chave) do nothing;   -- -3 fácil, 0 normal, 3 difícil


create or replace function public._nivel_ref(p_j uuid) returns int language sql stable security definer set search_path = public as $$
  select coalesce(round(avg(n))::int, 5) from (select nivel::int as n from public.pokemons where dono = p_j order by nivel desc limit 3) s $$;
create or replace function public._dificuldade() returns int language sql stable security definer set search_path = public as $$
  select coalesce((select (valor #>> '{}')::int from public.config where chave = 'dificuldade'), 0) $$;
-- teto de nível por insígnias: 0=15 1=20 2=25 3=30 4=35 5=40 6=45 7=50 8=55; Campeão: sem teto
create or replace function public._teto_nivel(p_j uuid) returns int language sql stable security definer set search_path = public as $$
  select coalesce((select case when campeao then 100 else (array[15,20,25,30,35,40,45,50,55])[least(coalesce(array_length(insignias, 1), 0), 8) + 1] end
                     from public.jogadores where id = p_j), 15) $$;
revoke all on function public._nivel_ref(uuid), public._dificuldade(), public._teto_nivel(uuid) from public, anon, authenticated;

create or replace function public._equipe_escalada(t public.treinadores, p_ref int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  esc jsonb := t.escala; n int := coalesce((esc->>'time')::int, 3); bonus int := coalesce((esc->>'bonus')::int, 0);
  piso int := coalesce((esc->>'piso')::int, 1); var int := coalesce((esc->>'var')::int, 2); dif int := public._dificuldade();
  ace jsonb := esc->'ace'; pool jsonb := esc->'pool'; k int; total int; lvl int; ent jsonb; usadas int[] := '{}'; res jsonb := '[]'::jsonb;
begin
  total := n - case when ace is not null then 1 else 0 end;
  for k in 1 .. total loop
    lvl := least(100, greatest(piso, p_ref + bonus + dif + floor(random() * (var + 1))::int));
    ent := null;
    select e into ent from jsonb_array_elements(pool) e
     where (e->>'de')::int <= lvl and (e->>'ate')::int >= lvl and not ((e->>'linha')::int = any(usadas)) order by random() limit 1;
    if ent is null then
      select e into ent from jsonb_array_elements(pool) e where (e->>'de')::int <= lvl and (e->>'ate')::int >= lvl order by random() limit 1;
    end if;
    if ent is null then
      select e into ent from jsonb_array_elements(pool) e order by least(abs((e->>'de')::int - lvl), abs((e->>'ate')::int - lvl)) limit 1;
      lvl := greatest((ent->>'de')::int, least((ent->>'ate')::int, lvl));
    end if;
    usadas := usadas || (ent->>'linha')::int;
    res := res || public._equipe_treinador(jsonb_build_array(jsonb_build_object('especie', (ent->>'e')::int, 'nivel', lvl)));
  end loop;
  if ace is not null then
    lvl := least(100, greatest(piso, p_ref + (ace->>'bonus')::int + dif));
    res := res || public._equipe_treinador(jsonb_build_array(jsonb_build_object('especie', (ace->>'e')::int, 'nivel', lvl)));
  end if;
  return res;
end $$;
revoke all on function public._equipe_escalada(public.treinadores, int) from public, anon, authenticated;

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
    insert into public.mapas (id, nome, largura, altura, spawn_x, spawn_y, tipo, solido, grama, portais, pois, bioma, nivel_piso, nivel_teto, nivel_bonus, chance_oferta)
    select id, nome, largura, altura, spawn_x, spawn_y, coalesce(tipo, 'andavel'), solido, grama, coalesce(portais, '[]'::jsonb), coalesce(pois, '[]'::jsonb), bioma, nivel_piso, nivel_teto, nivel_bonus, chance_oferta
      from jsonb_populate_recordset(null::public.mapas, p_linhas)
    on conflict (id) do update set nome = excluded.nome, largura = excluded.largura, altura = excluded.altura, spawn_x = excluded.spawn_x,
      spawn_y = excluded.spawn_y, tipo = excluded.tipo, solido = excluded.solido, grama = excluded.grama, portais = excluded.portais,
      pois = excluded.pois, bioma = excluded.bioma, nivel_piso = excluded.nivel_piso, nivel_teto = excluded.nivel_teto,
      nivel_bonus = excluded.nivel_bonus, chance_oferta = excluded.chance_oferta;
  elsif p_tabela = 'itens' then
    insert into public.itens select * from jsonb_populate_recordset(null::public.itens, p_linhas)
    on conflict (slug) do update set nome = excluded.nome, categoria = excluded.categoria, efeito = excluded.efeito, arco = excluded.arco;
  elsif p_tabela = 'encontros' then
    insert into public.encontros (mapa_id, bioma, especie_id, peso, nivel_min, nivel_max)
    select mapa_id, coalesce(bioma, 'grama'), especie_id, peso, nivel_min, nivel_max from jsonb_populate_recordset(null::public.encontros, p_linhas)
    on conflict (mapa_id, bioma, especie_id) do update set peso = excluded.peso, nivel_min = excluded.nivel_min, nivel_max = excluded.nivel_max;
  else
    raise exception 'Tabela não permitida.';
  end if;
  get diagnostics n = row_count;
  insert into public.auditoria (ator, acao, detalhe) values (auth.uid(), 'importar_dados', jsonb_build_object('tabela', p_tabela, 'linhas', n));
  return n;
end $$;
revoke all on function public.importar_dados(text, jsonb) from public, anon;
grant execute on function public.importar_dados(text, jsonb) to authenticated;

create or replace function public.importar_treinadores(p_linhas jsonb) returns int
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if not public.eh_mestre() then raise exception 'Só o Mestre importa dados.'; end if;
  insert into public.treinadores (id, mapa_id, x, y, direcao, visao, nome, classe, aparencia, recompensa, falas, equipe, arco, escala, insignia, lider)
  select id, mapa_id, x, y, coalesce(direcao, 'baixo'), coalesce(visao, 3), nome, coalesce(classe, 'Treinador'), coalesce(aparencia, 0),
         coalesce(recompensa, 0), coalesce(falas, '{}'::jsonb), equipe, coalesce(arco, 1), escala, insignia, coalesce(lider, false)
    from jsonb_populate_recordset(null::public.treinadores, p_linhas)
  on conflict (id) do update set mapa_id = excluded.mapa_id, x = excluded.x, y = excluded.y, direcao = excluded.direcao, visao = excluded.visao,
    nome = excluded.nome, classe = excluded.classe, aparencia = excluded.aparencia, recompensa = excluded.recompensa, falas = excluded.falas,
    equipe = excluded.equipe, arco = excluded.arco, escala = excluded.escala, insignia = excluded.insignia, lider = excluded.lider;
  get diagnostics n = row_count;
  insert into public.auditoria (ator, acao, detalhe) values (auth.uid(), 'importar_dados', jsonb_build_object('tabela', 'treinadores', 'linhas', n));
  return n;
end $$;
revoke all on function public.importar_treinadores(jsonb) from public, anon;
grant execute on function public.importar_treinadores(jsonb) to authenticated;

create or replace function public.desafiar_treinador(p_treinador text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_j public.jogadores; v_t public.treinadores; v_b public.batalhas; v_ativo uuid;
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
  -- o treinador só desafia quando o jogador puxa conversa: precisa estar num tile ao lado dele
  if abs(v_t.x - v_j.x) + abs(v_t.y - v_j.y) <> 1 then raise exception 'Chegue ao lado de % para conversar.', v_t.nome; end if;
  select id into v_ativo from public.pokemons where dono = v_j.id and posicao is not null and hp_atual > 0 order by posicao limit 1;
  if v_ativo is null then
    if exists (select 1 from public.pokemons where dono = v_j.id) then raise exception 'Seus Pokémon estão desmaiados. Cure-os no Centro Pokémon ou em casa.';
    else raise exception 'Você ainda não tem Pokémon. Fale com o Professor Carvalho no laboratório.'; end if;
  end if;
  insert into public.batalhas (jogador, selvagem, ativo, tipo, treinador, adversarios)
  values (v_j.id, '{}'::jsonb, v_ativo, 'treinador', v_t.id, case when v_t.escala is not null then public._equipe_escalada(v_t, public._nivel_ref(v_j.id)) else public._equipe_treinador(v_t.equipe) end) returning * into v_b;
  return jsonb_build_object('batalha', to_jsonb(v_b) - 'sim' - 'meta', 'treinador', jsonb_build_object('nome', v_t.nome, 'classe', v_t.classe));
end $$;
grant execute on function public.desafiar_treinador(text) to authenticated;

create or replace function public.gerar_oferta()
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_j public.jogadores; v_m public.mapas; v_o public.ofertas; v_c char(1); v_bioma text; v_chave text;
  v_total int; v_r int; v_acc int := 0; v_e record; v_nivel int; v_chance int;
begin
  if auth.uid() is null then raise exception 'Faça login primeiro.'; end if;
  select * into v_j from public.jogadores where id = auth.uid() for update;
  if not found then raise exception 'Crie seu personagem primeiro.'; end if;
  v_chave := v_j.mapa_id || ':' || v_j.x || ':' || v_j.y;
  select * into v_o from public.ofertas where jogador = v_j.id;
  if found and v_o.mapa_id = v_j.mapa_id and v_o.x = v_j.x and v_o.y = v_j.y then
    return jsonb_build_object('especie_id', v_o.especie_id, 'nome', (select nome from public.especies where id = v_o.especie_id), 'nivel', v_o.nivel, 'bioma', v_o.bioma);
  end if;
  delete from public.ofertas where jogador = v_j.id;
  if v_j.rolagem = v_chave then return null; end if;                                             -- já sorteou neste tile
  if v_j.rolagem_em is not null and v_j.rolagem_em > clock_timestamp() - interval '150 milliseconds' then return null; end if;
  if exists (select 1 from public.batalhas where jogador = v_j.id and estado = 'ativa') then return null; end if;
  if not exists (select 1 from public.pokemons where dono = v_j.id and posicao is not null and hp_atual > 0) then return null; end if;
  update public.jogadores set rolagem = v_chave, rolagem_em = clock_timestamp() where id = v_j.id;

  select * into v_m from public.mapas where id = v_j.mapa_id;
  if v_m.bioma is null then return null; end if;
  v_c := substr(v_m.bioma, v_j.y * v_m.largura + v_j.x + 1, 1);
  v_bioma := case v_c when 'G' then 'grama' when 'E' then 'estrada' when 'F' then 'floresta' when 'A' then 'agua' when 'C' then 'campo' else null end;
  if v_bioma is null then return null; end if;
  v_chance := coalesce(v_m.chance_oferta, (select (valor #>> '{}')::int from public.config where chave = 'chance_oferta'), 100);
  if floor(random() * 100) >= v_chance then return null; end if;

  if v_m.nivel_piso is null then
  select coalesce(sum(peso), 0) into v_total from public.encontros where mapa_id = v_j.mapa_id and bioma = v_bioma;
  if v_total = 0 then return null; end if;
  v_r := floor(random() * v_total);
  for v_e in select * from public.encontros where mapa_id = v_j.mapa_id and bioma = v_bioma order by especie_id loop
    v_acc := v_acc + v_e.peso;
    if v_r < v_acc then exit; end if;
  end loop;
  v_nivel := v_e.nivel_min + floor(random() * (v_e.nivel_max - v_e.nivel_min + 1));
  else
    v_nivel := greatest(v_m.nivel_piso, least(v_m.nivel_teto, public._nivel_ref(v_j.id) + coalesce(v_m.nivel_bonus, 0) + public._dificuldade() + floor(random() * 4)::int - 2));
    select coalesce(sum(peso), 0) into v_total from public.encontros where mapa_id = v_j.mapa_id and bioma = v_bioma and v_nivel between nivel_min and nivel_max;
    if v_total = 0 then
      select * into v_e from public.encontros where mapa_id = v_j.mapa_id and bioma = v_bioma
       order by greatest(nivel_min - v_nivel, v_nivel - nivel_max, 0), random() limit 1;
      if not found then return null; end if;
      v_nivel := greatest(v_e.nivel_min, least(v_e.nivel_max, v_nivel));
    else
      v_r := floor(random() * v_total);
      for v_e in select * from public.encontros where mapa_id = v_j.mapa_id and bioma = v_bioma and v_nivel between nivel_min and nivel_max order by especie_id loop
        v_acc := v_acc + v_e.peso;
        if v_r < v_acc then exit; end if;
      end loop;
    end if;
  end if;
  insert into public.ofertas (jogador, mapa_id, x, y, especie_id, nivel, bioma) values (v_j.id, v_j.mapa_id, v_j.x, v_j.y, v_e.especie_id, v_nivel, v_bioma);
  return jsonb_build_object('especie_id', v_e.especie_id, 'nome', (select nome from public.especies where id = v_e.especie_id), 'nivel', v_nivel, 'bioma', v_bioma);
end $$;
grant execute on function public.gerar_oferta() to authenticated;

create or replace function public.andar(p_dir text)
returns public.jogadores
language plpgsql security definer set search_path = public as $$
declare
  v_j public.jogadores; v_m public.mapas; v_nx int; v_ny int; v_p jsonb;
begin
  if auth.uid() is null then raise exception 'Faça login primeiro.'; end if;
  if p_dir not in ('cima','baixo','esquerda','direita') then raise exception 'Direção inválida.'; end if;
  select * into v_j from public.jogadores where id = auth.uid() for update;
  if not found then raise exception 'Crie seu personagem primeiro.'; end if;
  if exists (select 1 from public.batalhas where jogador = v_j.id and estado = 'ativa') then
    raise exception 'Termine a batalha primeiro.';
  end if;
  select * into v_m from public.mapas where id = v_j.mapa_id;
  if v_m.tipo <> 'andavel' then raise exception 'Este mapa não é andável.'; end if;
  if v_m.solido is null then raise exception 'O Mestre ainda precisa importar os mapas.'; end if;

  v_nx := v_j.x + case p_dir when 'esquerda' then -1 when 'direita' then 1 else 0 end;
  v_ny := v_j.y + case p_dir when 'cima' then -1 when 'baixo' then 1 else 0 end;
  if v_j.posicao_em > clock_timestamp() - interval '100 milliseconds' then
    raise exception 'Calma, devagar.';
  end if;
  if v_nx < 0 or v_ny < 0 or v_nx >= v_m.largura or v_ny >= v_m.altura then
    raise exception 'Fim do mapa.';
  end if;
  if substr(v_m.solido, v_ny * v_m.largura + v_nx + 1, 1) = '1' then
    update public.jogadores set direcao = p_dir where id = v_j.id returning * into v_j;
    return v_j;
  end if;

  delete from public.ofertas where jogador = v_j.id;

  for v_p in select * from jsonb_array_elements(v_m.portais) loop
    if v_nx >= (v_p->>'x')::int and v_nx < (v_p->>'x')::int + coalesce((v_p->>'w')::int, 1)
       and v_ny >= (v_p->>'y')::int and v_ny < (v_p->>'y')::int + coalesce((v_p->>'h')::int, 1) then
      if v_p ? 'req_insignias' and coalesce(array_length(v_j.insignias, 1), 0) < (v_p->>'req_insignias')::int then
        raise exception 'O portão da Liga só abre para quem tem % insígnias (você tem %).', v_p->>'req_insignias', coalesce(array_length(v_j.insignias, 1), 0);
      end if;
      if v_p ? 'req_treinador' and not exists (select 1 from public.treinadores_vencidos where jogador = v_j.id and treinador = v_p->>'req_treinador') then
        raise exception 'Derrote % para seguir adiante.', coalesce((select nome from public.treinadores where id = v_p->>'req_treinador'), 'o desafiante');
      end if;
      update public.jogadores
         set mapa_id = v_p->>'dest', x = (v_p->>'dx')::int, y = (v_p->>'dy')::int,
             direcao = coalesce(v_p->>'dir', p_dir), posicao_em = clock_timestamp()
       where id = v_j.id returning * into v_j;
      return v_j;
    end if;
  end loop;

  update public.jogadores set x = v_nx, y = v_ny, direcao = p_dir, posicao_em = clock_timestamp()
   where id = v_j.id returning * into v_j;
  return v_j;
end;
$$;

-- sorteia a prévia do bioma onde o jogador está parado (chance configurável; nunca re-sorteia no mesmo tile)
create or replace function public.gerar_oferta()
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_j public.jogadores; v_m public.mapas; v_o public.ofertas; v_c char(1); v_bioma text; v_chave text;
  v_total int; v_r int; v_acc int := 0; v_e record; v_nivel int; v_chance int;
begin
  if auth.uid() is null then raise exception 'Faça login primeiro.'; end if;
  select * into v_j from public.jogadores where id = auth.uid() for update;
  if not found then raise exception 'Crie seu personagem primeiro.'; end if;
  v_chave := v_j.mapa_id || ':' || v_j.x || ':' || v_j.y;
  select * into v_o from public.ofertas where jogador = v_j.id;
  if found and v_o.mapa_id = v_j.mapa_id and v_o.x = v_j.x and v_o.y = v_j.y then
    return jsonb_build_object('especie_id', v_o.especie_id, 'nome', (select nome from public.especies where id = v_o.especie_id), 'nivel', v_o.nivel, 'bioma', v_o.bioma);
  end if;
  delete from public.ofertas where jogador = v_j.id;
  if v_j.rolagem = v_chave then return null; end if;                                             -- já sorteou neste tile
  if v_j.rolagem_em is not null and v_j.rolagem_em > clock_timestamp() - interval '700 milliseconds' then return null; end if;
  if exists (select 1 from public.batalhas where jogador = v_j.id and estado = 'ativa') then return null; end if;
  if not exists (select 1 from public.pokemons where dono = v_j.id and posicao is not null and hp_atual > 0) then return null; end if;
  update public.jogadores set rolagem = v_chave, rolagem_em = clock_timestamp() where id = v_j.id;

  select * into v_m from public.mapas where id = v_j.mapa_id;
  if v_m.bioma is null then return null; end if;
  v_c := substr(v_m.bioma, v_j.y * v_m.largura + v_j.x + 1, 1);
  v_bioma := case v_c when 'G' then 'grama' when 'E' then 'estrada' when 'F' then 'floresta' when 'A' then 'agua' when 'C' then 'campo' else null end;
  if v_bioma is null then return null; end if;
  v_chance := coalesce((select (valor #>> '{}')::int from public.config where chave = 'chance_oferta'), 50);
  if floor(random() * 100) >= v_chance then return null; end if;

  select coalesce(sum(peso), 0) into v_total from public.encontros where mapa_id = v_j.mapa_id and bioma = v_bioma;
  if v_total = 0 then return null; end if;
  v_r := floor(random() * v_total);
  for v_e in select * from public.encontros where mapa_id = v_j.mapa_id and bioma = v_bioma order by especie_id loop
    v_acc := v_acc + v_e.peso;
    if v_r < v_acc then exit; end if;
  end loop;
  v_nivel := v_e.nivel_min + floor(random() * (v_e.nivel_max - v_e.nivel_min + 1));
  insert into public.ofertas (jogador, mapa_id, x, y, especie_id, nivel, bioma) values (v_j.id, v_j.mapa_id, v_j.x, v_j.y, v_e.especie_id, v_nivel, v_bioma);
  return jsonb_build_object('especie_id', v_e.especie_id, 'nome', (select nome from public.especies where id = v_e.especie_id), 'nivel', v_nivel, 'bioma', v_bioma);
end $$;
grant execute on function public.andar(text) to authenticated;

create or replace function public._dar_exp(p_pk public.pokemons, p_sel jsonb, p_ev jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare ganho int := floor((p_sel->>'exp_base')::int * (p_sel->>'nivel')::int / 7.0); e public.especies; novo public.pokemons := p_pk;
  g record; hpmax_ant int; cap int;
begin
  select * into e from public.especies where id = p_pk.especie_id;
  cap := public._teto_nivel(p_pk.dono);
  if p_pk.nivel >= cap then ganho := 0; end if;
  novo.exp := p_pk.exp + ganho;
  p_ev := p_ev || jsonb_build_array(jsonb_build_object('t', 'exp', 'valor', ganho, 'nome', coalesce(p_pk.apelido, e.nome)));
  while novo.nivel < least(100, cap) and novo.exp >= public.exp_para(novo.nivel + 1) loop
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
  delete from public.poi_usos where jogador = p_jogador;
  update public.jogadores set insignias = '{}', campeao = false where id = p_jogador;
  update public.jogadores
     set mapa_id = s.p_mapa, x = s.p_x, y = s.p_y, direcao = 'baixo', rolagem = null,
         pa = coalesce((select (valor #>> '{}')::smallint from public.config where chave = 'pa_por_dia'), 30),
         dinheiro = 1000, posicao_em = now()
   where id = p_jogador;
  return v_nome;
end $$;

create or replace function public._poi_aqui_acao(p_j public.jogadores, p_acao text) returns boolean language sql stable set search_path = public as
$$ select exists (select 1 from public.mapas m, jsonb_array_elements(m.pois) p
    where m.id = p_j.mapa_id and p->>'acao' = p_acao and (p->>'x')::int = p_j.x and (p->>'y')::int = p_j.y) $$;
revoke all on function public._poi_aqui_acao(public.jogadores, text) from public, anon, authenticated;

create or replace function public.curar_time()
returns int language plpgsql security definer set search_path = public as $$
declare v_j public.jogadores; n int;
begin
  if auth.uid() is null then raise exception 'Faça login primeiro.'; end if;
  select * into v_j from public.jogadores where id = auth.uid() for update;
  if not (public._poi_aqui(v_j, 'centro') or public._poi_aqui(v_j, 'casa_jogador') or public._poi_aqui_acao(v_j, 'cura')) then
    raise exception 'Só dá para curar no Centro Pokémon, numa pousada ou na sua casa.';
  end if;
  if exists (select 1 from public.batalhas where jogador = v_j.id and estado = 'ativa') then raise exception 'Termine a batalha primeiro.'; end if;
  update public.pokemons p set hp_atual = hp_max,
    golpes = coalesce((select jsonb_agg(jsonb_build_object('id', (g->>'id')::int, 'pp', (select pp from public.golpes where id = (g->>'id')::int)))
                         from jsonb_array_elements(p.golpes) g), '[]'::jsonb)
   where dono = v_j.id;
  get diagnostics n = row_count;
  return n;
end $$;
grant execute on function public.curar_time() to authenticated;

create or replace function public._poi_do_jogador(p_j public.jogadores, p_poi text) returns jsonb language sql stable set search_path = public as
$$ select p from public.mapas m, jsonb_array_elements(m.pois) p
    where m.id = p_j.mapa_id and p->>'id' = p_poi and (p->>'x')::int = p_j.x and (p->>'y')::int = p_j.y limit 1 $$;
revoke all on function public._poi_do_jogador(public.jogadores, text) from public, anon, authenticated;

-- presente (uma vez por jogador) e troca (uma vez por jogador)
create or replace function public.usar_poi(p_poi text, p_pokemon uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_j public.jogadores; v_p jsonb; v_old public.pokemons; v_new public.pokemons; v_acao text;
begin
  if auth.uid() is null then raise exception 'Faça login primeiro.'; end if;
  select * into v_j from public.jogadores where id = auth.uid() for update;
  if not found then raise exception 'Crie seu personagem primeiro.'; end if;
  if exists (select 1 from public.batalhas where jogador = v_j.id and estado = 'ativa') then raise exception 'Termine a batalha primeiro.'; end if;
  v_p := public._poi_do_jogador(v_j, p_poi);
  if v_p is null then raise exception 'Chegue até a porta para interagir.'; end if;
  v_acao := v_p->>'acao';
  if exists (select 1 from public.poi_usos where jogador = v_j.id and mapa_id = v_j.mapa_id and poi = p_poi) then
    raise exception 'Você já fez isso aqui.';
  end if;
  if v_acao = 'presente' then
    insert into public.inventario (jogador, item, qtd) values (v_j.id, v_p->>'item', coalesce((v_p->>'qtd')::int, 1))
    on conflict (jogador, item) do update set qtd = public.inventario.qtd + coalesce((v_p->>'qtd')::int, 1);
    insert into public.poi_usos (jogador, mapa_id, poi) values (v_j.id, v_j.mapa_id, p_poi);
    return jsonb_build_object('acao', 'presente', 'item', v_p->>'item', 'qtd', coalesce((v_p->>'qtd')::int, 1), 'texto', v_p->>'texto');
  elsif v_acao = 'troca' then
    if p_pokemon is null then raise exception 'Escolha o Pokémon que quer oferecer.'; end if;
    select * into v_old from public.pokemons where id = p_pokemon and dono = v_j.id and especie_id = (v_p->>'quer')::int;
    if not found then raise exception 'Este viajante só aceita % em troca.', (select nome from public.especies where id = (v_p->>'quer')::int); end if;
    delete from public.pokemons where id = v_old.id;
    v_new := public._novo_pokemon(v_j.id, (v_p->>'da')::int, v_old.nivel);
    if v_old.posicao is not null and v_new.posicao is distinct from v_old.posicao then
      update public.pokemons set posicao = null where id = v_new.id;
      update public.pokemons set posicao = v_old.posicao where id = v_new.id;
    end if;
    insert into public.poi_usos (jogador, mapa_id, poi) values (v_j.id, v_j.mapa_id, p_poi);
    return jsonb_build_object('acao', 'troca', 'recebeu', (select nome from public.especies where id = v_new.especie_id), 'nivel', v_new.nivel);
  end if;
  raise exception 'Este lugar não faz isso.';
end $$;
revoke all on function public.usar_poi(text, uuid) from public, anon;
grant execute on function public.usar_poi(text, uuid) to authenticated;

-- loja: o preço vem do próprio ponto de interesse (o servidor decide)
create or replace function public.comprar_item(p_poi text, p_item text, p_qtd int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_j public.jogadores; v_p jsonb; v_e jsonb; v_total int;
begin
  if auth.uid() is null then raise exception 'Faça login primeiro.'; end if;
  if p_qtd is null or p_qtd < 1 or p_qtd > 99 then raise exception 'Quantidade inválida.'; end if;
  select * into v_j from public.jogadores where id = auth.uid() for update;
  if not found then raise exception 'Crie seu personagem primeiro.'; end if;
  v_p := public._poi_do_jogador(v_j, p_poi);
  if v_p is null or v_p->>'acao' <> 'loja' then raise exception 'Chegue ao balcão da loja.'; end if;
  select e into v_e from jsonb_array_elements(v_p->'estoque') e where e->>'item' = p_item limit 1;
  if v_e is null then raise exception 'Esta loja não vende isso.'; end if;
  v_total := (v_e->>'preco')::int * p_qtd;
  if v_j.dinheiro < v_total then raise exception 'Dinheiro insuficiente (precisa de %).', v_total; end if;
  update public.jogadores set dinheiro = dinheiro - v_total where id = v_j.id;
  insert into public.inventario (jogador, item, qtd) values (v_j.id, p_item, p_qtd)
  on conflict (jogador, item) do update set qtd = public.inventario.qtd + p_qtd;
  return jsonb_build_object('item', p_item, 'qtd', p_qtd, 'total', v_total, 'dinheiro', v_j.dinheiro - v_total);
end $$;
revoke all on function public.comprar_item(text, text, int) from public, anon;
grant execute on function public.comprar_item(text, text, int) to authenticated;

-- dificuldade global (Mestre): -3 fácil, 0 normal, 3 difícil
create or replace function public.definir_dificuldade(p_valor int) returns int language plpgsql security definer set search_path = public as $$
begin
  if not public.eh_mestre() then raise exception 'Só o Mestre.'; end if;
  if p_valor not in (-3, 0, 3) then raise exception 'Use -3 (fácil), 0 (normal) ou 3 (difícil).'; end if;
  insert into public.config (chave, valor) values ('dificuldade', to_jsonb(p_valor)) on conflict (chave) do update set valor = excluded.valor;
  insert into public.auditoria (ator, acao, detalhe) values (auth.uid(), 'definir_dificuldade', jsonb_build_object('valor', p_valor));
  return p_valor;
end $$;
revoke all on function public.definir_dificuldade(int) from public, anon;
grant execute on function public.definir_dificuldade(int) to authenticated;

-- Viridian sai de cena: quem estava lá volta ao laboratório (corrigir_posicoes leva ao spawn)
delete from public.ofertas where mapa_id = 'viridian';
delete from public.encontros where mapa_id = 'viridian';
delete from public.treinadores where mapa_id = 'viridian';
update public.jogadores set mapa_id = 'lab', x = 6, y = 14, direcao = 'baixo', posicao_em = now() where mapa_id = 'viridian';
delete from public.mapas where id = 'viridian';
