-- Regimen — full-feature test state for one account
--
-- Builds a rich, self-consistent state for a@a.a so every feature has
-- something real to show. Re-runnable: it clears that account's own rows
-- first, so running it twice gives the same result rather than doubling up.
--
-- Run AFTER every migration, in particular:
--   schema.sql, layering.sql, dose.sql, skin_score.sql, premium.sql,
--   multi_tag_conflicts.sql, zone_findings.sql, streak_restores.sql,
--   free_scan.sql, streak_restore_credits.sql, skin_profile.sql,
--   scan_persistence.sql, indexes.sql, schedules_and_history.sql
--
-- ---------------------------------------------------------------------
-- ONE THING THIS SCRIPT CANNOT DO
--
-- Progress photos are rows here but JPEGs in Supabase Storage. This
-- inserts the metadata (scores, zones, attributes) so the trend chart,
-- per-zone progress and weekly digest all have real data to draw, but the
-- image files don't exist, so thumbnails render as grey placeholders and
-- opening one shows no photo.
--
-- To exercise the scan itself, take two or three photos in the app after
-- running this. They'll sit alongside the seeded history.
-- ---------------------------------------------------------------------
--
-- Not part of the Xcode target. Delete it once you're done testing.

do $$
declare
  uid uuid;
  cleanser_id uuid := gen_random_uuid();
  niacinamide_id uuid := gen_random_uuid();
  vitamin_c_id uuid := gen_random_uuid();
  bha_id uuid := gen_random_uuid();
  retinol_id uuid := gen_random_uuid();
  moisturizer_id uuid := gen_random_uuid();
  sunscreen_id uuid := gen_random_uuid();
  archived_id uuid := gen_random_uuid();
  photo_old uuid := gen_random_uuid();
  photo_mid uuid := gen_random_uuid();
  photo_new uuid := gen_random_uuid();
  folder text;
