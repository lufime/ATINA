-- Local-device Mímicas: return one card at a time so the client does not download
-- the complete private answer deck. The caller supplies IDs already used in this
-- local game; the browser never reads the private table directly.
CREATE OR REPLACE FUNCTION public.atina_v2_local_mime_card(
  p_excluded_ids integer[] DEFAULT ARRAY[]::integer[]
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_card private.atina_mime_cards%rowtype;
BEGIN
  SELECT * INTO v_card
  FROM private.atina_mime_cards c
  WHERE NOT (c.id = ANY(coalesce(p_excluded_ids, ARRAY[]::integer[])))
  ORDER BY random()
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  RETURN jsonb_build_object(
    'id', v_card.id,
    'word', v_card.word,
    'category', v_card.category,
    'clues', v_card.clues
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.atina_v2_local_mime_card(integer[]) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.atina_v2_local_mime_card(integer[]) TO anon, authenticated;

COMMENT ON FUNCTION public.atina_v2_local_mime_card(integer[]) IS
  'Returns one unused private Mímicas card for local pass-the-device play; never exposes direct table access.';
