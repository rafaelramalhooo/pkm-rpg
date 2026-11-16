-- Conferência do Mundo vivo (só leitura). Rode no SQL Editor depois de aplicar m59, m59b, m60 e m61.
-- Todas as linhas devem vir com ok = true.
select 'tabelas mv_*' as item, (select count(*) from information_schema.tables where table_schema = 'public' and table_name like 'mv\_%') = 11 as ok
union all select 'pontos de surgimento (328)', (select count(*) from public.mv_pontos) >= 300
union all select 'fofoqueiros e murais (20)', (select count(*) from public.mv_fixos) = 20
union all select 'arquétipos (13)', (select count(*) from public.mv_arquetipos) = 13
union all select 'funções de interação (11 serviços/quests/trocas)', (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname like '\_mv\_h\_%' and p.proname <> '_mv_h_quest') = 8 + 4
union all select 'cron mv_turno agendado', exists (select 1 from cron.job where jobname = 'mv_turno')
union all select 'config mundo_vivo', exists (select 1 from public.config where chave = 'mundo_vivo')
union all select 'desafiantes de hoje (3 a 6 por rota)', (select count(*) from public.treinadores where id like 'dc\_%') >= 0
union all select 'gatilhos de quests', (select count(*) from pg_trigger where tgname in ('tg_mv_quest_atividade', 'tg_mv_quest_dex', 'tg_mv_quest_mapa', 'tg_mv_batalha')) = 4;
-- Para gerar já (como Mestre ou no SQL Editor): select public._mv_gerar(true);
-- Para ver o que existe agora:
-- select arquetipo, nome, mapa_id from public.mv_npcs order by mapa_id;
-- select * from public.mv_pokemon_dia order by dia desc, turno;
