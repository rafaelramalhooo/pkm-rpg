-- m73: Reserva Dourada com encontro por passo (como num Safári), sem depender de o jogador parar
insert into public.config (chave, valor) values ('reserva_chance_passo', '7'::jsonb) on conflict (chave) do nothing;

create or replace function public._reserva_sortear(p_j uuid, p_x int, p_y int) returns void
language plpgsql security definer set search_path = public as $$
declare v public.reserva_visitas; m public.mapas; c char(1); b text; ref int; nv int; tot int; r int; acc int := 0; e record;
begin
  select * into v from public.reserva_visitas where jogador = p_j and ativa;
  if not found or v.enc is not null or v.passos <= 0 then return; end if;
  if random() * 100 >= coalesce((select (valor #>> '{}')::numeric from public.config where chave = 'reserva_chance_passo'), 7) then return; end if;
  select * into m from public.mapas where id = 'reserva';
  c := substr(m.bioma, p_y * m.largura + p_x + 1, 1);
  b := case c when 'G' then 'grama' when 'E' then 'estrada' when 'F' then 'floresta' when 'C' then 'campo' else null end;
  if b is null then return; end if;
  ref := public._nivel_ref(p_j);
  nv := greatest(least(m.nivel_piso, ref + 2), least(m.nivel_teto, ref + 5, ref + coalesce(m.nivel_bonus, 0) + public._dificuldade() + floor(random() * 4)::int - 2));
  select coalesce(sum(peso), 0) into tot from public.encontros where mapa_id = 'reserva' and bioma = b and nv between nivel_min and nivel_max;
  if tot = 0 then
    select * into e from public.encontros where mapa_id = 'reserva' and bioma = b order by greatest(nivel_min - nv, nv - nivel_max, 0), random() limit 1;
    if not found then return; end if;
    nv := greatest(e.nivel_min, least(e.nivel_max, nv));
  else
    r := floor(random() * tot);
    for e in select * from public.encontros where mapa_id = 'reserva' and bioma = b and nv between nivel_min and nivel_max order by especie_id loop
      acc := acc + e.peso; if r < acc then exit; end if;
    end loop;
  end if;
  update public.reserva_visitas set enc = jsonb_build_object('especie_id', e.especie_id, 'nivel', nv, 'iscas', 0, 'pedras', 0) where id = v.id;
end $$;
revoke all on function public._reserva_sortear(uuid, int, int) from public, anon, authenticated;

create or replace function public._reserva_passo(p_j uuid, p_x int, p_y int) returns void
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  update public.reserva_visitas set passos = greatest(passos - 1, 0) where jogador = p_j and ativa returning passos into n;
  if not found then return; end if;
  if n = 0 then perform public._reserva_fim(p_j); else perform public._reserva_sortear(p_j, p_x, p_y); end if;
end $$;
revoke all on function public._reserva_passo(uuid, int, int) from public, anon, authenticated;

create or replace function public._pt2(d text, a text, b text, p_todos boolean default false) returns text
language plpgsql as $$
declare rx text; r text;
begin
  rx := regexp_replace(a, '([\\.\[\](){}*+?^$|])', '\\\1', 'g');
  rx := regexp_replace(rx, '\s+', '\\s+', 'g');
  r := regexp_replace(d, rx, b, case when p_todos then 'g' else '' end);
  if r = d then raise exception 'm73: trecho não encontrado: %', left(a, 80); end if;
  return r;
end $$;
do $m73$
declare d text;
begin
  d := pg_get_functiondef('public.andar(text)'::regprocedure);
  d := public._pt2(d, 'perform public._reserva_passo(v_j.id);', 'perform public._reserva_passo(v_j.id, v_nx, v_ny);');
  execute d;
  d := pg_get_functiondef('public.gerar_oferta()'::regprocedure);
  d := public._pt2(d, 'v_chance := case when v_m.chance_oferta is not null',
    'if v_j.mapa_id = ''reserva'' and v_bioma <> ''agua'' then return null; end if; v_chance := case when v_m.chance_oferta is not null');
  execute d;
end $m73$;
drop function public._pt2(text, text, text, boolean);
drop function if exists public._reserva_passo(uuid);
