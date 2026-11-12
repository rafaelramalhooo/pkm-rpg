-- M26: (1) 2º personagem: a linha guardada tem id próprio e não pode apontar para auth.users -> remove essa chave estrangeira
--      (2) Mestre editar jogador: corrige "aggregate functions are not allowed in UPDATE" (alias `x` colidia com a coluna x)
--      (3) Jogador apaga todos os seus personagens e cria do zero (o papel de Mestre é preservado)

-- (1) remove a FK jogadores.id -> auth.users e passa a limpar os personagens ao apagar a conta
do $$
declare r record;
begin
  for r in select conname from pg_constraint where conrelid = 'public.jogadores'::regclass and contype = 'f' and confrelid = 'auth.users'::regclass loop
    execute format('alter table public.jogadores drop constraint %I', r.conname);
  end loop;
end $$;

create or replace function public._limpar_jogador_da_conta() returns trigger language plpgsql security definer set search_path = public as $$
begin
  delete from public.jogadores where id = old.id or conta = old.id;
  return old;
end $$;

do $$
begin
  drop trigger if exists limpar_jogador_da_conta on auth.users;
  create trigger limpar_jogador_da_conta after delete on auth.users for each row execute function public._limpar_jogador_da_conta();
exception when others then
  raise notice 'Não foi possível criar o gatilho em auth.users (%). Apagar a conta pelo painel deixará o personagem órfão; o Mestre pode removê-lo.', sqlerrm;
end $$;

-- (2) edição do Mestre
create or replace function public.mestre_editar_jogador(p_id uuid, p_campos jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare v_mapa text;
begin
  if not public.eh_mestre() then raise exception 'Só o Mestre.'; end if;
  if not exists (select 1 from public.jogadores where id = p_id) then raise exception 'Jogador não encontrado.'; end if;
  if p_campos ? 'nome' and length(btrim(p_campos->>'nome')) between 2 and 24 then update public.jogadores set nome = btrim(p_campos->>'nome') where id = p_id; end if;
  if p_campos ? 'pa' then update public.jogadores set pa = greatest(0, least(32000, (p_campos->>'pa')::int)) where id = p_id; end if;
  if p_campos ? 'dinheiro' then update public.jogadores set dinheiro = greatest(0, least(99999999, (p_campos->>'dinheiro')::int)) where id = p_id; end if;
  if p_campos ? 'papel' and p_campos->>'papel' in ('jogador', 'mestre') then update public.jogadores set papel = p_campos->>'papel' where id = p_id; end if;
  if p_campos ? 'campeao' then update public.jogadores set campeao = (p_campos->>'campeao')::boolean where id = p_id; end if;
  if p_campos ? 'insignias' then
    update public.jogadores set insignias = coalesce((select array_agg(distinct ins.v) from jsonb_array_elements_text(p_campos->'insignias') as ins(v)), '{}') where id = p_id;
  end if;
  if p_campos ? 'mapa_id' then
    v_mapa := p_campos->>'mapa_id';
    if not exists (select 1 from public.mapas where id = v_mapa) then raise exception 'Mapa inexistente.'; end if;
    update public.jogadores set mapa_id = v_mapa, x = coalesce((p_campos->>'x')::int, x), y = coalesce((p_campos->>'y')::int, y) where id = p_id;
    delete from public.ofertas where jogador = p_id;
  end if;
  insert into public.auditoria (ator, acao, detalhe) values (auth.uid(), 'mestre_editar_jogador', jsonb_build_object('jogador', p_id, 'campos', p_campos));
end $$;
grant execute on function public.mestre_editar_jogador(uuid, jsonb) to authenticated;

-- (3) papel guardado + criar_personagem que o restaura + apagar tudo
create table if not exists public.papel_guardado (conta uuid primary key, papel text not null);
alter table public.papel_guardado enable row level security;
revoke all on public.papel_guardado from anon, authenticated;

create or replace function public.criar_personagem(p_nome text, p_aparencia smallint)
returns public.jogadores language plpgsql security definer set search_path = public as $$
declare v_nome text; v_jogador public.jogadores; s record; v_papel text;
begin
  if auth.uid() is null then raise exception 'Faça login primeiro.'; end if;
  if exists (select 1 from public.jogadores where id = auth.uid()) then raise exception 'Você já tem um personagem.'; end if;
  v_nome := public._novo_nome_ok(p_nome);
  if p_aparencia is null or p_aparencia not between 0 and 11 then raise exception 'Aparência inválida.'; end if;
  select * into s from public._spawn_inicial();
  insert into public.jogadores (id, nome, aparencia, mapa_id, x, y, pa)
  values (auth.uid(), v_nome, p_aparencia, s.p_mapa, s.p_x, s.p_y, coalesce((select (valor #>> '{}')::smallint from public.config where chave = 'pa_por_dia'), 30))
  returning * into v_jogador;
  select papel into v_papel from public.papel_guardado where conta = auth.uid();
  if v_papel is not null then
    update public.jogadores set papel = v_papel where id = auth.uid() returning * into v_jogador;
    delete from public.papel_guardado where conta = auth.uid();
  end if;
  insert into public.auditoria (ator, acao, detalhe) values (auth.uid(), 'criar_personagem', jsonb_build_object('nome', v_nome));
  return v_jogador;
end $$;

create or replace function public.apagar_todos_meus_personagens() returns void language plpgsql security definer set search_path = public as $$
declare v_papel text;
begin
  if auth.uid() is null then raise exception 'Faça login primeiro.'; end if;
  if exists (select 1 from public.batalhas where jogador = auth.uid() and estado = 'ativa') then raise exception 'Termine a batalha primeiro.'; end if;
  select papel into v_papel from public.jogadores where id = auth.uid();
  if v_papel is not null and v_papel <> 'jogador' then
    insert into public.papel_guardado (conta, papel) values (auth.uid(), v_papel) on conflict (conta) do update set papel = excluded.papel;
  end if;
  delete from public.jogadores where conta = auth.uid();
  delete from public.jogadores where id = auth.uid();
  insert into public.auditoria (ator, acao, detalhe) values (auth.uid(), 'apagar_todos_meus_personagens', '{}'::jsonb);
end $$;
revoke all on function public.apagar_todos_meus_personagens(), public._limpar_jogador_da_conta() from public, anon;
grant execute on function public.apagar_todos_meus_personagens(), public.criar_personagem(text, smallint) to authenticated;
