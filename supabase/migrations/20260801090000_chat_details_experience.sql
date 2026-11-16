alter table public.messages
  add column if not exists attachment_name text,
  add column if not exists attachment_mime text,
  add column if not exists attachment_size bigint,
  add column if not exists metadata jsonb not null default '{}'::jsonb,
  add column if not exists delivered_at timestamptz not null default now(),
  add column if not exists read_at timestamptz;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'messages_attachment_size_valid'
      and conrelid = 'public.messages'::regclass
  ) then
    alter table public.messages
      add constraint messages_attachment_size_valid
      check (
        attachment_size is null
        or (attachment_size >= 0 and attachment_size <= 26214400)
      );
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'messages_type_valid'
      and conrelid = 'public.messages'::regclass
  ) then
    alter table public.messages
      add constraint messages_type_valid
      check (message_type in ('text', 'link', 'image', 'video', 'audio', 'document'));
  end if;
end
$$;

create index if not exists messages_direct_chat_created_idx
  on public.messages (sender_id, recipient_id, created_at desc)
  where is_deleted = false;
create index if not exists messages_recipient_unread_idx
  on public.messages (recipient_id, created_at desc)
  where is_read = false and is_deleted = false;

create table if not exists public.message_reactions (
  message_id uuid not null references public.messages(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  emoji text not null check (char_length(emoji) between 1 and 16),
  created_at timestamptz not null default now(),
  primary key (message_id, user_id, emoji)
);

create index if not exists message_reactions_user_idx
  on public.message_reactions (user_id);

alter table public.message_reactions enable row level security;

drop policy if exists "Chat participants view message reactions"
  on public.message_reactions;
create policy "Chat participants view message reactions"
  on public.message_reactions
  for select
  to authenticated
  using (
    exists (
      select 1 from public.messages message
      where message.id = message_id
        and (
          message.sender_id = (select auth.uid())
          or message.recipient_id = (select auth.uid())
        )
    )
  );

drop policy if exists "Chat participants add own reactions"
  on public.message_reactions;
create policy "Chat participants add own reactions"
  on public.message_reactions
  for insert
  to authenticated
  with check (
    user_id = (select auth.uid())
    and exists (
      select 1 from public.messages message
      where message.id = message_id
        and (
          message.sender_id = (select auth.uid())
          or message.recipient_id = (select auth.uid())
        )
    )
  );

drop policy if exists "Users remove own message reactions"
  on public.message_reactions;
create policy "Users remove own message reactions"
  on public.message_reactions
  for delete
  to authenticated
  using (user_id = (select auth.uid()));

revoke all on table public.message_reactions from anon;
grant select, insert, delete
  on table public.message_reactions to authenticated;

create table if not exists public.chat_typing_status (
  user_id uuid not null references public.profiles(id) on delete cascade,
  peer_id uuid not null references public.profiles(id) on delete cascade,
  is_typing boolean not null default false,
  updated_at timestamptz not null default now(),
  primary key (user_id, peer_id),
  constraint chat_typing_status_not_self check (user_id <> peer_id)
);

create index if not exists chat_typing_status_peer_updated_idx
  on public.chat_typing_status (peer_id, updated_at desc);

alter table public.chat_typing_status enable row level security;

drop policy if exists "Chat participants view typing status"
  on public.chat_typing_status;
create policy "Chat participants view typing status"
  on public.chat_typing_status
  for select
  to authenticated
  using (
    user_id = (select auth.uid())
    or peer_id = (select auth.uid())
  );

drop policy if exists "Users create own typing status"
  on public.chat_typing_status;
create policy "Users create own typing status"
  on public.chat_typing_status
  for insert
  to authenticated
  with check (user_id = (select auth.uid()));

drop policy if exists "Users update own typing status"
  on public.chat_typing_status;
create policy "Users update own typing status"
  on public.chat_typing_status
  for update
  to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

drop policy if exists "Users delete own typing status"
  on public.chat_typing_status;
create policy "Users delete own typing status"
  on public.chat_typing_status
  for delete
  to authenticated
  using (user_id = (select auth.uid()));

revoke all on table public.chat_typing_status from anon;
grant select, insert, update, delete
  on table public.chat_typing_status to authenticated;

create table if not exists public.chat_reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references public.profiles(id) on delete cascade,
  reported_user_id uuid not null references public.profiles(id) on delete cascade,
  message_id uuid references public.messages(id) on delete set null,
  reason text not null check (char_length(btrim(reason)) between 1 and 120),
  details text not null default '' check (char_length(details) <= 2000),
  status text not null default 'open' check (status in ('open', 'reviewing', 'resolved', 'dismissed')),
  created_at timestamptz not null default now(),
  constraint chat_reports_not_self check (reporter_id <> reported_user_id)
);

