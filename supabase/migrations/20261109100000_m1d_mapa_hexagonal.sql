-- M1d: mapa hexagonal (hexcrawl). Substitui o mapa andável tile a tile do M1b.
-- Coordenadas: q = coluna, r = linha (grade "odd-r": linhas ímpares deslocadas meio hexágono para a direita).
-- Em `jogadores`, x = q e y = r. PA é a única fonte de custo: andar gasta PA conforme o terreno do destino.
-- Regra de ouro: o navegador só LÊ; mover e repor PA passam por funções do servidor.

create table public.hexes (
  mapa_id text not null references public.mapas (id) on delete cascade,
  q int not null,
  r int not null,
  bioma text not null,
  tile text not null,                 -- nome do arquivo em public/assets/hex (sem .png)
  custo smallint not null check (custo between 0 and 9),
  bloqueado boolean not null default false,
  poi_id text,
  poi_nome text,
  poi_descricao text,
  rotulo text,                        -- texto desenhado no mapa
  arco_liberado smallint not null default 1,
  primary key (mapa_id, q, r)
);
alter table public.hexes enable row level security;
create policy "hexes_leitura" on public.hexes for select to authenticated using (true);
grant select on public.hexes to authenticated;

alter table public.jogadores add column pa smallint not null default 10 check (pa >= 0);

insert into public.config (chave, valor) values ('pa_por_dia', '10'::jsonb), ('arco_atual', '1'::jsonb)
on conflict (chave) do nothing;

insert into public.mapas (id, nome, largura, altura, spawn_x, spawn_y)
values ('kanto', 'Kanto (Arco 1)', 11, 14, 5, 12);

alter table public.jogadores alter column mapa_id set default 'kanto';
update public.jogadores set mapa_id = 'kanto', x = 5, y = 12, direcao = 'baixo', pa = 10, posicao_em = now();
delete from public.mapas where id = 'pallet';

