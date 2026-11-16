-- A private call can only ring for one minute. The expiry is enforced on the
-- database update path as well as in the client so an old invitation cannot be
-- accepted after the caller has gone offline.

alter table public.calls
  add column if not exists expires_at timestamptz;

update public.calls
set expires_at = started_at + interval '1 minute'
where expires_at is null;

alter table public.calls
  alter column expires_at set default (now() + interval '1 minute'),
  alter column expires_at set not null;

create index if not exists calls_ringing_expires_at_idx
  on public.calls (expires_at)
  where status = 'ringing';

create or replace function private.enforce_private_call_expiry()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if old.status = 'ringing'
     and new.status = 'active'
     and old.expires_at <= now() then
    raise exception 'This call invitation has expired.';
  end if;
  return new;
end;
$$;

drop trigger if exists enforce_private_call_expiry on public.calls;
create trigger enforce_private_call_expiry
  before update of status on public.calls
  for each row
  execute function private.enforce_private_call_expiry();

create or replace function private.protect_calls_from_blocks()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_table_name = 'calls' then
    if exists (
      select 1
      from public.blocked_users block
      where (block.user_id = new.caller_id and block.blocked_user_id = new.callee_id)
         or (block.user_id = new.callee_id and block.blocked_user_id = new.caller_id)
    ) then
      raise exception 'This call is not available.';
    end if;
    return new;
  end if;

  update public.calls
  set status = 'ended', ended_at = now()
  where status in ('ringing', 'active', 'reconnecting')
    and (
      (caller_id = new.user_id and callee_id = new.blocked_user_id)
      or (caller_id = new.blocked_user_id and callee_id = new.user_id)
    );
  return new;
end;
$$;

drop trigger if exists protect_private_calls_from_blocks on public.calls;
create trigger protect_private_calls_from_blocks
  before insert on public.calls
  for each row
  execute function private.protect_calls_from_blocks();

drop trigger if exists end_private_calls_when_blocked on public.blocked_users;
create trigger end_private_calls_when_blocked
  after insert on public.blocked_users
  for each row
  execute function private.protect_calls_from_blocks();

drop policy if exists "Call participants can send signals" on public.call_signals;
create policy "Call participants can send signals"
on public.call_signals
for insert to authenticated
with check (
  (select auth.uid()) = sender_id
  and exists (
    select 1
    from public.calls c
    where c.id = call_signals.call_id
      and (select auth.uid()) in (c.caller_id, c.callee_id)
      and (
        c.status = 'active'
        or (c.status = 'ringing' and c.expires_at > now())
      )
  )
);