begin
  select id into uid from auth.users where email = 'a@a.a';
  if uid is null then
    raise exception 'No account found for a@a.a. Sign up in the app first.';
  end if;

  -- Storage paths follow the app's own convention: a lowercase per-user
  -- folder, which the storage RLS policy compares against auth.uid()::text.
  folder := lower(uid::text);

  -- ==================================================================
  -- 1. Clear this account's data (and only this account's)
  -- ==================================================================
  delete from public.usage_logs      where user_id = uid;
  delete from public.zone_findings   where user_id = uid;
  delete from public.progress_photos where user_id = uid;
  delete from public.products        where user_id = uid;
  delete from public.streak_restores where user_id = uid;
  delete from public.skin_reactions  where user_id = uid;
  delete from public.product_empties where user_id = uid;

  -- ==================================================================
  -- 2. Profile: premium, quiz answered, free scan already spent
  -- ==================================================================
  -- Premium so the widget, trend charts, per-zone progress, routine
  -- builder and streak restores are all reachable. Two restore credits so
  -- the purchased path can be exercised without a sandbox purchase.
  update public.profiles set
    is_premium                = true,
    has_used_free_scan        = true,
    purchased_restore_credits = 2,
    has_completed_onboarding  = true,
    skin_type                 = 'Combination',
    skin_sensitivity          = 'Yes, easily',
    actives_experience        = 'Used to actives',
    routine_length            = 'Long'
  where id = uid;

  -- ==================================================================
  -- 3. Products
  -- ==================================================================
  -- Chosen so the cabinet covers every axis at once: all three frequency
  -- kinds, AM/PM/Both, a guaranteed conflict, a bottle about to run out,
  -- one past its shelf life, and one archived.
  insert into public.products
    (id, user_id, name, brand, routine_time, layer_category, application_order,
     conflict_tags, size_ml, typical_dose_ml, opened_date, is_archived,
     frequency_kind, frequency_days_of_week, frequency_interval_days, months_after_opening)
  values
    -- Daily, both routines, plenty left.
    (cleanser_id, uid, 'Hydrating Facial Cleanser', 'CeraVe', 'Both', 'Cleanser', 1,
     '{}', 355, 2.0, now() - interval '60 days', false,
     'daily', '{}', 1, 12),

    -- These two are the guaranteed conflict: pure vitamin C and
    -- niacinamide, both AM, both daily, so the Routine tab always shows a
    -- conflict banner in the morning.
    (niacinamide_id, uid, 'Niacinamide 10% + Zinc 1%', 'The Ordinary', 'AM', 'Treatment', 1,
     '{Niacinamide}', 30, 0.5, now() - interval '40 days', false,
     'daily', '{}', 1, 12),
    (vitamin_c_id, uid, 'Vitamin C Suspension 23%', 'The Ordinary', 'AM', 'Treatment', 2,
     '{Pure Vitamin C}', 30, 0.5, now() - interval '20 days', false,
     'daily', '{}', 1, 6),

    -- Tuesday / Thursday / Saturday (Calendar weekdays 3, 5, 7).
    -- Demonstrates the weekday schedule and the "Not due today" section.
    (bha_id, uid, '2% BHA Liquid Exfoliant', 'Paula''s Choice', 'PM', 'Treatment', 1,
     '{Exfoliating Acid}', 118, 0.5, now() - interval '90 days', false,
     'days_of_week', '{3,5,7}', 1, 24);

  -- Every other day, and deliberately opened 300 days ago against a 6
  -- month shelf life, so the expiry warning has something to show. 300 is
  -- even, so counting every second day from the opened date lands on today.
  insert into public.products
    (id, user_id, name, brand, routine_time, layer_category, application_order,
     conflict_tags, size_ml, typical_dose_ml, opened_date, is_archived,
     frequency_kind, frequency_days_of_week, frequency_interval_days, months_after_opening)
  values
    (retinol_id, uid, 'Retinol 0.5% in Squalane', 'The Ordinary', 'PM', 'Treatment', 2,
     '{Retinoid}', 30, 0.5, date_trunc('day', now()) - interval '300 days', false,
     'every_n_days', '{}', 2, 6),

    -- Sized and dosed to land in the red on the Reorder tab, which is what
    -- surfaces the "Restocked" button.
    (moisturizer_id, uid, 'Toleriane Double Repair Moisturizer', 'La Roche-Posay', 'Both', 'Moisturizer', 1,
     '{}', 75, 1.5, now() - interval '30 days', false,
     'daily', '{}', 1, 12),

    (sunscreen_id, uid, 'Anthelios UV Mune 400 SPF50+', 'La Roche-Posay', 'AM', 'Sunscreen', 1,
     '{}', 50, 1.25, now() - interval '25 days', false,
     'daily', '{}', 1, 12),

    -- Archived, so the Cabinet's archived filter has something behind it.
    (archived_id, uid, 'Foaming Facial Cleanser', 'CeraVe', 'Both', 'Cleanser', 2,
     '{}', 236, 2.0, now() - interval '200 days', true,
     'daily', '{}', 1, null);

  -- ==================================================================
  -- 4. Usage history
  -- ==================================================================
  -- Days 2 through 20 are fully logged, which builds a streak in the
  -- badge's second-hottest tier. Yesterday and today are deliberately
  -- *partial*: yesterday keeps the streak alive (one log is enough) while
  -- still leaving the "Forgot yesterday?" backfill prompt actionable, and
  -- today leaves the progress row mid-way rather than complete.
  --
  -- Each product is logged only on days its own schedule actually calls
  -- for, so the history agrees with the frequencies set above.
  insert into public.usage_logs (user_id, product_id, "timestamp", time_of_day, estimated_amount_used_ml)
  select
    uid,
    p.id,
    (date_trunc('day', now()) - (d || ' days')::interval) + interval '12 hours',
    t.time_of_day,
    p.dose
  from generate_series(2, 20) as d
  cross join (values
    (cleanser_id,     2.0,  'Both'),
    (niacinamide_id,  0.5,  'AM'),
    (vitamin_c_id,    0.5,  'AM'),
    (bha_id,          0.5,  'PM'),
    (retinol_id,      0.5,  'PM'),
    (moisturizer_id,  1.5,  'Both'),
    (sunscreen_id,    1.25, 'AM')
  ) as p(id, dose, routine_time)
  cross join lateral (
    select unnest(
      case p.routine_time when 'Both' then array['AM','PM'] else array[p.routine_time] end
    ) as time_of_day
  ) as t
  where
    -- Never log a product before it was opened.
    (date_trunc('day', now()) - (d || ' days')::interval)
      >= date_trunc('day', (select opened_date from public.products where id = p.id))
    -- Respect each product's own schedule.
    and (
      p.id not in (bha_id, retinol_id)
      -- Postgres dow is 0=Sunday, Calendar's weekday is 1=Sunday, so the
      -- {3,5,7} stored on the product is dow {2,4,6} here. Cast because
      -- extract returns numeric, not integer.
      or (p.id = bha_id and extract(dow from (now() - (d || ' days')::interval))::int in (2, 4, 6))
      or (p.id = retinol_id and (300 - d) % 2 = 0)
    );

  -- Yesterday: cleanser only. Streak survives, backfill prompt appears.
  insert into public.usage_logs (user_id, product_id, "timestamp", time_of_day, estimated_amount_used_ml)
  values (uid, cleanser_id, date_trunc('day', now()) - interval '12 hours', 'AM', 2.0);

  -- Today: two of the morning products, so the routine reads part-done.
  insert into public.usage_logs (user_id, product_id, "timestamp", time_of_day, estimated_amount_used_ml)
  values
    (uid, cleanser_id,    now() - interval '2 hours', 'AM', 2.0),
    (uid, niacinamide_id, now() - interval '2 hours', 'AM', 0.5);

  -- ==================================================================
  -- 5. Progress photos and scan results
  -- ==================================================================
  -- Three scans on an improving trend, which is what the score chart,
  -- the per-zone card and the weekly digest all read from. Attributes are
  -- stored with the stable keys SkinAttribute.persistenceKey writes.
  insert into public.progress_photos
    (id, user_id, "timestamp", storage_path, note, skin_score, skin_attributes)
  values
    (photo_old, uid, now() - interval '42 days', folder || '/' || gen_random_uuid() || '.jpg',
     'Starting point', 58, '{uneven_skin,dark_spots}'),
    (photo_mid, uid, now() - interval '21 days', folder || '/' || gen_random_uuid() || '.jpg',
     'Three weeks in, added the BHA', 66, '{uneven_skin}'),
    (photo_new, uid, now() - interval '2 days',  folder || '/' || gen_random_uuid() || '.jpg',
     'Best it has looked', 74, '{}');

  -- Per-zone findings, trending down across the three scans so the
  -- per-zone card shows real improvement rather than flat bars.
  insert into public.zone_findings (user_id, progress_photo_id, zone, kind, finding_count, cell_count)
  values
    (uid, photo_old, 'forehead',    'blemish',   4, 22),
    (uid, photo_old, 'left cheek',  'spot',      3, 14),
    (uid, photo_old, 'right cheek', 'spot',      2, 11),
    (uid, photo_old, 'nose',        'blackhead', 5, 12),
    (uid, photo_old, 'chin',        'blemish',   3, 16),

    (uid, photo_mid, 'forehead',    'blemish',   2, 12),
    (uid, photo_mid, 'left cheek',  'spot',      3, 13),
    (uid, photo_mid, 'right cheek', 'spot',      1,  6),
    (uid, photo_mid, 'nose',        'blackhead', 4, 10),
    (uid, photo_mid, 'chin',        'blemish',   1,  7),

    (uid, photo_new, 'forehead',    'blemish',   1,  5),
    (uid, photo_new, 'left cheek',  'spot',      2,  9),
    (uid, photo_new, 'nose',        'blackhead', 2,  6);

  -- ==================================================================
  -- 6. Reactions
  -- ==================================================================
  -- One lines up with starting the vitamin C 20 days ago, which is exactly
  -- the correlation the reaction log exists to make visible.
  insert into public.skin_reactions (user_id, occurred_on, severity, note)
  values
    (uid, current_date - 18, 'moderate', 'Stinging and redness after the new vitamin C.'),
    (uid, current_date - 6,  'mild',     'A bit tight, probably the cold weather.');

  -- ==================================================================
  -- 7. Empties
  -- ==================================================================
  insert into public.product_empties
    (user_id, product_id, product_name, brand, finished_on, would_repurchase, rating, note)
  values
    (uid, null, 'Gentle Skin Cleanser', 'Cetaphil', current_date - 35, true,  4,
     'Did the job, never irritated anything.'),
    (uid, null, 'Ultra Facial Cream',   'Kiehl''s', current_date - 70, false, 2,
     'Too heavy, kept breaking me out along the jaw.');

  raise notice 'Seeded test state for a@a.a (%).', uid;
