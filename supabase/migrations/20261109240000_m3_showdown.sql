-- M3: batalhas movidas pelo simulador oficial do Pokémon Showdown (roda na Edge Function "batalha").
-- O banco guarda o estado da simulação e aplica os resultados (PV, PP, experiência, captura, itens).

alter table public.batalhas add column if not exists sim jsonb;          -- estado serializado do simulador
alter table public.batalhas add column if not exists meta jsonb not null default '{}'::jsonb; -- ids do time, participantes, tentativas de fuga
alter table public.batalhas add column if not exists log_len int not null default 0;
alter table public.batalhas add column if not exists tipo text not null default 'selvagem' check (tipo in ('selvagem','treinador'));
alter table public.batalhas add column if not exists adversarios jsonb;  -- equipe adversária (treinadores); selvagem usa a coluna "selvagem"

-- ===== gasta 1 unidade de um item (erro se não tiver) =====
create or replace function public.sim_gastar_item(p_jogador uuid, p_item text) returns void
language plpgsql security definer set search_path = public as $$
declare v_qtd int;
begin
  select qtd into v_qtd from public.inventario where jogador = p_jogador and item = p_item for update;
  if coalesce(v_qtd, 0) <= 0 then raise exception 'Você não tem esse item.'; end if;
  update public.inventario set qtd = qtd - 1 where jogador = p_jogador and item = p_item;
end $$;

-- ===== grava o resultado de um turno =====
-- p_time: [{id, hp, pp:[...]}]; p_exp: [{exp_base, nivel}] (adversários derrotados) ; p_fim: null|vitoria|derrota|fuga
create or replace function public.sim_gravar(
  p_batalha uuid, p_turno int, p_sim jsonb, p_meta jsonb, p_log_len int, p_time jsonb, p_fim text, p_exp jsonb default '[]'::jsonb
) returns jsonb language plpgsql security definer set search_path = public as $$
declare
  b public.batalhas; m jsonb; ev jsonb := '[]'::jsonb; pk public.pokemons; pk2 public.pokemons; novo jsonb; i int; k int; sel jsonb; part uuid[]; n int; x jsonb;
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
    if p_fim = 'vitoria' and jsonb_array_length(p_exp) > 0 then
      select array_agg(distinct (e)::uuid) into part from jsonb_array_elements_text(p_meta->'participantes') e;
      n := coalesce(array_length(part, 1), 1);
      for pk in select * from public.pokemons where id = any(coalesce(part, '{}')) and dono = b.jogador and hp_atual > 0 loop
        for x in select * from jsonb_array_elements(p_exp) loop
          sel := jsonb_build_object('exp_base', greatest(1, floor((x->>'exp_base')::numeric / n)), 'nivel', (x->>'nivel')::int);
          select * into pk2 from public.pokemons where id = pk.id;
          ev := public._dar_exp(pk2, sel, ev);
        end loop;
      end loop;
    end if;
  end if;
  return ev;
end $$;

-- ===== captura bem-sucedida =====
create or replace function public.sim_capturar(p_batalha uuid, p_turno int, p_sim jsonb, p_meta jsonb, p_log_len int, p_time jsonb, p_especie int, p_nivel int, p_golpes jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare b public.batalhas; novo public.pokemons; esp public.especies;
begin
  perform public.sim_gravar(p_batalha, p_turno, p_sim, p_meta, p_log_len, p_time, null);
  select * into b from public.batalhas where id = p_batalha;
  select * into esp from public.especies where id = p_especie;
  novo := public._novo_pokemon(b.jogador, p_especie, p_nivel, p_golpes);
  update public.batalhas set estado = 'captura' where id = b.id;
  return jsonb_build_object('nome', esp.nome, 'time', novo.posicao is not null);
end $$;

revoke all on function public.sim_gastar_item(uuid, text), public.sim_gravar(uuid,int,jsonb,jsonb,int,jsonb,text,jsonb),
  public.sim_capturar(uuid,int,jsonb,jsonb,int,jsonb,int,int,jsonb) from public, anon, authenticated;
grant execute on function public.sim_gastar_item(uuid, text), public.sim_gravar(uuid,int,jsonb,jsonb,int,jsonb,text,jsonb),
  public.sim_capturar(uuid,int,jsonb,jsonb,int,jsonb,int,int,jsonb) to service_role;

-- As ações antigas de batalha (motor próprio) deixam de ser chamáveis pelo navegador.
revoke execute on function public.batalha_atacar(uuid,int), public.batalha_trocar(uuid,uuid), public.batalha_fugir(uuid), public.batalha_capturar(uuid,text) from authenticated;
