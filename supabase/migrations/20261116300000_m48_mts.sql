-- m48: MTs (Geração 9) — catálogo, compatibilidade por espécie, compra na loja grande e ensino (infinito, troca 1 dos 4 golpes).
insert into public.golpes (id, slug, nome, tipo, categoria, poder, precisao, pp, prioridade, arco) values
(512,'acrobatics','Acrobatics','flying','physical',55,100,15,0,1),
(914,'alluring-voice','Alluring Voice','fairy','special',80,100,10,0,1),
(502,'ally-switch','Ally Switch','psychic','status',null,null,15,2,1),
(213,'attract','Attract','normal','status',null,100,15,0,1),
(419,'avalanche','Avalanche','ice','physical',60,100,10,-4,1),
(251,'beat-up','Beat Up','dark','physical',null,100,10,0,1),
(307,'blast-burn','Blast Burn','fire','special',150,90,5,0,1),
(776,'body-press','Body Press','fighting','physical',80,100,10,0,1),
(340,'bounce','Bounce','flying','physical',85,85,5,0,1),
(784,'breaking-swipe','Breaking Swipe','dragon','physical',60,100,15,0,1),
(693,'brutal-swing','Brutal Swing','dark','physical',60,100,20,0,1),
(807,'burning-jealousy','Burning Jealousy','fire','special',70,100,5,0,1),
(886,'chilling-water','Chilling Water','water','special',50,100,20,0,1),
(811,'coaching','Coaching','fighting','status',null,null,10,0,1),
(434,'draco-meteor','Draco Meteor','dragon','special',130,90,5,0,1),
(913,'dragon-cheer','Dragon Cheer','dragon','status',0,0,15,0,1),
(577,'draining-kiss','Draining Kiss','fairy','special',50,100,10,0,1),
(814,'dual-wingbeat','Dual Wingbeat','flying','physical',40,90,10,0,1),
(527,'electroweb','Electroweb','electric','special',55,95,15,0,1),
(797,'expanding-force','Expanding Force','psychic','special',80,100,10,0,1),
(263,'facade','Facade','normal','physical',70,100,20,0,1),
(297,'feather-dance','Feather Dance','flying','status',null,100,15,0,1),
(519,'fire-pledge','Fire Pledge','fire','special',80,100,10,0,1),
(488,'flame-charge','Flame Charge','fire','physical',50,100,20,0,1),
(812,'flip-turn','Flip Turn','water','physical',60,100,20,0,1),
(19,'fly','Fly','flying','physical',90,95,15,0,1),
(411,'focus-blast','Focus Blast','fighting','special',120,70,5,0,1),
(492,'foul-play','Foul Play','dark','physical',95,100,15,0,1),
(338,'frenzy-plant','Frenzy Plant','grass','special',150,90,5,0,1),
(447,'grass-knot','Grass Knot','grass','special',null,100,20,0,1),
(520,'grass-pledge','Grass Pledge','grass','special',80,100,10,0,1),
(803,'grassy-glide','Grassy Glide','grass','physical',55,100,20,0,1),
(258,'hail','Hail','ice','status',null,null,10,0,1),
(912,'hard-press','Hard Press','steel','physical',0,100,10,0,1),
(535,'heat-crash','Heat Crash','fire','physical',null,100,10,0,1),
(308,'hydro-cannon','Hydro Cannon','water','special',150,90,5,0,1),
(861,'ice-spinner','Ice Spinner','ice','physical',80,100,15,0,1),
(808,'lash-out','Lash Out','dark','physical',75,100,5,0,1),
(679,'lunge','Lunge','bug','physical',80,100,15,0,1),
(478,'magic-room','Magic Room','psychic','status',null,null,10,0,1),
(345,'magical-leaf','Magical Leaf','grass','special',60,null,20,0,1),
(800,'meteor-beam','Meteor Beam','rock','special',120,90,10,0,1),
(802,'misty-explosion','Misty Explosion','fairy','special',100,100,5,0,1),
(581,'misty-terrain','Misty Terrain','fairy','status',null,null,10,0,1),
(220,'pain-split','Pain Split','normal','status',null,null,20,0,1),
(566,'phantom-force','Phantom Force','ghost','physical',90,100,10,0,1),
(342,'poison-tail','Poison Tail','poison','physical',50,100,25,0,1),
(676,'pollen-puff','Pollen Puff','bug','special',90,100,15,0,1),
(809,'poltergeist','Poltergeist','ghost','physical',110,90,5,0,1),
(884,'pounce','Pounce','bug','physical',50,100,20,0,1),
(706,'psychic-fangs','Psychic Fangs','psychic','physical',85,100,10,0,1),
(917,'psychic-noise','Psychic Noise','psychic','special',75,100,10,0,1),
(678,'psychic-terrain','Psychic Terrain','psychic','status',null,null,10,0,1),
(279,'revenge','Revenge','fighting','physical',60,100,10,-4,1),
(317,'rock-tomb','Rock Tomb','rock','physical',60,95,15,0,1),
(503,'scald','Scald','water','special',80,100,15,0,1),
(799,'scale-shot','Scale Shot','dragon','physical',25,90,20,0,1),
(815,'scorching-sands','Scorching Sands','ground','special',70,100,10,0,1),
(421,'shadow-claw','Shadow Claw','ghost','physical',70,100,15,0,1),
(285,'skill-swap','Skill Swap','psychic','status',null,null,10,0,1),
(806,'skitter-smack','Skitter Smack','bug','physical',70,90,10,0,1),
(684,'smart-strike','Smart Strike','steel','physical',70,null,10,0,1),
(555,'snarl','Snarl','dark','special',55,95,15,0,1),
(669,'solar-blade','Solar Blade','grass','physical',125,100,10,0,1),
(796,'steel-beam','Steel Beam','steel','special',140,95,5,0,1),
(211,'steel-wing','Steel Wing','steel','physical',70,90,25,0,1),
(522,'struggle-bug','Struggle Bug','bug','special',50,100,20,0,1),
(164,'substitute','Substitute','normal','status',null,null,10,0,1),
(916,'supercell-slam','Supercell Slam','electric','physical',100,95,15,0,1),
(915,'temper-flare','Temper Flare','fire','physical',75,100,10,0,1),
(851,'tera-blast','Tera Blast','normal','special',80,100,10,0,1),
(168,'thief','Thief','dark','physical',60,100,25,0,1),
(675,'throat-chop','Throat Chop','dark','physical',80,100,15,0,1),
(885,'trailblaze','Trailblaze','grass','physical',50,100,20,0,1),
(271,'trick','Trick','psychic','status',null,100,10,0,1),
(433,'trick-room','Trick Room','psychic','status',null,null,5,-7,1),
(813,'triple-axel','Triple Axel','ice','physical',20,90,10,0,1),
(369,'u-turn','U Turn','bug','physical',70,100,20,0,1),
(918,'upper-hand','Upper Hand','fighting','physical',65,100,15,3,1),
(599,'venom-drench','Venom Drench','poison','status',null,100,20,0,1),
(521,'volt-switch','Volt Switch','electric','special',70,100,20,0,1),
(518,'water-pledge','Water Pledge','water','special',80,100,10,0,1),
(311,'weather-ball','Weather Ball','normal','special',50,100,10,0,1),
(528,'wild-charge','Wild Charge','electric','physical',90,100,15,0,1)
on conflict do nothing;

