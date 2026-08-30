-- Regimen — one free skin scan for non-premium accounts
--
-- Run this in the Supabase SQL Editor after schema.sql. Lets a free
-- account run the on-device skin scan once before hitting the paywall --
-- letting someone actually see a highlighted photo and a real score is a
-- much stronger pitch for premium than a feature list alone.
--
-- Stored server-side (not on-device) so it can't be reset by deleting and
-- reinstalling the app or signing out and back in -- the same reasoning as
-- `is_premium` living here rather than in UserDefaults.
--
-- This file is not part of the Xcode target — it's a reference script for
-- the Supabase dashboard, not app source.

alter table public.profiles
  add column has_used_free_scan boolean not null default false;
