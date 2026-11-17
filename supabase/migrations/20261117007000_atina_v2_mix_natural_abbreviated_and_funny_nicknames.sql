-- Mix full names, abbreviations, nicknames, handles and light humorous names.
update private.atina_v2_bot_profiles set nickname = 'atina_tmp_' || id::text;

with new_names(id, nickname) as (
  values
  (1,'Rui M.'),(2,'Ana C.'),(3,'Jota'),(4,'Kikas'),(5,'Mimi'),
  (6,'Zé Carlos'),(7,'Tó Miguel'),(8,'Lipe'),(9,'Bia'),(10,'Nando'),
  (11,'ines.a correr'),(12,'Martim_23'),(13,'Duarte LOL'),(14,'Catarina.pt'),(15,'Tigas'),
  (16,'Lara_lx'),(17,'Gui das pistas'),(18,'Rafa_77'),(19,'Pipoca'),(20,'Capitão Óbvio'),
  (21,'Joãozinho'),(22,'Madalena R.'),(23,'Tita'),(24,'Pedro.sem.pistas'),(25,'Nocas'),
  (26,'Miguel Costa'),(27,'Sofia_404'),(28,'Bubu'),(29,'Chico esperto'),(30,'Rita M.'),
  (31,'Leo a pensar'),(32,'Didi'),(33,'Vasco_03'),(34,'Marta.lx'),(35,'Tó Zé'),
  (36,'Bolas de Berlim'),(37,'Afonso F.'),(38,'Lelé'),(39,'Dani_21'),(40,'Zuca'),
  (41,'Tomás Silva'),(42,'Cris das pistas'),(43,'Pé Leve'),(44,'Mafalda C.'),(45,'Ricky'),
  (46,'Sónia_reis'),(47,'Gonçalo R.'),(48,'Pintas'),(49,'Nina_16'),(50,'Tété'),
  (51,'Bruno do Norte'),(52,'Micas'),(53,'Eva M.'),(54,'Zé da Esquina'),(55,'Rafaela.pt'),
  (56,'Tiago_91'),(57,'Lulu'),(58,'Dinis Rocha'),(59,'Mestre dos palpites'),(60,'Xana'),
  (61,'Noa Costa'),(62,'Puto_curioso'),(63,'Mário L.'),(64,'Kiko'),(65,'Leonor_7'),
  (66,'Fifi'),(67,'Santiago_5'),(68,'Tânia Lopes'),(69,'Panda'),(70,'Alex Duarte'),
  (71,'Emma Müller'),(72,'Lucas García'),(73,'Sofia Rossi'),(74,'Alex Johnson'),(75,'Camille Dubois'),
  (76,'Ivan Petrov'),(77,'Aiko Tanaka'),(78,'Omar Hassan'),(79,'Mia Novak'),(80,'Diego Fernández'),
  (81,'Rui das ideias'),(82,'Bárbara B.'),(83,'Zé_Povinho'),(84,'Tico'),(85,'Lara Mendes'),
  (86,'Nuno_27'),(87,'Pipinhas'),(88,'Duda'),(89,'Francisco M.'),(90,'Caju'),
  (91,'Marta_88'),(92,'Tóni'),(93,'Sérgio Lopes'),(94,'Rita_23'),(95,'Chalupa'),
  (96,'Matilde R.'),(97,'Guga'),(98,'Vítor Reis'),(99,'Pisco'),(100,'Didi_404')
)
update private.atina_v2_bot_profiles b
set nickname = n.nickname
from new_names n
where b.id = n.id;

update public.atina_v2_room_players rp
   set nickname = b.nickname
  from private.atina_v2_bot_matches m
  join private.atina_v2_bot_profiles b on b.id=m.bot_profile_id
 where rp.id=m.bot_player_id
   and rp.is_bot is true
   and rp.nickname is distinct from b.nickname;