end $$;


-- =====================================================================
-- VARIATIONS
--
-- The states below are mutually exclusive with the one above, so they're
-- left commented. Uncomment a block and run it on its own after the main
-- script to test that specific path.
-- =====================================================================

-- ---------------------------------------------------------------------
-- A. Streak restore available
--
-- The main script keeps the streak unbroken, so nothing is restorable.
-- This clears yesterday's only log to open a gap with earned history
-- behind it, which is what makes a restore worth spending.
-- ---------------------------------------------------------------------
-- delete from public.usage_logs
-- where user_id = (select id from auth.users where email = 'a@a.a')
--   and "timestamp" >= date_trunc('day', now()) - interval '1 day'
--   and "timestamp" <  date_trunc('day', now());

-- ---------------------------------------------------------------------
-- B. Restore on cooldown, so the purchase path is the only way through
--
-- Back-dates a restore so the free monthly one is unavailable, and zeroes
-- the credit balance. Pair with variation A to see the paid prompt.
-- ---------------------------------------------------------------------
-- insert into public.streak_restores (user_id, restored_on)
-- values ((select id from auth.users where email = 'a@a.a'), current_date - 10)
-- on conflict (user_id, restored_on) do nothing;
--
-- update public.profiles set purchased_restore_credits = 0
-- where id = (select id from auth.users where email = 'a@a.a');

