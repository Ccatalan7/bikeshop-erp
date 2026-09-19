-- Un movimiento de la cartola puede empezar al pie de una página y terminar
-- arriba de la siguiente: el lector del Banco de Chile los recompone («Se
-- recompusieron 1 movimientos divididos por un salto de página»). La fila
-- guardaba una sola página y exigía línea final >= inicial, así que el
-- aporte de $700.000 del 11-08 (página 2 línea 39 → página 3 línea 1) hacía
-- rechazar la cartola de agosto entera con bank_statement_row_invalid, y con
-- ella «Aplicar» y el borrador de la conciliación (2026-09-19).
--
-- La fila guarda ahora también la página donde termina. Líneas en páginas
-- distintas no se comparan; en la misma página, la final no precede a la
-- inicial.

alter table public.bank_statement_rows
  add column if not exists source_page_end integer;

do $$
begin
  if exists (
    select 1 from pg_constraint
     where conrelid = 'public.bank_statement_rows'::regclass
       and conname = 'bank_statement_rows_check'
  ) then
    alter table public.bank_statement_rows
      drop constraint bank_statement_rows_check;
  end if;
  if not exists (
    select 1 from pg_constraint
     where conrelid = 'public.bank_statement_rows'::regclass
       and conname = 'bank_statement_rows_source_span_check'
  ) then
    alter table public.bank_statement_rows
      add constraint bank_statement_rows_source_span_check check (
        (source_page_end is null or source_page_end >= source_page)
        and (
          coalesce(source_page_end, source_page) > source_page
          or source_line_end >= source_line_start
        )
      );
  end if;
end;
$$;

