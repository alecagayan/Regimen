-- Regimen — self-service account deletion
--
-- Run this in the Supabase SQL Editor after schema.sql. Apple requires
-- (App Store Review Guideline 5.1.1(v)) that any app supporting account
-- creation also let the user delete their account from inside the app --
-- this is that: a `security definer` function a signed-in user can call
-- on themselves, since actually deleting an `auth.users` row needs
-- elevated privileges the client's anon/authenticated key doesn't have.
--
-- Every table with a `user_id` foreign key (products, usage_logs,
-- progress_photos, zone_findings) already cascades on delete (see
-- schema.sql), so deleting the `auth.users` row alone clears all of them.
-- Storage objects aren't tied by a foreign key, though, so this deletes
-- the user's uploaded photos first.
--
-- This file is not part of the Xcode target — it's a reference script for
-- the Supabase dashboard, not app source.

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
