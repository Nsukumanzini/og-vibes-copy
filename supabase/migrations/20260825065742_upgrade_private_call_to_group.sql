-- Safely convert an active private call into an ad-hoc call with up to 5 people.

alter table public.group_calls
  alter column group_id drop not null;

alter table public.group_calls
  add column if not exists source_call_id uuid unique
    references public.calls(id) on delete set null,
  add column if not exists room_name text;

create or replace function public.upgrade_private_call_to_group(
  target_call_id uuid,
  invitee_ids uuid[]
) returns public.group_calls
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor uuid := auth.uid();
  private_call public.calls;
  other_user uuid;
  clean_invitees uuid[];
  created_call public.group_calls;
begin
  if actor is null then
    raise exception 'Sign in before adding people to a call.';
  end if;

  select * into private_call
  from public.calls
  where id = target_call_id
  for update;

  if private_call.id is null
     or private_call.status not in ('ringing', 'active')
     or actor not in (private_call.caller_id, private_call.callee_id) then
    raise exception 'This private call is no longer available.';
  end if;

  other_user := case
    when actor = private_call.caller_id then private_call.callee_id
    else private_call.caller_id
  end;

  if cardinality(coalesce(invitee_ids, '{}'::uuid[])) < 1
     or cardinality(coalesce(invitee_ids, '{}'::uuid[])) > 3 then
    raise exception 'Choose between one and three friends.';
  end if;

  select coalesce(array_agg(candidate.user_id order by candidate.user_id), '{}'::uuid[])
  into clean_invitees
  from (
    select distinct requested.user_id
    from unnest(coalesce(invitee_ids, '{}'::uuid[])) as requested(user_id)
    where requested.user_id not in (actor, other_user)
      and exists (
        select 1
        from public.friendships friendship
        where (friendship.user_id = actor and friendship.friend_id = requested.user_id)
           or (friendship.user_id = requested.user_id and friendship.friend_id = actor)
      )
    limit 3
  ) candidate;

  if cardinality(clean_invitees) <>
     cardinality(coalesce(invitee_ids, '{}'::uuid[])) then
    raise exception 'Only accepted friends can be added to this call.';
  end if;

  insert into public.group_calls(
    group_id,
    started_by,
    call_type,
    source_call_id,
    room_name
  ) values (
    null,
    actor,
    private_call.type,
    private_call.id,
    'Group call'
  )
  returning * into created_call;

  insert into public.group_call_participants(
    call_id,
    user_id,
    status,
    joined_at
  ) values (created_call.id, actor, 'joined', now());

  insert into public.group_call_participants(call_id, user_id, status)
  values (created_call.id, other_user, 'invited');

  insert into public.group_call_participants(call_id, user_id, status)
  select created_call.id, unnest(clean_invitees), 'invited';

  update public.calls
  set status = 'ended', ended_at = now()
  where id = private_call.id;

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
  if actor is null then
    raise exception 'Sign in before joining a call.';
  end if;

  select * into target_call
  from public.group_calls
  where id = target_call_id
  for update;

  if target_call.id is null
     or target_call.status not in ('ringing', 'active') then
    raise exception 'This group call has ended.';
  end if;

  if not exists (
    select 1
    from public.group_call_participants participant
    where participant.call_id = target_call_id
      and participant.user_id = actor
      and participant.status = 'invited'
  ) then
    raise exception 'This call invitation is not available.';
  end if;

  if target_call.group_id is not null
     and not private.is_group_member(target_call.group_id, actor) then
    raise exception 'You are no longer a member of this group.';
  end if;

  select count(*) into joined_count
  from public.group_call_participants participant
  where participant.call_id = target_call_id
    and participant.status = 'joined';

  if joined_count >= 5 then
    raise exception 'This group call is full.';
  end if;

  update public.group_call_participants
  set status = 'joined', joined_at = now(), left_at = null
  where call_id = target_call_id and user_id = actor;

  update public.group_calls
  set status = 'active'
  where id = target_call_id and status = 'ringing';

  select * into target_call
  from public.group_calls
  where id = target_call_id;
  return target_call;
end;
$$;

revoke all on function public.upgrade_private_call_to_group(uuid, uuid[])
  from public, anon;
grant execute on function public.upgrade_private_call_to_group(uuid, uuid[])
  to authenticated;

revoke all on function public.join_group_call(uuid) from public, anon;
grant execute on function public.join_group_call(uuid) to authenticated;