create or replace function public.save_bank_statement_import_v1(
  p_operation_key text,
  p_file_sha256 text,
  p_account_fingerprint text,
  p_erp_account_id uuid,
  p_source_metadata jsonb,
  p_rows jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_tenant_id uuid := public.user_tenant_id();
  v_user_id uuid := auth.uid();
  v_payload_hash text;
  v_existing record;
  v_import record;
  v_row jsonb;
  v_row_id uuid;
  v_rows_receipt jsonb := '[]'::jsonb;
  v_receipt jsonb;
begin
  if v_user_id is null or v_tenant_id is null
     or not public.can_manage_tenant_accounting(v_tenant_id) then
    raise exception using errcode = '42501', message = 'accounting_access_required';
  end if;
  if p_operation_key is null or length(trim(p_operation_key)) not between 1 and 200
     or p_file_sha256 !~ '^[0-9a-f]{64}$'
     or (p_account_fingerprint is not null and p_account_fingerprint !~ '^[0-9a-f]{64}$')
     or jsonb_typeof(coalesce(p_source_metadata, '{}'::jsonb)) <> 'object'
     or coalesce(jsonb_typeof(p_rows), 'null') <> 'array'
     or jsonb_array_length(p_rows) not between 1 and 5000 then
    raise exception using errcode = '22023', message = 'bank_statement_import_payload_invalid';
  end if;
  if not exists (
    select 1 from public.accounts account
     where account.tenant_id = v_tenant_id
       and account.id = p_erp_account_id
       and account.type = 'asset'
       and account.is_active
  ) then
    raise exception using errcode = '42501', message = 'bank_account_not_accessible';
  end if;

  v_payload_hash := encode(extensions.digest(convert_to(jsonb_build_object(
    'file_sha256', p_file_sha256,
    'account_fingerprint', p_account_fingerprint,
    'erp_account_id', p_erp_account_id,
    'source_metadata', coalesce(p_source_metadata, '{}'::jsonb),
    'rows', p_rows
  )::text, 'utf8'), 'sha256'), 'hex');

  perform pg_advisory_xact_lock(hashtextextended(
    v_tenant_id::text || ':bank-reconciliation', 0
  ));
  select operation.action, operation.payload_hash, operation.receipt
    into v_existing
    from public.bank_reconciliation_operations operation
   where operation.tenant_id = v_tenant_id
     and operation.operation_key = trim(p_operation_key);
  if found then
    if v_existing.action <> 'create_import'
       or v_existing.payload_hash <> v_payload_hash then
      raise exception using errcode = 'P0001', message = 'bank_reconciliation_idempotency_conflict';
    end if;
    return v_existing.receipt || jsonb_build_object('replayed', true);
  end if;

  insert into public.bank_statement_imports (
    tenant_id, erp_account_id, file_sha256, account_fingerprint,
    source_metadata, created_by
  ) values (
    v_tenant_id, p_erp_account_id, p_file_sha256, p_account_fingerprint,
    coalesce(p_source_metadata, '{}'::jsonb), v_user_id
  )
  on conflict (tenant_id, erp_account_id, file_sha256) do update
    set source_metadata = public.bank_statement_imports.source_metadata
  returning id, revision, status into v_import;

  if not exists (
    select 1 from public.bank_statement_rows row
     where row.import_id = v_import.id
  ) then
    for v_row in select value from jsonb_array_elements(p_rows)
    loop
      if jsonb_typeof(v_row) <> 'object'
         or coalesce(v_row->>'source_row_id', '') = ''
         or coalesce(v_row->>'description', '') = ''
         or coalesce(v_row->>'normalized_description', '') = ''
         or coalesce(v_row->>'fingerprint', '') !~ '^[0-9a-f]{64}$'
         or coalesce(v_row->>'direction', '') not in ('debit', 'credit', 'unknown')
         or coalesce((v_row->>'ordinal')::integer, 0) not between 1 and 5000
         or coalesce((v_row->>'source_page')::integer, 0) <= 0
         or coalesce((v_row->>'source_line_start')::integer, 0) <= 0
         or coalesce((v_row->>'source_line_end')::integer, 0) <= 0
         or coalesce(nullif(v_row->>'source_page_end', '')::integer,
                     (v_row->>'source_page')::integer)
              < (v_row->>'source_page')::integer
         or (coalesce(nullif(v_row->>'source_page_end', '')::integer,
                      (v_row->>'source_page')::integer)
               = (v_row->>'source_page')::integer
             and (v_row->>'source_line_end')::integer
               < (v_row->>'source_line_start')::integer) then
        raise exception using errcode = '22023', message = 'bank_statement_row_invalid';
      end if;
      insert into public.bank_statement_rows (
        tenant_id, import_id, source_row_id, ordinal, booking_date,
        operation_date, direction, amount, description,
        normalized_description, counterparty_observed, document_number,
        balance, warning_codes, source_page, source_page_end,
        source_line_start, source_line_end, fingerprint
      ) values (
        v_tenant_id,
        v_import.id,
        v_row->>'source_row_id',
        (v_row->>'ordinal')::integer,
        nullif(v_row->>'booking_date', '')::date,
        nullif(v_row->>'operation_date', '')::date,
        v_row->>'direction',
        nullif(v_row->>'amount', '')::numeric,
        v_row->>'description',
        v_row->>'normalized_description',
        nullif(v_row->>'counterparty_observed', ''),
        nullif(v_row->>'document_number', ''),
        nullif(v_row->>'balance', '')::numeric,
        coalesce(array(
          select jsonb_array_elements_text(coalesce(v_row->'warning_codes', '[]'::jsonb))
        ), '{}'::text[]),
        (v_row->>'source_page')::integer,
        nullif(nullif(v_row->>'source_page_end', '')::integer,
               (v_row->>'source_page')::integer),
        (v_row->>'source_line_start')::integer,
        (v_row->>'source_line_end')::integer,
        v_row->>'fingerprint'
      ) returning id into v_row_id;
      v_rows_receipt := v_rows_receipt || jsonb_build_array(jsonb_build_object(
        'source_row_id', v_row->>'source_row_id', 'row_id', v_row_id
      ));
    end loop;
  else
    select coalesce(jsonb_agg(jsonb_build_object(
      'source_row_id', row.source_row_id, 'row_id', row.id
    ) order by row.ordinal), '[]'::jsonb)
      into v_rows_receipt
      from public.bank_statement_rows row
     where row.import_id = v_import.id;
    if jsonb_array_length(v_rows_receipt) <> jsonb_array_length(p_rows)
       or exists (
         select 1
         from jsonb_array_elements(p_rows) payload(row_payload)
         where not exists (
           select 1
           from public.bank_statement_rows stored
           where stored.import_id = v_import.id
             and stored.source_row_id = payload.row_payload->>'source_row_id'
             and stored.ordinal = (payload.row_payload->>'ordinal')::integer
             and stored.fingerprint = payload.row_payload->>'fingerprint'
         )
       ) then
      raise exception using errcode = '55000', message = 'bank_statement_import_shape_conflict';
    end if;
  end if;

  v_receipt := jsonb_build_object(
    'operation', 'create_import',
    'operation_key', trim(p_operation_key),
    'payload_hash', v_payload_hash,
    'replayed', false,
    'import_id', v_import.id,
    'revision', v_import.revision,
    'status', v_import.status,
    'rows', v_rows_receipt
  );
  insert into public.bank_reconciliation_operations (
    tenant_id, import_id, operation_key, action, payload_hash, receipt, created_by
  ) values (
    v_tenant_id, v_import.id, trim(p_operation_key), 'create_import',
    v_payload_hash, v_receipt, v_user_id
  );
  return v_receipt;
end;
$$;

revoke all on function public.save_bank_statement_import_v1(
  text, text, text, uuid, jsonb, jsonb
) from public, anon;
grant execute on function public.save_bank_statement_import_v1(
  text, text, text, uuid, jsonb, jsonb
) to authenticated, service_role;
