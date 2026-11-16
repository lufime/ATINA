create or replace function private.atina_v2_award_bot_competition_progress()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_profile_id integer;
  v_inserted integer;
begin
  if new.is_correct is distinct from true then
    return new;
  end if;

  select m.bot_profile_id
    into v_profile_id
    from private.atina_v2_bot_matches m
    join public.atina_v2_room_players rp
      on rp.id=m.bot_player_id and rp.room_id=m.room_id
   where m.room_id=new.room_id
     and m.bot_player_id=new.player_id;

  if v_profile_id is null then
    return new;
  end if;

  insert into private.atina_v2_bot_competition_events
    (bot_profile_id,source,source_id,challenge_position,points,xp,is_correct)
  values
    (v_profile_id,'room',new.room_id,new.challenge_index+1,
     greatest(coalesce(new.points,0),0),10,true)
  on conflict (bot_profile_id,source,source_id,challenge_position) do nothing;

  get diagnostics v_inserted = row_count;
  if v_inserted=1 then
    update private.atina_v2_bot_competition_stats
       set points=points+greatest(coalesce(new.points,0),0),
           xp=xp+10,
           total_challenges=total_challenges+1,
           updated_at=clock_timestamp()
     where bot_profile_id=v_profile_id;
  end if;

  return new;
end;
$function$;

revoke all on function private.atina_v2_award_bot_competition_progress() from public, anon, authenticated;

drop trigger if exists atina_v2_award_bot_competition_progress_after_answer
  on public.atina_v2_room_answers;

create trigger atina_v2_award_bot_competition_progress_after_answer
after insert on public.atina_v2_room_answers
for each row
when (new.is_correct is true)
execute function private.atina_v2_award_bot_competition_progress();
