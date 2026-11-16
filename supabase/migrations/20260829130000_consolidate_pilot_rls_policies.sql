-- Remove redundant permissive policy evaluation without changing who can act.

drop index if exists public.post_poll_votes_option_id_idx;
create index if not exists post_poll_votes_option_id_post_id_idx
  on public.post_poll_votes (option_id, post_id);

do $migration$
declare
  source_policy record;
  operation text;
  policy_suffix text;
begin
  for source_policy in
    select schemaname, tablename, policyname, qual, with_check
    from pg_policies
    where schemaname = 'public'
      and cmd = 'ALL'
      and (tablename, policyname) in (
        ('assessment_rubrics', 'Lecturers manage own assessment rubrics'),
        ('attendance_records', 'Lecturers manage module attendance records'),
        ('attendance_sessions', 'Lecturers manage module attendance sessions'),
        ('module_lecturers', 'Admins can manage module lecturer assignments'),
        ('modules', 'Admins can manage modules'),
        ('post_poll_options', 'Post owners can manage poll options'),
        ('programmes', 'Admins can manage programmes')
      )
  loop
    execute format(
      'drop policy %I on %I.%I',
      source_policy.policyname,
      source_policy.schemaname,
      source_policy.tablename
    );

    foreach operation in array array['INSERT', 'UPDATE', 'DELETE']
    loop
      policy_suffix := lower(operation);
      if operation = 'INSERT' then
        execute format(
          'create policy %I on %I.%I for insert to authenticated with check (%s)',
          source_policy.policyname || ' - ' || policy_suffix,
          source_policy.schemaname,
          source_policy.tablename,
          coalesce(source_policy.with_check, source_policy.qual)
        );
      elsif operation = 'UPDATE' then
        execute format(
          'create policy %I on %I.%I for update to authenticated using (%s) with check (%s)',
          source_policy.policyname || ' - ' || policy_suffix,
          source_policy.schemaname,
          source_policy.tablename,
          source_policy.qual,
          coalesce(source_policy.with_check, source_policy.qual)
        );
      else
        execute format(
          'create policy %I on %I.%I for delete to authenticated using (%s)',
          source_policy.policyname || ' - ' || policy_suffix,
          source_policy.schemaname,
          source_policy.tablename,
          source_policy.qual
        );
      end if;
    end loop;
  end loop;
end
$migration$;

drop policy if exists "Lecturers can view submissions for their modules"
  on public.assignment_submissions;
drop policy if exists "Students view own submissions"
  on public.assignment_submissions;
create policy "Students and lecturers view relevant submissions"
on public.assignment_submissions
for select to authenticated
using (
  user_id = (select auth.uid())
  or exists (
    select 1 from public.module_lecturers ml
    where ml.module_id = assignment_submissions.module_id
      and ml.lecturer_id = (select auth.uid())
  )
);

drop policy if exists "Lecturers can grade submissions for their modules"
  on public.assignment_submissions;
drop policy if exists "Students update registered submissions"
  on public.assignment_submissions;
create policy "Students and lecturers update relevant submissions"
on public.assignment_submissions
for update to authenticated
using (
  (
    user_id = (select auth.uid())
    and (select private.can_access_module(assignment_submissions.module_id))
  )
  or exists (
    select 1 from public.module_lecturers ml
    where ml.module_id = assignment_submissions.module_id
      and ml.lecturer_id = (select auth.uid())
  )
)
with check (
  (
    user_id = (select auth.uid())
    and (select private.can_access_module(assignment_submissions.module_id))
    and (
      brief_id is null
      or exists (
        select 1 from public.assessment_briefs brief
        where brief.id = assignment_submissions.brief_id
          and not (brief.module_id is distinct from assignment_submissions.module_id)
          and brief.published
      )
    )
  )
  or exists (
    select 1 from public.module_lecturers ml
    where ml.module_id = assignment_submissions.module_id
      and ml.lecturer_id = (select auth.uid())
  )
);

drop policy if exists "Receiver can accept or decline a pending request"
  on public.friend_requests;
drop policy if exists "Sender can cancel their own pending request"
  on public.friend_requests;
create policy "Participants update pending friend requests"
on public.friend_requests
for update to authenticated
using (
  status = 'pending'
  and (
    receiver_id = (select auth.uid())
    or sender_id = (select auth.uid())
  )
)
with check (
  (
    receiver_id = (select auth.uid())
    and status in ('accepted', 'declined')
  )
  or (
    sender_id = (select auth.uid())
    and status = 'cancelled'
  )
);

drop policy if exists "Lecturers view answers for their quizzes"
  on public.quiz_attempt_answers;
drop policy if exists quiz_answers_select_own
  on public.quiz_attempt_answers;
create policy "Students and lecturers view relevant quiz answers"
on public.quiz_attempt_answers
for select to authenticated
using (
  exists (
    select 1 from public.quiz_attempts attempt
    where attempt.id = quiz_attempt_answers.attempt_id
      and attempt.user_id = (select auth.uid())
  )
  or exists (
    select 1
    from public.quiz_attempts attempt
    join public.quizzes quiz on quiz.id = attempt.quiz_id
    where attempt.id = quiz_attempt_answers.attempt_id
      and (
        quiz.lecturer_id = (select auth.uid())
        or (select private.is_app_admin())
      )
  )
);
