-- ============================================================================
-- Fix: Payment Deletion Should Preserve "Confirmed" Status
-- ============================================================================
-- Problem: When deleting a payment from a "paid" invoice, the status goes to
--          "sent" instead of "confirmed", losing the accounting/inventory link
--
-- Solution: If invoice was previously confirmed/paid, keep it as confirmed
--           when balance > 0 after payment deletion
-- ============================================================================

CREATE OR REPLACE FUNCTION public.recalculate_sales_invoice_payments(p_invoice_id uuid)
RETURNS VOID AS $$
DECLARE
  v_invoice RECORD;
  v_total NUMERIC(12,2);
  v_new_status TEXT;
  v_balance NUMERIC(12,2);
BEGIN
  IF p_invoice_id IS NULL THEN
    RETURN;
  END IF;

  SELECT id,
         total,
         status
    INTO v_invoice
    FROM public.sales_invoices
   WHERE id = p_invoice_id
   FOR UPDATE;

  IF NOT FOUND THEN
    RETURN;
  END IF;

  SELECT COALESCE(SUM(amount), 0)
    INTO v_total
    FROM public.sales_payments
   WHERE invoice_id = p_invoice_id;

  v_balance := GREATEST(COALESCE(v_invoice.total, 0) - v_total, 0);

  -- Determine new status based on current status and payment amount
  IF v_invoice.status = 'cancelled' THEN
    v_new_status := v_invoice.status;
  ELSIF v_invoice.status = 'draft' AND v_total = 0 THEN
    v_new_status := 'draft';
  ELSIF v_total >= COALESCE(v_invoice.total, 0) THEN
    -- Fully paid
    v_new_status := 'paid';
  ELSIF v_balance > 0 AND (v_invoice.status = 'confirmed' OR v_invoice.status = 'paid') THEN
    -- ⭐ FIX: If invoice was confirmed/paid and now has balance, keep it as confirmed
    --         This preserves the accounting entry and inventory deduction
    v_new_status := 'confirmed';
  ELSIF v_invoice.status = 'overdue' AND v_balance > 0 THEN
    v_new_status := 'overdue';
  ELSIF v_total > 0 THEN
    -- Has partial payment but was never confirmed
    v_new_status := 'sent';
  ELSE
    v_new_status := v_invoice.status;
  END IF;

  UPDATE public.sales_invoices
     SET paid_amount = v_total,
         balance = v_balance,
         status = v_new_status,
         updated_at = NOW()
   WHERE id = p_invoice_id;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- What Changed:
-- ============================================================================
-- Added condition on line 52-55:
--   ELSIF v_balance > 0 AND (v_invoice.status = 'confirmed' OR v_invoice.status = 'paid')
--
-- This ensures that:
-- 1. If invoice is "paid" and we delete payment → status becomes "confirmed" (not "sent")
-- 2. If invoice is "confirmed" with partial payment, it stays "confirmed"
-- 3. Accounting entry and inventory deduction are preserved
-- 4. Invoice can be paid again or payment can be undone multiple times
-- ============================================================================
