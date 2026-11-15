create or replace function public.revoke_admin_sessions(target_user_id uuid)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  removed_count bigint;
begin
  delete from auth.sessions
  where user_id = target_user_id;

  get diagnostics removed_count = row_count;
  return removed_count;
end;
$$;

revoke all on function public.revoke_admin_sessions(uuid) from public, anon, authenticated;
grant execute on function public.revoke_admin_sessions(uuid) to service_role;
