-- Mestre: depois de trocar os mapas, move para o ponto inicial quem ficou em cima de um bloqueio ou fora do mapa.
create or replace function public.corrigir_posicoes()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare n int;
begin
  if not public.eh_mestre() then raise exception 'Só o Mestre.'; end if;
  update public.jogadores j
     set mapa_id = 'pallet', x = (select spawn_x from public.mapas where id = 'pallet'), y = (select spawn_y from public.mapas where id = 'pallet'),
         direcao = 'baixo', posicao_em = now()
   where not exists (select 1 from public.mapas m where m.id = j.mapa_id and m.solido is not null)
      or exists (
        select 1 from public.mapas m
         where m.id = j.mapa_id
           and (j.x < 0 or j.y < 0 or j.x >= m.largura or j.y >= m.altura
                or substr(m.solido, j.y * m.largura + j.x + 1, 1) = '1'));
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function public.corrigir_posicoes() from public, anon;
grant execute on function public.corrigir_posicoes() to authenticated;
