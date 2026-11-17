-- Give bot profiles a broader mix of natural names and handle styles.
update private.atina_v2_bot_profiles set nickname = 'atina_tmp_' || id::text;

with first_names as (
  select array[
    'Inês','Martim','Leonor','Tomás','Beatriz','Afonso','Madalena','Guilherme','Matilde','Duarte',
    'Lara','Rodrigo','Catarina','Tiago','Mariana','Rafael','Eva','Miguel','Sofia','Diogo'
  ]::text[] as a
), surnames as (
  select array['Almeida','Carvalho','Mendes','Ferreira','Costa']::text[] as a
), numbered as (
  select id, row_number() over(order by id) as rn
  from private.atina_v2_bot_profiles
), names as (
  select n.id, f.a[((n.rn-1)/5)::integer+1] as first_name,
         s.a[((n.rn-1)%5)::integer+1] as last_name, n.rn
  from numbered n cross join first_names f cross join surnames s
), generated as (
  select id,
    case mod(rn,5)
      when 0 then first_name || ' ' || last_name
      when 1 then lower(first_name) || '.' || lower(last_name)
      when 2 then first_name || '_' || lpad((17 + rn*3)::text,2,'0')
      when 3 then first_name || ' ' || left(last_name,1) || '.'
      else first_name || ' ' || last_name || ' ' || (2000 + rn)::text
    end as nickname
  from names
)
update private.atina_v2_bot_profiles b set nickname=g.nickname
from generated g where b.id=g.id;

update public.atina_v2_room_players rp
   set nickname = b.nickname
  from private.atina_v2_bot_matches m
  join private.atina_v2_bot_profiles b on b.id=m.bot_profile_id
 where rp.id=m.bot_player_id and rp.is_bot is true
   and rp.nickname is distinct from b.nickname;
