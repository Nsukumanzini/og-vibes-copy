create table if not exists public.call_history_hidden (
  user_id uuid not null references auth.users (id) on delete cascade,
  call_kind text not null check (call_kind in ('direct', 'group')),
  call_id uuid not null,
  hidden_at timestamptz not null default now(),
  primary key (user_id, call_kind, call_id)
);

alter table public.call_history_hidden enable row level security;
revoke all on public.call_history_hidden from anon, authenticated;
grant select, insert on public.call_history_hidden to authenticated;

create policy "Users read their own hidden call history"
  on public.call_history_hidden
  for select
  to authenticated
  using ((select auth.uid()) = user_id and (select private.is_account_active()));

create policy "Users hide their own call history"
  on public.call_history_hidden
  for insert
  to authenticated
  with check ((select auth.uid()) = user_id and (select private.is_account_active()));

drop policy if exists "Active accounts use OG Vibes" on public.calls;
drop policy if exists "Users can view their own calls" on public.calls;
drop policy if exists "Participants can update their own calls" on public.calls;
drop policy if exists "Users can create calls as themselves" on public.calls;

create policy "Active participants can view their calls"
  on public.calls for select to authenticated
  using (
    (select private.is_account_active())
    and ((select auth.uid()) = caller_id or (select auth.uid()) = callee_id)
  );

create policy "Active participants can update their calls"
  on public.calls for update to authenticated
  using (
    (select private.is_account_active())
    and ((select auth.uid()) = caller_id or (select auth.uid()) = callee_id)
  )
  with check (
    (select private.is_account_active())
    and ((select auth.uid()) = caller_id or (select auth.uid()) = callee_id)
  );

create policy "Active users create calls as themselves"
  on public.calls for insert to authenticated
  with check ((select private.is_account_active()) and (select auth.uid()) = caller_id);

create or replace function private.enforce_call_record_integrity()
returns trigger
language plpgsql
security invoker
set search_path = pg_catalog, public
as $function$
begin
  if tg_op = 'INSERT' then
    if new.caller_id is distinct from auth.uid() then
      raise exception 'A call must be created by its caller';
    end if;
    if new.type not in ('audio', 'video') then
      raise exception 'Unsupported call type';
    end if;
    new.status := 'ringing';
    new.started_at := clock_timestamp();
    new.created_at := clock_timestamp();
    new.answered_at := null;
    new.ended_at := null;
    return new;
  end if;

  if new.id is distinct from old.id
    or new.caller_id is distinct from old.caller_id
    or new.callee_id is distinct from old.callee_id
    or new.type is distinct from old.type
    or new.started_at is distinct from old.started_at
    or new.created_at is distinct from old.created_at then
    raise exception 'Call identity and start details cannot be changed';
  end if;

  if new.status is not distinct from old.status then
    if new.answered_at is distinct from old.answered_at
      or new.ended_at is distinct from old.ended_at then
      raise exception 'Call times are set by the call status';
    end if;
    return new;
  end if;

  if old.status = 'ringing' and new.status = 'active' then
    if auth.uid() is distinct from old.callee_id then
      raise exception 'Only the invited student can answer this call';
    end if;
    new.answered_at := clock_timestamp();
    new.ended_at := null;
  elsif old.status = 'ringing' and new.status = 'cancelled' then
    if auth.uid() is distinct from old.caller_id then
      raise exception 'Only the caller can cancel this call';
    end if;
    new.answered_at := old.answered_at;
    new.ended_at := clock_timestamp();
  elsif old.status = 'ringing' and new.status = 'declined' then
    if auth.uid() is distinct from old.callee_id then
      raise exception 'Only the invited student can decline this call';
    end if;
    new.answered_at := old.answered_at;
    new.ended_at := clock_timestamp();
  elsif old.status = 'ringing' and new.status = 'missed' then
    if auth.uid() not in (old.caller_id, old.callee_id) then
      raise exception 'Only a call participant can mark this call missed';
    end if;
    if clock_timestamp() < old.started_at + interval '1 minute' then
      raise exception 'A call can only be marked missed after ringing';
    end if;
    new.answered_at := old.answered_at;
    new.ended_at := clock_timestamp();
  elsif old.status = 'active' and new.status = 'ended' then
    if auth.uid() not in (old.caller_id, old.callee_id) then
      raise exception 'Only a call participant can end this call';
    end if;
    new.answered_at := old.answered_at;
    new.ended_at := clock_timestamp();
  else
    raise exception 'This call status change is not allowed';
  end if;

  return new;
end;
$function$;

drop trigger if exists enforce_call_record_integrity on public.calls;
create trigger enforce_call_record_integrity
  before insert or update on public.calls
  for each row execute function private.enforce_call_record_integrity();
