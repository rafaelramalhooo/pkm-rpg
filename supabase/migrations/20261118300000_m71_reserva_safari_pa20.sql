-- m71: Reserva Dourada (Zona do Safári) + PA 20/dia + Treinar custa 2 PA
-- Aplicada no TEST e no PROD em 16/11/2026.
update public.config set valor = to_jsonb(20) where chave = 'pa_por_dia';
insert into public.config (chave, valor) select 'reserva_preco', to_jsonb(500) where not exists (select 1 from public.config where chave = 'reserva_preco');
insert into public.config (chave, valor) select 'reserva_passos', to_jsonb(250) where not exists (select 1 from public.config where chave = 'reserva_passos');
insert into public.config (chave, valor) select 'reserva_bolas', to_jsonb(30) where not exists (select 1 from public.config where chave = 'reserva_bolas');
create table if not exists public.reserva_visitas (
  id bigint generated always as identity primary key,
  jogador uuid not null references public.jogadores(id) on delete cascade,
  dia date not null,
  ativa boolean not null default true,
  passos int not null,
  bolas int not null,
  capturas jsonb not null default '[]'::jsonb,
  enc jsonb,
  entregues jsonb,
  visto boolean not null default true,
  criado_em timestamptz not null default now(),
  unique (jogador, dia)
);
alter table public.reserva_visitas enable row level security;
revoke all on public.reserva_visitas from anon, authenticated;
create or replace function public._reserva_fim(p_j uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v public.reserva_visitas; c jsonb; ent jsonb := '[]'::jsonb; perd int := 0; p public.pokemons;
begin
  select * into v from public.reserva_visitas where jogador = p_j and ativa for update;
  if not found then return null; end if;
  for c in select * from jsonb_array_elements(v.capturas) loop
    begin
      p := public._novo_pokemon(p_j, (c->>'especie_id')::int, (c->>'nivel')::int);
      ent := ent || jsonb_build_array(c);
    exception when others then
      perd := perd + 1;
    end;
  end loop;
  update public.reserva_visitas set ativa = false, enc = null, entregues = ent, visto = false where id = v.id;
  return jsonb_build_object('entregues', ent, 'perdidos', perd);
end $$;
create or replace function public._reserva_passo(p_j uuid) returns void
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  update public.reserva_visitas set passos = greatest(passos - 1, 0) where jogador = p_j and ativa returning passos into n;
  if found and n = 0 then perform public._reserva_fim(p_j); end if;
end $$;
create or replace function public._reserva_estado(p_j uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v public.reserva_visitas; r jsonb;
begin
  select * into v from public.reserva_visitas where jogador = p_j order by dia desc limit 1;
  if not found then
    return jsonb_build_object('ativa', false, 'visitou_hoje', false, 'preco', public._cfg_int('reserva_preco', 500),
      'passos_max', public._cfg_int('reserva_passos', 250), 'bolas_max', public._cfg_int('reserva_bolas', 30));
  end if;
  r := jsonb_build_object(
    'ativa', v.ativa, 'passos', v.passos, 'bolas', v.bolas,
    'visitou_hoje', v.dia = public._dia_jogo(),
    'preco', public._cfg_int('reserva_preco', 500),
    'passos_max', public._cfg_int('reserva_passos', 250), 'bolas_max', public._cfg_int('reserva_bolas', 30),
    'capturas', coalesce((select jsonb_agg(jsonb_build_object('especie_id', (x->>'especie_id')::int, 'nivel', (x->>'nivel')::int,
        'nome', (select nome from public.especies where id = (x->>'especie_id')::int))) from jsonb_array_elements(v.capturas) x), '[]'::jsonb),
    'enc', case when v.enc is null then null else jsonb_build_object(
        'especie_id', (v.enc->>'especie_id')::int, 'nivel', (v.enc->>'nivel')::int,
        'nome', (select nome from public.especies where id = (v.enc->>'especie_id')::int),
        'iscas', (v.enc->>'iscas')::int, 'pedras', (v.enc->>'pedras')::int) end,
    'fim', case when not v.ativa and not v.visto then coalesce((select jsonb_agg(jsonb_build_object('especie_id', (x->>'especie_id')::int, 'nivel', (x->>'nivel')::int,
        'nome', (select nome from public.especies where id = (x->>'especie_id')::int))) from jsonb_array_elements(v.entregues) x), '[]'::jsonb) else null end);
  if not v.ativa and not v.visto then update public.reserva_visitas set visto = true where id = v.id; end if;
  return r;
end $$;
revoke all on function public._reserva_fim(uuid), public._reserva_passo(uuid), public._reserva_estado(uuid) from public, anon, authenticated;
create or replace function public.reserva_estado() returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Faça login primeiro.'; end if;
  return public._reserva_estado(auth.uid());
end $$;
create or replace function public.reserva_entrar() returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_j public.jogadores; v_preco int := public._cfg_int('reserva_preco', 500); v_hoje date := public._dia_jogo();
begin
  if auth.uid() is null then raise exception 'Faça login primeiro.'; end if;
  select * into v_j from public.jogadores where id = auth.uid() for update;
  if not found then raise exception 'Crie seu personagem primeiro.'; end if;
  if v_j.mapa_id <> 'reserva' then raise exception 'Vá até a Reserva Dourada primeiro.'; end if;
  if exists (select 1 from public.batalhas where jogador = v_j.id and estado = 'ativa') then raise exception 'Termine a batalha primeiro.'; end if;
  if exists (select 1 from public.reserva_visitas where jogador = v_j.id and ativa) then raise exception 'Você já está em uma visita.'; end if;
  if exists (select 1 from public.reserva_visitas where jogador = v_j.id and dia = v_hoje) then
    raise exception 'Você já visitou a Reserva hoje. Volte amanhã (o dia vira às 6h).';
  end if;
  if coalesce(v_j.dinheiro, 0) < v_preco then raise exception 'A entrada custa ₽ %.', v_preco; end if;
  if (select o_caixa from public._vaga_caixa(v_j.id)) is null then
    raise exception 'Suas caixas estão cheias: libere espaço antes de entrar.';
  end if;
  update public.jogadores set dinheiro = dinheiro - v_preco where id = v_j.id;
  insert into public.reserva_visitas (jogador, dia, passos, bolas)
  values (v_j.id, v_hoje, public._cfg_int('reserva_passos', 250), public._cfg_int('reserva_bolas', 30));
  return public._reserva_estado(v_j.id);
end $$;
create or replace function public.reserva_encontro() returns jsonb
language plpgsql security definer set search_path = public as $$
declare v public.reserva_visitas; o public.ofertas; v_j public.jogadores;
begin
  if auth.uid() is null then raise exception 'Faça login primeiro.'; end if;
  select * into v_j from public.jogadores where id = auth.uid() for update;
  select * into v from public.reserva_visitas where jogador = auth.uid() and ativa for update;
  if not found then raise exception 'Você não está em uma visita à Reserva.'; end if;
  select * into o from public.ofertas where jogador = auth.uid();
  if not found or o.mapa_id <> 'reserva' or o.bioma = 'agua' or o.x <> v_j.x or o.y <> v_j.y then
    raise exception 'Não há Pokémon à vista aqui.';
  end if;
  delete from public.ofertas where jogador = auth.uid();
  update public.reserva_visitas set enc = jsonb_build_object('especie_id', o.especie_id, 'nivel', o.nivel, 'iscas', 0, 'pedras', 0) where id = v.id;
  return public._reserva_estado(auth.uid());
end $$;
create or replace function public.reserva_acao(p_acao text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v public.reserva_visitas; e public.especies; en jsonb; nome text;
  isc int; ped int; net int; base numeric; pc numeric; pf numeric; msg text; capturou boolean := false; fugiu boolean := false; fim jsonb; est jsonb;
begin
  if auth.uid() is null then raise exception 'Faça login primeiro.'; end if;
  if p_acao not in ('bola', 'isca', 'pedra', 'fugir') then raise exception 'Ação inválida.'; end if;
  select * into v from public.reserva_visitas where jogador = auth.uid() and ativa for update;
  if not found then raise exception 'Você não está em uma visita à Reserva.'; end if;
  en := v.enc;
  if en is null then raise exception 'Não há Pokémon à vista.'; end if;
  select * into e from public.especies where id = (en->>'especie_id')::int;
  nome := e.nome;
  isc := (en->>'iscas')::int; ped := (en->>'pedras')::int;
  if p_acao = 'fugir' then
    update public.reserva_visitas set enc = null where id = v.id;
    msg := 'Você se afastou com cuidado.';
    return jsonb_build_object('msg', msg, 'capturou', false, 'fugiu', true, 'estado', public._reserva_estado(auth.uid()));
  end if;
  if p_acao = 'bola' then
    if v.bolas < 1 then raise exception 'Você não tem mais Bolas Safári.'; end if;
    v.bolas := v.bolas - 1;
  elsif p_acao = 'isca' then isc := isc + 1; msg := nome || ' come a isca e fica mais calmo.';
  else ped := ped + 1; msg := nome || ' leva uma pedrada e fica irritado!';
  end if;
  net := greatest(-3, least(3, ped - isc));
  base := least(0.95, (coalesce(e.taxa_captura, 45)::numeric / 255.0) * 1.5);
  pc := least(0.9, greatest(0.03, base * power(2, net)));
  pf := least(0.85, greatest(0.05, (0.10 + coalesce(e.spe, 50)::numeric / 400.0) * power(2, net)));
  if p_acao = 'bola' then
    if random() < pc then
      capturou := true;
      msg := 'Gotcha! ' || nome || ' foi capturado! Ele será entregue ao fim da visita.';
      v.capturas := v.capturas || jsonb_build_array(jsonb_build_object('especie_id', e.id, 'nivel', (en->>'nivel')::int));
      en := null;
    else
      msg := 'A Bola Safári falhou: ' || nome || ' escapou da bola!';
    end if;
  end if;
  if en is not null and random() < pf then
    fugiu := true; en := null;
    msg := coalesce(msg || ' ', '') || nome || ' fugiu!';
  end if;
  if en is not null then en := jsonb_build_object('especie_id', e.id, 'nivel', (en->>'nivel')::int, 'iscas', isc, 'pedras', ped); end if;
  update public.reserva_visitas set bolas = v.bolas, capturas = v.capturas, enc = en where id = v.id;
  if v.bolas = 0 then
    fim := public._reserva_fim(auth.uid());
    msg := coalesce(msg, '') || ' Suas Bolas Safári acabaram: a visita terminou.';
  end if;
  est := public._reserva_estado(auth.uid());
  return jsonb_build_object('msg', msg, 'capturou', capturou, 'fugiu', fugiu, 'fim', fim, 'estado', est,
    'chance_captura', round(pc * 100), 'chance_fuga', round(pf * 100));
end $$;
grant execute on function public.reserva_estado(), public.reserva_entrar(), public.reserva_encontro(), public.reserva_acao(text) to authenticated;
revoke execute on function public.reserva_estado(), public.reserva_entrar(), public.reserva_encontro(), public.reserva_acao(text) from anon;
-- Patches nas funções existentes (helper temporário, removido no fim)
create or replace function public._pt2(d text, a text, b text, p_todos boolean default false) returns text
language plpgsql as $$
declare rx text; r text;
begin
  rx := regexp_replace(a, '([\\.\[\](){}*+?^$|])', '\\\1', 'g');
  rx := regexp_replace(rx, '\s+', '\\s+', 'g');
  r := regexp_replace(d, rx, b, case when p_todos then 'g' else '' end);
  if r = d then raise exception 'm71: trecho não encontrado: %', left(a, 80); end if;
  return r;
end $$;
do $m71$
declare d text;
begin
  d := pg_get_functiondef('public.andar(text)'::regprocedure);
  d := public._pt2(d, 'update public.jogadores set x = v_nx, y = v_ny, direcao = p_dir, posicao_em = clock_timestamp() where id = v_j.id returning * into v_j; return v_j;',
    'if v_j.mapa_id = ''reserva'' then perform public._reserva_passo(v_j.id); end if; update public.jogadores set x = v_nx, y = v_ny, direcao = p_dir, posicao_em = clock_timestamp() where id = v_j.id returning * into v_j; return v_j;');
  d := public._pt2(d, 'update public.jogadores set mapa_id = v_p->>''dest''',
    'if v_j.mapa_id = ''reserva'' then perform public._reserva_fim(v_j.id); end if; update public.jogadores set mapa_id = v_p->>''dest''');
  execute d;
  d := pg_get_functiondef('public.viajar(text)'::regprocedure);
  d := public._pt2(d, 'if v_j.mapa_id = p_mapa then raise exception ''Você já está aqui.''; end if;',
    'if v_j.mapa_id = p_mapa then raise exception ''Você já está aqui.''; end if; if v_j.mapa_id = ''reserva'' then perform public._reserva_fim(v_j.id); end if;');
  execute d;
  d := pg_get_functiondef('public.gerar_oferta()'::regprocedure);
  d := public._pt2(d, 'if v_m.bioma is null then return null; end if;',
    'if v_j.mapa_id = ''reserva'' and not exists (select 1 from public.reserva_visitas rv where rv.jogador = v_j.id and rv.ativa and rv.passos > 0) then return null; end if; if v_m.bioma is null then return null; end if;');
  execute d;
  d := pg_get_functiondef('public.procurar_pokemon()'::regprocedure);
  d := public._pt2(d, 'if auth.uid() is null then raise exception ''Faça login primeiro.''; end if;',
    'if auth.uid() is null then raise exception ''Faça login primeiro.''; end if; if exists (select 1 from public.ofertas oo where oo.jogador = auth.uid() and oo.mapa_id = ''reserva'' and oo.bioma <> ''agua'') then raise exception ''Na Reserva Dourada a captura é pelo Safári (Observar).''; end if;');
  execute d;
  d := pg_get_functiondef('public.acao_treinar(uuid)'::regprocedure);
  d := public._pt2(d, 'perform public._gastar_pa(auth.uid()); perform public._criador_mestre(auth.uid());',
    'if public._ev(''pa_gratis'', 0) = 0 and coalesce((select pa from public.jogadores where id = auth.uid()), 0) < 2 then raise exception ''PA insuficiente: Treinar custa 2 PA.''; end if; perform public._gastar_pa(auth.uid()); perform public._gastar_pa(auth.uid()); perform public._criador_mestre(auth.uid());');
  execute d;
end $m71$;
drop function public._pt2(text, text, text, boolean);
