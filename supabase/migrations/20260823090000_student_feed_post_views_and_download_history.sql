create table if not exists public.post_views (
  user_id uuid not null references auth.users(id) on delete cascade,
  post_id uuid not null references public.posts(id) on delete cascade,
  first_seen_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  primary key (user_id, post_id)
);

alter table public.post_views enable row level security;
grant select, insert, update, delete on public.post_views to authenticated;

create index if not exists post_views_post_id_idx
  on public.post_views(post_id);

drop policy if exists "Students read own post views" on public.post_views;
create policy "Students read own post views"
on public.post_views for select to authenticated
using (
  (select auth.uid()) = user_id
  and (select private.is_account_active())
);

drop policy if exists "Students create own post views" on public.post_views;
create policy "Students create own post views"
on public.post_views for insert to authenticated
with check (
  (select auth.uid()) = user_id
  and (select private.is_account_active())
);

drop policy if exists "Students update own post views" on public.post_views;
create policy "Students update own post views"
on public.post_views for update to authenticated
using (
  (select auth.uid()) = user_id
  and (select private.is_account_active())
)
with check (
  (select auth.uid()) = user_id
  and (select private.is_account_active())
);

drop policy if exists "Students delete own post views" on public.post_views;
create policy "Students delete own post views"
on public.post_views for delete to authenticated
using (
  (select auth.uid()) = user_id
  and (select private.is_account_active())
);

alter table public.download_history
  add column if not exists storage_bucket text not null default 'academic-content';

comment on table public.post_views is
  'Tracks which feed posts each signed-in student has actually seen.';

comment on column public.download_history.storage_bucket is
  'Private Storage bucket used to regenerate a fresh download link.';
