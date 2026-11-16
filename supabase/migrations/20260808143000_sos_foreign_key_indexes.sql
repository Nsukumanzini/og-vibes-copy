drop index if exists public.sos_trusted_contacts_user_idx;
create index if not exists sos_location_student_idx on public.sos_location_updates(student_id);
create index if not exists sos_evidence_student_idx on public.sos_evidence(student_id);

