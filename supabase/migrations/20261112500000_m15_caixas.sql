-- m15: Caixas (Box). Cada jogador tem 2 caixas de 15 espaços (configurável: config 'qtd_caixas' e 'tam_caixa').
-- A partir do 7º Pokémon a captura vai sozinha para a caixa; sem vaga, a captura é bloqueada.
-- Guardar, retirar e trocar só no Centro Pokémon ou no Laboratório (validado aqui no servidor).
alter table public.pokemons add column if not exists caixa smallint check (caixa between 1 and 20);
alter table public.pokemons add column if not exists slot_caixa smallint check (slot_caixa between 1 and 100);
create unique index if not exists pokemons_caixa_unico on public.pokemons (dono, caixa, slot_caixa) where caixa is not null;

with r as (select id, row_number() over (partition by dono order by criado_em, id) rn from public.pokemons where posicao is null and caixa is null)
update public.pokemons p set caixa = ((r.rn - 1) / 15) + 1, slot_caixa = ((r.rn - 1) % 15) + 1 from r where p.id = r.id and r.rn <= 30;

create or replace function public._cfg_int(p_chave text, p_padrao int) returns int
language sql stable security definer set search_path = public as $$
  select coalesce((select (valor #>> '{}')::int from public.config where chave = p_chave), p_padrao) $$;
revoke all on function public._cfg_int(text,int) from public, anon, authenticated;

create or replace function public._vaga_caixa(p_dono uuid, out o_caixa int, out o_slot int)
language plpgsql security definer set search_path = public as $$
begin
  select c, s into o_caixa, o_slot
    from generate_series(1, public._cfg_int('qtd_caixas', 2)) c, generate_series(1, public._cfg_int('tam_caixa', 15)) s
   where not exists (select 1 from public.pokemons where dono = p_dono and caixa = c and slot_caixa = s)
   order by c, s limit 1;
end $$;
revoke all on function public._vaga_caixa(uuid) from public, anon, authenticated;

create or replace function public._novo_pokemon(p_dono uuid, p_esp int, p_nivel int, p_golpes jsonb default null, p_brilhante boolean default null)
returns public.pokemons language plpgsql security definer set search_path = public as $$
declare
  e public.especies; nat text; v public.pokemons;
  ih int := floor(random()*32); ia int := floor(random()*32); id_ int := floor(random()*32);
  isa int := floor(random()*32); isd int := floor(random()*32); ise int := floor(random()*32);
  slot int; vc int; vs int;
  br boolean := coalesce(p_brilhante, random() < least(1, coalesce((select (valor #>> '{}')::numeric from public.config where chave = 'chance_brilhante'), 0.004) * public._ev('brilhante', 1)));
begin
  select * into e from public.especies where id = p_esp;
  if not found then raise exception 'Espécie desconhecida.'; end if;
  select nome into nat from public.naturezas order by random() limit 1;
  nat := coalesce(nat, 'hardy');
  select min(s) into slot from generate_series(1,6) s where not exists (select 1 from public.pokemons where dono = p_dono and posicao = s);
  if slot is null then
    select o_caixa, o_slot into vc, vs from public._vaga_caixa(p_dono);
    if vc is null then raise exception 'Suas caixas estão cheias! Abra espaço no Centro Pokémon ou no Laboratório do Prof. Carvalho antes de capturar.'; end if;
  end if;
  insert into public.pokemons (dono, especie_id, nivel, exp, natureza, iv_hp, iv_atk, iv_def, iv_spa, iv_spd, iv_spe,
      hp_max, atk, def, spa, spd, spe, hp_atual, golpes, posicao, brilhante, caixa, slot_caixa)
  values (p_dono, p_esp, p_nivel, public.exp_para(p_nivel), nat, ih, ia, id_, isa, isd, ise,
      public.calc_hp(e.hp, ih, p_nivel),
      public.calc_stat(e.atk, ia, p_nivel, public.mult_nat(nat, 'attack')),
      public.calc_stat(e.def, id_, p_nivel, public.mult_nat(nat, 'defense')),
      public.calc_stat(e.spa, isa, p_nivel, public.mult_nat(nat, 'sp_attack')),
      public.calc_stat(e.spd, isd, p_nivel, public.mult_nat(nat, 'sp_defense')),
      public.calc_stat(e.spe, ise, p_nivel, public.mult_nat(nat, 'speed')),
      public.calc_hp(e.hp, ih, p_nivel),
      coalesce(p_golpes, public.golpes_do_nivel(p_esp, p_nivel)), slot, br, vc, vs)
  returning * into v;
  insert into public.pokedex (jogador, especie_id, capturado) values (p_dono, p_esp, true)
  on conflict (jogador, especie_id) do update set capturado = true;
  return v;
end $$;
revoke all on function public._novo_pokemon(uuid,int,int,jsonb,boolean) from public, anon, authenticated;

create or replace function public.tem_vaga(p_dono uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select (select count(*) from public.pokemons where dono = p_dono and posicao is not null) < 6
      or (select o_caixa from public._vaga_caixa(p_dono)) is not null $$;
revoke all on function public.tem_vaga(uuid) from public, anon, authenticated;
grant execute on function public.tem_vaga(uuid) to service_role;

create or replace function public._em_centro_lab(p_uid uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.jogadores j
     where j.id = p_uid
       and (j.mapa_id = 'lab' or exists (
             select 1 from public.mapas m, jsonb_array_elements(m.pois) p
              where m.id = j.mapa_id and p->>'tipo' = 'centro'
                and abs((p->>'x')::int - j.x) + abs((p->>'y')::int - j.y) <= 2))) $$;
revoke all on function public._em_centro_lab(uuid) from public, anon, authenticated;

create or replace function public.posso_mexer_caixa() returns boolean
language sql stable security definer set search_path = public as $$ select public._em_centro_lab(auth.uid()) $$;
grant execute on function public.posso_mexer_caixa() to authenticated;

create or replace function public.config_caixas() returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('qtd', public._cfg_int('qtd_caixas', 2), 'tam', public._cfg_int('tam_caixa', 15)) $$;
grant execute on function public.config_caixas() to authenticated;

-- reordenar o time (qualquer lugar): precisa ser exatamente os mesmos Pokémon do time
create or replace function public.organizar_time(p_ordem uuid[]) returns void
language plpgsql security definer set search_path = public as $$
declare v_id uuid; i int := 0;
begin
  if auth.uid() is null then raise exception 'Faça login primeiro.'; end if;
  if p_ordem is null or array_length(p_ordem, 1) is null then raise exception 'Time inválido.'; end if;
  if exists (select 1 from public.batalhas where jogador = auth.uid() and estado = 'ativa') then raise exception 'Termine a batalha primeiro.'; end if;
  if (select count(distinct x) from unnest(p_ordem) x) <> array_length(p_ordem, 1)
     or (select count(*) from public.pokemons where dono = auth.uid() and posicao is not null) <> array_length(p_ordem, 1)
     or (select count(*) from public.pokemons where dono = auth.uid() and posicao is not null and id = any(p_ordem)) <> array_length(p_ordem, 1)
  then raise exception 'Só dá para reordenar o time aqui. Trocar com a caixa só no Centro Pokémon ou no Laboratório.'; end if;
  update public.pokemons set posicao = null where dono = auth.uid() and posicao is not null;
  foreach v_id in array p_ordem loop
    i := i + 1;
    update public.pokemons set posicao = i where id = v_id;
  end loop;
end $$;
grant execute on function public.organizar_time(uuid[]) to authenticated;

create or replace function public._caixa_pre() returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Faça login primeiro.'; end if;
  if exists (select 1 from public.batalhas where jogador = auth.uid() and estado = 'ativa') then raise exception 'Termine a batalha primeiro.'; end if;
  if not public._em_centro_lab(auth.uid()) then raise exception 'As caixas só podem ser mexidas no Centro Pokémon ou no Laboratório do Prof. Carvalho.'; end if;
end $$;
revoke all on function public._caixa_pre() from public, anon, authenticated;

create or replace function public.caixa_guardar(p_pokemon uuid) returns void
language plpgsql security definer set search_path = public as $$
declare vc int; vs int; v public.pokemons;
begin
  perform public._caixa_pre();
  select * into v from public.pokemons where id = p_pokemon and dono = auth.uid() and posicao is not null for update;
  if not found then raise exception 'Esse Pokémon não está no seu time.'; end if;
  if (select count(*) from public.pokemons where dono = auth.uid() and posicao is not null) <= 1 then raise exception 'O time precisa de ao menos 1 Pokémon.'; end if;
  select o_caixa, o_slot into vc, vs from public._vaga_caixa(auth.uid());
  if vc is null then raise exception 'As caixas estão cheias.'; end if;
  update public.pokemons set posicao = null, caixa = vc, slot_caixa = vs where id = v.id;
end $$;
grant execute on function public.caixa_guardar(uuid) to authenticated;

create or replace function public.caixa_retirar(p_pokemon uuid) returns void
language plpgsql security definer set search_path = public as $$
declare slot int; v public.pokemons;
begin
  perform public._caixa_pre();
  select * into v from public.pokemons where id = p_pokemon and dono = auth.uid() and caixa is not null for update;
  if not found then raise exception 'Esse Pokémon não está numa caixa.'; end if;
  select min(s) into slot from generate_series(1, 6) s where not exists (select 1 from public.pokemons where dono = auth.uid() and posicao = s);
  if slot is null then raise exception 'Seu time já tem 6 Pokémon. Guarde um deles ou use Trocar.'; end if;
  update public.pokemons set posicao = slot, caixa = null, slot_caixa = null where id = v.id;
end $$;
grant execute on function public.caixa_retirar(uuid) to authenticated;

create or replace function public.caixa_trocar(p_time uuid, p_caixa uuid) returns void
language plpgsql security definer set search_path = public as $$
declare a public.pokemons; b public.pokemons;
begin
  perform public._caixa_pre();
  select * into a from public.pokemons where id = p_time and dono = auth.uid() and posicao is not null for update;
  select * into b from public.pokemons where id = p_caixa and dono = auth.uid() and caixa is not null for update;
  if a.id is null or b.id is null then raise exception 'Escolha um Pokémon do time e um da caixa.'; end if;
  update public.pokemons set posicao = null, caixa = null, slot_caixa = null where id = b.id;
  update public.pokemons set posicao = null, caixa = b.caixa, slot_caixa = b.slot_caixa where id = a.id;
  update public.pokemons set posicao = a.posicao where id = b.id;
end $$;
grant execute on function public.caixa_trocar(uuid, uuid) to authenticated;

create or replace function public.caixa_mover(p_pokemon uuid, p_caixa int, p_slot int) returns void
language plpgsql security definer set search_path = public as $$
declare a public.pokemons; b public.pokemons;
begin
  perform public._caixa_pre();
  if p_caixa < 1 or p_caixa > public._cfg_int('qtd_caixas', 2) or p_slot < 1 or p_slot > public._cfg_int('tam_caixa', 15) then raise exception 'Espaço inválido.'; end if;
  select * into a from public.pokemons where id = p_pokemon and dono = auth.uid() and caixa is not null for update;
  if not found then raise exception 'Esse Pokémon não está numa caixa.'; end if;
  select * into b from public.pokemons where dono = auth.uid() and caixa = p_caixa and slot_caixa = p_slot for update;
  if b.id is not null and b.id = a.id then return; end if;
  if b.id is not null then
    update public.pokemons set caixa = null, slot_caixa = null where id = b.id;
    update public.pokemons set caixa = p_caixa, slot_caixa = p_slot where id = a.id;
    update public.pokemons set caixa = a.caixa, slot_caixa = a.slot_caixa where id = b.id;
  else
    update public.pokemons set caixa = p_caixa, slot_caixa = p_slot where id = a.id;
  end if;
end $$;
grant execute on function public.caixa_mover(uuid, int, int) to authenticated;

-- bloqueia o arremesso da bola (antes de gastá-la) se o time e as caixas estiverem cheios
create or replace function public.sim_gastar_item(p_jogador uuid, p_item text) returns void
language plpgsql security definer set search_path = public as $$
declare v_qtd int;
begin
  if p_item like '%ball' and exists (select 1 from public.batalhas where jogador = p_jogador and estado = 'ativa' and tipo = 'selvagem')
     and not public.tem_vaga(p_jogador) then
    raise exception 'Suas caixas estão cheias! Abra espaço no Centro Pokémon ou no Laboratório do Prof. Carvalho antes de capturar.';
  end if;
  select qtd into v_qtd from public.inventario where jogador = p_jogador and item = p_item for update;
  if coalesce(v_qtd, 0) <= 0 then raise exception 'Você não tem esse item.'; end if;
  update public.inventario set qtd = qtd - 1 where jogador = p_jogador and item = p_item;
end $$;
revoke all on function public.sim_gastar_item(uuid, text) from public, anon, authenticated;
grant execute on function public.sim_gastar_item(uuid, text) to service_role;
