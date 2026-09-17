-- Regimen — first-party product analytics
--
-- Run this in the Supabase SQL Editor after schema.sql and indexes.sql.
--
-- Why a table and not an SDK
-- --------------------------
-- The app's entire positioning is that scans run on-device and photos are
-- never sent anywhere to be scored. Dropping in Firebase or Mixpanel would
-- contradict that in the one place users are most likely to check: the
-- App Privacy label, which would gain a third-party data collector. Events
-- land in the same Postgres the app already uses, under the same RLS, so
-- nothing leaves infrastructure the user has already trusted with their
-- products and photos.
--
-- What goes in here
-- -----------------
-- Funnel shape only: which step of onboarding someone reached, whether
-- they ran a scan, whether the paywall converted. No photo data, no skin
-- scores, no product names, no free text. `properties` is deliberately
-- small and typed on the client (see `Analytics.swift`) rather than a
-- free-for-all.
--
-- IMPORTANT for submission: these rows are tied to `user_id`, which makes
-- this "Linked to You" usage data in App Store Connect's App Privacy
-- questionnaire. Declare it as Product Interaction / Analytics, linked.
-- The in-app opt-out lives in Settings.
--
-- This file is not part of the Xcode target — it's a reference script for
-- the Supabase dashboard, not app source.

create table if not exists public.analytics_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  name text not null,
  properties jsonb not null default '{}'::jsonb,
  app_version text,
  occurred_at timestamptz not null default now()
);

alter table public.analytics_events enable row level security;

-- Insert-only from the client. Deliberately no select policy: a user has
-- no reason to read the event stream back, and not granting it keeps the
-- table from becoming another surface to reason about.
create policy "Users can record their own events"
  on public.analytics_events for insert
  with check (auth.uid() = user_id);

create index if not exists analytics_events_name_time_idx
  on public.analytics_events (name, occurred_at desc);

create index if not exists analytics_events_user_idx
  on public.analytics_events (user_id, occurred_at desc);

-- ---------------------------------------------------------------------
-- Funnel query to run once there's data. Each step is a distinct user
-- count, so the drop between rows is the thing worth looking at.
-- ---------------------------------------------------------------------
-- select name, count(distinct user_id) as users
-- from public.analytics_events
-- where name in (
--   'onboarding_started', 'onboarding_completed', 'first_product_added',
--   'scan_started', 'scan_completed', 'paywall_shown', 'purchase_completed'
-- )
-- group by name
-- order by users desc;
