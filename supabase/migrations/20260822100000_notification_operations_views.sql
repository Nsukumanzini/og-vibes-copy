create or replace view public.push_registration_status
with (security_invoker = true)
as
select
  profile.id as user_id,
  profile.nickname,
  profile.email,
  profile.campus,
  profile.role,
  count(token.id)::integer as device_count,
  coalesce(array_agg(distinct token.platform) filter (where token.platform is not null), '{}') as platforms,
  max(token.last_seen_at) as last_seen_at,
  case when count(token.id) > 0 then 'ready' else 'not_registered' end as push_status
from public.profiles profile
left join public.device_push_tokens token on token.user_id = profile.id
where profile.role in ('student', 'lecturer')
group by profile.id, profile.nickname, profile.email, profile.campus, profile.role;

revoke all on public.push_registration_status from public, anon, authenticated;
grant select on public.push_registration_status to service_role;

create or replace view public.notification_delivery_health
with (security_invoker = true)
as
select
  date_trunc('day', created_at) as delivery_day,
  category,
  delivery_status,
  count(*)::integer as total
from public.student_notifications
group by date_trunc('day', created_at), category, delivery_status;

revoke all on public.notification_delivery_health from public, anon, authenticated;
grant select on public.notification_delivery_health to service_role;

comment on view public.push_registration_status is
  'Admin-only notification enrollment coverage without exposing FCM tokens.';
comment on view public.notification_delivery_health is
  'Admin-only daily push delivery outcomes by category.';
