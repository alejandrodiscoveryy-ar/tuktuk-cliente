-- PREPARACION, NO EJECUTAR SIN AUTORIZACION DE PRODUCCION.
-- Source of truth after approval: vrixora-admin-canvas/supabase/migrations/.
-- Customer push uses a separate delivery queue and no auth.users or Conductor licenses.
-- Only the service_role can read subscriptions or manipulate queue. No direct anon table access.

create table if not exists public.marketplace_customer_eltoque_push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  token_hash text not null unique,
  fcm_token text not null,
  secret_hash text not null,
  enabled boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '180 days'),
  constraint customer_eltoque_token_hash_shape check (token_hash ~ '^[0-9a-f]{64}$'),
  constraint customer_eltoque_secret_hash_shape check (secret_hash ~ '^[0-9a-f]{64}$'),
  constraint customer_eltoque_token_limit check (char_length(fcm_token) between 80 and 4096)
);

create table if not exists public.marketplace_customer_eltoque_push_deliveries (
  id bigint generated always as identity primary key,
  subscription_id uuid not null references public.marketplace_customer_eltoque_push_subscriptions(id) on delete cascade,
  rate_history_id bigint not null references public.project_exchange_rate_history(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending','sending','retry','sent','failed')),
  attempt_count integer not null default 0,
  claimed_until timestamptz,
  claim_id uuid,
  next_attempt_at timestamptz not null default now(),
  last_error text,
  created_at timestamptz not null default now(),
  sent_at timestamptz,
  unique (subscription_id, rate_history_id)
);

create index if not exists marketplace_customer_eltoque_push_delivery_pending_idx
  on public.marketplace_customer_eltoque_push_deliveries(status, next_attempt_at)
  where status in ('pending','retry','sending');
create index if not exists marketplace_customer_eltoque_push_subscription_expiry_idx
  on public.marketplace_customer_eltoque_push_subscriptions(expires_at) where enabled;

alter table public.marketplace_customer_eltoque_push_subscriptions enable row level security;
alter table public.marketplace_customer_eltoque_push_deliveries enable row level security;
revoke all on public.marketplace_customer_eltoque_push_subscriptions from public, anon, authenticated;
revoke all on public.marketplace_customer_eltoque_push_deliveries from public, anon, authenticated;
grant all on public.marketplace_customer_eltoque_push_subscriptions to service_role;
grant all on public.marketplace_customer_eltoque_push_deliveries to service_role;
grant usage, select on sequence public.marketplace_customer_eltoque_push_deliveries_id_seq to service_role;

create or replace function app_private.enqueue_marketplace_customer_eltoque_push()
returns trigger
language plpgsql security definer set search_path = '' as $function$
begin
  if new.project_id <> 'dfb41cea-a812-46f2-b511-7a60bd3d78af'::uuid
     or new.rate_source is distinct from 'elTOQUE'
     or new.rate_mode is distinct from 'automatic' then
    return new;
  end if;

  insert into public.marketplace_customer_eltoque_push_deliveries(subscription_id,rate_history_id)
  select s.id, new.id
  from public.marketplace_customer_eltoque_push_subscriptions s
  where s.enabled and s.expires_at > now() and s.created_at < new.created_at
  on conflict (subscription_id, rate_history_id) do nothing;
  return new;
end;
$function$;

drop trigger if exists trg_marketplace_customer_eltoque_push on public.project_exchange_rate_history;
create trigger trg_marketplace_customer_eltoque_push
  after insert on public.project_exchange_rate_history
  for each row execute function app_private.enqueue_marketplace_customer_eltoque_push();

create or replace function public.marketplace_customer_eltoque_push_claim(batch_limit int default 80)
returns table (
  delivery_id bigint, claim_uuid uuid, subscription_id uuid, fcm_token text,
  rate_history_id bigint, current_rate numeric, previous_rate numeric,
  attempt_number integer
)
language plpgsql security definer set search_path = '' as $function$
begin
  if auth.role() <> 'service_role' then
    raise exception 'Forbidden' using errcode='42501';
  end if;
  if batch_limit < 1 or batch_limit > 100 then
    raise exception 'Invalid batch limit' using errcode='22023';
  end if;
  return query
  with candidates as (
    select d.id
    from public.marketplace_customer_eltoque_push_deliveries d
    join public.marketplace_customer_eltoque_push_subscriptions s on s.id=d.subscription_id
    join public.project_exchange_rate_history h on h.id=d.rate_history_id
    where s.enabled and s.expires_at > now()
      and h.created_at >= now()-interval '12 hours'
      and d.attempt_count < 5
      and (
        (d.status in ('pending','retry') and d.next_attempt_at <= now())
        or (d.status = 'sending' and d.claimed_until < now())
      )
    order by d.id
    limit batch_limit
    for update of d skip locked
  ), claimed as (
    update public.marketplace_customer_eltoque_push_deliveries d
    set status='sending', attempt_count=d.attempt_count+1,
        claim_id=gen_random_uuid(), claimed_until=now()+interval '4 minutes'
    where d.id in (select c.id from candidates c)
    returning d.id, d.claim_id, d.subscription_id, d.rate_history_id, d.attempt_count
  )
  select c.id, c.claim_id, c.subscription_id, s.fcm_token, h.id, h.rate,
    (
      select prev.rate from public.project_exchange_rate_history prev
      where prev.project_id=h.project_id and prev.rate_source='elTOQUE' and prev.id<h.id
      order by prev.id desc limit 1
    ),c.attempt_count
  from claimed c
  join public.marketplace_customer_eltoque_push_subscriptions s on s.id=c.subscription_id
  join public.project_exchange_rate_history h on h.id=c.rate_history_id;
end;
$function$;

revoke all on function public.marketplace_customer_eltoque_push_claim(int) from public, anon, authenticated;
grant execute on function public.marketplace_customer_eltoque_push_claim(int) to service_role;

-- Best-effort anonymous enrollment throttle. Still require perimeter/WAF review.
create table if not exists public.marketplace_customer_eltoque_push_registration_limits (
  ip_hash text primary key check (ip_hash ~ '^[0-9a-f]{64}$'),
  window_start timestamptz not null default now(),
  attempt_count int not null default 0,
  updated_at timestamptz not null default now()
);
alter table public.marketplace_customer_eltoque_push_registration_limits enable row level security;
revoke all on public.marketplace_customer_eltoque_push_registration_limits from public, anon, authenticated;
grant all on public.marketplace_customer_eltoque_push_registration_limits to service_role;

create or replace function public.marketplace_customer_eltoque_push_allow_signup(ip_digest text)
returns boolean language plpgsql security definer set search_path = '' as $function$
declare attempts int;
begin
  if auth.role() <> 'service_role' then
    raise exception 'Forbidden' using errcode='42501';
  end if;
  if ip_digest !~ '^[0-9a-f]{64}$' then return false; end if;
  insert into public.marketplace_customer_eltoque_push_registration_limits as l
    (ip_hash,window_start,attempt_count,updated_at)
  values (ip_digest,now(),1,now())
  on conflict (ip_hash) do update set
    attempt_count=case when l.window_start<now()-interval '1 hour'
      then 1 else l.attempt_count+1 end,
    window_start=case when l.window_start<now()-interval '1 hour'
      then now() else l.window_start end,
    updated_at=now()
  returning attempt_count into attempts;
  return attempts <= 8;
end;
$function$;
revoke all on function public.marketplace_customer_eltoque_push_allow_signup(text)
  from public,anon,authenticated;
grant execute on function public.marketplace_customer_eltoque_push_allow_signup(text) to service_role;
