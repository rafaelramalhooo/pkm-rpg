-- m51: barra de atalhos (10 espaços) salva por conta
alter table public.jogadores add column if not exists atalhos jsonb not null default '[]'::jsonb;
create or replace function public.atalhos_salvar(p_atalhos jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare x jsonb; n int := 0;
begin
  if auth.uid() is null then raise exception 'Faça login primeiro.'; end if;
  if p_atalhos is null or jsonb_typeof(p_atalhos) <> 'array' or jsonb_array_length(p_atalhos) > 10 then raise exception 'Atalhos inválidos.'; end if;
  for x in select * from jsonb_array_elements(p_atalhos) loop
    if jsonb_typeof(x) not in ('string','null') or (jsonb_typeof(x) = 'string' and length(x #>> '{}') > 60) then raise exception 'Atalho inválido.'; end if;
    n := n + 1;
  end loop;
  update public.jogadores set atalhos = p_atalhos where id = auth.uid();
end $$;
revoke all on function public.atalhos_salvar(jsonb) from public, anon;
grant execute on function public.atalhos_salvar(jsonb) to authenticated;
