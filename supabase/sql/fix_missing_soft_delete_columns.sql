-- SQL FIX: Add missing soft-delete columns to payments tables
-- This resolves the "column deleted_at does not exist" error when saving invoices.

-- 1. Add columns to sales_payments
ALTER TABLE public.sales_payments ADD COLUMN IF NOT EXISTS deleted_at timestamp with time zone;
ALTER TABLE public.sales_payments ADD COLUMN IF NOT EXISTS deleted_by uuid REFERENCES auth.users(id) ON DELETE SET NULL;

-- 2. Add columns to purchase_payments
ALTER TABLE public.purchase_payments ADD COLUMN IF NOT EXISTS deleted_at timestamp with time zone;
ALTER TABLE public.purchase_payments ADD COLUMN IF NOT EXISTS deleted_by uuid REFERENCES auth.users(id) ON DELETE SET NULL;

-- 3. Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_sales_payments_deleted_at ON public.sales_payments(deleted_at) WHERE deleted_at IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_purchase_payments_deleted_at ON public.purchase_payments(deleted_at) WHERE deleted_at IS NOT NULL;

-- 4. Verify deployment
SELECT table_name, column_name, data_type 
FROM information_schema.columns 
WHERE table_name IN ('sales_payments', 'purchase_payments') 
  AND column_name IN ('deleted_at', 'deleted_by')
ORDER BY table_name, column_name;
