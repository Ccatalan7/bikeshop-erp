-- Fix RLS policies for user_invitations table
-- Allow authenticated users to create invitations (not just managers)

-- Drop old restrictive policy
drop policy if exists "managers_create_invitations" on user_invitations;

-- Create new policy: any authenticated user in tenant can create invitations
create policy "user_invitations_insert" on user_invitations
  for insert
  to authenticated
  with check (tenant_id = public.user_tenant_id());

-- Update SELECT policy to be consistent
drop policy if exists "managers_view_tenant_invitations" on user_invitations;

create policy "user_invitations_select" on user_invitations
  for select
  to authenticated
  using (tenant_id = public.user_tenant_id());

-- Add UPDATE policy for managing invitation status
create policy "user_invitations_update" on user_invitations
  for update
  to authenticated
  using (tenant_id = public.user_tenant_id());

-- Add DELETE policy for canceling invitations
create policy "user_invitations_delete" on user_invitations
  for delete
  to authenticated
  using (tenant_id = public.user_tenant_id());

-- Verify policies
select tablename, policyname, roles, cmd 
from pg_policies 
where tablename = 'user_invitations'
order by policyname;
