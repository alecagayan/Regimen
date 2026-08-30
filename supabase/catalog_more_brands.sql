-- Regimen — catalog: additional brands
--
-- Run this in the Supabase SQL Editor after catalog.sql, layering.sql, and
-- multi_tag_conflicts.sql (this file inserts directly into the
-- `suggested_conflict_tags` array and `layer_category` columns those add,
-- rather than needing a separate update pass the way catalog.sql's
-- original The-Ordinary-only seed did).
--
-- Adds five widely-available brands spanning drugstore to mid-range, so
-- the catalog isn't The-Ordinary-only. Active-ingredient tagging reflects
-- each product's commonly documented flagship formula (own-brand product
-- pages, INCI listings) at the time this was written -- brands do
-- reformulate, so treat this as a reasonable-effort baseline, the same
-- caveat the app already carries about the skin score's own accuracy.
-- Only *leave-on* products (treatments, moisturizers, serums) are tagged;
-- rinse-off cleansers aren't, matching how catalog.sql already treats The
-- Ordinary's own cleansers -- a product that's washed off within a minute
-- isn't part of a same-routine layering conflict the way a leave-on
-- product is.
--
-- This file is not part of the Xcode target — it's a reference script for
-- the Supabase dashboard, not app source.

insert into public.catalog_products (brand, name, category, suggested_conflict_tags, layer_category, description) values

-- ============================================================
-- CeraVe
-- ============================================================
  ('CeraVe', 'Foaming Facial Cleanser', 'Cleansers', '{}', 'Cleanser', 'Foaming gel cleanser with ceramides and niacinamide, for normal to oily skin.'),
  ('CeraVe', 'Hydrating Facial Cleanser', 'Cleansers', '{}', 'Cleanser', 'Non-foaming cream cleanser with ceramides and hyaluronic acid, for normal to dry skin.'),
  ('CeraVe', 'Daily Moisturizing Lotion', 'Moisturizers', '{}', 'Moisturizer', 'Lightweight, oil-free lotion with three essential ceramides and hyaluronic acid.'),
  ('CeraVe', 'Moisturizing Cream', 'Moisturizers', '{}', 'Moisturizer', 'Richer, jar-packaged version of the lotion for drier skin — same ceramide base.'),
  ('CeraVe', 'PM Facial Moisturizing Lotion', 'Moisturizers', '{Niacinamide}', 'Moisturizer', 'Lightweight night moisturizer with niacinamide, ceramides, and hyaluronic acid.'),
  ('CeraVe', 'AM Facial Moisturizing Lotion SPF 30', 'Sunscreen', '{}', 'Sunscreen', 'Daily broad-spectrum SPF 30 moisturizer with ceramides and hyaluronic acid.'),
  ('CeraVe', 'Skin Renewing Vitamin C Serum', 'Vitamin C', '{Pure Vitamin C}', 'Treatment', '10% L-ascorbic acid serum with hyaluronic acid and ceramides.'),
  ('CeraVe', 'Resurfacing Retinol Serum', 'Retinoids', '{Retinoid,Niacinamide}', 'Treatment', 'Encapsulated retinol with niacinamide and licochalcone A to offset irritation.'),
  ('CeraVe', 'Hydrating Hyaluronic Acid Serum', 'Hydrators', '{}', 'Treatment', 'Hyaluronic acid and vitamin B5 serum with ceramides, no exfoliating or brightening actives.'),
  ('CeraVe', 'Eye Repair Cream', 'Eye Care', '{Niacinamide}', 'Eye Care', 'Fragrance-free eye cream with niacinamide, hyaluronic acid, and ceramides.'),

-- ============================================================
-- La Roche-Posay
-- ============================================================
  ('La Roche-Posay', 'Toleriane Hydrating Gentle Cleanser', 'Cleansers', '{}', 'Cleanser', 'Fragrance-free, soap-free cream cleanser formulated for sensitive skin.'),
  ('La Roche-Posay', 'Effaclar Purifying Foaming Gel', 'Cleansers', '{}', 'Cleanser', 'Foaming gel cleanser for oily, blemish-prone skin.'),
  ('La Roche-Posay', 'Toleriane Double Repair Moisturizer', 'Moisturizers', '{Niacinamide}', 'Moisturizer', 'Ceramide and niacinamide moisturizer with prebiotic thermal water, for sensitive skin.'),
  ('La Roche-Posay', 'Anthelios Melt-in Milk Sunscreen SPF 60', 'Sunscreen', '{}', 'Sunscreen', 'Broad-spectrum SPF 60 body-and-face sunscreen with a lightweight milk texture.'),
  ('La Roche-Posay', 'Anthelios Ultra-Light Fluid SPF 60', 'Sunscreen', '{}', 'Sunscreen', 'Oil-free, matte-finish SPF 60 fluid for daily wear under makeup.'),
  ('La Roche-Posay', 'Hyalu B5 Serum', 'Hydrators', '{}', 'Treatment', 'Hyaluronic acid and vitamin B5 serum aimed at plumping and repairing the moisture barrier.'),
  ('La Roche-Posay', 'Pure Vitamin C10 Serum', 'Vitamin C', '{Pure Vitamin C}', 'Treatment', '10% pure vitamin C serum with neurosensine, formulated for first-time vitamin C users.'),
  ('La Roche-Posay', 'Retinol B3 Serum', 'Retinoids', '{Retinoid,Niacinamide}', 'Treatment', 'Pure retinol paired with vitamin B3 (niacinamide) to help offset dryness and irritation.'),
  ('La Roche-Posay', 'Effaclar Duo (+)', 'Treatments', '{Benzoyl Peroxide}', 'Treatment', '5.5% benzoyl peroxide leave-on treatment for blemishes and post-acne marks.'),
  ('La Roche-Posay', 'Redermic R Retinol Concentrate', 'Retinoids', '{Retinoid}', 'Treatment', 'Pure retinol anti-aging concentrate for fine lines and uneven texture.'),

