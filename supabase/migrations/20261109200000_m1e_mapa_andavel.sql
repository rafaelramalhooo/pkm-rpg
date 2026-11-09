-- M1e: mapa andável tile a tile (substitui o hexcrawl como exploração principal; o hexcrawl fica guardado em hexes).
-- Passos são grátis; PA é gasto em ações (procurar Pokémon etc.). O servidor valida cada passo.

alter table public.mapas
  add column if not exists tipo text not null default 'andavel',
  add column if not exists solido text,                 -- largura*altura caracteres: 1 = bloqueado
  add column if not exists grama text,                  -- 1 = grama alta (permite procurar Pokémon)
  add column if not exists portais jsonb not null default '[]'::jsonb,
  add column if not exists pois jsonb not null default '[]'::jsonb;
update public.mapas set tipo = 'hex' where id = 'kanto';

alter table public.jogadores drop constraint if exists jogadores_aparencia_check;
alter table public.jogadores add constraint jogadores_aparencia_check check (aparencia between 0 and 11);
alter table public.jogadores add column if not exists dinheiro int not null default 1000 check (dinheiro >= 0);

-- ponto de partida novo: jogadores antigos voltam para Pallet Town
insert into public.mapas (id, nome, largura, altura, spawn_x, spawn_y, tipo) values ('pallet', 'Pallet Town', 32, 26, 16, 21, 'andavel');
insert into public.mapas (id, nome, largura, altura, spawn_x, spawn_y, tipo) values ('rota1', 'Rota 1', 40, 20, 20, 10, 'andavel');
insert into public.mapas (id, nome, largura, altura, spawn_x, spawn_y, tipo) values ('viridian', 'Viridian City', 40, 40, 20, 20, 'andavel');

update public.config set valor = '30'::jsonb where chave = 'pa_por_dia';
alter table public.jogadores alter column mapa_id set default 'pallet';
update public.jogadores set mapa_id = 'pallet', x = 16, y = 21, direcao = 'baixo', pa = 30, posicao_em = now();

-- Anda um passo (cima/baixo/esquerda/direita): valida limites, bloqueio e velocidade; trata portais.
create or replace function public.andar(p_dir text)
returns public.jogadores
language plpgsql
security definer
set search_path = public
as $$
declare
  v_j public.jogadores;
  v_m public.mapas;
  v_nx int; v_ny int; v_p jsonb;
begin
  if auth.uid() is null then raise exception 'Faça login primeiro.'; end if;
  if p_dir not in ('cima','baixo','esquerda','direita') then raise exception 'Direção inválida.'; end if;
  select * into v_j from public.jogadores where id = auth.uid() for update;
  if not found then raise exception 'Crie seu personagem primeiro.'; end if;
  if exists (select 1 from public.batalhas where jogador = v_j.id and estado = 'ativa') then
    raise exception 'Termine a batalha primeiro.';
  end if;
  select * into v_m from public.mapas where id = v_j.mapa_id;
  if v_m.tipo <> 'andavel' then raise exception 'Este mapa não é andável.'; end if;
  if v_m.solido is null then raise exception 'O Mestre ainda precisa importar os mapas.'; end if;

  v_nx := v_j.x + case p_dir when 'esquerda' then -1 when 'direita' then 1 else 0 end;
  v_ny := v_j.y + case p_dir when 'cima' then -1 when 'baixo' then 1 else 0 end;
  -- velocidade máxima: ~9 passos por segundo (o cliente anda a ~5)
  if v_j.posicao_em > clock_timestamp() - interval '100 milliseconds' then
    raise exception 'Calma, devagar.';
  end if;
  if v_nx < 0 or v_ny < 0 or v_nx >= v_m.largura or v_ny >= v_m.altura then
    raise exception 'Fim do mapa.';
  end if;
  if substr(v_m.solido, v_ny * v_m.largura + v_nx + 1, 1) = '1' then
    update public.jogadores set direcao = p_dir where id = v_j.id returning * into v_j;
    return v_j;
  end if;

  -- portal?
  for v_p in select * from jsonb_array_elements(v_m.portais) loop
    if v_nx >= (v_p->>'x')::int and v_nx < (v_p->>'x')::int + coalesce((v_p->>'w')::int, 1)
       and v_ny >= (v_p->>'y')::int and v_ny < (v_p->>'y')::int + coalesce((v_p->>'h')::int, 1) then
      update public.jogadores
         set mapa_id = v_p->>'dest', x = (v_p->>'dx')::int, y = (v_p->>'dy')::int,
             direcao = coalesce(v_p->>'dir', p_dir), posicao_em = clock_timestamp()
       where id = v_j.id returning * into v_j;
      return v_j;
    end if;
  end loop;

  update public.jogadores set x = v_nx, y = v_ny, direcao = p_dir, posicao_em = clock_timestamp()
   where id = v_j.id returning * into v_j;
  return v_j;
end;
$$;

-- novo personagem nasce em Pallet Town
create or replace function public.criar_personagem(p_nome text, p_aparencia smallint)
returns public.jogadores
language plpgsql
security definer
set search_path = public
as $$
declare
  v_nome text := btrim(coalesce(p_nome, ''));
  v_mapa public.mapas;
  v_jogador public.jogadores;
begin
  if auth.uid() is null then raise exception 'Faça login primeiro.'; end if;
  if exists (select 1 from public.jogadores where id = auth.uid()) then raise exception 'Você já tem um personagem.'; end if;
  if char_length(v_nome) not between 2 and 12 or v_nome !~ '^[A-Za-zÀ-ÿ0-9 ]+$' then
    raise exception 'O nome deve ter de 2 a 12 letras, números ou espaços.';
  end if;
  if p_aparencia is null or p_aparencia not between 0 and 11 then raise exception 'Aparência inválida.'; end if;
  if exists (select 1 from public.jogadores where lower(nome) = lower(v_nome)) then raise exception 'Esse nome já está em uso.'; end if;
  select * into v_mapa from public.mapas where id = 'pallet';
  insert into public.jogadores (id, nome, aparencia, mapa_id, x, y, pa)
  values (auth.uid(), v_nome, p_aparencia, v_mapa.id, v_mapa.spawn_x, v_mapa.spawn_y,
          coalesce((select (valor #>> '{}')::smallint from public.config where chave = 'pa_por_dia'), 30))
  returning * into v_jogador;
  insert into public.auditoria (ator, acao, detalhe) values (auth.uid(), 'criar_personagem', jsonb_build_object('nome', v_nome));
  return v_jogador;
end;
$$;

drop function if exists public.mover(int, int);
revoke all on function public.andar(text) from public, anon;
revoke all on function public.criar_personagem(text, smallint) from public, anon;
grant execute on function public.andar(text) to authenticated;
grant execute on function public.criar_personagem(text, smallint) to authenticated;

