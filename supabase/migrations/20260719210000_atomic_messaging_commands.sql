-- Close the remaining messaging consistency gaps around read evidence,
-- customer request creation, WhatsApp rebinding, and supplier capabilities.
--
-- Forward plan:
--   * persist a stable conversation counterparty boundary;
--   * accept read receipts only through an exact visible message id;
--   * create customer support requests as one idempotent aggregate;
--   * create/rebind WhatsApp cases atomically instead of reopening archives.
--
-- Recovery plan:
--   Roll the client back while retaining the additive counterparty column and
--   command receipts. They are compatible audit evidence. Do not drop them or
--   restore unsafe one-argument read behavior. A compatibility no-op remains
--   available to old clients without advancing unread state. A forward
--   migration can replace individual command bodies without rewriting history.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '60s';

alter table public.conversations
  add column if not exists counterparty_type text;

alter table public.conversations
  add column if not exists is_group boolean;

-- Legacy internal groups were represented only by a title/participant count.
-- Persist the distinction so a one-recipient titled group is never mistaken
-- for the reusable direct-chat pair.
update public.conversations conversation
set is_group = case
  when conversation.type = 'internal'
    and (
      nullif(btrim(coalesce(conversation.title, '')), '') is not null
      or (
        select count(*)
        from public.conversation_participants participant
        where participant.conversation_id = conversation.id
      ) > 2
    ) then true
  else false
end
where conversation.is_group is null;

alter table public.conversations
  alter column is_group set default false,
  alter column is_group set not null;

-- Message insertion order is the exact read cursor. Timestamps alone cannot
-- distinguish two rows written in the same transaction/microsecond.
alter table public.messages
  add column if not exists message_sequence bigint
    generated always as identity;

alter table public.messages
  alter column message_sequence set generated always;

alter table public.conversation_participants
  add column if not exists last_read_message_sequence bigint;

alter table public.conversations
  add column if not exists staff_last_read_message_sequence bigint;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'messages_message_sequence_key'
      and conrelid = 'public.messages'::regclass
  ) then
    alter table public.messages
      add constraint messages_message_sequence_key unique (message_sequence);
  end if;
end;
$$;

create index if not exists idx_messages_conversation_sequence
  on public.messages(conversation_id, message_sequence);

comment on column public.messages.message_sequence is
  'Monotonic server insertion cursor used for exact read-through semantics.';
comment on column public.conversation_participants.last_read_message_sequence is
  'Highest exact server message sequence acknowledged by this participant.';
comment on column public.conversations.staff_last_read_message_sequence is
  'Shared highest exact server message sequence acknowledged by support staff.';

-- Preserve the effective legacy timestamp boundary once, then use the exact
-- sequence for every subsequent read. Rows without prior messages stay null.
update public.conversation_participants participant
set last_read_message_sequence = (
  select message.message_sequence
  from public.messages message
  where message.conversation_id = participant.conversation_id
    and message.created_at <= participant.last_read_at
  order by message.message_sequence desc
  limit 1
)
where participant.last_read_message_sequence is null
  and participant.last_read_at is not null
  and exists (
    select 1
    from public.messages message
    where message.conversation_id = participant.conversation_id
      and message.created_at <= participant.last_read_at
  );

update public.conversations conversation
set staff_last_read_message_sequence = (
  select message.message_sequence
  from public.messages message
  where message.conversation_id = conversation.id
    and message.created_at <= conversation.staff_last_read_at
  order by message.message_sequence desc
  limit 1
)
where conversation.staff_last_read_message_sequence is null
  and conversation.staff_last_read_at is not null
  and exists (
    select 1
    from public.messages message
    where message.conversation_id = conversation.id
      and message.created_at <= conversation.staff_last_read_at
  );

-- A supplier thread is identified from any durable supplier-side context.
-- Every other support thread is customer-facing; internal chats remain their
-- own capability class. This one-time classification is retained even when the
-- primary operational context changes later.
update public.conversations conversation
set counterparty_type = case
  when conversation.type = 'internal' then 'internal'
  when conversation.context_type in ('supplier', 'purchase_invoice')
    or exists (
      select 1
      from public.conversation_contexts context_link
      where context_link.conversation_id = conversation.id
        and context_link.tenant_id = conversation.tenant_id
        and context_link.context_type in ('supplier', 'purchase_invoice')
    ) then 'supplier'
  else 'customer'
end
where conversation.counterparty_type is null
   or conversation.counterparty_type not in ('internal', 'customer', 'supplier');

-- Keep old context links as history, but ensure the scalar primary projection
-- of a supplier thread cannot continue advertising a customer-only entity.
with preferred_supplier_context as (
  select distinct on (context_link.conversation_id)
    context_link.conversation_id,
    context_link.context_type,
    context_link.context_id
  from public.conversation_contexts context_link
  join public.conversations conversation
    on conversation.id = context_link.conversation_id
   and conversation.tenant_id = context_link.tenant_id
  where conversation.counterparty_type = 'supplier'
    and context_link.context_type in ('supplier', 'purchase_invoice')
  order by
    context_link.conversation_id,
    context_link.is_primary desc,
    context_link.added_at desc nulls last,
    context_link.id desc
)
update public.conversations conversation
set context_type = preferred.context_type,
    context_id = preferred.context_id,
    updated_at = greatest(conversation.updated_at, now())
from preferred_supplier_context preferred
where conversation.id = preferred.conversation_id
  and conversation.counterparty_type = 'supplier'
  and (
    conversation.context_type not in ('supplier', 'purchase_invoice')
    or conversation.context_type is null
    or conversation.context_id is null
  );

-- Historical links remain, but an incompatible link can never be promoted to
-- the active context of the opposite capability.
update public.conversation_contexts context_link
set is_primary = false
from public.conversations conversation
where conversation.id = context_link.conversation_id
  and conversation.tenant_id = context_link.tenant_id
  and context_link.is_primary
  and (
    (
      conversation.counterparty_type = 'supplier'
      and context_link.context_type not in ('supplier', 'purchase_invoice')
    )
    or (
      conversation.counterparty_type = 'customer'
      and context_link.context_type in ('supplier', 'purchase_invoice')
    )
  );

-- Legacy data could advertise more than one primary. Retain the scalar match
-- when possible, otherwise the most recently added valid primary wins.
with duplicate_primary as (
  select
    context_link.id,
    row_number() over (
      partition by context_link.conversation_id
      order by
        (
          context_link.context_type = conversation.context_type
          and context_link.context_id = conversation.context_id
        ) desc,
        context_link.added_at desc nulls last,
        context_link.id desc
    ) as position
  from public.conversation_contexts context_link
  join public.conversations conversation
    on conversation.id = context_link.conversation_id
   and conversation.tenant_id = context_link.tenant_id
  where context_link.is_primary
)
update public.conversation_contexts context_link
set is_primary = false
from duplicate_primary duplicate
where context_link.id = duplicate.id
  and duplicate.position > 1;

create unique index if not exists uq_conversation_contexts_one_primary
  on public.conversation_contexts(conversation_id)
  where is_primary;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'conversations_counterparty_type_check'
      and conrelid = 'public.conversations'::regclass
  ) then
    alter table public.conversations
      add constraint conversations_counterparty_type_check
      check (
        (type = 'internal' and counterparty_type = 'internal')
        or (
          type = 'support'
          and counterparty_type in ('customer', 'supplier')
        )
      );
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'conversations_is_group_type_check'
      and conrelid = 'public.conversations'::regclass
  ) then
    alter table public.conversations
      add constraint conversations_is_group_type_check
      check (type = 'internal' or not is_group);
  end if;
end;
$$;

alter table public.conversations
  alter column counterparty_type set not null,
  alter column counterparty_type drop default;

comment on column public.conversations.counterparty_type is
  'Stable capability boundary: internal, customer, or supplier. It does not change when the primary operational context changes.';
comment on column public.conversations.is_group is
  'Immutable internal-conversation shape. False identifies reusable exact-pair direct chats.';

create table if not exists public.messaging_participant_reconciliation_audit (
  id uuid primary key default gen_random_uuid(),
  edge_fingerprint text not null unique,
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  conversation_id uuid not null references public.conversations(id)
    on delete restrict,
  user_id uuid not null references auth.users(id) on delete restrict,
  old_role text,
  old_joined_at timestamptz,
  old_last_read_at timestamptz,
  old_last_read_message_sequence bigint,
  reason text not null,
  migration_version text not null,
  reconciled_at timestamptz not null default clock_timestamp(),
  check (edge_fingerprint ~ '^[0-9a-f]{32}$'),
  check (nullif(btrim(reason), '') is not null),
  check (nullif(btrim(migration_version), '') is not null)
);

alter table public.messaging_participant_reconciliation_audit
  enable row level security;
revoke all on table public.messaging_participant_reconciliation_audit
  from public, anon, authenticated, service_role;
grant select, insert on table public.messaging_participant_reconciliation_audit
  to service_role;

comment on table public.messaging_participant_reconciliation_audit is
  'Append-only evidence for unsafe legacy participant edges removed by guarded messaging reconciliation.';

