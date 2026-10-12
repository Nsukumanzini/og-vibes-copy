alter table public.career_opportunities
  add column if not exists employer_logo_url text,
  add column if not exists qualification text,
  add column if not exists location text,
  add column if not exists is_remote boolean not null default false,
  add column if not exists course text,
  add column if not exists faculty text,
  add column if not exists level text,
  add column if not exists application_url text,
  add column if not exists closing_at timestamptz,
  add column if not exists requirements text[] not null default '{}',
  add column if not exists is_published boolean not null default true,
  add column if not exists is_verified boolean not null default false,
  add column if not exists updated_at timestamptz not null default now();

create index if not exists career_opportunities_published_created_idx
  on public.career_opportunities (is_published, created_at desc);
create index if not exists career_opportunities_category_idx
  on public.career_opportunities (category);

alter table public.career_opportunities enable row level security;

drop policy if exists "Authenticated users can view career opportunities"
  on public.career_opportunities;
drop policy if exists "Students can view published career opportunities"
  on public.career_opportunities;
create policy "Students can view published career opportunities"
  on public.career_opportunities
  for select
  to authenticated
  using (is_published = true);

revoke all on table public.career_opportunities from anon;
grant select on table public.career_opportunities to authenticated;

create table if not exists public.career_applications (
  id uuid primary key default gen_random_uuid(),
  opportunity_id uuid not null
    references public.career_opportunities(id) on delete cascade,
  student_id uuid not null
    references auth.users(id) on delete cascade,
  status text not null default 'submitted'
    check (status in ('draft', 'submitted', 'withdrawn')),
  cover_note text,
  created_at timestamptz not null default now(),
  submitted_at timestamptz,
  updated_at timestamptz not null default now(),
  unique (opportunity_id, student_id)
);

create index if not exists career_applications_student_updated_idx
  on public.career_applications (student_id, updated_at desc);

alter table public.career_applications enable row level security;

drop policy if exists "Students can view own career applications"
  on public.career_applications;
create policy "Students can view own career applications"
  on public.career_applications
  for select
  to authenticated
  using ((select auth.uid()) = student_id);

drop policy if exists "Students can create own career applications"
  on public.career_applications;
create policy "Students can create own career applications"
  on public.career_applications
  for insert
  to authenticated
  with check ((select auth.uid()) = student_id);

drop policy if exists "Students can update own career applications"
  on public.career_applications;
create policy "Students can update own career applications"
  on public.career_applications
  for update
  to authenticated
  using ((select auth.uid()) = student_id)
  with check ((select auth.uid()) = student_id);

drop policy if exists "Students can delete own draft career applications"
  on public.career_applications;
create policy "Students can delete own draft career applications"
  on public.career_applications
  for delete
  to authenticated
  using ((select auth.uid()) = student_id and status = 'draft');

revoke all on table public.career_applications from anon;
grant select, insert, update, delete
  on table public.career_applications to authenticated;

create table if not exists public.career_application_documents (
  application_id uuid not null
    references public.career_applications(id) on delete cascade,
  document_id uuid not null
    references public.student_documents(id) on delete restrict,
  added_at timestamptz not null default now(),
  primary key (application_id, document_id)
);

create index if not exists career_application_documents_document_idx
  on public.career_application_documents (document_id);

alter table public.career_application_documents enable row level security;

drop policy if exists "Students can view own career application documents"
  on public.career_application_documents;
create policy "Students can view own career application documents"
  on public.career_application_documents
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.career_applications application
      where application.id = application_id
        and application.student_id = (select auth.uid())
    )
  );

drop policy if exists "Students can attach own wallet documents"
  on public.career_application_documents;
create policy "Students can attach own wallet documents"
  on public.career_application_documents
  for insert
  to authenticated
  with check (
    exists (
      select 1
      from public.career_applications application
      where application.id = application_id
        and application.student_id = (select auth.uid())
    )
    and exists (
      select 1
      from public.student_documents document
      where document.id = document_id
        and document.user_id = (select auth.uid())
    )
  );

drop policy if exists "Students can remove own career application documents"
  on public.career_application_documents;
create policy "Students can remove own career application documents"
  on public.career_application_documents
  for delete
  to authenticated
  using (
    exists (
      select 1
      from public.career_applications application
      where application.id = application_id
        and application.student_id = (select auth.uid())
    )
  );

revoke all on table public.career_application_documents from anon;
grant select, insert, delete
  on table public.career_application_documents to authenticated;

create table if not exists public.career_resources (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  title text not null,
  summary text not null,
  body text not null,
  icon_name text not null default 'article',
  is_active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.career_resources enable row level security;

drop policy if exists "Students can view active career resources"
  on public.career_resources;
create policy "Students can view active career resources"
  on public.career_resources
  for select
  to authenticated
  using (is_active = true);

revoke all on table public.career_resources from anon;
grant select on table public.career_resources to authenticated;

insert into public.career_resources
  (slug, title, summary, body, icon_name, sort_order)
values
  (
    'cv-checklist',
    'Build a recruiter-ready CV',
    'A focused checklist for a clear, credible student CV.',
    'Lead with a short profile, education and relevant experience. Use strong action verbs, quantify outcomes where possible, keep formatting consistent, and tailor skills to each opportunity. Proofread before attaching the final PDF from your Document Wallet.',
    'description',
    10
  ),
  (
    'application-guide',
    'Submit a stronger application',
    'Turn requirements into a complete, tailored submission.',
    'Read every requirement, match your evidence to the role, tailor your cover note, attach only requested documents, and submit before the closing date. Keep document names professional and review every field before confirming.',
    'task_alt',
    20
  ),
  (
    'interview-prep',
    'Prepare for interviews',
    'Practise concise examples that show your skills and impact.',
    'Research the organisation and role. Prepare examples using Situation, Task, Action and Result. Practise a short introduction, prepare thoughtful questions, test your setup for online interviews, and send a brief thank-you message afterwards.',
    'record_voice_over',
    30
  )
on conflict (slug) do update set
  title = excluded.title,
  summary = excluded.summary,
  body = excluded.body,
  icon_name = excluded.icon_name,
  sort_order = excluded.sort_order,
  is_active = true,
  updated_at = now();

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'career_opportunities'
  ) then
    alter publication supabase_realtime
      add table public.career_opportunities;
  end if;

  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'career_applications'
  ) then
    alter publication supabase_realtime
      add table public.career_applications;
  end if;
end
$$;
