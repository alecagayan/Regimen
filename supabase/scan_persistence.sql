-- Regimen — persisted scan results
--
-- Run this in the Supabase SQL Editor after schema.sql and zone_findings.sql.
--
-- A scan used to persist only its score. The highlighted overlay, the
-- whole-face attributes, and the crop the overlay maps onto were all
-- recomputed per view and thrown away on dismiss -- so reopening a scanned
-- photo showed a bare number where the highlighted face had been.
--
-- For a *free* account that was worse than untidy: one free scan, spent
-- once, and the single most compelling thing the app does was gone for
-- good the moment the sheet closed, with re-scanning blocked behind the
-- paywall. The overlay is a small PNG (a 448px render of a 56x56 mask), so
-- it lives in the same private Storage bucket as the photo itself and only
-- its path is stored here.
--
-- The per-zone finding *counts* are not duplicated here -- `zone_findings`
-- already stores them, and the app rebuilds the "SPOTTED" list from that.
--
-- This file is not part of the Xcode target — it's a reference script for
-- the Supabase dashboard, not app source.

alter table public.progress_photos
  -- Stable keys ("sensitivity", "dark_spots", "uneven_skin"), not the
  -- Core ML model filenames -- see `SkinAttribute.persistenceKey`.
  add column if not exists skin_attributes text[] not null default '{}',
  add column if not exists overlay_path text,
  -- Normalized (0-1, top-left origin) crop of the photo the scan ran on,
  -- which is what positions the overlay. Null together with overlay_path.
  add column if not exists face_rect_x double precision,
  add column if not exists face_rect_y double precision,
  add column if not exists face_rect_width double precision,
  add column if not exists face_rect_height double precision;
