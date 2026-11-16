-- Student engagement completion: actionable notifications, moderated events,
-- and administrator-managed accommodation listings.

alter table public.events
  add column if not exists approval_status text not null default 'approved',
  add column if not exists submitted_by uuid references auth.users(id) on delete set null,
  add column if not exists reviewed_by uuid references auth.users(id) on delete set null,
  add column if not exists reviewed_at timestamptz,
  add column if not exists review_note text;

alter table public.events drop constraint if exists events_approval_status_check;
alter table public.events add constraint events_approval_status_check
  check (approval_status in ('pending', 'approved', 'rejected'));
alter table public.events alter column published set default false;

drop policy if exists "Students view published events" on public.events;
create policy "Students view approved events or own submissions"
on public.events for select to authenticated
using (
  (published and approval_status = 'approved')
  or submitted_by = (select auth.uid())
  or (select private.is_app_admin())
);

create policy "Students submit events for review"
on public.events for insert to authenticated
with check (
  submitted_by = (select auth.uid())
  and organizer_id = (select auth.uid())
  and approval_status = 'pending'
  and published = false
);

create policy "Students edit pending event submissions"
on public.events for update to authenticated
using (submitted_by = (select auth.uid()) and approval_status = 'pending')
with check (
  submitted_by = (select auth.uid())
  and organizer_id = (select auth.uid())
  and approval_status = 'pending'
  and published = false
);

