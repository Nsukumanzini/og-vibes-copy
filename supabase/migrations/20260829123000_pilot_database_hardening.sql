-- Pilot hardening for the OG Vibes student app.
-- Keeps the public RPC contract stable while moving privileged implementations
-- out of the API-exposed schema, indexes foreign-key joins, and prevents RLS
-- auth functions from being re-evaluated once per row.

create schema if not exists private;
revoke all on schema private from public, anon;
grant usage on schema private to authenticated, service_role;

alter function public.decline_group_call(uuid) set schema private;
alter function public.end_group_call(uuid) set schema private;
alter function public.join_group_call(uuid) set schema private;
alter function public.leave_group_call(uuid) set schema private;
alter function public.start_group_call(uuid, text, uuid[]) set schema private;
alter function public.upgrade_private_call_to_group(uuid, uuid[]) set schema private;

revoke all on function private.decline_group_call(uuid) from public, anon;
revoke all on function private.end_group_call(uuid) from public, anon;
revoke all on function private.join_group_call(uuid) from public, anon;
revoke all on function private.leave_group_call(uuid) from public, anon;
revoke all on function private.start_group_call(uuid, text, uuid[]) from public, anon;
revoke all on function private.upgrade_private_call_to_group(uuid, uuid[]) from public, anon;

grant execute on function private.decline_group_call(uuid) to authenticated, service_role;
grant execute on function private.end_group_call(uuid) to authenticated, service_role;
grant execute on function private.join_group_call(uuid) to authenticated, service_role;
grant execute on function private.leave_group_call(uuid) to authenticated, service_role;
grant execute on function private.start_group_call(uuid, text, uuid[]) to authenticated, service_role;
grant execute on function private.upgrade_private_call_to_group(uuid, uuid[]) to authenticated, service_role;

create function public.decline_group_call(target_call_id uuid)
returns void
language sql
volatile
security invoker
set search_path = ''
as $$ select private.decline_group_call(target_call_id); $$;

create function public.end_group_call(target_call_id uuid)
returns void
language sql
volatile
security invoker
set search_path = ''
as $$ select private.end_group_call(target_call_id); $$;

create function public.join_group_call(target_call_id uuid)
returns public.group_calls
language sql
volatile
security invoker
set search_path = ''
as $$ select private.join_group_call(target_call_id); $$;

create function public.leave_group_call(target_call_id uuid)
returns void
language sql
volatile
security invoker
set search_path = ''
as $$ select private.leave_group_call(target_call_id); $$;

create function public.start_group_call(
  target_group_id uuid,
  target_call_type text,
  invitee_ids uuid[] default '{}'::uuid[]
)
returns public.group_calls
language sql
volatile
security invoker
set search_path = ''
as $$ select private.start_group_call(target_group_id, target_call_type, invitee_ids); $$;

create function public.upgrade_private_call_to_group(
  target_call_id uuid,
  invitee_ids uuid[] default '{}'::uuid[]
)
returns public.group_calls
language sql
volatile
security invoker
set search_path = ''
as $$ select private.upgrade_private_call_to_group(target_call_id, invitee_ids); $$;

revoke all on function public.decline_group_call(uuid) from public, anon;
revoke all on function public.end_group_call(uuid) from public, anon;
revoke all on function public.join_group_call(uuid) from public, anon;
revoke all on function public.leave_group_call(uuid) from public, anon;
revoke all on function public.start_group_call(uuid, text, uuid[]) from public, anon;
revoke all on function public.upgrade_private_call_to_group(uuid, uuid[]) from public, anon;

grant execute on function public.decline_group_call(uuid) to authenticated, service_role;
grant execute on function public.end_group_call(uuid) to authenticated, service_role;
grant execute on function public.join_group_call(uuid) to authenticated, service_role;
grant execute on function public.leave_group_call(uuid) to authenticated, service_role;
grant execute on function public.start_group_call(uuid, text, uuid[]) to authenticated, service_role;
grant execute on function public.upgrade_private_call_to_group(uuid, uuid[]) to authenticated, service_role;

create index if not exists accommodation_reports_reviewed_by_idx on public.accommodation_reports (reviewed_by);
create index if not exists admin_alerts_student_id_idx on public.admin_alerts (student_id);
create index if not exists blocked_users_blocked_user_id_idx on public.blocked_users (blocked_user_id);
create index if not exists bug_reports_user_id_idx on public.bug_reports (user_id);
create index if not exists comment_likes_user_id_idx on public.comment_likes (user_id);
create index if not exists comments_author_id_idx on public.comments (author_id);
create index if not exists comments_parent_id_idx on public.comments (parent_id);
create index if not exists comments_post_id_idx on public.comments (post_id);
create index if not exists group_invites_created_by_idx on public.group_invites (created_by);
create index if not exists group_message_reactions_user_id_idx on public.group_message_reactions (user_id);
create index if not exists group_messages_reply_to_id_idx on public.group_messages (reply_to_id);
create index if not exists group_poll_votes_user_id_idx on public.group_poll_votes (user_id);
create index if not exists group_reports_message_id_idx on public.group_reports (message_id);
create index if not exists group_reports_reported_user_id_idx on public.group_reports (reported_user_id);
create index if not exists group_reports_reporter_id_idx on public.group_reports (reporter_id);
create index if not exists group_user_blocks_blocked_user_id_idx on public.group_user_blocks (blocked_user_id);
create index if not exists group_user_blocks_blocker_id_idx on public.group_user_blocks (blocker_id);
create index if not exists lecturer_applications_reviewed_by_idx on public.lecturer_applications (reviewed_by);
create index if not exists live_questions_author_id_idx on public.live_questions (author_id);
create index if not exists past_papers_module_id_idx on public.past_papers (module_id);
create index if not exists post_likes_user_id_idx on public.post_likes (user_id);
create index if not exists post_poll_votes_option_id_idx on public.post_poll_votes (option_id);
create index if not exists post_poll_votes_post_id_idx on public.post_poll_votes (post_id);
create index if not exists posts_user_id_idx on public.posts (user_id);
create index if not exists quiz_attempt_answers_question_id_idx on public.quiz_attempt_answers (question_id);
create index if not exists quiz_security_events_user_id_idx on public.quiz_security_events (user_id);
create index if not exists reports_comment_id_idx on public.reports (comment_id);
create index if not exists reports_post_id_idx on public.reports (post_id);
create index if not exists reports_reporter_id_idx on public.reports (reporter_id);

do $migration$
declare
  policy_row record;
  using_clause text;
  check_clause text;
begin
  for policy_row in
    select schemaname, tablename, policyname, qual, with_check
    from pg_policies
    where schemaname in ('public', 'realtime')
      and (
        (qual like '%auth.uid()%' and qual not like '%select auth.uid()%')
        or
        (with_check like '%auth.uid()%' and with_check not like '%select auth.uid()%')
      )
  loop
    using_clause := case
      when policy_row.qual is null then ''
      else ' using (' || replace(policy_row.qual, 'auth.uid()', '(select auth.uid())') || ')'
    end;
    check_clause := case
      when policy_row.with_check is null then ''
      else ' with check (' || replace(policy_row.with_check, 'auth.uid()', '(select auth.uid())') || ')'
    end;
    execute format(
      'alter policy %I on %I.%I%s%s',
      policy_row.policyname,
      policy_row.schemaname,
      policy_row.tablename,
      using_clause,
      check_clause
    );
  end loop;
end
$migration$;

comment on schema private is
  'Internal OG Vibes routines that are not exposed through the public Data API.';
