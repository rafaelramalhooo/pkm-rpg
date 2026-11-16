-- m57: aparências de jogador passam a vir de uma lista no servidor (config.aparencias_jogador, editável pelo Mestre).
-- Sprites p0–p11: jogadores originais; p12–p23: papéis de NPC (rival, cientistas, enfermeira, líderes); p24–p48: moradores e treinadores.
alter table public.jogadores drop constraint if exists jogadores_aparencia_check;
alter table public.jogadores add constraint jogadores_aparencia_check check (aparencia between 0 and 48);

insert into public.config (chave, valor) values ('aparencias_jogador', '[0,1,2,3,4,5,6,7,8,9,10,11,24,25,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48]'::jsonb)
on conflict (chave) do nothing;

create or replace function public._aparencia_ok(p smallint) returns boolean
language sql stable security definer set search_path = public as $$
  select p is not null and exists (
    select 1 from jsonb_array_elements_text(coalesce((select valor from public.config where chave = 'aparencias_jogador'), '[0,1,2,3,4,5,6,7,8,9,10,11]'::jsonb)) e
    where e::int = p);
$$;
revoke all on function public._aparencia_ok(smallint) from public, anon;
grant execute on function public._aparencia_ok(smallint) to authenticated;

-- Troca só a linha de validação das duas funções de criação, mantendo o resto do corpo intacto.
do $$
declare d text; f text;
begin
  foreach f in array array['public.criar_personagem(text,smallint)', 'public.criar_novo_personagem(text,smallint)'] loop
    d := pg_get_functiondef(f::regprocedure);
    if position('p_aparencia is null or p_aparencia not between 0 and 11' in d) > 0 then
      d := replace(d, 'p_aparencia is null or p_aparencia not between 0 and 11', 'not public._aparencia_ok(p_aparencia)');
      execute d;
    end if;
  end loop;
end $$;
