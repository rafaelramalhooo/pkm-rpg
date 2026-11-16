-- m46: motor de evolução com condições (amizade, dia/noite, golpe, troca), avisos e amizade viva.
alter table public.evolucoes add column if not exists condicoes jsonb;
alter table public.evolucoes add column if not exists ativo boolean not null default true;

-- evoluções por troca: deixam de ser nível 36 e passam a exigir troca entre jogadores
update public.evolucoes set nivel = null, condicoes = '{"troca": true}'::jsonb
 where (de, para) in ((64,65),(67,68),(75,76),(93,94));

create or replace function public._periodo_dia() returns text language sql stable as $$
  select case when extract(hour from (now() at time zone 'America/Sao_Paulo')) between 6 and 17 then 'dia' else 'noite' end
$$;

-- avalia as condições (exceto 'troca', tratada no gatilho). 'local' fica desativada por enquanto.
create or replace function public._cond_ok(p public.pokemons, c jsonb) returns boolean language plpgsql stable as $$
begin
  if c is null then return false; end if;
  if c ? 'local' then return false; end if;
  if c ? 'nivel_min' and p.nivel < (c->>'nivel_min')::int then return false; end if;
  if c ? 'min_amizade' and p.amizade < (c->>'min_amizade')::int then return false; end if;
  if c ? 'periodo' and public._periodo_dia() <> c->>'periodo' then return false; end if;
  if c ? 'golpe_id' and not exists (select 1 from jsonb_array_elements(p.golpes) x where (x->>'id')::int = (c->>'golpe_id')::int) then return false; end if;
  return true;
end $$;
revoke all on function public._cond_ok(public.pokemons, jsonb) from public, anon, authenticated;

create table if not exists public.avisos_evolucao (
  id bigserial primary key, jogador uuid not null references public.jogadores (id) on delete cascade,
  texto text not null, criado_em timestamptz not null default now(), lido boolean not null default false
);
alter table public.avisos_evolucao enable row level security;

create or replace function public.avisos_evolucao_meus() returns jsonb language plpgsql security definer set search_path = public as $$
declare r jsonb;
begin
  if auth.uid() is null then return '[]'::jsonb; end if;
  select coalesce(jsonb_agg(texto order by id), '[]'::jsonb) into r from public.avisos_evolucao where jogador = auth.uid() and not lido;
  update public.avisos_evolucao set lido = true where jogador = auth.uid() and not lido;
  return r;
end $$;
revoke all on function public.avisos_evolucao_meus() from public, anon;
grant execute on function public.avisos_evolucao_meus() to authenticated;

-- evolução manual por condições
create or replace function public.evoluir_pokemon(p_pokemon uuid) returns jsonb language plpgsql security definer set search_path = public as $$
declare pk public.pokemons; evo record; n public.pokemons; nome_ant text; e public.especies;
begin
  if auth.uid() is null then raise exception 'Faça login primeiro.'; end if;
  if exists (select 1 from public.batalhas where jogador = auth.uid() and estado = 'ativa') then raise exception 'Não é possível evoluir durante a batalha.'; end if;
  select * into pk from public.pokemons where id = p_pokemon and dono = auth.uid() for update;
  if not found then raise exception 'Pokémon não encontrado.'; end if;
  select ev.* into evo from public.evolucoes ev
   where ev.de = pk.especie_id and ev.ativo and ev.item is null and ev.condicoes is not null and not (ev.condicoes ? 'troca')
     and public._cond_ok(pk, ev.condicoes) order by ev.para limit 1;
  if not found then raise exception 'Ainda não é hora de evoluir.'; end if;
  select nome into nome_ant from public.especies where id = pk.especie_id;
  n := public._aplicar_evolucao(pk, evo.para);
  update public.pokemons set especie_id = n.especie_id, hp_max = n.hp_max, atk = n.atk, def = n.def, spa = n.spa, spd = n.spd, spe = n.spe, hp_atual = n.hp_atual where id = pk.id;
  select * into e from public.especies where id = evo.para;
  return jsonb_build_object('evolucao', jsonb_build_object('nome', coalesce(pk.apelido, nome_ant), 'para', e.nome, 'pontos', true));
end $$;
revoke all on function public.evoluir_pokemon(uuid) from public, anon;
grant execute on function public.evoluir_pokemon(uuid) to authenticated;

-- quais Pokémon do jogador podem evoluir agora (por condições)
create or replace function public.evolucoes_possiveis() returns jsonb language plpgsql security definer set search_path = public as $$
declare r jsonb := '[]'::jsonb; pk public.pokemons; evo record;
begin
  if auth.uid() is null then return r; end if;
  for pk in select * from public.pokemons where dono = auth.uid() loop
    select ev.* into evo from public.evolucoes ev
     where ev.de = pk.especie_id and ev.ativo and ev.item is null and ev.condicoes is not null and not (ev.condicoes ? 'troca')
       and public._cond_ok(pk, ev.condicoes) order by ev.para limit 1;
    if found then r := r || jsonb_build_array(jsonb_build_object('pokemon', pk.id, 'para', evo.para)); end if;
  end loop;
  return r;
end $$;
revoke all on function public.evolucoes_possiveis() from public, anon;
grant execute on function public.evolucoes_possiveis() to authenticated;

-- evolução por troca (só entre jogadores reais)
create or replace function public._trg_evo_troca() returns trigger language plpgsql security definer set search_path = public as $$
declare evo record; n public.pokemons; nome_ant text; e public.especies;
begin
  if new.dono is distinct from old.dono and old.dono is not null
     and exists (select 1 from public.jogadores where id = old.dono) and exists (select 1 from public.jogadores where id = new.dono) then
    select ev.* into evo from public.evolucoes ev where ev.de = new.especie_id and ev.ativo and ev.condicoes->>'troca' = 'true' limit 1;
    if found then
      select nome into nome_ant from public.especies where id = new.especie_id;
      n := public._aplicar_evolucao(new, evo.para);
      update public.pokemons set especie_id = n.especie_id, hp_max = n.hp_max, atk = n.atk, def = n.def, spa = n.spa, spd = n.spd, spe = n.spe, hp_atual = n.hp_atual where id = new.id;
      select * into e from public.especies where id = evo.para;
      insert into public.avisos_evolucao (jogador, texto) values (new.dono, coalesce(new.apelido, nome_ant) || ' evoluiu para ' || e.nome || ' com a troca!');
    end if;
  end if;
  return null;
end $$;
drop trigger if exists trg_evo_troca on public.pokemons;
create trigger trg_evo_troca after update of dono on public.pokemons for each row execute function public._trg_evo_troca();

-- amizade viva: +1 por nível ganho, -1 ao desmaiar
create or replace function public._trg_amizade() returns trigger language plpgsql as $$
begin
  if new.nivel > old.nivel then new.amizade := least(255, new.amizade + (new.nivel - old.nivel)); end if;
  if old.hp_atual > 0 and new.hp_atual <= 0 then new.amizade := greatest(0, new.amizade - 1); end if;
  return new;
end $$;
drop trigger if exists trg_amizade on public.pokemons;
create trigger trg_amizade before update on public.pokemons for each row execute function public._trg_amizade();
