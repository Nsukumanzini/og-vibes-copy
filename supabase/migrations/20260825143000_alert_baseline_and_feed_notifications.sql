-- New students start with every alert that predates their profile marked read.
-- Only alerts published after registration should light the Alerts bell.
create or replace function private.prepare_new_student_notifications()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.role <> 'student' then
    return new;
  end if;

  insert into public.notification_preferences (user_id)
  values (new.id)
  on conflict (user_id) do nothing;

  insert into public.alert_reads (user_id, alert_id, read_at)
  select new.id, content.id, coalesce(new.created_at, now())
  from public.app_content content
  where content.section = 'announcements'
    and content.is_active
    and content.created_at <= coalesce(new.created_at, now())
  on conflict (user_id, alert_id) do nothing;

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

  return new;
end;
$$;

revoke all on function private.prepare_new_student_notifications()
from public, anon, authenticated;

create or replace function private.notify_comment()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  target uuid;
  actor_name text;
  preview text;
begin
  if new.parent_id is not null then
    select author_id into target from public.comments where id = new.parent_id;
  else
    select user_id into target from public.posts where id = new.post_id;
  end if;
  select nullif(btrim(nickname), '') into actor_name
  from public.profiles where id = new.author_id;
  preview := left(regexp_replace(coalesce(new.text, ''), '\\s+', ' ', 'g'), 180);

  perform private.enqueue_student_notification(
    target,
    'social',
    coalesce(actor_name, 'A student') ||
      case when new.parent_id is null then ' commented on your post' else ' replied to your comment' end,
    case when preview = '' then 'Open your post to see the response.' else preview end,
    'feed',
    new.post_id::text,
    new.author_id,
    jsonb_build_object('kind', 'post_comment', 'post_id', new.post_id, 'comment_id', new.id),
    'comment:' || new.id::text || ':' || target::text
  );
  return new;
end;
$$;

revoke all on function private.notify_comment() from public, anon, authenticated;

create or replace function private.notify_post_like()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  target uuid;
  actor_name text;
  post_preview text;
begin
  select user_id,
         left(regexp_replace(coalesce(content, ''), '\\s+', ' ', 'g'), 120)
  into target, post_preview
  from public.posts
  where id = new.post_id;

  select nullif(btrim(nickname), '') into actor_name
  from public.profiles where id = new.user_id;

  perform private.enqueue_student_notification(
    target,
    'social',
    coalesce(actor_name, 'A student') || ' liked your post',
    case when post_preview = '' then 'Open your post to see the activity.' else post_preview end,
    'feed',
    new.post_id::text,
    new.user_id,
    jsonb_build_object('kind', 'post_like', 'post_id', new.post_id),
    'post-like:' || new.post_id::text || ':' || new.user_id::text
  );
  return new;
end;
$$;

revoke all on function private.notify_post_like() from public, anon, authenticated;
