-- Regimen — schema verification
--
-- Read-only: it changes nothing. Paste the whole thing into the Supabase
-- SQL Editor and run it.
--
-- ONE query on purpose. The previous version was four separate statements,
-- and the Supabase SQL Editor only ever shows the result of the last one --
-- so it silently displayed the catalog count while hiding the table,
-- column and RLS checks, which are the ones that actually explain a broken
-- fetch. Everything now comes back in a single result set.
--
-- Read the `status` column. Anything that is not `ok` is the problem, and
-- problems sort to the top. If every row says `ok`, the schema is not the
-- cause: check whether the Supabase project is paused, and read the app's
-- console for a decode error (see `PostgresDay` -- a Postgres `date`
-- column that the client can't parse fails the whole fetch and looks
-- exactly like a network outage).

with
-- ------------------------------------------------------------
-- 1. Tables the app reads
-- ------------------------------------------------------------
expected_tables(table_name) as (
  values ('profiles'), ('products'), ('usage_logs'), ('progress_photos'),
         ('catalog_products'), ('zone_findings'), ('streak_restores'),
         ('skin_reactions'), ('product_empties'), ('analytics_events')
),
table_check as (
  select
    1 as sort_group,
    'table' as check_type,
    e.table_name as item,
    case when t.table_name is null then 'MISSING' else 'ok' end as status,
    case when t.table_name is null
         then 'Run complete_schema.sql -- this table does not exist'
         else '' end as detail
  from expected_tables e
  left join information_schema.tables t
    on t.table_schema = 'public' and t.table_name = e.table_name
),

-- ------------------------------------------------------------
-- 2. Columns the Swift models decode
-- ------------------------------------------------------------
-- One absent column fails the whole table's fetch: PostgREST errors on the
-- select, so the app sees nothing rather than a partial row.
expected_columns(table_name, column_name) as (
  values
    ('profiles','is_premium'), ('profiles','has_used_free_scan'),
    ('profiles','purchased_restore_credits'), ('profiles','skin_type'),
    ('profiles','skin_sensitivity'), ('profiles','actives_experience'),
    ('profiles','routine_length'), ('profiles','has_completed_onboarding'),

    ('products','layer_category'), ('products','conflict_tags'),
    ('products','typical_dose_ml'), ('products','frequency_kind'),
    ('products','frequency_days_of_week'), ('products','frequency_interval_days'),
    ('products','months_after_opening'), ('products','ingredients'),
    ('products','is_archived'), ('products','opened_date'),

    ('progress_photos','skin_score'), ('progress_photos','skin_attributes'),
    ('progress_photos','overlay_path'), ('progress_photos','face_rect_x'),
    ('progress_photos','face_rect_y'), ('progress_photos','face_rect_width'),
    ('progress_photos','face_rect_height'), ('progress_photos','note'),

    ('usage_logs','time_of_day'), ('usage_logs','estimated_amount_used_ml'),

    ('catalog_products','suggested_conflict_tags'), ('catalog_products','description'),
    ('catalog_products','layer_category'), ('catalog_products','ingredients'),
    ('catalog_products','barcode'),

    ('zone_findings','finding_count'), ('zone_findings','cell_count'),
    ('streak_restores','restored_on'),
    ('skin_reactions','occurred_on'), ('skin_reactions','severity'),
    ('product_empties','would_repurchase'), ('product_empties','rating'),
    ('analytics_events','properties'), ('analytics_events','app_version')
),
column_check as (
  select
    2 as sort_group,
    'column' as check_type,
    e.table_name || '.' || e.column_name as item,
    case when c.column_name is null then 'MISSING' else 'ok' end as status,
    case when c.column_name is null
         then 'Run complete_schema.sql -- the app decodes this column'
         else '' end as detail
  from expected_columns e
  left join information_schema.columns c
    on c.table_schema = 'public'
   and c.table_name = e.table_name
   and c.column_name = e.column_name
),

-- ------------------------------------------------------------
-- 3. RLS and policies
-- ------------------------------------------------------------
-- RLS on with NO policy is the quiet failure: every query succeeds and
-- returns zero rows, so the app looks empty rather than broken. RLS off is
-- the opposite problem -- it works, and every user can read everyone else's
-- photos.
rls_check as (
  select
    3 as sort_group,
    'rls' as check_type,
    c.relname as item,
    case
      when not c.relrowsecurity then 'SECURITY HOLE'
      when count(p.polname) = 0 then 'NO POLICY'
      else 'ok'
    end as status,
    case
      when not c.relrowsecurity then 'RLS is OFF -- every user can read every other user''s rows'
      when count(p.polname) = 0 then 'RLS on with no policy -- all reads return empty'
      else count(p.polname) || ' policies'
    end as detail
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  left join pg_policy p on p.polrelid = c.oid
  where n.nspname = 'public'
    and c.relname in (
      'profiles','products','usage_logs','progress_photos','catalog_products',
      'zone_findings','streak_restores','skin_reactions','product_empties','analytics_events'
    )
  group by c.relname, c.relrowsecurity
),

-- ------------------------------------------------------------
-- 4. Catalog sanity
-- ------------------------------------------------------------
-- A multiple of 133 means a catalog migration ran more than once and
-- duplicated the reference data.
catalog_check as (
  select
    4 as sort_group,
    'catalog' as check_type,
    'catalog_products rows' as item,
    case when count(*) = count(distinct (brand, name)) then 'ok' else 'DUPLICATES' end as status,
    count(*) || ' rows, ' || count(distinct (brand, name)) || ' unique' as detail
  from public.catalog_products
),

-- Conflict tags must have survived the singular-to-array backfill. A
-- non-zero count here means the app cannot read the conflict tag on those
-- products, so conflict detection is silently dead for them -- the exact
-- bug the schema's backfill ordering used to cause.
catalog_tag_check as (
  select
    4 as sort_group,
    'catalog' as check_type,
    'catalog conflict tags' as item,
    case when count(*) filter (
           where suggested_conflict_tags = '{}' and suggested_conflict_tag <> 'None'
         ) = 0 then 'ok' else 'NOT BACKFILLED' end as status,
    count(*) filter (
      where suggested_conflict_tags = '{}' and suggested_conflict_tag <> 'None'
    ) || ' of ' || count(*) || ' products have a tag the app cannot read' as detail
  from public.catalog_products
)

select check_type, item, status, detail
from (
  select * from table_check
  union all select * from column_check
  union all select * from rls_check
  union all select * from catalog_check
  union all select * from catalog_tag_check
) all_checks
-- Problems first, so a long all-clear list never buries a single failure.
order by (status = 'ok'), sort_group, item;
