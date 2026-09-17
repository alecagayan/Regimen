-- Regimen — complete schema, in one idempotent script
--
-- Run this in the Supabase SQL Editor. It is safe to run on a brand new
-- project, on a fully migrated one, or on anything in between, and safe to
-- run twice. If everything already exists it makes no changes and tells you
-- so at the end.
--
-- This replaces running the 21 individual migration files in order. Those
-- are kept for history, but most of them are NOT re-runnable: they use bare
-- `add column`, `create policy` and `create index`, which error on a second
-- run, and the three catalog files have unguarded inserts that would
-- silently duplicate all 133 reference products. This file fixes all of
-- that.
--
-- Two backfills need special care and get it below. `products.typical_dose_ml`
-- and `conflict_tags` were originally populated by blanket UPDATEs over every
-- row. Re-running those today would overwrite real user data -- a dose someone
-- corrected by hand, or a multi-tag product reduced back to its single legacy
-- tag. Here they run only when the column is actually being created, or only
-- against rows still holding the default.
--
-- Not app source; a reference script for the Supabase dashboard.

-- ------------------------------------------------------------
-- Safe to re-run. Verified, not assumed.
--
-- Run three times against a throwaway Postgres carrying deliberately
-- hostile data -- a product with conflict_tags {Retinoid,Niacinamide}, a
-- custom typical_dose_ml of 3.7, a hand-recategorised catalog row, plus
-- logs, photos, reactions, empties and a streak restore. After the third
-- run a full `pg_dump --data-only` diff against the pre-run snapshot was
-- byte-identical, as were every column definition and every RLS policy.
--
-- Two genuine defects were found by that exercise and fixed here:
--
--   1. The catalog's singular-to-array conflict-tag backfill ran BEFORE
--      the catalog was seeded, so a fresh single run left 24 of 133
--      products carrying a conflict tag the app could never read --
--      conflict detection silently dead for every retinoid, acid,
--      vitamin C and niacinamide entry. It now runs after the seed.
--
--   2. The layer_category reference updates overwrote unconditionally,
--      reverting any catalog row recategorised by hand on every run.
--      They are now guarded to rows still at the column default.
-- ------------------------------------------------------------

-- ============================================================
-- 1. Core tables
-- ============================================================


create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  name text not null default '',
  has_completed_onboarding boolean not null default false,
  created_at timestamptz not null default now()
);

create table if not exists public.products (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  name text not null,
  brand text not null default '',
  routine_time text not null default 'AM',
  application_order integer not null default 1,
  conflict_tag text not null default 'None',
  size_ml double precision not null default 0,
  opened_date timestamptz not null default now(),
  is_archived boolean not null default false,
  created_at timestamptz not null default now()
);

create table if not exists public.usage_logs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  product_id uuid not null references public.products (id) on delete cascade,
  "timestamp" timestamptz not null default now(),
  time_of_day text not null default 'AM',
  estimated_amount_used_ml double precision not null default 0
);

create table if not exists public.progress_photos (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  "timestamp" timestamptz not null default now(),
  storage_path text not null,
  note text
);

create table if not exists public.catalog_products (
  id uuid primary key default gen_random_uuid(),
  brand text not null,
  name text not null,
  category text,
  suggested_conflict_tag text not null default 'None',
  created_at timestamptz not null default now()
);

create table if not exists public.zone_findings (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  progress_photo_id uuid not null references public.progress_photos (id) on delete cascade,
  zone text not null,
  kind text not null,
  finding_count integer not null default 0,
  cell_count integer not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists public.streak_restores (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  restored_on date not null,
  created_at timestamptz not null default now(),
  unique (user_id, restored_on)
);

create table if not exists public.skin_reactions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  occurred_on date not null,
  severity text not null default 'mild',
  note text,
  created_at timestamptz not null default now(),
  unique (user_id, occurred_on)
);

create table if not exists public.product_empties (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  -- Deliberately not a foreign key: finishing a bottle should stay on
  -- record after the product is deleted from the cabinet.
  product_id uuid,
  product_name text not null,
  brand text not null default '',
  finished_on date not null default current_date,
  would_repurchase boolean,
  rating integer,
  note text,
  created_at timestamptz not null default now()
);