create table if not exists public.mt_catalogo (num int primary key, golpe_id int not null unique references public.golpes (id), arco smallint not null default 1, preco int not null default 1000, ativa boolean not null default true);
create table if not exists public.mt_compat (especie_id int not null references public.especies (id) on delete cascade, golpe_id int not null references public.golpes (id) on delete cascade, primary key (especie_id, golpe_id));
create table if not exists public.mt_jogador (jogador uuid not null references public.jogadores (id) on delete cascade, num int not null references public.mt_catalogo (num) on delete cascade, obtida_em timestamptz not null default now(), primary key (jogador, num));
alter table public.mt_catalogo enable row level security; alter table public.mt_compat enable row level security; alter table public.mt_jogador enable row level security;
drop policy if exists mt_cat_leitura on public.mt_catalogo; create policy mt_cat_leitura on public.mt_catalogo for select to authenticated using (true);
drop policy if exists mt_compat_leitura on public.mt_compat; create policy mt_compat_leitura on public.mt_compat for select to authenticated using (true);
drop policy if exists mt_jog_leitura on public.mt_jogador; create policy mt_jog_leitura on public.mt_jogador for select to authenticated using (jogador = auth.uid());
grant select on public.mt_catalogo, public.mt_compat, public.mt_jogador to authenticated;

