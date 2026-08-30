-- Regimen — purchasable extra streak restores
--
-- Run this in the Supabase SQL Editor after streak_restores.sql. Adds a
-- balance of purchased-but-not-yet-spent restore credits, bought as a
-- $0.99 consumable in-app purchase -- a way past the one-every-30-days
-- free limit (see `AppData.daysBetweenStreakRestores`) without waiting.
--
-- A plain counter, not a row-per-purchase table like `streak_restores`
-- itself: there's nothing about an individual purchase worth keeping a
-- history of (no date range, no "which day" the way a restore has), just
-- a balance that goes up on purchase and down on use.
--
-- This file is not part of the Xcode target — it's a reference script for
-- the Supabase dashboard, not app source.

alter table public.profiles
  add column purchased_restore_credits integer not null default 0;
