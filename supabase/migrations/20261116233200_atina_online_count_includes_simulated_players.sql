create or replace function public.atina_online_player_count()
returns integer
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_site_presence_count integer := 0;
begin
  -- A tabela de presença pode não existir em instalações limpas/legadas.
  -- Mantém a contagem de bots funcional e inclui presenças reais quando
  -- a tabela opcional está disponível.
  if to_regclass('private.atina_site_presence') is not null then
    execute
      'select count(*)::integer
         from private.atina_site_presence
        where last_seen_at >= clock_timestamp() - interval ''60 seconds'''
      into v_site_presence_count;
  end if;

  return v_site_presence_count
    + least(10, (
        select count(*)::integer
          from private.atina_v2_bot_profiles b
         where b.active
           and private.atina_v2_bot_is_available(b)
      ));
end;
$function$;
