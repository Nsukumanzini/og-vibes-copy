create or replace function private.notify_assignment_outcome()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if old.grade is not distinct from new.grade
    and old.feedback is not distinct from new.feedback
    and old.extension_status is not distinct from new.extension_status
    and old.status is not distinct from new.status then
    return new;
  end if;
  if (select auth.uid()) = new.user_id then return new; end if;
  perform private.enqueue_student_notification(new.user_id, 'academics',
    'Assessment submission updated',
    'A grade, feedback, extension decision, or submission status has changed.',
    'assessments', null, (select auth.uid()),
    jsonb_build_object('submission_id', new.id),
    'submission-outcome:' || new.id::text || ':' || new.updated_at::text);
  return new;
end; $$;
revoke all on function private.notify_assignment_outcome() from public, anon, authenticated;
drop trigger if exists notify_assignment_outcome on public.assignment_submissions;
create trigger notify_assignment_outcome
after update of grade, feedback, extension_status, status on public.assignment_submissions
for each row execute function private.notify_assignment_outcome();

create or replace function private.notify_career_application_outcome()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if old.status is not distinct from new.status then return new; end if;
  if (select auth.uid()) = new.student_id then return new; end if;
  perform private.enqueue_student_notification(new.student_id, 'academics',
    'Career application updated',
    'The status of one of your career applications has changed.',
    'career', null, (select auth.uid()),
    jsonb_build_object('application_id', new.id),
    'career-outcome:' || new.id::text || ':' || new.status);
  return new;
end; $$;
revoke all on function private.notify_career_application_outcome() from public, anon, authenticated;
drop trigger if exists notify_career_application_outcome on public.career_applications;
create trigger notify_career_application_outcome
after update of status on public.career_applications
for each row execute function private.notify_career_application_outcome();
