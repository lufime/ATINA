-- Diversify bot nicknames and keep the visible simulated presence modest.
update private.atina_v2_bot_profiles set nickname='atina_tmp_'||id::text;
update private.atina_v2_bot_profiles as p
set nickname=v.nickname
from (values
(1,'Lua_27'),(2,'RuiDoNorte'),(3,'MartaK'),(4,'Tigas.pt'),(5,'Ines_azul'),
(6,'DidiR'),(7,'LeoCosta'),(8,'Mika'),(9,'Bea.lx'),(10,'Tommy'),
(11,'Carol_8'),(12,'AfonsoM'),(13,'Maty'),(14,'GoncaloZ'),(15,'SofiR'),
(16,'AndreV'),(17,'Mari_sol'),(18,'Pedrinho'),(19,'JoM'),(20,'Duarte.pt'),
(21,'Clara_21'),(22,'ChicoB'),(23,'EvaL'),(24,'GabiM'),(25,'AliR'),
(26,'Rodri'),(27,'Laura_7'),(28,'DaniC'),(29,'IrisM'),(30,'NunoLX'),
(31,'Catita'),(32,'VascoR'),(33,'AnaLua'),(34,'Bruno_13'),(35,'Ritinha'),
(36,'DavidP'),(37,'Sarita'),(38,'HugoM'),(39,'Fifi_'),(40,'GuiZ'),
(41,'Mada'),(42,'Fabz'),(43,'Teca'),(44,'SamR'),(45,'Babi'),
(46,'LuisDoMar'),(47,'DidiL'),(48,'Martim_'),(49,'LenaC'),(50,'RafaZ'),
(51,'MareAlta'),(52,'CafeComLeite'),(53,'Pipas.pt'),(54,'Riscas_'),(55,'Solta'),
(56,'NorteSul'),(57,'PoeiraBoa'),(58,'TostaMista'),(59,'Cereja_'),(60,'VentoL'),
(61,'Rota7'),(62,'PontoG'),(63,'MangaVerde'),(64,'Pardal.pt'),(65,'BolaAzul'),
(66,'CantoLivre'),(67,'Faisca'),(68,'Moinho'),(69,'Riacho_'),(70,'LimaoDoce'),
(71,'EstrelaM'),(72,'Trilho.pt'),(73,'MeiaLua'),(74,'Brisa_'),(75,'PeDeVento'),
(76,'CaisSul'),(77,'Papelote'),(78,'GinjaM'),(79,'Farol_'),(80,'PardalX'),
(81,'RosaVentos'),(82,'PonteNova'),(83,'PaoQuente'),(84,'Ritmo_9'),(85,'TintaAzul'),
(86,'PicoAlto'),(87,'Nuvem_'),(88,'Maresia'),(89,'Pirilampo'),(90,'ChuvaMiuda'),
(91,'RodaLivre'),(92,'PimentaM'),(93,'Pinhao.pt'),(94,'CaminhoCerto'),(95,'Lagoa'),
(96,'Ribeiro_'),(97,'FioPrumo'),(98,'SombraBoa'),(99,'MeioCopo'),(100,'PassoLeve')
) as v(id,nickname)
where p.id=v.id;
update public.atina_v2_room_players p
set nickname=b.nickname
from private.atina_v2_bot_matches m
join private.atina_v2_bot_profiles b on b.id=m.bot_profile_id
join public.atina_v2_rooms r on r.id=m.room_id
where p.id=m.bot_player_id and p.room_id=m.room_id and r.status in ('waiting','playing');
create or replace function public.atina_v2_online_players()
returns jsonb language sql stable security definer set search_path to ''
as $function$
  with bot_presence as (
    select b.nickname from private.atina_v2_bot_profiles b
    where private.atina_v2_bot_is_available(b)
    order by md5(b.id::text || date_trunc('minute', current_timestamp)::text)
    limit 10
  ),
  visible_players as (
    select p.nickname from public.atina_v2_room_players p
    where not coalesce(p.is_bot,false) and p.last_seen_at > clock_timestamp()-interval '90 seconds'
    union select nickname from bot_presence
    union
    select b.nickname
    from private.atina_v2_bot_matches m
    join private.atina_v2_bot_profiles b on b.id=m.bot_profile_id
    join public.atina_v2_rooms r on r.id=m.room_id
    join public.atina_v2_room_players p on p.id=m.bot_player_id
    where r.status in ('waiting','playing') and p.last_seen_at > clock_timestamp()-interval '90 seconds'
  )
  select coalesce(jsonb_agg(jsonb_build_object('nickname',nickname,'online',true) order by nickname),'[]'::jsonb)
  from (select distinct nickname from visible_players where nickname is not null and btrim(nickname)<>'') v;
$function$;
