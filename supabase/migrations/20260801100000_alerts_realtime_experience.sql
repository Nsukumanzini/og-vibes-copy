create table if not exists public.alert_reads (
  user_id uuid not null references auth.users(id) on delete cascade,
  alert_id uuid not null references public.app_content(id) on delete cascade,
  read_at timestamptz not null default now(),
  primary key (user_id, alert_id)
);

comment on table public.alert_reads is
  'Per-user acknowledgement state for active announcements shown in Alerts.';

alter table public.alert_reads enable row level security;

revoke all on table public.alert_reads from anon;
grant select, insert, update on table public.alert_reads to authenticated;
grant all on table public.alert_reads to service_role;

drop policy if exists "Students can read own alert status"
  on public.alert_reads;
create policy "Students can read own alert status"
  on public.alert_reads
  for select
  to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists "Students can acknowledge active alerts"
  on public.alert_reads;
create policy "Students can acknowledge active alerts"
  on public.alert_reads
  for insert
  to authenticated
  with check (
    (select auth.uid()) = user_id
    and exists (
      select 1
      from public.app_content content
      where content.id = alert_reads.alert_id
        and content.section = 'announcements'
        and content.is_active
    )
  );

drop policy if exists "Students can refresh own alert status"
  on public.alert_reads;
create policy "Students can refresh own alert status"
  on public.alert_reads
  for update
  to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create index if not exists alert_reads_alert_id_idx
  on public.alert_reads (alert_id);

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'app_content'
  ) then
    alter publication supabase_realtime add table public.app_content;
  end if;

  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'alert_reads'
  ) then
    alter publication supabase_realtime add table public.alert_reads;
  end if;
end
$$;
