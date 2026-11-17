-- m75: reset das Habilidades (reset parcial), bônus de manutenção e mensagens da regra "maior atributo <= 2x o menor"

-- 1) Habilidades que sobreviveram a um reset parcial: zera habilidades/classes/desconto. XP, Pokémon, PA e dinheiro ficam intactos.
--    Os pontos são calculados (xp_treino + níveis), então o saldo volta inteiro.
do $$
declare n int;
begin
  update public.jogadores
     set habilidades = '{}'::jsonb, classe_rpg = null, classe_sec = null, desconto_barganha = 0
   where conta is null and papel <> 'mestre' and habilidades <> '{}'::jsonb;
  get diagnostics n = row_count;
  insert into public.auditoria (ator, acao, detalhe) values (null, 'm75_reset_habilidades', jsonb_build_object('jogadores', n));
end $$;

-- 2) Bônus de manutenção (uma vez só): +5 PA, +₽500 e +10 Poké Balls para todos os personagens ativos
do $$
declare n int;
begin
  if exists (select 1 from public.config where chave = 'bonus_manutencao_1117') then return; end if;
  update public.jogadores set pa = least(32000, pa + 5), dinheiro = dinheiro + 500 where conta is null;
  get diagnostics n = row_count;
  insert into public.inventario (jogador, item, qtd)
    select id, 'poke-ball', 10 from public.jogadores where conta is null
  on conflict (jogador, item) do update set qtd = public.inventario.qtd + 10;
  insert into public.config (chave, valor) values ('bonus_manutencao_1117', to_jsonb(now()::text));
  insert into public.auditoria (ator, acao, detalhe) values (null, 'm75_bonus_manutencao', jsonb_build_object('jogadores', n, 'pa', 5, 'dinheiro', 500, 'poke_ball', 10));
end $$;

-- 3) Regra dos atributos: mesma conta de antes, mas a mensagem informa o limite real
--    (2x o menor; se a ficha automática já nasce acima disso, o limite é a proporção dela e não pode piorar).
create or replace function public.distribuir_evolucao(p_pokemon uuid, p_aloc jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare pk public.pokemons; k text; a int; soma int := 0; pool int; g int; nv jsonb := '{}'::jsonb; aut jsonb := '{}'::jsonb; mx int; mn int; amx int; amn int; novo_aj jsonb; lim numeric;
begin
  if auth.uid() is null then raise exception 'Faça login primeiro.'; end if;
  select * into pk from public.pokemons where id = p_pokemon and dono = auth.uid() for update;
  if not found then raise exception 'Pokémon não encontrado.'; end if;
  if pk.evo_pend is null then raise exception 'Este Pokémon não tem pontos para distribuir.'; end if;
  pool := (pk.evo_pend->>'pool')::int;
  novo_aj := pk.ajuste;
  foreach k in array array['atk','def','spa','spd','spe'] loop
    a := coalesce((p_aloc->>k)::int, 0);
    if a < 0 then raise exception 'Pontos inválidos.'; end if;
    soma := soma + a;
    g := coalesce((pk.evo_pend->'gain'->>k)::int, 0);
    aut := aut || jsonb_build_object(k, (to_jsonb(pk)->>k)::int);
    nv := nv || jsonb_build_object(k, (to_jsonb(pk)->>k)::int - g + a);
    novo_aj := novo_aj || jsonb_build_object(k, coalesce((pk.ajuste->>k)::int, 0) - g + a);
  end loop;
  if soma <> pool then raise exception 'Distribua exatamente % pontos (você usou %).', pool, soma; end if;
  select max(v::int), min(v::int) into mx, mn from jsonb_each_text(nv) t(k, v);
  select max(v::int), min(v::int) into amx, amn from jsonb_each_text(aut) t(k, v);
  lim := greatest(2.0, amx::numeric / greatest(1, amn));
  if mx > lim * greatest(1, mn) then
    raise exception 'O maior atributo (%) passou do limite (% vezes o menor, %). Ajuste os pontos.', mx, round(lim, 2), mn;
  end if;
  update public.pokemons set atk = (nv->>'atk')::int, def = (nv->>'def')::int, spa = (nv->>'spa')::int, spd = (nv->>'spd')::int, spe = (nv->>'spe')::int,
    ajuste = novo_aj, evo_pend = null where id = pk.id;
  return nv;
end $$;
revoke all on function public.distribuir_evolucao(uuid, jsonb) from public, anon;
grant execute on function public.distribuir_evolucao(uuid, jsonb) to authenticated;
