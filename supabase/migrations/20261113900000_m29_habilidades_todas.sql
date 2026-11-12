-- m29: libera todas as habilidades de todas as classes para teste (as que ainda não têm efeito no jogo só gastam pontos)
update public.habilidades_catalogo set ativo = true where not ativo;
