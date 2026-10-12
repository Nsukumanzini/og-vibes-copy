-- Exercise a pending application through the backend role without committing
-- its approval. All profile and module changes are rolled back at the end.
begin;
set local role service_role;
do $$
declare
  reviewer uuid;
  target public.lecturer_applications;
  result jsonb;
begin
  select id into reviewer from public.profiles
  where role = 'admin' and account_status = 'active' limit 1;
  select * into target from public.lecturer_applications
  where status = 'pending' and programme_id is not null
    and cardinality(requested_module_ids) > 0 limit 1;
  if reviewer is null or target.id is null then
    raise exception 'No eligible reviewer or pending application for this test';
  end if;
  result := public.admin_review_lecturer_application(
    target.id, 'approved', 'Rollback-only verification', reviewer);
  if result->>'status' <> 'approved' or not exists (
    select 1 from public.profiles where id = target.user_id and role = 'lecturer'
  ) then raise exception 'Approval did not update the lecturer profile'; end if;
  if exists (
    select 1 from unnest(target.requested_module_ids) as requested(module_id)
    where not exists (select 1 from public.module_lecturers ml
      where ml.module_id = requested.module_id and ml.lecturer_id = target.user_id)
  ) then raise exception 'Approval did not assign all requested modules'; end if;
end;
$$;
select 'Approval and module assignment passed; changes rolled back' as verification;
rollback;
