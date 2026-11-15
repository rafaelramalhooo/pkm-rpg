-- m36b: curar o time conta como atividade (Conquistas / mini-quests).
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
  perform public._atividade(v_j.id, 'cura', null);
  return n;
end $$;
