create table if not exists public.chat_preferences (
  user_id uuid not null references public.profiles(id) on delete cascade,
  peer_id uuid not null references public.profiles(id) on delete cascade,
  is_archived boolean not null default false,
  updated_at timestamptz not null default now(),
  primary key (user_id, peer_id),
  constraint chat_preferences_not_self check (user_id <> peer_id)
);

create index if not exists chat_preferences_peer_idx
  on public.chat_preferences (peer_id);

alter table public.chat_preferences enable row level security;

drop policy if exists "Users can view own chat preferences"
  on public.chat_preferences;
create policy "Users can view own chat preferences"
  on public.chat_preferences
  for select
  to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists "Users can create own chat preferences"
  on public.chat_preferences;
create policy "Users can create own chat preferences"
  on public.chat_preferences
  for insert
  to authenticated
  with check ((select auth.uid()) = user_id);

drop policy if exists "Users can update own chat preferences"
  on public.chat_preferences;
create policy "Users can update own chat preferences"
  on public.chat_preferences
  for update
  to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

drop policy if exists "Users can delete own chat preferences"
  on public.chat_preferences;
create policy "Users can delete own chat preferences"
  on public.chat_preferences
  for delete
  to authenticated
  using ((select auth.uid()) = user_id);

revoke all on table public.chat_preferences from anon;
grant select, insert, update, delete
  on table public.chat_preferences to authenticated;

insert into public.conversations (
  user_a_id,
  user_b_id,
  last_message_at,
  updated_at
)
select
  least(message.sender_id, message.recipient_id),
  greatest(message.sender_id, message.recipient_id),
  max(message.created_at),
  max(message.updated_at)
from public.messages message
group by
  least(message.sender_id, message.recipient_id),
  greatest(message.sender_id, message.recipient_id)
on conflict (user_a_id, user_b_id) do update set
  last_message_at = greatest(
    conversations.last_message_at,
    excluded.last_message_at
  ),
  updated_at = greatest(conversations.updated_at, excluded.updated_at);

create index if not exists conversations_user_b_id_idx
  on public.conversations (user_b_id);
create index if not exists conversations_last_message_id_idx
  on public.conversations (last_message_id);

drop policy if exists "Users can create conversations they are part of"
  on public.conversations;
create policy "Friends can create conversations"
  on public.conversations
  for insert
  to authenticated
  with check (
    ((select auth.uid()) = user_a_id or (select auth.uid()) = user_b_id)
    and exists (
      select 1
      from public.friendships friendship
      where (
        friendship.user_id = user_a_id
        and friendship.friend_id = user_b_id
      ) or (
        friendship.user_id = user_b_id
        and friendship.friend_id = user_a_id
      )
    )
  );

drop policy if exists "Users can send messages as themselves"
  on public.messages;
create policy "Users can message friends or existing chat peers"
  on public.messages
  for insert
  to authenticated
  with check (
    (select auth.uid()) = sender_id
    and sender_id <> recipient_id
    and (
      exists (
        select 1
        from public.friendships friendship
        where (
          friendship.user_id = sender_id
          and friendship.friend_id = recipient_id
        ) or (
          friendship.user_id = recipient_id
          and friendship.friend_id = sender_id
        )
      )
      or exists (
        select 1
        from public.conversations conversation
        where (
          conversation.user_a_id = sender_id
          and conversation.user_b_id = recipient_id
        ) or (
          conversation.user_a_id = recipient_id
          and conversation.user_b_id = sender_id
        )
      )
    )
  );

drop policy if exists "Users can update messages they sent or received"
  on public.messages;
drop policy if exists "Recipients can mark messages as read"
  on public.messages;
create policy "Recipients can mark messages as read"
  on public.messages
  for update
  to authenticated
  using ((select auth.uid()) = recipient_id)
  with check ((select auth.uid()) = recipient_id);

revoke update on table public.messages from authenticated;
grant update (is_read, updated_at)
  on table public.messages to authenticated;

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'chat_preferences'
  ) then
    alter publication supabase_realtime
      add table public.chat_preferences;
  end if;
end
$$;
