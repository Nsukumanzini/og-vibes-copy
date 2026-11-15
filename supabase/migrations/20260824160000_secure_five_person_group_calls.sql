-- Secure WebRTC mesh rooms for group voice and video calls (maximum 5 people).

create table if not exists public.group_calls (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.group_chats(id) on delete cascade,
  started_by uuid not null references auth.users(id) on delete cascade,
  call_type text not null check (call_type in ('audio', 'video')),
  status text not null default 'ringing'
    check (status in ('ringing', 'active', 'ended', 'cancelled')),
  created_at timestamptz not null default now(),
  started_at timestamptz not null default now(),
  ended_at timestamptz
);

create table if not exists public.group_call_participants (
  call_id uuid not null references public.group_calls(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'invited'
    check (status in ('invited', 'joined', 'declined', 'left', 'missed')),
  invited_at timestamptz not null default now(),
  joined_at timestamptz,
  left_at timestamptz,
  primary key (call_id, user_id)
);

create table if not exists public.group_call_signals (
  id bigint generated always as identity primary key,
  call_id uuid not null references public.group_calls(id) on delete cascade,
  sender_id uuid not null references auth.users(id) on delete cascade,
  recipient_id uuid not null references auth.users(id) on delete cascade,
  kind text not null check (kind in ('offer', 'answer', 'ice')),
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  check (sender_id <> recipient_id)
);

create unique index if not exists one_live_call_per_group_idx
  on public.group_calls(group_id)
  where status in ('ringing', 'active');
create index if not exists group_call_participant_user_idx
  on public.group_call_participants(user_id, status, invited_at desc);
create index if not exists group_call_signal_recipient_idx
  on public.group_call_signals(call_id, recipient_id, id);

alter table public.group_calls enable row level security;
alter table public.group_call_participants enable row level security;
alter table public.group_call_signals enable row level security;

create or replace function private.is_group_call_participant(
  target_call_id uuid,
  target_user_id uuid
) returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.group_call_participants participant
    where participant.call_id = target_call_id
      and participant.user_id = target_user_id
  );
$$;

create or replace function private.is_joined_group_call_participant(
  target_call_id uuid,
  target_user_id uuid
) returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.group_call_participants participant
    where participant.call_id = target_call_id
      and participant.user_id = target_user_id
      and participant.status = 'joined'
  );
$$;

revoke all on function private.is_group_call_participant(uuid, uuid) from public;
revoke all on function private.is_joined_group_call_participant(uuid, uuid) from public;
grant execute on function private.is_group_call_participant(uuid, uuid) to authenticated;
grant execute on function private.is_joined_group_call_participant(uuid, uuid) to authenticated;

drop policy if exists "Participants view their group calls" on public.group_calls;
create policy "Participants view their group calls"
on public.group_calls for select to authenticated
using (private.is_group_call_participant(id, (select auth.uid())));

drop policy if exists "Participants view the call roster" on public.group_call_participants;
create policy "Participants view the call roster"
on public.group_call_participants for select to authenticated
using (private.is_group_call_participant(call_id, (select auth.uid())));

drop policy if exists "Peers view addressed call signals" on public.group_call_signals;
create policy "Peers view addressed call signals"
on public.group_call_signals for select to authenticated
using ((select auth.uid()) in (sender_id, recipient_id));

drop policy if exists "Joined peers send addressed call signals" on public.group_call_signals;
create policy "Joined peers send addressed call signals"
on public.group_call_signals for insert to authenticated
with check (
  sender_id = (select auth.uid())
  and private.is_joined_group_call_participant(call_id, sender_id)
  and private.is_joined_group_call_participant(call_id, recipient_id)
  and exists (
    select 1 from public.group_calls call
    where call.id = call_id and call.status in ('ringing', 'active')
  )
);

grant select on public.group_calls to authenticated;
grant select on public.group_call_participants to authenticated;
grant select, insert on public.group_call_signals to authenticated;
grant usage, select on sequence public.group_call_signals_id_seq to authenticated;

create or replace function public.start_group_call(
  target_group_id uuid,
  target_call_type text,
  invitee_ids uuid[]
) returns public.group_calls
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor uuid := auth.uid();
  clean_invitees uuid[];
  created_call public.group_calls;
