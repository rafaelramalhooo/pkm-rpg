-- m78: habilidades dos Pokémon (Gen 1): tabela por espécie, slot no Pokémon, sorteio, retroativo e chave para ligar/desligar
create table if not exists public.especie_habilidades (
  especie_id int not null references public.especies (id) on delete cascade,
  slot smallint not null check (slot between 1 and 3),
  nome text not null,
  primary key (especie_id, slot)
);
alter table public.especie_habilidades enable row level security;
drop policy if exists hab_leitura on public.especie_habilidades;
create policy hab_leitura on public.especie_habilidades for select to authenticated using (true);
grant select on public.especie_habilidades to authenticated;
insert into public.especie_habilidades (especie_id, slot, nome) values (1,1,'overgrow'),(1,3,'chlorophyll'),(2,1,'overgrow'),(2,3,'chlorophyll'),(3,1,'overgrow'),(3,3,'chlorophyll'),(4,1,'blaze'),(4,3,'solar-power'),(5,1,'blaze'),(5,3,'solar-power'),(6,1,'blaze'),(6,3,'solar-power'),(7,1,'torrent'),(7,3,'rain-dish'),(8,1,'torrent'),(8,3,'rain-dish'),(9,1,'torrent'),(9,3,'rain-dish'),(10,1,'shield-dust'),(10,3,'run-away'),(11,1,'shed-skin'),(12,1,'compound-eyes'),(12,3,'tinted-lens'),(13,1,'shield-dust'),(13,3,'run-away'),(14,1,'shed-skin'),(15,1,'swarm'),(15,3,'sniper'),(16,1,'keen-eye'),(16,2,'tangled-feet'),(16,3,'big-pecks'),(17,1,'keen-eye'),(17,2,'tangled-feet'),(17,3,'big-pecks'),(18,1,'keen-eye'),(18,2,'tangled-feet'),(18,3,'big-pecks'),(19,1,'run-away'),(19,2,'guts'),(19,3,'hustle'),(20,1,'run-away'),(20,2,'guts'),(20,3,'hustle'),(21,1,'keen-eye'),(21,3,'sniper'),(22,1,'keen-eye'),(22,3,'sniper'),(23,1,'intimidate'),(23,2,'shed-skin'),(23,3,'unnerve'),(24,1,'intimidate'),(24,2,'shed-skin'),(24,3,'unnerve'),(25,1,'static'),(25,3,'lightning-rod'),(26,1,'static'),(26,3,'lightning-rod'),(27,1,'sand-veil'),(27,3,'sand-rush'),(28,1,'sand-veil'),(28,3,'sand-rush'),(29,1,'poison-point'),(29,2,'rivalry'),(29,3,'hustle'),(30,1,'poison-point'),(30,2,'rivalry'),(30,3,'hustle'),(31,1,'poison-point'),(31,2,'rivalry'),(31,3,'sheer-force'),(32,1,'poison-point'),(32,2,'rivalry'),(32,3,'hustle'),(33,1,'poison-point'),(33,2,'rivalry'),(33,3,'hustle'),(34,1,'poison-point'),(34,2,'rivalry'),(34,3,'sheer-force'),(35,1,'cute-charm'),(35,2,'magic-guard'),(35,3,'friend-guard'),(36,1,'cute-charm'),(36,2,'magic-guard'),(36,3,'unaware'),(37,1,'flash-fire'),(37,3,'drought'),(38,1,'flash-fire'),(38,3,'drought'),(39,1,'cute-charm'),(39,2,'competitive'),(39,3,'friend-guard'),(40,1,'cute-charm'),(40,2,'competitive'),(40,3,'frisk'),(41,1,'inner-focus'),(41,3,'infiltrator'),(42,1,'inner-focus'),(42,3,'infiltrator'),(43,1,'chlorophyll'),(43,3,'run-away'),(44,1,'chlorophyll'),(44,3,'stench'),(45,1,'chlorophyll'),(45,3,'effect-spore'),(46,1,'effect-spore'),(46,2,'dry-skin'),(46,3,'damp'),(47,1,'effect-spore'),(47,2,'dry-skin'),(47,3,'damp'),(48,1,'compound-eyes'),(48,2,'tinted-lens'),(48,3,'run-away'),(49,1,'shield-dust'),(49,2,'tinted-lens'),(49,3,'wonder-skin'),(50,1,'sand-veil'),(50,2,'arena-trap'),(50,3,'sand-force'),(51,1,'sand-veil'),(51,2,'arena-trap'),(51,3,'sand-force'),(52,1,'pickup'),(52,2,'technician'),(52,3,'unnerve'),(53,1,'limber'),(53,2,'technician'),(53,3,'unnerve'),(54,1,'damp'),(54,2,'cloud-nine'),(54,3,'swift-swim'),(55,1,'damp'),(55,2,'cloud-nine'),(55,3,'swift-swim'),(56,1,'vital-spirit'),(56,2,'anger-point'),(56,3,'defiant'),(57,1,'vital-spirit'),(57,2,'anger-point'),(57,3,'defiant'),(58,1,'intimidate'),(58,2,'flash-fire'),(58,3,'justified'),(59,1,'intimidate'),(59,2,'flash-fire'),(59,3,'justified'),(60,1,'water-absorb'),(60,2,'damp'),(60,3,'swift-swim'),(61,1,'water-absorb'),(61,2,'damp'),(61,3,'swift-swim'),(62,1,'water-absorb'),(62,2,'damp'),(62,3,'swift-swim'),(63,1,'synchronize'),(63,2,'inner-focus'),(63,3,'magic-guard'),(64,1,'synchronize'),(64,2,'inner-focus'),(64,3,'magic-guard'),(65,1,'synchronize'),(65,2,'inner-focus'),(65,3,'magic-guard'),(66,1,'guts'),(66,2,'no-guard'),(66,3,'steadfast'),(67,1,'guts'),(67,2,'no-guard'),(67,3,'steadfast'),(68,1,'guts'),(68,2,'no-guard'),(68,3,'steadfast'),(69,1,'chlorophyll'),(69,3,'gluttony'),(70,1,'chlorophyll'),(70,3,'gluttony'),(71,1,'chlorophyll'),(71,3,'gluttony'),(72,1,'clear-body'),(72,2,'liquid-ooze'),(72,3,'rain-dish'),(73,1,'clear-body'),(73,2,'liquid-ooze'),(73,3,'rain-dish'),(74,1,'rock-head'),(74,2,'sturdy'),(74,3,'sand-veil'),(75,1,'rock-head'),(75,2,'sturdy'),(75,3,'sand-veil'),(76,1,'rock-head'),(76,2,'sturdy'),(76,3,'sand-veil'),(77,1,'run-away'),(77,2,'flash-fire'),(77,3,'flame-body'),(78,1,'run-away'),(78,2,'flash-fire'),(78,3,'flame-body'),(79,1,'oblivious'),(79,2,'own-tempo'),(79,3,'regenerator'),(80,1,'oblivious'),(80,2,'own-tempo'),(80,3,'regenerator'),(81,1,'magnet-pull'),(81,2,'sturdy'),(81,3,'analytic'),(82,1,'magnet-pull'),(82,2,'sturdy'),(82,3,'analytic'),(83,1,'keen-eye'),(83,2,'inner-focus'),(83,3,'defiant'),(84,1,'run-away'),(84,2,'early-bird'),(84,3,'tangled-feet'),(85,1,'run-away'),(85,2,'early-bird'),(85,3,'tangled-feet'),(86,1,'thick-fat'),(86,2,'hydration'),(86,3,'ice-body'),(87,1,'thick-fat'),(87,2,'hydration'),(87,3,'ice-body'),(88,1,'stench'),(88,2,'sticky-hold'),(88,3,'poison-touch'),(89,1,'stench'),(89,2,'sticky-hold'),(89,3,'poison-touch'),(90,1,'shell-armor'),(90,2,'skill-link'),(90,3,'overcoat'),(91,1,'shell-armor'),(91,2,'skill-link'),(91,3,'overcoat'),(92,1,'levitate'),(93,1,'levitate'),(94,1,'cursed-body'),(95,1,'rock-head'),(95,2,'sturdy'),(95,3,'weak-armor'),(96,1,'insomnia'),(96,2,'forewarn'),(96,3,'inner-focus'),(97,1,'insomnia'),(97,2,'forewarn'),(97,3,'inner-focus'),(98,1,'hyper-cutter'),(98,2,'shell-armor'),(98,3,'sheer-force'),(99,1,'hyper-cutter'),(99,2,'shell-armor'),(99,3,'sheer-force'),(100,1,'soundproof'),(100,2,'static'),(100,3,'aftermath'),(101,1,'soundproof'),(101,2,'static'),(101,3,'aftermath'),(102,1,'chlorophyll'),(102,3,'harvest'),(103,1,'chlorophyll'),(103,3,'harvest'),(104,1,'rock-head'),(104,2,'lightning-rod'),(104,3,'battle-armor'),(105,1,'rock-head'),(105,2,'lightning-rod'),(105,3,'battle-armor'),(106,1,'limber'),(106,2,'reckless'),(106,3,'unburden'),(107,1,'keen-eye'),(107,2,'iron-fist'),(107,3,'inner-focus'),(108,1,'own-tempo'),(108,2,'oblivious'),(108,3,'cloud-nine'),(109,1,'levitate'),(109,2,'neutralizing-gas'),(109,3,'stench'),(110,1,'levitate'),(110,2,'neutralizing-gas'),(110,3,'stench'),(111,1,'lightning-rod'),(111,2,'rock-head'),(111,3,'reckless'),(112,1,'lightning-rod'),(112,2,'rock-head'),(112,3,'reckless'),(113,1,'natural-cure'),(113,2,'serene-grace'),(113,3,'healer'),(114,1,'chlorophyll'),(114,2,'leaf-guard'),(114,3,'regenerator'),(115,1,'early-bird'),(115,2,'scrappy'),(115,3,'inner-focus'),(116,1,'swift-swim'),(116,2,'sniper'),(116,3,'damp'),(117,1,'poison-point'),(117,2,'sniper'),(117,3,'damp'),(118,1,'swift-swim'),(118,2,'water-veil'),(118,3,'lightning-rod'),(119,1,'swift-swim'),(119,2,'water-veil'),(119,3,'lightning-rod'),(120,1,'illuminate'),(120,2,'natural-cure'),(120,3,'analytic'),(121,1,'illuminate'),(121,2,'natural-cure'),(121,3,'analytic'),(122,1,'soundproof'),(122,2,'filter'),(122,3,'technician'),(123,1,'swarm'),(123,2,'technician'),(123,3,'steadfast'),(124,1,'oblivious'),(124,2,'forewarn'),(124,3,'dry-skin'),(125,1,'static'),(125,3,'vital-spirit'),(126,1,'flame-body'),(126,3,'vital-spirit'),(127,1,'hyper-cutter'),(127,2,'mold-breaker'),(127,3,'moxie'),(128,1,'intimidate'),(128,2,'anger-point'),(128,3,'sheer-force'),(129,1,'swift-swim'),(129,3,'rattled'),(130,1,'intimidate'),(130,3,'moxie'),(131,1,'water-absorb'),(131,2,'shell-armor'),(131,3,'hydration'),(132,1,'limber'),(132,3,'imposter'),(133,1,'run-away'),(133,2,'adaptability'),(133,3,'anticipation'),(134,1,'water-absorb'),(134,3,'hydration'),(135,1,'volt-absorb'),(135,3,'quick-feet'),(136,1,'flash-fire'),(136,3,'guts'),(137,1,'trace'),(137,2,'download'),(137,3,'analytic'),(138,1,'swift-swim'),(138,2,'shell-armor'),(138,3,'weak-armor'),(139,1,'swift-swim'),(139,2,'shell-armor'),(139,3,'weak-armor'),(140,1,'swift-swim'),(140,2,'battle-armor'),(140,3,'weak-armor'),(141,1,'swift-swim'),(141,2,'battle-armor'),(141,3,'weak-armor'),(142,1,'rock-head'),(142,2,'pressure'),(142,3,'unnerve'),(143,1,'immunity'),(143,2,'thick-fat'),(143,3,'gluttony'),(144,1,'pressure'),(144,3,'snow-cloak'),(145,1,'pressure'),(145,3,'static'),(146,1,'pressure'),(146,3,'flame-body'),(147,1,'shed-skin'),(147,3,'marvel-scale'),(148,1,'shed-skin'),(148,3,'marvel-scale'),(149,1,'inner-focus'),(149,3,'multiscale'),(150,1,'pressure'),(150,3,'unnerve'),(151,1,'synchronize')
on conflict (especie_id, slot) do update set nome = excluded.nome;

