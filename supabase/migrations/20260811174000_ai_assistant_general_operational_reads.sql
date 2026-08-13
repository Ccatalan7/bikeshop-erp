-- General model-first ERP reads for operational risk, accounting posture and
-- authorized conversations. Every RPC derives the caller and tenant, exposes
-- a closed projection, and leaves prioritization/explanation to the model.

begin;

create or replace function public.assistant_capabilities_internal_v2(
  p_profile_role text,
  p_authority_role text,
  p_permissions jsonb
)
returns jsonb
language plpgsql
immutable
set search_path = pg_catalog, pg_temp
as $$
declare
  v_permissions jsonb := coalesce(p_permissions, '{}'::jsonb);
  v_capabilities text[] := array['ai.read.operational']::text[];
begin
  if p_authority_role in ('owner', 'admin', 'manager', 'cashier', 'accountant')
     or v_permissions @> '{"create_invoices":true}'::jsonb
     or v_permissions @> '{"access_accounting":true}'::jsonb then
    v_capabilities := array_append(v_capabilities, 'ai.read.sales');
  end if;
  if p_authority_role in ('owner', 'admin', 'manager', 'accountant')
     or v_permissions @> '{"access_accounting":true}'::jsonb then
    v_capabilities := array_append(v_capabilities, 'ai.read.purchases');
  end if;
  -- Deliberately use the persisted profile role, not the presentation-only
  -- owner label. Ownership alone must not widen accounting authority.
  if p_profile_role in ('admin', 'manager', 'accountant')
     or v_permissions @> '{"access_accounting":true}'::jsonb then
    v_capabilities := array_append(v_capabilities, 'ai.read.accounting');
  end if;
  return to_jsonb(v_capabilities);
end;
$$;

-- Authority replacements come before every capability-gated read below.
revoke all on function public.assistant_capabilities_internal_v2(
  text, text, jsonb
) from public, anon, authenticated, service_role;

