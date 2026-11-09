-- Função leve para o fluxo "Manter ativo": faz uma consulta de verdade ao banco (um simples
-- /auth/v1/health não pareceu contar como atividade e o plano gratuito pausou os projetos).
-- Devolve só uma contagem; não expõe dados.
create or replace function public.ping()
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select count(*)::int from public.mapas;
$$;

revoke all on function public.ping() from public;
grant execute on function public.ping() to anon, authenticated;