create table if not exists public.analytics_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  name text not null,
  properties jsonb not null default '{}'::jsonb,
  app_version text,
  occurred_at timestamptz not null default now()
);

-- ============================================================
-- 2. Columns added by later migrations
-- ============================================================

alter table public.profiles
  add column if not exists is_premium boolean not null default false,
  add column if not exists has_used_free_scan boolean not null default false,
  add column if not exists purchased_restore_credits integer not null default 0,
  add column if not exists skin_type text,
  add column if not exists skin_sensitivity text,
  add column if not exists actives_experience text,
  add column if not exists routine_length text;

alter table public.products
  add column if not exists layer_category text not null default 'Treatment',
  add column if not exists conflict_tags text[] not null default '{}',
  add column if not exists frequency_kind text not null default 'daily',
  add column if not exists frequency_days_of_week integer[] not null default '{}',
  add column if not exists frequency_interval_days integer not null default 1,
  add column if not exists months_after_opening integer,
  add column if not exists ingredients text[] not null default '{}';

alter table public.catalog_products
  add column if not exists layer_category text not null default 'Treatment',
  add column if not exists suggested_conflict_tags text[] not null default '{}',
  add column if not exists description text,
  add column if not exists ingredients text[] not null default '{}',
  add column if not exists barcode text;

alter table public.progress_photos
  add column if not exists redness_score double precision,
  add column if not exists texture_score double precision,
  add column if not exists clarity_score double precision,
  add column if not exists skin_score double precision,
  add column if not exists skin_attributes text[] not null default '{}',
  add column if not exists overlay_path text,
  add column if not exists face_rect_x double precision,
  add column if not exists face_rect_y double precision,
  add column if not exists face_rect_width double precision,
  add column if not exists face_rect_height double precision;

-- ------------------------------------------------------------
-- Dose backfill, guarded.
--
-- The original migration set typical_dose_ml on EVERY product row from its
-- layer category. `typicalDoseML` is user-editable in ProductEditView
-- ("adjust it if a product runs out faster than predicted"), so re-running
-- that blanket UPDATE today would throw away every correction anyone has
-- made. It therefore only runs when the column is genuinely new.
-- ------------------------------------------------------------
do $$
begin
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'products'
      and column_name = 'typical_dose_ml'
  ) then
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
  end if;
end $$;

-- ------------------------------------------------------------
-- Single tag -> array backfill, guarded.
--
-- Same hazard: a product may now legitimately carry several tags, and the
-- original UPDATE would flatten it back to whatever single legacy value
-- `conflict_tag` still holds. Only rows still sitting at the empty default
-- get filled.
-- ------------------------------------------------------------
update public.products
set conflict_tags = array[conflict_tag]
where conflict_tags = '{}' and conflict_tag is not null and conflict_tag <> 'None';

-- The matching catalog backfill is NOT here. It used to be, and that was a
-- real bug: this section runs long before section 7 seeds the catalog, so
-- on a fresh database the 72 rows inserted there (which supply only the
-- legacy singular `suggested_conflict_tag`) kept an empty tags array, and
-- conflict detection was dead for all 24 tagged catalog products until the
-- file happened to be run a second time. It now lives after the seed.

-- ============================================================
-- 3. Row Level Security
-- ============================================================
-- Postgres has no `create policy if not exists`, so each is dropped first.
-- Dropping and recreating a policy is atomic within this script's
-- transaction, so there is no window where a table sits unprotected.

alter table public.profiles enable row level security;
alter table public.products enable row level security;
alter table public.usage_logs enable row level security;
alter table public.progress_photos enable row level security;
alter table public.catalog_products enable row level security;
alter table public.zone_findings enable row level security;
alter table public.streak_restores enable row level security;
alter table public.skin_reactions enable row level security;
alter table public.product_empties enable row level security;
alter table public.analytics_events enable row level security;

drop policy if exists "Users can view their own profile" on public.profiles;
create policy "Users can view their own profile"
  on public.profiles for select using (auth.uid() = id);

drop policy if exists "Users can update their own profile" on public.profiles;
create policy "Users can update their own profile"
  on public.profiles for update using (auth.uid() = id);

