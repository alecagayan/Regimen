-- Regimen — per-product typical dose
--
-- Run this in the Supabase SQL Editor *after* schema.sql, catalog.sql, and
-- layering.sql. Adds `typical_dose_ml` to `products` — how much of *this*
-- product gets used per application, replacing the old flat 0.5 mL guess
-- that was applied to every product regardless of type. Backfills existing
-- rows with a sensible default per their `layer_category` (matches
-- `LayerCategory.defaultDoseML` in the app) rather than leaving them all at
-- one number.
--
-- This file is not part of the Xcode target — it's a reference script for
-- the Supabase dashboard, not app source.

alter table public.products
  add column typical_dose_ml double precision not null default 0.5;

update public.products set typical_dose_ml = case layer_category
  when 'Cleanser' then 2.0
  when 'Toner' then 1.0
  when 'Treatment' then 0.5
  when 'Eye Care' then 0.2
  when 'Moisturizer' then 1.5
  when 'Facial Oil' then 0.4
  when 'Sunscreen' then 1.25
  when 'Primer' then 0.5
  else 0.5
end;
