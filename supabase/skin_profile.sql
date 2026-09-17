-- Regimen — skin profile on the account
--
-- Run this in the Supabase SQL Editor after schema.sql.
--
-- The routine quiz's four answers (`SkinProfile`) started out in
-- UserDefaults, which was a reasonable call when they only shaped a
-- one-off routine build. They now drive `RecommendationEngine` as well --
-- every "what to use" card is filtered through the user's sensitivity and
-- experience -- so keeping them device-local meant the same account got
-- materially different advice on an iPad than on an iPhone, and lost the
-- answers entirely on reinstall.
--
-- Nullable with no default: null means "hasn't taken the quiz", which is
-- distinct from "answered with the defaults" and is what the app uses to
-- decide whether to prompt.
--
-- This file is not part of the Xcode target — it's a reference script for
-- the Supabase dashboard, not app source.

alter table public.profiles
  add column if not exists skin_type text,
  add column if not exists skin_sensitivity text,
  add column if not exists actives_experience text,
  add column if not exists routine_length text;
