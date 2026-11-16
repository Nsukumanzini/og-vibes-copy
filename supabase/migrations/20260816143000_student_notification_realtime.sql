begin;

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'student_notifications'
  ) then
    alter publication supabase_realtime add table public.student_notifications;
  end if;
end;
$$;

commit;
