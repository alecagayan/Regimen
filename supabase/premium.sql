-- Regimen — premium entitlement flag
--
-- Run this in the Supabase SQL Editor after schema.sql etc.
-- Adds `is_premium` to `profiles`. There's no real payment processing wired
-- up yet (App Store subscriptions need StoreKit configuration in App Store
-- Connect, which needs the developer's own Apple account and can't be set
-- up from outside Xcode/App Store Connect) -- this flag is the entitlement
-- check every gated feature reads, ready to be flipped by a real purchase
-- once StoreKit is wired in. For now PaywallView flips it directly.
--
-- This file is not part of the Xcode target -- it's a reference script for
-- the Supabase dashboard, not app source.

alter table public.profiles
  add column if not exists is_premium boolean not null default false;
