create index if not exists accommodations_created_by_idx on public.accommodations (created_by);
create index if not exists events_organizer_id_idx on public.events (organizer_id);
create index if not exists events_submitted_by_idx on public.events (submitted_by);
create index if not exists events_reviewed_by_idx on public.events (reviewed_by);
