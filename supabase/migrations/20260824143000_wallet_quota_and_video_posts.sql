-- Enforce the student Document Wallet quota and add first-class post videos.

alter table public.posts
  add column if not exists videos text[] not null default '{}'::text[];

comment on column public.posts.videos is
  'Private Storage object paths for videos attached to this post.';

create or replace function private.enforce_student_document_quota()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  total_bytes bigint;
  quota_bytes constant bigint := 31457280;
begin
  if tg_op = 'UPDATE'
     and new.user_id is not distinct from old.user_id
     and new.file_size is not distinct from old.file_size then
    return new;
  end if;

  if new.user_id is null then
    raise exception using
      errcode = '23514',
      message = 'A wallet document must belong to a student.';
  end if;

  if coalesce(new.file_size, 0) < 0 then
    raise exception using
      errcode = '23514',
      message = 'A wallet document cannot have a negative file size.';
  end if;

  -- Serialise quota-changing writes for the same student so concurrent
  -- uploads cannot both pass the quota check.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(new.user_id::text, 0)
  );

  select coalesce(sum(document.file_size), 0)
    into total_bytes
    from public.student_documents as document
   where document.user_id = new.user_id
     and document.id is distinct from new.id;

  if total_bytes + coalesce(new.file_size, 0) > quota_bytes then
    raise exception using
      errcode = '23514',
      message = 'Your Document Wallet has reached its 30 MB storage limit.';
  end if;

  return new;
end;
$$;

revoke all on function private.enforce_student_document_quota() from public;
revoke all on function private.enforce_student_document_quota() from anon;
revoke all on function private.enforce_student_document_quota() from authenticated;

drop trigger if exists enforce_student_document_quota
  on public.student_documents;
create trigger enforce_student_document_quota
before insert or update of user_id, file_size
on public.student_documents
for each row
execute function private.enforce_student_document_quota();

update storage.buckets
set file_size_limit = 31457280
where id = 'documents';

update storage.buckets
set file_size_limit = 26214400
where id = 'posts';
