create table if not exists public.device_push_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  token text not null unique check (char_length(token) between 20 and 4096),
  platform text not null check (platform in ('android', 'web')),
  device_id text not null check (char_length(device_id) between 8 and 200),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  unique (platform, device_id)
);

alter table public.device_push_tokens enable row level security;
revoke all on table public.device_push_tokens from anon, authenticated;

drop policy if exists "Push tokens are service managed" on public.device_push_tokens;
create policy "Push tokens are service managed"
on public.device_push_tokens
for all
to authenticated
using (false)
with check (false);

create index if not exists device_push_tokens_user_id_idx
  on public.device_push_tokens (user_id);
create index if not exists device_push_tokens_last_seen_at_idx
  on public.device_push_tokens (last_seen_at);

comment on table public.device_push_tokens is
  'Private FCM registrations managed only by the authenticated call-push Edge Function.';