alter table public.pokemons add column if not exists hab_slot smallint check (hab_slot between 1 and 3);

-- sorteio: slot 1 ou 2 (50/50; só 1 se a espécie tem uma habilidade comum); a oculta (slot 3) só com p_oculta (capturas), 5%
create or replace function public._hab_sorteio(p_esp int, p_oculta boolean) returns smallint
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  select count(*) into n from public.especie_habilidades where especie_id = p_esp and slot < 3;
  if n = 0 then return null; end if;
  if p_oculta and random() < 0.05 and exists (select 1 from public.especie_habilidades where especie_id = p_esp and slot = 3) then return 3; end if;
  return 1 + floor(random() * n)::int;
end $$;
revoke all on function public._hab_sorteio(int, boolean) from public, anon, authenticated;

-- novo Pokémon recebe slot; ao evoluir mantém o slot (se a nova espécie não tem esse slot, volta ao 1)
create or replace function public._tg_hab_slot() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    if new.hab_slot is null then new.hab_slot := public._hab_sorteio(new.especie_id, false); end if;
  elsif new.especie_id is distinct from old.especie_id then
    if exists (select 1 from public.especie_habilidades where especie_id = new.especie_id) then
      if new.hab_slot is null or not exists (select 1 from public.especie_habilidades where especie_id = new.especie_id and slot = new.hab_slot) then new.hab_slot := 1; end if;
    end if;
  end if;
  return new;
