-- Group-call RPCs are client-facing only for authenticated members.
-- PostgreSQL grants EXECUTE to PUBLIC on new functions unless it is revoked
-- explicitly; revoking PUBLIC also removes the inherited anon permission.
revoke execute on function public.start_group_call(uuid, text, uuid[]) from public, anon;
revoke execute on function public.join_group_call(uuid) from public, anon;
revoke execute on function public.decline_group_call(uuid) from public, anon;
revoke execute on function public.leave_group_call(uuid) from public, anon;
revoke execute on function public.end_group_call(uuid) from public, anon;

grant execute on function public.start_group_call(uuid, text, uuid[]) to authenticated;
grant execute on function public.join_group_call(uuid) to authenticated;
grant execute on function public.decline_group_call(uuid) to authenticated;
grant execute on function public.leave_group_call(uuid) to authenticated;
grant execute on function public.end_group_call(uuid) to authenticated;