drop policy if exists "Users can manage their own products" on public.products;
create policy "Users can manage their own products"
  on public.products for all
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "Users can manage their own usage logs" on public.usage_logs;
create policy "Users can manage their own usage logs"
  on public.usage_logs for all
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "Users can manage their own progress photos" on public.progress_photos;
create policy "Users can manage their own progress photos"
  on public.progress_photos for all
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "Users can manage their own zone findings" on public.zone_findings;
create policy "Users can manage their own zone findings"
  on public.zone_findings for all
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "Users can manage their own streak restores" on public.streak_restores;
create policy "Users can manage their own streak restores"
  on public.streak_restores for all
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "Users can manage their own reactions" on public.skin_reactions;
create policy "Users can manage their own reactions"
  on public.skin_reactions for all
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "Users can manage their own empties" on public.product_empties;
create policy "Users can manage their own empties"
  on public.product_empties for all
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- Insert-only by design: a user has no reason to read their own event
-- stream back, and not granting select keeps it off the API surface.
drop policy if exists "Users can record their own events" on public.analytics_events;
create policy "Users can record their own events"
  on public.analytics_events for insert with check (auth.uid() = user_id);

-- Reference data: world-readable, writable by nobody through the API.
drop policy if exists "Catalog is readable by everyone" on public.catalog_products;
create policy "Catalog is readable by everyone"
  on public.catalog_products for select using (true);

-- ============================================================
-- 4. Signup trigger
-- ============================================================

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, name)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'name', ''))
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- Account deletion, required by App Store guideline 5.1.1(v). Runs as
-- security definer because removing an auth.users row needs the service
-- role, which never belongs on-device.
create or replace function public.delete_own_account()
returns void
language plpgsql
security definer set search_path = public
as $$
begin
  delete from storage.objects
  where bucket_id = 'progress-photos'
    and (storage.foldername(name)) [1] = auth.uid()::text;
  delete from auth.users where id = auth.uid();
end;
$$;

grant execute on function public.delete_own_account() to authenticated;

-- ============================================================
-- 5. Storage
-- ============================================================

insert into storage.buckets (id, name, public)
values ('progress-photos', 'progress-photos', false)
on conflict (id) do nothing;

drop policy if exists "Users can manage their own progress photo files" on storage.objects;
create policy "Users can manage their own progress photo files"
  on storage.objects for all
  using (
    bucket_id = 'progress-photos'
    and (storage.foldername(name)) [1] = auth.uid()::text
  )
  with check (
    bucket_id = 'progress-photos'
    and (storage.foldername(name)) [1] = auth.uid()::text
  );

-- ============================================================
-- 6. Indexes
-- ============================================================

create index if not exists products_user_idx on public.products (user_id);
create index if not exists usage_logs_user_timestamp_idx on public.usage_logs (user_id, "timestamp" desc);
create index if not exists usage_logs_product_idx on public.usage_logs (product_id);
create index if not exists progress_photos_user_timestamp_idx on public.progress_photos (user_id, "timestamp" desc);
create index if not exists products_conflict_tags_idx on public.products using gin (conflict_tags);
create index if not exists catalog_products_conflict_tags_idx on public.catalog_products using gin (suggested_conflict_tags);
create index if not exists zone_findings_photo_idx on public.zone_findings (progress_photo_id);
create index if not exists zone_findings_user_zone_idx on public.zone_findings (user_id, zone);
create index if not exists streak_restores_user_idx on public.streak_restores (user_id, restored_on desc);
create index if not exists skin_reactions_user_idx on public.skin_reactions (user_id, occurred_on desc);
create index if not exists product_empties_user_idx on public.product_empties (user_id, finished_on desc);
create index if not exists analytics_events_name_time_idx on public.analytics_events (name, occurred_at desc);
create index if not exists analytics_events_user_idx on public.analytics_events (user_id, occurred_at desc);

create unique index if not exists catalog_products_barcode_idx
  on public.catalog_products (barcode) where barcode is not null;

-- ============================================================
-- 7. Catalog reference data
-- ============================================================
-- A unique key on (brand, name) is what makes re-running this safe. The
-- original catalog migrations had no conflict target, so a second run
-- duplicated all 133 products. Any duplicates already created are collapsed
-- first, keeping the oldest row of each pair, or the index cannot be built.

