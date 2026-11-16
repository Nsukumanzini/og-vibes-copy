create schema if not exists private;

create table if not exists public.notification_preferences (
  user_id uuid primary key references auth.users(id) on delete cascade,
  messages boolean not null default true,
  academics boolean not null default true,
  campus boolean not null default true,
  social boolean not null default true,
  marketplace boolean not null default true,
  updated_at timestamptz not null default now()
);

alter table public.notification_preferences enable row level security;
revoke all on table public.notification_preferences from anon;
grant select, insert, update on table public.notification_preferences to authenticated;
grant all on table public.notification_preferences to service_role;

drop policy if exists "Users read own notification preferences" on public.notification_preferences;
create policy "Users read own notification preferences"
on public.notification_preferences for select to authenticated
using ((select auth.uid()) = user_id);

drop policy if exists "Users create own notification preferences" on public.notification_preferences;
create policy "Users create own notification preferences"
on public.notification_preferences for insert to authenticated
with check ((select auth.uid()) = user_id);

drop policy if exists "Users update own notification preferences" on public.notification_preferences;
create policy "Users update own notification preferences"
on public.notification_preferences for update to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

create table if not exists public.student_notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  category text not null check (category in ('messages', 'academics', 'campus', 'social', 'marketplace')),
  title text not null check (char_length(title) between 1 and 120),
  body text not null check (char_length(body) between 1 and 500),
  route text not null check (char_length(route) between 1 and 80),
  entity_id text,
  actor_id uuid references auth.users(id) on delete set null,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata) = 'object'),
  dedupe_key text unique,
  created_at timestamptz not null default now(),
  pushed_at timestamptz,
  delivery_status text not null default 'pending'
    check (delivery_status in ('pending', 'processing', 'sent', 'partial', 'failed', 'suppressed', 'no_devices')),
  delivery_error text,
  read_at timestamptz
);

alter table public.student_notifications enable row level security;
revoke all on table public.student_notifications from anon;
grant select on table public.student_notifications to authenticated;
grant update (read_at) on table public.student_notifications to authenticated;
grant all on table public.student_notifications to service_role;

drop policy if exists "Users read own notifications" on public.student_notifications;
create policy "Users read own notifications"
on public.student_notifications for select to authenticated
using ((select auth.uid()) = user_id);

drop policy if exists "Users acknowledge own notifications" on public.student_notifications;
create policy "Users acknowledge own notifications"
on public.student_notifications for update to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

create index if not exists student_notifications_user_created_idx
  on public.student_notifications (user_id, created_at desc);
create index if not exists student_notifications_pending_idx
  on public.student_notifications (created_at) where pushed_at is null;

create table if not exists public.notification_webhook_config (
  singleton boolean primary key default true check (singleton),
  secret text not null check (char_length(secret) >= 32),
  created_at timestamptz not null default now()
);
alter table public.notification_webhook_config enable row level security;
revoke all on table public.notification_webhook_config from anon, authenticated;
grant all on table public.notification_webhook_config to service_role;
insert into public.notification_webhook_config (singleton, secret)
values (true, encode(gen_random_bytes(32), 'hex'))
on conflict (singleton) do nothing;

create or replace function private.enqueue_student_notification(
  target_user uuid,
  notification_category text,
  notification_title text,
  notification_body text,
  destination_route text,
  destination_entity text default null,
  source_actor uuid default null,
  extra_metadata jsonb default '{}'::jsonb,
  unique_key text default null
) returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if target_user is null or target_user = source_actor then return; end if;
  insert into public.student_notifications (
    user_id, category, title, body, route, entity_id, actor_id, metadata, dedupe_key
  ) values (
    target_user,
    notification_category,
    left(notification_title, 120),
    left(notification_body, 500),
    destination_route,
    destination_entity,
    source_actor,
    coalesce(extra_metadata, '{}'::jsonb),
    unique_key
  ) on conflict (dedupe_key) do nothing;
end;
$$;
revoke all on function private.enqueue_student_notification(uuid,text,text,text,text,text,uuid,jsonb,text) from public, anon, authenticated;

create or replace function private.dispatch_student_notification()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  webhook_secret text;
begin
  select secret into webhook_secret
  from public.notification_webhook_config
  where singleton = true;
  if webhook_secret is null then return new; end if;
  perform net.http_post(
    url := 'https://qcxqmsczkbtfimluinig.supabase.co/functions/v1/notification-push',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-og-notification-secret', webhook_secret
    ),
    body := jsonb_build_object('notification_id', new.id),
    timeout_milliseconds := 5000
  );
  return new;