create or replace function public.assistant_current_authority_internal_v1()
returns table (
  tenant_id uuid,
  actor_user_id uuid,
  authority_role text,
  permissions jsonb,
  capabilities jsonb,
  authority_fingerprint text
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public, auth, extensions, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_tenant_id uuid;
  v_count integer;
  v_profile record;
  v_owner boolean;
begin
  if v_user_id is null or coalesce(auth.role(), '') <> 'authenticated' then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  select count(*), min(profile.tenant_id::text)::uuid
  into v_count, v_tenant_id
  from public.user_profiles profile
  join public.tenants tenant
    on tenant.id = profile.tenant_id and tenant.is_active is true
  where profile.user_id = v_user_id and profile.is_active is true;
  if v_count <> 1 or v_tenant_id is null then
    raise exception 'A single active tenant is required' using errcode = '42501';
  end if;
  select profile.role as role,
         coalesce(profile.permissions, '{}'::jsonb) as permissions,
         tenant.owner_email as owner_email,
         auth_user.email as email,
         auth_user.raw_app_meta_data as raw_app_meta_data
  into strict v_profile
  from public.user_profiles profile
  join public.tenants tenant on tenant.id = profile.tenant_id
  join auth.users auth_user on auth_user.id = profile.user_id
  where profile.user_id = v_user_id
    and profile.tenant_id = v_tenant_id
    and profile.is_active is true
    and tenant.is_active is true;
  if v_profile.role not in (
    'admin', 'manager', 'cashier', 'mechanic', 'accountant'
  ) then
    raise exception 'Account access is invalid' using errcode = '42501';
  end if;
  v_owner := (
    nullif(lower(btrim(v_profile.email)), '') is not null
    and lower(btrim(v_profile.email)) = lower(btrim(v_profile.owner_email))
  ) or (
    v_profile.raw_app_meta_data ->> 'account_type' = 'erp_owner'
    and v_profile.raw_app_meta_data ->> 'tenant_id' = v_tenant_id::text
  );
  tenant_id := v_tenant_id;
  actor_user_id := v_user_id;
  authority_role := case when v_owner then 'owner' else v_profile.role end;
  permissions := v_profile.permissions;
  capabilities := public.assistant_capabilities_internal_v2(
    v_profile.role, authority_role, permissions
  );
  authority_fingerprint := encode(extensions.digest(
    convert_to(jsonb_build_object(
      'tenantId', tenant_id, 'actorUserId', actor_user_id,
      'role', authority_role, 'permissions', permissions,
      'capabilities', capabilities
    )::text, 'UTF8'), 'sha256'), 'hex');
  return next;
end;
$$;

revoke all on function public.assistant_current_authority_internal_v1()
from public, anon, authenticated, service_role;

-- The caller-bound server-authority function is owned by the runtime ledger
-- migration. Do not replace it here: the v2 HMAC wrappers execute under the
-- original authenticated caller and compare against current authority.

create or replace function public.assistant_analyze_cash_and_receivables_v1(
  p_horizon text,
  p_limit integer
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, pg_temp
set statement_timeout = '4500ms'
as $$
declare
  v_authority record;
  v_business_date date;
  v_end_date date;
  v_cash_source_status text;
  v_book_liquid_funds_balance numeric;
  v_cash_account_count integer;
  v_receivables_source_status text;
  v_receivables_total numeric;
  v_overdue_receivables numeric;
  v_due_in_horizon_receivables numeric;
  v_no_due_date_receivables numeric;
  v_open_invoice_count integer;
  v_overdue_invoice_count integer;
  v_receivable_items jsonb := '[]'::jsonb;
  v_items jsonb;
  v_has_more boolean := false;
begin
  select authority.tenant_id, authority.actor_user_id,
    authority.authority_role, authority.permissions, authority.capabilities,
    authority.authority_fingerprint
  into strict v_authority
  from public.assistant_require_capability_internal_v1(
    'ai.read.accounting'
  ) authority;
  if p_horizon is null
     or p_horizon not in ('today', 'next_7_days', 'next_30_days')
     or p_limit is null or p_limit not between 1 and 8 then
    raise exception 'Invalid AI tool arguments' using errcode = '22023';
  end if;
  v_business_date := public.tenant_business_date(v_authority.tenant_id);
  v_end_date := case p_horizon
    when 'today' then v_business_date
    when 'next_7_days' then v_business_date + 7
    else v_business_date + 30
  end;

  -- This is a book balance over the explicitly mapped liquid asset accounts;
  -- it is never presented as a provider/bank balance.
  begin
    with liquid_accounts as materialized (
      select distinct account.id
      from public.payment_methods payment_method
      join public.accounts account
        on account.id = payment_method.account_id
       and account.tenant_id = payment_method.tenant_id
      where payment_method.tenant_id = v_authority.tenant_id
        and payment_method.is_active is true
        and account.is_active is true
        and account.type = 'asset'
    ), balances as (
      select liquid_account.id,
        coalesce(sum(journal_line.debit_amount
          - journal_line.credit_amount) filter (
            where journal_entry.id is not null
          ), 0) balance
      from liquid_accounts liquid_account
      left join public.journal_lines journal_line
        on journal_line.tenant_id = v_authority.tenant_id
       and journal_line.account_id = liquid_account.id
      left join public.journal_entries journal_entry
        on journal_entry.id = journal_line.entry_id
       and journal_entry.tenant_id = journal_line.tenant_id
       and lower(journal_entry.status) = 'posted'
       and journal_entry.entry_date <= statement_timestamp()
      group by liquid_account.id
    )
    select count(*)::integer,
      coalesce(sum(balance), 0)
    into v_cash_account_count, v_book_liquid_funds_balance
    from balances;
    v_cash_source_status := case when v_cash_account_count = 0
      then 'verifiedEmpty' else 'success' end;
  exception when others then
    v_cash_source_status := 'unavailable';
    v_cash_account_count := null;
    v_book_liquid_funds_balance := null;
  end;

  begin
    with payment_totals as materialized (
      select payment.invoice_id,
        public.clp_round(coalesce(sum(payment.amount), 0)) amount
      from public.sales_payments payment
      where payment.tenant_id = v_authority.tenant_id
        and payment.deleted_at is null
      group by payment.invoice_id
    ), credit_totals as materialized (
      select credit.sales_invoice_id invoice_id,
        public.clp_round(coalesce(sum(credit.total_amount), 0)) amount
      from public.sales_credit_notes credit
      where credit.tenant_id = v_authority.tenant_id
        and credit.status = 'posted'
      group by credit.sales_invoice_id
    ), refund_totals as materialized (
      select refund.sales_invoice_id invoice_id,
        public.clp_round(coalesce(sum(refund.amount), 0)) amount
      from public.sales_customer_refunds refund
      where refund.tenant_id = v_authority.tenant_id
        and refund.status = 'posted'
      group by refund.sales_invoice_id
    ), settlement as materialized (
      select invoice.id entity_id, invoice.invoice_number,
        invoice.due_date,
        greatest(
          greatest(public.clp_round(invoice.total)
            - coalesce(credit.amount, 0), 0)
          - greatest(coalesce(payment.amount, 0)
            - coalesce(refund.amount, 0), 0),
          0
        ) balance
      from public.sales_invoices invoice
      left join payment_totals payment on payment.invoice_id = invoice.id
      left join credit_totals credit on credit.invoice_id = invoice.id
      left join refund_totals refund on refund.invoice_id = invoice.id
      where invoice.tenant_id = v_authority.tenant_id
        and lower(coalesce(invoice.status, '')) not in (
          'draft', 'borrador', 'cancelled', 'cancelado', 'cancelada',
          'anulado', 'anulada'
        )
    ), open_receivables as materialized (
      select settlement.entity_id, settlement.invoice_number,
        settlement.due_date, settlement.balance,
        case
          when due_date is null then 'no_due_date'
          when public.tenant_business_date(
            v_authority.tenant_id, due_date
          ) < v_business_date then 'overdue'
          when public.tenant_business_date(
            v_authority.tenant_id, due_date
          ) = v_business_date then 'due_today'
          when public.tenant_business_date(
            v_authority.tenant_id, due_date
          ) <= v_end_date then 'due_in_horizon'
          else 'later'
        end timing,
        case when due_date is not null
          and public.tenant_business_date(
            v_authority.tenant_id, due_date
          ) < v_business_date
          then v_business_date - public.tenant_business_date(
            v_authority.tenant_id, due_date
          ) else null end days_overdue
      from settlement
      where balance > 0
    ), numbered as materialized (
      select open_receivable.entity_id, open_receivable.invoice_number,
        open_receivable.due_date, open_receivable.balance,
        open_receivable.timing, open_receivable.days_overdue,
        row_number() over (order by
          case timing when 'overdue' then 0 when 'due_today' then 1
            when 'due_in_horizon' then 2 when 'later' then 3 else 4 end,
          due_date nulls last, invoice_number, entity_id
        ) ordinal
      from open_receivables open_receivable
    )
    select count(*)::integer,
      coalesce(sum(balance), 0),
      coalesce(sum(balance) filter (where timing = 'overdue'), 0),
      coalesce(sum(balance) filter (
        where timing in ('due_today', 'due_in_horizon')
      ), 0),
      coalesce(sum(balance) filter (where timing = 'no_due_date'), 0),
      count(*) filter (where timing = 'overdue')::integer,
      coalesce(jsonb_agg(jsonb_build_object(
        'kind', 'receivable',
        'entityId', entity_id,
        'invoiceNumber', public.assistant_truncate_utf8_internal_v1(
          invoice_number, 100),
        'balance', balance,
        'dueDate', case when due_date is null then null else
          public.tenant_business_date(v_authority.tenant_id, due_date) end,
        'daysOverdue', days_overdue,
        'timing', timing
      ) order by ordinal) filter (where ordinal <= p_limit), '[]'::jsonb)
    into v_open_invoice_count, v_receivables_total,
      v_overdue_receivables, v_due_in_horizon_receivables,
      v_no_due_date_receivables, v_overdue_invoice_count,
      v_receivable_items
    from numbered;
    v_receivables_source_status := case when v_open_invoice_count = 0
      then 'verifiedEmpty' else 'success' end;
    v_has_more := v_open_invoice_count > p_limit;
  exception when others then
    v_receivables_source_status := 'unavailable';
    v_receivables_total := null;
    v_overdue_receivables := null;
    v_due_in_horizon_receivables := null;
    v_no_due_date_receivables := null;
    v_open_invoice_count := null;
    v_overdue_invoice_count := null;
    v_receivable_items := '[]'::jsonb;
    v_has_more := false;
  end;

  v_items := jsonb_build_array(jsonb_build_object(
    'kind', 'summary',
    'asOfDate', v_business_date,
    'horizon', p_horizon,
    'cashSourceStatus', v_cash_source_status,
    'bookLiquidFundsBalance', v_book_liquid_funds_balance,
    'cashAccountCount', v_cash_account_count,
    'receivablesSourceStatus', v_receivables_source_status,
    'receivablesTotal', v_receivables_total,
    'overdueReceivables', v_overdue_receivables,
    'dueInHorizonReceivables', v_due_in_horizon_receivables,
    'noDueDateReceivables', v_no_due_date_receivables,
    'openInvoiceCount', v_open_invoice_count,
    'overdueInvoiceCount', v_overdue_invoice_count
  )) || v_receivable_items;
  return public.assistant_tool_envelope_internal_v1(
    v_authority.tenant_id, v_items, v_has_more
  );
end;
$$;

create or replace function public.assistant_search_conversations_v1(
  p_query text,
  p_channel text,
  p_status text,
  p_context_type text,
  p_unread_only boolean,
  p_needs_reply_only boolean,
  p_days integer,
  p_limit integer
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, pg_temp
set statement_timeout = '4500ms'
as $$
declare
  v_authority record;
  v_query text;
  v_business_date date;
  v_items jsonb;
  v_total integer;
begin
  select authority.tenant_id, authority.actor_user_id,
    authority.authority_role, authority.permissions, authority.capabilities,
    authority.authority_fingerprint
  into strict v_authority
  from public.assistant_require_capability_internal_v1(
    'ai.read.operational'
  ) authority;
  if octet_length(coalesce(p_query, '')) > 240
     or p_channel is null or p_channel not in (
       'any', 'internal', 'website_portal', 'whatsapp', 'instagram',
       'facebook_messenger'
     )
     or p_status is null or p_status not in (
       'any', 'pending', 'active', 'resolved', 'rejected'
     )
     or p_context_type is null or p_context_type not in (
       'any', 'job', 'invoice', 'order', 'purchase_invoice', 'supplier',
       'customer', 'product', 'bike'
     )
     or p_unread_only is null or p_needs_reply_only is null
     or p_days is null or p_days not between 1 and 365
     or p_limit is null or p_limit not between 1 and 10 then
    raise exception 'Invalid AI tool arguments' using errcode = '22023';
  end if;
  v_query := nullif(public.assistant_normalize_query_internal_v1(p_query), '');
  v_business_date := public.tenant_business_date(v_authority.tenant_id);

  with visible as materialized (
    select conversation.id entity_id, conversation.channel,
      coalesce(conversation.counterparty_type,
        case when conversation.type = 'internal'
          then 'internal' else 'customer' end) counterparty_type,
      coalesce(conversation.status, 'active') status,
      coalesce(conversation.is_group, false) is_group,
      coalesce(primary_context.context_type,
        conversation.context_type) context_type,
      coalesce(primary_context.context_id,
        conversation.context_id) context_entity_id,
      conversation.title, conversation.created_at,
      latest.content latest_content, latest.created_at last_message_at,
      latest.type last_message_type,
      latest.message_direction last_message_direction,
      latest.sender_id last_sender_id,
      latest.message_sequence,
      coalesce(unread.unread_count, 0)::integer unread_count,
      whatsapp.contact_name whatsapp_contact_name,
      whatsapp.external_phone_number whatsapp_phone,
      meta.contact_name meta_contact_name, meta.username meta_username
    from public.conversations conversation
    left join lateral (
      select message.content, message.created_at, message.type,
        message.message_direction, message.sender_id,
        message.message_sequence
      from public.messages message
      where message.conversation_id = conversation.id
        and message.tenant_id = conversation.tenant_id
        and coalesce(message.type, 'text') <> 'system'
      order by message.message_sequence desc
      limit 1
    ) latest on true
    left join lateral (
      select context.context_type, context.context_id
      from public.conversation_contexts context
      where context.conversation_id = conversation.id
        and context.tenant_id = conversation.tenant_id
        and context.is_primary is true
      order by context.added_at desc nulls last, context.id desc
      limit 1
    ) primary_context on true
    left join public.conversation_unread_counts unread
      on unread.conversation_id = conversation.id
     and unread.user_id = v_authority.actor_user_id
    left join lateral (
      select binding.contact_name, binding.external_phone_number
      from public.whatsapp_conversation_bindings binding
      where binding.conversation_id = conversation.id
        and binding.tenant_id = conversation.tenant_id
      order by binding.updated_at desc, binding.id desc
      limit 1
    ) whatsapp on true
    left join lateral (
      select binding.contact_name, binding.username
      from public.meta_conversation_bindings binding
      where binding.conversation_id = conversation.id
        and binding.tenant_id = conversation.tenant_id
      order by binding.updated_at desc, binding.id desc
      limit 1
    ) meta on true
    where conversation.tenant_id = v_authority.tenant_id
      and public.messaging_can_read_conversation_messages(conversation.id)
      and public.tenant_business_date(
        v_authority.tenant_id,
        coalesce(latest.created_at, conversation.last_message_at,
          conversation.created_at)
      ) between v_business_date - (p_days - 1) and v_business_date
      and (p_channel = 'any' or conversation.channel = p_channel)
      and (p_status = 'any' or conversation.status = p_status)
  ), contextualized as materialized (
    select visible.entity_id, visible.channel, visible.counterparty_type,
      visible.status, visible.is_group, visible.context_type,
      visible.context_entity_id, visible.title, visible.created_at,
      visible.latest_content, visible.last_message_at,
      visible.last_message_type, visible.last_message_direction,
      visible.last_sender_id, visible.message_sequence,
      visible.unread_count, visible.whatsapp_contact_name,
      visible.whatsapp_phone, visible.meta_contact_name,
      visible.meta_username,
      case visible.context_type
        when 'job' then job.job_number
        when 'invoice' then invoice.invoice_number
        when 'order' then online_order.order_number
        when 'purchase_invoice' then purchase_invoice.invoice_number
        else null
      end context_label
    from visible
    left join public.mechanic_jobs job
      on visible.context_type = 'job'
     and job.id = visible.context_entity_id
     and job.tenant_id = v_authority.tenant_id
    left join public.sales_invoices invoice
      on visible.context_type = 'invoice'
     and invoice.id = visible.context_entity_id
     and invoice.tenant_id = v_authority.tenant_id
    left join public.online_orders online_order
      on visible.context_type = 'order'
     and online_order.id = visible.context_entity_id
     and online_order.tenant_id = v_authority.tenant_id
    left join public.purchase_invoices purchase_invoice
      on visible.context_type = 'purchase_invoice'
     and purchase_invoice.id = visible.context_entity_id
     and purchase_invoice.tenant_id = v_authority.tenant_id
  ), classified as materialized (
    select contextualized.entity_id, contextualized.channel,
      contextualized.counterparty_type, contextualized.status,
      contextualized.is_group, contextualized.context_type,
      contextualized.context_entity_id, contextualized.title,
      contextualized.created_at, contextualized.latest_content,
      contextualized.last_message_at, contextualized.last_message_type,
      contextualized.last_message_direction, contextualized.last_sender_id,
      contextualized.message_sequence, contextualized.unread_count,
      contextualized.whatsapp_contact_name, contextualized.whatsapp_phone,
      contextualized.meta_contact_name, contextualized.meta_username,
      contextualized.context_label,
      coalesce(
        status in ('pending', 'active')
        and message_sequence is not null
        and case
          when channel in ('whatsapp', 'instagram', 'facebook_messenger')
            then last_message_direction = 'inbound'
          when channel = 'website_portal' then not exists (
            select 1 from public.user_profiles sender_profile
            where sender_profile.user_id = contextualized.last_sender_id
              and sender_profile.tenant_id = v_authority.tenant_id
              and sender_profile.is_active is true
          )
          when channel = 'internal'
            then last_sender_id is distinct from v_authority.actor_user_id
          else false
        end,
        false
      ) needs_reply
    from contextualized
  ), matched as materialized (
    select entity_id, channel, counterparty_type, status, is_group,
      context_type, context_entity_id, context_label, last_message_at,
      last_message_type, last_message_direction, unread_count, needs_reply,
      message_sequence
    from classified
    where (p_context_type = 'any' or context_type = p_context_type)
      and (p_unread_only is false or unread_count > 0)
      and (p_needs_reply_only is false or needs_reply)
      and (v_query is null or not exists (
        select 1 from regexp_split_to_table(v_query, ' +') token
        where position(token in public.assistant_normalize_query_internal_v1(
          concat_ws(' ', title, latest_content, whatsapp_contact_name,
            whatsapp_phone, meta_contact_name, meta_username, channel,
            status, context_label)
        )) = 0
      ))
    order by message_sequence desc nulls last, last_message_at desc nulls last,
      entity_id
    limit p_limit + 1
  ), numbered as (
    select matched.entity_id, matched.channel, matched.counterparty_type,
      matched.status, matched.is_group, matched.context_type,
      matched.context_entity_id, matched.context_label,
      matched.last_message_at, matched.last_message_type,
      matched.last_message_direction, matched.unread_count,
      matched.needs_reply, matched.message_sequence,
      row_number() over (order by
      message_sequence desc nulls last, last_message_at desc nulls last,
      entity_id
    ) ordinal
    from matched
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'entityId', entity_id,
      'channel', channel,
      'counterpartyType', counterparty_type,
      'status', status,
      'isGroup', is_group,
      'contextType', context_type,
      'contextEntityId', context_entity_id,
      'contextLabel', nullif(public.assistant_truncate_utf8_internal_v1(
        coalesce(context_label, ''), 100), ''),
      'lastMessageAt', last_message_at,
      'lastMessageType', last_message_type,
      'lastMessageDirection', last_message_direction,
      'unreadCount', unread_count,
      'needsReply', needs_reply
    ) order by ordinal) filter (where ordinal <= p_limit), '[]'::jsonb),
    count(*)
  into v_items, v_total
  from numbered;
  return public.assistant_tool_envelope_internal_v1(
    v_authority.tenant_id, v_items, v_total > p_limit
  );
end;
$$;

revoke all on function public.assistant_analyze_cash_and_receivables_v1(
  text, integer
) from public, anon, authenticated, service_role;
revoke all on function public.assistant_search_conversations_v1(
  text, text, text, text, boolean, boolean, integer, integer
) from public, anon, authenticated, service_role;

grant execute on function public.assistant_analyze_cash_and_receivables_v1(
  text, integer
) to authenticated;
grant execute on function public.assistant_search_conversations_v1(
  text, text, text, text, boolean, boolean, integer, integer
) to authenticated;

comment on function public.assistant_analyze_cash_and_receivables_v1(
  text, integer
) is 'Accounting-capability book liquid-funds and recomputed receivables projection.';
comment on function public.assistant_search_conversations_v1(
  text, text, text, text, boolean, boolean, integer, integer
) is 'Conversation-access-bound metadata projection with no message content or counterparty PII.';

create or replace function public.assistant_find_inventory_risks_v1(
  p_query text,
  p_risk text,
  p_limit integer
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, pg_temp
set statement_timeout = '4500ms'
as $$
declare
  v_authority record;
  v_query text;
  v_items jsonb;
  v_total integer;
begin
  select authority.tenant_id, authority.actor_user_id,
    authority.authority_role, authority.permissions, authority.capabilities,
    authority.authority_fingerprint
  into strict v_authority
  from public.assistant_require_capability_internal_v1(
    'ai.read.operational'
  ) authority;
  if octet_length(coalesce(p_query, '')) > 240
     or p_risk is null
     or p_risk not in ('any', 'low_stock', 'out_of_stock')
     or p_limit is null or p_limit not between 1 and 10 then
    raise exception 'Invalid AI tool arguments' using errcode = '22023';
  end if;
  v_query := nullif(public.assistant_normalize_query_internal_v1(p_query), '');

  with candidates as materialized (
    select product.id entity_id, product.name, product.sku,
      coalesce(product.category_name, product.category) category,
      case when coalesce(product.is_set, false)
        then public.get_full_sets_count(product.id)
        else coalesce(product.stock_quantity, product.inventory_qty, 0)
      end stock,
      greatest(coalesce(product.min_stock_level, 0), 0) minimum_stock,
      coalesce(product.is_set, false) is_set,
      product.updated_at,
      concat_ws(' ', product.name, product.sku, product.brand,
        product.category_name, product.category) searchable
    from public.products product
    where product.tenant_id = v_authority.tenant_id
      and product.is_active is true
      and coalesce(product.track_stock, true) is true
      and coalesce(product.is_service, false) is false
      and coalesce(product.purchase_treatment, 'inventory') = 'inventory'
  ), classified as materialized (
    select candidate.entity_id, candidate.name, candidate.sku,
      candidate.category, candidate.stock, candidate.minimum_stock,
      candidate.is_set, candidate.updated_at, candidate.searchable,
      case when stock <= 0 then 'out_of_stock' else 'low_stock' end risk
    from candidates candidate
    where stock <= 0 or stock <= minimum_stock
  ), matched as materialized (
    select entity_id, name, sku, category, stock, minimum_stock, risk,
      is_set, updated_at
    from classified
    where (p_risk = 'any' or risk = p_risk)
      and (v_query is null or not exists (
        select 1 from regexp_split_to_table(v_query, ' +') token
        where position(token in public.assistant_normalize_query_internal_v1(
          searchable
        )) = 0
      ))
    order by case risk when 'out_of_stock' then 0 else 1 end,
      stock, minimum_stock desc, updated_at desc nulls last, name, entity_id
    limit p_limit + 1
  ), numbered as (
    select matched.entity_id, matched.name, matched.sku, matched.category,
      matched.stock, matched.minimum_stock, matched.risk, matched.is_set,
      matched.updated_at,
      row_number() over (order by
        case risk when 'out_of_stock' then 0 else 1 end,
        stock, minimum_stock desc, updated_at desc nulls last, name, entity_id
      ) ordinal
    from matched
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'entityId', entity_id,
      'name', public.assistant_truncate_utf8_internal_v1(name, 160),
      'sku', nullif(public.assistant_truncate_utf8_internal_v1(
        coalesce(sku, ''), 80), ''),
      'category', nullif(public.assistant_truncate_utf8_internal_v1(
        coalesce(category, ''), 100), ''),
      'stock', stock,
      'minimumStock', minimum_stock,
      'risk', risk,
      'isSet', is_set,
      'updatedAt', updated_at
    ) order by ordinal) filter (where ordinal <= p_limit), '[]'::jsonb),
    count(*)
  into v_items, v_total
  from numbered;
  return public.assistant_tool_envelope_internal_v1(
    v_authority.tenant_id, v_items, v_total > p_limit
  );
