-- Regimen — layering / application order
--
-- Run this in the Supabase SQL Editor *after* schema.sql and catalog.sql.
-- Adds a `layer_category` column to both `products` and `catalog_products`
-- — the canonical skincare-layering step a product belongs to (cleanser,
-- toner, treatment, eye care, moisturizer, facial oil, sunscreen, primer).
-- The app uses this to compute a recommended application order instead of
-- trusting only the user's manually-typed `application_order`, which is
-- now a same-step tiebreaker rather than the sole ordering signal.
--
-- This file is not part of the Xcode target — it's a reference script for
-- the Supabase dashboard, not app source.

alter table public.products
  add column layer_category text not null default 'Treatment';

alter table public.catalog_products
  add column layer_category text not null default 'Treatment';

-- ============================================================
-- Assign layer categories to the seeded "The Ordinary" catalog.
-- Everything not listed below keeps the 'Treatment' default, which is
-- correct for the great majority of actives/serums.
-- ============================================================

-- Cleansers
update public.catalog_products set layer_category = 'Cleanser'
where name in (
  'Squalane Cleanser',
  'Glucoside Foaming Cleanser',
  'Glycolipid Cream Cleanser'
);

-- Toners (specifically the active/exfoliating toners — not a general
-- "hydrating toner" category The Ordinary doesn't really have)
update public.catalog_products set layer_category = 'Toner'
where name in (
  'Glycolic Acid 7% Exfoliating Toner',
  'Saccharomyces Ferment 30% Milky Toner'
);

-- Eye care
update public.catalog_products set layer_category = 'Eye Care'
where name in (
  'Multi-Peptide Eye Serum',
  'Caffeine Solution 5% + EGCG Eye Serum',
  'Lacto-PDRN 4% + B9 Firming Eye Cream'
);

-- Moisturizers (the products literally named as moisturizers — hydrating
-- serums like plain Hyaluronic Acid stay 'Treatment', since they're worn
-- under a moisturizer, not as one)
update public.catalog_products set layer_category = 'Moisturizer'
where name in (
  'Natural Moisturizing Factors + HA',
  'Natural Moisturizing Factors + PhytoCeramides',
  'Natural Moisturizing Factors + Beta Glucan',
  'Rice Lipids & Ectoin Moisturizer'
);

-- Facial oils (always last among skincare — before sunscreen in the AM,
-- last step at night)
update public.catalog_products set layer_category = 'Facial Oil'
where name in (
  'Moroccan Argan Oil',
  'Marula Oil',
  'Rose Hip Seed Oil',
  'Fermented Rose Hip Seed Oil',
  '100% Plant-Derived Squalane',
  '"B" Oil'
);

-- Sunscreen
update public.catalog_products set layer_category = 'Sunscreen'
where name in (
  'SPF UV Filters 45'
);

-- Primer/makeup — applied after skincare and sunscreen
update public.catalog_products set layer_category = 'Primer'
where name in (
  'Serum Foundation',
  'High-Adherence Silicone Primer',
  'High-Spreadability Fluid Primer',
  'Clear Mascara (Lash & Curl Finisher)'
);
