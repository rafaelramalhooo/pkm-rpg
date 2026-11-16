-- m58: NPCs passam a usar as aparências novas (p12–p48). Líderes p16–p23, Alto Comando e Campeã na Liga, demais por papel.
-- O Prof. Carvalho (NPC do laboratório, desenhado no cliente) usa p13 (cientista).
update public.treinadores t set aparencia = v.a
from (values
  ('gin_argila_lider', 16),
  ('gin_verdelume_lider', 17),
  ('gin_azurana_lider', 18),
  ('gin_ambar_lider', 19),
  ('gin_carmesim_lider', 20),
  ('gin_ametista_lider', 21),
  ('gin_quartzo_lider', 22),
  ('gin_obsidiana_lider', 23),
  ('liga_campeao_chefe', 40),
  ('liga_salao1_chefe', 25),
  ('liga_salao2_chefe', 30),
  ('liga_salao3_chefe', 41),
  ('liga_salao4_chefe', 44),
  ('ambar_edu', 29),
  ('ametista_lun', 33),
  ('argila_pedreiro', 27),
  ('azurana_cris', 32),
  ('cva_luna', 36),
  ('cva_ze', 31),
  ('carmesim_rex', 45),
  ('costa1_mar', 26),
  ('costa2_lara', 44),
  ('gin_ambar_bobina', 39),
  ('gin_ambar_fusível', 29),
  ('gin_ametista_cristal', 33),
  ('gin_ametista_reflexo', 38),
  ('gin_argila_brita', 27),
  ('gin_argila_cal', 37),
  ('gin_azurana_corvina', 26),
  ('gin_azurana_pescada', 32),
  ('gin_carmesim_cinzas', 48),
  ('gin_carmesim_fagulha', 45),
  ('gin_obsidiana_asa', 46),
  ('gin_obsidiana_garra', 42),
  ('gin_quartzo_bolero', 47),
  ('gin_quartzo_valsa', 44),
  ('gin_verdelume_fiapo', 31),
  ('gin_verdelume_musgo', 35),
  ('gruta_pedro', 27),
  ('obsidiana_sol', 28),
  ('quartzo_dora', 36),
  ('rota1_lia', 34),
  ('rota1_tiago', 47),
  ('rota10_ola', 24),
  ('rota2_bia', 38),
  ('rota2_caio', 35),
  ('rota3_tomas', 37),
  ('rota4_ravi', 43),
  ('rota5_mel', 44),
  ('rota6_dina', 25),
  ('rota7_nico', 29),
  ('rota8_ana', 36),
  ('rota8_gui', 39),
  ('rota9_cris', 27),
  ('vale_morgana', 33),
  ('verdelume_ines', 34)
) as v(id, a) where t.id = v.id;

update public.treinadores set aparencia = case classe
    when 'Pesquisadora' then 14
    when 'Domadora' then 33
    when 'Colecionadora' then 36
    when 'Treinadora Viajante' then 34
    when 'Veterano' then 46
    when 'Andarilho' then 28
    when 'Aventureira' then 44
    when 'Mochileiro' then 31
    when 'Ex-campeão local' then 30
    when 'Desafiante' then 41
    else aparencia end
where left(id, 3) = 'mq_';

update public.npcs_missao t set aparencia = v.a
from (values
  ('q_lia', 25),
  ('q_nina', 32),
  ('q_beto', 28),
  ('q_gil', 29)
) as v(id, a) where t.id = v.id;
