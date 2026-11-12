-- M9: cidades (Pallet Town e Viridian) têm chance menor de encontro (40%) e Pokémon de ambiente urbano.
alter table public.mapas add column if not exists chance_oferta smallint;   -- null = usa config.chance_oferta
update public.mapas set chance_oferta = 40 where id in ('pallet', 'viridian');

delete from public.encontros where mapa_id = 'viridian' or (mapa_id = 'pallet' and bioma <> 'agua');
insert into public.encontros (mapa_id, bioma, especie_id, peso, nivel_min, nivel_max)
select v.m, v.b, v.e, v.p, v.a, v.z from (values
  ('pallet','campo',19,35,2,4),
  ('pallet','campo',16,25,2,4),
  ('pallet','campo',52,20,2,4),
  ('pallet','campo',21,10,2,4),
  ('pallet','campo',81,5,2,4),
  ('pallet','campo',100,5,2,4),
  ('pallet','estrada',19,35,2,4),
  ('pallet','estrada',16,25,2,4),
  ('pallet','estrada',52,20,2,4),
  ('pallet','estrada',21,10,2,4),
  ('pallet','estrada',81,5,2,4),
  ('pallet','estrada',100,5,2,4),
  ('pallet','grama',19,40,2,4),
  ('pallet','grama',16,40,2,4),
  ('pallet','grama',52,20,2,4),
  ('pallet','floresta',16,40,2,4),
  ('pallet','floresta',19,35,2,4),
  ('pallet','floresta',21,15,2,4),
  ('pallet','floresta',52,10,2,4),
  ('viridian','campo',19,30,3,5),
  ('viridian','campo',52,20,3,5),
  ('viridian','campo',16,15,3,5),
  ('viridian','campo',21,10,3,5),
  ('viridian','campo',81,10,3,5),
  ('viridian','campo',100,5,3,5),
  ('viridian','campo',88,5,3,5),
  ('viridian','campo',109,5,3,5)
) as v(m, b, e, p, a, z)
where exists (select 1 from public.mapas where id = v.m) and exists (select 1 from public.especies where id = v.e)
on conflict (mapa_id, bioma, especie_id) do update set peso = excluded.peso, nivel_min = excluded.nivel_min, nivel_max = excluded.nivel_max;

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


grant execute on function public.gerar_oferta() to authenticated;
