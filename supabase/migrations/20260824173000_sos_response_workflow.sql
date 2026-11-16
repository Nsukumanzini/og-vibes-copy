-- Align the admin response workflow with the SOS incident state machine.

alter table public.sos_incidents
  drop constraint if exists sos_incidents_status_check;
alter table public.sos_incidents
  add constraint sos_incidents_status_check
  check (status in ('active', 'acknowledged', 'responding', 'resolved', 'cancelled'));

create or replace function private.set_sos_incident_timestamps()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  if new.status in ('resolved', 'cancelled') and new.resolved_at is null then
    new.resolved_at := now();
  elsif new.status not in ('resolved', 'cancelled') then
    new.resolved_at := null;
  end if;
  return new;
end;
$$;

drop trigger if exists set_sos_incident_timestamps on public.sos_incidents;
create trigger set_sos_incident_timestamps
before update on public.sos_incidents
for each row execute function private.set_sos_incident_timestamps();

revoke all on function private.set_sos_incident_timestamps() from public;
revoke all on function private.set_sos_incident_timestamps() from anon;
revoke all on function private.set_sos_incident_timestamps() from authenticated;
