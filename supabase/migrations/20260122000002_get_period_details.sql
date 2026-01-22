-- Drop the function first because we are changing the return table structure
DROP FUNCTION IF EXISTS public.get_expense_period_details(timestamp with time zone, timestamp with time zone, boolean);

-- Recreate the function with new columns
CREATE OR REPLACE FUNCTION public.get_expense_period_details(
  p_start_date timestamp with time zone,
  p_end_date timestamp with time zone,
  p_is_cash_flow boolean
)
RETURNS TABLE (
  id uuid,
  document_number text,
  description text,
  account_name text,
  amount numeric,
  transaction_date date,
  source_type text,
  account_id uuid,
  account_code text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_is_cash_flow THEN
    -- Cash Flow: Return payments + paid expenses
    RETURN QUERY
    -- 1. Purchase Payments (Payments to suppliers)
    -- These are generally against Accounts Payable, so specific expense account is unknown/mixed.
    -- We leave account_id/code as NULL or default.
    SELECT
      pp.id,
      pi.invoice_number AS document_number,
      COALESCE(s.name, 'Proveedor') AS description,
      'Pago a Proveedor'::text AS account_name,
      pp.amount::numeric(14,2),
      pp.date::date AS transaction_date,
      'purchase_payment'::text AS source_type,
      NULL::uuid AS account_id,
      NULL::text AS account_code
    FROM purchase_payments pp
    LEFT JOIN purchase_invoices pi ON pi.id = pp.invoice_id
    LEFT JOIN suppliers s ON s.id = pi.supplier_id
    WHERE pp.date >= p_start_date
      AND pp.date < p_end_date
      AND pp.tenant_id = user_tenant_id()
    
    UNION ALL
    
    -- 2. Paid operating expenses (salaries, rent, utilities, etc.)
    SELECT
      e.id,
      e.expense_number AS document_number,
      COALESCE(e.supplier_name, 'Gasto') AS description,
      a.name AS account_name,
      el.total::numeric(14,2) AS amount,
      e.paid_at::date AS transaction_date,
      'expense'::text AS source_type,
      a.id AS account_id,
      a.code AS account_code
    FROM expenses e
    JOIN expense_lines el ON el.expense_id = e.id
    JOIN accounts a ON a.id = el.account_id
    WHERE e.payment_status = 'paid'
      AND e.paid_at >= p_start_date
      AND e.paid_at < p_end_date
      AND e.tenant_id = user_tenant_id()
      AND a.type = 'expense'
    
    ORDER BY transaction_date DESC, amount DESC;
    
  ELSE
    -- Accrual: Return expense journal entries (This feeds the Pie Chart usually)
    RETURN QUERY
    SELECT
      je.id,
      COALESCE(je.reference, '') AS document_number,
      je.description,
      a.name AS account_name,
      (COALESCE(SUM(jl.debit_amount), 0) - COALESCE(SUM(jl.credit_amount), 0))::numeric(14,2) AS amount,
      je.entry_date::date AS transaction_date,
      'journal_entry'::text AS source_type,
      a.id AS account_id,
      a.code AS account_code
    FROM journal_lines jl
    JOIN journal_entries je ON je.id = jl.entry_id
    JOIN accounts a ON a.id = jl.account_id
    WHERE je.status = 'posted'
      AND a.type = 'expense'
      AND je.entry_date >= p_start_date
      AND je.entry_date < p_end_date
      AND je.tenant_id = user_tenant_id()
      AND jl.tenant_id = user_tenant_id()
      AND a.tenant_id = user_tenant_id()
    GROUP BY je.id, je.reference, je.description, a.name, je.entry_date, a.id, a.code
    HAVING (COALESCE(SUM(jl.debit_amount), 0) - COALESCE(SUM(jl.credit_amount), 0)) <> 0
    ORDER BY je.entry_date DESC, amount DESC;
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_expense_period_details(timestamp with time zone, timestamp with time zone, boolean) TO authenticated;
