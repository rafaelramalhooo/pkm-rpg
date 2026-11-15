-- m45: rivais NPC com vida própria (modos: lider | autonomo | media), ritmo diário, pontos extras do Mestre e notícias do ranking.
alter table public.ranking_rivais add column if not exists modo text not null default 'lider';
alter table public.ranking_rivais add column if not exists ritmo numeric not null default 40;
alter table public.ranking_rivais drop constraint if exists ranking_rivais_modo_chk;
alter table public.ranking_rivais add constraint ranking_rivais_modo_chk check (modo in ('lider', 'autonomo', 'media'));
alter table public.ranking_rivais_pontos add column if not exists extra int not null default 0;

update public.ranking_rivais set modo = 'lider', fator = v.f from (values ('rv_gary', 0.95), ('rv_lance', 0.90), ('rv_blue', 0.85), ('rv_cynthia', 0.80)) v(i, f) where id = v.i;
update public.ranking_rivais set modo = 'autonomo', ritmo = v.r from (values ('rv_red', 75), ('rv_steven', 65), ('rv_misty', 55), ('rv_lorelei', 50), ('rv_bruno', 45),
  ('rv_agatha', 40), ('rv_brock', 35), ('rv_sabrina', 30), ('rv_erika', 25), ('rv_vaga1', 30), ('rv_vaga2', 30), ('rv_vaga3', 30), ('rv_vaga4', 30)) v(i, r) where id = v.i;
update public.ranking_rivais set modo = 'media', fator = v.f from (values ('rv_koga', 0.90), ('rv_surge', 0.75), ('rv_giovanni', 0.60), ('rv_brendan', 0.40)) v(i, f) where id = v.i;
delete from public.ranking_rivais_pontos where periodo in (select id from public.ranking_periodos where estado = 'ativo');

-- pontos de um rival autônomo num dia: ritmo ±40%, 8% de dia parado, 8% de maratona (x2,2); determinístico por rival e dia
create or replace function public._rival_dia(p_id text, p_ritmo numeric, p_dia date) returns int language sql stable as $$
  select case
    when abs(hashtext(p_id || 'd' || p_dia::text)) % 100 < 8 then 0
    when abs(hashtext(p_id || 'd' || p_dia::text)) % 100 >= 92 then round(p_ritmo * 2.2)::int
    else round(p_ritmo * (1 + ((abs(hashtext(p_id || 'j' || p_dia::text)) % 81) - 40) / 100.0))::int
  end
$$;

create or replace function public._rival_pts(p_id text, p_modo text, p_fator numeric, p_ritmo numeric, p_ini date, p_ate date, p_lider int, p_media int, p_extra int) returns int
language plpgsql stable as $$
declare jit numeric := ((abs(hashtext(p_id || p_ate::text)) % 21) - 10) / 100.0; base int;
begin
  if p_modo = 'autonomo' then
    select coalesce(sum(public._rival_dia(p_id, p_ritmo, g::date)), 0) into base from generate_series(p_ini::timestamp, p_ate::timestamp, interval '1 day') g;
  elsif p_modo = 'media' then base := round(p_media * p_fator * (1 + jit));
  else base := round(p_lider * p_fator * (1 + jit)); end if;
  return greatest(base + p_extra, 0);
end $$;
revoke all on function public._rival_dia(text, numeric, date), public._rival_pts(text, text, numeric, numeric, date, date, int, int, int) from public, anon, authenticated;

create or replace function public.ranking_tabela() returns jsonb language plpgsql security definer set search_path = public as $$
declare per public.ranking_periodos; d date := public._dia_jogo(); lider int; media int; lider0 int; media0 int; r record; novo int; ent jsonb; linhas jsonb; noticias jsonb := '[]'::jsonb;
  l_agora text; l_antes text; txt text;
