-- m13: eventos do Mestre, Pokémon brilhante, viagem livre e correção de gerar_oferta (escala de nível de Rafar)
alter table public.pokemons add column if not exists brilhante boolean not null default false;

create table if not exists public.eventos (
  id uuid primary key default gen_random_uuid(),
  tipo text not null check (tipo in ('xp', 'dinheiro', 'brilhante', 'encontro', 'pa_gratis')),
  valor numeric not null default 1 check (valor > 0 and valor <= 1000),
  mensagem text,
  inicio timestamptz not null default now(),
  fim timestamptz not null,
  encerrado boolean not null default false,
  criado_por uuid references public.jogadores(id) on delete set null
);
alter table public.eventos enable row level security;
drop policy if exists ev_ler on public.eventos;
create policy ev_ler on public.eventos for select to authenticated using (true);

create or replace function public._ev(p_tipo text, p_padrao numeric default 1) returns numeric
language sql stable security definer set search_path = public as $$
  select coalesce((select max(valor) from public.eventos where tipo = p_tipo and not encerrado and now() >= inicio and now() < fim), p_padrao) $$;
revoke all on function public._ev(text, numeric) from public, anon, authenticated;

create or replace function public.eventos_ativos() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'tipo', tipo, 'valor', valor, 'mensagem', mensagem, 'fim', fim) order by fim), '[]'::jsonb)
    from public.eventos where not encerrado and now() >= inicio and now() < fim $$;
grant execute on function public.eventos_ativos() to authenticated;

