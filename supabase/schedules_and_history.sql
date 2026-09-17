-- Regimen — product schedules, shelf life, reactions, and empties
--
-- Run this in the Supabase SQL Editor after schema.sql and indexes.sql.
--
-- Four additions, all filling gaps in what the app could previously even
-- represent:
--
-- 1. Frequency. Every product was implicitly "every day". Real routines
--    aren't: retinoids run Mon/Wed/Fri, exfoliants twice a week. The app
--    was already *giving* advice it couldn't store -- ConflictChecker says
--    "alternate evenings" and RecommendationEngine says "start 2x a week",
--    neither of which the model could express.
--
-- 2. Shelf life. Most skincare carries a period-after-opening symbol
--    (6M, 12M). `opened_date` was already stored, so this is the missing
--    half of "is this still any good".
--
-- 3. Reactions. A place to record that skin flared on a given day, so the
--    score trend can be read against what was introduced and when.
--
-- 4. Empties. What happened to a bottle once it ran out, which is the only
--    honest signal of whether a product was actually worth using.
--
-- This file is not part of the Xcode target — it's a reference script for
-- the Supabase dashboard, not app source.

-- 1. Frequency ------------------------------------------------------------
-- Three shapes in three columns rather than jsonb, so the client decodes
-- them without a nested type. `daily` ignores the other two.
alter table public.products
  add column if not exists frequency_kind text not null default 'daily',
  -- Calendar weekday numbers, 1 = Sunday through 7 = Saturday.
  add column if not exists frequency_days_of_week integer[] not null default '{}',
  add column if not exists frequency_interval_days integer not null default 1;

-- 2. Shelf life -----------------------------------------------------------
-- Months after opening before the product is considered past its best.
-- Null means "not specified", which is different from "never expires".
alter table public.products
  add column if not exists months_after_opening integer;

-- 3. Reactions ------------------------------------------------------------
create table if not exists public.skin_reactions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  -- A whole calendar day in the user's own timezone, same reasoning as
  -- streak_restores.restored_on.
  occurred_on date not null,
  severity text not null default 'mild',
  note text,
  created_at timestamptz not null default now(),
  unique (user_id, occurred_on)
);

alter table public.skin_reactions enable row level security;

create policy "Users can manage their own reactions"
  on public.skin_reactions for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create index if not exists skin_reactions_user_idx
  on public.skin_reactions (user_id, occurred_on desc);

-- 4. Empties --------------------------------------------------------------
-- One row per finished bottle. Kept separate from `products` so a
-- repurchase of the same product accumulates history instead of
-- overwriting it.
create table if not exists public.product_empties (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  -- Deliberately not a foreign key: the record of having finished a bottle
  -- should outlive deleting the product from the cabinet.
  product_id uuid,
  product_name text not null,
  brand text not null default '',
  finished_on date not null default current_date,
  would_repurchase boolean,
  rating integer,
  note text,
  created_at timestamptz not null default now()
);

alter table public.product_empties enable row level security;

create policy "Users can manage their own empties"
  on public.product_empties for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create index if not exists product_empties_user_idx
  on public.product_empties (user_id, finished_on desc);

-- 5. Catalog ingredients and barcodes --------------------------------------
-- Full INCI list per catalog product. The eight hardcoded ConflictTag
-- values stay as the thing the conflict engine reasons about; this is the
-- raw list behind them, which is what makes "does anything I own contain
-- fragrance" or "is this safe in pregnancy" answerable at all.
--
-- `barcode` is what turns a scan into a prefilled form. Unique so a scan
-- resolves to exactly one row, but nullable, since most existing catalog
-- entries were curated by hand without one.
alter table public.catalog_products
  add column if not exists ingredients text[] not null default '{}',
  add column if not exists barcode text;

create unique index if not exists catalog_products_barcode_idx
  on public.catalog_products (barcode)
  where barcode is not null;
