-- Single skin score, replacing the per-dimension redness/texture/clarity
-- columns from skin_scores.sql (left in place so existing rows keep their
-- history; the app no longer reads or writes them).
alter table public.progress_photos
  add column if not exists skin_score double precision;
