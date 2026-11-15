-- Keep academic files private. Extend the existing SELECT policy to the
-- materials published by both staff and admin; do not change upload rights.
alter policy "Authorized users read academic content" on storage.objects
using (
  bucket_id = 'academic-content'
  and (
    (select private.is_app_admin())
    or exists (
      select 1 from public.lecture_slides slide
      where slide.storage_path = objects.name
        and (select private.can_access_module(slide.module_id))
    )
    or exists (
      select 1 from public.timetables timetable
      where timetable.storage_path = objects.name
        and (select private.can_access_module(timetable.module_id))
    )
    or exists (
      select 1 from public.past_papers paper
      where paper.storage_path = objects.name
        and (select private.can_access_module(paper.module_id))
    )
    or exists (
      select 1 from public.assessment_briefs brief
      where brief.attachment_storage_path = objects.name
        and (brief.lecturer_id = (select auth.uid())
          or (brief.published and (select private.can_access_module(brief.module_id))))
    )
    or exists (
      select 1 from public.quizzes quiz
      where quiz.attachment_storage_path = objects.name
        and quiz.published
        and (select private.can_access_module(quiz.module_id))
    )
    or exists (
      select 1 from public.quiz_questions question
      join public.quizzes quiz on quiz.id = question.quiz_id
      where question.attachment_storage_path = objects.name
        and quiz.published
        and (select private.can_access_module(quiz.module_id))
    )
  )
);

-- New publications get an actual publication timestamp, including documents
-- saved as drafts first. The creation date is only a legacy approximation.
alter table public.assessment_briefs
  add column if not exists published_at timestamptz;

update public.assessment_briefs
set published_at = created_at
where published and published_at is null;

create or replace function private.set_assessment_publication_time()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    new.published_at := case when new.published then now() else null end;
  elsif new.published and not old.published then
    new.published_at := now();
  else
    new.published_at := old.published_at;
  end if;
  return new;
end;
$$;
revoke all on function private.set_assessment_publication_time() from public, anon, authenticated;
drop trigger if exists set_assessment_publication_time on public.assessment_briefs;
create trigger set_assessment_publication_time
before insert or update on public.assessment_briefs
for each row execute function private.set_assessment_publication_time();
