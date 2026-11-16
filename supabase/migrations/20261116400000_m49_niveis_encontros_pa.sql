-- m49: níveis proporcionais ao time (sem pisos fixos), selvagens limitados, chance de encontro por piso, PA 30 às 6h.
-- Faixas de nível em relação à média do time: rota -2..+1, desafiante de caminho 0..+2, líder de ginásio +2..+4, Liga +4..+6.
create or replace function public._equipe_escalada(t public.treinadores, p_ref int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  esc jsonb := t.escala; n int := coalesce((esc->>'time')::int, 3); bonus int := coalesce((esc->>'bonus')::int, 0);
  piso int := coalesce((esc->>'piso')::int, 1); dif int := public._dificuldade();
  lo int := case when t.id like 'liga\_%' then 4 when t.lider then 2 when t.id like 'mq\_%' then 0 else -2 end;
  hi int := case when t.id like 'liga\_%' then 6 when t.lider then 4 when t.id like 'mq\_%' then 2 else 1 end;
  ace jsonb := esc->'ace'; pool jsonb := esc->'pool'; k int; total int; lvl int; ent jsonb; usadas int[] := '{}'; res jsonb := '[]'::jsonb;
  menos int := 0; off int;
begin
  total := n - case when ace is not null then 1 else 0 end;
  for k in 1 .. total loop
    off := lo + floor(random() * (hi - lo + 1))::int;
    lvl := least(1000, greatest(1, p_ref + dif + off));
    ent := null;
    select e into ent from jsonb_array_elements(pool) e
     where (e->>'de')::int <= lvl and (e->>'ate')::int >= lvl and not ((e->>'linha')::int = any(usadas)) order by random() limit 1;
    if ent is null then
      select e into ent from jsonb_array_elements(pool) e where (e->>'de')::int <= lvl and (e->>'ate')::int >= lvl order by random() limit 1;
    end if;
    if ent is null then
      select e into ent from jsonb_array_elements(pool) e order by (e->>'de')::int, random() limit 1;
    end if;
    usadas := usadas || (ent->>'linha')::int;
    res := res || public._equipe_treinador(jsonb_build_array(jsonb_build_object('especie', (ent->>'e')::int, 'nivel', lvl)));
  end loop;
  if ace is not null then
    lvl := least(1000, greatest(1, p_ref + hi + dif));
    res := res || public._equipe_treinador(jsonb_build_array(jsonb_build_object('especie', (ace->>'e')::int, 'nivel', lvl)));
  end if;
  return res;
end $$;
revoke all on function public._equipe_escalada(public.treinadores, int) from public, anon, authenticated;

create or replace function public.gerar_oferta()
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_j public.jogadores; v_m public.mapas; v_o public.ofertas; v_c char(1); v_bioma text; v_chave text;
  v_total int; v_r int; v_acc int := 0; v_e record; v_nivel int; v_chance int;
begin
  if auth.uid() is null then raise exception 'Faça login primeiro.'; end if;
  select * into v_j from public.jogadores where id = auth.uid() for update;
  if not found then raise exception 'Crie seu personagem primeiro.'; end if;
  v_chave := v_j.mapa_id || ':' || v_j.x || ':' || v_j.y;
  select * into v_o from public.ofertas where jogador = v_j.id;
  if found and v_o.mapa_id = v_j.mapa_id and v_o.x = v_j.x and v_o.y = v_j.y then
    return jsonb_build_object('especie_id', v_o.especie_id, 'nome', (select nome from public.especies where id = v_o.especie_id), 'nivel', v_o.nivel, 'bioma', v_o.bioma);
  end if;
  delete from public.ofertas where jogador = v_j.id;
  if v_j.rolagem = v_chave then return null; end if;                                             -- já sorteou neste tile
  if v_j.rolagem_em is not null and v_j.rolagem_em > clock_timestamp() - interval '150 milliseconds' then return null; end if;
  if exists (select 1 from public.batalhas where jogador = v_j.id and estado = 'ativa') then return null; end if;
  if not exists (select 1 from public.pokemons where dono = v_j.id and posicao is not null and hp_atual > 0) then return null; end if;
  update public.jogadores set rolagem = v_chave, rolagem_em = clock_timestamp() where id = v_j.id;

  select * into v_m from public.mapas where id = v_j.mapa_id;
  if v_m.bioma is null then return null; end if;
  v_c := substr(v_m.bioma, v_j.y * v_m.largura + v_j.x + 1, 1);
  v_bioma := case v_c when 'G' then 'grama' when 'E' then 'estrada' when 'F' then 'floresta' when 'A' then 'agua' when 'C' then 'campo' else null end;
  if v_bioma is null then return null; end if;
  -- cidades: chance rara; fora delas, a chance depende do piso (grama é a mais efetiva). Valores em config 'chance_bioma'.
  v_chance := case when v_m.chance_oferta is not null then least(v_m.chance_oferta, 3)
    else coalesce((select (valor ->> v_bioma)::int from public.config where chave = 'chance_bioma'), 30) end;
  v_chance := least(100, round(v_chance * public._ev('encontro', 1)))::int;
  if floor(random() * 100) >= v_chance then return null; end if;

  if v_m.nivel_piso is null then
  select coalesce(sum(peso), 0) into v_total from public.encontros where mapa_id = v_j.mapa_id and bioma = v_bioma;
  if v_total = 0 then return null; end if;
  v_r := floor(random() * v_total);
  for v_e in select * from public.encontros where mapa_id = v_j.mapa_id and bioma = v_bioma order by especie_id loop
    v_acc := v_acc + v_e.peso;
    if v_r < v_acc then exit; end if;
  end loop;
  v_nivel := v_e.nivel_min + floor(random() * (v_e.nivel_max - v_e.nivel_min + 1));
  else
    v_nivel := greatest(least(v_m.nivel_piso, public._nivel_ref(v_j.id) + 2), least(v_m.nivel_teto, public._nivel_ref(v_j.id) + 5, public._nivel_ref(v_j.id) + coalesce(v_m.nivel_bonus, 0) + public._dificuldade() + floor(random() * 4)::int - 2));
    select coalesce(sum(peso), 0) into v_total from public.encontros where mapa_id = v_j.mapa_id and bioma = v_bioma and v_nivel between nivel_min and nivel_max;
    if v_total = 0 then
      select * into v_e from public.encontros where mapa_id = v_j.mapa_id and bioma = v_bioma
       order by greatest(nivel_min - v_nivel, v_nivel - nivel_max, 0), random() limit 1;
      if not found then return null; end if;
      v_nivel := greatest(v_e.nivel_min, least(v_e.nivel_max, v_nivel));
    else
      v_r := floor(random() * v_total);
      for v_e in select * from public.encontros where mapa_id = v_j.mapa_id and bioma = v_bioma and v_nivel between nivel_min and nivel_max order by especie_id loop
        v_acc := v_acc + v_e.peso;
        if v_r < v_acc then exit; end if;
      end loop;
    end if;
  end if;
  if v_nivel > public._nivel_ref(v_j.id) + 8 then return null; end if;   -- nada de selvagem muito acima do time
  insert into public.ofertas (jogador, mapa_id, x, y, especie_id, nivel, bioma) values (v_j.id, v_j.mapa_id, v_j.x, v_j.y, v_e.especie_id, v_nivel, v_bioma);
  return jsonb_build_object('especie_id', v_e.especie_id, 'nome', (select nome from public.especies where id = v_e.especie_id), 'nivel', v_nivel, 'bioma', v_bioma);
end $$;

insert into public.config (chave, valor) values ('chance_bioma', '{"grama": 45, "floresta": 35, "campo": 20, "agua": 20, "estrada": 8}'::jsonb) on conflict (chave) do nothing;

-- PA: 30 por dia, recarga às 6h (horário de São Paulo), sem acumular (quem tem mais por bônus do Mestre mantém)
alter table public.jogadores add column if not exists pa_dia date;
create or replace function public._pa_virada() returns int language plpgsql security definer set search_path = public as $$
declare d date := public._dia_jogo(); n int;
begin
  update public.jogadores set pa = greatest(pa, coalesce((select (valor #>> '{}')::int from public.config where chave = 'pa_por_dia'), 30)), pa_dia = d
   where pa_dia is distinct from d;
  get diagnostics n = row_count; return n;
end $$;
revoke all on function public._pa_virada() from public, anon, authenticated;

create or replace function public.pa_garantir() returns int language plpgsql security definer set search_path = public as $$
declare d date := public._dia_jogo(); v int;
begin
  if auth.uid() is null then return null; end if;
  update public.jogadores set pa = greatest(pa, coalesce((select (valor #>> '{}')::int from public.config where chave = 'pa_por_dia'), 30)), pa_dia = d
   where id = auth.uid() and pa_dia is distinct from d;
  select pa into v from public.jogadores where id = auth.uid();
  return v;
end $$;
revoke all on function public.pa_garantir() from public, anon;
grant execute on function public.pa_garantir() to authenticated;

-- agenda diária às 9h UTC = 6h de São Paulo (pg_cron)
create extension if not exists pg_cron with schema extensions;
select cron.schedule('pa_virada_6h', '0 9 * * *', 'select public._pa_virada()');
