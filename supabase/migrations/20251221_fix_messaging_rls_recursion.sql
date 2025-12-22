-- Fix RLS Infinite Recursion in Messaging System
-- The previous policy for conversation_participants queried the table itself, causing infinite recursion.
-- Solution: Use a SECURITY DEFINER function to check participation without triggering RLS.

-- 1. Create helper function to check participation (bypasses RLS)
create or replace function public.is_conversation_participant(p_conversation_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  return exists (
    select 1 from public.conversation_participants
    where conversation_id = p_conversation_id
    and user_id = auth.uid()
  );
end;
$$;

-- 2. Drop the problematic recursive policy
drop policy if exists "Users can view participants of their conversations" on public.conversation_participants;

-- 3. Re-create the policy using the helper function
create policy "Users can view participants of their conversations"
  on public.conversation_participants for select
  using (
    public.is_conversation_participant(conversation_participants.conversation_id)
    OR
    ( -- Employees can view participants of any support ticket
       exists (select 1 from public.conversations c where c.id = conversation_participants.conversation_id and c.type = 'support') AND
       exists (select 1 from public.user_profiles where user_id = auth.uid() and role in ('admin', 'manager', 'cashier', 'mechanic', 'accountant'))
    )
  );

-- 4. Optimizing 'Conversations' policy to also use the helper function for consistency (optional but good for performance)
drop policy if exists "Users can view conversations they participate in" on public.conversations;

create policy "Users can view conversations they participate in"
  on public.conversations for select
  using (
    public.is_conversation_participant(id)
    OR
    ( -- Employees can view support tickets even if not explicitly a participant yet
      type = 'support' AND 
      exists (select 1 from public.user_profiles where user_id = auth.uid() and role in ('admin', 'manager', 'cashier', 'mechanic', 'accountant'))
    )
  );

-- 5. Optimizing 'Messages' policy to use the helper function
drop policy if exists "Users can view messages in their conversations" on public.messages;

create policy "Users can view messages in their conversations"
  on public.messages for select
  using (
    public.is_conversation_participant(conversation_id)
    OR
    ( -- Employees can view messages of any support ticket
       exists (select 1 from public.conversations c where c.id = messages.conversation_id and c.type = 'support') AND
       exists (select 1 from public.user_profiles where user_id = auth.uid() and role in ('admin', 'manager', 'cashier', 'mechanic', 'accountant'))
    )
  );