end $$;
drop trigger if exists tg_hab_slot on public.pokemons;
create trigger tg_hab_slot before insert or update of especie_id on public.pokemons for each row execute function public._tg_hab_slot();

-- retroativo (uma vez): sorteia para quem ainda não tem; sem habilidade oculta
update public.pokemons set hab_slot = public._hab_sorteio(especie_id, false) where hab_slot is null;

-- chave para ligar/desligar (lida ao criar cada batalha)
insert into public.config (chave, valor) values ('habilidades_pokemon', 'true'::jsonb) on conflict (chave) do nothing;

create or replace function public._pt(d text, a text, b text) returns text language plpgsql as $$
begin
  if position(a in d) = 0 then raise exception 'Trecho não encontrado: %', left(a, 60); end if;
  return replace(d, a, b);
end $$;
do $$
declare d text;
begin
  -- captura em batalha: o selvagem já nasceu com slot (gravado pela Edge Function); a captura herda
  d := pg_get_functiondef('public.sim_capturar(uuid,integer,jsonb,jsonb,integer,jsonb,integer,integer,jsonb)'::regprocedure);
  if position('hab_slot' in d) = 0 then
    d := public._pt(d, 'update public.batalhas set estado = ''captura'' where id = b.id;', 'update public.pokemons set hab_slot = coalesce(nullif(b.selvagem->>''hab_slot'', '''')::smallint, hab_slot) where id = novo.id;
  update public.batalhas set estado = ''captura'' where id = b.id;');
    execute d;
  end if;
  -- captura na Reserva: 5% de chance de habilidade oculta
  d := pg_get_functiondef('public._reserva_fim(uuid)'::regprocedure);
  if position('hab_slot' in d) = 0 then
    d := public._pt(d, 'ent := ent || jsonb_build_array(c);', 'update public.pokemons set hab_slot = coalesce(public._hab_sorteio(p.especie_id, true), hab_slot) where id = p.id;
      ent := ent || jsonb_build_array(c);');
    execute d;
  end if;
end $$;
drop function public._pt(text, text, text);
