-- m50: qualquer batalha iniciada (selvagem, treinador NPC, ginásio, Liga, missão) marca os Pokémon adversários como "vistos" na Pokédex.
create or replace function public._tg_dex_visto() returns trigger language plpgsql security definer set search_path = public as $$
declare x jsonb; esp int;
begin
  if new.selvagem is not null and new.selvagem ? 'especie_id' then
    esp := nullif(new.selvagem->>'especie_id', '')::int;
    if esp is not null then insert into public.pokedex (jogador, especie_id) values (new.jogador, esp) on conflict do nothing; end if;
  end if;
  if new.adversarios is not null and jsonb_typeof(new.adversarios) = 'array' then
    for x in select * from jsonb_array_elements(new.adversarios) loop
      esp := nullif(x->>'especie_id', '')::int;
      if esp is not null and exists (select 1 from public.especies where id = esp) then
        insert into public.pokedex (jogador, especie_id) values (new.jogador, esp) on conflict do nothing;
      end if;
    end loop;
  end if;
  return new;
end $$;
drop trigger if exists tg_dex_visto on public.batalhas;
create trigger tg_dex_visto after insert on public.batalhas for each row execute function public._tg_dex_visto();