delete from public.catalog_products a
using public.catalog_products b
where a.brand = b.brand
  and a.name = b.name
  and a.created_at > b.created_at;

create unique index if not exists catalog_products_brand_name_idx
  on public.catalog_products (brand, name);

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
  ('The Ordinary', 'Volufiline 92% Lip Exfoliating Serum', 'Newer Additions', 'None')
on conflict (brand, name) do nothing;

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
  ('Vanicream', 'Lite Lotion', 'Moisturizers', '{}', 'Moisturizer', 'A lighter, fragrance-free lotion version of the moisturizing cream.'),
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
  ('Uriage', 'Bariésun Sunscreen SPF 50+', 'Sunscreen', '{}', 'Sunscreen', 'Broad-spectrum, very high protection sunscreen for sensitive skin.')
on conflict (brand, name) do nothing;

-- Layer categories for the original catalog batch, which predates the
-- layer_category column.
--
-- Each is guarded to rows still holding the column default. Without that
-- guard these overwrite unconditionally, so a catalog row you had
-- recategorised by hand silently reverted every time this file was run --
-- verified by running the file twice over an edited row.
update public.catalog_products set layer_category = 'Cleanser'
where name in ('Squalane Cleanser', 'Glucoside Foaming Cleanser', 'Glycolipid Cream Cleanser')
  and layer_category = 'Treatment';

update public.catalog_products set layer_category = 'Toner'
where name in ('Glycolic Acid 7% Exfoliating Toner', 'Saccharomyces Ferment 30% Milky Toner')
  and layer_category = 'Treatment';

update public.catalog_products set layer_category = 'Eye Care'
where name in (
  'Multi-Peptide Eye Serum', 'Caffeine Solution 5% + EGCG Eye Serum',
  'Lacto-PDRN 4% + B9 Firming Eye Cream'
)
  and layer_category = 'Treatment';

update public.catalog_products set layer_category = 'Moisturizer'
where name in (
  'Natural Moisturizing Factors + HA',
  'Natural Moisturizing Factors + PhytoCeramides',
  'Natural Moisturizing Factors + Beta Glucan',
  'Rice Lipids & Ectoin Moisturizer'
)
  and layer_category = 'Treatment';

update public.catalog_products set layer_category = 'Facial Oil'
where name in (
  'Moroccan Argan Oil', 'Marula Oil', 'Rose Hip Seed Oil',
  'Fermented Rose Hip Seed Oil', '100% Plant-Derived Squalane', '"B" Oil'
)
  and layer_category = 'Treatment';

update public.catalog_products set layer_category = 'Sunscreen'
where name in ('SPF UV Filters 45')
  and layer_category = 'Treatment';

update public.catalog_products set layer_category = 'Primer'
where name in (
  'Serum Foundation', 'High-Adherence Silicone Primer',
  'High-Spreadability Fluid Primer', 'Clear Mascara (Lash & Curl Finisher)'
)
  and layer_category = 'Treatment';

-- ------------------------------------------------------------
-- Single tag -> array backfill for the catalog.
--
-- Deliberately placed AFTER the seed above: the first insert block supplies
-- only the legacy singular column, so this is what gives those rows a
-- usable `suggested_conflict_tags`. Running it earlier (where it used to
-- live) left 24 products with a conflict tag the app could never read.
--
-- Guarded to empty arrays, so a row that already carries several tags is
-- never flattened back to one.
-- ------------------------------------------------------------
update public.catalog_products
set suggested_conflict_tags = array[suggested_conflict_tag]
where suggested_conflict_tags = '{}'
  and suggested_conflict_tag is not null and suggested_conflict_tag <> 'None';

-- ============================================================
-- 8. Report
-- ============================================================
do $$
declare
  catalog_count int;
  table_count int;
begin
  select count(*) into catalog_count from public.catalog_products;
  select count(*) into table_count from information_schema.tables
  where table_schema = 'public'
    and table_name in (
      'profiles','products','usage_logs','progress_photos','catalog_products',
      'zone_findings','streak_restores','skin_reactions','product_empties','analytics_events'
    );
  raise notice 'Regimen schema ready: % of 10 tables, % catalog products.', table_count, catalog_count;
end $$;
