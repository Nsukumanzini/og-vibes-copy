-- Make lock-screen notifications useful without requiring the student to open
-- the app first. Private marks are intentionally not included in previews.

create or replace function private.notify_announcement()
returns trigger language plpgsql security definer set search_path = '' as $$
declare student record; urgency text; alert_title text; alert_body text;
begin
  if new.section <> 'announcements' or not new.is_active then return new; end if;
  if tg_op = 'UPDATE' and old.is_active then return new; end if;
  urgency := coalesce(new.data->>'urgency', 'info');
  alert_title := coalesce(
    nullif(btrim(new.title), ''),
    case when urgency = 'critical' then 'Important campus alert' else 'Campus update' end
  );
  alert_body := coalesce(
    nullif(btrim(new.data->>'body'), ''),
    nullif(btrim(new.subtitle), ''),
    'Open Alerts to read this campus update.'
  );
  for student in select id from public.profiles where role = 'student' loop
    perform private.enqueue_student_notification(
      student.id, 'campus', alert_title, alert_body, 'alerts', new.id::text,
      new.created_by, jsonb_build_object('urgency', urgency, 'kind', 'alert'),
      'announcement:' || new.id::text || ':' || student.id::text
    );
  end loop;
  return new;
end $$;

create or replace function private.notify_quiz()
returns trigger language plpgsql security definer set search_path = '' as $$
declare registration record; module_label text;
begin
  if not new.published or new.module_id is null then return new; end if;
  if tg_op = 'UPDATE' and old.published then return new; end if;
  select coalesce(nullif(code, ''), nullif(name, ''), 'Your module')
  into module_label from public.modules where id = new.module_id;
  for registration in select student_id from public.student_module_registrations
    where module_id = new.module_id and status = 'active'
  loop
    perform private.enqueue_student_notification(
      registration.student_id, 'academics', 'New quiz · ' || left(module_label, 90),
      left(new.title, 220), 'quizzes', new.id::text, new.lecturer_id,
      jsonb_build_object('module_id', new.module_id, 'closes_at', new.closes_at, 'kind', 'quiz'),
      'quiz:' || new.id::text || ':' || registration.student_id::text
    );
  end loop;
  return new;
end $$;

create or replace function private.notify_assessment()
returns trigger language plpgsql security definer set search_path = '' as $$
declare registration record; module_label text;
begin
  if not new.published or new.module_id is null then return new; end if;
  if tg_op = 'UPDATE' and old.published then return new; end if;
  select coalesce(nullif(code, ''), nullif(name, ''), 'Your module')
  into module_label from public.modules where id = new.module_id;
  for registration in select student_id from public.student_module_registrations
    where module_id = new.module_id and status = 'active'
  loop
    perform private.enqueue_student_notification(
      registration.student_id, 'academics', 'New assessment · ' || left(module_label, 84),
      left(new.title, 220), 'assessments', new.id::text, new.lecturer_id,
      jsonb_build_object('module_id', new.module_id, 'due_at', new.due_at, 'kind', 'assessment'),
      'assessment:' || new.id::text || ':' || registration.student_id::text
    );
  end loop;
  return new;
end $$;

create or replace function private.notify_online_class()
returns trigger language plpgsql security definer set search_path = '' as $$
declare registration record; module_label text; class_title text;
begin
  if new.module_id is null then return new; end if;
  select coalesce(nullif(code, ''), nullif(name, ''), 'Your module')
  into module_label from public.modules where id = new.module_id;
  class_title := coalesce(nullif(btrim(new.topic), ''), nullif(btrim(new.subject), ''), 'Online class');
  for registration in select student_id from public.student_module_registrations
    where module_id = new.module_id and status = 'active'
  loop
    perform private.enqueue_student_notification(
      registration.student_id, 'academics', 'Online class · ' || left(module_label, 88),
      left(class_title, 220), 'online_classes', new.id::text, new.lecturer_id,
      jsonb_build_object('module_id', new.module_id, 'scheduled_at', new.scheduled_at, 'kind', 'online_class'),
      'online-class:' || new.id::text || ':' || registration.student_id::text
    );
  end loop;
  return new;
end $$;

create or replace function private.notify_icass_mark()
returns trigger language plpgsql security definer set search_path = '' as $$
declare mark_label text;
begin
  if not new.published then return new; end if;
  if tg_op = 'UPDATE' and old.published then return new; end if;
  mark_label := concat_ws(' · ', nullif(new.subject_name, ''), nullif(new.component_name, ''));
  perform private.enqueue_student_notification(
    new.student_id, 'academics', 'New ICASS result',
    coalesce(nullif(mark_label, ''), 'A new result has been published.'),
    'icass', new.id::text, null,
    jsonb_build_object('module_id', new.module_id, 'kind', 'icass'),
    'icass:' || new.id::text
  );
  return new;
end $$;

revoke all on function private.notify_announcement() from public, anon, authenticated;
revoke all on function private.notify_quiz() from public, anon, authenticated;
revoke all on function private.notify_assessment() from public, anon, authenticated;
revoke all on function private.notify_online_class() from public, anon, authenticated;
revoke all on function private.notify_icass_mark() from public, anon, authenticated;
