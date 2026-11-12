-- The two-argument overload is the intentional guest/single-player room creator.
-- Keep access scoped to Supabase client roles; the function validates inputs and
-- runs SECURITY DEFINER with an empty search_path.
GRANT EXECUTE ON FUNCTION public.atina_v2_create_room(text, integer) TO anon, authenticated;
