-- m63 (Lote B): Vara de Pesca + pescar em qualquer água.
-- Pescar exige a Vara de Pesca no inventário e água ao lado (tile 'A' do bioma). Custa 1 PA.
-- Sorteia: Pokémon aquático (lista 'agua' do mapa; a luta já está paga), item ou nada.
alter table public.ofertas add column if not exists gratis boolean not null default false;

insert into public.itens (slug, nome, categoria, efeito, arco) values
  ('old-rod', 'Vara de Pesca', 'gameplay', 'Permite pescar em qualquer lago, rio ou mar (1 PA por lançamento).', 1)
on conflict (slug) do update set nome = excluded.nome, efeito = excluded.efeito;

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
  if v_j.pa < 1 and not v_o.gratis and public._ev('pa_gratis', 0) = 0 then raise exception 'PA insuficiente: buscar Pokémon custa 1 PA.'; end if;
  v_sel := public._selvagem(v_o.especie_id, v_o.nivel);
  v_sel := v_sel || jsonb_build_object('brilhante', random() < least(1, (coalesce((select (valor #>> '{}')::numeric from public.config where chave = 'chance_brilhante'), 0.004) + public._bonus(v_j.id, 'olho_brilhante') / 100.0) * public._ev('brilhante', 1)));
  delete from public.ofertas where jogador = v_j.id;
  update public.jogadores set pa = pa - case when v_o.gratis or public._ev('pa_gratis', 0) > 0 then 0 else 1 end where id = v_j.id;
  insert into public.batalhas (jogador, selvagem, ativo) values (v_j.id, v_sel, v_ativo) returning * into v_b;
  insert into public.pokedex (jogador, especie_id) values (v_j.id, v_o.especie_id) on conflict do nothing;
  return public._resultado(v_b.id, jsonb_build_array(jsonb_build_object('t', 'apareceu', 'nome', v_sel->>'nome', 'nivel', v_o.nivel)));
end $$;
grant execute on function public.procurar_pokemon() to authenticated;

create or replace function public.acao_pescar() returns jsonb language plpgsql security definer set search_path = public as $$
declare
  j public.jogadores; m public.mapas; v_agua boolean := false; v_i int; v_nx int; v_ny int;
  v_b numeric; r numeric; v_total int; v_acc int := 0; v_r int; v_e record; v_nivel int; v_ref int; v_item text; din int; v_viva boolean;
begin
  if auth.uid() is null then raise exception 'Faça login primeiro.'; end if;
  select * into j from public.jogadores where id = auth.uid() for update;
  if not found then raise exception 'Crie seu personagem primeiro.'; end if;
  if exists (select 1 from public.batalhas where jogador = j.id and estado = 'ativa') then raise exception 'Termine a batalha primeiro.'; end if;
  if not exists (select 1 from public.inventario where jogador = j.id and item = 'old-rod' and qtd > 0) then
    raise exception 'Você precisa de uma Vara de Pesca. Procure nas lojas dos portos e feiras.';
  end if;
  select * into m from public.mapas where id = j.mapa_id;
  if m.bioma is not null then
    for v_i in 0..3 loop
      v_nx := j.x + (array[1, -1, 0, 0])[v_i + 1]; v_ny := j.y + (array[0, 0, 1, -1])[v_i + 1];
      if v_nx >= 0 and v_nx < m.largura and v_ny >= 0 and substr(m.bioma, v_ny * m.largura + v_nx + 1, 1) = 'A' then v_agua := true; end if;
    end loop;
  end if;
  if not v_agua then raise exception 'Chegue perto da água (lago, rio ou mar) para pescar.'; end if;
  perform public._gastar_pa(j.id);
  v_b := public._bonus(j.id, 'rede_pesca') / 100.0;
  r := random();
  v_viva := exists (select 1 from public.pokemons where dono = j.id and posicao is not null and hp_atual > 0);
  select coalesce(sum(peso), 0) into v_total from public.encontros where mapa_id = j.mapa_id and bioma = 'agua';
  if r < 0.40 + v_b and v_total > 0 and v_viva then
    v_r := floor(random() * v_total);
    for v_e in select * from public.encontros where mapa_id = j.mapa_id and bioma = 'agua' order by especie_id loop
      v_acc := v_acc + v_e.peso;
      if v_r < v_acc then exit; end if;
    end loop;
    v_ref := public._nivel_ref(j.id);
    v_nivel := least(v_e.nivel_min + floor(random() * (v_e.nivel_max - v_e.nivel_min + 1))::int, greatest(v_e.nivel_min, v_ref + 8));
    delete from public.ofertas where jogador = j.id;
    insert into public.ofertas (jogador, mapa_id, x, y, especie_id, nivel, bioma, gratis) values (j.id, j.mapa_id, j.x, j.y, v_e.especie_id, v_nivel, 'agua', true);
    perform public._ganhar_xp_treino(j.id, 10);
    return jsonb_build_object('tipo', 'pokemon', 'especie_id', v_e.especie_id, 'nome', (select nome from public.especies where id = v_e.especie_id), 'nivel', v_nivel);
  end if;
  if r < 0.40 + v_b + 0.25 then
    select s into v_item from unnest(array['potion','potion','poke-ball','poke-ball','great-ball','super-potion','antidote','awakening']) s
      where exists (select 1 from public.itens where slug = s) order by random() limit 1;
    if v_item is null then din := 200; update public.jogadores set dinheiro = dinheiro + din where id = j.id; return jsonb_build_object('tipo', 'dinheiro', 'valor', din); end if;
    insert into public.inventario (jogador, item, qtd) values (j.id, v_item, 1) on conflict (jogador, item) do update set qtd = public.inventario.qtd + 1;
    perform public._ganhar_xp_treino(j.id, 10);
    return jsonb_build_object('tipo', 'item', 'item', v_item, 'qtd', 1);
  end if;
  return jsonb_build_object('tipo', 'nada');
end $$;
grant execute on function public.acao_pescar() to authenticated;
