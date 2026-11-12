-- m12: Mapa Mundi — mapas visitados + viagem rápida validada no servidor
create table if not exists public.mapas_visitados (
  jogador uuid not null references public.jogadores(id) on delete cascade,
  mapa_id text not null,
  em timestamptz not null default now(),
  primary key (jogador, mapa_id)
);
alter table public.mapas_visitados enable row level security;
drop policy if exists mv_ler on public.mapas_visitados;
create policy mv_ler on public.mapas_visitados for select using (jogador = auth.uid());

-- quem já está em algum mapa conta como tendo visitado (e o início)
insert into public.mapas_visitados (jogador, mapa_id)
select id, mapa_id from public.jogadores where mapa_id is not null on conflict do nothing;
insert into public.mapas_visitados (jogador, mapa_id)
select j.id, m from public.jogadores j, unnest(array['lab','pallet']) m
where exists (select 1 from public.mapas where id = m) on conflict do nothing;

-- andar(): registra o mapa de destino ao atravessar um portal
do $mig$
declare v_def text;
begin
  select pg_get_functiondef('public.andar(text)'::regprocedure) into v_def;
  if v_def not like '%mapas_visitados%' then
    v_def := replace(v_def,
      E'      return v_j;\n    end if;\n  end loop;',
      E'      insert into public.mapas_visitados (jogador, mapa_id) values (v_j.id, v_j.mapa_id) on conflict do nothing;\n      return v_j;\n    end if;\n  end loop;');
    if v_def not like '%mapas_visitados%' then raise exception 'Não foi possível atualizar andar().'; end if;
    execute v_def;
  end if;
end
$mig$;

create or replace function public.mapa_mundi()
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_j public.jogadores;
begin
  if auth.uid() is null then raise exception 'Faça login primeiro.'; end if;
  select * into v_j from public.jogadores where id = auth.uid();
  if not found then raise exception 'Crie seu personagem primeiro.'; end if;
  insert into public.mapas_visitados (jogador, mapa_id) values (v_j.id, v_j.mapa_id) on conflict do nothing;
  return jsonb_build_object('atual', v_j.mapa_id, 'mestre', v_j.papel = 'mestre',
    'visitados', coalesce((select jsonb_agg(mapa_id) from public.mapas_visitados where jogador = v_j.id), '[]'::jsonb));
end;
$$;

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
    if not exists (select 1 from public.mapas_visitados where jogador = v_j.id and mapa_id = p_mapa) then
      raise exception 'Você ainda não esteve em %. Chegue lá a pé primeiro.', v_m.nome;
    end if;
  end if;
  -- chegada: spawn do mapa ou o tile de chegada de um portal que leva até ele
  if v_m.spawn_x is not null and v_m.spawn_y is not null then
    v_x := v_m.spawn_x; v_y := v_m.spawn_y;
  else
    select (p->>'dx')::int, (p->>'dy')::int, coalesce(p->>'dir', 'baixo') into v_x, v_y, v_dir
      from public.mapas o, jsonb_array_elements(o.portais) p
     where p->>'dest' = p_mapa and o.id <> p_mapa
     order by o.id limit 1;
  end if;
  if v_x is null then raise exception 'Este lugar ainda não tem ponto de chegada.'; end if;
  delete from public.ofertas where jogador = v_j.id;
  update public.jogadores set mapa_id = p_mapa, x = v_x, y = v_y, direcao = v_dir, posicao_em = clock_timestamp()
   where id = v_j.id returning * into v_j;
  insert into public.mapas_visitados (jogador, mapa_id) values (v_j.id, p_mapa) on conflict do nothing;
  return v_j;
end;
$$;
grant execute on function public.mapa_mundi() to authenticated;
grant execute on function public.viajar(text) to authenticated;
