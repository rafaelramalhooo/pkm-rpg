-- m53: reset geral (todos os jogadores, exceto o Mestre), protegido por código aleatório gerado no servidor
create or replace function public.mestre_reset_codigo() returns text
language plpgsql security definer set search_path = public as $$
declare c text;
begin
  if not public.eh_mestre() then raise exception 'Só o Mestre.'; end if;
  c := upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6));
  insert into public.config (chave, valor) values ('reset_codigo', jsonb_build_object('codigo', c, 'ate', now() + interval '3 minutes', 'por', auth.uid()))
  on conflict (chave) do update set valor = excluded.valor;
  return c;
end $$;
revoke all on function public.mestre_reset_codigo() from public, anon;
grant execute on function public.mestre_reset_codigo() to authenticated;

create or replace function public.mestre_resetar_todos(p_codigo text) returns int
language plpgsql security definer set search_path = public as $$
declare cfg jsonb; r record; n int := 0;
begin
  if not public.eh_mestre() then raise exception 'Só o Mestre.'; end if;
  select valor into cfg from public.config where chave = 'reset_codigo';
  if cfg is null or (cfg->>'por')::uuid is distinct from auth.uid() or (cfg->>'ate')::timestamptz < now() or upper(btrim(coalesce(p_codigo, ''))) <> cfg->>'codigo' then
    raise exception 'Código incorreto ou expirado. Peça um novo código.';
  end if;
  delete from public.config where chave = 'reset_codigo';
  -- manutenção ligada e todos desconectados, para ninguém jogar no meio
  insert into public.config (chave, valor) values ('manutencao', jsonb_build_object('ativo', true, 'mensagem', 'O mundo de Rafar foi reiniciado. Voltamos já!'))
  on conflict (chave) do update set valor = excluded.valor;
  insert into public.config (chave, valor) values ('derrubar_em', to_jsonb(now())) on conflict (chave) do update set valor = excluded.valor;
  for r in select j.id from public.jogadores j
            where j.papel <> 'mestre' and not exists (select 1 from public.jogadores m where m.papel = 'mestre' and m.id = coalesce(j.conta, j.id)) loop
    perform public._reiniciar(r.id);
    delete from public.missao_jogador where jogador = r.id;
    delete from public.pedra_progresso where jogador = r.id;
    delete from public.mt_jogador where jogador = r.id;
    n := n + 1;
  end loop;
  insert into public.auditoria (ator, acao, detalhe) values (auth.uid(), 'resetar_todos', jsonb_build_object('jogadores', n));
  return n;
end $$;
revoke all on function public.mestre_resetar_todos(text) from public, anon;
grant execute on function public.mestre_resetar_todos(text) to authenticated;
