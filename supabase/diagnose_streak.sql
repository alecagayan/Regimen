-- Regimen — why is the streak wrong?
--
-- Read-only. Paste into the Supabase SQL Editor and run one section at a
-- time. Replace 'a@a.a' with the signed-in account's email (it appears in
-- each section, so a find-and-replace across the file is easiest).
--
-- `StreakCalculator` is deliberately simple: a day counts if it has at
-- least one usage_logs row, OR a streak_restores row, OR nothing was
-- scheduled that day. The streak resets to 0 the moment a full day passes
-- with none of those. So a 0 is usually the data saying 0 rather than the
-- calculation being wrong -- this tells you which.

-- ============================================================
-- 0. Who are we looking at
-- ============================================================
select id, email, created_at
from auth.users
where email = 'a@a.a';


-- ============================================================
-- 1. The last 14 days, day by day
-- ============================================================
-- This is the calculator's input, laid out the way it walks it. Read from
-- the top (today) downward: the streak is the unbroken run of
-- `counts = true` starting at today or yesterday. The first `false` is
-- where it stopped.
--
-- Timezone matters. `usage_logs.timestamp` is stored UTC, but the app
-- buckets days in the *device's* calendar, so a late-evening log can show
-- up on the following day here while the app counts it as today. Change
-- 'America/Los_Angeles' to the phone's zone if a day looks off by one.
with account as (
  select id from auth.users where email = 'a@a.a'
),
days as (
  select (current_date - offset_days)::date as day
  from generate_series(0, 13) as offset_days
),
logged as (
  select distinct (l.timestamp at time zone 'America/Los_Angeles')::date as day
  from public.usage_logs l
  join account a on a.id = l.user_id
),
restored as (
  select distinct r.restored_on as day
  from public.streak_restores r
  join account a on a.id = r.user_id
)
select
  d.day,
  to_char(d.day, 'Dy') as weekday,
  (l.day is not null) as logged,
  (r.day is not null) as restored,
  (l.day is not null or r.day is not null) as counts
from days d
left join logged l on l.day = d.day
left join restored r on r.day = d.day
order by d.day desc;


-- ============================================================
-- 2. Totals — is there any history at all?
-- ============================================================
-- usage_logs = 0 means the logs were cleared (the reset script does
-- exactly that), and a 0 streak is then correct rather than a bug.
with account as (
  select id from auth.users where email = 'a@a.a'
)
select
  (select count(*) from public.usage_logs l join account a on a.id = l.user_id) as usage_logs,
  (select max(l.timestamp) from public.usage_logs l join account a on a.id = l.user_id) as newest_log,
  (select count(*) from public.streak_restores r join account a on a.id = r.user_id) as restores,
  (select count(*) from public.products p join account a on a.id = p.user_id
     where not p.is_archived) as active_products;


-- ============================================================
-- 3. Scheduling — could recent days all be "rest days"?
-- ============================================================
-- Rest days (nothing scheduled) count toward the streak, but only while
-- at least one active product exists: with an empty or fully archived
-- cabinet the rest-day rule switches off by design, so an empty account
-- can't report an infinite streak. If active_products above is 0, that is
-- the explanation for a 0 streak on an account that has no logs either.
with account as (
  select id from auth.users where email = 'a@a.a'
)
select
  p.name,
  p.frequency_kind,
  p.frequency_days_of_week,
  p.frequency_interval_days,
  p.is_archived
from public.products p
join account a on a.id = p.user_id
order by p.is_archived, p.name;
