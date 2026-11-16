-- m54: criar/trocar personagem falhava com duplicate key em mapas_visitados (o gatilho de visita já criava a linha no destino)
create or replace function public._filhos_mover(p_de uuid, p_para uuid) returns void language plpgsql security definer set search_path = public as $$
declare r record;
begin
  delete from public.mapas_visitados where jogador = p_para;
  for r in
    select c.conrelid::regclass::text as tabela, a.attname::text as coluna
      from pg_constraint c join pg_attribute a on a.attrelid = c.conrelid and a.attnum = c.conkey[1]
     where c.contype = 'f' and c.confrelid = 'public.jogadores'::regclass and array_length(c.conkey, 1) = 1
  loop
    execute format('update %s set %I = $1 where %I = $2', r.tabela, r.coluna, r.coluna) using p_para, p_de;
  end loop;
end $$;