-- Legacy supplier threads may contain customer-only participants from the old
-- generic support policy. Remove only that unsafe recipient edge; messages,
-- contexts, bindings and the conversation itself remain retained evidence.
create or replace function public.reconcile_supplier_customer_participants()
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_removed integer := 0;
begin
  insert into public.messaging_participant_reconciliation_audit (
    edge_fingerprint,
    tenant_id,
    conversation_id,
    user_id,
    old_role,
    old_joined_at,
    old_last_read_at,
    old_last_read_message_sequence,
    reason,
    migration_version
  )
  select
    md5(concat_ws(
      '|',
      '20260719210000',
      participant.tenant_id::text,
      participant.conversation_id::text,
      participant.user_id::text,
      coalesce(participant.created_at::text, '<null>')
    )),
    participant.tenant_id,
    participant.conversation_id,
    participant.user_id,
    participant.role,
    participant.created_at,
    participant.last_read_at,
    participant.last_read_message_sequence,
    'customer_only_identity_in_supplier_conversation',
    '20260719210000'
  from public.conversation_participants participant
  join public.conversations conversation
    on conversation.id = participant.conversation_id
   and conversation.tenant_id = participant.tenant_id
  where conversation.counterparty_type = 'supplier'
    and exists (
      select 1
      from public.customers customer
      where customer.auth_user_id = participant.user_id
        and customer.tenant_id = conversation.tenant_id
    )
    and not exists (
      select 1
      from public.user_profiles staff
      where staff.user_id = participant.user_id
        and staff.tenant_id = conversation.tenant_id
        and coalesce(staff.is_active, true)
    )
  on conflict (edge_fingerprint)
    do nothing;

  if exists (
    select 1
    from public.conversation_participants participant
    join public.conversations conversation
      on conversation.id = participant.conversation_id
     and conversation.tenant_id = participant.tenant_id
    where conversation.counterparty_type = 'supplier'
      and exists (
        select 1
        from public.customers customer
        where customer.auth_user_id = participant.user_id
          and customer.tenant_id = conversation.tenant_id
      )
      and not exists (
        select 1
        from public.user_profiles staff
        where staff.user_id = participant.user_id
          and staff.tenant_id = conversation.tenant_id
          and coalesce(staff.is_active, true)
      )
      and not exists (
        select 1
        from public.messaging_participant_reconciliation_audit audit
        where audit.migration_version = '20260719210000'
          and audit.conversation_id = participant.conversation_id
          and audit.user_id = participant.user_id
          and audit.old_joined_at is not distinct from participant.created_at
      )
  ) then
    raise exception 'Supplier participant reconciliation audit is incomplete'
      using errcode = '23514';
  end if;

  delete from public.conversation_participants participant
  using public.conversations conversation
  where conversation.id = participant.conversation_id
    and conversation.tenant_id = participant.tenant_id
    and conversation.counterparty_type = 'supplier'
    and exists (
      select 1
      from public.customers customer
      where customer.auth_user_id = participant.user_id
        and customer.tenant_id = conversation.tenant_id
    )
    and not exists (
      select 1
      from public.user_profiles staff
      where staff.user_id = participant.user_id
        and staff.tenant_id = conversation.tenant_id
        and coalesce(staff.is_active, true)
    );

  get diagnostics v_removed = row_count;

  if exists (
    select 1
    from public.conversation_participants participant
    join public.conversations conversation
      on conversation.id = participant.conversation_id
     and conversation.tenant_id = participant.tenant_id
    where conversation.counterparty_type = 'supplier'
      and exists (
        select 1
        from public.customers customer
        where customer.auth_user_id = participant.user_id
          and customer.tenant_id = conversation.tenant_id
      )
      and not exists (
        select 1
        from public.user_profiles staff
        where staff.user_id = participant.user_id
          and staff.tenant_id = conversation.tenant_id
          and coalesce(staff.is_active, true)
      )
  ) then
    raise exception 'Supplier customer-only participant reconciliation failed'
      using errcode = '23514';
  end if;

  return v_removed;
end;
$$;

select public.reconcile_supplier_customer_participants();

create or replace function public.enforce_conversation_counterparty()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if tg_op = 'INSERT' then
    if new.counterparty_type is null then
      new.counterparty_type := case
        when new.type = 'internal' then 'internal'
        when new.context_type in ('supplier', 'purchase_invoice') then 'supplier'
        else 'customer'
      end;
    end if;
  else
    if new.counterparty_type is distinct from old.counterparty_type then
      raise exception 'Conversation counterparty_type is immutable'
        using errcode = '23514';
    end if;
    if new.is_group is distinct from old.is_group then
      raise exception 'Conversation is_group is immutable'
        using errcode = '23514';
    end if;
  end if;

  if new.type <> 'internal' and new.is_group then
    raise exception 'Only internal conversations can be groups'
      using errcode = '23514';
  end if;

  if new.type = 'internal' and new.counterparty_type <> 'internal' then
    raise exception 'Internal conversations require an internal counterparty'
      using errcode = '23514';
  end if;

  if new.type = 'support' and new.counterparty_type = 'supplier'
     and new.context_type is not null
     and new.context_type not in ('supplier', 'purchase_invoice') then
    raise exception 'Supplier conversations only accept supplier or purchase contexts'
      using errcode = '23514';
  end if;

  if new.type = 'support' and new.counterparty_type = 'customer'
     and new.context_type in ('supplier', 'purchase_invoice') then
    raise exception 'Customer conversations cannot accept supplier contexts'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_conversations_counterparty_guard
  on public.conversations;
create trigger trg_conversations_counterparty_guard
before insert or update on public.conversations
for each row execute function public.enforce_conversation_counterparty();