create or replace function public.criar_evento(p_tipo text, p_valor numeric, p_minutos int, p_mensagem text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_j public.jogadores; v_e public.eventos;
begin
  if auth.uid() is null then raise exception 'Faça login primeiro.'; end if;
  select * into v_j from public.jogadores where id = auth.uid();
  if not found or v_j.papel <> 'mestre' then raise exception 'Só o Mestre cria eventos.'; end if;
  if p_tipo not in ('xp', 'dinheiro', 'brilhante', 'encontro', 'pa_gratis') then raise exception 'Tipo de evento inválido.'; end if;
  if p_minutos is null or p_minutos < 1 or p_minutos > 20160 then raise exception 'Duração inválida (1 minuto a 14 dias).'; end if;
  if p_valor is null or p_valor <= 0 or p_valor > 1000 then raise exception 'Valor inválido.'; end if;
  update public.eventos set encerrado = true where tipo = p_tipo and not encerrado;
  insert into public.eventos (tipo, valor, mensagem, fim, criado_por)
  values (p_tipo, p_valor, nullif(btrim(coalesce(p_mensagem, '')), ''), now() + make_interval(mins => p_minutos), v_j.id) returning * into v_e;
  return to_jsonb(v_e);
end $$;
grant execute on function public.criar_evento(text, numeric, int, text) to authenticated;

create or replace function public.encerrar_evento(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare v_j public.jogadores;
begin
  if auth.uid() is null then raise exception 'Faça login primeiro.'; end if;
  select * into v_j from public.jogadores where id = auth.uid();
  if not found or v_j.papel <> 'mestre' then raise exception 'Só o Mestre encerra eventos.'; end if;
  update public.eventos set encerrado = true where id = p_id;
end $$;
grant execute on function public.encerrar_evento(uuid) to authenticated;


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
  v_chance := least(100, round(v_chance * public._ev('encontro', 1)))::int;
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

create or replace function public._dar_exp(p_pk public.pokemons, p_sel jsonb, p_ev jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare ganho int := floor((p_sel->>'exp_base')::int * (p_sel->>'nivel')::int / 7.0 * public._ev('xp', 1)); e public.especies; novo public.pokemons := p_pk;
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
        update public.jogadores set dinheiro = dinheiro + floor(t.recompensa * public._ev('dinheiro', 1)) where id = b.jogador;
        ev := ev || jsonb_build_array(jsonb_build_object('t', 'dinheiro', 'valor', floor(t.recompensa * public._ev('dinheiro', 1)), 'nome', t.nome));
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
  if v_j.pa < 1 and public._ev('pa_gratis', 0) = 0 then raise exception 'PA insuficiente: buscar Pokémon custa 1 PA.'; end if;
  v_sel := public._selvagem(v_o.especie_id, v_o.nivel);
  delete from public.ofertas where jogador = v_j.id;
  update public.jogadores set pa = pa - case when public._ev('pa_gratis', 0) > 0 then 0 else 1 end where id = v_j.id;
  insert into public.batalhas (jogador, selvagem, ativo) values (v_j.id, v_sel, v_ativo) returning * into v_b;
  insert into public.pokedex (jogador, especie_id) values (v_j.id, v_o.especie_id) on conflict do nothing;
  return public._resultado(v_b.id, jsonb_build_array(jsonb_build_object('t', 'apareceu', 'nome', v_sel->>'nome', 'nivel', v_o.nivel)));
end $$;

create or replace function public._novo_pokemon(p_dono uuid, p_esp int, p_nivel int, p_golpes jsonb default null)
returns public.pokemons language plpgsql security definer set search_path = public as $$
declare
  e public.especies; nat text; v public.pokemons;
  ih int := floor(random()*32); ia int := floor(random()*32); id_ int := floor(random()*32);
  isa int := floor(random()*32); isd int := floor(random()*32); ise int := floor(random()*32);
  slot int;
  br boolean := random() < least(1, coalesce((select (valor #>> '{}')::numeric from public.config where chave = 'chance_brilhante'), 0.004) * public._ev('brilhante', 1));
begin
  select * into e from public.especies where id = p_esp;
  if not found then raise exception 'Espécie desconhecida.'; end if;
  select nome into nat from public.naturezas order by random() limit 1;
  nat := coalesce(nat, 'hardy');
  select min(s) into slot from generate_series(1,6) s where not exists (select 1 from public.pokemons where dono = p_dono and posicao = s);
  insert into public.pokemons (dono, especie_id, nivel, exp, natureza, iv_hp, iv_atk, iv_def, iv_spa, iv_spd, iv_spe,
      hp_max, atk, def, spa, spd, spe, hp_atual, golpes, posicao, brilhante)
  values (p_dono, p_esp, p_nivel, public.exp_para(p_nivel), nat, ih, ia, id_, isa, isd, ise,
      public.calc_hp(e.hp, ih, p_nivel),
      public.calc_stat(e.atk, ia, p_nivel, public.mult_nat(nat, 'attack')),
      public.calc_stat(e.def, id_, p_nivel, public.mult_nat(nat, 'defense')),
      public.calc_stat(e.spa, isa, p_nivel, public.mult_nat(nat, 'sp_attack')),
      public.calc_stat(e.spd, isd, p_nivel, public.mult_nat(nat, 'sp_defense')),
      public.calc_stat(e.spe, ise, p_nivel, public.mult_nat(nat, 'speed')),
      public.calc_hp(e.hp, ih, p_nivel),
      coalesce(p_golpes, public.golpes_do_nivel(p_esp, p_nivel)), slot, br)
  returning * into v;
  insert into public.pokedex (jogador, especie_id, capturado) values (p_dono, p_esp, true)
  on conflict (jogador, especie_id) do update set capturado = true;
  return v;
end $$;

revoke all on function public._novo_pokemon(uuid,int,int,jsonb) from public, anon, authenticated;
revoke all on function public._dar_exp(public.pokemons, jsonb, jsonb) from public, anon, authenticated;
revoke all on function public.sim_gravar(uuid,int,jsonb,jsonb,int,jsonb,text,jsonb) from public, anon, authenticated;
grant execute on function public.sim_gravar(uuid,int,jsonb,jsonb,int,jsonb,text,jsonb) to service_role;
grant execute on function public.gerar_oferta() to authenticated;
grant execute on function public.procurar_pokemon() to authenticated;

-- viagem livre (Mapa Mundi): qualquer lugar, exceto interiores; o Platô Prisma segue exigindo 8 insígnias
create or replace function public.viajar(p_mapa text)
returns public.jogadores language plpgsql security definer set search_path = public as $$
declare
  v_j public.jogadores; v_m public.mapas; v_x int; v_y int; v_dir text := 'baixo';
begin
  if auth.uid() is null then raise exception 'Faça login primeiro.'; end if;
  select * into v_j from public.jogadores where id = auth.uid() for update;
  if not found then raise exception 'Crie seu personagem primeiro.'; end if;
  if exists (select 1 from public.batalhas where jogador = v_j.id and estado = 'ativa') then
    raise exception 'Termine a batalha primeiro.';
  end if;
  select * into v_m from public.mapas where id = p_mapa;
  if not found or v_m.tipo <> 'andavel' or v_m.solido is null then raise exception 'Destino inválido.'; end if;
  if v_j.mapa_id = p_mapa then raise exception 'Você já está aqui.'; end if;
  if v_j.papel <> 'mestre' then
    if p_mapa like 'gin\_%' or p_mapa like 'liga\_%' or p_mapa = 'lab' then
      raise exception 'Este lugar não aceita viagem rápida.';
    end if;
    if p_mapa = 'plato' and coalesce(array_length(v_j.insignias, 1), 0) < 8 then
      raise exception 'O Platô Prisma (Liga) só abre para quem tem 8 insígnias (você tem %).', coalesce(array_length(v_j.insignias, 1), 0);
    end if;
  end if;
  select (p->>'dx')::int, (p->>'dy')::int, coalesce(p->>'dir', 'baixo') into v_x, v_y, v_dir
    from public.mapas o, jsonb_array_elements(o.portais) p
   where p->>'dest' = p_mapa and o.id <> p_mapa
   order by o.id limit 1;
  if v_x is null and v_m.spawn_x is not null and substr(v_m.solido, v_m.spawn_y * v_m.largura + v_m.spawn_x + 1, 1) = '0' then
    v_x := v_m.spawn_x; v_y := v_m.spawn_y;
  end if;
  if v_x is null then raise exception 'Este lugar ainda não tem ponto de chegada.'; end if;
  delete from public.ofertas where jogador = v_j.id;
  update public.jogadores set mapa_id = p_mapa, x = v_x, y = v_y, direcao = v_dir, posicao_em = clock_timestamp()
   where id = v_j.id returning * into v_j;
  return v_j;
end;
$$;
grant execute on function public.viajar(text) to authenticated;

create or replace function public.mapa_mundi()
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_j public.jogadores;
begin
  if auth.uid() is null then raise exception 'Faça login primeiro.'; end if;
  select * into v_j from public.jogadores where id = auth.uid();
  if not found then raise exception 'Crie seu personagem primeiro.'; end if;
  return jsonb_build_object('atual', v_j.mapa_id, 'mestre', v_j.papel = 'mestre', 'insignias', coalesce(array_length(v_j.insignias, 1), 0));
end;
$$;
grant execute on function public.mapa_mundi() to authenticated;
