-- m31: efeitos das habilidades de classe (Treinador, Criador, Pesquisador) + bônus usados pelo motor de batalha.

create or replace function public._pa_bonus(p_j uuid) returns int language sql stable security definer set search_path = public as $$
  select floor(public._bonus(p_j, 'resistencia') + public._bonus(p_j, 'provocacao') + public._bonus(p_j, 'intuicao'))::int $$;
revoke all on function public._pa_bonus(uuid) from public, anon, authenticated;

-- bônus de combate lidos pela Edge Function (só service_role)
create or replace function public.sim_bonus(p_jogador uuid) returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object('instinto', public._bonus(p_jogador, 'instinto'), 'foco', public._bonus(p_jogador, 'foco'),
    'campeao', public._bonus(p_jogador, 'campeao'), 'captura', public._bonus(p_jogador, 'captura')) $$;
revoke all on function public.sim_bonus(uuid) from public, anon, authenticated;
grant execute on function public.sim_bonus(uuid) to service_role;

create or replace function public._vaga_caixa(p_dono uuid, out o_caixa int, out o_slot int)
language plpgsql security definer set search_path = public as $$
begin
  select c, s into o_caixa, o_slot
    from generate_series(1, public._cfg_int('qtd_caixas', 2)) c, generate_series(1, (public._cfg_int('tam_caixa', 15) + floor(public._bonus(p_dono, 'espaco'))::int)) s
   where not exists (select 1 from public.pokemons where dono = p_dono and caixa = c and slot_caixa = s)
   order by c, s limit 1;
end $$;

create or replace function public.config_caixas() returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('qtd', public._cfg_int('qtd_caixas', 2), 'tam', public._cfg_int('tam_caixa', 15) + floor(public._bonus(auth.uid(), 'espaco'))::int) $$;

create or replace function public.caixa_mover(p_pokemon uuid, p_caixa int, p_slot int) returns void
language plpgsql security definer set search_path = public as $$
declare a public.pokemons; b public.pokemons;
begin
  perform public._caixa_pre();
  if p_caixa < 1 or p_caixa > public._cfg_int('qtd_caixas', 2) or p_slot < 1 or p_slot > public._cfg_int('tam_caixa', 15) + floor(public._bonus(auth.uid(), 'espaco'))::int then raise exception 'Espaço inválido.'; end if;
  select * into a from public.pokemons where id = p_pokemon and dono = auth.uid() and caixa is not null for update;
  if not found then raise exception 'Esse Pokémon não está numa caixa.'; end if;
  select * into b from public.pokemons where dono = auth.uid() and caixa = p_caixa and slot_caixa = p_slot for update;
  if b.id is not null and b.id = a.id then return; end if;
  if b.id is not null then
    update public.pokemons set caixa = null, slot_caixa = null where id = b.id;
    update public.pokemons set caixa = p_caixa, slot_caixa = p_slot where id = a.id;
    update public.pokemons set caixa = a.caixa, slot_caixa = a.slot_caixa where id = b.id;
  else
    update public.pokemons set caixa = p_caixa, slot_caixa = p_slot where id = a.id;
  end if;
end $$;