end;
$$;
revoke all on function private.dispatch_student_notification() from public, anon, authenticated;

drop trigger if exists dispatch_student_notification on public.student_notifications;
create trigger dispatch_student_notification
after insert on public.student_notifications
for each row execute function private.dispatch_student_notification();

create or replace function private.notify_direct_message()
returns trigger language plpgsql security definer set search_path = '' as $$
declare preview text;
begin
  if new.is_deleted then return new; end if;
  if exists (
    select 1 from public.blocked_users
    where user_id = new.recipient_id and blocked_user_id = new.sender_id
  ) then return new; end if;
  preview := case
    when new.message_type = 'image' then 'Sent you a photo'
    when new.message_type = 'voice' then 'Sent you a voice message'
    when new.message_type = 'document' then 'Sent you a document'
    else 'Sent you a new message'
  end;
  perform private.enqueue_student_notification(new.recipient_id, 'messages', 'New private message',
    preview, 'messages', null, new.sender_id,
    jsonb_build_object('message_id', new.id), 'message:' || new.id::text);
  return new;
end; $$;
revoke all on function private.notify_direct_message() from public, anon, authenticated;
drop trigger if exists notify_direct_message on public.messages;
create trigger notify_direct_message after insert on public.messages
for each row execute function private.notify_direct_message();

create or replace function private.notify_group_message()
returns trigger language plpgsql security definer set search_path = '' as $$
declare member record; preview text;
begin
  if new.is_deleted then return new; end if;
  preview := case
    when new.message_type = 'image' then 'A member sent a photo'
    when new.message_type = 'voice' then 'A member sent a voice message'
    when new.message_type = 'document' then 'A member sent a document'
    else 'A member sent a new message'
  end;
  for member in select user_id from public.group_members
    where group_id = new.group_id and user_id <> new.sender_id and not muted
  loop
    perform private.enqueue_student_notification(member.user_id, 'messages',
      'New group message', preview, 'group_chats', null,
      new.sender_id, jsonb_build_object('message_id', new.id, 'group_id', new.group_id),
      'group-message:' || new.id::text || ':' || member.user_id::text);
  end loop;
  return new;
end; $$;
revoke all on function private.notify_group_message() from public, anon, authenticated;
drop trigger if exists notify_group_message on public.group_messages;
create trigger notify_group_message after insert on public.group_messages
for each row execute function private.notify_group_message();

create or replace function private.notify_announcement()
returns trigger language plpgsql security definer set search_path = '' as $$
declare student record; urgency text;
begin
  if new.section <> 'announcements' or not new.is_active then return new; end if;
  if tg_op = 'UPDATE' and old.is_active then return new; end if;
  urgency := coalesce(new.data->>'urgency', 'info');
  for student in select id from public.profiles where role = 'student' loop
    perform private.enqueue_student_notification(student.id, 'campus',
      case when urgency = 'critical' then 'Important campus alert' else 'New campus update' end,
      'Open Alerts to read the campus update.', 'alerts', null, new.created_by,
      jsonb_build_object('urgency', urgency), 'announcement:' || new.id::text || ':' || student.id::text);
  end loop;
  return new;
end; $$;
revoke all on function private.notify_announcement() from public, anon, authenticated;
drop trigger if exists notify_announcement on public.app_content;
create trigger notify_announcement after insert or update of is_active on public.app_content
for each row execute function private.notify_announcement();

create or replace function private.notify_quiz()
returns trigger language plpgsql security definer set search_path = '' as $$
declare registration record; module_label text;
begin
  if not new.published or new.module_id is null then return new; end if;
  if tg_op = 'UPDATE' and old.published then return new; end if;
  select coalesce(code || ' · ' || name, name, code, 'your module') into module_label
  from public.modules where id = new.module_id;
  for registration in select student_id from public.student_module_registrations
    where module_id = new.module_id and status = 'active'
  loop
    perform private.enqueue_student_notification(registration.student_id, 'academics',
      'New quiz available', 'A quiz was published for one of your modules.',
      'quizzes', null, new.lecturer_id,
      jsonb_build_object('module_id', new.module_id, 'closes_at', new.closes_at),
      'quiz:' || new.id::text || ':' || registration.student_id::text);
  end loop;
  return new;
end; $$;
revoke all on function private.notify_quiz() from public, anon, authenticated;
drop trigger if exists notify_quiz on public.quizzes;
create trigger notify_quiz after insert or update of published on public.quizzes
for each row execute function private.notify_quiz();

