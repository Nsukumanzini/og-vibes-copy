-- Lecturer self-service applications choose an administrator-managed programme
-- and one or more modules. Requested modules grant no access until an admin
-- approves the application through the protected admin-control function.

alter table public.profiles drop constraint if exists profiles_role_check;
alter table public.profiles add constraint profiles_role_check
  check (role in ('student', 'pending_lecturer', 'lecturer', 'admin'));

alter table public.lecturer_applications
  add column if not exists programme_id uuid references public.programmes(id) on delete restrict,
  add column if not exists requested_module_ids uuid[] not null default '{}'::uuid[];

create index if not exists lecturer_applications_programme_id_idx
  on public.lecturer_applications (programme_id);

grant select (id, name) on public.programmes to anon, authenticated;
grant select (id, programme_id, level, name, code) on public.modules to anon, authenticated;

drop policy if exists "Public reads lecturer signup programmes" on public.programmes;
create policy "Public reads lecturer signup programmes"
on public.programmes for select to anon, authenticated using (true);

drop policy if exists "Public reads lecturer signup modules" on public.modules;
create policy "Public reads lecturer signup modules"
on public.modules for select to anon, authenticated using (true);

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  is_lecturer_application boolean :=
    coalesce(new.raw_user_meta_data->>'account_type', '') = 'lecturer';
  selected_programme_id uuid;
  selected_programme_name text;
  selected_module_ids uuid[] := '{}'::uuid[];
begin
  if is_lecturer_application then
    select programme.id, programme.name
      into selected_programme_id, selected_programme_name
    from public.programmes as programme
    where programme.id::text = coalesce(new.raw_user_meta_data->>'programme_id', '')
    limit 1;

    if selected_programme_id is null then
      raise exception 'Choose a valid programme.';
    end if;

    if jsonb_typeof(coalesce(new.raw_user_meta_data->'module_ids', '[]'::jsonb)) <> 'array' then
      raise exception 'Choose valid modules.';
    end if;

    select coalesce(array_agg(module.id order by module.name), '{}'::uuid[])
      into selected_module_ids
    from public.modules as module
    where module.programme_id = selected_programme_id
      and module.id::text in (
        select jsonb_array_elements_text(coalesce(new.raw_user_meta_data->'module_ids', '[]'::jsonb))
      );

    if cardinality(selected_module_ids) = 0 then
      raise exception 'Choose at least one module from the selected programme.';
    end if;
  end if;

  insert into public.profiles (
    id, email, name, surname, campus, department, course, level,
    student_type, gender, role
  ) values (
    new.id, coalesce(new.email, ''),
    coalesce(new.raw_user_meta_data->>'name', ''),
    coalesce(new.raw_user_meta_data->>'surname', ''),
    coalesce(new.raw_user_meta_data->>'campus', ''),
    '',
    case when is_lecturer_application then selected_programme_name else '' end,
    coalesce(new.raw_user_meta_data->>'level', ''),
    case when is_lecturer_application then 'staff' else coalesce(new.raw_user_meta_data->>'studentType', '') end,
    coalesce(new.raw_user_meta_data->>'gender', ''),
    case when is_lecturer_application then 'pending_lecturer' else 'student' end
  ) on conflict (id) do update set
    email = excluded.email;

  if is_lecturer_application then
    insert into public.lecturer_applications (
      user_id, status, programme_id, requested_module_ids, staff_id, department
    ) values (
      new.id, 'pending', selected_programme_id, selected_module_ids, null, null
    ) on conflict (user_id) do update set
      status = 'pending',
      programme_id = excluded.programme_id,
      requested_module_ids = excluded.requested_module_ids,
      staff_id = null,
      department = null,
      admin_note = null,
      reviewed_by = null,
      reviewed_at = null;
  end if;
  return new;
end;
$$;

create or replace function public.admin_review_lecturer_application(
  target_application_id uuid,
  decision text,
  review_note text,
  reviewer_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  application public.lecturer_applications;
  programme_name text;
  invalid_module_count integer;
begin
  if not exists (
    select 1 from public.profiles
    where id = reviewer_id and role = 'admin' and account_status = 'active'
  ) then
    raise exception 'Administrator approval is required.';
  end if;

  if decision not in ('approved', 'rejected') then
    raise exception 'Choose Approve or Reject.';
  end if;

  select * into application
  from public.lecturer_applications
  where id = target_application_id
  for update;

  if not found then raise exception 'Lecturer application not found.'; end if;

  if decision = 'approved' then
    if application.programme_id is null or cardinality(application.requested_module_ids) = 0 then
      raise exception 'The lecturer must choose a programme and at least one module.';
    end if;

    select count(*) into invalid_module_count
    from unnest(application.requested_module_ids) as requested(module_id)
    left join public.modules as module
      on module.id = requested.module_id
     and module.programme_id = application.programme_id
    where module.id is null;

    if invalid_module_count > 0 then
      raise exception 'One or more requested modules do not belong to the selected programme.';
    end if;

    select name into programme_name
    from public.programmes where id = application.programme_id;

    update public.profiles
    set role = 'lecturer', course = coalesce(programme_name, course), department = ''
    where id = application.user_id;

    insert into public.module_lecturers (module_id, lecturer_id)
    select module_id, application.user_id
    from unnest(application.requested_module_ids) as requested(module_id)
    on conflict (module_id, lecturer_id) do nothing;
  else
    delete from public.module_lecturers where lecturer_id = application.user_id;
    update public.profiles set role = 'pending_lecturer' where id = application.user_id;
  end if;

  update public.lecturer_applications
  set status = decision,
      admin_note = nullif(trim(review_note), ''),
      reviewed_by = reviewer_id,
      reviewed_at = now()
  where id = target_application_id
  returning * into application;

  return to_jsonb(application);
end;
$$;

revoke all on function public.admin_review_lecturer_application(uuid, text, text, uuid)
  from public, anon, authenticated;
grant execute on function public.admin_review_lecturer_application(uuid, text, text, uuid)
  to service_role;
