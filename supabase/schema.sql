-- Regimen — Supabase schema
--
-- Run this once in your Supabase project's SQL Editor
-- (https://supabase.com/dashboard/project/_/sql/new) after creating the
-- project. It creates the four tables the app reads and writes, locks every
-- row to its owning user with Row Level Security, auto-creates a `profiles`
-- row on signup, and sets up the private storage bucket for progress
-- photos.
--
-- This file is not part of the Xcode target — it's a reference script for
-- the Supabase dashboard, not app source.

-- ============================================================
-- 1. Profiles — one row per auth user, created automatically on signup.
-- ============================================================
create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  name text not null default '',
  has_completed_onboarding boolean not null default false,
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

create policy "Users can view their own profile"
  on public.profiles for select
  using (auth.uid() = id);

create policy "Users can update their own profile"
  on public.profiles for update
  using (auth.uid() = id);

-- Pulls the display name out of the signup metadata the app sends
-- (`data: ["name": ...]` in AuthService.signUp) and creates the profile row.
create function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, name)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'name', ''));
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- ============================================================
-- 2. Products
-- ============================================================
create table public.products (
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

alter table public.products enable row level security;

create policy "Users can manage their own products"
  on public.products for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- ============================================================
-- 3. Usage logs
-- ============================================================
create table public.usage_logs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  product_id uuid not null references public.products (id) on delete cascade,
  "timestamp" timestamptz not null default now(),
  time_of_day text not null default 'AM',
  estimated_amount_used_ml double precision not null default 0
);

alter table public.usage_logs enable row level security;

create policy "Users can manage their own usage logs"
  on public.usage_logs for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- ============================================================
-- 4. Progress photos
-- ============================================================
create table public.progress_photos (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  "timestamp" timestamptz not null default now(),
  storage_path text not null,
  note text
);

alter table public.progress_photos enable row level security;

create policy "Users can manage their own progress photos"
  on public.progress_photos for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- ============================================================
-- 5. Storage bucket for progress photos
-- ============================================================
-- Private (not public): the app always reads photos through short-lived
-- signed URLs rather than a permanently guessable public link.
insert into storage.buckets (id, name, public)
values ('progress-photos', 'progress-photos', false)
on conflict (id) do nothing;

-- Each user's files live under a folder named after their own auth UID
-- (the app uploads to "<uid>/<filename>.jpg"), so this policy scopes every
-- operation to that folder.
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
