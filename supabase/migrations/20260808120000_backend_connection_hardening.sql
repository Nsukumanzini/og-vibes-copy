-- Backend connection and content administration hardening.

create or replace function public.is_app_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.profiles
    where id = (select auth.uid()) and role = 'admin'
  );
$$;

revoke execute on function public.is_app_admin() from public, anon;
grant execute on function public.is_app_admin() to authenticated, service_role;

-- New accounts receive a complete profile even while email confirmation is pending.
create or replace function public.handle_new_user_profile()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (
    id, email, name, surname, nickname, campus, department, level,
    student_type, gender, student_number, phone, timezone_name,
    timezone_offset, device_locale
  ) values (
    new.id,
    coalesce(new.email, new.id::text || '@phone.local'),
    coalesce(nullif(new.raw_user_meta_data ->> 'name', ''), 'Student'),
    coalesce(nullif(new.raw_user_meta_data ->> 'surname', ''), ''),
    nullif(new.raw_user_meta_data ->> 'nickname', ''),
    coalesce(nullif(new.raw_user_meta_data ->> 'campus', ''), 'Not selected'),
    coalesce(nullif(new.raw_user_meta_data ->> 'department', ''), 'Not selected'),
    coalesce(nullif(new.raw_user_meta_data ->> 'level', ''), 'Not selected'),
    coalesce(nullif(new.raw_user_meta_data ->> 'student_type', ''), nullif(new.raw_user_meta_data ->> 'studentType', ''), 'Student'),
    coalesce(nullif(new.raw_user_meta_data ->> 'gender', ''), 'Prefer not to say'),
    coalesce(nullif(new.raw_user_meta_data ->> 'student_number', ''), nullif(new.raw_user_meta_data ->> 'studentNumber', '')),
    nullif(new.raw_user_meta_data ->> 'phone', ''),
    coalesce(nullif(new.raw_user_meta_data ->> 'timezone_name', ''), nullif(new.raw_user_meta_data ->> 'timeZoneName', '')),
    coalesce(nullif(new.raw_user_meta_data ->> 'timezone_offset', ''), nullif(new.raw_user_meta_data ->> 'timeZoneOffset', '')),
    coalesce(nullif(new.raw_user_meta_data ->> 'device_locale', ''), nullif(new.raw_user_meta_data ->> 'deviceLocale', ''))
  )
  on conflict (id) do update set email = excluded.email;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created_profile on auth.users;
create trigger on_auth_user_created_profile
after insert on auth.users
for each row execute function public.handle_new_user_profile();

-- The private posts bucket is readable only by signed-in users.
drop policy if exists "Authenticated users can read post media" on storage.objects;
create policy "Authenticated users can read post media"
on storage.objects for select to authenticated
using (bucket_id = 'posts');

-- Lost item owners can approve or reject claims; claimants cannot mutate outcomes.
grant update on table public.lost_and_found_claims to authenticated;
drop policy if exists "Item owners can update claims" on public.lost_and_found_claims;
create policy "Item owners can update claims"
on public.lost_and_found_claims for update to authenticated
using (
  exists (
    select 1 from public.lost_and_found_items i
    where i.id = item_id and i.user_id = (select auth.uid())
  )
)
with check (
  exists (
    select 1 from public.lost_and_found_items i
    where i.id = item_id and i.user_id = (select auth.uid())
  )
);

-- Auth deletion must not be blocked by historical submissions or reviewer links.
alter table public.assignment_submissions drop constraint if exists assignment_submissions_user_id_fkey;
alter table public.assignment_submissions add constraint assignment_submissions_user_id_fkey
  foreign key (user_id) references auth.users(id) on delete cascade;
alter table public.lecturer_applications drop constraint if exists lecturer_applications_reviewed_by_fkey;
alter table public.lecturer_applications add constraint lecturer_applications_reviewed_by_fkey
  foreign key (reviewed_by) references public.profiles(id) on delete set null;