-- catálogo: arco e preço por poder; golpes muito fortes e utilitários valiosos ficam nos arcos finais (o Mestre ajusta na tabela)
with base as (
  select g.id as gid, g.slug, g.poder,
    case
      when g.slug in ('earthquake','blizzard','fire-blast','hydro-pump','thunder','hyper-beam','giga-impact','outrage','close-combat','draco-meteor','focus-blast','overheat','flare-blitz','superpower','leaf-storm','solar-beam','stone-edge','future-sight','blast-burn','frenzy-plant','hydro-cannon','steel-beam','meteor-beam','heat-crash','solar-blade','poltergeist') then 5
      when g.slug in ('ice-beam','thunderbolt','flamethrower','surf','psychic','shadow-ball','earth-power','energy-ball','sludge-bomb','brave-bird','dragon-claw','iron-head','x-scissor','gunk-shot','play-rough','leaf-blade','hurricane','hyper-voice','dark-pulse','aura-sphere','flash-cannon','bug-buzz','power-gem','drill-run','waterfall','liquidation','megahorn','fly','dig','swords-dance','calm-mind','dragon-dance','nasty-plot','bulk-up','substitute','toxic','will-o-wisp','thunder-wave','trick-room','stealth-rock','cosmic-power','iron-defense') then 4
      when g.categoria = 'status' then case when g.slug in ('protect','rest','reflect','light-screen','rain-dance','sunny-day','sandstorm','snowscape','taunt','encore','roost','baton-pass','sleep-talk','spikes','toxic-spikes','tailwind','haze','focus-energy') then 3 else 2 end
      when g.poder is null or g.poder = 0 then 2
      when g.poder <= 60 then 1 when g.poder <= 80 then 2 when g.poder <= 95 then 3 when g.poder <= 120 then 4 else 5 end as arco
  from public.golpes g where g.slug = any (string_to_array('acid-spray,acrobatics,aerial-ace,agility,air-cutter,air-slash,alluring-voice,ally-switch,amnesia,assurance,attract,aura-sphere,avalanche,baton-pass,beat-up,blast-burn,blizzard,body-press,body-slam,bounce,brave-bird,breaking-swipe,brick-break,brine,brutal-swing,bug-bite,bug-buzz,bulk-up,bulldoze,bullet-seed,burning-jealousy,calm-mind,charge,charge-beam,charm,chilling-water,close-combat,coaching,confuse-ray,cosmic-power,cross-poison,crunch,curse,dark-pulse,dazzling-gleam,dig,disarming-voice,dive,double-edge,draco-meteor,dragon-cheer,dragon-claw,dragon-dance,dragon-pulse,dragon-tail,drain-punch,draining-kiss,drill-run,dual-wingbeat,earth-power,earthquake,eerie-impulse,electric-terrain,electro-ball,electroweb,encore,endeavor,endure,energy-ball,expanding-force,facade,fake-tears,false-swipe,feather-dance,fire-blast,fire-fang,fire-pledge,fire-punch,fire-spin,flame-charge,flamethrower,flare-blitz,flash-cannon,fling,flip-turn,fly,focus-blast,focus-energy,focus-punch,foul-play,frenzy-plant,future-sight,giga-drain,giga-impact,grass-knot,grass-pledge,grassy-glide,grassy-terrain,gravity,gunk-shot,gyro-ball,hail,hard-press,haze,headbutt,heat-crash,heat-wave,heavy-slam,helping-hand,hex,high-horsepower,hurricane,hydro-cannon,hydro-pump,hyper-beam,hyper-voice,ice-beam,ice-fang,ice-punch,ice-spinner,icicle-spear,icy-wind,imprison,iron-defense,iron-head,iron-tail,knock-off,lash-out,leaf-blade,leaf-storm,leech-life,light-screen,liquidation,low-kick,low-sweep,lunge,magic-room,magical-leaf,mega-drain,mega-kick,mega-punch,megahorn,metal-claw,metal-sound,meteor-beam,metronome,misty-explosion,misty-terrain,mud-shot,mud-slap,muddy-water,nasty-plot,night-shade,outrage,overheat,pain-split,pay-day,payback,petal-blizzard,phantom-force,pin-missile,play-rough,poison-jab,poison-tail,pollen-puff,poltergeist,pounce,power-gem,protect,psybeam,psych-up,psychic,psychic-fangs,psychic-noise,psychic-terrain,psycho-cut,psyshock,rain-dance,razor-shell,reflect,rest,retaliate,revenge,reversal,roar,rock-blast,rock-slide,rock-tomb,roost,round,safeguard,sand-tomb,sandstorm,scald,scale-shot,scary-face,scorching-sands,screech,seed-bomb,shadow-ball,shadow-claw,skill-swap,skitter-smack,sleep-talk,sludge-bomb,sludge-wave,smack-down,smart-strike,snarl,snore,snowscape,solar-beam,solar-blade,spikes,spite,stealth-rock,steel-beam,steel-wing,stomping-tantrum,stone-edge,stored-power,struggle-bug,substitute,sunny-day,super-fang,supercell-slam,superpower,surf,swift,swords-dance,tailwind,take-down,taunt,temper-flare,tera-blast,thief,throat-chop,thunder,thunder-fang,thunder-punch,thunder-wave,thunderbolt,toxic,toxic-spikes,trailblaze,tri-attack,trick,trick-room,triple-axel,u-turn,upper-hand,uproar,vacuum-wave,venom-drench,venoshock,volt-switch,water-pledge,water-pulse,waterfall,weather-ball,whirlpool,wild-charge,will-o-wisp,wonder-room,work-up,x-scissor,zen-headbutt', ','))
)
insert into public.mt_catalogo (num, golpe_id, arco, preco)
select row_number() over (order by arco, coalesce(poder, 0), slug), gid, arco, (array[800,1500,2500,4000,6000])[arco] from base
on conflict (golpe_id) do nothing;

