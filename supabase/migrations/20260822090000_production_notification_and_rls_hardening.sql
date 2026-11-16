-- Keep suspended accounts out of newer student/lecturer resources. The
-- takeover-notice table is intentionally excluded so a suspended user can read
-- the administrator's explanation.

drop policy if exists "Active accounts use OG Vibes" on public.accommodations;
create policy "Active accounts use OG Vibes"
on public.accommodations as restrictive for all to authenticated
using ((select private.is_account_active()))
with check ((select private.is_account_active()));

drop policy if exists "Active accounts use OG Vibes" on public.assessment_rubrics;
create policy "Active accounts use OG Vibes"
on public.assessment_rubrics as restrictive for all to authenticated
using ((select private.is_account_active()))
with check ((select private.is_account_active()));

drop policy if exists "Active accounts use OG Vibes" on public.attendance_records;
create policy "Active accounts use OG Vibes"
on public.attendance_records as restrictive for all to authenticated
using ((select private.is_account_active()))
with check ((select private.is_account_active()));

drop policy if exists "Active accounts use OG Vibes" on public.attendance_sessions;
create policy "Active accounts use OG Vibes"
on public.attendance_sessions as restrictive for all to authenticated
using ((select private.is_account_active()))
with check ((select private.is_account_active()));

create or replace function private.prepare_new_student_notifications()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_announcement record;
begin
  if new.role <> 'student' then
    return new;
  end if;

  insert into public.notification_preferences (user_id)
  values (new.id)
  on conflict (user_id) do nothing;

  perform private.enqueue_student_notification(
    new.id,
    'campus',
    'Welcome to OG Vibes',
    'Your campus updates, classes and conversations are ready in one place.',
    'home',
    null,
    null,
    jsonb_build_object('kind', 'welcome'),
    'welcome:' || new.id::text
  );

  -- Give a newly registered student the recent important notices that are
  -- still active, even when those notices were published before registration.
  for current_announcement in
    select id, created_by, data
    from public.app_content
    where section = 'announcements'
      and is_active
      and created_at >= now() - interval '30 days'
      and (
        lower(coalesce(data->>'urgency', '')) = 'critical'
        or lower(coalesce(data->>'is_pinned', data->>'isPinned', 'false')) = 'true'
      )
    order by created_at desc
    limit 10
  loop
    perform private.enqueue_student_notification(
      new.id,
      'campus',
      case
        when lower(coalesce(current_announcement.data->>'urgency', '')) = 'critical'
          then 'Important campus alert'
        else 'Campus update'
      end,
      coalesce(
        nullif(btrim(current_announcement.data->>'body'), ''),
        'Open Alerts to read this campus update.'
      ),
      'alerts',
      current_announcement.id::text,
      current_announcement.created_by,
      jsonb_build_object('kind', 'announcement'),
      'announcement:' || current_announcement.id::text || ':' || new.id::text
    );
  end loop;

  return new;
end;
$$;

revoke all on function private.prepare_new_student_notifications()
from public, anon, authenticated;

drop trigger if exists prepare_new_student_notifications on public.profiles;
create trigger prepare_new_student_notifications
after insert on public.profiles
for each row execute function private.prepare_new_student_notifications();

-- Backfill default preferences for students created before this trigger.
insert into public.notification_preferences (user_id)
select id from public.profiles where role = 'student'
on conflict (user_id) do nothing;
