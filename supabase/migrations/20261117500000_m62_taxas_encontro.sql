-- m62: taxas de encontro maiores em todos os pisos; cidades até 10%; cavernas e montanhas com taxa própria por mapa (config 'chance_mapa')
do $$
declare d text;
begin
  d := pg_get_functiondef('public.gerar_oferta()'::regprocedure);
  d := replace(d, 'least(v_m.chance_oferta, 6)', 'least(v_m.chance_oferta, 10)');
  d := replace(d, 'else coalesce((select (valor ->> v_bioma)::int from public.config where chave = ''chance_bioma''), 30) end;',
                  'else coalesce((select (valor ->> v_j.mapa_id)::int from public.config where chave = ''chance_mapa''), (select (valor ->> v_bioma)::int from public.config where chave = ''chance_bioma''), 30) end;');
  if d not like '%least(v_m.chance_oferta, 10)%' or d not like '%chave = ''chance_mapa''%' then raise exception 'gerar_oferta não foi alterada'; end if;
  execute d;
end $$;
update public.config set valor = '{"grama": 65, "floresta": 55, "campo": 45, "agua": 40, "estrada": 40}'::jsonb where chave = 'chance_bioma';
insert into public.config (chave, valor) values ('chance_mapa', '{"gruta": 55, "plato": 50, "vale": 50}'::jsonb)
on conflict (chave) do update set valor = excluded.valor;
