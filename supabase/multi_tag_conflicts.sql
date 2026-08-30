-- Regimen — multiple active ingredients per product
--
-- Run this in the Supabase SQL Editor after schema.sql, catalog.sql, and
-- layering.sql. Replaces the single `conflict_tag` column (on both
-- `products` and `catalog_products`) with a `conflict_tags` array.
--
-- Why: expanding the catalog beyond The Ordinary (which markets almost
-- every product as a single active) surfaced real products that combine
-- more than one flaggable ingredient -- a moisturizer with niacinamide AND
-- ceramides, a serum with a retinoid AND niacinamide. A single tag column
-- forces picking just one, which silently drops real conflicts sitting on
-- a product's second ingredient. See `ConflictTag` and `ConflictChecker`
-- in the app for how the array is used.
--
-- The old `conflict_tag` columns are left in place (unread by the app
-- going forward) rather than dropped, matching this project's existing
-- pattern for superseded columns (see skin_score.sql / skin_scores.sql) --
-- dropping a column is a one-way door, and there's no cost to leaving it.
--
-- This file is not part of the Xcode target — it's a reference script for
-- the Supabase dashboard, not app source.

alter table public.products
  add column conflict_tags text[] not null default '{}';

update public.products
set conflict_tags = case when conflict_tag = 'None' then '{}' else array[conflict_tag] end;

alter table public.catalog_products
  add column suggested_conflict_tags text[] not null default '{}',
  add column description text;

update public.catalog_products
set suggested_conflict_tags = case when suggested_conflict_tag = 'None' then '{}' else array[suggested_conflict_tag] end;

create index products_conflict_tags_idx on public.products using gin (conflict_tags);
create index catalog_products_conflict_tags_idx on public.catalog_products using gin (suggested_conflict_tags);