begin
  if actor is null then raise exception 'Sign in before starting a call.'; end if;
  if target_call_type not in ('audio', 'video') then raise exception 'Unsupported call type.'; end if;
  if not private.is_group_member(target_group_id, actor) then
    raise exception 'Only group members can start a call.';
  end if;

  select coalesce(array_agg(candidate.user_id order by candidate.user_id), '{}'::uuid[])
    into clean_invitees
    from (
      select distinct member.user_id
      from public.group_members member
      where member.group_id = target_group_id
        and member.user_id = any(coalesce(invitee_ids, '{}'::uuid[]))
        and member.user_id <> actor
      limit 4
    ) candidate;

  if cardinality(clean_invitees) = 0 then
    raise exception 'Choose at least one group member.';
  end if;
  if cardinality(coalesce(invitee_ids, '{}'::uuid[])) > 4
     or cardinality(clean_invitees) <> cardinality(coalesce(invitee_ids, '{}'::uuid[])) then
    raise exception 'Choose up to four valid group members.';
  end if;

  insert into public.group_calls(group_id, started_by, call_type)
  values (target_group_id, actor, target_call_type)
  returning * into created_call;

  insert into public.group_call_participants(call_id, user_id, status, joined_at)
  values (created_call.id, actor, 'joined', now());

  insert into public.group_call_participants(call_id, user_id, status)
  select created_call.id, unnest(clean_invitees), 'invited';

  return created_call;
end;
$$;

create or replace function public.join_group_call(target_call_id uuid)
returns public.group_calls
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor uuid := auth.uid();
  target_call public.group_calls;
  joined_count integer;
begin
  select * into target_call from public.group_calls
  where id = target_call_id for update;
  if target_call.id is null or target_call.status not in ('ringing', 'active') then
    raise exception 'This group call has ended.';
  end if;
  if not exists (
    select 1 from public.group_call_participants
    where call_id = target_call_id and user_id = actor and status = 'invited'
  ) then raise exception 'This call invitation is not available.'; end if;
  if not private.is_group_member(target_call.group_id, actor) then
    raise exception 'You are no longer a member of this group.';
  end if;
  select count(*) into joined_count from public.group_call_participants
  where call_id = target_call_id and status = 'joined';
  if joined_count >= 5 then raise exception 'This group call is full.'; end if;

  update public.group_call_participants
  set status = 'joined', joined_at = now(), left_at = null
  where call_id = target_call_id and user_id = actor;
  update public.group_calls set status = 'active'
  where id = target_call_id and status = 'ringing';
  select * into target_call from public.group_calls where id = target_call_id;
  return target_call;
end;
$$;

create or replace function public.decline_group_call(target_call_id uuid)
returns void
language sql
security definer
set search_path = ''
as $$
  update public.group_call_participants
  set status = 'declined', left_at = now()
  where call_id = target_call_id and user_id = auth.uid() and status = 'invited';
$$;

create or replace function public.leave_group_call(target_call_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.group_call_participants
  set status = 'left', left_at = now()
  where call_id = target_call_id and user_id = auth.uid() and status = 'joined';
  if not exists (
    select 1 from public.group_call_participants
    where call_id = target_call_id and status = 'joined'
  ) then
    update public.group_calls set status = 'ended', ended_at = now()
    where id = target_call_id and status in ('ringing', 'active');
  end if;
end;
$$;

create or replace function public.end_group_call(target_call_id uuid)
returns void
language sql
security definer
set search_path = ''
as $$
  update public.group_calls
  set status = 'ended', ended_at = now()
  where id = target_call_id and started_by = auth.uid()
    and status in ('ringing', 'active');
$$;

revoke all on function public.start_group_call(uuid, text, uuid[]) from public;
revoke all on function public.join_group_call(uuid) from public;
revoke all on function public.decline_group_call(uuid) from public;
revoke all on function public.leave_group_call(uuid) from public;
revoke all on function public.end_group_call(uuid) from public;
grant execute on function public.start_group_call(uuid, text, uuid[]) to authenticated;
grant execute on function public.join_group_call(uuid) to authenticated;
grant execute on function public.decline_group_call(uuid) to authenticated;
grant execute on function public.leave_group_call(uuid) to authenticated;
grant execute on function public.end_group_call(uuid) to authenticated;

do $$
begin
  alter publication supabase_realtime add table public.group_calls;
exception when duplicate_object then null;
end $$;
do $$
begin
  alter publication supabase_realtime add table public.group_call_participants;
exception when duplicate_object then null;
end $$;
do $$
begin
  alter publication supabase_realtime add table public.group_call_signals;
exception when duplicate_object then null;
end $$;