-- compatibilidade: bitset por espécie na ordem alfabética dos slugs (bit i = byte i/8, bit i%8)
insert into public.mt_compat (especie_id, golpe_id)
select c.sid, g.id
from (values (1,'0100042004040100580100d0031000400202000000011000401808c0a00414400800'),(2,'0100042004040100580100d0031000400202000000011001401808c0a00414400800'),(3,'0101043004040118580100f4031004400202004004011001481808c4a00414400800'),(4,'000064000022780048fd4b0100140000004000060001100d080900c0b08600004800'),(5,'000064000022780048fd4b0100140000000000060001100d080900c0b08600004800'),(6,'3680641000227d1048fc6b2100960400000000060001100d190908c0b08600004800'),(7,'0000450008200100480018019010d20a100050000001120000080040880400001b04'),(8,'0000450008200100480018019010d20a100050000001120000080040880400001b04'),(9,'00184700082a211048005c219010d70a100050000001120d08480040880400001b04'),(10,'00000000000000000100000000000000000000000000000000000000000000000000'),(11,'00000000000000000100000000000008000000000000000000000000000000000000'),(12,'222400040000000159000030008004080000000010091260800a0ac0100800420000'),(13,'00000000000000000000000000000000000000000000000000000000000000000000'),(14,'00000000000000000000000000000000000000000000000000000000000000000000'),(15,'00004000000000024000000000010400000400020401181000100840000004020002'),(16,'00000000000000004000200000010000000000000001181000000040000004020000'),(17,'00000000000000004000200000010000000000000001181000000040000004020000'),(18,'00000000000000004000200000010400000000000001181000000040000004020000'),(19,'00000100002000004000000000011020000000000001100080000040002107020000'),(20,'00000100002000004000000000011420000000000001100080000040002107020000'),(21,'00000000000000024000200000010000000000000001101000000040000024020000'),(22,'00000000000000024000200000010400000000000001101000000040000024020000'),(23,'01000000002a011048080010880000c0040030000c11120c4c3c41c0800c1c400000'),(24,'01002410002a411048080030880024c0040030080c11120c4c3c41c4805c1c400000'),(25,'48004400076000e1cf000841001000400800800002019a000008004098ac13842000'),(26,'48004400076000e14f004861001004400800800002019a000008004098ac13842000'),(27,'0c014410002401184c01080110400040244030000401108c1149a0ccb11c00000002'),(28,'0c0144100024011a4c01482118400440244030000401108c1149a0ccb11c00000002'),(29,'004405000422000848008000001010200000000004011220001902c000280a600000'),(30,'004405000422000848008000001010200000000004011220001902c400280a600000'),(31,'005447100422201a4824c9200070542200181012040112ae813982cc0cb90a681000'),(32,'004505000020000a48008000001010200000000004011220009902c000280a600000'),(33,'004505000020000a48008000001010200000000004011220009902c400280a600000'),(34,'005547100020201a4824c9200070542200381012040112ae81b982cc0cb90a681000'),(35,'402145800e708105ce2409410410584608020f01020f1b00800a88d090ac43080204'),(36,'402145800e708105ce24496904105c4608020f01020f1b00800a88d090ac43080204'),(37,'08200440442801005ac40302003400040000800c00051001000841c0900400004804'),(38,'082004c044280100dac40322003404040000800d00051101900849d0900400004804'),(39,'402147800c788101de2409411410d84208028e08022d1b00810a88d090ad13082204'),(40,'402147800c788101fe2449611410dc4208028e08022d1b00810a88d090ad13082204'),(41,'00000000000000000000000000000000000000000000000000000000000000000000'),(42,'00000000000000000000000000000000000000000000000000000000000000000000'),(43,'010000200400000058000050031000000202000000011000401808c0200414400000'),(44,'010000200400000058000050031000000202004010011000401808c0200414400000'),(45,'010004200410000058000870031004000202004010011000403818c0200414400800'),(46,'00000000000000000000000000000000000000000000000000000000000000000000'),(47,'00000000000000000000000000000000000000000000000000000000000000000000'),(48,'09200006400000005c0000100000000084000001402b1000001e08e0900c0c400004'),(49,'3b200006400001005c0000300000040084000001402b1000003e08e0900c0c420004'),(50,'08000410042401184c00000200100000000030000001908e115980cca01c00080000'),(51,'08000410042401184c00002200000400000030000001908e117980cca01c00080000'),(52,'0c0104000c280100cc010002081008c20040800882051200c00941c0903d13020000'),(53,'0c0104000c280100cc01002208100cc20040800882051201c00d41c0903d13020000'),(54,'00014580482001004e001801801052427800d200002f1300000b0040980d10101604'),(55,'00014580482001004e005869801056427800d200802f1300000b0040980d10101604'),(56,'02004418102481104e20480108104080600002060401920c480940cc909d020a0000'),(57,'02004418102481104e20482108104480600002060401920c4849c0cc90bd021a0000'),(58,'080004001426010048cc0300001400000000000602119001080801c0904e00006000'),(59,'0c0004101426210048cc032000160c100000000602119001180809c0904e00006000'),(60,'00010510082001084e00000180101202300070000009120000080040980c00001e00'),(61,'00014510082001184e0008018010520270007200000d120000080040980c00001e00'),(62,'00214518382081184e0048218050564270007200040d920c08080040981d00141e00'),(63,'00000000000000000000000000000000000000000000000000000000000000000000'),(64,'00000000000000000000000000000000000000000000000000000000000000000000'),(65,'00000000000000000000000000000000000000000000000000000000000000000000'),(66,'00000000000000000000000000000000000000000000000000000000000000000000'),(67,'00000000000000000000000000000000000000000000000000000000000000000000'),(68,'00000000000000000000000000000000000000000000000000000000000000000000'),(69,'01000020000000005a000050030000408602000044011800403808c0200c14400800'),(70,'01000422000000005a000050030000408602000044011800403808c0300c14400800'),(71,'01000422000000005a000070030004408602000044011800483808c0300c14400800'),(72,'01000100481000004800101088201242100050004401120000380040381c0c401200'),(73,'010001004810000048001030882016421000500044011200083c0040381c0c401a00'),(74,'00004410002401184824090110400008000032000001100e094880cc808400000000'),(75,'00004610002401184824490150480018000032000001100e094880cc808400000000'),(76,'00004610002401184824492150480418000032000001100f094880cc808400000000'),(77,'00000000000000000000000000000000000000000000000000000000000000000000'),(78,'00000000000000000000000000000000000000000000000000000000000000000000'),(79,'0011059008240010680401420010120618001000004f1300800a04d09804c1001e04'),(80,'00114790082480106804496b0010560e1800d200006f1300820a04d09804c1001e04'),(81,'00000000430000e049000400141800180880000000011a00010800c1902403802000'),(82,'00000000430000e049000400141804180880000000011a00010800c1902403802000'),(83,'2a241401100000004801a000001400200100000004017020000812c23018000a0001'),(84,'0e201400000001004c02000000100040a000200000011200000800c0f01c00080000'),(85,'0e201400000001024c02202000100440a000200040011200080800c4f01d10080000'),(86,'001005000c0401024a00180080109203000040000001120000880440880c00091e00'),(87,'401005000c0401024e00182080109643100040000201120000880440880c00091e00'),(88,'01000400402480004824091088304004000032080401120c893800c080ad06400004'),(89,'01004400402c800048244931883044c4800032080401120c893840c090ad0e400004'),(90,'0010010008000000480000000010920b100010000001120200082440980408001600'),(91,'0010050008000002480000200010960b180010000401120208882440980408001e00'),(92,'01000000401c0000582000128820400600008009240d1200883e40c000adc6404000'),(93,'01000000401c00005a2048128820400600008289240d1200883f40c000adce404000'),(94,'01004400401c80005a2048338820444600008289242d1200883f40c000adcf404000'),(95,'00000000000000000000000000000000000000000000000000000000000000000000'),(96,'00004480001481016e20484b8010404468008201006f1b00800a00d0908dd5000004'),(97,'00204680401481016e20486b8030444468008201006f1b00880a00d0908dd5000004'),(98,'8805c50000a00000480108002000100a100010000001162c020802402c0800001002'),(99,'8805c50100a00000480108202040160a100010000001162c020802442c0800001002'),(100,'08000000030001e04900000210100000088000000001120000080040902d03802000'),(101,'08000000030401e04900002210100400088000000001120008080040922d03802000'),(102,'000000200004000058000050031000040a000000002f1900401a08d0200c40080004'),(103,'000004b00004011078000078071004042a020000006f1900401a08d4a00cc0080004'),(104,'0004451100200018482589000000103a201800000001302c210882c4308800080000'),(105,'00044511002000184825c9200000143a201800020001302c210882cc309800080000'),(106,'00284418300001104c00482000100040e00022000401920c080800ccb01d001c0000'),(107,'08284418300081104e20482100104040600022000401920c080800c8b09d101c0000'),(108,'00000000000000000000000000000000000000000000000000000000000000000000'),(109,'01000400000c000048040100980000000000000800031200883840c0802d0e404000'),(110,'01000400000c000048040120980404000000000800031200883840c0802d0e404000'),(111,'000007100026211a4c0c010000483002000030000401920f19c880cca26c02080000'),(112,'001067100026211a4c2c4921005a760a000031020401920f19c980ccaaec02080000'),(113,'000045900c5081504c24496004105c02080002000009120c810a8cd490ac13002204'),(114,'00000000000000000000000000000000000000000000000000000000000000000000'),(115,'00564510002280104824c92020105622201800020001b26c81090ac008a802081001'),(116,'08000100080030004800140000001202100040020001120004080040180400001e00'),(117,'0800010008003000480014200000160210004002000112000c080440180400001e00'),(118,'08040d00008000024800000020001202002050000401122002880240381000001400'),(119,'08040d00008000024800002020001602002050000401122002880240381000001400'),(120,'000081008090000048000400300012020800000080091a2002080240182023001400'),(121,'881081008090000048000460300016020800000080891b20020a02401820e3009400'),(122,'00000000000000000000000000000000000000000000000000000000000000000000'),(123,'3e2040061000000448010020001004008800000040019200080c00e0f00c10120002'),(124,'8014458004008001da00486820105c030819822000c91b20800a02500009c0088004'),(125,'00004408030001e0492048210010444068800200000912000008004092ad13882000'),(126,'010044404004010048e44b21001604406000020404091001180800c0808f00084000'),(127,'00044419102000104801c82000500408000000000001d22c000882c8241800000002'),(128,'00000510102401104c04012000501492000000020001920c898808cc883c12002004'),(129,'00000000000000000000000000000000000000000000000000000000000000000000'),(130,'00100510080a75104c0401200090369200004002000112010f0840c8882703001600'),(131,'401007104c4435124800002080101e131000400200291a0000880440882402001e04'),(132,'00000000000000000000000000000000000000000000000000000000000000000000'),(133,'4020048004240100c8000000001008000000200000011201800800d0900410000800'),(134,'402005800c240100c800102080101e021000600000011201820800d0980410001e00'),(135,'48200480052401e0c901002000100c000880200000011201800800d0906413802800'),(136,'402004c004240100cc4c032000140c000000200400011201980800d0900610004800'),(137,'0800010003000120490000220400140200000000000b1300800808c0902cc3000004'),(138,'0004850000800008480000003000120a000050000001122e0308a240080808001400'),(139,'0004850000820008480000203000160a100050000101122e0308a248080808001400'),(140,'0004850000200008480000102000120a140010000001122e23088248080800001400'),(141,'0004c50000a10008480000302000160a340810000081162e230882482c0800001402'),(142,'0806001100023818480c212000842430000000200011122e090882ca104900000000'),(143,'000147100c2601104a244921485a5c12000022020001120cc14808c48aa412082004'),(144,'3c1011000000010448022020809094030800000000011a01010804c0d00400030a00'),(145,'1e201000010000e448002020009404000880000000011200010800c0d22403822800'),(146,'3e0010400000010448c42320009404000000000400011201110808c0d00600024800'),(147,'080025000800760048440120801016120800000200011200040800c0982403000600'),(148,'080025000800760048440120801016120800000200011200040800c0982403000e00'),(149,'3c00671008007e104a6469218094d612280002020001120d0d0804ccd8a403000e00'),(150,'08194598480c81987824496b04b054c668008201846f9b0c890a48dc90a5d3004804'),(151,'7fb977fe7f7effffffff7fffdffeffdffec2ffcffe7f9b8fdffffdfdfbffdfdf7f06')) as c (sid, hex)
cross join lateral generate_series(0, 266) as i
join (select s.slug, s.ord - 1 as ix from unnest(string_to_array('acid-spray,acrobatics,aerial-ace,agility,air-cutter,air-slash,alluring-voice,ally-switch,amnesia,assurance,attract,aura-sphere,avalanche,baton-pass,beat-up,blast-burn,blizzard,body-press,body-slam,bounce,brave-bird,breaking-swipe,brick-break,brine,brutal-swing,bug-bite,bug-buzz,bulk-up,bulldoze,bullet-seed,burning-jealousy,calm-mind,charge,charge-beam,charm,chilling-water,close-combat,coaching,confuse-ray,cosmic-power,cross-poison,crunch,curse,dark-pulse,dazzling-gleam,dig,disarming-voice,dive,double-edge,draco-meteor,dragon-cheer,dragon-claw,dragon-dance,dragon-pulse,dragon-tail,drain-punch,draining-kiss,drill-run,dual-wingbeat,earth-power,earthquake,eerie-impulse,electric-terrain,electro-ball,electroweb,encore,endeavor,endure,energy-ball,expanding-force,facade,fake-tears,false-swipe,feather-dance,fire-blast,fire-fang,fire-pledge,fire-punch,fire-spin,flame-charge,flamethrower,flare-blitz,flash-cannon,fling,flip-turn,fly,focus-blast,focus-energy,focus-punch,foul-play,frenzy-plant,future-sight,giga-drain,giga-impact,grass-knot,grass-pledge,grassy-glide,grassy-terrain,gravity,gunk-shot,gyro-ball,hail,hard-press,haze,headbutt,heat-crash,heat-wave,heavy-slam,helping-hand,hex,high-horsepower,hurricane,hydro-cannon,hydro-pump,hyper-beam,hyper-voice,ice-beam,ice-fang,ice-punch,ice-spinner,icicle-spear,icy-wind,imprison,iron-defense,iron-head,iron-tail,knock-off,lash-out,leaf-blade,leaf-storm,leech-life,light-screen,liquidation,low-kick,low-sweep,lunge,magic-room,magical-leaf,mega-drain,mega-kick,mega-punch,megahorn,metal-claw,metal-sound,meteor-beam,metronome,misty-explosion,misty-terrain,mud-shot,mud-slap,muddy-water,nasty-plot,night-shade,outrage,overheat,pain-split,pay-day,payback,petal-blizzard,phantom-force,pin-missile,play-rough,poison-jab,poison-tail,pollen-puff,poltergeist,pounce,power-gem,protect,psybeam,psych-up,psychic,psychic-fangs,psychic-noise,psychic-terrain,psycho-cut,psyshock,rain-dance,razor-shell,reflect,rest,retaliate,revenge,reversal,roar,rock-blast,rock-slide,rock-tomb,roost,round,safeguard,sand-tomb,sandstorm,scald,scale-shot,scary-face,scorching-sands,screech,seed-bomb,shadow-ball,shadow-claw,skill-swap,skitter-smack,sleep-talk,sludge-bomb,sludge-wave,smack-down,smart-strike,snarl,snore,snowscape,solar-beam,solar-blade,spikes,spite,stealth-rock,steel-beam,steel-wing,stomping-tantrum,stone-edge,stored-power,struggle-bug,substitute,sunny-day,super-fang,supercell-slam,superpower,surf,swift,swords-dance,tailwind,take-down,taunt,temper-flare,tera-blast,thief,throat-chop,thunder,thunder-fang,thunder-punch,thunder-wave,thunderbolt,toxic,toxic-spikes,trailblaze,tri-attack,trick,trick-room,triple-axel,u-turn,upper-hand,uproar,vacuum-wave,venom-drench,venoshock,volt-switch,water-pledge,water-pulse,waterfall,weather-ball,whirlpool,wild-charge,will-o-wisp,wonder-room,work-up,x-scissor,zen-headbutt', ',')) with ordinality as s (slug, ord)) sl on sl.ix = i
join public.golpes g on g.slug = sl.slug
join public.especies e on e.id = c.sid
where get_bit(decode(c.hex, 'hex'), i) = 1
on conflict do nothing;

