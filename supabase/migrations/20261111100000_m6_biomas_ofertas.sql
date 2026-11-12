-- M6: biomas nos mapas + prévia de encontro. Ao andar e parar, o servidor sorteia (grátis) um Pokémon do bioma onde o
-- jogador parou; só se o jogador clicar em "Buscar" (1 PA) a batalha começa com aquele Pokémon.

alter table public.mapas add column if not exists bioma text;   -- 1 caractere por tile: G grama, E estrada, F floresta, A água, C campo, P praça/cidade, # sólido
alter table public.encontros add column if not exists bioma text not null default 'grama';
alter table public.encontros drop constraint if exists encontros_pkey;
alter table public.encontros add primary key (mapa_id, bioma, especie_id);

alter table public.jogadores add column if not exists rolagem text;        -- chave mapa:x:y da última prévia sorteada
alter table public.jogadores add column if not exists rolagem_em timestamptz;

create table if not exists public.ofertas (
  jogador uuid primary key references public.jogadores (id) on delete cascade,
  mapa_id text not null, x int not null, y int not null,
  especie_id int not null references public.especies (id) on delete cascade,
  nivel smallint not null, bioma text not null,
  criada_em timestamptz not null default now()
);
alter table public.ofertas enable row level security;
drop policy if exists "ofertas_dono" on public.ofertas;
create policy "ofertas_dono" on public.ofertas for select to authenticated using (jogador = auth.uid());
grant select on public.ofertas to authenticated;
grant all on public.ofertas to service_role;

insert into public.config (chave, valor) values ('chance_oferta', '50'::jsonb) on conflict (chave) do nothing;

-- importação (Mestre): mapas agora levam o bioma; encontros levam o bioma na chave
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
    insert into public.mapas (id, nome, largura, altura, spawn_x, spawn_y, tipo, solido, grama, portais, pois, bioma)
    select id, nome, largura, altura, spawn_x, spawn_y, coalesce(tipo, 'andavel'), solido, grama, coalesce(portais, '[]'::jsonb), coalesce(pois, '[]'::jsonb), bioma
      from jsonb_populate_recordset(null::public.mapas, p_linhas)
    on conflict (id) do update set nome = excluded.nome, largura = excluded.largura, altura = excluded.altura, spawn_x = excluded.spawn_x,
      spawn_y = excluded.spawn_y, tipo = excluded.tipo, solido = excluded.solido, grama = excluded.grama, portais = excluded.portais,
      pois = excluded.pois, bioma = excluded.bioma;
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

-- andar: passos descartam a prévia (a oferta vale só para quem parou naquele tile)
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

-- "Buscar": gasta 1 PA e começa a batalha com o Pokémon da prévia
create or replace function public.procurar_pokemon()
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_j public.jogadores; v_b public.batalhas; v_o public.ofertas; v_ativo uuid; v_sel jsonb;
begin
  if auth.uid() is null then raise exception 'Faça login primeiro.'; end if;
  select * into v_j from public.jogadores where id = auth.uid() for update;
  if not found then raise exception 'Crie seu personagem primeiro.'; end if;
  select * into v_b from public.batalhas where jogador = v_j.id and estado = 'ativa';
  if found then return public._resultado(v_b.id, jsonb_build_array(jsonb_build_object('t', 'retomada'))); end if;
  select * into v_o from public.ofertas where jogador = v_j.id and mapa_id = v_j.mapa_id and x = v_j.x and y = v_j.y;
  if not found then raise exception 'Não há Pokémon à vista aqui. Ande um pouco e pare de novo.'; end if;
  select id into v_ativo from public.pokemons where dono = v_j.id and posicao is not null and hp_atual > 0 order by posicao limit 1;
  if v_ativo is null then
    if exists (select 1 from public.pokemons where dono = v_j.id) then raise exception 'Seus Pokémon estão desmaiados. Cure-os em casa ou no Centro Pokémon.';
    else raise exception 'Você ainda não tem Pokémon. Fale com o Professor Carvalho no laboratório.'; end if;
  end if;
  if v_j.pa < 1 then raise exception 'PA insuficiente: buscar Pokémon custa 1 PA.'; end if;
  v_sel := public._selvagem(v_o.especie_id, v_o.nivel);
  delete from public.ofertas where jogador = v_j.id;
  update public.jogadores set pa = pa - 1 where id = v_j.id;
  insert into public.batalhas (jogador, selvagem, ativo) values (v_j.id, v_sel, v_ativo) returning * into v_b;
  insert into public.pokedex (jogador, especie_id) values (v_j.id, v_o.especie_id) on conflict do nothing;
  return public._resultado(v_b.id, jsonb_build_array(jsonb_build_object('t', 'apareceu', 'nome', v_sel->>'nome', 'nivel', v_o.nivel)));
end $$;

revoke all on function public.gerar_oferta() from public, anon;
grant execute on function public.gerar_oferta() to authenticated;
grant execute on function public.andar(text), public.procurar_pokemon(), public.importar_dados(text, jsonb) to authenticated;