create or replace function private.notify_assessment()
returns trigger language plpgsql security definer set search_path = '' as $$
declare registration record; module_label text;
begin
  if not new.published or new.module_id is null then return new; end if;
  if tg_op = 'UPDATE' and old.published then return new; end if;
  select coalesce(code || ' · ' || name, name, code, 'your module') into module_label
  from public.modules where id = new.module_id;
  for registration in select student_id from public.student_module_registrations
    where module_id = new.module_id and status = 'active'
  loop
    perform private.enqueue_student_notification(registration.student_id, 'academics',
      'New assessment available', 'An assessment was published for one of your modules.',
      'assessments', null, new.lecturer_id,
      jsonb_build_object('module_id', new.module_id, 'due_at', new.due_at),
      'assessment:' || new.id::text || ':' || registration.student_id::text);
  end loop;
  return new;
end; $$;
revoke all on function private.notify_assessment() from public, anon, authenticated;
drop trigger if exists notify_assessment on public.assessment_briefs;
create trigger notify_assessment after insert or update of published on public.assessment_briefs
for each row execute function private.notify_assessment();

create or replace function private.notify_online_class()
returns trigger language plpgsql security definer set search_path = '' as $$
declare registration record; class_title text;
begin
  if new.module_id is null then return new; end if;
  class_title := coalesce(nullif(btrim(new.topic), ''), nullif(btrim(new.subject), ''), 'Online class');
  for registration in select student_id from public.student_module_registrations
    where module_id = new.module_id and status = 'active'
  loop
    perform private.enqueue_student_notification(registration.student_id, 'academics',
      'Online class scheduled', 'A new online class was scheduled for your module.', 'online_classes', null, new.lecturer_id,
      jsonb_build_object('module_id', new.module_id, 'scheduled_at', new.scheduled_at),
      'online-class:' || new.id::text || ':' || registration.student_id::text);
  end loop;
  return new;
end; $$;
revoke all on function private.notify_online_class() from public, anon, authenticated;
drop trigger if exists notify_online_class on public.online_classes;
create trigger notify_online_class after insert on public.online_classes
for each row execute function private.notify_online_class();

create or replace function private.notify_icass_mark()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if not new.published then return new; end if;
  if tg_op = 'UPDATE' and old.published then return new; end if;
  perform private.enqueue_student_notification(new.student_id, 'academics',
    'New ICASS mark available', 'A new mark has been published. Open OG Vibes to view it.',
    'icass', null, null,
    jsonb_build_object('module_id', new.module_id), 'icass:' || new.id::text);
  return new;
end; $$;
revoke all on function private.notify_icass_mark() from public, anon, authenticated;
drop trigger if exists notify_icass_mark on public.icass_marks;
create trigger notify_icass_mark after insert or update of published on public.icass_marks
for each row execute function private.notify_icass_mark();

create or replace function private.notify_friend_request()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.status <> 'pending' then return new; end if;
  perform private.enqueue_student_notification(new.receiver_id, 'social', 'New friend request',
    'A student wants to connect with you.', 'friends', null, new.sender_id,
    '{}'::jsonb, 'friend-request:' || new.id::text);
  return new;
end; $$;
revoke all on function private.notify_friend_request() from public, anon, authenticated;
drop trigger if exists notify_friend_request on public.friend_requests;
create trigger notify_friend_request after insert on public.friend_requests
for each row execute function private.notify_friend_request();

create or replace function private.notify_event_invitation()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  perform private.enqueue_student_notification(new.receiver_id, 'campus', 'Event invitation',
    'You were invited to a campus event.',
    'events', null, new.sender_id, '{}'::jsonb,
    'event-invite:' || new.id::text);
  return new;
end; $$;
revoke all on function private.notify_event_invitation() from public, anon, authenticated;
drop trigger if exists notify_event_invitation on public.event_invitations;
create trigger notify_event_invitation after insert on public.event_invitations
for each row execute function private.notify_event_invitation();

create or replace function private.notify_published_event()
returns trigger language plpgsql security definer set search_path = '' as $$
declare student record;
begin
  if not new.published or new.status <> 'scheduled' then return new; end if;
  if tg_op = 'UPDATE' and old.published then return new; end if;
  for student in select id from public.profiles
    where role = 'student' and (
      lower(new.campus) in ('all', 'all campuses', '') or lower(campus) = lower(new.campus)
    )
  loop
    perform private.enqueue_student_notification(student.id, 'campus', 'New campus event',
      'A new event was published for your campus.', 'events', null, new.organizer_id,
      jsonb_build_object('date', new.date), 'event:' || new.id::text || ':' || student.id::text);
  end loop;
  return new;
