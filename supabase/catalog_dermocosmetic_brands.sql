-- Regimen — catalog: European dermocosmetic brands
--
-- Run this in the Supabase SQL Editor after multi_tag_conflicts.sql (this
-- file inserts directly into the `suggested_conflict_tags` array and
-- `layer_category` columns that migration adds).
--
-- Adds four pharmacy-brand skincare lines (Bioderma, Avène, Eucerin,
-- Uriage) -- internationally available, not just French despite the
-- French-market origin, and widely sold in the US through Walmart, Amazon,
-- and pharmacies. Sourced from these brands' own well-documented flagship
-- formulas, not from any bulk dataset -- an Open Beauty Facts export was
-- evaluated first but had zero coverage of this app's existing brands and
-- only ~20 usable (non-empty, English, actually-facial) rows total across
-- everything, too thin to be worth pulling from. Kept deliberately
-- conservative: several of these brands' treatment-line hero ingredients
-- (e.g. Eucerin's thiamidol) don't map to any tag in this app's closed
-- `ConflictTag` set, so those products are included with no tag rather
-- than forced into the wrong one.
--
-- This file is not part of the Xcode target — it's a reference script for
-- the Supabase dashboard, not app source.

insert into public.catalog_products (brand, name, category, suggested_conflict_tags, layer_category, description) values

-- ============================================================
-- Bioderma
-- ============================================================
  ('Bioderma', 'Sensibio H2O Micellar Water', 'Cleansers', '{}', 'Cleanser', 'The original no-rinse micellar cleansing water, for sensitive skin.'),
  ('Bioderma', 'Sébium H2O Micellar Water', 'Cleansers', '{}', 'Cleanser', 'Micellar cleansing water formulated for oily, blemish-prone skin.'),
  ('Bioderma', 'Hydrabio H2O Micellar Water', 'Cleansers', '{}', 'Cleanser', 'Micellar cleansing water formulated for dehydrated skin.'),
  ('Bioderma', 'Sensibio Light', 'Moisturizers', '{}', 'Moisturizer', 'Lightweight daily moisturizer for sensitive skin.'),
  ('Bioderma', 'Sébium Sensitive', 'Moisturizers', '{}', 'Moisturizer', 'Soothing moisturizer for sensitive, blemish-prone skin.'),
  ('Bioderma', 'Atoderm Cream', 'Moisturizers', '{Niacinamide}', 'Moisturizer', 'Barrier-repair cream with niacinamide, for very dry to atopic-prone skin.'),
  ('Bioderma', 'Photoderm MAX SPF 50+', 'Sunscreen', '{}', 'Sunscreen', 'Broad-spectrum, very high protection sunscreen spray or fluid.'),

-- ============================================================
-- Avène
-- ============================================================
  ('Avène', 'Cleanance Cleansing Gel', 'Cleansers', '{}', 'Cleanser', 'Soap-free gel cleanser for oily, blemish-prone skin.'),
  ('Avène', 'Tolérance Extrême Cleansing Lotion', 'Cleansers', '{}', 'Cleanser', 'Minimal-ingredient, no-rinse cleansing lotion for extremely reactive skin.'),
  ('Avène', 'Cicalfate+ Restorative Protective Cream', 'Moisturizers', '{}', 'Moisturizer', 'Barrier-repair cream with thermal water, for irritated or compromised skin.'),
  ('Avène', 'Tolérance Extrême Cream', 'Moisturizers', '{}', 'Moisturizer', 'Ultra-minimal formula moisturizer for extremely sensitive or allergic skin.'),
  ('Avène', 'Hydrance Rich Hydrating Cream', 'Moisturizers', '{}', 'Moisturizer', 'Richer hydrating cream for dehydrated, sensitive skin.'),
  ('Avène', 'Very High Protection Sunscreen SPF 50+', 'Sunscreen', '{}', 'Sunscreen', 'Broad-spectrum SPF 50+ formulated for sensitive skin.'),

-- ============================================================
-- Eucerin
-- ============================================================
  ('Eucerin', 'DermatoCLEAN Micellar Cleansing Fluid', 'Cleansers', '{}', 'Cleanser', 'Micellar cleansing fluid that removes makeup without rinsing.'),
  ('Eucerin', 'Hyaluron-Filler Day Cream', 'Moisturizers', '{}', 'Moisturizer', 'Hyaluronic acid day cream aimed at fine lines and hydration.'),
  ('Eucerin', 'Hyaluron-Filler Vitamin C Booster', 'Vitamin C', '{Pure Vitamin C}', 'Treatment', 'Concentrated pure vitamin C booster, mixed into moisturizer or used alone.'),
  ('Eucerin', 'AtoControl Face Cream', 'Moisturizers', '{}', 'Moisturizer', 'Barrier-repair face cream for very dry, atopic-prone skin.'),
  ('Eucerin', 'Oil Control Gel-Cream SPF 30', 'Sunscreen', '{}', 'Sunscreen', 'Mattifying, oil-free SPF 30 for oily and blemish-prone skin.'),

-- ============================================================
-- Uriage
-- ============================================================
  ('Uriage', 'Eau Thermale Thermal Water', 'Toners', '{}', 'Toner', 'Soothing thermal water spray, used to refresh or calm skin.'),
  ('Uriage', 'Hyséac Cleansing Gel', 'Cleansers', '{}', 'Cleanser', 'Gentle gel cleanser for oily, blemish-prone skin.'),
  ('Uriage', 'Bariéderm Cica-Cream', 'Moisturizers', '{}', 'Moisturizer', 'Barrier-repair cream with cica ingredients, for irritated or compromised skin.'),
  ('Uriage', 'Hyséac 3-Regul Local Care', 'Treatments', '{Exfoliating Acid}', 'Treatment', 'Targeted blemish treatment with salicylic-acid-derivative exfoliation.'),
  ('Uriage', 'Bariésun Sunscreen SPF 50+', 'Sunscreen', '{}', 'Sunscreen', 'Broad-spectrum, very high protection sunscreen for sensitive skin.');
