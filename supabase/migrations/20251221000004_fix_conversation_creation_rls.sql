-- Fix RLS Insert Blocking Conversation Creation
-- Problem: 'INSERT ... RETURNING' fails because the user is not yet a participant (SELECT policy blocks viewing the new row).
-- Solution: Add 'created_by' column and allow creators to see their own conversations.

-- 1. Add created_by column
alter table public.conversations 
add column if not exists created_by uuid references auth.users(id) default auth.uid();

-- 2. Update SELECT policy for conversations to include created_by
drop policy if exists "Users can view conversations they participate in" on public.conversations;

create policy "Users can view conversations they participate in"
  on public.conversations for select
  using (
    -- Use the optimized function from previous fix
    public.is_conversation_participant(id)
    OR
    created_by = auth.uid() -- Allow creator to see it (crucial for INSERT ... RETURNING)
    OR
    ( -- Employees can view support tickets even if not explicitly a participant yet
      type = 'support' AND 
      exists (select 1 from public.user_profiles where user_id = auth.uid() and role in ('admin', 'manager', 'cashier', 'mechanic', 'accountant'))
    )
  );

-- 3. Ensure INSERT policy explicitly allows setting created_by (optional but safe)
drop policy if exists "Users can create conversations" on public.conversations;

create policy "Users can create conversations"
  on public.conversations for insert
  with check (
    tenant_id = public.user_tenant_id()
    -- created_by is handled by default auth.uid()
  );
