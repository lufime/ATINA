-- Extend the existing server-side nickname filter without replacing registration RPCs
-- or recreating the nickname triggers. This migration only updates the existing
-- private.atina_nickname_is_allowed(text) function.

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
  v_normalized_phrase text;
  v_blocked text[] := array[
    -- Portuguese
    'puta','puto','putaria','putinha','putinhas','caralho','caralhos',
    'foda','foder','fodido','fodida','fodase','fodas','fodes',
    'merda','merdas','bosta','porra','cona','cabrao','paneleiro',
    'paneleira','boiola','bicha','arrombado','otario','otaria',
    'estupido','estupida','idiota','palhaco','palhaca','vagabundo',
    'vagabunda','buceta','desgraca','corno','fdp','pqp','vsf','vtc',
    'crl','krl',
    -- English
    'fuck','fucking','motherfucker','motherfucking','shit','bullshit',
    'bitch','asshole','bastard','dick','dickhead','cunt','whore',
    'slut','fag','faggot','retard','nigger','nigga','kike','chink',
    'spic','wetback','dumbass','jackass',
    -- French (accent-folded)
    'putain','connard','connasse','salope','encule','enculer',
    'enculee','encules','pute','bordel','merdeux','merdeuse',
    'batard','batarde','couille','couilles','conne','nique','niquer',
    'foutre',
    -- German (umlaut-folded)
    'scheisse','scheiss','fick','ficken','gefickt','hurensohn',
    'hurentochter','fotze','wichser','wichsen','schlampe','schwanz',
    'hure','miststueck',
    -- Common multi-word forms after whitespace/punctuation folding
    'filhodaputa','filhodocaralho','vaitomarnocu','vaitomarocu',
    'vaisefoder','vaimerda','putaquepariu','sonofabitch',
    'pieceofshit','gofyourself','filsdepute','vatefairefoutre',
    'niquetamere','trouduc','sohneinerhure','fickdich'
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
  v_folded := replace(v_folded, 'ß', 'ss');

  -- Normalize frequent leetspeak substitutions before matching.
  v_folded := translate(v_folded, '0134578269', 'oieastbzgg');
  v_words := regexp_split_to_array(v_folded, '[^a-z]+');
  v_compact := regexp_replace(v_folded, '[^a-z0-9]', '', 'g');
  v_letters := regexp_replace(v_folded, '[^a-z]', '', 'g');
  v_normalized_phrase := btrim(regexp_replace(
    regexp_replace(v_folded, '[^a-z0-9]+', ' ', 'g'),
    '[[:space:]]+', ' ', 'g'
  ));

  if v_words && v_blocked then
    return false;
  end if;

  if v_compact = any(v_blocked)
     or v_letters = any(v_blocked) then
    return false;
  end if;

  -- Phrase matching is boundary-aware to avoid rejecting ordinary names
  -- merely because they contain a short character sequence.
  if v_normalized_phrase ~ '(^| )(filho da puta|filho do caralho|puta que pariu|vai tomar no cu|vai tomar o cu|vai se foder|vai a merda|vai para o caralho|son of a bitch|piece of shit|go fuck yourself|fils de pute|va te faire foutre|nique ta mere|ta gueule|trou du cul|sohn einer hure|fick dich|leck mich am arsch)( |$)' then
    return false;
  end if;

  if v_compact = any(array[
    'filhodaputa','filhodocaralho','putaquepariu','vaitomarnocu',
    'vaitomarocu','vaisefoder','vaimerda','vaiparaocaralho',
    'sonofabitch','pieceofshit','gofuckyourself','filsdepute',
    'vatefairefoutre','niquetamere','trouduc','sohneinerhure',
    'fickdich','leckmichamarsch'
  ]) then
    return false;
  end if;

  return true;
end;
$function$;

-- Preserve the existing function's security-definer posture and ACL.
revoke all on function private.atina_nickname_is_allowed(text)
  from public, anon, authenticated;

-- Regression checks: offensive terms and obfuscated variants are rejected,
-- while legitimate names containing similar letter sequences remain allowed.
do $tests$
begin
  if private.atina_nickname_is_allowed('Caralho')
     or private.atina_nickname_is_allowed('c@r@lh0')
     or private.atina_nickname_is_allowed('P0rr4')
     or private.atina_nickname_is_allowed('p.u.t.a')
     or private.atina_nickname_is_allowed('Puta Que Pariu')
     or private.atina_nickname_is_allowed('Vai tomar no cu')
     or private.atina_nickname_is_allowed('Putain')
     or private.atina_nickname_is_allowed('Fils de pute')
     or private.atina_nickname_is_allowed('Scheiße')
     or private.atina_nickname_is_allowed('Hurensohn')
     or private.atina_nickname_is_allowed('Fick dich')
     or private.atina_nickname_is_allowed('Motherfucker') then
    raise exception 'Nickname policy regression: an offensive value was accepted.';
  end if;

  if not private.atina_nickname_is_allowed('Pikachu')
     or not private.atina_nickname_is_allowed('Ana Sousa')
     or not private.atina_nickname_is_allowed('João Silva')
     or not private.atina_nickname_is_allowed('Francisco')
     or not private.atina_nickname_is_allowed('Conrado')
     or not private.atina_nickname_is_allowed('Connor') then
    raise exception 'Nickname policy regression: a legitimate name was rejected.';
  end if;
end;
$tests$;
