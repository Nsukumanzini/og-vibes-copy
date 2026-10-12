-- Keep academic-content private while allowing a student to read past papers
-- for their own programme and NCV level, or for a module they have explicitly
-- joined. Staff module managers and app administrators retain access.
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
    or (
      (select private.is_account_active())
      and exists (
        select 1
        from public.past_papers paper
        join public.modules module on module.id = paper.module_id
        left join public.programmes programme on programme.id = module.programme_id
        where paper.storage_path = objects.name
          and (
            (select private.can_access_module(module.id))
            or exists (
              select 1
              from public.profiles profile
              where profile.id = (select auth.uid())
                and profile.role = 'student'
                and lower(trim(profile.course)) = lower(trim(programme.name))
                and lower(trim(profile.level)) = lower(trim(module.level))
            )
          )
      )
    )
    or exists (
      select 1 from public.assessment_briefs brief
      where brief.attachment_storage_path = objects.name
        and (
          brief.lecturer_id = (select auth.uid())
          or (
            brief.published
            and (select private.can_access_module(brief.module_id))
          )
        )
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

-- Replace the legacy catch-all event policy before restoring write grants.
-- Otherwise an active user could bypass the pending-review requirements.
drop policy if exists "Active accounts use OG Vibes" on public.events;

drop policy if exists "App administrators manage events" on public.events;
create policy "App administrators manage events"
on public.events
for all
to authenticated
using ((select private.is_app_admin()))
with check ((select private.is_app_admin()));

drop policy if exists "Students delete pending event submissions" on public.events;
create policy "Students delete pending event submissions"
on public.events
for delete
to authenticated
using (
  submitted_by = (select auth.uid())
  and approval_status = 'pending'
  and published = false
  and (select private.is_account_active())
);

grant select, insert, update, delete on table public.events to authenticated;
revoke all on table public.events from anon;
