create table if not exists public.post_polls (
  post_id uuid primary key references public.posts(id) on delete cascade,
  question text not null check (char_length(btrim(question)) between 1 and 280),
  created_at timestamptz not null default now()
);

create table if not exists public.post_poll_options (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.post_polls(post_id) on delete cascade,
  label text not null check (char_length(btrim(label)) between 1 and 160),
  position smallint not null check (position between 0 and 9),
  unique (post_id, position),
  unique (id, post_id)
);

create table if not exists public.post_poll_votes (
  post_id uuid not null references public.post_polls(post_id) on delete cascade,
  option_id uuid not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (post_id, user_id),
  foreign key (option_id, post_id)
    references public.post_poll_options(id, post_id)
    on delete cascade
);

alter table public.post_polls enable row level security;
alter table public.post_poll_options enable row level security;
alter table public.post_poll_votes enable row level security;

revoke all on table public.post_polls from anon;
revoke all on table public.post_poll_options from anon;
revoke all on table public.post_poll_votes from anon;
grant select, insert, update, delete on table public.post_polls to authenticated;
grant select, insert, update, delete on table public.post_poll_options to authenticated;
grant select, insert, update, delete on table public.post_poll_votes to authenticated;
grant all on table public.post_polls to service_role;
grant all on table public.post_poll_options to service_role;
grant all on table public.post_poll_votes to service_role;

drop policy if exists "Students can view post polls" on public.post_polls;
create policy "Students can view post polls"
  on public.post_polls for select to authenticated
  using (true);

drop policy if exists "Post owners can create polls" on public.post_polls;
create policy "Post owners can create polls"
  on public.post_polls for insert to authenticated
  with check (
    exists (
      select 1 from public.posts
      where posts.id = post_polls.post_id
        and posts.user_id = (select auth.uid())
        and not posts.is_deleted
    )
  );

drop policy if exists "Post owners can update polls" on public.post_polls;
create policy "Post owners can update polls"
  on public.post_polls for update to authenticated
  using (
    exists (
      select 1 from public.posts
      where posts.id = post_polls.post_id
        and posts.user_id = (select auth.uid())
    )
  )
  with check (
    exists (
      select 1 from public.posts
      where posts.id = post_polls.post_id
        and posts.user_id = (select auth.uid())
    )
  );

drop policy if exists "Post owners can delete polls" on public.post_polls;
create policy "Post owners can delete polls"
  on public.post_polls for delete to authenticated
  using (
    exists (
      select 1 from public.posts
      where posts.id = post_polls.post_id
        and posts.user_id = (select auth.uid())
    )
  );

drop policy if exists "Students can view poll options" on public.post_poll_options;
create policy "Students can view poll options"
  on public.post_poll_options for select to authenticated
  using (true);

drop policy if exists "Post owners can manage poll options" on public.post_poll_options;
create policy "Post owners can manage poll options"
  on public.post_poll_options for all to authenticated
  using (
    exists (
      select 1 from public.posts
      where posts.id = post_poll_options.post_id
        and posts.user_id = (select auth.uid())
    )
  )
  with check (
    exists (
      select 1 from public.posts
      where posts.id = post_poll_options.post_id
        and posts.user_id = (select auth.uid())
        and not posts.is_deleted
    )
  );

drop policy if exists "Students can view poll results" on public.post_poll_votes;
create policy "Students can view poll results"
  on public.post_poll_votes for select to authenticated
  using (true);

drop policy if exists "Students can vote as themselves" on public.post_poll_votes;
create policy "Students can vote as themselves"
  on public.post_poll_votes for insert to authenticated
  with check (
    user_id = (select auth.uid())
    and exists (
      select 1 from public.post_poll_options option
      where option.id = post_poll_votes.option_id
        and option.post_id = post_poll_votes.post_id
    )
  );

drop policy if exists "Students can change own vote" on public.post_poll_votes;
create policy "Students can change own vote"
  on public.post_poll_votes for update to authenticated
  using (user_id = (select auth.uid()))
  with check (
    user_id = (select auth.uid())
    and exists (
      select 1 from public.post_poll_options option
      where option.id = post_poll_votes.option_id
        and option.post_id = post_poll_votes.post_id
    )
  );

drop policy if exists "Students can remove own vote" on public.post_poll_votes;
create policy "Students can remove own vote"
  on public.post_poll_votes for delete to authenticated
  using (user_id = (select auth.uid()));

create index if not exists post_poll_options_post_id_idx
  on public.post_poll_options (post_id);
create index if not exists post_poll_votes_option_id_idx
  on public.post_poll_votes (option_id);
create index if not exists post_poll_votes_user_id_idx
  on public.post_poll_votes (user_id);

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'posts', 'post_likes', 'comments',
    'post_polls', 'post_poll_options', 'post_poll_votes'
  ]
  loop
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = table_name
    ) then
      execute format(
        'alter publication supabase_realtime add table public.%I',
        table_name
      );
    end if;
  end loop;
end
$$;
