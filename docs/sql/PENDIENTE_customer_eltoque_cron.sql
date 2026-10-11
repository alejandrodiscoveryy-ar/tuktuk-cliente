-- DEPLOY ORDER: after review of schema, Edge function, Firebase access and smoke tests.
-- DO NOT EXECUTE NOW. Reuses an EXISTING vault secret; it never embeds the secret.
-- Schema owner: vrixora-admin-canvas/supabase/migrations/.
select cron.schedule('tuktuk-customer-eltoque-push-dispatch', '*/5 * * * *', $cron$
  select net.http_post(
    url := 'https://vvxvnywzgtqhlaqpxyqh.supabase.co/functions/v1/marketplace-customer-rate-push',
    headers := jsonb_build_object(
      'Content-Type','application/json',
      'x-tuktuk-dispatch-secret',(
        select decrypted_secret from vault.decrypted_secrets
        where name='tuktuk_push_dispatch_secret' limit 1
      )
    ),
    body := jsonb_build_object('action','dispatch')
  );
$cron$);
