-- m42: mais rivais NPC no ranking + criar/remover rivais pelo Mestre + vagas livres.
insert into public.ranking_rivais (id, nome, fator) values
  ('rv_gary', 'Gary', 0.95), ('rv_lance', 'Lance', 0.90), ('rv_cynthia', 'Cynthia', 0.80), ('rv_steven', 'Steven', 0.75),
  ('rv_lorelei', 'Lorelei', 0.65), ('rv_bruno', 'Bruno', 0.60), ('rv_agatha', 'Agatha', 0.50), ('rv_sabrina', 'Sabrina', 0.40),
  ('rv_surge', 'Surge', 0.35), ('rv_giovanni', 'Giovanni', 0.25), ('rv_brendan', 'Brendan', 0.15)
on conflict (id) do nothing;

-- vagas livres (desligadas): o Mestre só preenche o nome e liga
insert into public.ranking_rivais (id, nome, fator, ativo) values
  ('rv_vaga1', 'Vaga livre 1', 0.50, false), ('rv_vaga2', 'Vaga livre 2', 0.50, false),
  ('rv_vaga3', 'Vaga livre 3', 0.50, false), ('rv_vaga4', 'Vaga livre 4', 0.50, false)
on conflict (id) do nothing;

create or replace function public.mestre_rival_criar(p_nome text, p_fator numeric) returns void language plpgsql security definer set search_path = public as $$
declare n text := btrim(coalesce(p_nome, ''));
begin
  if not public.eh_mestre() then raise exception 'Só o Mestre.'; end if;
  if char_length(n) not between 1 and 30 then raise exception 'O nome do rival deve ter de 1 a 30 letras.'; end if;
  if coalesce(p_fator, -1) not between 0 and 2 then raise exception 'O fator vai de 0 a 2.'; end if;
  if (select count(*) from public.ranking_rivais) >= 60 then raise exception 'Limite de 60 rivais.'; end if;
  insert into public.ranking_rivais (id, nome, fator) values ('rv_' || substr(md5(random()::text || clock_timestamp()::text), 1, 10), n, p_fator);
end $$;

create or replace function public.mestre_rival_remover(p_id text) returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.eh_mestre() then raise exception 'Só o Mestre.'; end if;
  delete from public.ranking_rivais where id = p_id;
end $$;

revoke all on function public.mestre_rival_criar(text, numeric), public.mestre_rival_remover(text) from public, anon;
grant execute on function public.mestre_rival_criar(text, numeric), public.mestre_rival_remover(text) to authenticated;
