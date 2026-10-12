-- OG Assistant: permission-aware extractive search over approved material.

create extension if not exists vector with schema extensions;

create table if not exists public.academic_assistant_documents (
  id uuid primary key default gen_random_uuid(),
  source_type text not null check (source_type in ('lecture_slide', 'academic_note', 'past_paper')),
  source_id uuid not null,
  module_id uuid not null references public.modules(id) on delete cascade,
  title text not null,
  storage_path text not null,
  approved boolean not null default true,
  approved_by uuid not null default auth.uid() references public.profiles(id) on delete restrict,
  index_status text not null default 'indexing' check (index_status in ('indexing', 'ready', 'failed')),
  indexed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (source_type, source_id)
);

create table if not exists public.academic_assistant_chunks (
  id bigint generated always as identity primary key,
  document_id uuid not null references public.academic_assistant_documents(id) on delete cascade,
  page_number integer not null check (page_number > 0),
  chunk_index integer not null check (chunk_index >= 0),
  content text not null check (char_length(content) between 20 and 2400),
  embedding extensions.vector(384),
  created_at timestamptz not null default now(),
  unique (document_id, page_number, chunk_index)
);

alter table public.academic_assistant_documents enable row level security;
alter table public.academic_assistant_chunks enable row level security;

grant select, insert, update, delete on public.academic_assistant_documents to authenticated;
grant select, insert, update, delete on public.academic_assistant_chunks to authenticated;
grant usage, select on sequence public.academic_assistant_chunks_id_seq to authenticated;
grant usage on schema extensions to authenticated;

drop policy if exists "Authorized users read approved assistant documents"
  on public.academic_assistant_documents;
create policy "Authorized users read approved assistant documents"
on public.academic_assistant_documents for select to authenticated
using (approved and (select private.can_access_module(module_id)));

drop policy if exists "Academic publishers create assistant documents"
  on public.academic_assistant_documents;
create policy "Academic publishers create assistant documents"
on public.academic_assistant_documents for insert to authenticated
with check (
  approved
  and approved_by = (select auth.uid())
  and (select private.can_manage_module(module_id))
);

drop policy if exists "Academic publishers update assistant documents"
  on public.academic_assistant_documents;
create policy "Academic publishers update assistant documents"
on public.academic_assistant_documents for update to authenticated
using (
  approved_by = (select auth.uid())
  and (select private.can_manage_module(module_id))
)
with check (
  approved_by = (select auth.uid())
  and (select private.can_manage_module(module_id))
);

drop policy if exists "Academic publishers delete assistant documents"
  on public.academic_assistant_documents;
create policy "Academic publishers delete assistant documents"
on public.academic_assistant_documents for delete to authenticated
using (
  approved_by = (select auth.uid())
  and (select private.can_manage_module(module_id))
);

drop policy if exists "Authorized users read approved assistant chunks"
  on public.academic_assistant_chunks;
create policy "Authorized users read approved assistant chunks"
on public.academic_assistant_chunks for select to authenticated
using (
  exists (
    select 1
    from public.academic_assistant_documents document
    where document.id = document_id
      and document.approved
      and (select private.can_access_module(document.module_id))
  )
);

drop policy if exists "Academic publishers create assistant chunks"
  on public.academic_assistant_chunks;
create policy "Academic publishers create assistant chunks"
on public.academic_assistant_chunks for insert to authenticated
with check (
  exists (
    select 1
    from public.academic_assistant_documents document
    where document.id = document_id
      and document.approved_by = (select auth.uid())
      and (select private.can_manage_module(document.module_id))
  )
);

drop policy if exists "Academic publishers update assistant chunks"
  on public.academic_assistant_chunks;
create policy "Academic publishers update assistant chunks"
on public.academic_assistant_chunks for update to authenticated
using (
  exists (
    select 1
    from public.academic_assistant_documents document
    where document.id = document_id
      and document.approved_by = (select auth.uid())
      and (select private.can_manage_module(document.module_id))
  )
)
with check (
  exists (
    select 1
    from public.academic_assistant_documents document
    where document.id = document_id
      and document.approved_by = (select auth.uid())
      and (select private.can_manage_module(document.module_id))
  )
);

drop policy if exists "Academic publishers delete assistant chunks"
  on public.academic_assistant_chunks;
create policy "Academic publishers delete assistant chunks"
on public.academic_assistant_chunks for delete to authenticated
using (
  exists (
    select 1
    from public.academic_assistant_documents document
    where document.id = document_id
      and document.approved_by = (select auth.uid())
      and (select private.can_manage_module(document.module_id))
  )
);

create index if not exists academic_assistant_documents_module_idx
  on public.academic_assistant_documents(module_id, approved, index_status);
create index if not exists academic_assistant_documents_approved_by_idx
  on public.academic_assistant_documents(approved_by);
create index if not exists academic_assistant_chunks_document_idx
  on public.academic_assistant_chunks(document_id, page_number, chunk_index);
create index if not exists academic_assistant_chunks_embedding_hnsw_idx
  on public.academic_assistant_chunks
  using hnsw (embedding extensions.vector_ip_ops)
  where embedding is not null;

create or replace function public.match_academic_chunks(
  query_embedding extensions.vector(384),
  match_threshold double precision default 0.52,
  match_count integer default 6,
  filter_module_id uuid default null
)
returns table (
  document_id uuid,
  title text,
  module_id uuid,
  module_name text,
  module_code text,
  source_type text,
  page_number integer,
  content text,
  storage_path text,
  similarity double precision
)
language sql
stable
security invoker
set search_path = ''
as $$
  select
    document.id,
    document.title,
    document.module_id,
    module.name,
    coalesce(module.code, ''),
    document.source_type,
    chunk.page_number,
    chunk.content,
    document.storage_path,
    -(chunk.embedding operator(extensions.<#>) query_embedding)::double precision
  from public.academic_assistant_chunks chunk
  join public.academic_assistant_documents document on document.id = chunk.document_id
  join public.modules module on module.id = document.module_id
  where document.approved
    and document.index_status = 'ready'
    and chunk.embedding is not null
    and (filter_module_id is null or document.module_id = filter_module_id)
    and -(chunk.embedding operator(extensions.<#>) query_embedding) >= match_threshold
  order by chunk.embedding operator(extensions.<#>) query_embedding
  limit least(greatest(match_count, 1), 10);
$$;

revoke execute on function public.match_academic_chunks(
  extensions.vector, double precision, integer, uuid
) from public, anon;
grant execute on function public.match_academic_chunks(
  extensions.vector, double precision, integer, uuid
) to authenticated;
