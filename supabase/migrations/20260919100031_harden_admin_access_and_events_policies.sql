-- Production advisor follow-up:
-- 1) keep administrator access server-only while documenting its intended RLS path;
-- 2) index the grantor foreign key; and
-- 3) replace overlapping event policies with exactly one permissive policy
--    per operation, preserving the same student and Owner access rules.

begin;

-- Browser roles retain no privileges on this sensitive table. The explicit
-- service-role policy records the trusted Edge Function access path and avoids
-- leaving an RLS-enabled table without any policy.
drop policy if exists "Service role manages administrator access" on public.admin_access;
create policy "Service role manages administrator access"
on public.admin_access
for all
to service_role
using (true)
with check (true);

create index if not exists admin_access_granted_by_idx
on public.admin_access (granted_by);

-- These five policies overlap because the former administrator FOR ALL policy
-- is permissive alongside each student policy. Keep each operation explicit so
-- the policy contract remains auditable and advisors see a single policy per
-- operation.
drop policy if exists "Students view approved events or own submissions" on public.events;
drop policy if exists "Students submit events for review" on public.events;
drop policy if exists "Students edit pending event submissions" on public.events;
drop policy if exists "Students delete pending event submissions" on public.events;
drop policy if exists "App administrators manage events" on public.events;

create policy "Read approved events, own submissions, or admin events"
on public.events
for select
to authenticated
using (
  (select private.is_app_admin())
  or (published and approval_status = 'approved')
  or submitted_by = (select auth.uid())
);

create policy "Submit pending events or admin events"
on public.events
for insert
to authenticated
with check (
  (select private.is_app_admin())
  or (
    submitted_by = (select auth.uid())
    and organizer_id = (select auth.uid())
    and approval_status = 'pending'
    and published = false
  )
);

create policy "Edit own pending events or admin events"
on public.events
for update
to authenticated
using (
  (select private.is_app_admin())
  or (submitted_by = (select auth.uid()) and approval_status = 'pending')
)
with check (
  (select private.is_app_admin())
  or (
    submitted_by = (select auth.uid())
    and organizer_id = (select auth.uid())
    and approval_status = 'pending'
    and published = false
  )
);

create policy "Delete own pending events or admin events"
on public.events
for delete
to authenticated
using (
  (select private.is_app_admin())
  or (
    submitted_by = (select auth.uid())
    and approval_status = 'pending'
    and published = false
    and (select private.is_account_active())
  )
);

comment on policy "Service role manages administrator access" on public.admin_access is
  'Trusted server-side administration only. Browser roles are explicitly revoked.';

comment on policy "Read approved events, own submissions, or admin events" on public.events is
  'Students read approved events and their own submissions; Owners read all events.';

commit;