-- Deploy to Supabase: Add 'expense' document type with 'GTO' prefix
-- Run this in Supabase SQL Editor

-- Update get_next_document_number function to include expense
create or replace function public.get_next_document_number(
  p_tenant_id uuid,
  p_document_type text,
  p_prefix text default null
) returns text
language plpgsql
security definer
as $$
declare
  v_next_number integer;
  v_prefix text;
  v_formatted_number text;
begin
  -- Default prefixes if not provided
  v_prefix := coalesce(p_prefix, case p_document_type
    when 'sales_invoice' then 'FV'
    when 'purchase_invoice' then 'FC'
    when 'sales_payment' then 'PV'
    when 'purchase_payment' then 'PC'
    when 'journal_entry' then 'AC'
    when 'mechanic_job' then 'PG'
    when 'stock_adjustment' then 'AJ'
    when 'expense' then 'GTO'
    else 'DOC'
  end);
  
  -- Insert or update sequence (atomic operation)
  insert into document_sequences (tenant_id, document_type, last_number)
  values (p_tenant_id, p_document_type, 1)
  on conflict (tenant_id, document_type)
  do update set
    last_number = document_sequences.last_number + 1,
    updated_at = now()
  returning last_number into v_next_number;
  
  -- Format: PREFIX-NNNNN (e.g., FV-00143)
  v_formatted_number := v_prefix || '-' || lpad(v_next_number::text, 5, '0');
  
  return v_formatted_number;
end;
$$;

grant execute on function public.get_next_document_number(uuid, text, text) to authenticated;

-- Update preview_next_document_number function to include expense
create or replace function public.preview_next_document_number(
  p_tenant_id uuid,
  p_document_type text,
  p_prefix text default null
) returns text
language plpgsql
security definer
as $$
declare
  v_current_number integer;
  v_next_number integer;
  v_prefix text;
  v_formatted_number text;
begin
  -- Default prefixes if not provided
  v_prefix := coalesce(p_prefix, case p_document_type
    when 'sales_invoice' then 'FV'
    when 'purchase_invoice' then 'FC'
    when 'sales_payment' then 'PV'
    when 'purchase_payment' then 'PC'
    when 'journal_entry' then 'AC'
    when 'mechanic_job' then 'PG'
    when 'stock_adjustment' then 'AJ'
    when 'expense' then 'GTO'
    else 'DOC'
  end);
  
  -- Get current sequence value (or 0 if none)
  select coalesce(last_number, 0) into v_current_number
  from document_sequences
  where tenant_id = p_tenant_id and document_type = p_document_type;
  
  -- Next number is current + 1 (or 1 if no sequence exists)
  v_next_number := coalesce(v_current_number, 0) + 1;
  
  -- Format: PREFIX-NNNNN (e.g., FV-00143)
  v_formatted_number := v_prefix || '-' || lpad(v_next_number::text, 5, '0');
  
  return v_formatted_number;
end;
$$;

grant execute on function public.preview_next_document_number(uuid, text, text) to authenticated;