-- Capability-aware access remains safe even if a historical participant row
-- linked the wrong user class before this migration.
create or replace function public.messaging_is_conversation_participant(
  p_conversation_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select auth.uid() is not null
    and exists (
      select 1
      from public.conversation_participants participant
      join public.conversations conversation
        on conversation.id = participant.conversation_id
      where participant.conversation_id = p_conversation_id
        and participant.user_id = auth.uid()
        and participant.tenant_id = conversation.tenant_id
        and (
          conversation.counterparty_type <> 'supplier'
          or public.messaging_is_staff_in_tenant(conversation.tenant_id)
        )
    );
$$;

create or replace function public.messaging_can_access_conversation(
  p_conversation_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select auth.uid() is not null
    and exists (
      select 1
      from public.conversations conversation
      where conversation.id = p_conversation_id
        and (
          (
            conversation.type = 'internal'
            and (
              public.messaging_is_conversation_participant(conversation.id)
              or (
                conversation.created_by = auth.uid()
                and public.messaging_is_staff_in_tenant(conversation.tenant_id)
                and not exists (
                  select 1
                  from public.conversation_participants any_participant
                  where any_participant.conversation_id = conversation.id
                )
              )
            )
          )
          or (
            conversation.type = 'support'
            and (
              public.messaging_is_staff_in_tenant(conversation.tenant_id)
              or (
                conversation.counterparty_type = 'customer'
                and public.messaging_is_customer_in_tenant(
                  conversation.tenant_id
                )
                and (
                  public.messaging_is_conversation_participant(conversation.id)
                  or conversation.created_by = auth.uid()
                )
              )
            )
          )
        )
    );
$$;

create or replace function public.messaging_can_read_conversation_messages(
  p_conversation_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select auth.uid() is not null
    and exists (
      select 1
      from public.conversations conversation
      where conversation.id = p_conversation_id
        and (
          (
            conversation.type = 'internal'
            and public.messaging_is_conversation_participant(conversation.id)
          )
          or (
            conversation.type = 'support'
            and (
              public.messaging_is_staff_in_tenant(conversation.tenant_id)
              or (
                conversation.counterparty_type = 'customer'
                and public.messaging_is_customer_in_tenant(
                  conversation.tenant_id
                )
                and public.messaging_is_conversation_participant(
                  conversation.id
                )
              )
            )
          )
        )
    );
$$;

-- Resolve the authenticated customer account that owns a customer-scoped
-- business context. Product references are intentionally not ownership
-- evidence: a product can be discussed with many customers.
create or replace function public.messaging_context_customer_id(
  p_context_type text,
  p_context_id uuid,
  p_tenant_id uuid
)
returns uuid
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select case lower(coalesce(p_context_type, ''))
    when 'customer' then (
      select customer.id
      from public.customers customer
      where customer.id = p_context_id
        and customer.tenant_id = p_tenant_id
    )
    when 'job' then (
      select job.customer_id
      from public.mechanic_jobs job
      where job.id = p_context_id
        and job.tenant_id = p_tenant_id
    )
    when 'invoice' then (
      select invoice.customer_id
      from public.sales_invoices invoice
      where invoice.id = p_context_id
        and invoice.tenant_id = p_tenant_id
    )
    when 'bike' then (
      select bike.customer_id
      from public.bikes bike
      where bike.id = p_context_id
        and bike.tenant_id = p_tenant_id
    )
    when 'order' then (
      select online_order.customer_id
      from public.online_orders online_order
      where online_order.id = p_context_id
        and online_order.tenant_id = p_tenant_id
    )
    else null::uuid
  end;
$$;

create or replace function public.messaging_context_customer_user_id(
  p_context_type text,
  p_context_id uuid,
  p_tenant_id uuid
)
returns uuid
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select customer.auth_user_id
  from public.customers customer
  where customer.id = public.messaging_context_customer_id(
      p_context_type,
      p_context_id,
      p_tenant_id
    )
    and customer.tenant_id = p_tenant_id
    and coalesce(customer.is_active, true);
$$;

-- A customer participant is a capability, not a display hint. Staff may add a
-- customer only when immutable graph evidence identifies that exact account:
-- the customer created the case, owns a linked business context, or owns the
-- canonical WhatsApp binding. Merely belonging to the same tenant is never
-- sufficient.
create or replace function public.messaging_is_customer_counterparty(
  p_conversation_id uuid,
  p_user_id uuid,
  p_tenant_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select auth.uid() is not null
    and exists (
      select 1
      from public.conversations conversation
      join public.customers target_customer
        on target_customer.auth_user_id = p_user_id
       and target_customer.tenant_id = conversation.tenant_id
       and coalesce(target_customer.is_active, true)
      where conversation.id = p_conversation_id
        and conversation.tenant_id = p_tenant_id
        and conversation.type = 'support'
        and conversation.counterparty_type = 'customer'
        and (
          conversation.created_by = p_user_id
          or public.messaging_context_customer_user_id(
            conversation.context_type,
            conversation.context_id,
            conversation.tenant_id
          ) = p_user_id
          or exists (
            select 1
            from public.conversation_contexts context_link
            where context_link.conversation_id = conversation.id
              and context_link.tenant_id = conversation.tenant_id
              and public.messaging_context_customer_user_id(
                context_link.context_type,
                context_link.context_id,
                context_link.tenant_id
              ) = p_user_id
          )
          or exists (
            select 1
            from public.whatsapp_conversation_bindings binding
            join public.customers bound_customer
              on bound_customer.id = binding.customer_id
             and bound_customer.tenant_id = binding.tenant_id
             and coalesce(bound_customer.is_active, true)
            where binding.conversation_id = conversation.id
              and binding.tenant_id = conversation.tenant_id
              and bound_customer.auth_user_id = p_user_id
          )
        )
    );
$$;

create or replace function public.messaging_can_add_participant(
  p_conversation_id uuid,
  p_user_id uuid,
  p_tenant_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select auth.uid() is not null
    and exists (
      select 1
      from public.conversations conversation
      where conversation.id = p_conversation_id
        and conversation.tenant_id = p_tenant_id
        and public.messaging_user_belongs_to_tenant(
          p_user_id,
          conversation.tenant_id
        )
        and (
          (
            conversation.type = 'internal'
            and public.messaging_is_staff_in_tenant(conversation.tenant_id)
            and exists (
              select 1
              from public.user_profiles target_staff
              where target_staff.user_id = p_user_id
                and target_staff.tenant_id = conversation.tenant_id
                and coalesce(target_staff.is_active, true)
            )
            and (
              conversation.created_by = auth.uid()
              or exists (
                select 1
                from public.conversation_participants actor_participant
                where actor_participant.conversation_id = conversation.id
                  and actor_participant.user_id = auth.uid()
                  and actor_participant.tenant_id = conversation.tenant_id
                  and actor_participant.role = 'admin'
              )
            )
          )
          or (
            conversation.type = 'support'
            and conversation.counterparty_type = 'supplier'
            and public.messaging_is_staff_in_tenant(conversation.tenant_id)
            and exists (
              select 1
              from public.user_profiles target_staff
              where target_staff.user_id = p_user_id
                and target_staff.tenant_id = conversation.tenant_id
                and coalesce(target_staff.is_active, true)
            )
          )
          or (
            conversation.type = 'support'
            and conversation.counterparty_type = 'customer'
            and (
              (
                public.messaging_is_staff_in_tenant(conversation.tenant_id)
                and exists (
                  select 1
                  from public.user_profiles target_staff
                  where target_staff.user_id = p_user_id
                    and target_staff.tenant_id = conversation.tenant_id
                    and coalesce(target_staff.is_active, true)
                )
              )
              or (
                public.messaging_is_customer_counterparty(
                  conversation.id,
                  p_user_id,
                  conversation.tenant_id
                )
                and (
                  public.messaging_is_staff_in_tenant(conversation.tenant_id)
                  or (
                    p_user_id = auth.uid()
                    and conversation.created_by = auth.uid()
                    and public.messaging_is_customer_in_tenant(
                      conversation.tenant_id
                    )
                  )
                )
              )
            )
          )
        )
    );
$$;

create or replace function public.enforce_conversation_context_counterparty()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_conversation public.conversations%rowtype;
  v_context_customer_id uuid;
begin
  if tg_op = 'DELETE' then
    if old.is_primary then
      update public.conversations conversation
      set context_type = null,
          context_id = null,
          updated_at = clock_timestamp()
      where conversation.id = old.conversation_id
        and conversation.tenant_id = old.tenant_id
        and conversation.context_type is not distinct from old.context_type
        and conversation.context_id is not distinct from old.context_id;
    end if;
    return old;
  end if;

  if tg_op = 'UPDATE'
     and (
       new.id is distinct from old.id
       or new.conversation_id is distinct from old.conversation_id
       or new.context_type is distinct from old.context_type
       or new.context_id is distinct from old.context_id
       or new.tenant_id is distinct from old.tenant_id
       or new.added_by is distinct from old.added_by
       or new.added_at is distinct from old.added_at
     ) then
    raise exception 'Conversation context identity and evidence are immutable'
      using errcode = '23514';
  end if;

  -- A non-primary display-only update does not reinterpret historical identity.
  if tg_op = 'UPDATE'
     and not coalesce(new.is_primary, false)
     and not coalesce(old.is_primary, false)
     and new.conversation_id is not distinct from old.conversation_id
     and new.context_type is not distinct from old.context_type
     and new.context_id is not distinct from old.context_id then
    return new;
  end if;

  select conversation.*
  into v_conversation
  from public.conversations conversation
  where conversation.id = new.conversation_id;

  if not found then
    raise exception 'Parent conversation not found' using errcode = '23503';
  end if;

  if v_conversation.type = 'support'
     and v_conversation.counterparty_type = 'supplier'
     and new.context_type not in ('supplier', 'purchase_invoice') then
    raise exception 'Supplier conversations only accept supplier or purchase contexts'
      using errcode = '23514';
  end if;

  if v_conversation.type = 'support'
     and v_conversation.counterparty_type = 'customer'
     and new.context_type in ('supplier', 'purchase_invoice') then
    raise exception 'Customer conversations cannot accept supplier contexts'
      using errcode = '23514';
  end if;

  v_context_customer_id := public.messaging_context_customer_id(
    new.context_type,
    new.context_id,
    v_conversation.tenant_id
  );

  if v_conversation.type = 'support'
     and v_conversation.counterparty_type = 'customer'
     and v_context_customer_id is not null
     and (
       exists (
         select 1
         from public.customers creator_customer
         where creator_customer.auth_user_id = v_conversation.created_by
           and creator_customer.tenant_id = v_conversation.tenant_id
           and creator_customer.id is distinct from v_context_customer_id
           and not exists (
             select 1
             from public.user_profiles creator_staff
             where creator_staff.user_id = v_conversation.created_by
               and creator_staff.tenant_id = v_conversation.tenant_id
               and coalesce(creator_staff.is_active, true)
           )
       )
       or exists (
         select 1
         from public.conversation_participants participant
         join public.customers participant_customer
           on participant_customer.auth_user_id = participant.user_id
          and participant_customer.tenant_id = participant.tenant_id
         where participant.conversation_id = v_conversation.id
           and participant.tenant_id = v_conversation.tenant_id
           and participant_customer.id is distinct from v_context_customer_id
           and not exists (
             select 1
             from public.user_profiles participant_staff
             where participant_staff.user_id = participant.user_id
               and participant_staff.tenant_id = participant.tenant_id
               and coalesce(participant_staff.is_active, true)
           )
       )
       or exists (
         select 1
         from public.whatsapp_conversation_bindings binding
         where binding.conversation_id = v_conversation.id
           and binding.tenant_id = v_conversation.tenant_id
           and binding.customer_id is not null
           and binding.customer_id is distinct from v_context_customer_id
       )
       or (
         public.messaging_context_customer_id(
           v_conversation.context_type,
           v_conversation.context_id,
           v_conversation.tenant_id
         ) is not null
         and public.messaging_context_customer_id(
           v_conversation.context_type,
           v_conversation.context_id,
           v_conversation.tenant_id
         ) is distinct from v_context_customer_id
       )
       or exists (
         select 1
         from public.conversation_contexts retained_context
         where retained_context.conversation_id = v_conversation.id
           and retained_context.tenant_id = v_conversation.tenant_id
           and retained_context.id is distinct from new.id
           and public.messaging_context_customer_id(
             retained_context.context_type,
             retained_context.context_id,
             retained_context.tenant_id
           ) is not null
           and public.messaging_context_customer_id(
             retained_context.context_type,
             retained_context.context_id,
             retained_context.tenant_id
           ) is distinct from v_context_customer_id
       )
     ) then
    raise exception 'Customer conversation context belongs to another customer'
      using errcode = '23514';
  end if;

  if coalesce(new.is_primary, false) then
    -- Run before the outer row becomes primary. This keeps the partial unique
    -- index race-safe and synchronizes the scalar projection in one statement.
    update public.conversation_contexts other_context
    set is_primary = false
    where other_context.conversation_id = new.conversation_id
      and other_context.tenant_id = v_conversation.tenant_id
      and other_context.id is distinct from new.id
      and other_context.is_primary;

    update public.conversations conversation
    set context_type = new.context_type,
        context_id = new.context_id,
        updated_at = clock_timestamp()
    where conversation.id = new.conversation_id
      and conversation.tenant_id = v_conversation.tenant_id;
  elsif tg_op = 'UPDATE' and coalesce(old.is_primary, false) then
    update public.conversations conversation
    set context_type = null,
        context_id = null,
        updated_at = clock_timestamp()
    where conversation.id = old.conversation_id
      and conversation.tenant_id = old.tenant_id
      and conversation.context_type is not distinct from old.context_type
      and conversation.context_id is not distinct from old.context_id;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_conversation_context_counterparty_guard
  on public.conversation_contexts;
create trigger trg_conversation_context_counterparty_guard
before insert or update or delete on public.conversation_contexts
for each row execute function public.enforce_conversation_context_counterparty();

-- A staff reply is also read evidence for every inbound message inserted
-- before it. Persist the exact insertion cursor, not only wall-clock time.
create or replace function public.update_conversation_timestamp()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_sender_is_staff boolean := false;
  v_message_direction text := to_jsonb(new)->>'message_direction';
  v_staff_reply boolean := false;
begin
  if new.sender_id is not null then
    select exists (
      select 1
      from public.user_profiles profile
      where profile.user_id = new.sender_id
        and profile.tenant_id = new.tenant_id
        and coalesce(profile.is_active, true)
    ) into v_sender_is_staff;
  end if;

  v_staff_reply := v_sender_is_staff
    and coalesce(new.type, 'text') <> 'system'
    and coalesce(v_message_direction, 'outbound') <> 'inbound';

  update public.conversations conversation
  set last_message_at = greatest(
        coalesce(conversation.last_message_at, new.created_at),
        new.created_at
      ),
      updated_at = greatest(
        coalesce(conversation.updated_at, new.created_at),
        new.created_at
      ),
      staff_last_read_at = case
        when conversation.type = 'support'
          and v_staff_reply
          and new.message_sequence > coalesce(
            conversation.staff_last_read_message_sequence,
            0
          )
        then new.created_at
        else conversation.staff_last_read_at
      end,
      staff_last_read_message_sequence = case
        when conversation.type = 'support' and v_staff_reply
        then greatest(
          coalesce(conversation.staff_last_read_message_sequence, 0),
          new.message_sequence
        )
        else conversation.staff_last_read_message_sequence
      end
  where conversation.id = new.conversation_id
    and conversation.tenant_id = new.tenant_id;

  if not found then
    raise exception 'Message tenant does not match its parent conversation'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

create or replace view public.conversation_unread_counts
with (security_invoker = true, security_barrier = true)
as
with participant_scope as (
  select
    participant.conversation_id,
    participant.user_id,
    participant.last_read_at,
    participant.last_read_message_sequence,
    conversation.type as conversation_type,
    conversation.tenant_id,
    conversation.staff_last_read_at,
    conversation.staff_last_read_message_sequence,
    public.messaging_is_staff_in_tenant(conversation.tenant_id)
      as participant_is_staff
  from public.conversation_participants participant
  join public.conversations conversation
    on conversation.id = participant.conversation_id
  where participant.user_id = auth.uid()
    and participant.tenant_id = conversation.tenant_id
  union all
  select
    conversation.id as conversation_id,
    auth.uid() as user_id,
    null::timestamptz as last_read_at,
    null::bigint as last_read_message_sequence,
    conversation.type as conversation_type,
    conversation.tenant_id,
    conversation.staff_last_read_at,
    conversation.staff_last_read_message_sequence,
    true as participant_is_staff
  from public.conversations conversation
  where conversation.type = 'support'
    and public.messaging_is_staff_in_tenant(conversation.tenant_id)
    and public.messaging_can_read_conversation_messages(conversation.id)
    and not exists (
      select 1
      from public.conversation_participants participant
      where participant.conversation_id = conversation.id
        and participant.tenant_id = conversation.tenant_id
        and participant.user_id = auth.uid()
    )
), marker_scope as (
  select
    participant_scope.*,
    case
      when conversation_type = 'support' and participant_is_staff then
        greatest(
          last_read_message_sequence,
          staff_last_read_message_sequence
        )
      else last_read_message_sequence
    end as read_message_sequence,
    case
      when conversation_type = 'support'
        and participant_is_staff
        and last_read_message_sequence is null
        and staff_last_read_message_sequence is null
      then greatest(
        coalesce(last_read_at, '1970-01-01'::timestamptz),
        coalesce(staff_last_read_at, '1970-01-01'::timestamptz)
      )
      when conversation_type = 'support'
        and participant_is_staff
        and coalesce(staff_last_read_message_sequence, -1)
          >= coalesce(last_read_message_sequence, -1)
      then coalesce(staff_last_read_at, '1970-01-01'::timestamptz)
      else coalesce(last_read_at, '1970-01-01'::timestamptz)
    end as read_at
  from participant_scope
)
select
  marker.conversation_id,
  marker.user_id,
  coalesce(count(message.id), 0)::integer as unread_count
from marker_scope marker
left join public.messages message
  on message.conversation_id = marker.conversation_id
  and message.tenant_id = marker.tenant_id
  and (
    (
      marker.read_message_sequence is not null
      and message.message_sequence > marker.read_message_sequence
    )
    or (
      marker.read_message_sequence is null
      and message.created_at > marker.read_at
    )
  )
  and coalesce(message.type, 'text') <> 'system'
  and case
    when marker.conversation_type = 'support'
      and marker.participant_is_staff then
      message.message_direction = 'inbound'
      or (
        message.message_direction is null
        and (
          message.sender_id is null
          or exists (
            select 1
            from public.customers sender_customer
            where sender_customer.auth_user_id = message.sender_id
              and sender_customer.tenant_id = marker.tenant_id
          )
        )
      )
    else message.sender_id is distinct from marker.user_id
  end
group by marker.conversation_id, marker.user_id;

revoke all on table public.conversation_unread_counts
  from public, anon, authenticated;
grant select on table public.conversation_unread_counts to authenticated;

create table if not exists public.messaging_command_receipts (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  command_type text not null,
  idempotency_key text not null,
  actor_id uuid not null references auth.users(id) on delete restrict,
  request_fingerprint text not null,
  conversation_id uuid not null references public.conversations(id)
    on delete restrict,
  related_conversation_id uuid references public.conversations(id)
    on delete restrict,
  result jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default clock_timestamp(),
  unique (tenant_id, command_type, idempotency_key),
  check (nullif(btrim(idempotency_key), '') is not null),
  check (length(idempotency_key) <= 200),
  check (request_fingerprint ~ '^[0-9a-f]{32}$')
);

alter table public.messaging_command_receipts
  drop constraint if exists messaging_command_receipts_command_type_check;
alter table public.messaging_command_receipts
  add constraint messaging_command_receipts_command_type_check check (
    command_type in (
      'customer_support_request',
      'open_whatsapp_support',
      'staff_support_conversation',
      'staff_internal_conversation'
    )
  );

create index if not exists idx_messaging_command_receipts_conversation
  on public.messaging_command_receipts(tenant_id, conversation_id, created_at desc);

alter table public.messaging_command_receipts enable row level security;
revoke all on table public.messaging_command_receipts
  from public, anon, authenticated;
grant select on table public.messaging_command_receipts to service_role;

comment on table public.messaging_command_receipts is
  'Append-only receipts for replay-safe messaging aggregate commands and terminal WhatsApp rebinding.';

-- The previous RPC advanced to now(), which could include a message arriving
-- after the UI rendered. The new contract requires the exact last message the
-- user actually saw and advances monotonically only to its server timestamp.
drop function if exists public.mark_conversation_read(uuid);

create or replace function public.mark_conversation_read(
  p_conversation_id uuid,
  p_read_through_message_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_conversation public.conversations%rowtype;
  v_target_message public.messages%rowtype;
  v_is_staff boolean := false;
begin
  if v_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if p_read_through_message_id is null then
    raise exception 'Read-through message evidence is required'
      using errcode = '22023';
  end if;

  select conversation.*
  into v_conversation
  from public.conversations conversation
  where conversation.id = p_conversation_id;

  if not found then
    raise exception 'Conversation not found' using errcode = 'P0002';
  end if;

  if not public.messaging_can_read_conversation_messages(p_conversation_id) then
    raise exception 'Not allowed to mark this conversation as read'
      using errcode = '42501';
  end if;

  v_is_staff := public.messaging_is_staff_in_tenant(v_conversation.tenant_id);

  select message.*
  into v_target_message
  from public.messages message
  where message.id = p_read_through_message_id
    and message.conversation_id = p_conversation_id
    and message.tenant_id = v_conversation.tenant_id
    and coalesce(message.type, 'text') <> 'system'
    and case
      when v_conversation.type = 'support' and v_is_staff then
        message.message_direction = 'inbound'
        or (
          message.message_direction is null
          and (
            message.sender_id is null
            or exists (
              select 1
              from public.customers sender_customer
              where sender_customer.auth_user_id = message.sender_id
                and sender_customer.tenant_id = v_conversation.tenant_id
            )
          )
        )
      else message.sender_id is distinct from v_user_id
    end;

  if not found then
    raise exception 'Read-through message is not visible unread evidence'
      using errcode = '42501';
  end if;

  insert into public.conversation_participants (
    conversation_id,
    user_id,
    tenant_id,
    role,
    last_read_at,
    last_read_message_sequence
  ) values (
    v_conversation.id,
    v_user_id,
    v_conversation.tenant_id,
    case when v_is_staff then 'admin' else 'member' end,
    v_target_message.created_at,
    v_target_message.message_sequence
  )
  on conflict (conversation_id, user_id) do update
  set last_read_at = case
        when excluded.last_read_message_sequence > coalesce(
          public.conversation_participants.last_read_message_sequence,
          0
        ) then excluded.last_read_at
        else public.conversation_participants.last_read_at
      end,
      last_read_message_sequence = greatest(
        coalesce(
          public.conversation_participants.last_read_message_sequence,
          0
        ),
        excluded.last_read_message_sequence
      );

  if v_conversation.type = 'support' and v_is_staff then
    update public.conversations conversation
    set staff_last_read_at = case
          when v_target_message.message_sequence > coalesce(
            conversation.staff_last_read_message_sequence,
            0
          ) then v_target_message.created_at
          else conversation.staff_last_read_at
        end,
        staff_last_read_message_sequence = greatest(
          coalesce(conversation.staff_last_read_message_sequence, 0),
          v_target_message.message_sequence
        )
    where conversation.id = v_conversation.id
      and conversation.tenant_id = v_conversation.tenant_id;
  end if;

  return jsonb_build_object(
    'conversation_id', v_conversation.id,
    'read_through_message_id', v_target_message.id,
    'read_through_at', v_target_message.created_at,
    'read_through_sequence', v_target_message.message_sequence
  );
end;
$$;

-- Compatibility for an older client during rollout. It validates access but
-- deliberately performs no write because it cannot prove which message was
-- actually rendered. New clients use the exact two-argument command above.
create or replace function public.mark_conversation_read(
  p_conversation_id uuid
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if not public.messaging_can_read_conversation_messages(p_conversation_id) then
    raise exception 'Not allowed to mark this conversation as read'
      using errcode = '42501';
  end if;

  -- Safe no-op. Never infer a read boundary from server now().
  return;
end;
$$;

comment on function public.mark_conversation_read(uuid) is
  'Deprecated compatibility no-op. Upgrade clients to mark_conversation_read(uuid, uuid) for exact read evidence.';

-- Provider/webhook binding remains the low-level transport primitive. It now
-- serializes per contact and creates a fresh pending case when the previous
-- conversation is terminal instead of trying to reopen retained evidence.
create or replace function public.ensure_whatsapp_conversation_binding(
  p_tenant_id uuid,
  p_channel_id uuid,
  p_wa_id text,
  p_phone_number text default null,
  p_contact_name text default null,
  p_customer_id uuid default null,
  p_context_type text default null,
  p_context_id uuid default null,
  p_conversation_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_binding record;
  v_binding_found boolean := false;
  v_conversation public.conversations%rowtype;
  v_conversation_id uuid;
  v_previous_conversation_id uuid;
  v_binding_id uuid;
  v_customer_id uuid;
  v_context_customer_id uuid;
  v_customer_auth_user_id uuid;
  v_context_type text;
  v_context_id uuid;
  v_counterparty_type text;
  v_title text;
  v_wa_id text;
  v_role text := coalesce(auth.jwt()->>'role', auth.role(), '');
begin
  v_wa_id := public.normalize_whatsapp_phone(p_wa_id);
  if p_tenant_id is null or p_channel_id is null or v_wa_id is null then
    raise exception 'tenant, channel and wa_id are required'
      using errcode = '22023';
  end if;

  if v_role <> 'service_role'
     and not public.messaging_is_staff_in_tenant(p_tenant_id) then
    raise exception 'Messaging staff access is required'
      using errcode = '42501';
  end if;

  if not exists (
    select 1
    from public.whatsapp_channels channel
    where channel.id = p_channel_id
      and channel.tenant_id = p_tenant_id
      and channel.is_active
  ) then
    raise exception 'Active WhatsApp channel not found in tenant'
      using errcode = '42501';
  end if;

  v_context_type := nullif(
    lower(replace(btrim(coalesce(p_context_type, '')), '-', '_')),
    ''
  );
  v_context_id := p_context_id;

  if (v_context_type is null) is distinct from (v_context_id is null) then
    raise exception 'Context type and id must be supplied together'
      using errcode = '22023';
  end if;

  if v_context_type is not null
     and not public.messaging_context_belongs_to_tenant(
       v_context_type,
       v_context_id,
       p_tenant_id
     ) then
    raise exception 'Messaging context does not belong to tenant'
      using errcode = '42501';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(p_channel_id::text || ':' || v_wa_id, 0)
  );

  select
    binding.*,
    conversation.status as conversation_status,
    conversation.counterparty_type as conversation_counterparty_type
  into v_binding
  from public.whatsapp_conversation_bindings binding
  join public.conversations conversation
    on conversation.id = binding.conversation_id
   and conversation.tenant_id = binding.tenant_id
  where binding.channel_id = p_channel_id
    and binding.external_wa_id = v_wa_id
  for update of binding, conversation;

  v_binding_found := found;

  if v_binding_found
     and v_binding.customer_id is not null
     and p_customer_id is not null
     and v_binding.customer_id is distinct from p_customer_id then
    raise exception 'WhatsApp customer binding is immutable'
      using errcode = '23514';
  end if;

  v_customer_id := coalesce(
    p_customer_id,
    case when v_binding_found then v_binding.customer_id else null end
  );

  if v_context_type in ('customer', 'job', 'invoice', 'bike', 'order') then
    v_context_customer_id := public.messaging_context_customer_id(
      v_context_type,
      v_context_id,
      p_tenant_id
    );
    if v_context_customer_id is not null
       and v_customer_id is not null
       and v_context_customer_id is distinct from v_customer_id then
      raise exception 'WhatsApp customer does not own messaging context'
        using errcode = '23514';
    end if;
    v_customer_id := coalesce(v_customer_id, v_context_customer_id);
  end if;

  if v_customer_id is not null
     and not exists (
       select 1
       from public.customers customer
       where customer.id = v_customer_id
         and customer.tenant_id = p_tenant_id
         and coalesce(customer.is_active, true)
     ) then
    raise exception 'WhatsApp customer does not belong to tenant'
      using errcode = '42501';
  end if;

  v_counterparty_type := case
    when v_context_type in ('supplier', 'purchase_invoice') then 'supplier'
    when v_context_type is not null or v_customer_id is not null then 'customer'
    when v_binding_found then v_binding.conversation_counterparty_type
    else 'customer'
  end;

  if v_counterparty_type = 'supplier' and v_customer_id is not null then
    raise exception 'Supplier conversations cannot bind a customer identity'
      using errcode = '23514';
  end if;

  if v_binding_found then
    if v_binding.tenant_id is distinct from p_tenant_id then
      raise exception 'WhatsApp binding belongs to another tenant'
        using errcode = '42501';
    end if;

    if v_binding.conversation_counterparty_type is distinct from v_counterparty_type then
      raise exception 'WhatsApp contact is already bound to another counterparty capability'
        using errcode = '23514';
    end if;

    if coalesce(v_binding.conversation_status, '') in ('pending', 'active') then
      v_conversation_id := v_binding.conversation_id;
      v_binding_id := v_binding.id;
    else
      v_previous_conversation_id := v_binding.conversation_id;
    end if;
  elsif p_conversation_id is not null then
    select conversation.*
    into v_conversation
    from public.conversations conversation
    where conversation.id = p_conversation_id
      and conversation.tenant_id = p_tenant_id
    for update;

    if found and coalesce(v_conversation.status, '') in ('pending', 'active') then
      if v_conversation.counterparty_type is distinct from v_counterparty_type then
        raise exception 'Conversation counterparty capability does not match contact'
          using errcode = '23514';
      end if;
      v_conversation_id := v_conversation.id;
    end if;
  end if;

  if v_conversation_id is null then
    v_title := coalesce(
      nullif(btrim(p_contact_name), ''),
      nullif(btrim(p_phone_number), ''),
      v_wa_id,
      'WhatsApp'
    );

    insert into public.conversations (
      tenant_id,
      type,
      channel,
      counterparty_type,
      title,
      status,
      last_message_at,
      updated_at
    ) values (
      p_tenant_id,
      'support',
      'whatsapp',
      v_counterparty_type,
      v_title,
      'pending',
      now(),
      now()
    ) returning * into v_conversation;
    v_conversation_id := v_conversation.id;
  end if;

  if v_binding_id is null and v_previous_conversation_id is null then
    insert into public.whatsapp_conversation_bindings (
      tenant_id,
      conversation_id,
      channel_id,
      customer_id,
      external_wa_id,
      external_phone_number,
      contact_name
    ) values (
      p_tenant_id,
      v_conversation_id,
      p_channel_id,
      v_customer_id,
      v_wa_id,
      public.normalize_whatsapp_phone(p_phone_number),
      nullif(btrim(p_contact_name), '')
    ) returning id into v_binding_id;
  elsif v_previous_conversation_id is not null then
    update public.whatsapp_conversation_bindings
    set conversation_id = v_conversation_id,
        customer_id = coalesce(v_customer_id, customer_id),
        external_phone_number = coalesce(
          public.normalize_whatsapp_phone(p_phone_number),
          external_phone_number
        ),
        contact_name = coalesce(
          nullif(btrim(p_contact_name), ''),
          contact_name
        ),
        updated_at = now()
    where id = v_binding.id
    returning id into v_binding_id;
  end if;

  update public.whatsapp_conversation_bindings
  set customer_id = coalesce(v_customer_id, customer_id),
      external_phone_number = coalesce(
        public.normalize_whatsapp_phone(p_phone_number),
        external_phone_number
      ),
      contact_name = coalesce(
        nullif(btrim(p_contact_name), ''),
        contact_name
      ),
      updated_at = now()
  where id = v_binding_id;

  if v_customer_id is not null then
    select customer.auth_user_id
    into v_customer_auth_user_id
    from public.customers customer
    where customer.id = v_customer_id
      and customer.tenant_id = p_tenant_id;

    if v_customer_auth_user_id is not null then
      insert into public.conversation_participants (
        conversation_id,
        user_id,
        tenant_id,
        role,
        last_read_at
      ) values (
        v_conversation_id,
        v_customer_auth_user_id,
        p_tenant_id,
        'member',
        '1970-01-01'::timestamptz
      ) on conflict (conversation_id, user_id) do nothing;
    end if;
  end if;

  if v_context_type is null and v_customer_id is not null then
    v_context_type := 'customer';
    v_context_id := v_customer_id;
  end if;

  if v_context_type is not null then
    update public.conversation_contexts
    set is_primary = false
    where conversation_id = v_conversation_id
      and tenant_id = p_tenant_id;

    insert into public.conversation_contexts (
      conversation_id,
      context_type,
      context_id,
      is_primary,
      tenant_id
    ) values (
      v_conversation_id,
      v_context_type,
      v_context_id,
      true,
      p_tenant_id
    ) on conflict (conversation_id, context_type, context_id) do update
      set is_primary = true;
  end if;

  update public.conversations
  set title = case
        when nullif(btrim(p_contact_name), '') is not null
          and (
            title is null
            or btrim(title) = ''
            or public.normalize_whatsapp_phone(title) = v_wa_id
            or public.normalize_whatsapp_phone(title) =
              public.normalize_whatsapp_phone(p_phone_number)
          ) then btrim(p_contact_name)
        else coalesce(
          title,
          nullif(btrim(p_contact_name), ''),
          nullif(btrim(p_phone_number), ''),
          v_wa_id
        )
      end,
      channel = 'whatsapp',
      context_type = coalesce(v_context_type, context_type),
      context_id = coalesce(v_context_id, context_id),
      updated_at = now()
  where id = v_conversation_id;

  return jsonb_build_object(
    'binding_id', v_binding_id,
    'conversation_id', v_conversation_id,
    'customer_id', v_customer_id,
    'channel_id', p_channel_id,
    'counterparty_type', v_counterparty_type,
    'rebound_from_conversation_id', v_previous_conversation_id
  );
end;
$$;

create or replace function public.open_whatsapp_support_conversation(
  p_tenant_id uuid,
  p_channel_id uuid,
  p_wa_id text,
  p_phone_number text,
  p_contact_name text,
  p_customer_id uuid,
  p_context_type text,
  p_context_id uuid,
  p_idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor uuid := auth.uid();
  v_fingerprint text;
  v_existing public.messaging_command_receipts%rowtype;
  v_binding jsonb;
  v_conversation_id uuid;
  v_previous_conversation_id uuid;
  v_accepted_by uuid;
  v_accepted_at timestamptz;
  v_result jsonb;
begin
  if v_actor is null
     or not public.messaging_is_staff_in_tenant(p_tenant_id) then
    raise exception 'Messaging staff access is required'
      using errcode = '42501';
  end if;

  if nullif(btrim(p_idempotency_key), '') is null then
    raise exception 'Messaging idempotency key is required'
      using errcode = '22023';
  end if;

  v_fingerprint := md5(concat_ws(
    '|',
    p_tenant_id::text,
    p_channel_id::text,
    coalesce(public.normalize_whatsapp_phone(p_wa_id), ''),
    coalesce(public.normalize_whatsapp_phone(p_phone_number), ''),
    coalesce(btrim(p_contact_name), ''),
    coalesce(p_customer_id::text, ''),
    coalesce(lower(btrim(p_context_type)), ''),
    coalesce(p_context_id::text, '')
  ));

  perform pg_advisory_xact_lock(hashtextextended(
    p_tenant_id::text || ':open_whatsapp:' || btrim(p_idempotency_key),
    0
  ));

  select receipt.*
  into v_existing
  from public.messaging_command_receipts receipt
  where receipt.tenant_id = p_tenant_id
    and receipt.command_type = 'open_whatsapp_support'
    and receipt.idempotency_key = btrim(p_idempotency_key)
  for update;

  if found then
    if v_existing.actor_id is distinct from v_actor
       or v_existing.request_fingerprint is distinct from v_fingerprint then
      raise exception 'Messaging idempotency key belongs to another request'
        using errcode = '23514';
    end if;
    return v_existing.result || jsonb_build_object('replayed', true);
  end if;

  v_binding := public.ensure_whatsapp_conversation_binding(
    p_tenant_id,
    p_channel_id,
    p_wa_id,
    p_phone_number,
    p_contact_name,
    p_customer_id,
    p_context_type,
    p_context_id,
    null
  );

  v_conversation_id := (v_binding->>'conversation_id')::uuid;
  v_previous_conversation_id := nullif(
    v_binding->>'rebound_from_conversation_id',
    ''
  )::uuid;

  update public.conversations conversation
  set status = 'active',
      -- Treat the acceptance actor/timestamp as one evidence pair. A partial
      -- legacy pair is not reliable evidence, so repair both values together.
      accepted_by = case
        when conversation.accepted_by is null
          or conversation.accepted_at is null then v_actor
        else conversation.accepted_by
      end,
      accepted_at = case
        when conversation.accepted_by is null
          or conversation.accepted_at is null then clock_timestamp()
        else conversation.accepted_at
      end,
      updated_at = clock_timestamp()
  where conversation.id = v_conversation_id
    and conversation.tenant_id = p_tenant_id
    and conversation.status in ('pending', 'active')
  returning conversation.accepted_by, conversation.accepted_at
  into v_accepted_by, v_accepted_at;

  if not found then
    raise exception 'WhatsApp conversation is not open for staff'
      using errcode = '23514';
  end if;

  insert into public.conversation_participants (
    conversation_id,
    user_id,
    tenant_id,
    role,
    last_read_at
  ) values (
    v_conversation_id,
    v_actor,
    p_tenant_id,
    'admin',
    '1970-01-01'::timestamptz
  ) on conflict (conversation_id, user_id) do nothing;

  v_result := v_binding || jsonb_build_object(
    'conversation_id', v_conversation_id,
    'status', 'active',
    'accepted_by', v_accepted_by,
    'accepted_at', v_accepted_at,
    'replayed', false
  );

  insert into public.messaging_command_receipts (
    tenant_id,
    command_type,
    idempotency_key,
    actor_id,
    request_fingerprint,
    conversation_id,
    related_conversation_id,
    result
  ) values (
    p_tenant_id,
    'open_whatsapp_support',
    btrim(p_idempotency_key),
    v_actor,
    v_fingerprint,
    v_conversation_id,
    v_previous_conversation_id,
    v_result
  );

  return v_result;
end;
$$;

create or replace function public.create_customer_support_request(
  p_tenant_id uuid,
  p_initial_message text,
  p_context_type text,
  p_context_id uuid,
  p_idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor uuid := auth.uid();
  v_context_type text := nullif(
    lower(replace(btrim(coalesce(p_context_type, '')), '-', '_')),
    ''
  );
  v_initial_message text := nullif(btrim(p_initial_message), '');
  v_fingerprint text;
  v_existing public.messaging_command_receipts%rowtype;
  v_conversation_id uuid;
  v_message_id uuid;
  v_result jsonb;
begin
  if v_actor is null
     or not public.messaging_is_customer_in_tenant(p_tenant_id) then
    raise exception 'Customer messaging access is required'
      using errcode = '42501';
  end if;

  if v_initial_message is null or length(v_initial_message) > 8000 then
    raise exception 'Initial message must contain between 1 and 8000 characters'
      using errcode = '22023';
  end if;

  if nullif(btrim(p_idempotency_key), '') is null then
    raise exception 'Messaging idempotency key is required'
      using errcode = '22023';
  end if;

  if (v_context_type is null) is distinct from (p_context_id is null) then
    raise exception 'Context type and id must be supplied together'
      using errcode = '22023';
  end if;

  if v_context_type is not null
     and not public.messaging_customer_can_reference_context(
       v_context_type,
       p_context_id,
       p_tenant_id
     ) then
    raise exception 'Customer cannot reference this messaging context'
      using errcode = '42501';
  end if;

  v_fingerprint := md5(concat_ws(
    '|',
    p_tenant_id::text,
    v_actor::text,
    v_initial_message,
    coalesce(v_context_type, ''),
    coalesce(p_context_id::text, '')
  ));

  perform pg_advisory_xact_lock(hashtextextended(
    p_tenant_id::text || ':customer_support:' || btrim(p_idempotency_key),
    0
  ));

  select receipt.*
  into v_existing
  from public.messaging_command_receipts receipt
  where receipt.tenant_id = p_tenant_id
    and receipt.command_type = 'customer_support_request'
    and receipt.idempotency_key = btrim(p_idempotency_key)
  for update;

  if found then
    if v_existing.actor_id is distinct from v_actor
       or v_existing.request_fingerprint is distinct from v_fingerprint then
      raise exception 'Messaging idempotency key belongs to another request'
        using errcode = '23514';
    end if;
    return v_existing.result || jsonb_build_object('replayed', true);
  end if;

  insert into public.conversations (
    tenant_id,
    type,
    channel,
    counterparty_type,
    status,
    context_type,
    context_id,
    created_by,
    last_message_at,
    updated_at
  ) values (
    p_tenant_id,
    'support',
    'website_portal',
    'customer',
    'pending',
    v_context_type,
    p_context_id,
    v_actor,
    clock_timestamp(),
    clock_timestamp()
  ) returning id into v_conversation_id;

  insert into public.conversation_participants (
    conversation_id,
    user_id,
    tenant_id,
    role,
    last_read_at
  ) values (
    v_conversation_id,
    v_actor,
    p_tenant_id,
    'member',
    clock_timestamp()
  );

  if v_context_type is not null then
    insert into public.conversation_contexts (
      conversation_id,
      context_type,
      context_id,
      is_primary,
      added_by,
      tenant_id
    ) values (
      v_conversation_id,
      v_context_type,
      p_context_id,
      true,
      v_actor,
      p_tenant_id
    );
  end if;

  insert into public.messages (
    conversation_id,
    sender_id,
    tenant_id,
    content,
    type,
    message_direction,
    created_at
  ) values (
    v_conversation_id,
    v_actor,
    p_tenant_id,
    v_initial_message,
    'text',
    'inbound',
    clock_timestamp()
  ) returning id into v_message_id;

  v_result := jsonb_build_object(
    'conversation_id', v_conversation_id,
    'message_id', v_message_id,
    'status', 'pending',
    'counterparty_type', 'customer',
    'replayed', false
  );

  insert into public.messaging_command_receipts (
    tenant_id,
    command_type,
    idempotency_key,
    actor_id,
    request_fingerprint,
    conversation_id,
    result
  ) values (
    p_tenant_id,
    'customer_support_request',
    btrim(p_idempotency_key),
    v_actor,
    v_fingerprint,
    v_conversation_id,
    v_result
  );

  return v_result;
end;
$$;

-- Staff-created support conversations are one aggregate: conversation,
-- participant graph, optional customer identity and optional retained context
-- either all commit or none do. The durable receipt makes a lost ACK replay
-- return the exact committed conversation.
create or replace function public.create_staff_support_conversation(
  p_tenant_id uuid,
  p_title text,
  p_customer_user_id uuid,
  p_context_type text,
  p_context_id uuid,
  p_idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor uuid := auth.uid();
  v_requested_title text := nullif(btrim(coalesce(p_title, '')), '');
  v_conversation_title text;
  v_context_type text := nullif(
    lower(replace(btrim(coalesce(p_context_type, '')), '-', '_')),
    ''
  );
  v_customer_user_id uuid := p_customer_user_id;
  v_customer_id uuid;
  v_context_customer_id uuid;
  v_primary_context_type text;
  v_primary_context_id uuid;
  v_counterparty_type text;
  v_fingerprint text;
  v_existing public.messaging_command_receipts%rowtype;
  v_conversation_id uuid;
  v_now timestamptz := clock_timestamp();
  v_result jsonb;
begin
  if v_actor is null
     or not public.messaging_is_staff_in_tenant(p_tenant_id) then
    raise exception 'Messaging staff access is required'
      using errcode = '42501';
  end if;

  if v_requested_title is not null and length(v_requested_title) > 240 then
    raise exception 'Support conversation title is too long'
      using errcode = '22023';
  end if;

  if nullif(btrim(p_idempotency_key), '') is null
     or length(btrim(p_idempotency_key)) > 200 then
    raise exception 'Messaging idempotency key is required'
      using errcode = '22023';
  end if;

  if (v_context_type is null) is distinct from (p_context_id is null) then
    raise exception 'Context type and id must be supplied together'
      using errcode = '22023';
  end if;

  if v_context_type is not null
     and not public.messaging_context_belongs_to_tenant(
       v_context_type,
       p_context_id,
       p_tenant_id
     ) then
    raise exception 'Messaging context does not belong to tenant'
      using errcode = '42501';
  end if;

  v_counterparty_type := case
    when v_context_type in ('supplier', 'purchase_invoice') then 'supplier'
    else 'customer'
  end;

  if v_counterparty_type = 'supplier' and v_customer_user_id is not null then
    raise exception 'Supplier conversations cannot bind a customer identity'
      using errcode = '23514';
  end if;

  if v_customer_user_id is not null then
    if v_customer_user_id = v_actor then
      raise exception 'Staff actor cannot be the customer participant'
        using errcode = '23514';
    end if;

    select customer.id
    into v_customer_id
    from public.customers customer
    where customer.auth_user_id = v_customer_user_id
      and customer.tenant_id = p_tenant_id
      and coalesce(customer.is_active, true);

    if not found then
      raise exception 'Customer participant does not belong to tenant'
        using errcode = '42501';
    end if;
  end if;

  v_context_customer_id := public.messaging_context_customer_id(
    v_context_type,
    p_context_id,
    p_tenant_id
  );

  if v_context_customer_id is not null then
    if v_customer_id is not null
       and v_customer_id is distinct from v_context_customer_id then
      raise exception 'Customer participant does not own support context'
        using errcode = '42501';
    end if;

    v_customer_id := v_context_customer_id;
    if v_customer_user_id is null then
      select customer.auth_user_id
      into v_customer_user_id
      from public.customers customer
      where customer.id = v_customer_id
        and customer.tenant_id = p_tenant_id
        and coalesce(customer.is_active, true);
    end if;
  end if;

  if v_context_type in ('customer', 'job', 'invoice', 'bike', 'order')
     and v_context_customer_id is null then
    raise exception 'Customer support context has no customer owner'
      using errcode = '23514';
  end if;

  if v_counterparty_type = 'customer' and v_customer_user_id is null then
    raise exception 'Customer support conversation requires an active customer account'
      using errcode = '42501';
  end if;

  v_primary_context_type := coalesce(
    v_context_type,
    case when v_customer_id is not null then 'customer' end
  );
  v_primary_context_id := coalesce(
    p_context_id,
    v_customer_id
  );

  v_fingerprint := md5(concat_ws(
    '|',
    p_tenant_id::text,
    v_actor::text,
    coalesce(v_requested_title, ''),
    coalesce(p_customer_user_id::text, ''),
    coalesce(v_context_type, ''),
    coalesce(p_context_id::text, '')
  ));

  perform pg_advisory_xact_lock(hashtextextended(
    p_tenant_id::text || ':staff_support:' || btrim(p_idempotency_key),
    0
  ));

  select receipt.*
  into v_existing
  from public.messaging_command_receipts receipt
  where receipt.tenant_id = p_tenant_id
    and receipt.command_type = 'staff_support_conversation'
    and receipt.idempotency_key = btrim(p_idempotency_key)
  for update;

  if found then
    if v_existing.actor_id is distinct from v_actor
       or v_existing.request_fingerprint is distinct from v_fingerprint then
      raise exception 'Messaging idempotency key belongs to another request'
        using errcode = '23514';
    end if;
    return v_existing.result || jsonb_build_object('replayed', true);
  end if;

  v_conversation_title := coalesce(
    v_requested_title,
    (
      select nullif(btrim(customer.name), '')
      from public.customers customer
      where customer.id = v_customer_id
        and customer.tenant_id = p_tenant_id
    ),
    (
      select nullif(btrim(supplier.name), '')
      from public.suppliers supplier
      where v_context_type = 'supplier'
        and supplier.id = p_context_id
        and supplier.tenant_id = p_tenant_id
    ),
    (
      select coalesce(
        nullif(btrim(supplier.name), ''),
        nullif(btrim(purchase_invoice.supplier_name), '')
      )
      from public.purchase_invoices purchase_invoice
      left join public.suppliers supplier
        on supplier.id = purchase_invoice.supplier_id
       and supplier.tenant_id = purchase_invoice.tenant_id
      where v_context_type = 'purchase_invoice'
        and purchase_invoice.id = p_context_id
        and purchase_invoice.tenant_id = p_tenant_id
    ),
    'Soporte'
  );
  v_conversation_title := left(v_conversation_title, 240);

  insert into public.conversations (
    tenant_id,
    type,
    channel,
    counterparty_type,
    status,
    title,
    context_type,
    context_id,
    created_by,
    accepted_by,
    accepted_at,
    last_message_at,
    updated_at
  ) values (
    p_tenant_id,
    'support',
    'website_portal',
    v_counterparty_type,
    'active',
    v_conversation_title,
    v_primary_context_type,
    v_primary_context_id,
    v_actor,
    v_actor,
    v_now,
    v_now,
    v_now
  ) returning id into v_conversation_id;

  insert into public.conversation_participants (
    conversation_id,
    user_id,
    tenant_id,
    role,
    last_read_at
  ) values (
    v_conversation_id,
    v_actor,
    p_tenant_id,
    'admin',
    v_now
  );

  if v_customer_user_id is not null then
    insert into public.conversation_participants (
      conversation_id,
      user_id,
      tenant_id,
      role,
      last_read_at
    ) values (
      v_conversation_id,
      v_customer_user_id,
      p_tenant_id,
      'member',
      '1970-01-01'::timestamptz
    );
  end if;

  if v_context_type is not null then
    insert into public.conversation_contexts (
      conversation_id,
      context_type,
      context_id,
      is_primary,
      added_by,
      tenant_id
    ) values (
      v_conversation_id,
      v_context_type,
      p_context_id,
      true,
      v_actor,
      p_tenant_id
    );
  end if;

  if v_customer_id is not null and v_context_customer_id is null then
    insert into public.conversation_contexts (
      conversation_id,
      context_type,
      context_id,
      is_primary,
      added_by,
      tenant_id
    ) values (
      v_conversation_id,
      'customer',
      v_customer_id,
      v_context_type is null,
      v_actor,
      p_tenant_id
    );
  end if;

  v_result := jsonb_build_object(
    'conversation_id', v_conversation_id,
    'status', 'active',
    'counterparty_type', v_counterparty_type,
    'customer_user_id', v_customer_user_id,
    'reused', false,
    'replayed', false
  );

  insert into public.messaging_command_receipts (
    tenant_id,
    command_type,
    idempotency_key,
    actor_id,
    request_fingerprint,
    conversation_id,
    result
  ) values (
    p_tenant_id,
    'staff_support_conversation',
    btrim(p_idempotency_key),
    v_actor,
    v_fingerprint,
    v_conversation_id,
    v_result
  );

  return v_result;
end;
$$;

-- Direct employee chats reuse the exact active two-person graph under a pair
-- lock. Groups always create a new graph, but both modes use a durable command
-- receipt so retries after an uncertain acknowledgement are replay-only.
create or replace function public.create_staff_internal_conversation(
  p_tenant_id uuid,
  p_participant_ids uuid[],
  p_title text,
  p_is_group boolean,
  p_idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor uuid := auth.uid();
  v_title text := nullif(btrim(coalesce(p_title, '')), '');
  v_targets uuid[];
  v_target_count integer;
  v_valid_target_count integer;
  v_direct_target uuid;
  v_fingerprint text;
  v_existing public.messaging_command_receipts%rowtype;
  v_conversation_id uuid;
  v_reused boolean := false;
  v_now timestamptz := clock_timestamp();
  v_result jsonb;
begin
  if v_actor is null
     or not public.messaging_is_staff_in_tenant(p_tenant_id) then
    raise exception 'Messaging staff access is required'
      using errcode = '42501';
  end if;

  if p_is_group is null then
    raise exception 'Internal conversation mode is required'
      using errcode = '22023';
  end if;

  select coalesce(
    array_agg(distinct target_user_id order by target_user_id),
    '{}'::uuid[]
  )
  into v_targets
  from unnest(coalesce(p_participant_ids, '{}'::uuid[]))
    as target(target_user_id)
  where target_user_id is not null
    and target_user_id is distinct from v_actor;

  v_target_count := cardinality(v_targets);
  if v_target_count < 1 or v_target_count > 50 then
    raise exception 'Internal conversation requires between 1 and 50 other participants'
      using errcode = '22023';
  end if;

  if p_is_group then
    if v_title is null or length(v_title) > 120 then
      raise exception 'Group title must contain between 1 and 120 characters'
        using errcode = '22023';
    end if;
  else
    if v_target_count <> 1 then
      raise exception 'Direct internal conversation requires one other participant'
        using errcode = '22023';
    end if;
    if v_title is not null then
      raise exception 'Direct internal conversation cannot define a group title'
        using errcode = '22023';
    end if;
  end if;

  select count(distinct staff.user_id)::integer
  into v_valid_target_count
  from public.user_profiles staff
  where staff.tenant_id = p_tenant_id
    and staff.user_id = any(v_targets)
    and coalesce(staff.is_active, true);

  if v_valid_target_count <> v_target_count then
    raise exception 'Every internal participant must be active staff in tenant'
      using errcode = '42501';
  end if;

  if nullif(btrim(p_idempotency_key), '') is null
     or length(btrim(p_idempotency_key)) > 200 then
    raise exception 'Messaging idempotency key is required'
      using errcode = '22023';
  end if;

  v_fingerprint := md5(concat_ws(
    '|',
    p_tenant_id::text,
    v_actor::text,
    p_is_group::text,
    coalesce(v_title, ''),
    array_to_string(v_targets, ',')
  ));

  perform pg_advisory_xact_lock(hashtextextended(
    p_tenant_id::text || ':staff_internal:' || btrim(p_idempotency_key),
    0
  ));

  select receipt.*
  into v_existing
  from public.messaging_command_receipts receipt
  where receipt.tenant_id = p_tenant_id
    and receipt.command_type = 'staff_internal_conversation'
    and receipt.idempotency_key = btrim(p_idempotency_key)
  for update;

  if found then
    if v_existing.actor_id is distinct from v_actor
       or v_existing.request_fingerprint is distinct from v_fingerprint then
      raise exception 'Messaging idempotency key belongs to another request'
        using errcode = '23514';
    end if;
    return v_existing.result || jsonb_build_object('replayed', true);
  end if;

  if not p_is_group then
    v_direct_target := v_targets[1];
    perform pg_advisory_xact_lock(hashtextextended(
      p_tenant_id::text || ':internal_pair:' ||
      least(v_actor, v_direct_target)::text || ':' ||
      greatest(v_actor, v_direct_target)::text,
      0
    ));

    select conversation.id
    into v_conversation_id
    from public.conversations conversation
    where conversation.tenant_id = p_tenant_id
      and conversation.type = 'internal'
      and conversation.channel = 'internal'
      and conversation.status = 'active'
      and not conversation.is_group
      and exists (
        select 1
        from public.conversation_participants actor_participant
        where actor_participant.conversation_id = conversation.id
          and actor_participant.tenant_id = p_tenant_id
          and actor_participant.user_id = v_actor
      )
      and exists (
        select 1
        from public.conversation_participants target_participant
        where target_participant.conversation_id = conversation.id
          and target_participant.tenant_id = p_tenant_id
          and target_participant.user_id = v_direct_target
      )
      and (
        select count(*)
        from public.conversation_participants participant
        where participant.conversation_id = conversation.id
          and participant.tenant_id = p_tenant_id
      ) = 2
    order by conversation.last_message_at desc nulls last, conversation.id
    limit 1
    for update;

    v_reused := found;
  end if;

  if v_conversation_id is null then
    insert into public.conversations (
      tenant_id,
      type,
      channel,
      counterparty_type,
      status,
      is_group,
      title,
      created_by,
      last_message_at,
      updated_at
    ) values (
      p_tenant_id,
      'internal',
      'internal',
      'internal',
      'active',
      p_is_group,
      case when p_is_group then v_title else null end,
      v_actor,
      v_now,
      v_now
    ) returning id into v_conversation_id;

    insert into public.conversation_participants (
      conversation_id,
      user_id,
      tenant_id,
      role,
      last_read_at
    ) values (
      v_conversation_id,
      v_actor,
      p_tenant_id,
      'admin',
      v_now
    );

    insert into public.conversation_participants (
      conversation_id,
      user_id,
      tenant_id,
      role,
      last_read_at
    )
    select
      v_conversation_id,
      target_user_id,
      p_tenant_id,
      'member',
      v_now
    from unnest(v_targets) as target(target_user_id);
  end if;

  v_result := jsonb_build_object(
    'conversation_id', v_conversation_id,
    'status', 'active',
    'is_group', p_is_group,
    'participant_count', v_target_count + 1,
    'reused', v_reused,
    'replayed', false
  );

  insert into public.messaging_command_receipts (
    tenant_id,
    command_type,
    idempotency_key,
    actor_id,
    request_fingerprint,
    conversation_id,
    result
  ) values (
    p_tenant_id,
    'staff_internal_conversation',
    btrim(p_idempotency_key),
    v_actor,
    v_fingerprint,
    v_conversation_id,
    v_result
  );

  return v_result;
end;
$$;

-- Primary context changes are one transaction. Removing the primary link only
-- clears its projection; historical context rows remain available for audit.
create or replace function public.set_conversation_primary_context(
  p_conversation_id uuid,
  p_context_type text,
  p_context_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor uuid := auth.uid();
  v_conversation public.conversations%rowtype;
  v_context_type text := nullif(
    lower(replace(btrim(coalesce(p_context_type, '')), '-', '_')),
    ''
  );
begin
  if v_actor is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select conversation.*
  into v_conversation
  from public.conversations conversation
  where conversation.id = p_conversation_id
  for update;

  if not found then
    raise exception 'Conversation not found' using errcode = 'P0002';
  end if;

  if not public.messaging_can_manage_conversation(p_conversation_id) then
    raise exception 'Not authorized to change conversation context'
      using errcode = '42501';
  end if;

  if (v_context_type is null) is distinct from (p_context_id is null) then
    raise exception 'Context type and id must be supplied together'
      using errcode = '22023';
  end if;

  if v_context_type is not null
     and not public.messaging_context_belongs_to_tenant(
       v_context_type,
       p_context_id,
       v_conversation.tenant_id
     ) then
    raise exception 'Messaging context does not belong to tenant'
      using errcode = '42501';
  end if;

  update public.conversation_contexts
  set is_primary = false
  where conversation_id = v_conversation.id
    and tenant_id = v_conversation.tenant_id
    and is_primary;

  if v_context_type is not null then
    insert into public.conversation_contexts (
      conversation_id,
      context_type,
      context_id,
      is_primary,
      added_by,
      tenant_id
    ) values (
      v_conversation.id,
      v_context_type,
      p_context_id,
      true,
      v_actor,
      v_conversation.tenant_id
    ) on conflict (conversation_id, context_type, context_id) do update
      set is_primary = true;
  end if;

  update public.conversations
  set context_type = v_context_type,
      context_id = p_context_id,
      updated_at = clock_timestamp()
  where id = v_conversation.id
    and tenant_id = v_conversation.tenant_id;

  return jsonb_build_object(
    'conversation_id', v_conversation.id,
    'context_type', v_context_type,
    'context_id', p_context_id,
    'counterparty_type', v_conversation.counterparty_type
  );
end;
$$;

revoke all on function public.enforce_conversation_counterparty()
  from public, anon, authenticated, service_role;
revoke all on function public.enforce_conversation_context_counterparty()
  from public, anon, authenticated, service_role;
revoke all on function public.reconcile_supplier_customer_participants()
  from public, anon, authenticated, service_role;
revoke all on function public.messaging_context_customer_id(
  text, uuid, uuid
) from public, anon, authenticated, service_role;
revoke all on function public.messaging_context_customer_user_id(
  text, uuid, uuid
) from public, anon, authenticated, service_role;
revoke all on function public.messaging_is_customer_counterparty(
  uuid, uuid, uuid
) from public, anon, authenticated, service_role;

revoke all on function public.mark_conversation_read(uuid, uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.mark_conversation_read(uuid, uuid)
  to authenticated;
revoke all on function public.mark_conversation_read(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.mark_conversation_read(uuid)
  to authenticated;

-- Context history is append-only through the client API. Primary selection and
-- clearing use set_conversation_primary_context instead of deleting evidence.
revoke delete on table public.conversation_contexts from authenticated;
revoke update on table public.conversation_contexts from authenticated;
revoke insert on table public.conversation_contexts from authenticated;
revoke insert on table public.conversations from authenticated;

revoke all on function public.ensure_whatsapp_conversation_binding(
  uuid, uuid, text, text, text, uuid, text, uuid, uuid
) from public, anon, authenticated;
grant execute on function public.ensure_whatsapp_conversation_binding(
  uuid, uuid, text, text, text, uuid, text, uuid, uuid
) to service_role;

revoke all on function public.open_whatsapp_support_conversation(
  uuid, uuid, text, text, text, uuid, text, uuid, text
) from public, anon, authenticated, service_role;
grant execute on function public.open_whatsapp_support_conversation(
  uuid, uuid, text, text, text, uuid, text, uuid, text
) to authenticated;

revoke all on function public.create_customer_support_request(
  uuid, text, text, uuid, text
) from public, anon, authenticated, service_role;
grant execute on function public.create_customer_support_request(
  uuid, text, text, uuid, text
) to authenticated;

revoke all on function public.create_staff_support_conversation(
  uuid, text, uuid, text, uuid, text
) from public, anon, authenticated, service_role;
grant execute on function public.create_staff_support_conversation(
  uuid, text, uuid, text, uuid, text
) to authenticated;

revoke all on function public.create_staff_internal_conversation(
  uuid, uuid[], text, boolean, text
) from public, anon, authenticated, service_role;
grant execute on function public.create_staff_internal_conversation(
  uuid, uuid[], text, boolean, text
) to authenticated;

revoke all on function public.set_conversation_primary_context(
  uuid, text, uuid
) from public, anon, authenticated, service_role;
grant execute on function public.set_conversation_primary_context(
  uuid, text, uuid
) to authenticated;

commit;
