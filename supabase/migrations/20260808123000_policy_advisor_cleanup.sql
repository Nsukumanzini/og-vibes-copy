create schema if not exists private;
revoke all on schema private from public, anon, authenticated;
grant usage on schema private to authenticated, service_role;

create or replace function private.is_app_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.profiles
    where id = (select auth.uid()) and role = 'admin'
  );
$$;
revoke execute on function private.is_app_admin() from public, anon;
grant execute on function private.is_app_admin() to authenticated, service_role;

-- The existing policy has the same ownership check plus an allowed-status guard.
drop policy if exists "Item owners can update claims" on public.lost_and_found_claims;

drop policy if exists "Admins read support donations" on public.support_donations;
drop policy if exists "Users manage own support donations" on public.support_donations;
create policy "Users or admins read support donations" on public.support_donations
for select to authenticated
using (user_id = (select auth.uid()) or (select private.is_app_admin()));
create policy "Users insert own support donations" on public.support_donations
for insert to authenticated with check (user_id = (select auth.uid()));
create policy "Users update own support donations" on public.support_donations
for update to authenticated using (user_id = (select auth.uid()))
with check (user_id = (select auth.uid()));
create policy "Users delete own support donations" on public.support_donations
for delete to authenticated using (user_id = (select auth.uid()));

drop policy if exists "Admins upload academic content" on storage.objects;
create policy "Admins upload academic content" on storage.objects for insert to authenticated
with check (bucket_id = 'academic-content' and (select private.is_app_admin()));
drop policy if exists "Admins update academic content" on storage.objects;
create policy "Admins update academic content" on storage.objects for update to authenticated
using (bucket_id = 'academic-content' and (select private.is_app_admin()))
with check (bucket_id = 'academic-content' and (select private.is_app_admin()));
drop policy if exists "Admins delete academic content" on storage.objects;
create policy "Admins delete academic content" on storage.objects for delete to authenticated
using (bucket_id = 'academic-content' and (select private.is_app_admin()));

do $$
declare t text;
begin
  foreach t in array array['past_papers','lecture_slides','timetables','online_classes','app_content'] loop
    execute format('drop policy if exists %I on public.%I', 'Admins manage ' || t, t);
    execute format('create policy %I on public.%I for insert to authenticated with check ((select private.is_app_admin()))', 'Admins insert ' || t, t);
    execute format('create policy %I on public.%I for update to authenticated using ((select private.is_app_admin())) with check ((select private.is_app_admin()))', 'Admins update ' || t, t);
    execute format('create policy %I on public.%I for delete to authenticated using ((select private.is_app_admin()))', 'Admins delete ' || t, t);
  end loop;
end $$;

revoke execute on function public.handle_new_user_profile() from public, anon, authenticated;
drop function public.is_app_admin();

