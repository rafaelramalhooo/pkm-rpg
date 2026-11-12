-- m18: usar itens de cura da mochila fora de batalha (Minhas Coisas). Validado no servidor.
create or replace function public.usar_item_fora(p_item text, p_pokemon uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare pk public.pokemons; cura int; novo int; revive boolean := false;
begin
  if auth.uid() is null then raise exception 'Faça login primeiro.'; end if;
  if exists (select 1 from public.batalhas where jogador = auth.uid() and estado = 'ativa') then raise exception 'Use os itens pelo menu da batalha.'; end if;
  select * into pk from public.pokemons where id = p_pokemon and dono = auth.uid() for update;
  if not found then raise exception 'Pokémon não encontrado.'; end if;
  cura := case p_item when 'potion' then 20 when 'super-potion' then 50 when 'hyper-potion' then 200 when 'max-potion' then 99999
                      when 'full-restore' then 99999 when 'revive' then -1 when 'max-revive' then -2 else null end;
  if cura is null then raise exception 'Este item não pode ser usado aqui.'; end if;
  if not exists (select 1 from public.inventario where jogador = auth.uid() and item = p_item and qtd > 0) then raise exception 'Você não tem este item.'; end if;
  if cura < 0 then
    if pk.hp_atual > 0 then raise exception 'Este Pokémon não está desmaiado.'; end if;
    novo := case when cura = -1 then greatest(1, pk.hp_max / 2) else pk.hp_max end;
  else
    if pk.hp_atual <= 0 then raise exception 'Use uma Revive neste Pokémon.'; end if;
    if pk.hp_atual >= pk.hp_max then raise exception 'O HP já está cheio.'; end if;
    novo := least(pk.hp_max, pk.hp_atual + cura);
  end if;
  update public.pokemons set hp_atual = novo where id = pk.id;
  update public.inventario set qtd = qtd - 1 where jogador = auth.uid() and item = p_item;
  return jsonb_build_object('hp', novo, 'hp_max', pk.hp_max);
end $$;
grant execute on function public.usar_item_fora(text, uuid) to authenticated;
