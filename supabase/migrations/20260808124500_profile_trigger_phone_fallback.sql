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
revoke execute on function public.handle_new_user_profile() from public, anon, authenticated;

