-- Keep notification content and deep links consistent across the staff,
-- admin and student applications. These private trigger functions only
-- enqueue records for the intended student.

create or replace function private.notify_direct_message()
returns trigger language plpgsql security definer set search_path = '' as $$
declare actor_name text; preview text;
begin
  if new.is_deleted then return new; end if;
  if exists (select 1 from public.blocked_users where user_id = new.recipient_id and blocked_user_id = new.sender_id) then return new; end if;
  select nullif(btrim(nickname), '') into actor_name from public.profiles where id = new.sender_id;
  preview := left(regexp_replace(coalesce(new.text, ''), '\s+', ' ', 'g'), 240);
  if preview = '' then
    preview := case
      when new.message_type = 'image' then coalesce(new.attachment_name, 'Photo')
      when new.message_type = 'video' then coalesce(new.attachment_name, 'Video')
      when new.message_type in ('voice', 'audio') then 'Voice message'
      when new.message_type = 'document' then coalesce(new.attachment_name, 'Document')
      else 'New message' end;
  end if;
  perform private.enqueue_student_notification(
    new.recipient_id, 'messages', coalesce(actor_name, 'A student') || ' sent you a message',
    preview, 'chat', new.sender_id::text, new.sender_id,
    jsonb_build_object('kind', 'direct_message', 'message_id', new.id, 'sender_id', new.sender_id),
    'message:' || new.id::text
  );
  return new;
end; $$;
revoke all on function private.notify_direct_message() from public, anon, authenticated;

create or replace function private.notify_group_message()
returns trigger language plpgsql security definer set search_path = '' as $$
declare member record; actor_name text; group_name text; preview text;
begin
  if new.is_deleted then return new; end if;
  select nullif(btrim(nickname), '') into actor_name from public.profiles where id = new.sender_id;
  select nullif(btrim(name), '') into group_name from public.group_chats where id = new.group_id;
  preview := left(regexp_replace(coalesce(new.text, ''), '\s+', ' ', 'g'), 240);
  if preview = '' then
    preview := case
      when new.message_type = 'image' then coalesce(new.attachment_name, 'Photo')
      when new.message_type = 'video' then coalesce(new.attachment_name, 'Video')
      when new.message_type in ('voice', 'audio') then 'Voice message'
      when new.message_type = 'document' then coalesce(new.attachment_name, 'Document')
      else 'New group message' end;
  end if;
  for member in select user_id from public.group_members where group_id = new.group_id and user_id <> new.sender_id and not muted loop
    perform private.enqueue_student_notification(
      member.user_id, 'messages', coalesce(group_name, 'Group chat') || ' · ' || coalesce(actor_name, 'New message'),
      preview, 'group_chats', new.group_id::text, new.sender_id,
      jsonb_build_object('kind', 'group_message', 'message_id', new.id, 'group_id', new.group_id),
      'group-message:' || new.id::text || ':' || member.user_id::text
    );
  end loop;
  return new;
end; $$;
revoke all on function private.notify_group_message() from public, anon, authenticated;

create or replace function private.notify_announcement()
returns trigger language plpgsql security definer set search_path = '' as $$
declare student record; urgency text; preview text;
begin
  if new.section <> 'announcements' or not new.is_active then return new; end if;
  if tg_op = 'UPDATE' and old.is_active then return new; end if;
  urgency := coalesce(new.data->>'urgency', 'info');
  preview := left(coalesce(nullif(btrim(new.data->>'body'), ''), nullif(btrim(new.subtitle), ''), 'Open Alerts to read this update.'), 500);
  for student in select id from public.profiles where role = 'student' loop
    perform private.enqueue_student_notification(
      student.id, 'campus',
      coalesce(nullif(btrim(new.title), ''), case when urgency = 'critical' then 'Important campus alert' else 'Campus update' end),
      preview, 'alerts', new.id::text, new.created_by,
      jsonb_build_object('kind', 'official_alert', 'urgency', urgency, 'alert_id', new.id),
      'announcement:' || new.id::text || ':' || student.id::text
    );
  end loop;
  return new;
end; $$;
revoke all on function private.notify_announcement() from public, anon, authenticated;

