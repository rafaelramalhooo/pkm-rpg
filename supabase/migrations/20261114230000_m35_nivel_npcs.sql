-- m35: níveis dos treinadores/ginásios/Liga em função da média do time do jogador (só quem está de pé).
-- Variação por Pokémon: -1 a +5 (comuns) e 0 a +3 (líderes de ginásio e Liga); no máximo UM -1 por equipe (1 chance em 3,
-- só equipes com 3+ Pokémon; o ás do líder e o Campeão nunca recebem -1). O piso de cada treinador continua valendo.
create or replace function public._nivel_ref(p_j uuid) returns int language sql stable security definer set search_path = public as $$
  select coalesce(
    (select round(avg(nivel))::int from public.pokemons where dono = p_j and posicao is not null and hp_atual > 0),
    (select round(avg(nivel))::int from public.pokemons where dono = p_j and posicao is not null),
    5) $$;

create or replace function public._equipe_escalada(t public.treinadores, p_ref int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  esc jsonb := t.escala; n int := coalesce((esc->>'time')::int, 3); bonus int := coalesce((esc->>'bonus')::int, 0);
  piso int := coalesce((esc->>'piso')::int, 1); dif int := public._dificuldade();
  var int := case when t.lider or t.id like 'liga\_%' then 3 else 5 end;
  ace jsonb := esc->'ace'; pool jsonb := esc->'pool'; k int; total int; lvl int; ent jsonb; usadas int[] := '{}'; res jsonb := '[]'::jsonb;
  menos int := 0; off int;
begin
  total := n - case when ace is not null then 1 else 0 end;
  if n >= 3 and t.id <> 'liga_campeao_chefe' and random() < 1.0 / 3 then menos := 1 + floor(random() * total)::int; end if;
  for k in 1 .. total loop
    off := case when k = menos then -1 else floor(random() * (var + 1))::int end;
    lvl := least(1000, greatest(piso, p_ref + bonus + dif + off));
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
    lvl := least(1000, greatest(piso, p_ref + (ace->>'bonus')::int + dif));
    res := res || public._equipe_treinador(jsonb_build_array(jsonb_build_object('especie', (ace->>'e')::int, 'nivel', lvl)));
  end if;
  return res;
end $$;
revoke all on function public._equipe_escalada(public.treinadores, int) from public, anon, authenticated;
