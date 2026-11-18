-- m79: trava da Liga NPC (config liga_npc_ativa), auditoria de aumentos de PA,
-- correção do jogador que venceu a Liga NPC antes da hora (campeao=false, prêmio em dinheiro removido).

insert into public.config (chave, valor) values ('liga_npc_ativa', 'false'::jsonb)
on conflict (chave) do nothing;

-- 1) desafiar_treinador: bloqueia liga_% enquanto a chave estiver desligada (o Mestre passa)
do $$
declare d text; novo text;
begin
  d := pg_get_functiondef('public.desafiar_treinador(text)'::regprocedure);
  if d like '%liga_npc_ativa%' then return; end if;
  novo := replace(d,
    'raise exception ''Não há esse treinador por aqui.''; end if;',
    'raise exception ''Não há esse treinador por aqui.''; end if; if v_t.id like ''liga\_%'' and v_j.papel <> ''mestre'' and not coalesce((select (valor #>> ''{}'')::boolean from public.config where chave = ''liga_npc_ativa''), false) then raise exception ''A Liga Pokémon ainda não está aberta.''; end if;');
  if novo = d then raise exception 'ancora nao encontrada em desafiar_treinador'; end if;
  execute novo;
end $$;

-- 2) auditoria de todo aumento de PA (para rastrear origem se acontecer de novo)
create or replace function public._tg_pa_auditoria() returns trigger
language plpgsql security definer set search_path to 'public' as $$
begin
  if new.pa > old.pa then
    insert into public.auditoria (ator, acao, detalhe)
    values (new.id, 'pa_aumento', jsonb_build_object(
      'de', old.pa, 'para', new.pa,
      'hora_sp', to_char(now() at time zone 'America/Sao_Paulo', 'YYYY-MM-DD HH24:MI:SS'),
      'dia_jogo', public._dia_jogo(), 'pa_dia_antes', old.pa_dia, 'pa_dia_depois', new.pa_dia,
      'consulta', left(coalesce(current_query(), ''), 120)));
  end if;
  return new;
end $$;

drop trigger if exists tg_pa_auditoria on public.jogadores;
create trigger tg_pa_auditoria after update of pa on public.jogadores
for each row execute function public._tg_pa_auditoria();

-- 3) correção do jogador que zerou a Liga NPC antes de ela estar configurada
update public.jogadores set campeao = false, dinheiro = greatest(dinheiro - 6000, 0)
where nome = 'Chinash' and campeao = true;
insert into public.auditoria (ator, acao, detalhe)
select id, 'm79_corrige_liga', jsonb_build_object('campeao', false, 'dinheiro_removido_base', 6000)
from public.jogadores where nome = 'Chinash';
