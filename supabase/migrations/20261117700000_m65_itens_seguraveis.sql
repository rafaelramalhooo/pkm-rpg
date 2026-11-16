-- m65 (Lote C): itens seguráveis. Cada Pokémon segura 1 item (coluna item_seguro); o efeito roda no Showdown.
-- Itens consumíveis na batalha (Faixa Focal, Bagas) valem só para aquela batalha; o item volta a estar equipado depois.
alter table public.pokemons add column if not exists item_seguro text references public.itens (slug);

insert into public.itens (slug, nome, categoria, efeito, arco) values
  ('leftovers', 'Sobras', 'held-items', 'Recupera 1/16 do HP máximo no fim de cada turno.', 1),
  ('life-orb', 'Orbe da Vida', 'held-items', 'Golpes causam 30% mais dano, mas o Pokémon perde 10% do HP ao atacar.', 1),
  ('choice-band', 'Faixa Escolha', 'held-items', 'Ataque ×1,5, mas só pode usar o primeiro golpe escolhido até sair da batalha.', 1),
  ('choice-specs', 'Óculos Escolha', 'held-items', 'Ataque Especial ×1,5, mas só pode usar o primeiro golpe escolhido até sair da batalha.', 1),
  ('choice-scarf', 'Lenço Escolha', 'held-items', 'Velocidade ×1,5, mas só pode usar o primeiro golpe escolhido até sair da batalha.', 1),
  ('rocky-helmet', 'Capacete Pedregoso', 'held-items', 'Quem atacar o portador com contato perde 1/6 do HP.', 1),
  ('focus-sash', 'Faixa Focal', 'held-items', 'Com HP cheio, sobrevive com 1 HP a um golpe que o derrubaria (uma vez por batalha).', 1),
  ('scope-lens', 'Lente de Mira', 'held-items', 'Aumenta a chance de acerto crítico.', 1),
  ('expert-belt', 'Cinto Especialista', 'held-items', 'Golpes super eficazes causam 20% mais dano.', 1),
  ('shell-bell', 'Sino Concha', 'held-items', 'Recupera 1/8 do dano causado.', 1),
  ('black-glasses', 'Óculos Escuros', 'held-items', 'Aumenta em 20% o poder de golpes do tipo Sombrio.', 1),
  ('quick-claw', 'Garra Rápida', 'held-items', '20% de chance de agir primeiro no turno.', 1),
  ('lum-berry', 'Baga Lum', 'held-items', 'Cura qualquer condição de status (uma vez por batalha).', 1),
  ('magnet', 'Ímã', 'held-items', 'Aumenta em 20% o poder de golpes do tipo Elétrico.', 1),
  ('black-belt', 'Faixa Preta', 'held-items', 'Aumenta em 20% o poder de golpes do tipo Lutador.', 1),
  ('never-melt-ice', 'Gelo Eterno', 'held-items', 'Aumenta em 20% o poder de golpes do tipo Gelo.', 1),
  ('oran-berry', 'Baga Oran', 'held-items', 'Recupera 10 HP quando o HP cai à metade (uma vez por batalha).', 1),
  ('sitrus-berry', 'Baga Sitrus', 'held-items', 'Recupera 25% do HP quando ele cai à metade (uma vez por batalha).', 1),
  ('charcoal', 'Carvão', 'held-items', 'Aumenta em 20% o poder de golpes do tipo Fogo.', 1),
  ('mystic-water', 'Água Mística', 'held-items', 'Aumenta em 20% o poder de golpes do tipo Água.', 1),
  ('miracle-seed', 'Semente Milagrosa', 'held-items', 'Aumenta em 20% o poder de golpes do tipo Planta.', 1)
on conflict (slug) do update set nome = excluded.nome, categoria = excluded.categoria, efeito = excluded.efeito;

create or replace function public.equipar_item(p_pokemon uuid, p_item text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare pk public.pokemons; v_ant text;
begin
  if auth.uid() is null then raise exception 'Faça login primeiro.'; end if;
  select * into pk from public.pokemons where id = p_pokemon and dono = auth.uid() for update;
  if not found then raise exception 'Pokémon não encontrado.'; end if;
  if exists (select 1 from public.batalhas where jogador = auth.uid() and estado = 'ativa') then raise exception 'Termine a batalha primeiro.'; end if;
  v_ant := pk.item_seguro;
  if p_item is not distinct from v_ant then return jsonb_build_object('item', v_ant, 'devolvido', null); end if;
  if p_item is not null then
    if not exists (select 1 from public.itens where slug = p_item and categoria = 'held-items') then raise exception 'Este item não pode ser segurado.'; end if;
    if not exists (select 1 from public.inventario where jogador = auth.uid() and item = p_item and qtd > 0) then raise exception 'Você não tem este item.'; end if;
    update public.inventario set qtd = qtd - 1 where jogador = auth.uid() and item = p_item;
  end if;
  if v_ant is not null then
    insert into public.inventario (jogador, item, qtd) values (auth.uid(), v_ant, 1) on conflict (jogador, item) do update set qtd = public.inventario.qtd + 1;
  end if;
  update public.pokemons set item_seguro = p_item where id = pk.id;
  return jsonb_build_object('item', p_item, 'devolvido', v_ant);
end $$;
revoke all on function public.equipar_item(uuid, text) from public, anon;
grant execute on function public.equipar_item(uuid, text) to authenticated;

-- lojas das cidades maiores
do $$ begin
  update public.mapas set pois = (select jsonb_agg(case when q->>'id' = 'mart' then jsonb_set(q, '{estoque}', (q->'estoque') || '[{"item": "leftovers", "preco": 5000}, {"item": "life-orb", "preco": 5000}, {"item": "choice-band", "preco": 4000}, {"item": "choice-specs", "preco": 4000}, {"item": "choice-scarf", "preco": 4000}, {"item": "rocky-helmet", "preco": 3000}]'::jsonb) else q end order by o) from jsonb_array_elements(pois) with ordinality t(q, o)) where id = 'obsidiana';
  update public.mapas set pois = (select jsonb_agg(case when q->>'id' = 'mart' then jsonb_set(q, '{estoque}', (q->'estoque') || '[{"item": "focus-sash", "preco": 3000}, {"item": "scope-lens", "preco": 2500}, {"item": "expert-belt", "preco": 3500}, {"item": "shell-bell", "preco": 2500}, {"item": "black-glasses", "preco": 2000}]'::jsonb) else q end order by o) from jsonb_array_elements(pois) with ordinality t(q, o)) where id = 'carmesim';
  update public.mapas set pois = (select jsonb_agg(case when q->>'id' = 'mart' then jsonb_set(q, '{estoque}', (q->'estoque') || '[{"item": "quick-claw", "preco": 2000}, {"item": "lum-berry", "preco": 2000}, {"item": "magnet", "preco": 2000}, {"item": "black-belt", "preco": 2000}, {"item": "never-melt-ice", "preco": 2000}]'::jsonb) else q end order by o) from jsonb_array_elements(pois) with ordinality t(q, o)) where id = 'ametista';
  update public.mapas set pois = (select jsonb_agg(case when q->>'id' = 'mart' then jsonb_set(q, '{estoque}', (q->'estoque') || '[{"item": "oran-berry", "preco": 1000}, {"item": "sitrus-berry", "preco": 1500}, {"item": "charcoal", "preco": 2000}, {"item": "mystic-water", "preco": 2000}, {"item": "miracle-seed", "preco": 2000}]'::jsonb) else q end order by o) from jsonb_array_elements(pois) with ordinality t(q, o)) where id = 'quartzo';
end $$;
