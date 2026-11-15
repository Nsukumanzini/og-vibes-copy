create table if not exists public.sos_trusted_contacts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  priority smallint not null check (priority between 1 and 2),
  name text not null check (char_length(name) between 2 and 80),
  phone text not null check (char_length(phone) between 7 and 24),
  relationship text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, priority),
  unique (user_id, phone)
);

create table if not exists public.safety_responders (
  user_id uuid primary key references auth.users(id) on delete cascade,
  responder_type text not null check (responder_type in ('admin', 'src')),
  campus text,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.sos_incidents (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  emergency_type text not null check (emergency_type in ('ambulance', 'firefighters', 'police')),
  silent_mode boolean not null default false,
  evidence_enabled boolean not null default false,
  status text not null default 'active' check (status in ('active', 'cancelled', 'resolved')),
  campus text not null default '',
  latitude double precision,
  longitude double precision,
  accuracy_meters double precision,
  maps_url text,
  responder_notified_at timestamptz,
  sms_fallback_used boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  resolved_at timestamptz
);

create table if not exists public.sos_location_updates (
  id bigint generated always as identity primary key,
  incident_id uuid not null references public.sos_incidents(id) on delete cascade,
  student_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  latitude double precision not null,
  longitude double precision not null,
  accuracy_meters double precision,
  recorded_at timestamptz not null default now()
);

create table if not exists public.sos_evidence (
  id uuid primary key default gen_random_uuid(),
  incident_id uuid not null references public.sos_incidents(id) on delete cascade,
  student_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  evidence_type text not null check (evidence_type in ('front_photo', 'rear_photo', 'audio')),
  storage_path text not null,
  mime_type text not null,
  capture_seconds integer,
  created_at timestamptz not null default now(),
  unique (incident_id, evidence_type)
);

alter table public.sos_trusted_contacts enable row level security;
alter table public.safety_responders enable row level security;
alter table public.sos_incidents enable row level security;
alter table public.sos_location_updates enable row level security;
alter table public.sos_evidence enable row level security;

grant select, insert, update, delete on public.sos_trusted_contacts to authenticated;
grant select on public.safety_responders to authenticated;
grant select, insert, update on public.sos_incidents to authenticated;
grant select, insert on public.sos_location_updates to authenticated;
grant select, insert on public.sos_evidence to authenticated;
grant usage, select on sequence public.sos_location_updates_id_seq to authenticated;

create index if not exists sos_trusted_contacts_user_idx on public.sos_trusted_contacts(user_id);
create index if not exists sos_incidents_student_created_idx on public.sos_incidents(student_id, created_at desc);
create index if not exists sos_incidents_status_campus_idx on public.sos_incidents(status, campus, created_at desc);
create index if not exists sos_location_incident_time_idx on public.sos_location_updates(incident_id, recorded_at desc);
create index if not exists sos_evidence_incident_idx on public.sos_evidence(incident_id);

drop policy if exists "Students manage two trusted contacts" on public.sos_trusted_contacts;
create policy "Students manage two trusted contacts" on public.sos_trusted_contacts
for all to authenticated using (user_id = (select auth.uid()))
with check (user_id = (select auth.uid()));

drop policy if exists "Responders view own assignment" on public.safety_responders;
create policy "Responders view own assignment" on public.safety_responders
for select to authenticated using (user_id = (select auth.uid()));

drop policy if exists "Students create own SOS incidents" on public.sos_incidents;
create policy "Students create own SOS incidents" on public.sos_incidents
for insert to authenticated with check (student_id = (select auth.uid()));
drop policy if exists "Students and responders view SOS incidents" on public.sos_incidents;
create policy "Students and responders view SOS incidents" on public.sos_incidents
for select to authenticated using (
  student_id = (select auth.uid()) or exists (
    select 1 from public.safety_responders responder
    where responder.user_id = (select auth.uid()) and responder.active
      and (responder.campus is null or responder.campus = sos_incidents.campus)
  )
);
drop policy if exists "Students update own SOS incidents" on public.sos_incidents;
create policy "Students update own SOS incidents" on public.sos_incidents
for update to authenticated using (student_id = (select auth.uid()))
with check (student_id = (select auth.uid()));

drop policy if exists "Students add own live locations" on public.sos_location_updates;
create policy "Students add own live locations" on public.sos_location_updates
for insert to authenticated with check (
  student_id = (select auth.uid()) and exists (
    select 1 from public.sos_incidents incident
    where incident.id = incident_id and incident.student_id = (select auth.uid())
  )
);
drop policy if exists "Students and responders view live locations" on public.sos_location_updates;
create policy "Students and responders view live locations" on public.sos_location_updates
for select to authenticated using (
  student_id = (select auth.uid()) or exists (
    select 1 from public.sos_incidents incident
    join public.safety_responders responder on responder.user_id = (select auth.uid()) and responder.active
    where incident.id = incident_id and (responder.campus is null or responder.campus = incident.campus)
  )
);

drop policy if exists "Students add own SOS evidence" on public.sos_evidence;
create policy "Students add own SOS evidence" on public.sos_evidence
for insert to authenticated with check (
  student_id = (select auth.uid()) and exists (
    select 1 from public.sos_incidents incident
    where incident.id = incident_id and incident.student_id = (select auth.uid())
  )
);
drop policy if exists "Students and responders view SOS evidence" on public.sos_evidence;
create policy "Students and responders view SOS evidence" on public.sos_evidence
for select to authenticated using (
  student_id = (select auth.uid()) or exists (
    select 1 from public.sos_incidents incident
    join public.safety_responders responder on responder.user_id = (select auth.uid()) and responder.active
    where incident.id = incident_id and (responder.campus is null or responder.campus = incident.campus)
  )
);

insert into storage.buckets(id, name, public, file_size_limit, allowed_mime_types)
values (
  'sos-evidence', 'sos-evidence', false, 15728640,
  array['image/jpeg','image/png','audio/wav','audio/mp4','audio/aac']
)
on conflict (id) do update set public=false, file_size_limit=excluded.file_size_limit,
allowed_mime_types=excluded.allowed_mime_types;

drop policy if exists "Students upload own SOS evidence" on storage.objects;
create policy "Students upload own SOS evidence" on storage.objects
for insert to authenticated with check (
  bucket_id = 'sos-evidence' and (storage.foldername(name))[1] = (select auth.uid())::text
);
drop policy if exists "Students read own SOS evidence" on storage.objects;
create policy "Students read own SOS evidence" on storage.objects
for select to authenticated using (
  bucket_id = 'sos-evidence' and (storage.foldername(name))[1] = (select auth.uid())::text
);

