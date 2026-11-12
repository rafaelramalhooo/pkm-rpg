-- m10: "Estou preso" — leva o jogador ao tile andável alcançável mais próximo (a partir dos portais do mapa)
create or replace function public.destravar() returns public.jogadores language plpgsql security definer set search_path = public as $$
declare
  v_j public.jogadores; v_m public.mapas; v_w int; v_h int;
  v_alc boolean[]; v_fila int[] := '{}'; v_ini int := 1; v_i int; v_x int; v_y int; v_k int;
  v_p jsonb; px int; py int; a int; b int; d int; v_melhor int := null; v_dist int := 1000000; v_d int; v_presa boolean;
begin
  if auth.uid() is null then raise exception 'Faça login primeiro.'; end if;
  select * into v_j from public.jogadores where id = auth.uid() for update;
  if not found then raise exception 'Crie seu personagem primeiro.'; end if;
  if exists (select 1 from public.batalhas where jogador = v_j.id and estado = 'ativa') then raise exception 'Termine a batalha primeiro.'; end if;
  select * into v_m from public.mapas where id = v_j.mapa_id;
  if v_m.solido is null or v_m.tipo <> 'andavel' then return v_j; end if;
  v_w := v_m.largura; v_h := v_m.altura;
  v_alc := array_fill(false, array[v_w * v_h]);
  -- sementes: tiles dos portais e a chegada padrão
  for v_p in select * from jsonb_array_elements(v_m.portais) loop
    for px in (v_p->>'x')::int .. (v_p->>'x')::int + coalesce((v_p->>'w')::int, 1) - 1 loop
      for py in (v_p->>'y')::int .. (v_p->>'y')::int + coalesce((v_p->>'h')::int, 1) - 1 loop
        if px between 0 and v_w - 1 and py between 0 and v_h - 1 and not v_alc[py * v_w + px + 1] and substr(v_m.solido, py * v_w + px + 1, 1) = '0' then
          v_alc[py * v_w + px + 1] := true; v_fila := v_fila || (py * v_w + px);
        end if;
      end loop;
    end loop;
  end loop;
  if v_m.spawn_x is not null and substr(v_m.solido, v_m.spawn_y * v_w + v_m.spawn_x + 1, 1) = '0' and not v_alc[v_m.spawn_y * v_w + v_m.spawn_x + 1] then
    v_alc[v_m.spawn_y * v_w + v_m.spawn_x + 1] := true; v_fila := v_fila || (v_m.spawn_y * v_w + v_m.spawn_x);
  end if;
  if coalesce(array_length(v_fila, 1), 0) = 0 then return v_j; end if;
  while v_ini <= array_length(v_fila, 1) loop
    v_k := v_fila[v_ini]; v_ini := v_ini + 1; v_x := v_k % v_w; v_y := v_k / v_w;
    for d in 0..3 loop
      a := v_x + case d when 0 then 1 when 1 then -1 else 0 end; b := v_y + case d when 2 then 1 when 3 then -1 else 0 end;
      if a >= 0 and b >= 0 and a < v_w and b < v_h and not v_alc[b * v_w + a + 1] and substr(v_m.solido, b * v_w + a + 1, 1) = '0' then
        v_alc[b * v_w + a + 1] := true; v_fila := v_fila || (b * v_w + a);
      end if;
    end loop;
  end loop;
  v_presa := v_j.x < 0 or v_j.y < 0 or v_j.x >= v_w or v_j.y >= v_h or not v_alc[v_j.y * v_w + v_j.x + 1];
  if not v_presa then return v_j; end if;
  for v_i in 1..array_length(v_fila, 1) loop
    v_k := v_fila[v_i]; v_d := abs((v_k % v_w) - v_j.x) + abs((v_k / v_w) - v_j.y);
    if v_d < v_dist then v_dist := v_d; v_melhor := v_k; end if;
  end loop;
  update public.jogadores set x = v_melhor % v_w, y = v_melhor / v_w, posicao_em = clock_timestamp() where id = v_j.id returning * into v_j;
  insert into public.auditoria (ator, acao, detalhe) values (auth.uid(), 'destravar', jsonb_build_object('mapa', v_j.mapa_id, 'x', v_j.x, 'y', v_j.y));
  return v_j;
end $$;
revoke all on function public.destravar() from public, anon;
grant execute on function public.destravar() to authenticated;
