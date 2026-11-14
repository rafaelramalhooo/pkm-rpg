-- m33: o laboratório aceita o jogador a até 2 passos do ponto (o Prof. Carvalho agora é um NPC visível)
create or replace function public._poi_aqui(p_j public.jogadores, p_tipo text) returns boolean language sql stable as
$$ select exists (select 1 from public.mapas m, jsonb_array_elements(m.pois) p
    where m.id = p_j.mapa_id and p->>'tipo' = p_tipo
      and abs((p->>'x')::int - p_j.x) + abs((p->>'y')::int - p_j.y) <= case when p_tipo = 'lab' then 2 else 0 end) $$;

-- m33: "Viajar para…" só vale para lugares já visitados.
-- Todo lugar onde o jogador pisa (a pé, portal, viagem) entra em mapas_visitados por gatilho.
create or replace function public._registrar_visita() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.mapa_id is not null and (tg_op = 'INSERT' or new.mapa_id is distinct from old.mapa_id) then
    insert into public.mapas_visitados (jogador, mapa_id) values (new.id, new.mapa_id) on conflict do nothing;
  end if;
  return new;
end $$;
drop trigger if exists trg_registrar_visita on public.jogadores;
create trigger trg_registrar_visita after insert or update of mapa_id on public.jogadores
  for each row execute function public._registrar_visita();
-- quem já está em algum lugar conta como tendo visitado
insert into public.mapas_visitados (jogador, mapa_id) select id, mapa_id from public.jogadores where mapa_id is not null on conflict do nothing;

create or replace function public.mapa_mundi()
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_j public.jogadores;
begin
  if auth.uid() is null then raise exception 'Faça login primeiro.'; end if;
  select * into v_j from public.jogadores where id = auth.uid();
  if not found then raise exception 'Crie seu personagem primeiro.'; end if;
  insert into public.mapas_visitados (jogador, mapa_id) values (v_j.id, v_j.mapa_id) on conflict do nothing;
  return jsonb_build_object('atual', v_j.mapa_id, 'mestre', v_j.papel = 'mestre', 'insignias', coalesce(array_length(v_j.insignias, 1), 0),
    'visitados', coalesce((select jsonb_agg(mapa_id) from public.mapas_visitados where jogador = v_j.id), '[]'::jsonb));
end;
$$;
grant execute on function public.mapa_mundi() to authenticated;

create or replace function public.viajar(p_mapa text)
returns public.jogadores language plpgsql security definer set search_path = public as $$
declare
  v_j public.jogadores; v_m public.mapas; v_x int; v_y int; v_dir text := 'baixo';
begin
  if auth.uid() is null then raise exception 'Faça login primeiro.'; end if;
  select * into v_j from public.jogadores where id = auth.uid() for update;
  if not found then raise exception 'Crie seu personagem primeiro.'; end if;
  if exists (select 1 from public.batalhas where jogador = v_j.id and estado = 'ativa') then
    raise exception 'Termine a batalha primeiro.';
  end if;
  select * into v_m from public.mapas where id = p_mapa;
  if not found or v_m.tipo <> 'andavel' or v_m.solido is null then raise exception 'Destino inválido.'; end if;
  if v_j.mapa_id = p_mapa then raise exception 'Você já está aqui.'; end if;
  if v_j.papel <> 'mestre' then
    if p_mapa like 'gin\_%' or p_mapa like 'liga\_%' or p_mapa = 'lab' then
      raise exception 'Este lugar não aceita viagem rápida.';
    end if;
    if p_mapa = 'plato' and coalesce(array_length(v_j.insignias, 1), 0) < 8 then
      raise exception 'O Platô Prisma (Liga) só abre para quem tem 8 insígnias (você tem %).', coalesce(array_length(v_j.insignias, 1), 0);
    end if;
    if not exists (select 1 from public.mapas_visitados where jogador = v_j.id and mapa_id = p_mapa) then
      raise exception 'Você ainda não esteve aqui. Chegue a pé primeiro.';
    end if;
  end if;
  select (p->>'dx')::int, (p->>'dy')::int, coalesce(p->>'dir', 'baixo') into v_x, v_y, v_dir
    from public.mapas o, jsonb_array_elements(o.portais) p
   where p->>'dest' = p_mapa and o.id <> p_mapa
   order by o.id limit 1;
  if v_x is null and v_m.spawn_x is not null and substr(v_m.solido, v_m.spawn_y * v_m.largura + v_m.spawn_x + 1, 1) = '0' then
    v_x := v_m.spawn_x; v_y := v_m.spawn_y;
  end if;
  if v_x is null then raise exception 'Este lugar ainda não tem ponto de chegada.'; end if;
  delete from public.ofertas where jogador = v_j.id;
  update public.jogadores set mapa_id = p_mapa, x = v_x, y = v_y, direcao = v_dir, posicao_em = clock_timestamp()
   where id = v_j.id returning * into v_j;
  return v_j;
end;
$$;
grant execute on function public.viajar(text) to authenticated;
