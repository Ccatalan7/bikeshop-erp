-- NUCLEAR FIX: Drop ALL policies on messaging tables and recreate
-- Run this in Supabase SQL Editor

-- 1. Drop ALL policies on conversations (any name)
DO $$
DECLARE
  pol RECORD;
BEGIN
  FOR pol IN SELECT policyname FROM pg_policies WHERE tablename = 'conversations' LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.conversations', pol.policyname);
    RAISE NOTICE 'Dropped policy: %', pol.policyname;
  END LOOP;
END $$;

-- 2. Drop ALL policies on conversation_participants
DO $$
DECLARE
  pol RECORD;
BEGIN
  FOR pol IN SELECT policyname FROM pg_policies WHERE tablename = 'conversation_participants' LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.conversation_participants', pol.policyname);
    RAISE NOTICE 'Dropped policy: %', pol.policyname;
  END LOOP;
END $$;

-- 3. Drop ALL policies on messages
DO $$
DECLARE
  pol RECORD;
BEGIN
  FOR pol IN SELECT policyname FROM pg_policies WHERE tablename = 'messages' LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.messages', pol.policyname);
    RAISE NOTICE 'Dropped policy: %', pol.policyname;
  END LOOP;
END $$;

-- 4. Drop ALL policies on conversation_contexts
DO $$
DECLARE
  pol RECORD;
BEGIN
  FOR pol IN SELECT policyname FROM pg_policies WHERE tablename = 'conversation_contexts' LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.conversation_contexts', pol.policyname);
    RAISE NOTICE 'Dropped policy: %', pol.policyname;
  END LOOP;
END $$;

-- 5. Now create SIMPLE, NON-RECURSIVE policies

-- CONVERSATIONS
CREATE POLICY "conv_insert" ON public.conversations FOR INSERT TO authenticated WITH CHECK (TRUE);

CREATE POLICY "conv_select" ON public.conversations FOR SELECT TO authenticated
  USING (
    created_by = auth.uid()
    OR id IN (SELECT conversation_id FROM public.conversation_participants WHERE user_id = auth.uid())
    OR (type = 'support' AND EXISTS (SELECT 1 FROM public.user_profiles WHERE user_id = auth.uid()))
  );

CREATE POLICY "conv_update" ON public.conversations FOR UPDATE TO authenticated
  USING (
    created_by = auth.uid()
    OR id IN (SELECT conversation_id FROM public.conversation_participants WHERE user_id = auth.uid())
    OR EXISTS (SELECT 1 FROM public.user_profiles WHERE user_id = auth.uid())
  );

-- PARTICIPANTS (NO self-reference!)
CREATE POLICY "part_select" ON public.conversation_participants FOR SELECT TO authenticated
  USING (
    user_id = auth.uid()
    OR conversation_id IN (SELECT id FROM public.conversations WHERE created_by = auth.uid())
    OR EXISTS (SELECT 1 FROM public.user_profiles WHERE user_id = auth.uid())
  );

CREATE POLICY "part_insert" ON public.conversation_participants FOR INSERT TO authenticated
  WITH CHECK (
    user_id = auth.uid()
    OR EXISTS (SELECT 1 FROM public.user_profiles WHERE user_id = auth.uid())
  );

-- MESSAGES
CREATE POLICY "msg_select" ON public.messages FOR SELECT TO authenticated
  USING (
    conversation_id IN (SELECT id FROM public.conversations WHERE created_by = auth.uid())
    OR conversation_id IN (SELECT conversation_id FROM public.conversation_participants WHERE user_id = auth.uid())
    OR EXISTS (SELECT 1 FROM public.user_profiles WHERE user_id = auth.uid())
  );

CREATE POLICY "msg_insert" ON public.messages FOR INSERT TO authenticated
  WITH CHECK (
    sender_id = auth.uid()
    AND (
      conversation_id IN (SELECT id FROM public.conversations WHERE created_by = auth.uid())
      OR conversation_id IN (SELECT conversation_id FROM public.conversation_participants WHERE user_id = auth.uid())
      OR EXISTS (SELECT 1 FROM public.user_profiles WHERE user_id = auth.uid())
    )
  );

-- CONTEXTS
CREATE POLICY "ctx_select" ON public.conversation_contexts FOR SELECT TO authenticated
  USING (
    conversation_id IN (SELECT id FROM public.conversations WHERE created_by = auth.uid())
    OR conversation_id IN (SELECT conversation_id FROM public.conversation_participants WHERE user_id = auth.uid())
    OR EXISTS (SELECT 1 FROM public.user_profiles WHERE user_id = auth.uid())
  );

CREATE POLICY "ctx_insert" ON public.conversation_contexts FOR INSERT TO authenticated
  WITH CHECK (
    conversation_id IN (SELECT id FROM public.conversations WHERE created_by = auth.uid())
    OR conversation_id IN (SELECT conversation_id FROM public.conversation_participants WHERE user_id = auth.uid())
    OR EXISTS (SELECT 1 FROM public.user_profiles WHERE user_id = auth.uid())
  );

-- Verify: List all policies
SELECT tablename, policyname FROM pg_policies 
WHERE tablename IN ('conversations', 'conversation_participants', 'messages', 'conversation_contexts')
ORDER BY tablename, policyname;