end;
$$;

create or replace function public.assistant_list_recent_expenses_v1(
  p_query text,
  p_days integer,
  p_posting_status text,
  p_payment_status text,
  p_approval_status text,
  p_limit integer
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, pg_temp
set statement_timeout = '4500ms'
as $$
declare
  v_authority record;
  v_query text;
  v_business_date date;
  v_items jsonb;
  v_total integer;
begin
  select authority.tenant_id, authority.actor_user_id,
    authority.authority_role, authority.permissions, authority.capabilities,
    authority.authority_fingerprint
  into strict v_authority
  from public.assistant_require_capability_internal_v1(
    'ai.read.accounting'
  ) authority;
  if octet_length(coalesce(p_query, '')) > 240
     or p_days is null or p_days not between 1 and 365
     or p_posting_status is null
     or p_posting_status not in ('any', 'draft', 'posted', 'void')
     or p_payment_status is null
     or p_payment_status not in (
       'any', 'pending', 'scheduled', 'partial', 'paid', 'void'
     )
     or p_approval_status is null
     or p_approval_status not in ('any', 'pending', 'approved', 'rejected')
     or p_limit is null or p_limit not between 1 and 10 then
    raise exception 'Invalid AI tool arguments' using errcode = '22023';
  end if;
  v_query := nullif(public.assistant_normalize_query_internal_v1(p_query), '');
  v_business_date := public.tenant_business_date(v_authority.tenant_id);

  with matched as materialized (
    select expense.id entity_id, expense.expense_number,
      category.name category, expense.issue_date, expense.due_date,
      expense.posting_status, expense.payment_status,
      expense.approval_status, expense.currency, expense.total_amount,
      expense.amount_paid, expense.balance, expense.updated_at
    from public.expenses expense
    left join public.expense_categories category
      on category.id = expense.category_id
     and category.tenant_id = expense.tenant_id
    where expense.tenant_id = v_authority.tenant_id
      and public.tenant_business_date(
        v_authority.tenant_id, expense.issue_date
      ) between v_business_date - (p_days - 1) and v_business_date
      and (p_posting_status = 'any'
        or lower(expense.posting_status) = p_posting_status)
      and (p_payment_status = 'any'
        or lower(expense.payment_status) = p_payment_status)
      and (p_approval_status = 'any'
        or lower(expense.approval_status) = p_approval_status)
      and (v_query is null or not exists (
        select 1 from regexp_split_to_table(v_query, ' +') token
        where position(token in public.assistant_normalize_query_internal_v1(
          concat_ws(' ', expense.expense_number, expense.document_type,
            expense.document_number, category.name, expense.supplier_name)
        )) = 0
      ))
    order by expense.issue_date desc, expense.updated_at desc,
      expense.expense_number, expense.id
    limit p_limit + 1
  ), numbered as (
    select matched.entity_id, matched.expense_number, matched.category,
      matched.issue_date, matched.due_date, matched.posting_status,
      matched.payment_status, matched.approval_status, matched.currency,
      matched.total_amount, matched.amount_paid, matched.balance,
      matched.updated_at,
      row_number() over (order by issue_date desc, updated_at desc,
        expense_number, entity_id) ordinal
    from matched
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'entityId', entity_id,
      'expenseNumber', public.assistant_truncate_utf8_internal_v1(
        expense_number, 100),
      'category', nullif(public.assistant_truncate_utf8_internal_v1(
        coalesce(category, ''), 160), ''),
      'issueDate', public.tenant_business_date(
        v_authority.tenant_id, issue_date),
      'dueDate', case when due_date is null then null else
        public.tenant_business_date(v_authority.tenant_id, due_date) end,
      'postingStatus', posting_status,
      'paymentStatus', payment_status,
      'approvalStatus', approval_status,
      'currency', public.assistant_truncate_utf8_internal_v1(currency, 12),
      'totalAmount', total_amount,
      'amountPaid', amount_paid,
      'balance', balance
    ) order by ordinal) filter (where ordinal <= p_limit), '[]'::jsonb),
    count(*)
  into v_items, v_total
  from numbered;
  return public.assistant_tool_envelope_internal_v1(
    v_authority.tenant_id, v_items, v_total > p_limit
  );
end;
$$;

revoke all on function public.assistant_find_inventory_risks_v1(
  text, text, integer
) from public, anon, authenticated, service_role;
revoke all on function public.assistant_list_recent_expenses_v1(
  text, integer, text, text, text, integer
) from public, anon, authenticated, service_role;

grant execute on function public.assistant_find_inventory_risks_v1(
  text, text, integer
) to authenticated;
grant execute on function public.assistant_list_recent_expenses_v1(
  text, integer, text, text, text, integer
) to authenticated;

comment on function public.assistant_find_inventory_risks_v1(
  text, text, integer
) is 'Tenant-bound closed inventory risk projection for the ERP assistant.';
comment on function public.assistant_list_recent_expenses_v1(
  text, integer, text, text, text, integer
) is 'Accounting-capability closed expense header projection for the ERP assistant.';

commit;
