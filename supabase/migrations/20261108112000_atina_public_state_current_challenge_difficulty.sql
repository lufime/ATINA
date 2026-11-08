-- Report the actual level of the current card in random-difficulty sessions.
create or replace function private.atina_v2_local_public_state(
  p_session private.atina_v2_local_sessions
)
returns jsonb language sql stable security definer set search_path = ''
as $$
  select jsonb_build_object(
    'session_id', p_session.id,
    'mode', p_session.game_mode,
    'difficulty', coalesce((
      select c.difficulty from private.atina_challenges c
       where c.challenge_id = p_session.challenge_queue[p_session.position] and c.active
    ), p_session.difficulty),
    'category_filter', p_session.category,
    'scores', to_jsonb(p_session.scores),
    'streaks', to_jsonb(p_session.streaks),
    'current_player', p_session.current_player,
    'position', p_session.position,
    'queue_size', cardinality(p_session.challenge_queue),
    'answered_count', p_session.answered_count,
    'round_locked', p_session.round_locked,
    'status', p_session.status,
    'deadline_at', p_session.deadline_at,
    'special_card', p_session.special_card,
    'last_result', p_session.last_result,
    'challenge', (
      select jsonb_build_object(
        'id', c.challenge_id, 'category', c.category, 'emoji', c.emoji,
        'image_url', c.image_url, 'total_clues', jsonb_array_length(c.clues),
        'clues', (select coalesce(jsonb_agg(cl.value order by cl.ordinality), '[]'::jsonb)
                    from jsonb_array_elements(c.clues) with ordinality cl(value, ordinality)
                   where cl.ordinality <= p_session.revealed_clues),
        'answer', case when p_session.round_locked then c.answer else null end,
        'solution_image_url', case when p_session.round_locked then c.solution_image_url else null end
      ) from private.atina_challenges c
       where c.challenge_id = p_session.challenge_queue[p_session.position] and c.active
    )
  );
$$;