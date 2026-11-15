create or replace function private.can_publish_academic_content()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.profiles
    where id = (select auth.uid()) and role in ('admin', 'lecturer')
  );
$$;
revoke execute on function private.can_publish_academic_content() from public, anon;
grant execute on function private.can_publish_academic_content() to authenticated, service_role;

drop policy if exists "Admins upload academic content" on storage.objects;
create policy "Academic publishers upload content" on storage.objects for insert to authenticated
with check (bucket_id = 'academic-content' and (select private.can_publish_academic_content()));
drop policy if exists "Admins update academic content" on storage.objects;
create policy "Academic publishers update content" on storage.objects for update to authenticated
using (bucket_id = 'academic-content' and (select private.can_publish_academic_content()))
with check (bucket_id = 'academic-content' and (select private.can_publish_academic_content()));
drop policy if exists "Admins delete academic content" on storage.objects;
create policy "Academic publishers delete content" on storage.objects for delete to authenticated
using (bucket_id = 'academic-content' and (select private.can_publish_academic_content()));

do $$
declare t text;
begin
  foreach t in array array['past_papers','lecture_slides','timetables','online_classes'] loop
    execute format('drop policy if exists %I on public.%I', 'Admins insert ' || t, t);
    execute format('drop policy if exists %I on public.%I', 'Admins update ' || t, t);
    execute format('drop policy if exists %I on public.%I', 'Admins delete ' || t, t);
    execute format('create policy %I on public.%I for insert to authenticated with check ((select private.can_publish_academic_content()))', 'Academic publishers insert ' || t, t);
    execute format('create policy %I on public.%I for update to authenticated using ((select private.can_publish_academic_content())) with check ((select private.can_publish_academic_content()))', 'Academic publishers update ' || t, t);
    execute format('create policy %I on public.%I for delete to authenticated using ((select private.can_publish_academic_content()))', 'Academic publishers delete ' || t, t);
  end loop;
end $$;

