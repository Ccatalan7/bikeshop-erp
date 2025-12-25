-- Migration: Add chat request flow support to conversations
-- Supports: pending/active/resolved/rejected status, acceptance tracking, multi-context

-- 1. Add status column for request flow
ALTER TABLE public.conversations
ADD COLUMN IF NOT EXISTS status text DEFAULT 'active' 
  CHECK (status IN ('pending', 'active', 'resolved', 'rejected'));

-- 2. Add acceptance tracking columns
ALTER TABLE public.conversations
ADD COLUMN IF NOT EXISTS accepted_by uuid REFERENCES auth.users(id);

ALTER TABLE public.conversations
ADD COLUMN IF NOT EXISTS accepted_at timestamptz;

ALTER TABLE public.conversations
ADD COLUMN IF NOT EXISTS reject_reason text;

-- 3. Create conversation_contexts table for multi-context support
CREATE TABLE IF NOT EXISTS public.conversation_contexts (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  conversation_id uuid REFERENCES public.conversations(id) ON DELETE CASCADE,
  context_type text NOT NULL CHECK (context_type IN ('job', 'invoice', 'bike', 'product', 'order', 'customer')),
  context_id uuid NOT NULL,
  is_primary boolean DEFAULT false,
  added_by uuid REFERENCES auth.users(id),
  added_at timestamptz DEFAULT now(),
  tenant_id uuid REFERENCES public.tenants(id) DEFAULT user_tenant_id(),
  UNIQUE(conversation_id, context_type, context_id)
);

-- Index for fast lookups
CREATE INDEX IF NOT EXISTS idx_conv_contexts_lookup 
ON public.conversation_contexts(context_type, context_id);

CREATE INDEX IF NOT EXISTS idx_conv_contexts_conversation 
ON public.conversation_contexts(conversation_id);

-- 4. RLS for conversation_contexts
ALTER TABLE public.conversation_contexts ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view contexts of their conversations"
  ON public.conversation_contexts FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.conversation_participants cp
      WHERE cp.conversation_id = conversation_contexts.conversation_id
      AND cp.user_id = auth.uid()
    )
    OR
    ( -- Employees can view contexts of support tickets
       EXISTS (SELECT 1 FROM public.conversations c WHERE c.id = conversation_contexts.conversation_id AND c.type = 'support') AND
       EXISTS (SELECT 1 FROM public.user_profiles WHERE user_id = auth.uid() AND role IN ('admin', 'manager', 'cashier', 'mechanic', 'accountant'))
    )
  );

CREATE POLICY "Participants can add contexts"
  ON public.conversation_contexts FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.conversation_participants cp
      WHERE cp.conversation_id = conversation_contexts.conversation_id
      AND cp.user_id = auth.uid()
    )
    OR
    EXISTS (SELECT 1 FROM public.user_profiles WHERE user_id = auth.uid() AND role IN ('admin', 'manager', 'mechanic'))
  );

-- 5. Update conversations policy to allow customers to see pending status
-- (Existing policy already allows participants to see their conversations)

-- 6. Grant permissions
GRANT SELECT, INSERT ON public.conversation_contexts TO authenticated;

-- 7. Index for filtering by status
CREATE INDEX IF NOT EXISTS idx_conversations_status ON public.conversations(status);
CREATE INDEX IF NOT EXISTS idx_conversations_type_status ON public.conversations(type, status);
