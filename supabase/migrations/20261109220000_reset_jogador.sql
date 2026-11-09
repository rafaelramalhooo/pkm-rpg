-- Mestre: devolve um jogador ao começo (Pallet Town, sem Pokémon, itens, Pokédex ou batalha; PA e dinheiro cheios).
create or replace function public.resetar_jogador(p_jogador uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare v_nome text; v_m public.mapas;
begin
  if not public.eh_mestre() then raise exception 'Só o Mestre pode resetar jogadores.'; end if;
  select nome into v_nome from public.jogadores where id = p_jogador;
  if not found then raise exception 'Jogador não encontrado.'; end if;
  select * into v_m from public.mapas where id = 'pallet';
  delete from public.batalhas where jogador = p_jogador;
  delete from public.pokemons where dono = p_jogador;
  delete from public.inventario where jogador = p_jogador;
  delete from public.pokedex where jogador = p_jogador;
  update public.jogadores
     set mapa_id = 'pallet', x = coalesce(v_m.spawn_x, 16), y = coalesce(v_m.spawn_y, 21), direcao = 'baixo',
         pa = coalesce((select (valor #>> '{}')::smallint from public.config where chave = 'pa_por_dia'), 30),
         dinheiro = 1000, posicao_em = now()
   where id = p_jogador;
  insert into public.auditoria (ator, acao, detalhe) values (auth.uid(), 'resetar_jogador', jsonb_build_object('jogador', p_jogador, 'nome', v_nome));
  return v_nome;
end $$;
revoke all on function public.resetar_jogador(uuid) from public, anon;
grant execute on function public.resetar_jogador(uuid) to authenticated;
