-- Reject offensive player nicknames for every registration path.
-- The check runs in PostgreSQL so clients cannot bypass it.

create or replace function private.atina_nickname_is_allowed(p_nickname text)
returns boolean
language plpgsql
immutable
security definer
set search_path = ''
as $function$
declare
  v_folded text;
  v_compact text;
  v_letters text;
  v_words text[];
  v_blocked text[] := array[
    'puta','puto','putaria','putinha','putinhas',
    'caralho','caralhos','foda','foder','fodido','fodida','foda-se',
    'merda','merdas','porra','cona','cabrao','cabrão',
    'paneleiro','paneleira','boiola','bicha','arrombado','otario','otaria',
    'estupido','estupida','idiota','palhaco','palhaca',
    'fuck','fucking','shit','bullshit','bitch','asshole','bastard','dick',
    'dickhead','cunt','motherfucker','whore','slut','fag','faggot',
    'retard','nigger','nigga','kike','chink','spic','wetback',
    'filhodaputa','va tomar no cu','vaisetefoder','sonofabitch'
  ];
begin
  if p_nickname is null then
    return false;
  end if;

  v_folded := lower(translate(
    btrim(p_nickname),
    'áàâãäéèêëíìîïóòôõöúùûüçñ',
    'aaaaaeeeeiiiiooooouuuucn'
  ));
  -- Common number substitutions are normalized before checking.
  v_folded := translate(v_folded, '0134578269', 'oieastbzgg');
  v_words := regexp_split_to_array(v_folded, '[^a-z]+');
  v_compact := regexp_replace(v_folded, '[^a-z0-9]', '', 'g');
  v_letters := regexp_replace(v_folded, '[^a-z]', '', 'g');

  if v_words && v_blocked then
    return false;
  end if;

  if v_compact = any(v_blocked)
     or v_letters = any(v_blocked) then
    return false;
  end if;

  -- Explicitly reject common multi-word abusive phrases.
  if array_to_string(v_words, ' ') like '%filho da puta%'
     or array_to_string(v_words, ' ') like '%vai tomar no cu%'
     or array_to_string(v_words, ' ') like '%vai se foder%'
     or array_to_string(v_words, ' ') like '%son of a bitch%' then
    return false;
  end if;

  return true;
end;
$function$;

revoke all on function private.atina_nickname_is_allowed(text) from public, anon, authenticated;

create or replace function private.atina_reject_offensive_nickname()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if not private.atina_nickname_is_allowed(new.nickname) then
    raise exception 'Este pseudónimo não é permitido. Escolhe um nome respeitador e adequado a todos os públicos.'
      using errcode = '22023';
  end if;
  return new;
end;
$function$;

revoke all on function private.atina_reject_offensive_nickname() from public, anon, authenticated;

drop trigger if exists atina_players_nickname_policy on private.atina_players;
create trigger atina_players_nickname_policy
before insert or update of nickname on private.atina_players
for each row execute function private.atina_reject_offensive_nickname();

drop trigger if exists atina_player_accounts_nickname_policy on private.atina_player_accounts;
create trigger atina_player_accounts_nickname_policy
before insert or update of nickname on private.atina_player_accounts
for each row execute function private.atina_reject_offensive_nickname();

comment on function private.atina_nickname_is_allowed(text) is
  'Valida pseudónimos contra linguagem ofensiva, incluindo variantes acentuadas e substituições comuns por números.';
