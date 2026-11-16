create table if not exists public.app_takeover_notices (
  id uuid primary key default gen_random_uuid(),
  title text not null check (char_length(btrim(title)) between 1 and 120),
  message text not null check (char_length(btrim(message)) between 1 and 2000),
  is_blocking boolean not null default false,
  is_active boolean not null default true,
  starts_at timestamptz not null default now(),
  ends_at timestamptz,
  created_by uuid not null default auth.uid() references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint app_takeover_notices_valid_window check (ends_at is null or ends_at > starts_at)
);

alter table public.app_takeover_notices enable row level security;

revoke all on table public.app_takeover_notices from anon, authenticated;
grant select on table public.app_takeover_notices to anon, authenticated;
grant insert, update, delete on table public.app_takeover_notices to authenticated;

drop policy if exists "Anyone can read current app notices" on public.app_takeover_notices;
create policy "Anyone can read current app notices"
on public.app_takeover_notices
for select
to anon, authenticated
using (
  is_active
  and starts_at <= now()
  and (ends_at is null or ends_at > now())
);

drop policy if exists "Admins read all app notices" on public.app_takeover_notices;
create policy "Admins read all app notices"
on public.app_takeover_notices
for select
to authenticated
using ((select private.is_app_admin()));

drop policy if exists "Admins create app notices" on public.app_takeover_notices;
create policy "Admins create app notices"
on public.app_takeover_notices
for insert
to authenticated
with check (
  (select private.is_app_admin())
  and created_by = (select auth.uid())
);

drop policy if exists "Admins update app notices" on public.app_takeover_notices;
create policy "Admins update app notices"
on public.app_takeover_notices
for update
to authenticated
using ((select private.is_app_admin()))
with check ((select private.is_app_admin()));

drop policy if exists "Admins delete app notices" on public.app_takeover_notices;
create policy "Admins delete app notices"
on public.app_takeover_notices
for delete
to authenticated
using ((select private.is_app_admin()));

create index if not exists app_takeover_notices_active_window_idx
on public.app_takeover_notices (is_blocking desc, starts_at desc)
where is_active;

create or replace function private.set_app_takeover_notice_updated_at()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists set_app_takeover_notice_updated_at on public.app_takeover_notices;
create trigger set_app_takeover_notice_updated_at
before update on public.app_takeover_notices
for each row execute function private.set_app_takeover_notice_updated_at();

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'app_takeover_notices'
  ) then
    alter publication supabase_realtime add table public.app_takeover_notices;
  end if;
end;
$$;
