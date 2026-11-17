-- m77: 10 caixas + Caixa Principal (caixa 11, 6 espaços). Quem está na Caixa Principal ganha o mesmo XP por cabeça
-- de cada Pokémon do time quando o time vence (sem diluir o XP do time). Pontos/golpes novos ficam pendentes.
insert into public.config (chave, valor) values ('qtd_caixas', '10'::jsonb)
on conflict (chave) do update set valor = '10'::jsonb;

-- mover: permite a Caixa Principal (11) com até 6 espaços; as caixas comuns seguem 1..qtd_caixas
create or replace function public.caixa_mover(p_pokemon uuid, p_caixa int, p_slot int) returns void
language plpgsql security definer set search_path = public as $$
declare a public.pokemons; b public.pokemons;
begin
  perform public._caixa_pre();
  if p_caixa = 11 then
    if p_slot < 1 or p_slot > 6 then raise exception 'Espaço inválido.'; end if;
  elsif p_caixa < 1 or p_caixa > public._cfg_int('qtd_caixas', 10) or p_slot < 1 or p_slot > public._cfg_int('tam_caixa', 15) + floor(public._bonus(auth.uid(), 'espaco'))::int then
    raise exception 'Espaço inválido.';
  end if;
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

-- XP da Caixa Principal: patch no sim_gravar vivo
create or replace function public._pt(d text, a text, b text) returns text language plpgsql as $$
begin
  if position(a in d) = 0 then raise exception 'Trecho não encontrado: %', left(a, 60); end if;
  return replace(d, a, b);
end $$;

do $$
declare d text;
begin
  d := pg_get_functiondef('public.sim_gravar(uuid,integer,jsonb,jsonb,integer,jsonb,text,jsonb)'::regprocedure);
  if position('caixa = 11' in d) = 0 then
    d := public._pt(d, '      -- Cura Rápida: recupera uma parte do HP de quem lutou', '      -- Caixa Principal: mesmo XP por cabeça do time, sem diluir; eventos descartados (pontos e golpes ficam pendentes)
      for pk in select * from public.pokemons where dono = b.jogador and caixa = 11 loop
        for x in select * from jsonb_array_elements(p_exp) loop
          sel := jsonb_build_object(''exp_base'', greatest(1, round((x->>''exp_base'')::numeric * public._xp_mult_time() / n)), ''nivel'', (x->>''nivel'')::int);
          select * into pk2 from public.pokemons where id = pk.id;
          perform public._dar_exp(pk2, sel, ''[]''::jsonb);
        end loop;
      end loop;
      -- Cura Rápida: recupera uma parte do HP de quem lutou');
    execute d;
  end if;
end $$;
drop function public._pt(text, text, text);

-- ===== Ginásio e Liga: 2 a 3 Pokémon do NPC (sorteados) ganham um golpe de dano com vantagem sobre algum tipo do time do jogador.
-- O golpe vem do conjunto de golpes que a espécie aprende até o nível dela; nível e dificuldade não mudam. Feito uma vez, ao iniciar o desafio.
create or replace function public._golpes_vantagem(p_res jsonb, p_jog uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare tipos text[]; n int := jsonb_array_length(p_res); alvos int[]; i int; ent jsonb; esp public.especies; gs jsonb; c record; vit int;
begin
  select array_agg(distinct t) into tipos from public.pokemons p join public.especies e on e.id = p.especie_id cross join lateral unnest(e.tipos) t
   where p.dono = p_jog and p.posicao is not null;
  if tipos is null or n = 0 then return p_res; end if;
  select array_agg(q.i) into alvos from (select g as i from generate_series(0, n - 1) g order by random() limit (2 + floor(random() * 2)::int)) q;
  foreach i in array alvos loop
    ent := p_res -> i;
    gs := ent -> 'golpes';
    select * into esp from public.especies where id = (ent ->> 'especie_id')::int;
    if exists (select 1 from jsonb_array_elements(gs) x join public.golpes gg on gg.id = (x ->> 'id')::int
                where coalesce(gg.poder, 0) > 0 and exists (select 1 from public.eficacia ef where ef.atacante = gg.tipo and ef.defensor = any (tipos) and ef.mult >= 2)) then
      continue;
    end if;
    select a.golpe_id, g.pp into c
      from public.aprende a join public.golpes g on g.id = a.golpe_id
     where a.especie_id = esp.id and a.nivel <= (ent ->> 'nivel')::int and coalesce(g.poder, 0) > 0
       and exists (select 1 from public.eficacia ef where ef.atacante = g.tipo and ef.defensor = any (tipos) and ef.mult >= 2)
       and not exists (select 1 from jsonb_array_elements(gs) x where (x ->> 'id')::int = g.id)
     order by (g.tipo = any (esp.tipos)) desc, g.poder desc, random() limit 1;
    if c.golpe_id is null then continue; end if;
    if jsonb_array_length(gs) >= 4 then
      select (x ->> 'id')::int into vit from jsonb_array_elements(gs) x join public.golpes gg on gg.id = (x ->> 'id')::int order by coalesce(gg.poder, 0), random() limit 1;
      select coalesce(jsonb_agg(x), '[]'::jsonb) into gs from jsonb_array_elements(gs) x where (x ->> 'id')::int <> vit;
    end if;
    gs := gs || jsonb_build_array(jsonb_build_object('id', c.golpe_id, 'pp', c.pp));
    p_res := jsonb_set(p_res, array[i::text, 'golpes'], gs);
  end loop;
  return p_res;
end $$;
revoke all on function public._golpes_vantagem(jsonb, uuid) from public, anon, authenticated;

create or replace function public._pt(d text, a text, b text) returns text language plpgsql as $$
begin
  if position(a in d) = 0 then raise exception 'Trecho não encontrado: %', left(a, 60); end if;
  return replace(d, a, b);
end $$;
do $$
declare d text;
begin
  d := pg_get_functiondef('public._equipe_escalada(public.treinadores,integer)'::regprocedure);
  if position('_golpes_vantagem' in d) = 0 then
    d := public._pt(d, 'return res;', 'if t.lider or t.id like ''gin\_%'' or t.id like ''liga\_%'' then res := public._golpes_vantagem(res, auth.uid()); end if;
  return res;');
    execute d;
  end if;
end $$;
drop function public._pt(text, text, text);
