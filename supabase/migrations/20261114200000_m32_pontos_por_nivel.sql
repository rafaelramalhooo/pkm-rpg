-- m32: pontos de atributo de CADA nível ficam pendentes (jogador escolhe onde colocar); HP segue a fórmula.
create or replace function public._dar_exp(p_pk public.pokemons, p_sel jsonb, p_ev jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare ganho int := floor((p_sel->>'exp_base')::int * (p_sel->>'nivel')::int / 7.0 * public._ev('xp', 1)
    * (1 + (public._bonus(p_pk.dono, 'veterano') + case when p_pk.amizade >= 150 then public._bonus(p_pk.dono, 'laco') else 0 end) / 100.0)); e public.especies; novo public.pokemons := p_pk;
  g record; hpmax_ant int; evo record; r record; nome_ant text; de_ant int; lg jsonb := '{}'::jsonb; pend jsonb; k text; v int; gsum int; gnovo jsonb; pnovo jsonb;
begin
  select * into e from public.especies where id = novo.especie_id;
  if p_pk.nivel >= 1000 then ganho := 0; end if;
  novo.exp := p_pk.exp + ganho;
  p_ev := p_ev || jsonb_build_array(jsonb_build_object('t', 'exp', 'valor', ganho, 'nome', coalesce(p_pk.apelido, e.nome)));
  while novo.nivel < 1000 and novo.exp >= public.exp_para(novo.nivel + 1) loop
    novo.nivel := novo.nivel + 1;
    hpmax_ant := novo.hp_max;
    -- pontos que este nível dá (viram pendentes: o jogador decide onde colocá-los)
    lg := lg || jsonb_build_object(
      'atk', coalesce((lg->>'atk')::int, 0) + greatest(0, public.calc_stat(e.atk, novo.iv_atk, novo.nivel, public.mult_nat(novo.natureza, 'attack')) - public.calc_stat(e.atk, novo.iv_atk, novo.nivel - 1, public.mult_nat(novo.natureza, 'attack'))),
      'def', coalesce((lg->>'def')::int, 0) + greatest(0, public.calc_stat(e.def, novo.iv_def, novo.nivel, public.mult_nat(novo.natureza, 'defense')) - public.calc_stat(e.def, novo.iv_def, novo.nivel - 1, public.mult_nat(novo.natureza, 'defense'))),
      'spa', coalesce((lg->>'spa')::int, 0) + greatest(0, public.calc_stat(e.spa, novo.iv_spa, novo.nivel, public.mult_nat(novo.natureza, 'sp_attack')) - public.calc_stat(e.spa, novo.iv_spa, novo.nivel - 1, public.mult_nat(novo.natureza, 'sp_attack'))),
      'spd', coalesce((lg->>'spd')::int, 0) + greatest(0, public.calc_stat(e.spd, novo.iv_spd, novo.nivel, public.mult_nat(novo.natureza, 'sp_defense')) - public.calc_stat(e.spd, novo.iv_spd, novo.nivel - 1, public.mult_nat(novo.natureza, 'sp_defense'))),
      'spe', coalesce((lg->>'spe')::int, 0) + greatest(0, public.calc_stat(e.spe, novo.iv_spe, novo.nivel, public.mult_nat(novo.natureza, 'speed')) - public.calc_stat(e.spe, novo.iv_spe, novo.nivel - 1, public.mult_nat(novo.natureza, 'speed'))));
    novo.hp_max := public.calc_hp(e.hp, novo.iv_hp, novo.nivel);
    novo.atk := public.calc_stat(e.atk, novo.iv_atk, novo.nivel, public.mult_nat(novo.natureza, 'attack')) + public._aj(novo, 'atk');
    novo.def := public.calc_stat(e.def, novo.iv_def, novo.nivel, public.mult_nat(novo.natureza, 'defense')) + public._aj(novo, 'def');
    novo.spa := public.calc_stat(e.spa, novo.iv_spa, novo.nivel, public.mult_nat(novo.natureza, 'sp_attack')) + public._aj(novo, 'spa');
    novo.spd := public.calc_stat(e.spd, novo.iv_spd, novo.nivel, public.mult_nat(novo.natureza, 'sp_defense')) + public._aj(novo, 'spd');
    novo.spe := public.calc_stat(e.spe, novo.iv_spe, novo.nivel, public.mult_nat(novo.natureza, 'speed')) + public._aj(novo, 'spe');
    novo.hp_atual := novo.hp_atual + (novo.hp_max - hpmax_ant);
    p_ev := p_ev || jsonb_build_array(jsonb_build_object('t', 'nivel', 'nome', coalesce(p_pk.apelido, e.nome), 'nivel', novo.nivel, 'pontos', true));
    select * into evo from public.evolucoes where de = novo.especie_id and nivel is not null and nivel <= novo.nivel order by nivel desc limit 1;
    if found then
      nome_ant := coalesce(p_pk.apelido, e.nome); de_ant := novo.especie_id;
      novo := public._aplicar_evolucao(novo, evo.para);
      select * into e from public.especies where id = novo.especie_id;
      p_ev := p_ev || jsonb_build_array(jsonb_build_object('t', 'evolucao', 'nome', nome_ant, 'para', e.nome, 'especie_id', e.id, 'de_id', de_ant, 'pontos', true));
    end if;
    for g in select a.golpe_id, gg.nome from public.aprende a join public.golpes gg on gg.id = a.golpe_id
              where a.especie_id = novo.especie_id and a.nivel = novo.nivel loop
      if exists (select 1 from jsonb_array_elements(novo.golpes) x where (x->>'id')::int = g.golpe_id) then continue; end if;
      if jsonb_array_length(novo.golpes) < 4 then
        novo.golpes := novo.golpes || jsonb_build_array(jsonb_build_object('id', g.golpe_id, 'pp', (select pp from public.golpes where id = g.golpe_id)));
        p_ev := p_ev || jsonb_build_array(jsonb_build_object('t', 'aprendeu', 'nome', coalesce(p_pk.apelido, e.nome), 'golpe', g.nome, 'esqueceu', null));
      else
        insert into public.golpes_pendentes (pokemon, golpe) values (p_pk.id, g.golpe_id) on conflict do nothing;
        p_ev := p_ev || jsonb_build_array(jsonb_build_object('t', 'aprender', 'pokemon', p_pk.id, 'nome', coalesce(p_pk.apelido, e.nome), 'golpe', g.nome, 'golpe_id', g.golpe_id));
      end if;
    end loop;
  end loop;
  -- soma os pontos de nível aos pontos pendentes (os da evolução, se houve, já estão na tabela)
  select evo_pend into pend from public.pokemons where id = p_pk.id;
  gnovo := '{}'::jsonb; gsum := 0;
  foreach k in array array['atk','def','spa','spd','spe'] loop
    v := coalesce((pend->'gain'->>k)::int, 0) + coalesce((lg->>k)::int, 0);
    gnovo := gnovo || jsonb_build_object(k, v); gsum := gsum + v;
  end loop;
  pnovo := case when gsum > 0 then jsonb_build_object('gain', gnovo, 'pool', gsum) else null end;
  update public.pokemons set evo_pend = pnovo, especie_id = novo.especie_id, nivel = novo.nivel, exp = novo.exp, hp_max = novo.hp_max, atk = novo.atk, def = novo.def, spa = novo.spa,
    spd = novo.spd, spe = novo.spe, hp_atual = novo.hp_atual, golpes = novo.golpes where id = p_pk.id;
  return p_ev;
end $$;
revoke all on function public._dar_exp(public.pokemons, jsonb, jsonb) from public, anon, authenticated;
