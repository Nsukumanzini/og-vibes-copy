alter table public.accommodations
  add column if not exists image_urls text[] not null default '{}',
  add column if not exists nsfas_accreditation_expires_on date;

alter table public.accommodations
  drop constraint if exists accommodations_image_urls_limit;

alter table public.accommodations
  add constraint accommodations_image_urls_limit
  check (cardinality(image_urls) <= 8);

update public.accommodations
set image_urls = array[image_url]
where image_url is not null
  and btrim(image_url) <> ''
  and cardinality(image_urls) = 0;

create table if not exists public.accommodation_reports (
  id uuid primary key default gen_random_uuid(),
  accommodation_id uuid references public.accommodations(id) on delete set null,
  reporter_id uuid not null references auth.users(id) on delete cascade,
  reason text not null check (
    reason in (
      'Incorrect information',
      'No longer available',
      'Accreditation concern',
      'Suspicious listing',
      'Unsafe property',
      'Other'
    )
  ),
  details text not null default '' check (char_length(details) <= 1000),
  status text not null default 'open' check (
    status in ('open', 'reviewing', 'resolved', 'dismissed')
  ),
  resolution_note text,
  reviewed_by uuid references auth.users(id) on delete set null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists accommodation_reports_one_open_per_student_idx
  on public.accommodation_reports(accommodation_id, reporter_id)
  where status in ('open', 'reviewing');

create index if not exists accommodation_reports_status_created_idx
  on public.accommodation_reports(status, created_at desc);

create index if not exists accommodation_reports_reporter_idx
  on public.accommodation_reports(reporter_id, created_at desc);

alter table public.accommodation_reports enable row level security;

grant select, insert on public.accommodation_reports to authenticated;
revoke update, delete on public.accommodation_reports from anon, authenticated;

drop policy if exists "Active students report accommodation" on public.accommodation_reports;
create policy "Active students report accommodation"
on public.accommodation_reports
as restrictive
for all
to authenticated
using ((select private.is_account_active()))
with check ((select private.is_account_active()));

drop policy if exists "Students view their accommodation reports" on public.accommodation_reports;
create policy "Students view their accommodation reports"
on public.accommodation_reports
for select
to authenticated
using ((select auth.uid()) = reporter_id);

drop policy if exists "Students report active accommodation" on public.accommodation_reports;
create policy "Students report active accommodation"
on public.accommodation_reports
for insert
to authenticated
with check (
  (select auth.uid()) = reporter_id
  and accommodation_id is not null
  and exists (
    select 1
    from public.accommodations accommodation
    where accommodation.id = accommodation_id
      and accommodation.is_active
  )
);
