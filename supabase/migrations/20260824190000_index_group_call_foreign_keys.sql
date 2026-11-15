-- Cover group-call foreign keys used by participant, cleanup, and moderation queries.
create index if not exists group_calls_started_by_idx
  on public.group_calls(started_by);

create index if not exists group_call_signals_sender_idx
  on public.group_call_signals(sender_id, call_id);

create index if not exists group_call_signals_recipient_call_idx
  on public.group_call_signals(recipient_id, call_id, id);
