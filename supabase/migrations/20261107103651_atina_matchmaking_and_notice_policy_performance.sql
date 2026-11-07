-- Performance fixes verified on the production project.
-- One composite index covers both foreign keys (room_id) and (room_id, player_id).
create index if not exists atina_v2_matchmaking_queue_room_player_idx
  on private.atina_v2_matchmaking_queue (room_id, player_id);

-- Keep the administrator check stable for each statement instead of evaluating
-- auth.jwt() once per affected row.
drop policy if exists atina_notice_admin_insert on public.atina_site_notice;
create policy atina_notice_admin_insert
  on public.atina_site_notice
  for insert
  with check ((select auth.jwt()) ->> 'email' = 'lufime@gmail.com');

drop policy if exists atina_notice_admin_update on public.atina_site_notice;
create policy atina_notice_admin_update
  on public.atina_site_notice
  for update
  using ((select auth.jwt()) ->> 'email' = 'lufime@gmail.com')
  with check ((select auth.jwt()) ->> 'email' = 'lufime@gmail.com');