begin
  if auth.uid() is null or not public._modulo('ranking') then return jsonb_build_object('ativo', false); end if;
  select * into per from public.ranking_periodos where id = public._ranking_periodo();
  select coalesce(max(rp.pontos), 0), coalesce(round(avg(rp.pontos) filter (where rp.pontos > 0)), 0) into lider, media
    from public.ranking_pontos rp join public.jogadores j on j.id = rp.jogador where rp.periodo = per.id and j.papel <> 'mestre';
  with t as (select e.jogador, sum(e.pontos) p from public.ranking_eventos e join public.jogadores j on j.id = e.jogador
              where e.periodo = per.id and e.dia_jogo < d and j.papel <> 'mestre' group by e.jogador)
  select coalesce(max(p), 0), coalesce(round(avg(p) filter (where p > 0)), 0) into lider0, media0 from t;
  for r in select rv.*, coalesce(rp.extra, 0) as extra from public.ranking_rivais rv left join public.ranking_rivais_pontos rp on rp.periodo = per.id and rp.rival = rv.id where rv.ativo loop
    novo := public._rival_pts(r.id, r.modo, r.fator, r.ritmo, per.inicio, d, lider, media, r.extra);
    insert into public.ranking_rivais_pontos (periodo, rival, pontos) values (per.id, r.id, novo)
    on conflict (periodo, rival) do update set pontos = greatest(public.ranking_rivais_pontos.pontos, excluded.pontos);
  end loop;
  select coalesce(jsonb_agg(to_jsonb(q)), '[]'::jsonb) into ent from (
    select j.nome as nome, false as npc, rp.pontos as agora,
           coalesce((select sum(e.pontos) from public.ranking_eventos e where e.periodo = per.id and e.jogador = j.id and e.dia_jogo < d), 0)::int as antes
      from public.ranking_pontos rp join public.jogadores j on j.id = rp.jogador where rp.periodo = per.id and j.papel <> 'mestre'
    union all
    select rv.nome, true, rvp.pontos, least(rvp.pontos, public._rival_pts(rv.id, rv.modo, rv.fator, rv.ritmo, per.inicio, d - 1, lider0, media0, rvp.extra))
      from public.ranking_rivais_pontos rvp join public.ranking_rivais rv on rv.id = rvp.rival where rvp.periodo = per.id and rv.ativo
  ) q;
  -- notícias do mundo
  select x.nome into l_agora from jsonb_to_recordset(ent) x(nome text, npc boolean, agora int, antes int) order by x.agora desc, x.nome limit 1;
  select x.nome into l_antes from jsonb_to_recordset(ent) x(nome text, npc boolean, agora int, antes int) where x.antes > 0 order by x.antes desc, x.nome limit 1;
  if l_antes is not null and l_agora is not null and l_agora <> l_antes then noticias := noticias || to_jsonb('👑 ' || l_agora || ' assumiu a liderança do ranking!'::text); end if;
  for txt in select '🔀 ' || a.nome || ' passou ' || b.nome || '!'
             from jsonb_to_recordset(ent) a(nome text, npc boolean, agora int, antes int), jsonb_to_recordset(ent) b(nome text, npc boolean, agora int, antes int)
            where a.antes < b.antes and a.agora > b.agora and b.antes > 0 and not (a.npc and b.npc)
            order by a.agora desc, b.agora desc limit 3 loop
    noticias := noticias || to_jsonb(txt);
  end loop;
  for txt in select '🔥 ' || rv.nome || ' fez uma maratona hoje (+' || round(rv.ritmo * 2.2)::int || ' pontos)!'
             from public.ranking_rivais rv where rv.ativo and rv.modo = 'autonomo' and abs(hashtext(rv.id || 'd' || d::text)) % 100 >= 92 order by rv.nome limit 2 loop
    noticias := noticias || to_jsonb(txt);
  end loop;
  for txt in select '😴 ' || rv.nome || ' descansou hoje.'
             from public.ranking_rivais rv where rv.ativo and rv.modo = 'autonomo' and abs(hashtext(rv.id || 'd' || d::text)) % 100 < 8 order by rv.nome limit 1 loop
    noticias := noticias || to_jsonb(txt);
  end loop;
  select coalesce(jsonb_agg(x order by (x ->> 'pontos')::int desc, x ->> 'nome'), '[]'::jsonb) into linhas from (
    select jsonb_build_object('nome', j.nome, 'pontos', rp.pontos, 'npc', false, 'eu', j.id = auth.uid(), 'titulo', (select c.nome from public.cosmeticos_catalogo c where c.id = j.titulo_ativo),
             'moldura', (select c.estilo from public.cosmeticos_catalogo c where c.id = j.moldura_ativa)) as x
      from public.ranking_pontos rp join public.jogadores j on j.id = rp.jogador where rp.periodo = per.id and rp.pontos > 0 and j.papel <> 'mestre'
    union all
    select jsonb_build_object('nome', rv.nome, 'pontos', rvp.pontos, 'npc', true, 'eu', false)
      from public.ranking_rivais_pontos rvp join public.ranking_rivais rv on rv.id = rvp.rival where rvp.periodo = per.id and rv.ativo and rvp.pontos > 0
  ) t2;
  return jsonb_build_object('ativo', true, 'periodo', jsonb_build_object('id', per.id, 'inicio', per.inicio, 'fim', per.fim, 'dias_restantes', greatest(per.fim - d, 0)),
    'meus_pontos', coalesce((select pontos from public.ranking_pontos where periodo = per.id and jogador = auth.uid()), 0),
    'premios', coalesce((select valor from public.config where chave = 'ranking_premios'), '{}'::jsonb), 'linhas', linhas, 'noticias', noticias);
end $$;

