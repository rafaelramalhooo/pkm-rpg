-- m55: mais encontros (cidade até 6%, estrada 22%, grama 55%) e Pokédex de lendários/pseudo-lendários (144–151) zerada para quem não os tem
do $$
declare d text;
begin
  d := replace(pg_get_functiondef('public.gerar_oferta()'::regprocedure), 'least(v_m.chance_oferta, 3)', 'least(v_m.chance_oferta, 6)');
  if d not like '%least(v_m.chance_oferta, 6)%' then raise exception 'gerar_oferta não foi alterada'; end if;
  execute d;
end $$;
update public.config set valor = '{"grama": 55, "floresta": 40, "campo": 25, "agua": 22, "estrada": 22}'::jsonb where chave = 'chance_bioma';
delete from public.pokedex d where d.especie_id between 144 and 151 and not exists (select 1 from public.pokemons p where p.dono = d.jogador and p.especie_id = d.especie_id);
