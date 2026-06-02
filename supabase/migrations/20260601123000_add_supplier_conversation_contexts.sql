alter table public.conversation_contexts
  drop constraint if exists conversation_contexts_context_type_check;

alter table public.conversation_contexts
  add constraint conversation_contexts_context_type_check
  check (
    context_type in (
      'job',
      'invoice',
      'bike',
      'product',
      'order',
      'customer',
      'supplier',
      'purchase_invoice'
    )
  );
