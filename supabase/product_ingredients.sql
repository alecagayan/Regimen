-- Regimen — ingredient lists on the user's own products
--
-- Run this in the Supabase SQL Editor after schedules_and_history.sql.
--
-- `schedules_and_history.sql` added `ingredients` to catalog_products but
-- not to products, which left the barcode scanner pulling a full INCI list
-- and then dropping it on the floor: ProductEditView held it in local
-- state with nowhere to write it. This is the missing half.
--
-- Storing the list per-product rather than only per-catalog-entry matters
-- because most cabinets contain things the catalog has never heard of --
-- a barcode lookup against Open Beauty Facts returns ingredients for
-- products that have no catalog row at all, and that's exactly the case
-- where the user most needs the app to tell them what's in it.
--
-- This file is not part of the Xcode target — it's a reference script for
-- the Supabase dashboard, not app source.

alter table public.products
  add column if not exists ingredients text[] not null default '{}';