create or replace function public.mestre_ranking_salvar(p jsonb) returns void language plpgsql security definer set search_path = public as $$
declare k text; r jsonb; pd jsonb;
begin
  if not public.eh_mestre() then raise exception 'Só o Mestre.'; end if;
  if p ? 'duracao' then
    if (p ->> 'duracao')::int not between 1 and 120 then raise exception 'A duração vai de 1 a 120 dias.'; end if;
    insert into public.config (chave, valor) values ('ranking_duracao_dias', to_jsonb((p ->> 'duracao')::int)) on conflict (chave) do update set valor = excluded.valor;
    if coalesce((p ->> 'aplicar_atual')::boolean, false) then
      update public.ranking_periodos set fim = inicio + (p ->> 'duracao')::int where estado = 'ativo';
    end if;
  end if;
  if p ? 'premios' then
    for pd in select * from jsonb_array_elements(coalesce(p -> 'premios' -> 'podio', '[]'::jsonb)) loop perform public._payload_ok(pd); end loop;
    perform public._payload_ok(p -> 'premios' -> 'participacao');
  end if;
  foreach k in array array['pontos', 'tetos', 'pares', 'premios'] loop
    if p ? k then
      insert into public.config (chave, valor) values ('ranking_' || k, p -> k) on conflict (chave) do update set valor = excluded.valor;
    end if;
  end loop;
  for r in select * from jsonb_array_elements(coalesce(p -> 'rivais', '[]'::jsonb)) loop
    if r ? 'modo' and (r ->> 'modo') not in ('lider', 'autonomo', 'media') then raise exception 'Modo de rival inválido.'; end if;
    if r ? 'ritmo' and ((r ->> 'ritmo')::numeric < 0 or (r ->> 'ritmo')::numeric > 1000) then raise exception 'O ritmo vai de 0 a 1000 pontos por dia.'; end if;
    update public.ranking_rivais set fator = coalesce((r ->> 'fator')::numeric, fator), ativo = coalesce((r ->> 'ativo')::boolean, ativo), nome = coalesce(nullif(r ->> 'nome', ''), nome),
      modo = coalesce(r ->> 'modo', modo), ritmo = coalesce((r ->> 'ritmo')::numeric, ritmo)
     where id = r ->> 'id';
  end loop;
end $$;

-- pontos extras do Mestre para um rival (positivo ou negativo)
create or replace function public.mestre_rival_pontos(p_id text, p_delta int) returns void language plpgsql security definer set search_path = public as $$
declare per int;
begin
  if not public.eh_mestre() then raise exception 'Só o Mestre.'; end if;
  if p_delta = 0 or abs(p_delta) > 100000 then raise exception 'Valor inválido.'; end if;
  if not exists (select 1 from public.ranking_rivais where id = p_id) then raise exception 'Rival não encontrado.'; end if;
  per := public._ranking_periodo();
  insert into public.ranking_rivais_pontos (periodo, rival, pontos, extra) values (per, p_id, greatest(p_delta, 0), p_delta)
  on conflict (periodo, rival) do update set extra = public.ranking_rivais_pontos.extra + p_delta, pontos = greatest(public.ranking_rivais_pontos.pontos + p_delta, 0);
end $$;

drop function if exists public.mestre_rival_criar(text, numeric);
create or replace function public.mestre_rival_criar(p_nome text, p_fator numeric, p_modo text default 'autonomo', p_ritmo numeric default 40) returns void language plpgsql security definer set search_path = public as $$
declare n text := btrim(coalesce(p_nome, ''));
begin
  if not public.eh_mestre() then raise exception 'Só o Mestre.'; end if;
  if char_length(n) not between 1 and 30 then raise exception 'O nome do rival deve ter de 1 a 30 letras.'; end if;
  if coalesce(p_fator, -1) not between 0 and 2 then raise exception 'O fator vai de 0 a 2.'; end if;
  if coalesce(p_modo, '') not in ('lider', 'autonomo', 'media') then raise exception 'Modo de rival inválido.'; end if;
  if coalesce(p_ritmo, -1) not between 0 and 1000 then raise exception 'O ritmo vai de 0 a 1000 pontos por dia.'; end if;
  if (select count(*) from public.ranking_rivais) >= 60 then raise exception 'Limite de 60 rivais.'; end if;
  insert into public.ranking_rivais (id, nome, fator, modo, ritmo) values ('rv_' || substr(md5(random()::text || clock_timestamp()::text), 1, 10), n, p_fator, p_modo, p_ritmo);
end $$;
revoke all on function public.mestre_rival_pontos(text, int), public.mestre_rival_criar(text, numeric, text, numeric) from public, anon;
grant execute on function public.mestre_rival_pontos(text, int), public.mestre_rival_criar(text, numeric, text, numeric) to authenticated;
