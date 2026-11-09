-- Stop persisting individual answer records. Ranking progress remains in atina_xp_events
-- and private.atina_players.total_xp, with one award per player/session/challenge.
create or replace function private.atina_ignore_answer_history_insert()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
  return null;
end;
$function$;

drop trigger if exists atina_no_answer_history_insert
  on private.atina_v2_local_answer_history;

create trigger atina_no_answer_history_insert
before insert on private.atina_v2_local_answer_history
for each row execute function private.atina_ignore_answer_history_insert();