create or replace function public._novo_pokemon(p_dono uuid, p_esp int, p_nivel int, p_golpes jsonb default null, p_brilhante boolean default null)
returns public.pokemons language plpgsql security definer set search_path = public as $$
declare
  e public.especies; nat text; v public.pokemons;
  ih int := floor(random()*32); ia int := floor(random()*32); id_ int := floor(random()*32);
  isa int := floor(random()*32); isd int := floor(random()*32); ise int := floor(random()*32);
  slot int; vc int; vs int;
  br boolean := coalesce(p_brilhante, random() < least(1, (coalesce((select (valor #>> '{}')::numeric from public.config where chave = 'chance_brilhante'), 0.004) + public._bonus(p_dono, 'olho_brilhante') / 100.0) * public._ev('brilhante', 1)));
begin
  select * into e from public.especies where id = p_esp;
  if not found then raise exception 'Espécie desconhecida.'; end if;
  select nome into nat from public.naturezas order by random() limit 1;
  nat := coalesce(nat, 'hardy');
  select min(s) into slot from generate_series(1,6) s where not exists (select 1 from public.pokemons where dono = p_dono and posicao = s);
  if slot is null then
    select o_caixa, o_slot into vc, vs from public._vaga_caixa(p_dono);
    if vc is null then raise exception 'Suas caixas estão cheias! Abra espaço no Centro Pokémon ou no Laboratório do Prof. Carvalho antes de capturar.'; end if;
  end if;
  insert into public.pokemons (dono, especie_id, nivel, exp, natureza, iv_hp, iv_atk, iv_def, iv_spa, iv_spd, iv_spe,
      hp_max, atk, def, spa, spd, spe, hp_atual, golpes, posicao, brilhante, caixa, slot_caixa)
  values (p_dono, p_esp, p_nivel, public.exp_para(p_nivel), nat, ih, ia, id_, isa, isd, ise,
      public.calc_hp(e.hp, ih, p_nivel),
      public.calc_stat(e.atk, ia, p_nivel, public.mult_nat(nat, 'attack')),
      public.calc_stat(e.def, id_, p_nivel, public.mult_nat(nat, 'defense')),
      public.calc_stat(e.spa, isa, p_nivel, public.mult_nat(nat, 'sp_attack')),
      public.calc_stat(e.spd, isd, p_nivel, public.mult_nat(nat, 'sp_defense')),
      public.calc_stat(e.spe, ise, p_nivel, public.mult_nat(nat, 'speed')),
      public.calc_hp(e.hp, ih, p_nivel),
      coalesce(p_golpes, public.golpes_do_nivel(p_esp, p_nivel)), slot, br, vc, vs)
  returning * into v;
  insert into public.pokedex (jogador, especie_id, capturado) values (p_dono, p_esp, true)
  on conflict (jogador, especie_id) do update set capturado = true;
  return v;
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
  v_sel := v_sel || jsonb_build_object('brilhante', random() < least(1, (coalesce((select (valor #>> '{}')::numeric from public.config where chave = 'chance_brilhante'), 0.004) + public._bonus(v_j.id, 'olho_brilhante') / 100.0) * public._ev('brilhante', 1)));
  delete from public.ofertas where jogador = v_j.id;
  update public.jogadores set pa = pa - case when public._ev('pa_gratis', 0) > 0 then 0 else 1 end where id = v_j.id;
  insert into public.batalhas (jogador, selvagem, ativo) values (v_j.id, v_sel, v_ativo) returning * into v_b;
  insert into public.pokedex (jogador, especie_id) values (v_j.id, v_o.especie_id) on conflict do nothing;
  return public._resultado(v_b.id, jsonb_build_array(jsonb_build_object('t', 'apareceu', 'nome', v_sel->>'nome', 'nivel', v_o.nivel)));
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
        update public.jogadores set dinheiro = dinheiro + floor(t.recompensa * public._ev('dinheiro', 1) * (1 + public._bonus(b.jogador, 'recompensa') / 100.0)) where id = b.jogador;
        ev := ev || jsonb_build_array(jsonb_build_object('t', 'dinheiro', 'valor', floor(t.recompensa * public._ev('dinheiro', 1) * (1 + public._bonus(b.jogador, 'recompensa') / 100.0)), 'nome', t.nome));
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
      -- Cura Rápida: recupera uma parte do HP de quem lutou
      if public._bonus(b.jogador, 'cura_rapida') > 0 then
        update public.pokemons set hp_atual = least(hp_max, hp_atual + ceil(hp_max * public._bonus(b.jogador, 'cura_rapida') / 100.0)::int)
         where id = any(coalesce(part, '{}')) and dono = b.jogador and hp_atual > 0;
      end if;
    end if;
  end if;
  return ev;
end $$;

create or replace function public.acao_treinar(p_pokemon uuid) returns jsonb language plpgsql security definer set search_path = public as $$
declare pk public.pokemons; ev jsonb; xp int; ant int;
begin
  select * into pk from public.pokemons where id = p_pokemon and dono = auth.uid();
  if not found then raise exception 'Pokémon não encontrado.'; end if;
  perform public._gastar_pa(auth.uid());
  perform public._criador_mestre(auth.uid());
  xp := floor((25 + public._bonus(auth.uid(), 'mestre_treino')) * (1 + public._bonus(auth.uid(), 'treino_intenso') / 100.0))::int;
  ant := pk.nivel;
  ev := public._dar_exp(pk, jsonb_build_object('exp_base', 7, 'nivel', xp), '[]'::jsonb);  -- _dar_exp aplica o multiplicador de evento
  return jsonb_build_object('eventos', ev, 'pa', (select pa from public.jogadores where id = auth.uid()));
end $$;

-- Criador Mestre: a cada 3 usos de Treinar/Cuidar no dia, o terceiro não gasta PA
create or replace function public._criador_mestre(p_j uuid) returns void language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if public._rank(p_j, 'criador_mestre') < 1 then return; end if;
  insert into public.acoes_dia (jogador, chave, n) values (p_j, 'criador_mestre', 1) on conflict (jogador, dia, chave) do update set n = public.acoes_dia.n + 1 returning acoes_dia.n into n;
  if n % 3 = 0 then update public.jogadores set pa = pa + 1 where id = p_j; end if;
end $$;
revoke all on function public._criador_mestre(uuid) from public, anon, authenticated;

create or replace function public.acao_cuidar(p_pokemon uuid) returns jsonb language plpgsql security definer set search_path = public as $$
declare pk public.pokemons; ev jsonb := '[]'::jsonb; xp int;
begin
  select * into pk from public.pokemons where id = p_pokemon and dono = auth.uid();
  if not found then raise exception 'Pokémon não encontrado.'; end if;
  perform public._uso_dia(auth.uid(), 'cuidar:' || p_pokemon, 3 + floor(public._bonus(auth.uid(), 'afeto'))::int);
  perform public._gastar_pa(auth.uid());
  perform public._criador_mestre(auth.uid());
  update public.pokemons set amizade = least(255, amizade + 1 + floor(public._bonus(auth.uid(), 'lideranca'))::int),
    hp_atual = case when hp_atual > 0 then least(hp_max, hp_atual + ceil(hp_max * public._bonus(auth.uid(), 'mao_amiga') / 100.0)::int) else hp_atual end where id = p_pokemon;
  xp := floor(public._bonus(auth.uid(), 'alimentador'))::int;
  if xp > 0 then ev := public._dar_exp(pk, jsonb_build_object('exp_base', 7, 'nivel', xp), '[]'::jsonb); end if;
  return jsonb_build_object('amizade', least(255, pk.amizade + 1 + floor(public._bonus(auth.uid(), 'lideranca'))::int), 'eventos', ev, 'pa', (select pa from public.jogadores where id = auth.uid()));
end $$;

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
  if random() < public._bonus(auth.uid(), 'cientista') / 10.0 then xp := xp * 2; din := din * 2; end if;  -- Cientista: às vezes rende o dobro
  perform public._ganhar_xp_treino(auth.uid(), xp);
  update public.jogadores set dinheiro = dinheiro + din + extra where id = auth.uid();
  return jsonb_build_object('xp', xp, 'dinheiro', din + extra, 'pesquisadas', n, 'bonus', extra > 0);
end $$;

create or replace function public.acao_explorar() returns jsonb language plpgsql security definer set search_path = public as $$
declare j public.jogadores; r numeric := random(); mult numeric; din int; item text; res jsonb;
begin
  select * into j from public.jogadores where id = auth.uid();
  if not found then raise exception 'Crie seu personagem primeiro.'; end if;
  if j.mapa_id in ('lab') then raise exception 'Não há o que explorar aqui.'; end if;
  perform public._uso_dia(j.id, 'explorar:' || j.mapa_id || ':' || j.x || ':' || j.y, 1);
  perform public._gastar_pa(j.id);
  mult := (1 + public._bonus(j.id, 'exploracao') / 100.0) * case when random() < public._bonus(j.id, 'cientista') / 10.0 then 2 else 1 end;  -- Cientista: às vezes o dobro
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
  -- PA extra: cada rank dessas habilidades dá os PA na hora (e de novo a cada evento de PA extra)
  if p_hab in ('resistencia', 'provocacao', 'intuicao') then
    update public.jogadores set pa = least(32000, pa + (select bonus::int from public.habilidades_catalogo where id = p_hab)) where id = j.id;
  end if;
  return public.estado_treino();
end $$;

create or replace function public.criar_evento(p_tipo text, p_valor numeric, p_minutos int default null, p_mensagem text default null, p_fim timestamptz default null, p_inicio timestamptz default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_j public.jogadores; v_e public.eventos; v_ini timestamptz; v_fim timestamptz;
begin
  if auth.uid() is null then raise exception 'Faça login primeiro.'; end if;
  select * into v_j from public.jogadores where id = auth.uid();
  if not found or v_j.papel <> 'mestre' then raise exception 'Só o Mestre cria eventos.'; end if;
  if p_tipo not in ('xp', 'dinheiro', 'brilhante', 'encontro', 'pa_gratis', 'loja_desconto', 'pa_extra') then raise exception 'Tipo de evento inválido.'; end if;
  if p_valor is null or p_valor <= 0 or p_valor > 1000 then raise exception 'Valor inválido (use um número entre 0,1 e 1000).'; end if;
  if p_tipo = 'loja_desconto' and p_valor > 90 then raise exception 'O desconto máximo é 90%%.'; end if;
  v_ini := case when p_inicio is null or p_inicio < now() + interval '1 minute' then now() else p_inicio end;
  if v_ini > now() + interval '90 days' then raise exception 'O início pode ser no máximo daqui a 90 dias.'; end if;
  if p_tipo = 'pa_extra' and v_ini > now() then raise exception 'PA extra é entregue na hora: não pode ser agendado.'; end if;
  v_fim := coalesce(p_fim, v_ini + make_interval(mins => coalesce(p_minutos, 0)));
  if v_fim <= v_ini then raise exception 'O fim do evento precisa ser depois do início.'; end if;
  if v_fim > v_ini + interval '30 days' then raise exception 'Duração máxima: 30 dias.'; end if;
  insert into public.eventos (tipo, valor, mensagem, inicio, fim, criado_por)
  values (p_tipo, p_valor, nullif(btrim(coalesce(p_mensagem, '')), ''), v_ini, v_fim, v_j.id) returning * into v_e;
  if p_tipo = 'pa_extra' then update public.jogadores set pa = least(32000, pa + floor(p_valor)::int + public._pa_bonus(id)) where conta is null; end if;
  return to_jsonb(v_e);
end $$;

create or replace function public.comprar_item(p_poi text, p_item text, p_qtd int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_j public.jogadores; v_p jsonb; v_e jsonb; v_total int; v_desc numeric;
begin
  if auth.uid() is null then raise exception 'Faça login primeiro.'; end if;
  if p_qtd is null or p_qtd < 1 or p_qtd > 99 + floor(public._bonus(auth.uid(), 'mochila'))::int then raise exception 'Quantidade inválida.'; end if;
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

-- Mapa Mental: ao mudar de mapa, chance de achar um trocado no caminho
create or replace function public._tg_mapa_mental() returns trigger language plpgsql security definer set search_path = public as $$
declare r int;
begin
  if new.mapa_id is distinct from old.mapa_id then
    r := public._rank(new.id, 'mapa_mental');
    if r > 0 and random() < 0.05 * r then new.dinheiro := new.dinheiro + 50 + floor(random() * 100)::int; end if;
  end if;
  return new;
end $$;
drop trigger if exists tg_mapa_mental on public.jogadores;
create trigger tg_mapa_mental before update of mapa_id on public.jogadores for each row execute function public._tg_mapa_mental();

-- descrições (sem "em breve" nas que passaram a funcionar)
update public.habilidades_catalogo g set descricao = v.d, ativo = true from (values
 ('instinto','+2% de dano dos seus Pokémon por rank (Ataque e Ataque Esp. em batalha).'),
 ('recompensa','+10% de dinheiro ganho em batalhas de treinador por rank.'),
 ('resistencia','+2 de PA por rank, na hora e a cada evento de PA extra.'),
 ('foco','+3% de precisão nos golpes por rank (batalhas contra treinador e selvagens).'),
 ('cura_rapida','Cura 5% do HP dos Pokémon que lutaram após cada vitória, por rank.'),
 ('lideranca','+1 de amizade ao Cuidar por rank.'),
 ('provocacao','+3 de PA por rank, na hora e a cada evento de PA extra.'),
 ('veterano','+5% de experiência dos Pokémon por rank.'),
 ('campeao','+3% em todos os atributos dos Pokémon em batalha, por rank.'),
 ('mao_amiga','Cuidar também cura 10% do HP por rank.'),
 ('olho_brilhante','+0,1% de chance de Pokémon brilhante por rank.'),
 ('ovos','Libera o sistema de ovos quando ele existir (ainda em breve).'),
 ('laco','Pokémon com amizade 150 ou mais ganham +2% de experiência por rank.'),
 ('espaco','+5 espaços por caixa por rank.'),
 ('banco_dados','Na Pokédex, mostra os atributos e a natureza dos seus Pokémon capturados.'),
 ('criador_mestre','A cada 3 usos de Treinar/Cuidar no dia, o terceiro não gasta PA.'),
 ('captura','+3% de chance de captura por rank.'),
 ('mochila','+10 unidades por compra por rank (limite normal: 99).'),
 ('mapa_mental','5% de chance por rank de achar ₽ 50 a 150 ao mudar de mapa.'),
 ('intuicao','+3 de PA por rank, na hora e a cada evento de PA extra.'),
 ('cientista','Pesquisar e Explorar rendem o dobro em 10% das vezes por rank.')
) as v(id, d) where g.id = v.id;
