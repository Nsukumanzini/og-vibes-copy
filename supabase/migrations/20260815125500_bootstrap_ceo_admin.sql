begin;

-- Bootstrap the first administrator. The role-change guard cannot authorize
-- this transition while the project has no existing administrator.
lock table public.profiles in share row exclusive mode;
alter table public.profiles disable trigger profiles_guard_role_change;

update public.profiles as profile
set role = 'admin'
where lower(profile.email) = lower('ceo@ogtechnologies.co.za')
  and exists (
    select 1
    from auth.users as auth_user
    where auth_user.id = profile.id
      and lower(auth_user.email) = lower('ceo@ogtechnologies.co.za')
      and auth_user.email_confirmed_at is not null
  );

alter table public.profiles enable trigger profiles_guard_role_change;

commit;