create or replace function private.notify_quiz()
returns trigger language plpgsql security definer set search_path = '' as $$
declare registration record; module_label text;
begin
  if not new.published or new.module_id is null then return new; end if;
  if tg_op = 'UPDATE' and old.published then return new; end if;
  select coalesce(nullif(btrim(code || ' · ' || name), ''), name, code, 'Your module')
    into module_label from public.modules where id = new.module_id;
  for registration in select student_id from public.student_module_registrations where module_id = new.module_id and status = 'active' loop
    perform private.enqueue_student_notification(
      registration.student_id, 'academics', coalesce(nullif(btrim(new.title), ''), 'New quiz'),
      module_label || case when new.closes_at is null then ' · Available now' else ' · Complete before ' || to_char(new.closes_at at time zone 'Africa/Johannesburg', 'DD Mon HH24:MI') end,
      'quizzes', new.id::text, new.lecturer_id,
      jsonb_build_object('kind', 'quiz', 'quiz_id', new.id, 'module_id', new.module_id, 'closes_at', new.closes_at),
      'quiz:' || new.id::text || ':' || registration.student_id::text
    );
  end loop;
  return new;
end; $$;
revoke all on function private.notify_quiz() from public, anon, authenticated;

create or replace function private.notify_assessment()
returns trigger language plpgsql security definer set search_path = '' as $$
declare registration record; module_label text;
begin
  if not new.published or new.module_id is null then return new; end if;
  if tg_op = 'UPDATE' and old.published then return new; end if;
  select coalesce(nullif(btrim(code || ' · ' || name), ''), name, code, 'Your module')
    into module_label from public.modules where id = new.module_id;
  for registration in select student_id from public.student_module_registrations where module_id = new.module_id and status = 'active' loop
    perform private.enqueue_student_notification(
      registration.student_id, 'academics', coalesce(nullif(btrim(new.title), ''), 'New assessment'),
      module_label || case when new.due_at is null then ' · Open for details' else ' · Due ' || to_char(new.due_at at time zone 'Africa/Johannesburg', 'DD Mon HH24:MI') end,
      'assessments', new.id::text, new.lecturer_id,
      jsonb_build_object('kind', 'assessment', 'brief_id', new.id, 'module_id', new.module_id, 'due_at', new.due_at),
      'assessment:' || new.id::text || ':' || registration.student_id::text
    );
  end loop;
  return new;
end; $$;
revoke all on function private.notify_assessment() from public, anon, authenticated;

create or replace function private.notify_online_class()
returns trigger language plpgsql security definer set search_path = '' as $$
declare registration record; class_title text; module_label text;
begin
  if new.module_id is null then return new; end if;
  class_title := coalesce(nullif(btrim(new.topic), ''), nullif(btrim(new.subject), ''), 'Online class');
  select coalesce(nullif(btrim(code || ' · ' || name), ''), name, code, 'Your module')
    into module_label from public.modules where id = new.module_id;
  for registration in select student_id from public.student_module_registrations where module_id = new.module_id and status = 'active' loop
    perform private.enqueue_student_notification(
      registration.student_id, 'academics', class_title,
      module_label || case when new.scheduled_at is null then ' · Online class' else ' · ' || to_char(new.scheduled_at at time zone 'Africa/Johannesburg', 'DD Mon HH24:MI') end,
      'online_classes', new.id::text, new.lecturer_id,
      jsonb_build_object('kind', 'online_class', 'class_id', new.id, 'module_id', new.module_id, 'scheduled_at', new.scheduled_at),
      'online-class:' || new.id::text || ':' || registration.student_id::text
    );
  end loop;
  return new;
end; $$;
revoke all on function private.notify_online_class() from public, anon, authenticated;

create or replace function private.notify_published_event()
returns trigger language plpgsql security definer set search_path = '' as $$
declare student record;
begin
  if not new.published or new.approval_status <> 'approved' or new.status <> 'scheduled' then return new; end if;
  if tg_op = 'UPDATE' and old.published and old.approval_status = 'approved' then return new; end if;
  for student in select id from public.profiles
    where role = 'student' and (
      lower(coalesce(new.campus, '')) in ('all', 'all campuses', '') or lower(campus) = lower(new.campus)
    )
  loop
    perform private.enqueue_student_notification(
      student.id, 'campus', coalesce(nullif(btrim(new.title), ''), 'New campus event'),
      coalesce(nullif(btrim(new.venue), ''), 'Campus event') || case when new.date is null then '' else ' · ' || to_char(new.date at time zone 'Africa/Johannesburg', 'DD Mon HH24:MI') end,
      'events', new.id::text, new.organizer_id,
      jsonb_build_object('kind', 'event', 'event_id', new.id, 'date', new.date),
      'event:' || new.id::text || ':' || student.id::text
    );
  end loop;
  return new;
end; $$;
revoke all on function private.notify_published_event() from public, anon, authenticated;

comment on function private.notify_direct_message() is
  'Creates private-message notifications with a safe preview and peer deep link.';
comment on function private.notify_group_message() is
  'Creates group-message notifications with group and sender context.';
