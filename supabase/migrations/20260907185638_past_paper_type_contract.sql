alter table public.past_papers
  add column if not exists paper_type text;

create or replace function private.sync_past_paper_legacy_fields()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  linked_module_name text;
  linked_module_level text;
begin
  if new.paper_type is null then
    new.paper_type := 'Paper 1';
  end if;

  if new.module_id is not null then
    select m.name, m.level
      into linked_module_name, linked_module_level
    from public.modules as m
    where m.id = new.module_id;

    if linked_module_name is not null then
      new.subject := linked_module_name;
    end if;
    if linked_module_level is not null then
      new.level := linked_module_level;
    end if;
  end if;

  -- Keep legacy clients and notification triggers working during the rollout.
  -- New clients never ask the uploader to enter or display this generated value.
  new.title := concat_ws(
    ' · ',
    coalesce(linked_module_name, nullif(btrim(new.subject), ''), 'Past paper'),
    nullif(btrim(new.exam_type), ''),
    new.paper_type,
    new.year::text
  );
  return new;
end;
$$;

revoke all on function private.sync_past_paper_legacy_fields()
  from public, anon, authenticated;

drop trigger if exists sync_past_paper_legacy_fields on public.past_papers;
create trigger sync_past_paper_legacy_fields
before insert or update of module_id, subject, level, exam_type, paper_type, year
on public.past_papers
for each row execute function private.sync_past_paper_legacy_fields();

update public.past_papers
set paper_type = case
  when lower(concat_ws(' ', title, storage_path))
       ~ '(^|[^a-z0-9])(paper[ _-]*2|p2)([^a-z0-9]|$)'
    then 'Paper 2'
  else 'Paper 1'
end
where paper_type is null
   or paper_type not in ('Paper 1', 'Paper 2');

alter table public.past_papers
  alter column paper_type set default 'Paper 1',
  alter column paper_type set not null;

alter table public.past_papers
  drop constraint if exists past_papers_paper_type_check;
alter table public.past_papers
  add constraint past_papers_paper_type_check
  check (paper_type in ('Paper 1', 'Paper 2'));

create index if not exists past_papers_created_by_idx
  on public.past_papers (created_by);
