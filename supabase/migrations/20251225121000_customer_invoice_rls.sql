-- Enable RLS on sales_invoices if not already enabled
ALTER TABLE public.sales_invoices ENABLE ROW LEVEL SECURITY;

-- 1. Sales Invoices: Customers can view their own invoices
-- This INCLUDES the 'items' column which is JSONB inside this table
CREATE POLICY "Customers can view their own invoices"
ON public.sales_invoices
FOR SELECT
TO authenticated
USING (
  customer_id = auth.uid()
);

-- 2. Sales Invoices: Employees can view all (assuming user_profiles check)
CREATE POLICY "Employees can view all invoices"
ON public.sales_invoices
FOR SELECT
TO authenticated
USING (
  EXISTS (SELECT 1 FROM public.user_profiles WHERE user_id = auth.uid())
);
