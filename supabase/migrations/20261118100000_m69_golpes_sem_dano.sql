-- m69: Pokémon que só têm golpes de status no nível (ex.: Magikarp abaixo do 15) ficavam sem golpes e a batalha falhava
-- ("Set Magikarp has no moves"). Agora, se não há golpe de dano disponível, entram os de status.
create or replace function public.golpes_do_nivel(p_esp int, p_nivel int) returns jsonb language sql stable as $$
  with base as (
    select distinct on (a.golpe_id) a.golpe_id, g.pp, a.nivel, coalesce(g.poder, 0) > 0 as dano
      from public.aprende a join public.golpes g on g.id = a.golpe_id
     where a.especie_id = p_esp and a.nivel <= p_nivel
     order by a.golpe_id, a.nivel desc
  ), tem as (select exists (select 1 from base where dano) as d)
  select coalesce(jsonb_agg(jsonb_build_object('id', t.golpe_id, 'pp', t.pp) order by t.rn), '[]'::jsonb)
    from (select b.golpe_id, b.pp, row_number() over (order by b.nivel desc, b.golpe_id) rn from base b, tem where b.dano or not tem.d) t
   where t.rn <= 4 $$;

-- Pokémon que ficaram sem nenhum golpe recebem os golpes do nível
update public.pokemons set golpes = public.golpes_do_nivel(especie_id, nivel)
 where jsonb_array_length(golpes) = 0 and jsonb_array_length(public.golpes_do_nivel(especie_id, nivel)) > 0;
