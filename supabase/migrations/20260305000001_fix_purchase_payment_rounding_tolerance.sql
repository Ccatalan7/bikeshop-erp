-- Fix: Add rounding tolerance to recalculate_purchase_invoice_payments
-- Problem: Payments registered as round numbers (e.g. 61612) on totals with cents (e.g. 61612.25)
-- leave tiny balances (0.25) that prevent the invoice from being marked as paid.
-- Solution: Treat remaining balances under $1 as fully paid (standard accounting rounding tolerance).

CREATE OR REPLACE FUNCTION public.recalculate_purchase_invoice_payments(p_invoice_id uuid)
RETURNS void AS $$
DECLARE
  v_invoice record;
  v_total numeric(12,2);
  v_new_status text;
  v_balance numeric(12,2);
BEGIN
  IF p_invoice_id IS NULL THEN
    RETURN;
  END IF;

  SELECT id, total, status, prepayment_model
    INTO v_invoice
    FROM public.purchase_invoices
   WHERE id = p_invoice_id
   FOR UPDATE;

  IF NOT FOUND THEN
    RETURN;
  END IF;

  SELECT coalesce(sum(amount), 0)
    INTO v_total
    FROM public.purchase_payments
   WHERE invoice_id = p_invoice_id;

  v_balance := greatest(coalesce(v_invoice.total, 0) - v_total, 0);

  -- Status transition logic based on prepayment model
  -- Standard model: Draft→Sent→Confirmed→Received→Paid
  -- Prepayment model: Draft→Sent→Confirmed→Paid→Received
  
  IF v_invoice.status = 'cancelled' THEN
    v_new_status := 'cancelled';
    
  ELSIF v_invoice.status IN ('draft', 'sent') THEN
    v_new_status := v_invoice.status;
    
  -- Rounding tolerance: treat balance < $1 as fully paid
  ELSIF v_total >= coalesce(v_invoice.total, 0) OR v_balance < 1.0 THEN
    -- Only mark as paid if there's actually some payment
    IF v_total > 0 THEN
      v_new_status := 'paid';
    ELSE
      v_new_status := v_invoice.status;
    END IF;
    
  ELSIF v_total > 0 THEN
    IF v_invoice.prepayment_model THEN
      IF v_invoice.status IN ('paid', 'received') THEN
        v_new_status := 'paid';
      ELSE
        v_new_status := 'confirmed';
      END IF;
    ELSE
      IF v_invoice.status IN ('received', 'paid') THEN
        v_new_status := 'received';
      ELSE
        v_new_status := 'confirmed';
      END IF;
    END IF;
    
  ELSE
    IF v_invoice.prepayment_model THEN
      IF v_invoice.status IN ('paid', 'received') THEN
        v_new_status := 'confirmed';
      ELSE
        v_new_status := v_invoice.status;
      END IF;
    ELSE
      IF v_invoice.status = 'paid' THEN
        v_new_status := 'received';
      ELSE
        v_new_status := v_invoice.status;
      END IF;
    END IF;
  END IF;

  -- When balance is less than $1, set it to 0 and paid_amount to total
  IF v_balance < 1.0 AND v_total > 0 THEN
    UPDATE public.purchase_invoices
       SET paid_amount = total,
           balance = 0,
           status = v_new_status,
           updated_at = now()
     WHERE id = p_invoice_id;
  ELSE
    UPDATE public.purchase_invoices
       SET paid_amount = v_total,
           balance = v_balance,
           status = v_new_status,
           updated_at = now()
     WHERE id = p_invoice_id;
  END IF;
END;
$$ LANGUAGE plpgsql;

-- Fix existing invoices with tiny balances: recalculate them all
DO $$
DECLARE
  inv_id uuid;
BEGIN
  FOR inv_id IN 
    SELECT id FROM public.purchase_invoices 
    WHERE balance > 0 AND balance < 1.0 AND paid_amount > 0
  LOOP
    PERFORM public.recalculate_purchase_invoice_payments(inv_id);
    RAISE NOTICE 'Recalculated invoice %', inv_id;
  END LOOP;
END $$;