insert into public.hexes (mapa_id, q, r, bioma, tile, custo, bloqueado, poi_id, poi_nome, poi_descricao, rotulo) values
  ('kanto',0,0,'montanha','grass_14',3,false,null,null,null,null),
  ('kanto',1,0,'montanha','grass_14',3,false,null,null,null,null),
  ('kanto',2,0,'montanha','grass_14',3,false,null,null,null,null),
  ('kanto',3,0,'montanha','grass_14',3,false,null,null,null,null),
  ('kanto',4,0,'colina','grass_15',2,false,null,null,null,null),
  ('kanto',5,0,'planicie','grass_05',1,false,null,null,null,null),
  ('kanto',6,0,'colina','grass_15',2,false,null,null,null,null),
  ('kanto',7,0,'montanha','grass_14',3,false,null,null,null,null),
  ('kanto',8,0,'montanha','grass_14',3,false,null,null,null,null),
  ('kanto',9,0,'montanha','grass_14',3,false,null,null,null,null),
  ('kanto',10,0,'montanha','grass_14',3,false,null,null,null,null),
  ('kanto',0,1,'montanha','grass_14',3,false,null,null,null,null),
  ('kanto',1,1,'colina','grass_15',2,false,null,null,null,null),
  ('kanto',2,1,'planicie','grass_05',1,false,null,null,null,null),
  ('kanto',3,1,'planicie','grass_05',1,false,null,null,null,null),
  ('kanto',4,1,'planicie','grass_05',1,false,null,null,null,null),
  ('kanto',5,1,'cidade','medieval_smallCastle',1,false,'pewter','Pewter City','Cidade de pedra aos pés das montanhas. Em breve: o primeiro ginásio.','Pewter City'),
  ('kanto',6,1,'planicie','grass_05',1,false,null,null,null,null),
  ('kanto',7,1,'colina','grass_15',2,false,null,null,null,null),
  ('kanto',8,1,'montanha','grass_14',3,false,null,null,null,null),
  ('kanto',9,1,'montanha','grass_14',3,false,null,null,null,null),
  ('kanto',10,1,'montanha','grass_14',3,false,null,null,null,null),
  ('kanto',0,2,'colina','grass_15',2,false,null,null,null,null),
  ('kanto',1,2,'planicie','grass_05',1,false,null,null,null,null),
  ('kanto',2,2,'planicie','grass_05',1,false,null,null,null,null),
  ('kanto',3,2,'floresta','grass_12',2,false,null,null,null,null),
  ('kanto',4,2,'planicie','grass_05',1,false,null,null,null,null),
  ('kanto',5,2,'estrada','dirt_06',1,false,null,null,null,null),
  ('kanto',6,2,'planicie','grass_05',1,false,null,null,null,null),
  ('kanto',7,2,'planicie','grass_05',1,false,null,null,null,null),
  ('kanto',8,2,'planicie','grass_05',1,false,null,null,null,null),
  ('kanto',9,2,'colina','grass_15',2,false,null,null,null,null),
  ('kanto',10,2,'montanha','grass_14',3,false,null,null,null,null),
  ('kanto',0,3,'planicie','grass_05',1,false,null,null,null,null),
  ('kanto',1,3,'floresta','grass_12',2,false,null,null,null,null),
  ('kanto',2,3,'floresta','grass_12',2,false,null,null,null,null),
  ('kanto',3,3,'floresta','grass_12',2,false,null,null,null,null),
  ('kanto',4,3,'floresta','grass_12',2,false,null,null,null,null),
  ('kanto',5,3,'floresta_densa','grass_13',2,false,null,null,null,null),
  ('kanto',6,3,'floresta','grass_12',2,false,null,null,null,null),
  ('kanto',7,3,'floresta','grass_12',2,false,null,null,null,null),
  ('kanto',8,3,'planicie','grass_05',1,false,null,null,null,null),
  ('kanto',9,3,'planicie','grass_05',1,false,null,null,null,null),
  ('kanto',10,3,'colina','grass_15',2,false,null,null,null,null),
  ('kanto',0,4,'planicie','grass_05',1,false,null,null,null,null),
  ('kanto',1,4,'floresta','grass_12',2,false,null,null,null,null),
  ('kanto',2,4,'floresta','grass_12',2,false,null,null,null,null),
  ('kanto',3,4,'floresta','grass_12',2,false,null,null,null,null),
  ('kanto',4,4,'floresta_densa','grass_13',2,false,null,null,null,null),
  ('kanto',5,4,'floresta_densa','grass_13',2,false,null,null,null,'Floresta de Viridian'),
  ('kanto',6,4,'floresta','grass_12',2,false,null,null,null,null),
  ('kanto',7,4,'floresta','grass_12',2,false,null,null,null,null),
  ('kanto',8,4,'floresta','grass_12',2,false,null,null,null,null),
  ('kanto',9,4,'planicie','grass_05',1,false,null,null,null,null),
  ('kanto',10,4,'planicie','grass_05',1,false,null,null,null,null),
  ('kanto',0,5,'planicie','grass_05',1,false,null,null,null,null),
  ('kanto',1,5,'floresta','grass_12',2,false,null,null,null,null),
  ('kanto',2,5,'floresta','grass_12',2,false,null,null,null,null),
  ('kanto',3,5,'floresta','grass_12',2,false,null,null,null,null),
  ('kanto',4,5,'floresta','grass_12',2,false,null,null,null,null),
  ('kanto',5,5,'floresta_densa','grass_13',2,false,null,null,null,null),
  ('kanto',6,5,'floresta','grass_12',2,false,null,null,null,null),
  ('kanto',7,5,'floresta','grass_12',2,false,null,null,null,null),
  ('kanto',8,5,'floresta','grass_12',2,false,null,null,null,null),
  ('kanto',9,5,'planicie','grass_05',1,false,null,null,null,null),
  ('kanto',10,5,'planicie','grass_05',1,false,null,null,null,null),
  ('kanto',0,6,'planicie','grass_05',1,false,null,null,null,null),
  ('kanto',1,6,'planicie','grass_05',1,false,null,null,null,null),
  ('kanto',2,6,'planicie','grass_05',1,false,null,null,null,null),
  ('kanto',3,6,'colina','grass_15',2,false,null,null,null,null),
  ('kanto',4,6,'planicie','grass_05',1,false,null,null,null,null),
  ('kanto',5,6,'estrada','dirt_06',1,false,null,null,null,null),
  ('kanto',6,6,'planicie','grass_05',1,false,null,null,null,null),
  ('kanto',7,6,'planicie','grass_05',1,false,null,null,null,null),
  ('kanto',8,6,'colina','grass_15',2,false,null,null,null,null),
  ('kanto',9,6,'planicie','grass_05',1,false,null,null,null,null),
  ('kanto',10,6,'planicie','grass_05',1,false,null,null,null,null),
  ('kanto',0,7,'agua','agua_2',0,true,null,null,null,null),
  ('kanto',1,7,'planicie','grass_05',1,false,null,null,null,null),
  ('kanto',2,7,'planicie','grass_05',1,false,null,null,null,null),
  ('kanto',3,7,'planicie','grass_05',1,false,null,null,null,null),
  ('kanto',4,7,'planicie','grass_05',1,false,null,null,null,null),
  ('kanto',5,7,'cidade','modern_villageLarge',1,false,'viridian','Viridian City','Cidade no caminho para o norte. Em breve: Centro Pokémon e loja.','Viridian City'),
  ('kanto',6,7,'planicie','grass_05',1,false,null,null,null,null),
  ('kanto',7,7,'planicie','grass_05',1,false,null,null,null,null),
  ('kanto',8,7,'planicie','grass_05',1,false,null,null,null,null),
  ('kanto',9,7,'planicie','grass_05',1,false,null,null,null,null),
  ('kanto',10,7,'agua','agua_3',0,true,null,null,null,null),
  ('kanto',0,8,'agua','agua_3',0,true,null,null,null,null),
  ('kanto',1,8,'agua','agua_1',0,true,null,null,null,null),
  ('kanto',2,8,'planicie','grass_05',1,false,null,null,null,null),
  ('kanto',3,8,'planicie','grass_05',1,false,null,null,null,null),
  ('kanto',4,8,'floresta','grass_12',2,false,null,null,null,null),
  ('kanto',5,8,'estrada','dirt_06',1,false,null,null,null,null),
  ('kanto',6,8,'planicie','grass_05',1,false,null,null,null,null),
  ('kanto',7,8,'planicie','grass_05',1,false,null,null,null,null),
  ('kanto',8,8,'planicie','grass_05',1,false,null,null,null,null),
  ('kanto',9,8,'planicie','grass_05',1,false,null,null,null,null),
  ('kanto',10,8,'agua','agua_1',0,true,null,null,null,null),
  ('kanto',0,9,'agua','agua_1',0,true,null,null,null,null),
  ('kanto',1,9,'agua','agua_2',0,true,null,null,null,null),
  ('kanto',2,9,'planicie','grass_05',1,false,null,null,null,null),
  ('kanto',3,9,'planicie','grass_05',1,false,null,null,null,null),
  ('kanto',4,9,'planicie','grass_05',1,false,null,null,null,null),
  ('kanto',5,9,'estrada','dirt_06',1,false,null,null,null,'Rota 1'),
  ('kanto',6,9,'planicie','grass_05',1,false,null,null,null,null),
  ('kanto',7,9,'planicie','grass_05',1,false,null,null,null,null),
  ('kanto',8,9,'floresta','grass_12',2,false,null,null,null,null),
  ('kanto',9,9,'planicie','grass_05',1,false,null,null,null,null),
  ('kanto',10,9,'agua','agua_2',0,true,null,null,null,null),
  ('kanto',0,10,'agua','agua_2',0,true,null,null,null,null),
  ('kanto',1,10,'agua','agua_3',0,true,null,null,null,null),
  ('kanto',2,10,'planicie','grass_05',1,false,null,null,null,null),
  ('kanto',3,10,'planicie','grass_05',1,false,null,null,null,null),
  ('kanto',4,10,'floresta','grass_12',2,false,null,null,null,null),
  ('kanto',5,10,'estrada','dirt_06',1,false,null,null,null,null),
  ('kanto',6,10,'planicie','grass_05',1,false,null,null,null,null),
  ('kanto',7,10,'planicie','grass_05',1,false,null,null,null,null),
  ('kanto',8,10,'planicie','grass_05',1,false,null,null,null,null),
  ('kanto',9,10,'areia','sand_07',1,false,null,null,null,null),
  ('kanto',10,10,'agua','agua_3',0,true,null,null,null,null),
  ('kanto',0,11,'agua','agua_3',0,true,null,null,null,null),
  ('kanto',1,11,'agua','agua_1',0,true,null,null,null,null),
  ('kanto',2,11,'planicie','grass_05',1,false,null,null,null,null),
  ('kanto',3,11,'planicie','grass_05',1,false,null,null,null,null),
  ('kanto',4,11,'planicie','grass_05',1,false,null,null,null,null),
  ('kanto',5,11,'estrada','dirt_06',1,false,null,null,null,null),
  ('kanto',6,11,'planicie','grass_05',1,false,null,null,null,null),
  ('kanto',7,11,'planicie','grass_05',1,false,null,null,null,null),
  ('kanto',8,11,'planicie','grass_05',1,false,null,null,null,null),
  ('kanto',9,11,'areia','sand_07',1,false,null,null,null,null),
  ('kanto',10,11,'areia','sand_07',1,false,null,null,null,null),
  ('kanto',0,12,'agua','agua_1',0,true,null,null,null,null),
  ('kanto',1,12,'agua','agua_2',0,true,null,null,null,null),
  ('kanto',2,12,'agua','agua_3',0,true,null,null,null,null),
  ('kanto',3,12,'planicie','grass_05',1,false,null,null,null,null),
  ('kanto',4,12,'planicie','grass_05',1,false,null,null,null,null),
  ('kanto',5,12,'cidade','modern_houseSmall',1,false,'pallet','Pallet Town','Cidade pequena e tranquila, ponto de partida dos novos treinadores. O laboratório do Professor Carvalho fica aqui. Em breve: escolher o primeiro Pokémon.','Pallet Town'),
  ('kanto',6,12,'planicie','grass_05',1,false,null,null,null,null),
  ('kanto',7,12,'planicie','grass_05',1,false,null,null,null,null),
  ('kanto',8,12,'planicie','grass_05',1,false,null,null,null,null),
  ('kanto',9,12,'areia','sand_07',1,false,null,null,null,null),
  ('kanto',10,12,'areia','sand_07',1,false,null,null,null,null),
  ('kanto',0,13,'agua','agua_2',0,true,null,null,null,null),
  ('kanto',1,13,'agua','agua_3',0,true,null,null,null,null),
  ('kanto',2,13,'agua','agua_1',0,true,null,null,null,null),
  ('kanto',3,13,'agua','agua_2',0,true,null,null,null,null),
  ('kanto',4,13,'agua','agua_3',0,true,null,null,null,null),
  ('kanto',5,13,'agua','agua_1',0,true,null,null,null,null),
  ('kanto',6,13,'agua','agua_2',0,true,null,null,null,null),
  ('kanto',7,13,'agua','agua_3',0,true,null,null,null,null),
  ('kanto',8,13,'agua','agua_1',0,true,null,null,null,null),
  ('kanto',9,13,'agua','agua_2',0,true,null,null,null,null),
  ('kanto',10,13,'agua','agua_3',0,true,null,null,null,null);

