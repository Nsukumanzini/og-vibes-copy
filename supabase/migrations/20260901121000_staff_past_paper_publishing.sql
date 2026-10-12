begin;

alter table public.past_papers
  add column if not exists created_by uuid references public.profiles(id) on delete set null;

create index if not exists past_papers_created_by_idx
on public.past_papers (created_by, created_at desc);

grant select, insert, update, delete on public.past_papers to authenticated;

drop policy if exists "Past papers access grant" on public.past_papers;
create policy "Past papers access grant"
on public.past_papers
as permissive
for select
to authenticated
using (
  (select private.is_app_admin())
  or (select private.can_access_module(module_id))
);

drop policy if exists "Authorized users read past papers" on public.past_papers;
create policy "Authorized users read past papers"
on public.past_papers
as restrictive
for select
to authenticated
using (
  (select private.is_app_admin())
  or (select private.can_access_module(module_id))
);

drop policy if exists "Academic publishers insert past_papers" on public.past_papers;
drop policy if exists "Academic publishers update past_papers" on public.past_papers;
drop policy if exists "Academic publishers delete past_papers" on public.past_papers;
drop policy if exists "Lecturers create own past papers" on public.past_papers;
drop policy if exists "Lecturers update own past papers" on public.past_papers;
drop policy if exists "Lecturers delete own past papers" on public.past_papers;

create policy "Lecturers create own past papers"
on public.past_papers
for insert
to authenticated
with check (
  (
    created_by = (select auth.uid())
    and exists (
      select 1 from public.module_lecturers assignment
      where assignment.module_id = past_papers.module_id
        and assignment.lecturer_id = (select auth.uid())
    )
  )
  or (select private.is_app_admin())
);

create policy "Lecturers update own past papers"
on public.past_papers
for update
to authenticated
using (
  (
    created_by = (select auth.uid())
    and exists (
      select 1 from public.module_lecturers assignment
      where assignment.module_id = past_papers.module_id
        and assignment.lecturer_id = (select auth.uid())
    )
  )
  or (select private.is_app_admin())
)
with check (
  (
    created_by = (select auth.uid())
    and exists (
      select 1 from public.module_lecturers assignment
      where assignment.module_id = past_papers.module_id
        and assignment.lecturer_id = (select auth.uid())
    )
  )
  or (select private.is_app_admin())
);

create policy "Lecturers delete own past papers"
on public.past_papers
for delete
to authenticated
using (created_by = (select auth.uid()) or (select private.is_app_admin()));

drop policy if exists "Authorized users read academic content" on storage.objects;
create policy "Authorized users read academic content"
on storage.objects
for select
to authenticated
using (
  bucket_id = 'academic-content'
  and (
    (select private.is_app_admin())
    or exists (
      select 1 from public.past_papers paper
      where paper.storage_path = name
        and (select private.can_access_module(paper.module_id))
    )
    or exists (
      select 1 from public.lecture_slides slide
      where slide.storage_path = name
        and (select private.can_access_module(slide.module_id))
    )
    or exists (
      select 1 from public.timetables timetable
      where timetable.storage_path = name
        and (select private.can_access_module(timetable.module_id))
    )
  )
);

commit;
