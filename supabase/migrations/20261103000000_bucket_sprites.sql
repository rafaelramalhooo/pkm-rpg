-- Bucket PRIVADO para os sprites (arte protegida: nunca público, nunca no repositório).
insert into storage.buckets (id, name, public)
values ('sprites', 'sprites', false)
on conflict (id) do nothing;

-- Somente usuários logados leem os sprites.
-- O envio de arquivos é feito pelo Mestre (painel do Supabase / chave de serviço).
drop policy if exists "sprites_leitura_autenticados" on storage.objects;
create policy "sprites_leitura_autenticados"
  on storage.objects for select to authenticated
  using (bucket_id = 'sprites');
