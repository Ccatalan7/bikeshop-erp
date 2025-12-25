-- Secure RPC to handle action request responses (bypassing RLS for specific updates)
create or replace function public.respond_to_action_request(
  p_message_id uuid,
  p_action_type text,
  p_status text,
  p_metadata_updates jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer -- Runs with elevated privileges
as $$
declare
  v_message_exists boolean;
  v_current_metadata jsonb;
  v_new_metadata jsonb;
begin
  -- 1. Verify existence
  select exists(select 1 from public.messages where id = p_message_id)
  into v_message_exists;

  if not v_message_exists then
    raise exception 'StartChat: Message not found';
  end if;

  -- 2. Get current metadata
  select metadata into v_current_metadata
  from public.messages
  where id = p_message_id;

  -- 3. Merge updates
  -- We update status, responded_at, and any other fields provided
  v_new_metadata := v_current_metadata || 
                    jsonb_build_object(
                      'status', p_status,
                      'responded_at', now()
                    ) || p_metadata_updates;

  -- 4. Update the message
  update public.messages
  set metadata = v_new_metadata
  where id = p_message_id;

end;
$$;