-- Novo personagem nasce no ponto inicial de Kanto.
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
  if auth.uid() is null then
    raise exception 'Faça login primeiro.';
  end if;
  if exists (select 1 from public.jogadores where id = auth.uid()) then
    raise exception 'Você já tem um personagem.';
  end if;
  if char_length(v_nome) not between 2 and 12 or v_nome !~ '^[A-Za-zÀ-ÿ0-9 ]+$' then
    raise exception 'O nome deve ter de 2 a 12 letras, números ou espaços.';
  end if;
  if p_aparencia is null or p_aparencia not between 0 and 3 then
    raise exception 'Aparência inválida.';
  end if;
  if exists (select 1 from public.jogadores where lower(nome) = lower(v_nome)) then
    raise exception 'Esse nome já está em uso.';
  end if;

  select * into v_mapa from public.mapas where id = 'kanto';

  insert into public.jogadores (id, nome, aparencia, mapa_id, x, y)
  values (auth.uid(), v_nome, p_aparencia, v_mapa.id, v_mapa.spawn_x, v_mapa.spawn_y)
  returning * into v_jogador;

  insert into public.auditoria (ator, acao, detalhe)
  values (auth.uid(), 'criar_personagem', jsonb_build_object('nome', v_nome));

  return v_jogador;
