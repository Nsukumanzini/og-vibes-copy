begin;

create or replace function private.guard_profile_account_control()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if (
    new.account_status is distinct from old.account_status
    or new.suspended_at is distinct from old.suspended_at
    or new.suspension_reason is distinct from old.suspension_reason
    or new.suspended_by is distinct from old.suspended_by
  ) and not (
    current_user = 'service_role'
    or coalesce(current_setting('request.jwt.claim.role', true), '') = 'service_role'
    or (select private.is_app_admin())
  ) then
    raise exception 'Only an administrator can change account access.';
  end if;
  return new;
end;
$$;

create or replace function private.guard_profile_role_change()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if new.role is distinct from old.role and not (
    current_user = 'service_role'
    or coalesce(current_setting('request.jwt.claim.role', true), '') = 'service_role'
    or (select private.is_app_admin())
  ) then
    raise exception 'Only an administrator can change account roles.';
  end if;
  return new;
end;
$$;

revoke all on function private.guard_profile_account_control() from public, anon, authenticated;
revoke all on function private.guard_profile_role_change() from public, anon, authenticated;

commit;
