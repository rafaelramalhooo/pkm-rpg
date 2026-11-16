-- m56: Centro Pokémon (a partir de Argila, depois da Rota 2) reseta os golpes de um Pokémon por dinheiro.
-- Preço: config 'golpes_reset_preco' (padrão 1000 por Pokémon). Servidor valida tudo.
create or replace function public.golpes_reset_info(p_pokemon uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare pk public.pokemons;
begin
  if auth.uid() is null then raise exception 'Faça login primeiro.'; end if;
  select * into pk from public.pokemons where id = p_pokemon and dono = auth.uid();
  if not found then raise exception 'Pokémon não encontrado.'; end if;
  return jsonb_build_object(
    'preco', public._cfg_int('golpes_reset_preco', 1000),
    'padrao', coalesce((select jsonb_agg(x->'id') from jsonb_array_elements(public.golpes_do_nivel(pk.especie_id, pk.nivel)) x), '[]'::jsonb),
    'pool', coalesce((select jsonb_agg(t.golpe_id order by t.nivel desc, t.golpe_id) from (
              select a.golpe_id, max(a.nivel) as nivel from public.aprende a
               where a.especie_id = pk.especie_id and a.nivel <= pk.nivel group by a.golpe_id) t), '[]'::jsonb));
end $$;
revoke all on function public.golpes_reset_info(uuid) from public, anon;
grant execute on function public.golpes_reset_info(uuid) to authenticated;

create or replace function public.golpes_resetar(p_pokemon uuid, p_golpes int[] default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_j public.jogadores; pk public.pokemons; preco int := public._cfg_int('golpes_reset_preco', 1000); novos jsonb; n int;
begin
  if auth.uid() is null then raise exception 'Faça login primeiro.'; end if;
  select * into v_j from public.jogadores where id = auth.uid() for update;
  if not found then raise exception 'Crie seu personagem primeiro.'; end if;
  if exists (select 1 from public.batalhas where jogador = v_j.id and estado = 'ativa') then raise exception 'Termine a batalha primeiro.'; end if;
  if not public._poi_aqui(v_j, 'centro') then raise exception 'O reset de golpes é feito no balcão de um Centro Pokémon.'; end if;
  if v_j.mapa_id in ('pallet', 'porto') then raise exception 'Este serviço só existe nos Centros Pokémon a partir de Argila.'; end if;
  select * into pk from public.pokemons where id = p_pokemon and dono = v_j.id for update;
  if not found then raise exception 'Pokémon não encontrado.'; end if;
  if v_j.dinheiro < preco then raise exception 'Dinheiro insuficiente (precisa de ₽ %).', preco; end if;
  if p_golpes is null or coalesce(array_length(p_golpes, 1), 0) = 0 then
    novos := public.golpes_do_nivel(pk.especie_id, pk.nivel);
  else
    n := array_length(p_golpes, 1);
    if n > 4 then raise exception 'Escolha no máximo 4 golpes.'; end if;
    if (select count(distinct x) from unnest(p_golpes) x) <> n then raise exception 'Golpes repetidos.'; end if;
    if exists (select 1 from unnest(p_golpes) x where not exists (select 1 from public.aprende a where a.especie_id = pk.especie_id and a.golpe_id = x and a.nivel <= pk.nivel)) then
      raise exception 'Este Pokémon não aprende um dos golpes escolhidos neste nível.';
    end if;
    novos := (select jsonb_agg(jsonb_build_object('id', g.id, 'pp', g.pp) order by o.ord) from unnest(p_golpes) with ordinality o (id, ord) join public.golpes g on g.id = o.id);
  end if;
  if jsonb_array_length(novos) = 0 then raise exception 'Este Pokémon ainda não tem golpes para aprender.'; end if;
  update public.pokemons set golpes = novos where id = pk.id;
  delete from public.golpes_pendentes where pokemon = pk.id;
  update public.jogadores set dinheiro = dinheiro - preco where id = v_j.id;
  return jsonb_build_object('dinheiro', v_j.dinheiro - preco, 'golpes', novos, 'preco', preco);
end $$;
revoke all on function public.golpes_resetar(uuid, int[]) from public, anon;
grant execute on function public.golpes_resetar(uuid, int[]) to authenticated;