end;
$$;

-- Anda um hexágono vizinho: valida destino, bloqueio, liberação do arco e PA; desconta e grava.
create or replace function public.mover(p_q int, p_r int)
returns public.jogadores
language plpgsql
security definer
set search_path = public
as $$
declare
  v_j public.jogadores;
  v_hex public.hexes;
  v_arco int;
  v_dq int;
  v_dr int;
  v_vizinho boolean;
begin
  if auth.uid() is null then
    raise exception 'Faça login primeiro.';
  end if;
  select * into v_j from public.jogadores where id = auth.uid() for update;
  if not found then
    raise exception 'Crie seu personagem primeiro.';
  end if;
  if p_q is null or p_r is null then
    raise exception 'Destino inválido.';
  end if;

  select * into v_hex from public.hexes where mapa_id = v_j.mapa_id and q = p_q and r = p_r;
  if not found then
    raise exception 'Esse lugar não existe no mapa.';
  end if;

  v_dq := p_q - v_j.x;
  v_dr := p_r - v_j.y;
  if v_j.y % 2 = 0 then
    v_vizinho := (v_dq, v_dr) in ((-1, 0), (1, 0), (-1, -1), (0, -1), (-1, 1), (0, 1));
  else
    v_vizinho := (v_dq, v_dr) in ((-1, 0), (1, 0), (0, -1), (1, -1), (0, 1), (1, 1));
  end if;
  if not v_vizinho then
    raise exception 'Só dá para andar para um hexágono vizinho.';
  end if;

  if v_hex.bloqueado then
    raise exception 'O caminho está bloqueado.';
  end if;
  select coalesce((select (valor #>> '{}')::int from public.config where chave = 'arco_atual'), 1) into v_arco;
  if v_hex.arco_liberado > v_arco then
    raise exception 'Essa região ainda não foi liberada.';
  end if;
  if v_j.pa < v_hex.custo then
    raise exception 'PA insuficiente: este terreno custa % e você tem %.', v_hex.custo, v_j.pa;
  end if;

  update public.jogadores
     set x = p_q, y = p_r, pa = pa - v_hex.custo, posicao_em = now()
   where id = v_j.id
   returning * into v_j;
  return v_j;
end;
$$;

-- Mestre repõe os PA (só os dele ou de todos) até o valor diário da tabela config.
create or replace function public.repor_pa(p_todos boolean default false)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pa smallint;
  v_n int;
begin
  if auth.uid() is null then
    raise exception 'Faça login primeiro.';
  end if;
  if not public.eh_mestre() then
    raise exception 'Só o Mestre pode repor PA.';
  end if;
  select coalesce((select (valor #>> '{}')::smallint from public.config where chave = 'pa_por_dia'), 10) into v_pa;
  update public.jogadores set pa = v_pa where p_todos or id = auth.uid();
  get diagnostics v_n = row_count;
  insert into public.auditoria (ator, acao, detalhe)
  values (auth.uid(), 'repor_pa', jsonb_build_object('todos', p_todos, 'jogadores', v_n));
  return v_n;
end;
$$;

-- A posição agora só muda por mover(): sem ela ninguém teletransporta sem gastar PA.
drop function public.salvar_posicao(int, int, text);

revoke all on function public.mover(int, int) from public, anon;
revoke all on function public.repor_pa(boolean) from public, anon;
revoke all on function public.criar_personagem(text, smallint) from public, anon;
grant execute on function public.mover(int, int) to authenticated;
grant execute on function public.repor_pa(boolean) to authenticated;
grant execute on function public.criar_personagem(text, smallint) to authenticated;
