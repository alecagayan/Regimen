-- Regimen — on-device skin analysis scores
--
-- Run this in the Supabase SQL Editor *after* schema.sql. Adds nullable
-- score columns to `progress_photos` so a photo's on-device Core ML
-- analysis (see RegimenSkinModel/, the sibling training project) persists
-- and syncs across devices like everything else in this app. Nullable
-- because most photos will never be analyzed -- analysis is opt-in, run
-- locally on the device, not automatic on upload.
--
-- `overall_score` isn't stored -- it's always a plain average of the
-- other three, computed wherever it's displayed, same reasoning as the
-- training project not training a dedicated "overall" model head.
--
-- This file is not part of the Xcode target — it's a reference script for
-- the Supabase dashboard, not app source.

alter table public.progress_photos
  add column redness_score double precision,
  add column texture_score double precision,
  add column clarity_score double precision;
