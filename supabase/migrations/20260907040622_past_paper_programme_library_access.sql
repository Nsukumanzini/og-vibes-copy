drop policy if exists "Active accounts use OG Vibes" on public.past_papers;
drop policy if exists "Authenticated users can view past papers" on public.past_papers;

create policy "Authorized accounts view past papers"
on public.past_papers
for select
to authenticated
using (
  (select private.is_account_active())
  and (
    (select private.is_app_admin())
    or (select private.can_access_module(module_id))
    or exists (
      select 1
      from public.modules module
      join public.programmes programme on programme.id = module.programme_id
      join public.profiles profile on profile.id = (select auth.uid())
      where module.id = past_papers.module_id
        and profile.role = 'student'
        and lower(trim(profile.course)) = lower(trim(programme.name))
    )
  )
);

revoke all on table public.past_papers from anon;

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
