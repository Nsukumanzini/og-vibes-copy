-- Keep one authoritative auth-user trigger for both student profiles and
-- lecturer applications. A later lecturer-onboarding migration accidentally
-- omitted student nickname/course fields and read student_type with the wrong
-- metadata key.

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
  selected_department text := coalesce(
    nullif(btrim(new.raw_user_meta_data->>'department'), ''),
    nullif(btrim(new.raw_user_meta_data->>'course'), ''),
    ''
  );
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
        select jsonb_array_elements_text(
          coalesce(new.raw_user_meta_data->'module_ids', '[]'::jsonb)
        )
      );

    if cardinality(selected_module_ids) = 0 then
      raise exception 'Choose at least one module from the selected programme.';
    end if;
  end if;

  insert into public.profiles (
    id, email, name, surname, nickname, campus, department, course, level,
    student_type, gender, student_number, phone, timezone_name,
    timezone_offset, device_locale, role
  ) values (
    new.id,
    coalesce(new.email, new.id::text || '@phone.local'),
    coalesce(nullif(btrim(new.raw_user_meta_data->>'name'), ''), 'Student'),
    coalesce(new.raw_user_meta_data->>'surname', ''),
    nullif(btrim(new.raw_user_meta_data->>'nickname'), ''),
    coalesce(nullif(btrim(new.raw_user_meta_data->>'campus'), ''), 'Not selected'),
    case when is_lecturer_application then '' else selected_department end,
    case
      when is_lecturer_application then selected_programme_name
      else selected_department
    end,
    coalesce(nullif(btrim(new.raw_user_meta_data->>'level'), ''), 'Not selected'),
    case
      when is_lecturer_application then 'staff'
      else coalesce(
        nullif(btrim(new.raw_user_meta_data->>'student_type'), ''),
        nullif(btrim(new.raw_user_meta_data->>'studentType'), ''),
        'Student'
      )
    end,
    coalesce(nullif(btrim(new.raw_user_meta_data->>'gender'), ''), 'Prefer not to say'),
    coalesce(
      nullif(btrim(new.raw_user_meta_data->>'student_number'), ''),
      nullif(btrim(new.raw_user_meta_data->>'studentNumber'), '')
    ),
    nullif(btrim(new.raw_user_meta_data->>'phone'), ''),
    coalesce(
      nullif(btrim(new.raw_user_meta_data->>'timezone_name'), ''),
      nullif(btrim(new.raw_user_meta_data->>'timeZoneName'), '')
    ),
    coalesce(
      nullif(btrim(new.raw_user_meta_data->>'timezone_offset'), ''),
      nullif(btrim(new.raw_user_meta_data->>'timeZoneOffset'), '')
    ),
    coalesce(
      nullif(btrim(new.raw_user_meta_data->>'device_locale'), ''),
      nullif(btrim(new.raw_user_meta_data->>'deviceLocale'), '')
    ),
    case when is_lecturer_application then 'pending_lecturer' else 'student' end
  );

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

revoke execute on function public.handle_new_user() from public, anon, authenticated;

-- Remove the two competing profile triggers and install the unified trigger.
drop trigger if exists on_auth_user_created_profile on auth.users;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();

-- Repair only missing/default profile values for accounts already created.
-- Existing student edits are deliberately preserved.
update public.profiles as profile
set
  nickname = case
    when nullif(btrim(profile.nickname), '') is null
      then nullif(btrim(auth_user.raw_user_meta_data->>'nickname'), '')
    else profile.nickname
  end,
  department = case
    when nullif(btrim(profile.department), '') is null
      or profile.department = 'Not selected'
      then coalesce(
        nullif(btrim(auth_user.raw_user_meta_data->>'department'), ''),
        nullif(btrim(auth_user.raw_user_meta_data->>'course'), ''),
        profile.department
      )
    else profile.department
  end,
  course = case
    when nullif(btrim(profile.course), '') is null
      then coalesce(
        nullif(btrim(auth_user.raw_user_meta_data->>'course'), ''),
        nullif(btrim(auth_user.raw_user_meta_data->>'department'), ''),
        profile.course
      )
    else profile.course
  end,
  student_type = case
    when nullif(btrim(profile.student_type), '') is null
      then coalesce(
        nullif(btrim(auth_user.raw_user_meta_data->>'student_type'), ''),
        nullif(btrim(auth_user.raw_user_meta_data->>'studentType'), ''),
        profile.student_type
      )
    else profile.student_type
  end,
  student_number = case
    when nullif(btrim(profile.student_number), '') is null
      then coalesce(
        nullif(btrim(auth_user.raw_user_meta_data->>'student_number'), ''),
        nullif(btrim(auth_user.raw_user_meta_data->>'studentNumber'), ''),
        profile.student_number
      )
    else profile.student_number
  end
from auth.users as auth_user
where profile.id = auth_user.id
  and (
    nullif(btrim(profile.nickname), '') is null
    or nullif(btrim(profile.department), '') is null
    or profile.department = 'Not selected'
    or nullif(btrim(profile.course), '') is null
    or nullif(btrim(profile.student_type), '') is null
    or nullif(btrim(profile.student_number), '') is null
  );
