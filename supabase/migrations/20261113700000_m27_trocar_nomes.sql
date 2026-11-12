-- M27: corrige a troca de personagem (criar 2º personagem / jogar com o reserva).
-- Erro: duplicate key "jogadores_nome_unico" -> o nome temporário era copiado para duas linhas ao mesmo tempo.
-- Agora cada linha recebe um nome temporário próprio durante a troca.
create or replace function public._trocar(p_a uuid, p_b uuid) returns void language plpgsql security definer set search_path = public as $$
declare v_p uuid := gen_random_uuid(); v_na text; v_nb text; v_cols text := public._cols_personagem();
begin
  select nome into v_na from public.jogadores where id = p_a;
  select nome into v_nb from public.jogadores where id = p_b;
  delete from public.ofertas where jogador in (p_a, p_b);
  update public.jogadores set rolagem = null where id in (p_a, p_b);
  -- 1) cópia temporária do ativo (a) em v_p, com nome temporário próprio
  execute format('insert into public.jogadores (id, conta, %s) select $1, $2, %s from public.jogadores where id = $3',
                 v_cols, public._cols_personagem(quote_literal(public._nome_tmp(v_p)))) using v_p, p_b, p_a;
  perform public._filhos_mover(p_a, v_p);
  -- 2) libera o nome de b e copia o conteúdo de b para a (nome temporário de a), depois dá a a o nome de b
  update public.jogadores set nome = public._nome_tmp(p_b) where id = p_b;
  execute format('update public.jogadores t set (%s) = (select %s from public.jogadores s where s.id = $1) where t.id = $2',
                 v_cols, public._cols_personagem(quote_literal(public._nome_tmp(p_a)))) using p_b, p_a;
  update public.jogadores set nome = v_nb where id = p_a;
  perform public._filhos_mover(p_b, p_a);
  -- 3) copia o conteúdo original de a (guardado em v_p) para b, move os filhos e devolve o nome antigo de a
  execute format('update public.jogadores t set (%s) = (select %s from public.jogadores s where s.id = $1) where t.id = $2',
                 v_cols, public._cols_personagem(quote_literal(public._nome_tmp(p_b)))) using v_p, p_b;
  perform public._filhos_mover(v_p, p_b);
  delete from public.jogadores where id = v_p;
  update public.jogadores set nome = v_na where id = p_b;
end $$;
revoke all on function public._trocar(uuid, uuid) from public, anon, authenticated;
