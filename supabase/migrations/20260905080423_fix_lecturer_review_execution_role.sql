-- admin-control already authenticates the administrator and invokes this RPC
-- with service_role. Preserve that identity for the profile role-change guard.
-- Ordinary clients must never invoke this RPC with a supplied reviewer ID.
alter function public.admin_review_lecturer_application(uuid, text, text, uuid)
  security invoker;
revoke all on function public.admin_review_lecturer_application(uuid, text, text, uuid)
  from public, anon, authenticated;
grant execute on function public.admin_review_lecturer_application(uuid, text, text, uuid)
  to service_role;