end; $$;
revoke all on function private.notify_published_event() from public, anon, authenticated;
drop trigger if exists notify_published_event on public.events;
create trigger notify_published_event after insert or update of published on public.events
for each row execute function private.notify_published_event();

create or replace function private.notify_marketplace_order()
returns trigger language plpgsql security definer set search_path = '' as $$
declare target uuid; title_text text; body_text text;
begin
  if tg_op = 'INSERT' then
    target := new.seller_id;
    title_text := case when new.kind = 'offer' then 'New price offer' else 'New marketplace order' end;
    body_text := 'One of your listings has new buyer activity.';
  else
    if old.status = new.status then return new; end if;
    target := case when (select auth.uid()) = new.seller_id then new.buyer_id else new.seller_id end;
    title_text := 'Order updated';
    body_text := 'A marketplace order status has changed.';
  end if;
  perform private.enqueue_student_notification(target, 'marketplace', title_text, body_text,
    'marketplace', new.id::text, (select auth.uid()),
    jsonb_build_object('product_id', new.product_id, 'status', new.status),
    'market-order:' || new.id::text || ':' || new.status || ':' || target::text);
  return new;
end; $$;
revoke all on function private.notify_marketplace_order() from public, anon, authenticated;
drop trigger if exists notify_marketplace_order on public.marketplace_orders;
create trigger notify_marketplace_order after insert or update of status on public.marketplace_orders
for each row execute function private.notify_marketplace_order();

create or replace function private.notify_lost_found_claim()
returns trigger language plpgsql security definer set search_path = '' as $$
declare target uuid; title_text text; body_text text;
begin
  select user_id into target from public.lost_and_found_items where id = new.item_id;
  if tg_op = 'INSERT' then
    title_text := 'New lost-and-found claim';
    body_text := 'Someone submitted a claim for one of your reports.';
  else
    if old.status = new.status then return new; end if;
    target := new.claimant_id;
    title_text := 'Claim status updated';
    body_text := 'The status of one of your claims has changed.';
  end if;
  perform private.enqueue_student_notification(target, 'social', title_text, body_text,
    'lost_found', new.item_id::text, (select auth.uid()),
    jsonb_build_object('claim_id', new.id, 'status', new.status),
    'lost-claim:' || new.id::text || ':' || new.status || ':' || target::text);
  return new;
end; $$;
revoke all on function private.notify_lost_found_claim() from public, anon, authenticated;
drop trigger if exists notify_lost_found_claim on public.lost_and_found_claims;
create trigger notify_lost_found_claim after insert or update of status on public.lost_and_found_claims
for each row execute function private.notify_lost_found_claim();

create or replace function private.notify_comment()
returns trigger language plpgsql security definer set search_path = '' as $$
declare target uuid;
begin
  if new.parent_id is not null then
    select author_id into target from public.comments where id = new.parent_id;
  else
    select user_id into target from public.posts where id = new.post_id;
  end if;
  perform private.enqueue_student_notification(target, 'social',
    case when new.parent_id is null then 'New comment' else 'New reply' end,
    'Someone responded to your post activity.', 'feed', null, new.author_id,
    jsonb_build_object('comment_id', new.id), 'comment:' || new.id::text || ':' || target::text);
  return new;
end; $$;
revoke all on function private.notify_comment() from public, anon, authenticated;
drop trigger if exists notify_comment on public.comments;
create trigger notify_comment after insert on public.comments
for each row execute function private.notify_comment();

create or replace function private.notify_post_like()
returns trigger language plpgsql security definer set search_path = '' as $$
declare target uuid;
begin
  select user_id into target from public.posts where id = new.post_id;
  perform private.enqueue_student_notification(target, 'social', 'New post like',
    'Someone liked your post.', 'feed', null, new.user_id,
    '{}'::jsonb, 'post-like:' || new.post_id::text || ':' || new.user_id::text);
  return new;
end; $$;
revoke all on function private.notify_post_like() from public, anon, authenticated;
drop trigger if exists notify_post_like on public.post_likes;
create trigger notify_post_like after insert on public.post_likes
for each row execute function private.notify_post_like();

comment on table public.student_notifications is
  'Secure per-student notification outbox and in-app notification history.';
comment on table public.notification_preferences is
  'Per-student push category preferences. Missing rows use enabled defaults.';
