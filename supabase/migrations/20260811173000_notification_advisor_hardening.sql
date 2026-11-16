drop policy if exists "Webhook config is service managed"
  on public.notification_webhook_config;
create policy "Webhook config is service managed"
on public.notification_webhook_config
for all
to service_role
using (true)
with check (true);

create index if not exists student_notifications_actor_id_idx
  on public.student_notifications (actor_id)
  where actor_id is not null;
