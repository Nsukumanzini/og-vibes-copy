drop policy if exists "Users create own typing status"
  on public.chat_typing_status;
create policy "Users create own typing status"
  on public.chat_typing_status
  for insert
  to authenticated
  with check (
    user_id = (select auth.uid())
    and (
      is_typing = false
      or (select private.can_direct_message(peer_id))
    )
  );

drop policy if exists "Users update own typing status"
  on public.chat_typing_status;
create policy "Users update own typing status"
  on public.chat_typing_status
  for update
  to authenticated
  using (user_id = (select auth.uid()))
  with check (
    user_id = (select auth.uid())
    and (
      is_typing = false
      or (select private.can_direct_message(peer_id))
    )
  );

drop policy if exists "Chat participants add own reactions"
  on public.message_reactions;
create policy "Chat participants add own reactions"
  on public.message_reactions
  for insert
  to authenticated
  with check (
    user_id = (select auth.uid())
    and exists (
      select 1 from public.messages message
      where message.id = message_id
        and (
          message.sender_id = (select auth.uid())
          or message.recipient_id = (select auth.uid())
        )
        and (
          select private.can_direct_message(
            case
              when message.sender_id = (select auth.uid())
                then message.recipient_id
              else message.sender_id
            end
          )
        )
    )
  );
