-- Migration to create the Unified Messaging System
-- Includes conversations, participants, messages tables and Row Level Security (RLS) Policies

-- 1. Create conversations table
create table public.conversations (
  id uuid default gen_random_uuid() primary key,
  tenant_id uuid references public.tenants(id) default user_tenant_id(),
  type text not null check (type in ('internal', 'support')),
  title text, -- Optional title for group chats or ticket subjects
  context_type text, -- 'job', 'invoice', etc.
  context_id uuid, -- ID of the related entity
  last_message_at timestamptz default now(),
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- 2. Create conversation_participants table
create table public.conversation_participants (
  conversation_id uuid references public.conversations(id) on delete cascade,
  user_id uuid references auth.users(id) on delete cascade,
  tenant_id uuid references public.tenants(id) default user_tenant_id(),
  role text default 'member' check (role in ('admin', 'member')),
  last_read_at timestamptz default now(),
  created_at timestamptz default now(),
  primary key (conversation_id, user_id)
);

-- 3. Create messages table
create table public.messages (
  id uuid default gen_random_uuid() primary key,
  conversation_id uuid references public.conversations(id) on delete cascade,
  sender_id uuid references auth.users(id) on delete set null, -- Null if system message
  tenant_id uuid references public.tenants(id) default user_tenant_id(),
  content text,
  type text default 'text' check (type in ('text', 'image', 'file', 'system')),
  metadata jsonb default '{}'::jsonb, -- Store file URLs, payment button config, etc.
  created_at timestamptz default now()
);


-- Indexes for performance
create index idx_conversations_tenant on public.conversations(tenant_id);
create index idx_participants_user on public.conversation_participants(user_id);
create index idx_messages_conversation on public.messages(conversation_id);
create index idx_messages_created_at on public.messages(created_at);

-- Update last_message_at trigger
create or replace function update_conversation_timestamp()
returns trigger as $$
begin
  update public.conversations
  set last_message_at = new.created_at,
      updated_at = new.created_at
  where id = new.conversation_id;
  return new;
end;
$$ language plpgsql;

create trigger trg_update_conversation_timestamp
after insert on public.messages
for each row execute function update_conversation_timestamp();


-- ROW LEVEL SECURITY (RLS) POLICIES

-- Enable RLS
alter table public.conversations enable row level security;
alter table public.conversation_participants enable row level security;
alter table public.messages enable row level security;

-- Policies for CONVERSATIONS
-- Users can see conversations they are a participant in.
-- Employees (with correct permissions) can see all 'internal' conversations or 'support' conversations within their tenant.

create policy "Users can view conversations they participate in"
  on public.conversations for select
  using (
    exists (
      select 1 from public.conversation_participants cp
      where cp.conversation_id = conversations.id
      and cp.user_id = auth.uid()
    )
    OR
    ( -- Employees can view support tickets even if not explicitly a participant yet (to pick them up)
      type = 'support' AND 
      exists (select 1 from public.user_profiles where user_id = auth.uid() and role in ('admin', 'manager', 'cashier', 'mechanic', 'accountant'))
    )
  );

create policy "Users can create conversations"
  on public.conversations for insert
  with check (
    tenant_id = user_tenant_id()
  );


-- Policies for PARTICIPANTS
create policy "Users can view participants of their conversations"
  on public.conversation_participants for select
  using (
    exists (
      select 1 from public.conversation_participants cp
      where cp.conversation_id = conversation_participants.conversation_id
      and cp.user_id = auth.uid()
    )
    OR
    ( -- Employees can view participants of any support ticket
       exists (select 1 from public.conversations c where c.id = conversation_participants.conversation_id and c.type = 'support') AND
       exists (select 1 from public.user_profiles where user_id = auth.uid() and role in ('admin', 'manager', 'cashier', 'mechanic', 'accountant'))
    )
  );

create policy "Users can join conversations"
  on public.conversation_participants for insert
  with check (
    auth.uid() = user_id -- Only join yourself (unless admin logic added later)
    OR
    exists (select 1 from public.user_profiles where user_id = auth.uid() and role in ('admin', 'manager')) -- Admins can add others
  );


-- Policies for MESSAGES
create policy "Users can view messages in their conversations"
  on public.messages for select
  using (
    exists (
      select 1 from public.conversation_participants cp
      where cp.conversation_id = messages.conversation_id
      and cp.user_id = auth.uid()
    )
    OR
    ( -- Employees can view messages of any support ticket
       exists (select 1 from public.conversations c where c.id = messages.conversation_id and c.type = 'support') AND
       exists (select 1 from public.user_profiles where user_id = auth.uid() and role in ('admin', 'manager', 'cashier', 'mechanic', 'accountant'))
    )
  );

create policy "Users can insert messages in their conversations"
  on public.messages for insert
  with check (
    sender_id = auth.uid() AND
    (
        exists (
        select 1 from public.conversation_participants cp
        where cp.conversation_id = messages.conversation_id
        and cp.user_id = auth.uid()
        )
        OR
        ( -- Employees can reply to support tickets
        exists (select 1 from public.conversations c where c.id = messages.conversation_id and c.type = 'support') AND
        exists (select 1 from public.user_profiles where user_id = auth.uid() and role in ('admin', 'manager', 'cashier', 'mechanic', 'accountant'))
        )
    )
  );

-- Grant permissions (assuming 'authenticated' role uses these)
grant select, insert, update on public.conversations to authenticated;
grant select, insert, update on public.conversation_participants to authenticated;
grant select, insert on public.messages to authenticated;
