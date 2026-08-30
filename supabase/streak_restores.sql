-- Regimen — streak restores
--
-- Run this in the Supabase SQL Editor after schema.sql. One row per day a
-- user has spent a restore on: a day with no usage logs that is
-- nonetheless allowed to count toward their streak, bridging a gap that
-- would otherwise have reset it to zero (see StreakCalculator).
--
-- Stored as a `date`, not a timestamptz: a restore applies to a whole
-- calendar day in the user's own timezone, and pinning it to an instant
-- would make the same restore land on different days depending on where
-- the user opened the app.
--
-- The unique constraint makes a restore idempotent -- spending one twice
-- on the same day is a no-op rather than a duplicate row.
--
-- This file is not part of the Xcode target — it's a reference script for
-- the Supabase dashboard, not app source.

create table public.streak_restores (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  restored_on date not null,
  created_at timestamptz not null default now(),
  unique (user_id, restored_on)
);

alter table public.streak_restores enable row level security;

create policy "Users can manage their own streak restores"
  on public.streak_restores for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create index streak_restores_user_idx on public.streak_restores (user_id, restored_on desc);
