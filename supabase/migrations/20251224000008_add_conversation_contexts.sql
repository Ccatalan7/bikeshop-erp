create table if not exists public.conversation_contexts (
  id uuid default gen_random_uuid() primary key,
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  context_type text not null, -- 'job', 'invoice'
  context_id uuid not null, -- Foreign key typically, but generic here
  is_primary boolean default false,
  added_by uuid references auth.users(id),
  created_at timestamptz default now()
);

-- Index for faster joins
create index if not exists idx_conversation_contexts_conv_id on public.conversation_contexts(conversation_id);
create index if not exists idx_conversation_contexts_context on public.conversation_contexts(context_type, context_id);

-- RLS
alter table public.conversation_contexts enable row level security;

-- Policies
create policy "Users can view contexts for conversations they are part of"
  on public.conversation_contexts for select
  using (
    exists (
      select 1 from public.conversation_participants
      where conversation_participants.conversation_id = conversation_contexts.conversation_id
      and conversation_participants.user_id = auth.uid()
    )
  );

create policy "Users can add contexts to conversations they are part of"
  on public.conversation_contexts for insert
  with check (
    exists (
        select 1 from public.conversation_participants
        where conversation_participants.conversation_id = conversation_contexts.conversation_id
        and conversation_participants.user_id = auth.uid()
    )
  );
