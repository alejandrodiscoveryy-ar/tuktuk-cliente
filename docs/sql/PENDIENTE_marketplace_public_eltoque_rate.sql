-- TUKTUK Cliente: read-only public elTOQUE rate snapshot.
-- Pending migration ONLY. Do not execute automatically or in production without approval.
-- Authoritative location on integration: vrixora-admin-canvas/supabase/migrations/.
create or replace function public.marketplace_public_eltoque_rate()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  cfg public.project_exchange_settings%rowtype;
  last_change public.project_exchange_rate_history%rowtype;
  prior_rate numeric;
  fresh boolean;
begin
  select * into cfg
  from public.project_exchange_settings
  where project_id = 'dfb41cea-a812-46f2-b511-7a60bd3d78af'::uuid;

  if not found then
    return jsonb_build_object('available', false, 'fresh', false);
  end if;

  select * into last_change
  from public.project_exchange_rate_history
  where project_id = cfg.project_id and rate_source = 'elTOQUE'
  order by id desc
  limit 1;

  select h.rate into prior_rate
  from public.project_exchange_rate_history h
  where h.project_id = cfg.project_id
    and h.rate_source = 'elTOQUE'
    and (last_change.id is null or h.id < last_change.id)
  order by id desc
  limit 1;

  fresh := cfg.auto_sync_enabled
    and cfg.rate_mode = 'automatic'
    and cfg.last_auto_sync_status = 'ok'
    and cfg.last_auto_sync_at is not null
    and cfg.last_auto_sync_at >= now() - interval '2 hours';

  return jsonb_build_object(
    'available', cfg.current_rate is not null and cfg.current_rate > 0,
    'fresh', fresh,
    'rate', cfg.current_rate,
    'previous_rate', prior_rate,
    'base_currency', cfg.base_currency,
    'charge_currency', cfg.charge_currency,
    'source', 'elTOQUE',
    'checked_at', cfg.last_auto_sync_at,
    'changed_at', last_change.created_at
  );
end;
$function$;

revoke all on function public.marketplace_public_eltoque_rate() from public;
grant execute on function public.marketplace_public_eltoque_rate() to anon, authenticated;
