-- Regimen — product catalog
--
-- Run this in the Supabase SQL Editor *after* schema.sql. It adds a
-- `catalog_products` reference table (brand + product name + a suggested
-- conflict tag) that every signed-in user can read but nobody can write to
-- through the app — it's maintained here, not through the UI. The "Add
-- Product" screen searches this table to pre-fill name/brand/conflict tag;
-- picking a result still creates a normal row in the user's own `products`
-- table, scoped to them like any manually-typed product.
--
-- This file is not part of the Xcode target — it's a reference script for
-- the Supabase dashboard, not app source.

create table public.catalog_products (
  id uuid primary key default gen_random_uuid(),
  brand text not null,
  name text not null,
  category text,
  suggested_conflict_tag text not null default 'None',
  created_at timestamptz not null default now()
);

alter table public.catalog_products enable row level security;

-- Reference data, not user data — readable by anyone, writable by nobody
-- through the API (no insert/update/delete policy exists, so those are
-- denied by default with RLS on).
create policy "Catalog is publicly readable"
  on public.catalog_products for select
  using (true);

-- ============================================================
-- Seed data: The Ordinary
-- ============================================================
insert into public.catalog_products (brand, name, category, suggested_conflict_tag) values
  -- Peptides
  ('The Ordinary', 'Multi-Peptide + HA Serum (Buffet)', 'Peptides', 'None'),
  ('The Ordinary', 'Multi-Peptide + Copper Peptides 1% Serum', 'Peptides', 'Copper Peptide'),
  ('The Ordinary', 'Multi-Peptide Eye Serum', 'Peptides', 'None'),
  ('The Ordinary', 'Argireline Solution 10%', 'Peptides', 'None'),
  ('The Ordinary', 'Matrixyl 10% + HA', 'Peptides', 'None'),

  -- Hydrators / Moisturizers
  ('The Ordinary', 'Hyaluronic Acid 2% + B5', 'Hydrators / Moisturizers', 'None'),
  ('The Ordinary', 'Hyaluronic Acid 2% + B5 (with Ceramides)', 'Hydrators / Moisturizers', 'None'),
  ('The Ordinary', 'Marine Hyaluronics', 'Hydrators / Moisturizers', 'None'),
  ('The Ordinary', 'Amino Acids + B5', 'Hydrators / Moisturizers', 'None'),
  ('The Ordinary', 'Soothing & Barrier Support Serum', 'Hydrators / Moisturizers', 'None'),
  ('The Ordinary', 'Natural Moisturizing Factors + HA', 'Hydrators / Moisturizers', 'None'),
  ('The Ordinary', 'Natural Moisturizing Factors + PhytoCeramides', 'Hydrators / Moisturizers', 'None'),
  ('The Ordinary', 'Natural Moisturizing Factors + Beta Glucan', 'Hydrators / Moisturizers', 'None'),

  -- Oils
  ('The Ordinary', 'Moroccan Argan Oil', 'Oils', 'None'),
  ('The Ordinary', 'Marula Oil', 'Oils', 'None'),
  ('The Ordinary', 'Rose Hip Seed Oil', 'Oils', 'None'),
  ('The Ordinary', 'Fermented Rose Hip Seed Oil', 'Oils', 'None'),
  ('The Ordinary', '100% Plant-Derived Squalane', 'Oils', 'None'),
  ('The Ordinary', '"B" Oil', 'Oils', 'None'),

  -- Retinoids
  ('The Ordinary', 'Retinal 0.2% Emulsion', 'Retinoids', 'Retinoid'),
  ('The Ordinary', 'Granactive Retinoid 2% Emulsion', 'Retinoids', 'Retinoid'),
  ('The Ordinary', 'Granactive Retinoid 5% in Squalane', 'Retinoids', 'Retinoid'),
  ('The Ordinary', 'Retinol 0.2% in Squalane', 'Retinoids', 'Retinoid'),
  ('The Ordinary', 'Retinol 0.5% in Squalane', 'Retinoids', 'Retinoid'),
  ('The Ordinary', 'Retinol 1% in Squalane', 'Retinoids', 'Retinoid'),

  -- Antioxidants
  ('The Ordinary', 'EUK 134 0.1%', 'Antioxidants', 'None'),
  ('The Ordinary', 'Resveratrol 3% + Ferulic Acid 3%', 'Antioxidants', 'None'),
  ('The Ordinary', 'Pycnogenol 5%', 'Antioxidants', 'None'),
  ('The Ordinary', 'Multi-Antioxidant Radiance Serum', 'Antioxidants', 'None'),

  -- Direct Acids / Exfoliants
  ('The Ordinary', 'AHA 30% + BHA 2% Peeling Solution', 'Direct Acids / Exfoliants', 'Exfoliating Acid'),
  ('The Ordinary', 'Azelaic Acid Suspension 10%', 'Direct Acids / Exfoliants', 'Exfoliating Acid'),
  ('The Ordinary', 'Glycolic Acid 7% Exfoliating Toner', 'Direct Acids / Exfoliants', 'Exfoliating Acid'),
  ('The Ordinary', 'Lactic Acid 5%', 'Direct Acids / Exfoliants', 'Exfoliating Acid'),
  ('The Ordinary', 'Lactic Acid 10% + HA', 'Direct Acids / Exfoliants', 'Exfoliating Acid'),
  ('The Ordinary', 'Salicylic Acid 2% Solution', 'Direct Acids / Exfoliants', 'Exfoliating Acid'),
  ('The Ordinary', 'Salicylic Acid 2% Masque', 'Direct Acids / Exfoliants', 'Exfoliating Acid'),
  ('The Ordinary', 'Salicylic Acid 2% Anhydrous Solution', 'Direct Acids / Exfoliants', 'Exfoliating Acid'),
  ('The Ordinary', 'Mandelic Acid 10% + HA', 'Direct Acids / Exfoliants', 'Exfoliating Acid'),

  -- Vitamin C
  ('The Ordinary', 'Ascorbyl Glucoside Solution 12%', 'Vitamin C', 'Vitamin C Derivative'),
  ('The Ordinary', 'Ascorbyl Tetraisopalmitate Solution 20% in Vitamin F', 'Vitamin C', 'Vitamin C Derivative'),
  ('The Ordinary', 'Vitamin C Suspension 23% + HA Spheres 2%', 'Vitamin C', 'Pure Vitamin C'),
  ('The Ordinary', 'L-Ascorbic Acid Powder', 'Vitamin C', 'Pure Vitamin C'),
  ('The Ordinary', 'Ethylated Ascorbic Acid 15% Solution', 'Vitamin C', 'Vitamin C Derivative'),

  -- Niacinamide & Other Actives
  ('The Ordinary', 'Niacinamide 10% + Zinc 1%', 'Niacinamide & Other Actives', 'Niacinamide'),
  ('The Ordinary', 'Niacinamide Powder', 'Niacinamide & Other Actives', 'Niacinamide'),
  ('The Ordinary', 'Alpha Arbutin 2% + HA', 'Niacinamide & Other Actives', 'None'),
  ('The Ordinary', 'Caffeine Solution 5% + EGCG Eye Serum', 'Niacinamide & Other Actives', 'None'),
  ('The Ordinary', 'Caffeine 3% + Escin 1% Face Serum', 'Niacinamide & Other Actives', 'None'),
  ('The Ordinary', 'Aloe 2% + NAG 2%', 'Niacinamide & Other Actives', 'None'),
  ('The Ordinary', 'GF 15% Solution (Growth Factors)', 'Niacinamide & Other Actives', 'None'),
  ('The Ordinary', 'Saccharomyces Ferment 30% Milky Toner', 'Niacinamide & Other Actives', 'None'),
  ('The Ordinary', 'Multi-Active Delivery Essence', 'Niacinamide & Other Actives', 'None'),
  ('The Ordinary', 'Balancing & Clarifying Serum', 'Niacinamide & Other Actives', 'None'),
  ('The Ordinary', 'Volufiline 92% + Pal-Isoleucine 1% Plumping Serum', 'Niacinamide & Other Actives', 'None'),

  -- Cleansers
  ('The Ordinary', 'Squalane Cleanser', 'Cleansers', 'None'),
  ('The Ordinary', 'Glucoside Foaming Cleanser', 'Cleansers', 'None'),
  ('The Ordinary', 'Glycolipid Cream Cleanser', 'Cleansers', 'None'),

  -- Hair & Scalp
  ('The Ordinary', 'Multi-Peptide Serum for Hair Density', 'Hair & Scalp', 'None'),
  ('The Ordinary', 'Natural Moisturizing Factors + HA for Scalp', 'Hair & Scalp', 'None'),
  ('The Ordinary', 'Sulfate 4% Shampoo', 'Hair & Scalp', 'None'),
  ('The Ordinary', 'Behentrimonium Chloride 2% Conditioner', 'Hair & Scalp', 'None'),
  ('The Ordinary', 'Lash & Brow Serum', 'Hair & Scalp', 'None'),

  -- Makeup / Primers
  ('The Ordinary', 'Serum Foundation', 'Makeup / Primers', 'None'),
  ('The Ordinary', 'High-Adherence Silicone Primer', 'Makeup / Primers', 'None'),
  ('The Ordinary', 'High-Spreadability Fluid Primer', 'Makeup / Primers', 'None'),
  ('The Ordinary', 'Clear Mascara (Lash & Curl Finisher)', 'Makeup / Primers', 'None'),

  -- Newer additions
  ('The Ordinary', 'Lacto-PDRN 4% + B9 Firming Eye Cream', 'Newer Additions', 'None'),
  ('The Ordinary', 'Rice Lipids & Ectoin Moisturizer', 'Newer Additions', 'None'),
  ('The Ordinary', 'Sulfur 10% Powder to Cream Concentrate', 'Newer Additions', 'None'),
  ('The Ordinary', 'SPF UV Filters 45', 'Newer Additions', 'None'),
  ('The Ordinary', 'PHA 5% Exfoliating Lip Serum', 'Newer Additions', 'Exfoliating Acid'),
  ('The Ordinary', 'Volufiline 92% Lip Exfoliating Serum', 'Newer Additions', 'None');