-- ---------------------------------------------------------------------
-- C. Free account with its scan unspent
--
-- For the paywall, the free-scan confirmation, and every premium gate.
-- ---------------------------------------------------------------------
-- update public.profiles set is_premium = false, has_used_free_scan = false
-- where id = (select id from auth.users where email = 'a@a.a');

-- ---------------------------------------------------------------------
-- D. Quiz never taken
--
-- Recommendations fall back to conservative defaults, and Settings shows
-- "Not set".
-- ---------------------------------------------------------------------
-- update public.profiles set
--   skin_type = null, skin_sensitivity = null,
--   actives_experience = null, routine_length = null
-- where id = (select id from auth.users where email = 'a@a.a');

-- ---------------------------------------------------------------------
-- E. Rest day
--
-- Makes every product weekend-only, so a weekday shows the "Rest Day"
-- empty state and proves a rest day doesn't break the streak.
-- ---------------------------------------------------------------------
-- update public.products
-- set frequency_kind = 'days_of_week', frequency_days_of_week = '{1,7}'
-- where user_id = (select id from auth.users where email = 'a@a.a')
--   and not is_archived;

-- ---------------------------------------------------------------------
-- F. Empty account
--
-- Every empty state, and the onboarding activation flow.
-- ---------------------------------------------------------------------
-- do $$
-- declare uid uuid;
-- begin
--   select id into uid from auth.users where email = 'a@a.a';
--   delete from public.usage_logs      where user_id = uid;
--   delete from public.zone_findings   where user_id = uid;
--   delete from public.progress_photos where user_id = uid;
--   delete from public.products        where user_id = uid;
--   delete from public.streak_restores where user_id = uid;
--   delete from public.skin_reactions  where user_id = uid;
--   delete from public.product_empties where user_id = uid;
--   update public.profiles set
--     is_premium = false, has_used_free_scan = false,
--     purchased_restore_credits = 0, has_completed_onboarding = false
--   where id = uid;
-- end $$;
