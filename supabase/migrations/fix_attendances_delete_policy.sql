-- Add missing DELETE policy for attendances table
-- This allows users to delete attendance records from their own tenant

create policy "attendances_delete" on attendances 
  for delete 
  using (tenant_id = public.user_tenant_id());