create or replace function public._dar_mt(p_jogador uuid, p_num int) returns boolean language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from public.mt_catalogo where num = p_num) then raise exception 'MT inexistente.'; end if;
  insert into public.mt_jogador (jogador, num) values (p_jogador, p_num) on conflict do nothing;
  return found;
end $$;
revoke all on function public._dar_mt(uuid, int) from public, anon, authenticated;

create or replace function public.mt_lista() returns jsonb language plpgsql security definer set search_path = public as $$
declare ar int;
begin
  if auth.uid() is null then return '[]'::jsonb; end if;
  select coalesce((select (valor #>> '{}')::int from public.config where chave = 'arco_atual'), 1) into ar;
  return coalesce((select jsonb_agg(jsonb_build_object('num', c.num, 'golpe_id', c.golpe_id, 'arco', c.arco, 'preco', c.preco,
           'liberada', c.arco <= ar, 'tenho', exists (select 1 from public.mt_jogador m where m.jogador = auth.uid() and m.num = c.num)) order by c.num)
         from public.mt_catalogo c where c.ativa), '[]'::jsonb);
end $$;
revoke all on function public.mt_lista() from public, anon;
grant execute on function public.mt_lista() to authenticated;

create or replace function public.mt_comprar(p_poi text, p_num int) returns jsonb language plpgsql security definer set search_path = public as $$
declare v_j public.jogadores; v_p jsonb; c public.mt_catalogo; ar int;
begin
  if auth.uid() is null then raise exception 'Faça login primeiro.'; end if;
  select * into v_j from public.jogadores where id = auth.uid() for update;
  if not found then raise exception 'Crie seu personagem primeiro.'; end if;
  v_p := public._poi_do_jogador(v_j, p_poi);
  if v_p is null or v_p->>'acao' <> 'loja' or v_p->>'tipo' <> 'loja' then raise exception 'As MTs só são vendidas nas lojas grandes.'; end if;
  select * into c from public.mt_catalogo where num = p_num and ativa;
  if not found then raise exception 'Esta MT não existe.'; end if;
  select coalesce((select (valor #>> '{}')::int from public.config where chave = 'arco_atual'), 1) into ar;
  if c.arco > ar then raise exception 'Esta MT ainda não chegou à loja.'; end if;
  if exists (select 1 from public.mt_jogador where jogador = v_j.id and num = p_num) then raise exception 'Você já possui esta MT.'; end if;
  if v_j.dinheiro < c.preco then raise exception 'Dinheiro insuficiente (precisa de %).', c.preco; end if;
  update public.jogadores set dinheiro = dinheiro - c.preco where id = v_j.id;
  perform public._dar_mt(v_j.id, p_num);
  return jsonb_build_object('num', p_num, 'preco', c.preco, 'dinheiro', v_j.dinheiro - c.preco);
end $$;
revoke all on function public.mt_comprar(text, int) from public, anon;
grant execute on function public.mt_comprar(text, int) to authenticated;

create or replace function public.mt_ensinar(p_pokemon uuid, p_num int, p_slot int default null) returns jsonb language plpgsql security definer set search_path = public as $$
declare pk public.pokemons; c public.mt_catalogo; g public.golpes; novos jsonb; esq text;
begin
  if auth.uid() is null then raise exception 'Faça login primeiro.'; end if;
  if exists (select 1 from public.batalhas where jogador = auth.uid() and estado = 'ativa') then raise exception 'Não é possível ensinar durante a batalha.'; end if;
  select * into pk from public.pokemons where id = p_pokemon and dono = auth.uid() for update;
  if not found then raise exception 'Pokémon não encontrado.'; end if;
  select * into c from public.mt_catalogo where num = p_num and ativa;
  if not found or not exists (select 1 from public.mt_jogador where jogador = auth.uid() and num = p_num) then raise exception 'Você não possui esta MT.'; end if;
  select * into g from public.golpes where id = c.golpe_id;
  if not exists (select 1 from public.mt_compat where especie_id = pk.especie_id and golpe_id = c.golpe_id) then raise exception 'Este Pokémon não aprende %.', g.nome; end if;
  if exists (select 1 from jsonb_array_elements(pk.golpes) x where (x->>'id')::int = g.id) then raise exception 'Este Pokémon já conhece %.', g.nome; end if;
  if jsonb_array_length(pk.golpes) < 4 then
    novos := pk.golpes || jsonb_build_array(jsonb_build_object('id', g.id, 'pp', g.pp));
  else
    if p_slot is null or p_slot < 0 or p_slot > 3 then raise exception 'Escolha qual golpe esquecer.'; end if;
    select gg.nome into esq from public.golpes gg where gg.id = (pk.golpes->p_slot->>'id')::int;
    novos := (select jsonb_agg(case when t.ord - 1 = p_slot then jsonb_build_object('id', g.id, 'pp', g.pp) else t.x end order by t.ord) from jsonb_array_elements(pk.golpes) with ordinality t (x, ord));
  end if;
  update public.pokemons set golpes = novos where id = pk.id;
  return jsonb_build_object('golpe', g.nome, 'esqueceu', esq);
end $$;
revoke all on function public.mt_ensinar(uuid, int, int) from public, anon;
grant execute on function public.mt_ensinar(uuid, int, int) to authenticated;

create or replace function public.mestre_dar_mt(p_jogador uuid, p_num int) returns boolean language plpgsql security definer set search_path = public as $$
begin
  if not public.eh_mestre() then raise exception 'Só o Mestre pode dar MTs.'; end if;
  return public._dar_mt(p_jogador, p_num);
end $$;
revoke all on function public.mestre_dar_mt(uuid, int) from public, anon;
grant execute on function public.mestre_dar_mt(uuid, int) to authenticated;