-- ============================================================
-- Paula's Choice
-- ============================================================
  ('Paula''s Choice', 'CALM Redness Relief Cleanser', 'Cleansers', '{}', 'Cleanser', 'Fragrance-free, oil-based cleanser formulated for redness-prone and sensitive skin.'),
  ('Paula''s Choice', 'Skin Recovery Enzyme Cleanser', 'Cleansers', '{}', 'Cleanser', 'Creamy, non-foaming cleanser for very dry or compromised skin.'),
  ('Paula''s Choice', 'Skin Perfecting 2% BHA Liquid Exfoliant', 'Direct Acids / Exfoliants', '{Exfoliating Acid}', 'Treatment', '2% salicylic acid leave-on exfoliant for texture, blackheads, and clogged pores.'),
  ('Paula''s Choice', 'Skin Perfecting 8% AHA Gel', 'Direct Acids / Exfoliants', '{Exfoliating Acid}', 'Treatment', '8% glycolic acid gel exfoliant for surface texture and dullness.'),
  ('Paula''s Choice', '10% Niacinamide Booster', 'Niacinamide & Other Actives', '{Niacinamide}', 'Treatment', 'Concentrated niacinamide booster aimed at pores, tone, and oil control.'),
  ('Paula''s Choice', 'C15 Super Booster', 'Vitamin C', '{Pure Vitamin C}', 'Treatment', '15% L-ascorbic acid booster for brightening and dark spots.'),
  ('Paula''s Choice', 'Resist 1% Retinol Booster', 'Retinoids', '{Retinoid}', 'Treatment', '1% pure retinol booster, meant to be mixed into or layered under moisturizer.'),
  ('Paula''s Choice', 'Omega+ Complex Moisturizer', 'Moisturizers', '{}', 'Moisturizer', 'Barrier-repair moisturizer with omega fatty acids and ceramides, no active exfoliants.'),

-- ============================================================
-- Neutrogena
-- ============================================================
  ('Neutrogena', 'Hydro Boost Cleansing Gel', 'Cleansers', '{}', 'Cleanser', 'Hyaluronic acid gel cleanser that rinses clean without stripping.'),
  ('Neutrogena', 'Oil-Free Acne Wash', 'Cleansers', '{}', 'Cleanser', 'Salicylic acid acne cleanser for oily, blemish-prone skin.'),
  ('Neutrogena', 'Hydro Boost Water Gel', 'Moisturizers', '{}', 'Moisturizer', 'Oil-free, hyaluronic acid water-gel moisturizer for normal to oily skin.'),
  ('Neutrogena', 'Ultra Sheer Dry-Touch Sunscreen SPF 55', 'Sunscreen', '{}', 'Sunscreen', 'Lightweight, non-greasy broad-spectrum SPF 55 for daily wear.'),
  ('Neutrogena', 'Rapid Wrinkle Repair Retinol Serum', 'Retinoids', '{Retinoid}', 'Treatment', 'Retinol SA (retinol + hyaluronic acid) serum aimed at fine lines and texture.'),
  ('Neutrogena', 'Bright Boost Serum', 'Vitamin C', '{Vitamin C Derivative}', 'Treatment', 'Neoglucosamine and vitamin C derivative complex aimed at brightening and radiance.'),

-- ============================================================
-- Vanicream — fragrance-free, minimal-ingredient, aimed at very sensitive
-- or reactive skin; deliberately no actives across the line.
-- ============================================================
  ('Vanicream', 'Gentle Facial Cleanser', 'Cleansers', '{}', 'Cleanser', 'Fragrance-free, soap-free cleanser for sensitive and easily irritated skin.'),
  ('Vanicream', 'Daily Facial Moisturizer SPF 30', 'Sunscreen', '{}', 'Sunscreen', 'Mineral-forward, fragrance-free SPF 30 moisturizer for sensitive skin.'),
  ('Vanicream', 'Moisturizing Cream', 'Moisturizers', '{}', 'Moisturizer', 'Fragrance-free, dye-free cream for very dry or reactive skin.'),
  ('Vanicream', 'Lite Lotion', 'Moisturizers', '{}', 'Moisturizer', 'A lighter, fragrance-free lotion version of the moisturizing cream.');
