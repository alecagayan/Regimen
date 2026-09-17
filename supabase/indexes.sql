-- Regimen — user_id indexes
--
-- Run this in the Supabase SQL Editor after schema.sql.
--
-- `schema.sql` created products, usage_logs and progress_photos with a
-- primary key and nothing else, so every query the app makes -- all of
-- which are "this user's rows", enforced by RLS's `auth.uid() = user_id`
-- -- is a sequential scan over the whole table. That's invisible while a
-- table holds a few hundred rows and gets steadily worse as the app grows;
-- usage_logs grows fastest of the three (one row per product per check-off
-- per day), so it's the one that matters most.
--
-- The composite indexes match how the app actually reads: logs are always
-- fetched per user and used newest-first, photos likewise.
--
-- This file is not part of the Xcode target — it's a reference script for
-- the Supabase dashboard, not app source.

create index if not exists products_user_idx
  on public.products (user_id);

-- Also covers the plain (user_id) lookup, so no separate index is needed.
create index if not exists usage_logs_user_timestamp_idx
  on public.usage_logs (user_id, "timestamp" desc);

-- Depletion prediction reads every log for one product.
create index if not exists usage_logs_product_idx
  on public.usage_logs (product_id);

create index if not exists progress_photos_user_timestamp_idx
  on public.progress_photos (user_id, "timestamp" desc);