create table if not exists public.accommodations (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  description text not null default '',
  address text not null,
  campus text not null default 'All campuses',
  distance_km numeric(7,2),
  monthly_price numeric(12,2) not null check (monthly_price >= 0),
  room_type text not null,
  nsfas_accredited boolean not null default false,
  verified_landlord boolean not null default false,
  amenities text[] not null default '{}',
  image_url text,
  contact_name text not null,
  contact_phone text not null,
  contact_email text,
  available_spaces integer check (available_spaces is null or available_spaces >= 0),
  is_active boolean not null default true,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.accommodations enable row level security;
grant select on public.accommodations to authenticated;
revoke insert, update, delete on public.accommodations from anon, authenticated;

create policy "Students view active accommodation"
on public.accommodations for select to authenticated
using (is_active or (select private.is_app_admin()));

do $$ begin
  alter publication supabase_realtime add table public.accommodations;
exception when duplicate_object then null;
end $$;

create or replace function private.notify_direct_message()
returns trigger language plpgsql security definer set search_path = '' as $$
declare sender_name text; preview text;
begin
  if new.is_deleted then return new; end if;
  if exists (select 1 from public.blocked_users where user_id = new.recipient_id and blocked_user_id = new.sender_id) then return new; end if;
  select coalesce(nullif(nickname, ''), 'A student') into sender_name from public.profiles where id = new.sender_id;
  preview := case
    when nullif(btrim(new.text), '') is not null then left(btrim(new.text), 180)
    when new.message_type = 'image' then 'Photo: ' || coalesce(new.attachment_name, 'image')
    when new.message_type = 'voice' then 'Voice message'
    when new.message_type = 'document' then 'Document: ' || coalesce(new.attachment_name, 'attachment')
    else 'New message'
  end;
  perform private.enqueue_student_notification(new.recipient_id, 'messages', sender_name,
    preview, 'chat', new.sender_id::text, new.sender_id,
    jsonb_build_object('kind', 'private_message', 'message_id', new.id), 'message:' || new.id::text);
  return new;
end $$;

create or replace function private.notify_group_message()
returns trigger language plpgsql security definer set search_path = '' as $$
declare member record; preview text; group_name text; sender_name text;
begin
  if new.is_deleted then return new; end if;
  select coalesce(nullif(name, ''), 'Group chat') into group_name from public.group_chats where id = new.group_id;
  select coalesce(nullif(nickname, ''), 'A member') into sender_name from public.profiles where id = new.sender_id;
  preview := case
    when nullif(btrim(new.text), '') is not null then sender_name || ': ' || left(btrim(new.text), 160)
    when new.message_type = 'image' then sender_name || ' sent a photo'
    when new.message_type = 'voice' then sender_name || ' sent a voice message'
    when new.message_type = 'document' then sender_name || ' sent ' || coalesce(new.attachment_name, 'a document')
    else sender_name || ' sent a message'
  end;
  for member in select user_id from public.group_members
    where group_id = new.group_id and user_id <> new.sender_id and not muted
  loop
    perform private.enqueue_student_notification(member.user_id, 'messages', group_name,
      preview, 'group_chats', new.group_id::text, new.sender_id,
      jsonb_build_object('kind', 'group_message', 'message_id', new.id, 'group_id', new.group_id),
      'group-message:' || new.id::text || ':' || member.user_id::text);
  end loop;
  return new;
end $$;

create or replace function private.notify_event_invitation()
returns trigger language plpgsql security definer set search_path = '' as $$
declare event_title text; sender_name text;
begin
  select coalesce(nullif(title, ''), 'Campus event') into event_title from public.events where id = new.event_id;
  select coalesce(nullif(nickname, ''), 'A friend') into sender_name from public.profiles where id = new.sender_id;
  perform private.enqueue_student_notification(new.receiver_id, 'campus', 'Event invitation',
    sender_name || ' invited you to ' || event_title || '.',
    'events', new.event_id::text, new.sender_id,
    jsonb_build_object('kind', 'event_invitation', 'invitation_id', new.id), 'event-invite:' || new.id::text);
  return new;
end $$;

create or replace function private.notify_published_event()
returns trigger language plpgsql security definer set search_path = '' as $$
declare student record;
begin
  if not new.published or new.approval_status <> 'approved' or new.status <> 'scheduled' then return new; end if;
  if tg_op = 'UPDATE' and old.published and old.approval_status = 'approved' then return new; end if;
  for student in select id from public.profiles where role = 'student' and (
    lower(new.campus) in ('all', 'all campuses', '') or lower(campus) = lower(new.campus)
  ) loop
    perform private.enqueue_student_notification(student.id, 'campus', 'New event: ' || left(new.title, 90),
      left(coalesce(nullif(new.description, ''), new.venue || ' · ' || new.date_label), 220),
      'events', new.id::text, new.organizer_id,
      jsonb_build_object('kind', 'event', 'date', new.date, 'venue', new.venue), 'event:' || new.id::text || ':' || student.id::text);
  end loop;
  return new;
end $$;

create or replace function private.notify_past_paper()
returns trigger language plpgsql security definer set search_path = '' as $$
declare registration record; module_label text;
begin
  if new.module_id is null then return new; end if;
  select coalesce(nullif(code, '') || ' · ' || nullif(name, ''), name, code, 'your module') into module_label from public.modules where id = new.module_id;
  for registration in select student_id from public.student_module_registrations where module_id = new.module_id and status = 'active'
  loop
    perform private.enqueue_student_notification(registration.student_id, 'academics', 'New past paper',
      left(new.title || ' · ' || module_label, 220), 'past_papers', new.id::text, null,
      jsonb_build_object('kind', 'past_paper', 'module_id', new.module_id, 'paper_title', new.title),
      'past-paper:' || new.id::text || ':' || registration.student_id::text);
  end loop;
  return new;
end $$;
revoke all on function private.notify_past_paper() from public, anon, authenticated;
drop trigger if exists notify_past_paper on public.past_papers;
create trigger notify_past_paper after insert on public.past_papers for each row execute function private.notify_past_paper();

create or replace function private.notify_lecture_slide()
returns trigger language plpgsql security definer set search_path = '' as $$
declare registration record; module_label text;
begin
  if new.module_id is null then return new; end if;
  select coalesce(nullif(code, '') || ' · ' || nullif(name, ''), name, code, 'your module') into module_label from public.modules where id = new.module_id;
  for registration in select student_id from public.student_module_registrations where module_id = new.module_id and status = 'active'
  loop
    perform private.enqueue_student_notification(registration.student_id, 'academics', 'New lecture slides',
      left(new.title || ' · ' || module_label, 220), 'lecture_slides', new.id::text, new.created_by,
      jsonb_build_object('kind', 'lecture_slides', 'module_id', new.module_id, 'slide_title', new.title),
      'lecture-slide:' || new.id::text || ':' || registration.student_id::text);
  end loop;
  return new;
end $$;
revoke all on function private.notify_lecture_slide() from public, anon, authenticated;
drop trigger if exists notify_lecture_slide on public.lecture_slides;
create trigger notify_lecture_slide after insert on public.lecture_slides for each row execute function private.notify_lecture_slide();

create index if not exists events_approval_queue_idx on public.events (approval_status, created_at desc);
create index if not exists accommodations_active_campus_idx on public.accommodations (is_active, campus);
create index if not exists student_notifications_unread_idx on public.student_notifications (user_id, category, created_at desc) where read_at is null;
