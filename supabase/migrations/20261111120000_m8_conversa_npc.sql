-- M8: NPCs só falam quando o jogador puxa conversa (adjacente) e a prévia de encontro aparece mais rápido; chance 100%.
update public.config set valor = '100'::jsonb where chave = 'chance_oferta';

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
  values (v_j.id, '{}'::jsonb, v_ativo, 'treinador', v_t.id, public._equipe_treinador(v_t.equipe)) returning * into v_b;
  return jsonb_build_object('batalha', to_jsonb(v_b) - 'sim' - 'meta', 'treinador', jsonb_build_object('nome', v_t.nome, 'classe', v_t.classe));
end $$;

grant execute on function public.gerar_oferta(), public.desafiar_treinador(text) to authenticated;
