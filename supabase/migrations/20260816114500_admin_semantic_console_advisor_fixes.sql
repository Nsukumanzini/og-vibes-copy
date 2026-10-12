begin;

create index if not exists profiles_suspended_by_idx
on public.profiles (suspended_by);

create index if not exists app_takeover_notices_created_by_idx
on public.app_takeover_notices (created_by);

drop policy if exists "Admins read all app notices" on public.app_takeover_notices;
drop policy if exists "Users read current relevant app notices" on public.app_takeover_notices;

create policy "Authenticated users read permitted app notices"
on public.app_takeover_notices
for select
to authenticated
using (
  (select private.is_app_admin())
  or (
    (target_user_id is null or target_user_id = (select auth.uid()))
    and is_active
    and starts_at <= now()
    and (ends_at is null or ends_at > now())
  )
);

commit;
