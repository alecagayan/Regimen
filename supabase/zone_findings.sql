-- Regimen — per-zone scan findings
--
-- Run this in the Supabase SQL Editor after schema.sql. Adds a table
-- persisting what each skin scan found per face zone (forehead, nose,
-- cheeks, chin) and finding kind (blemish, spot, blackhead, whitehead) --
-- previously this was recomputed fresh from the photo on every scan and
-- never saved (see SkinScanService/SkinScanResult), which was fine for
-- showing one photo's results but meant there was nothing to trend against
-- over time. One row per (photo, zone, kind) actually flagged; a re-scan
-- of the same photo replaces its rows rather than appending duplicates
-- (see ZoneFindingService.replace).
--
-- This file is not part of the Xcode target — it's a reference script for
-- the Supabase dashboard, not app source.

create table public.zone_findings (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  progress_photo_id uuid not null references public.progress_photos (id) on delete cascade,
  zone text not null,
  kind text not null,
  finding_count integer not null default 0,
  cell_count integer not null default 0,
  created_at timestamptz not null default now()
);

alter table public.zone_findings enable row level security;

create policy "Users can manage their own zone findings"
  on public.zone_findings for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create index zone_findings_photo_idx on public.zone_findings (progress_photo_id);
create index zone_findings_user_zone_idx on public.zone_findings (user_id, zone);