create index if not exists chat_reports_reporter_created_idx
  on public.chat_reports (reporter_id, created_at desc);
create index if not exists chat_reports_reported_status_idx
  on public.chat_reports (reported_user_id, status, created_at desc);
create index if not exists chat_reports_message_idx
  on public.chat_reports (message_id)
  where message_id is not null;

alter table public.chat_reports enable row level security;

drop policy if exists "Users view own chat reports"
  on public.chat_reports;
create policy "Users view own chat reports"
  on public.chat_reports
  for select
  to authenticated
  using (reporter_id = (select auth.uid()));

drop policy if exists "Users create own chat reports"
  on public.chat_reports;
create policy "Users create own chat reports"
  on public.chat_reports
  for insert
  to authenticated
  with check (
    reporter_id = (select auth.uid())
    and reporter_id <> reported_user_id
  );

revoke all on table public.chat_reports from anon;
grant select, insert on table public.chat_reports to authenticated;

create or replace function private.can_direct_message(target_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    (select auth.uid()) is not null
    and target_user_id is not null
    and target_user_id <> (select auth.uid())
    and not exists (
      select 1 from public.blocked_users block
      where (
        block.user_id = (select auth.uid())
        and block.blocked_user_id = target_user_id
      ) or (
        block.user_id = target_user_id
        and block.blocked_user_id = (select auth.uid())
      )
    )
    and (
      exists (
        select 1 from public.friendships friendship
        where (
          friendship.user_id = (select auth.uid())
          and friendship.friend_id = target_user_id
        ) or (
          friendship.user_id = target_user_id
          and friendship.friend_id = (select auth.uid())
        )
      )
      or exists (
        select 1 from public.conversations conversation
        where (
          conversation.user_a_id = (select auth.uid())
          and conversation.user_b_id = target_user_id
        ) or (
          conversation.user_a_id = target_user_id
          and conversation.user_b_id = (select auth.uid())
        )
      )
    );
$$;

revoke execute on function private.can_direct_message(uuid)
  from public, anon;
grant execute on function private.can_direct_message(uuid)
  to authenticated, service_role;

drop policy if exists "Users can message friends or existing chat peers"
  on public.messages;
create policy "Users can message allowed chat peers"
  on public.messages
  for insert
  to authenticated
  with check (
    sender_id = (select auth.uid())
    and (select private.can_direct_message(recipient_id))
  );

revoke update on table public.messages from authenticated;
grant update (is_read, read_at, updated_at)
  on table public.messages to authenticated;

insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values (
  'chat-media',
  'chat-media',
  false,
  26214400,
  array[
    'image/jpeg', 'image/png', 'image/webp', 'image/gif',
    'video/mp4', 'video/webm',
    'audio/mpeg', 'audio/mp4', 'audio/wav', 'audio/ogg', 'audio/webm',
    'application/pdf', 'application/msword',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'application/vnd.ms-excel',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'application/vnd.ms-powerpoint',
    'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    'text/plain'
  ]::text[]
)
on conflict (id) do update set
  public = false,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "Chat participants view direct media"
  on storage.objects;
create policy "Chat participants view direct media"
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'chat-media'
    and (
      (storage.foldername(name))[1] = (select auth.uid())::text
      or (storage.foldername(name))[2] = (select auth.uid())::text
    )
  );

drop policy if exists "Users upload media to allowed chat peers"
  on storage.objects;
create policy "Users upload media to allowed chat peers"
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'chat-media'
    and owner_id = (select auth.uid())::text
    and (storage.foldername(name))[1] = (select auth.uid())::text
    and (select private.can_direct_message(((storage.foldername(name))[2])::uuid))
  );

drop policy if exists "Uploaders update direct chat media"
  on storage.objects;
create policy "Uploaders update direct chat media"
  on storage.objects
  for update
  to authenticated
  using (
    bucket_id = 'chat-media'
    and owner_id = (select auth.uid())::text
  )
  with check (
    bucket_id = 'chat-media'
    and owner_id = (select auth.uid())::text
  );

drop policy if exists "Uploaders delete direct chat media"
  on storage.objects;
create policy "Uploaders delete direct chat media"
  on storage.objects
  for delete
  to authenticated
  using (
    bucket_id = 'chat-media'
    and owner_id = (select auth.uid())::text
  );

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'message_reactions'
  ) then
    alter publication supabase_realtime add table public.message_reactions;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'chat_typing_status'
  ) then
    alter publication supabase_realtime add table public.chat_typing_status;
  end if;
end
$$;
