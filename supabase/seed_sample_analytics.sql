-- Regimen — sample analytics data for testing dashboards/charts
--
-- Generates a realistic funnel shape across 40 synthetic accounts over the
-- last 14 days, so Supabase Studio's chart/report views (or any query
-- you're testing) have something to draw before real users exist.
--
-- Each stage keeps only some of the previous stage's users, mirroring an
-- actual drop-off funnel rather than random noise:
--   onboarding_started (40) -> onboarding_completed (30) -> first_product_added (26)
--   -> scan_started (20) -> scan_completed (16) -> paywall_shown (14)
--   -> purchase_started (6) -> purchase_completed (4)
--
-- Needs real rows in auth.users for the foreign key on analytics_events,
-- so this creates 40 clearly-marked test accounts first
-- (analytics-test-N@regimen.test). A cleanup query to remove everything
-- this creates is at the bottom -- run it once you're done looking.
--
-- Not part of the Xcode target and not a schema migration. Delete this
-- file (and run the cleanup block) once you're done testing.

do $$
declare
  user_ids uuid[];
  uid uuid;
  i int;
  day_offset int;
  event_time timestamptz;
begin
  -- ==================================================================
  -- 1. Forty synthetic accounts. Distinct users are what every funnel
  --    query below counts, so this can't be done with one repeated id.
  -- ==================================================================
  for i in 1..40 loop
    -- `id` is set explicitly -- Supabase's real auth.users has no default
    -- on it (only local scratch schemas used for testing this script had
    -- one), so omitting it fails with a not-null violation and rolls back
    -- this entire DO block with nothing to show for it.
    insert into auth.users (id, email, raw_user_meta_data, created_at)
    values (
      gen_random_uuid(),
      'analytics-test-' || i || '@regimen.test',
      jsonb_build_object('name', 'Test User ' || i),
      now() - ((14 - (i % 14)) || ' days')::interval
    )
    returning id into uid;
    user_ids := array_append(user_ids, uid);
  end loop;

  -- ==================================================================
  -- 2. Walk the funnel. Each stage samples from the array position range
  --    of whoever "made it" to the previous stage, so the same users
  --    carry through consistently rather than a fresh random subset each
  --    time (which would make step-over-step users inconsistent).
  -- ==================================================================
  for i in 1..40 loop
    uid := user_ids[i];
    day_offset := 14 - (i % 14);
    event_time := now() - (day_offset || ' days')::interval - (random() * interval '10 hours');

    -- onboarding_started: everyone.
    insert into public.analytics_events (user_id, name, properties, app_version, occurred_at)
    values (uid, 'onboarding_started', '{}', '1.0', event_time);

    -- onboarding_completed: 30 of 40. The other 10 skip.
    if i <= 30 then
      insert into public.analytics_events (user_id, name, properties, app_version, occurred_at)
      values (uid, 'onboarding_completed', '{}', '1.0', event_time + interval '3 minutes');
    else
      insert into public.analytics_events (user_id, name, properties, app_version, occurred_at)
      values (uid, 'onboarding_skipped', '{}', '1.0', event_time + interval '1 minute');
    end if;

    -- first_product_added: 26 of the 30 who completed onboarding.
    if i <= 26 then
      insert into public.analytics_events (user_id, name, properties, app_version, occurred_at)
      values (
        uid, 'first_product_added',
        jsonb_build_object('source', (array['catalog','manual','barcode'])[1 + (i % 3)]),
        '1.0', event_time + interval '5 minutes'
      );
    end if;

    -- A handful of returning users add a second product a few days later.
    if i <= 12 then
      insert into public.analytics_events (user_id, name, properties, app_version, occurred_at)
      values (uid, 'product_added', jsonb_build_object('source', 'catalog'), '1.0', event_time + interval '3 days');
    end if;

    -- scan_started: 20 of the 26 who added a product.
    if i <= 20 then
      insert into public.analytics_events (user_id, name, properties, app_version, occurred_at)
      values (uid, 'scan_started', jsonb_build_object('tier', 'free'), '1.0', event_time + interval '10 minutes');

      -- scan_completed for 16, scan_failed for the other 4.
      if i <= 16 then
        insert into public.analytics_events (user_id, name, properties, app_version, occurred_at)
        values (uid, 'scan_completed', jsonb_build_object('tier', 'free'), '1.0', event_time + interval '11 minutes');
      else
        insert into public.analytics_events (user_id, name, properties, app_version, occurred_at)
        values (
          uid, 'scan_failed',
          jsonb_build_object('reason', case when i = 17 then 'no_face' else 'other' end),
          '1.0', event_time + interval '11 minutes'
        );
      end if;
    end if;

    -- paywall_shown: 14 of the 16 completed scans, plus a couple from
    -- other triggers, so the source breakdown isn't 100% one value.
    if i <= 14 then
      insert into public.analytics_events (user_id, name, properties, app_version, occurred_at)
      values (
        uid, 'paywall_shown',
        jsonb_build_object('source', case when i <= 10 then 'scan' when i <= 12 then 'routine_builder' else 'streak_restore' end),
        '1.0', event_time + interval '12 minutes'
      );
    end if;

    -- purchase_started: 6, purchase_completed: 4 (2 cancel/abandon).
    if i <= 6 then
      insert into public.analytics_events (user_id, name, properties, app_version, occurred_at)
      values (
        uid, 'purchase_started',
        jsonb_build_object('plan', case when i % 2 = 0 then 'com.alecagayan.Regimen.premium.yearly' else 'com.alecagayan.Regimen.premium.monthly2' end),
        '1.0', event_time + interval '13 minutes'
      );
      if i <= 4 then
        insert into public.analytics_events (user_id, name, properties, app_version, occurred_at)
        values (
          uid, 'purchase_completed',
          jsonb_build_object('plan', case when i % 2 = 0 then 'com.alecagayan.Regimen.premium.yearly' else 'com.alecagayan.Regimen.premium.monthly2' end),
          '1.0', event_time + interval '14 minutes'
        );
      end if;
    end if;

    -- routine_completed: a spread of AM/PM check-offs over the following
    -- several days, only for users who got at least as far as adding a
    -- product -- gives the daily-trend chart something with real shape.
    if i <= 26 then
      for day_offset in 0..4 loop
        if random() < 0.7 then
          insert into public.analytics_events (user_id, name, properties, app_version, occurred_at)
          values (uid, 'routine_completed', jsonb_build_object('time_of_day', 'AM'), '1.0', event_time + (day_offset || ' days')::interval + interval '9 hours');
        end if;
        if random() < 0.6 then
          insert into public.analytics_events (user_id, name, properties, app_version, occurred_at)
          values (uid, 'routine_completed', jsonb_build_object('time_of_day', 'PM'), '1.0', event_time + (day_offset || ' days')::interval + interval '21 hours');
        end if;
      end loop;
    end if;

    -- quiz_completed: about half of the product-adders.
    if i <= 13 then
      insert into public.analytics_events (user_id, name, properties, app_version, occurred_at)
      values (uid, 'quiz_completed', '{}', '1.0', event_time + interval '20 minutes');
    end if;
  end loop;

  raise notice 'Seeded % synthetic users and their analytics events.', array_length(user_ids, 1);
end $$;


-- =====================================================================
-- CLEANUP -- run this once you're done looking at the dashboard.
-- Deletes the synthetic auth.users rows, which cascades to their
-- profiles (via the signup trigger's own row) and analytics_events.
-- =====================================================================
-- delete from auth.users where email like 'analytics-test-%@regimen.test';
