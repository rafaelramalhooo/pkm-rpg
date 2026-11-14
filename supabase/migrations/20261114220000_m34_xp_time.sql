-- m34: o XP de batalha/duelo é dividido igualmente entre TODOS os Pokémon do time (até 6, inclusive desmaiados),
-- com bônus de ×3 no total (ajustável em _xp_mult_time). "Treinar", "Cuidar" e missões seguem individuais.
create or replace function public._xp_mult_time() returns numeric language sql immutable as $$ select 3::numeric $$;

create or replace function public.sim_gravar(
  p_batalha uuid, p_turno int, p_sim jsonb, p_meta jsonb, p_log_len int, p_time jsonb, p_fim text, p_exp jsonb default '[]'::jsonb
) returns jsonb language plpgsql security definer set search_path = public as $$
declare
  b public.batalhas; t public.treinadores; m jsonb; ev jsonb := '[]'::jsonb; pk public.pokemons; pk2 public.pokemons; novo jsonb; i int; k int; sel jsonb; part uuid[]; n int; x jsonb;
begin
  select * into b from public.batalhas where id = p_batalha for update;
  if not found or b.estado <> 'ativa' then raise exception 'Batalha encerrada.'; end if;
  if b.turno <> p_turno then raise exception 'Outra ação já foi processada. Tente de novo.'; end if;
  for m in select * from jsonb_array_elements(p_time) loop
    select * into pk from public.pokemons where id = (m->>'id')::uuid and dono = b.jogador;
    if found then
      novo := '[]'::jsonb;
      for k in 0 .. jsonb_array_length(pk.golpes) - 1 loop
        novo := novo || jsonb_build_array((pk.golpes->k) || jsonb_build_object('pp', coalesce((m->'pp'->>k)::int, (pk.golpes->k->>'pp')::int)));
      end loop;
      update public.pokemons set hp_atual = greatest(0, least((m->>'hp')::int, hp_max)), golpes = novo where id = pk.id;
    end if;
  end loop;
  update public.batalhas set sim = p_sim, meta = p_meta, log_len = p_log_len, turno = turno + 1,
         ativo = coalesce((p_meta->>'ativo')::uuid, ativo) where id = b.id;
  if p_fim is not null then
    update public.batalhas set estado = p_fim where id = b.id;
    if p_fim = 'vitoria' and b.tipo = 'treinador' and b.treinador is not null then
      select * into t from public.treinadores where id = b.treinador;
      insert into public.treinadores_vencidos (jogador, treinador) values (b.jogador, b.treinador) on conflict do nothing;
      if t.insignia is not null then
        update public.jogadores set insignias = (select array_agg(distinct s) from unnest(insignias || t.insignia) s) where id = b.jogador;
        ev := ev || jsonb_build_array(jsonb_build_object('t', 'insignia', 'nome', t.insignia, 'lider', t.nome));
      end if;
      if t.id = 'liga_campeao_chefe' then
        update public.jogadores set campeao = true where id = b.jogador;
        ev := ev || jsonb_build_array(jsonb_build_object('t', 'campeao', 'nome', t.nome));
      end if;
      if t.recompensa > 0 then
        update public.jogadores set dinheiro = dinheiro + floor(t.recompensa * public._ev('dinheiro', 1) * (1 + public._bonus(b.jogador, 'recompensa') / 100.0)) where id = b.jogador;
        ev := ev || jsonb_build_array(jsonb_build_object('t', 'dinheiro', 'valor', floor(t.recompensa * public._ev('dinheiro', 1) * (1 + public._bonus(b.jogador, 'recompensa') / 100.0)), 'nome', t.nome));
      end if;
      if coalesce(t.falas->>'derrota', '') <> '' then
        ev := ev || jsonb_build_array(jsonb_build_object('t', 'fala', 'nome', t.nome, 'texto', t.falas->>'derrota'));
      end if;
    end if;
    if p_fim = 'vitoria' and jsonb_array_length(p_exp) > 0 then
      select array_agg(distinct (e)::uuid) into part from jsonb_array_elements_text(p_meta->'participantes') e;
      n := coalesce(array_length(part, 1), 1);
      n := greatest(1, (select count(*) from public.pokemons where dono = b.jogador and posicao is not null));
      for pk in select * from public.pokemons where dono = b.jogador and posicao is not null loop
        for x in select * from jsonb_array_elements(p_exp) loop
          sel := jsonb_build_object('exp_base', greatest(1, round((x->>'exp_base')::numeric * public._xp_mult_time() / n)), 'nivel', (x->>'nivel')::int);
          select * into pk2 from public.pokemons where id = pk.id;
          ev := public._dar_exp(pk2, sel, ev);
        end loop;
      end loop;
      -- Cura Rápida: recupera uma parte do HP de quem lutou
      if public._bonus(b.jogador, 'cura_rapida') > 0 then
        update public.pokemons set hp_atual = least(hp_max, hp_atual + ceil(hp_max * public._bonus(b.jogador, 'cura_rapida') / 100.0)::int)
         where id = any(coalesce(part, '{}')) and dono = b.jogador and hp_atual > 0;
      end if;
    end if;
  end if;
  return ev;
end $$;

create or replace function public.duelo_aplicar(p_row uuid, p_time jsonb, p_ganhou boolean, p_exp jsonb, p_part jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare b public.batalhas; m jsonb; pk public.pokemons; pk2 public.pokemons; novo jsonb; k int; ev jsonb := '[]'::jsonb; sel jsonb; part uuid[]; n int; x jsonb;
begin
  select * into b from public.batalhas where id = p_row for update;
  if not found or b.amistoso or b.aplicado then return '[]'::jsonb; end if;
  update public.batalhas set aplicado = true where id = b.id;
  for m in select * from jsonb_array_elements(p_time) loop
    select * into pk from public.pokemons where id = (m->>'id')::uuid and dono = b.jogador;
    if found then
      novo := '[]'::jsonb;
      for k in 0 .. jsonb_array_length(pk.golpes) - 1 loop
        novo := novo || jsonb_build_array((pk.golpes->k) || jsonb_build_object('pp', coalesce((m->'pp'->>k)::int, (pk.golpes->k->>'pp')::int)));
      end loop;
      update public.pokemons set hp_atual = greatest(0, least((m->>'hp')::int, hp_max)), golpes = novo where id = pk.id;
    end if;
  end loop;
  if p_ganhou and jsonb_array_length(coalesce(p_exp, '[]'::jsonb)) > 0 then
    select array_agg(distinct (e)::uuid) into part from jsonb_array_elements_text(coalesce(p_part, '[]'::jsonb)) e;
    n := coalesce(array_length(part, 1), 1);
    n := greatest(1, (select count(*) from public.pokemons where dono = b.jogador and posicao is not null));
    for pk in select * from public.pokemons where dono = b.jogador and posicao is not null loop
      for x in select * from jsonb_array_elements(p_exp) loop
        sel := jsonb_build_object('exp_base', greatest(1, round((x->>'exp_base')::numeric * public._xp_mult_time() / n)), 'nivel', (x->>'nivel')::int);
        select * into pk2 from public.pokemons where id = pk.id;
        ev := public._dar_exp(pk2, sel, ev);
      end loop;
    end loop;
  end if;
  return ev;
end $$;

revoke all on function public.duelo_aplicar(uuid, jsonb, boolean, jsonb, jsonb) from public, anon, authenticated;
grant execute on function public.duelo_aplicar(uuid, jsonb, boolean, jsonb, jsonb) to service_role;
