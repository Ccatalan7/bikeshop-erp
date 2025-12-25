-- RPC to allow customers (or employees) to confirm an invoice
CREATE OR REPLACE FUNCTION public.confirm_invoice_approval(p_invoice_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_customer_id uuid;
BEGIN
  -- Get invoice customer
  SELECT customer_id INTO v_customer_id
  FROM public.sales_invoices
  WHERE id = p_invoice_id;

  -- Check permissions (must be the customer or an admin/employee)
  -- Employees are checked via user_profiles usually, but here we focus on Customer approval
  IF v_customer_id != auth.uid() THEN
     -- Check if employee
     IF NOT EXISTS (SELECT 1 FROM public.user_profiles WHERE user_id = auth.uid()) THEN
        RAISE EXCEPTION 'Not authorized to approve this invoice';
     END IF;
  END IF;

  -- Update status
  UPDATE public.sales_invoices
  SET status = 'confirmed'
  WHERE id = p_invoice_id;
END;
$$;