create table if not exists public.support_donations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  category text not null,
  item text not null,
  details text not null default '',
  location text not null default '',
  is_anonymous boolean not null default true,
  status text not null default 'offered' check (status in ('offered','matched','completed','withdrawn')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.support_donations enable row level security;
grant select, insert, update, delete on public.support_donations to authenticated;
create index if not exists support_donations_user_created_idx on public.support_donations(user_id, created_at desc);
drop policy if exists "Users manage own support donations" on public.support_donations;
create policy "Users manage own support donations" on public.support_donations
for all to authenticated using (user_id = (select auth.uid()))
with check (user_id = (select auth.uid()));
drop policy if exists "Admins read support donations" on public.support_donations;
create policy "Admins read support donations" on public.support_donations
for select to authenticated using ((select public.is_app_admin()));

create table if not exists public.download_history (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  source_type text not null,
  source_id uuid,
  title text not null,
  url text,
  storage_path text,
  file_size_bytes bigint,
  downloaded_at timestamptz not null default now()
);
alter table public.download_history enable row level security;
grant select, insert, delete on public.download_history to authenticated;
create index if not exists download_history_user_date_idx on public.download_history(user_id, downloaded_at desc);
drop policy if exists "Users manage own download history" on public.download_history;
create policy "Users manage own download history" on public.download_history
for all to authenticated using (user_id = (select auth.uid()))
with check (user_id = (select auth.uid()));

alter table public.past_papers add column if not exists storage_path text;
alter table public.lecture_slides add column if not exists storage_path text;
alter table public.timetables add column if not exists storage_path text;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('academic-content', 'academic-content', false, 52428800, array['application/pdf'])
on conflict (id) do update set public=false, file_size_limit=excluded.file_size_limit, allowed_mime_types=excluded.allowed_mime_types;

drop policy if exists "Students read academic content" on storage.objects;
create policy "Students read academic content" on storage.objects for select to authenticated
using (bucket_id = 'academic-content');
drop policy if exists "Admins upload academic content" on storage.objects;
create policy "Admins upload academic content" on storage.objects for insert to authenticated
with check (bucket_id = 'academic-content' and (select public.is_app_admin()));
drop policy if exists "Admins update academic content" on storage.objects;
create policy "Admins update academic content" on storage.objects for update to authenticated
using (bucket_id = 'academic-content' and (select public.is_app_admin()))
with check (bucket_id = 'academic-content' and (select public.is_app_admin()));
drop policy if exists "Admins delete academic content" on storage.objects;
create policy "Admins delete academic content" on storage.objects for delete to authenticated
using (bucket_id = 'academic-content' and (select public.is_app_admin()));

-- Admin uploader permissions; student reads remain governed by existing policies.
grant insert, update, delete on public.past_papers, public.lecture_slides, public.timetables, public.online_classes, public.app_content to authenticated;
do $$
declare t text;
begin
  foreach t in array array['past_papers','lecture_slides','timetables','online_classes','app_content'] loop
    execute format('drop policy if exists %I on public.%I', 'Admins manage ' || t, t);
    execute format('create policy %I on public.%I for all to authenticated using ((select public.is_app_admin())) with check ((select public.is_app_admin()))', 'Admins manage ' || t, t);
  end loop;
end $$;

insert into public.app_content(section, slug, title, subtitle, data, sort_order, is_active)
values
('helpful_contacts','gsc-head-office','Gert Sibande TVET College Head Office','Official college switchboard',
 '{"category":"College support","action":"phone","value":"0177129040","display_value":"017 712 9040"}'::jsonb,10,true),
('helpful_contacts','student-support','Student Support Services','Academic, wellbeing, disability and financial-aid support',
 '{"category":"Student support","action":"web","value":"https://gscollege.edu.za/student-support/","display_value":"Open official support page"}'::jsonb,20,true),
('helpful_contacts','south-africa-emergency','National emergency services','Police, ambulance or fire emergency',
 '{"category":"Emergency","action":"phone","value":"112","display_value":"112"}'::jsonb,1,true)
on conflict (section, slug) do update set
 title=excluded.title, subtitle=excluded.subtitle, data=excluded.data,
 sort_order=excluded.sort_order, is_active=excluded.is_active, updated_at=now();
