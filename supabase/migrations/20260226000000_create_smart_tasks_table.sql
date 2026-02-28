-- migration: 20260226000000_create_smart_tasks_table.sql
-- description: Creates the smart_tasks table for the Smart To-Do module with polymorphic relations and RLS.

CREATE TABLE public.smart_tasks (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    description TEXT,
    
    status TEXT NOT NULL DEFAULT 'pending', 
    -- 'pending', 'in_progress', 'completed', 'cancelled'
    
    priority TEXT NOT NULL DEFAULT 'normal', 
    -- 'low', 'normal', 'high', 'urgent'
    
    due_date TIMESTAMPTZ,
    
    assigned_to UUID REFERENCES auth.users(id) ON DELETE SET NULL, 
    -- Optional: specific staff member to assign the task to
    
    created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    -- Who created the task
    
    -- Entity Links (Polymorphic relations)
    linked_job_id UUID REFERENCES public.mechanic_jobs(id) ON DELETE SET NULL,
    linked_purchase_invoice_id UUID REFERENCES public.purchase_invoices(id) ON DELETE SET NULL,
    linked_sales_invoice_id UUID REFERENCES public.sales_invoices(id) ON DELETE SET NULL,
    linked_customer_id UUID REFERENCES public.customers(id) ON DELETE SET NULL,
    linked_supplier_id UUID REFERENCES public.suppliers(id) ON DELETE SET NULL,
    
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- Indexes for fast querying, especially when filtering by linked entities
CREATE INDEX idx_smart_tasks_tenant_id ON public.smart_tasks(tenant_id);
CREATE INDEX idx_smart_tasks_status ON public.smart_tasks(status);
CREATE INDEX idx_smart_tasks_assigned_to ON public.smart_tasks(assigned_to);
CREATE INDEX idx_smart_tasks_linked_job_id ON public.smart_tasks(linked_job_id);

-- Enable RLS
ALTER TABLE public.smart_tasks ENABLE ROW LEVEL SECURITY;

-- RLS Policies
CREATE POLICY "Users can view tasks in their tenant"
    ON public.smart_tasks FOR SELECT
    USING (
        tenant_id IN (
            SELECT target_tenant_id 
            FROM user_tenant_access()
        )
    );

CREATE POLICY "Users can insert tasks in their tenant"
    ON public.smart_tasks FOR INSERT
    WITH CHECK (
        tenant_id IN (
            SELECT target_tenant_id 
            FROM user_tenant_access()
        )
    );

CREATE POLICY "Users can update tasks in their tenant"
    ON public.smart_tasks FOR UPDATE
    USING (
        tenant_id IN (
            SELECT target_tenant_id 
            FROM user_tenant_access()
        )
    )
    WITH CHECK (
        tenant_id IN (
            SELECT target_tenant_id 
            FROM user_tenant_access()
        )
    );

CREATE POLICY "Users can delete tasks in their tenant"
    ON public.smart_tasks FOR DELETE
    USING (
        tenant_id IN (
            SELECT target_tenant_id 
            FROM user_tenant_access()
        )
    );

-- Trigger for updated_at
CREATE TRIGGER handle_updated_at_smart_tasks
    BEFORE UPDATE ON public.smart_tasks
    FOR EACH ROW
    EXECUTE PROCEDURE moddatetime (updated_at);
