begin;

create table if not exists public.admin_access (
  user_id uuid primary key references public.profiles(id) on delete restrict,
  access_role text not null,
  status text not null default 'active',
  base_role text,
  granted_by uuid references public.profiles(id) on delete restrict,
  granted_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint admin_access_role_check check (access_role in ('owner', 'vice_admin')),
  constraint admin_access_status_check check (status in ('active', 'suspended', 'revoked'))
);

alter table public.admin_access add column if not exists base_role text;

alter table public.admin_access enable row level security;
revoke all on table public.admin_access from public, anon, authenticated;
grant select, insert, update on table public.admin_access to service_role;

create unique index if not exists admin_access_one_active_vice_idx
on public.admin_access (access_role)
where access_role = 'vice_admin' and status = 'active';

create index if not exists admin_access_status_role_idx
on public.admin_access (status, access_role);

do $seed_owner$
declare
  owner_user_id uuid;
begin
  select id into owner_user_id
  from public.profiles
  where lower(email) = 'ceo@ogtechnologies.co.za'
  limit 1;

  if owner_user_id is null then
    raise exception 'The CEO profile ceo@ogtechnologies.co.za must exist before applying the administrator security migration.';
  end if;

  insert into public.admin_access (user_id, access_role, status, base_role, granted_by)
  values (owner_user_id, 'owner', 'active', 'admin', owner_user_id)
  on conflict (user_id) do update
  set access_role = 'owner', status = 'active', updated_at = now();

  update public.profiles
  set role = 'admin', account_status = 'active'
  where id = owner_user_id;
end
$seed_owner$;

create or replace function private.is_app_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.admin_access access
    join public.profiles profile on profile.id = access.user_id
    where access.user_id = (select auth.uid())
      and access.access_role = 'owner'
      and access.status = 'active'
      and profile.account_status = 'active'
  );
$$;
revoke all on function private.is_app_admin() from public, anon;
grant execute on function private.is_app_admin() to authenticated, service_role;

create or replace function private.protect_last_owner()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.access_role = 'owner' and old.status = 'active'
     and (tg_op = 'DELETE' or new.access_role <> 'owner' or new.status <> 'active') then
    perform pg_advisory_xact_lock(74839201);
    if not exists (
      select 1 from public.admin_access other
      where other.access_role = 'owner'
        and other.status = 'active'
        and other.user_id <> old.user_id
    ) then
      raise exception 'The final active Owner cannot be removed, suspended or demoted.';
    end if;
  end if;
  if tg_op = 'DELETE' then return old; end if;
  new.updated_at := now();
  return new;
end;
$$;
revoke all on function private.protect_last_owner() from public, anon, authenticated;

drop trigger if exists admin_access_protect_last_owner on public.admin_access;
create trigger admin_access_protect_last_owner
before update or delete on public.admin_access
for each row execute function private.protect_last_owner();

alter table public.admin_audit_logs
  add column if not exists actor_name text,
  add column if not exists actor_email text,
  add column if not exists actor_role text,
  add column if not exists category text,
  add column if not exists outcome text not null default 'success',
  add column if not exists target_label text,
  add column if not exists before_data jsonb,
  add column if not exists after_data jsonb,
  add column if not exists changed_fields text[] not null default '{}'::text[],
  add column if not exists error_message text,
  add column if not exists request_id uuid,
  add column if not exists ip_address text,
  add column if not exists user_agent text;

alter table public.admin_audit_logs drop constraint if exists admin_audit_logs_outcome_check;
alter table public.admin_audit_logs
  add constraint admin_audit_logs_outcome_check
  check (outcome in ('success', 'failed', 'denied'));

create index if not exists admin_audit_logs_actor_time_idx
on public.admin_audit_logs (actor_email, created_at desc);

create index if not exists admin_audit_logs_category_outcome_time_idx
on public.admin_audit_logs (category, outcome, created_at desc);

create or replace function private.prevent_admin_audit_mutation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'Administrator audit records are immutable.';
end;
$$;
revoke all on function private.prevent_admin_audit_mutation() from public, anon, authenticated;

drop trigger if exists admin_audit_logs_immutable on public.admin_audit_logs;
create trigger admin_audit_logs_immutable
before update or delete on public.admin_audit_logs
for each row execute function private.prevent_admin_audit_mutation();

create or replace function public.revoke_admin_sessions(target_user_id uuid)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  removed_count bigint;
begin
  if coalesce(current_setting('request.jwt.claim.role', true), '') <> 'service_role' then
    raise exception 'Service access required.';
  end if;
  delete from auth.sessions where user_id = target_user_id;
  get diagnostics removed_count = row_count;
  return removed_count;
end;
$$;
revoke all on function public.revoke_admin_sessions(uuid) from public, anon, authenticated;
grant execute on function public.revoke_admin_sessions(uuid) to service_role;

commit;
