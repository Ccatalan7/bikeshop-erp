-- TRULY ISOLATED POLICIES - NO CROSS-REFERENCES
-- Each table's policy ONLY references user_profiles (which has no RLS on our tables)

-- 1. Drop ALL existing policies
DO $$
DECLARE pol RECORD;
BEGIN
  FOR pol IN SELECT policyname FROM pg_policies WHERE tablename = 'conversations' LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.conversations', pol.policyname);
  END LOOP;
  FOR pol IN SELECT policyname FROM pg_policies WHERE tablename = 'conversation_participants' LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.conversation_participants', pol.policyname);
  END LOOP;
  FOR pol IN SELECT policyname FROM pg_policies WHERE tablename = 'messages' LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.messages', pol.policyname);
  END LOOP;
  FOR pol IN SELECT policyname FROM pg_policies WHERE tablename = 'conversation_contexts' LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.conversation_contexts', pol.policyname);
  END LOOP;
END $$;

-- 2. CONVERSATIONS - Only check created_by and user_profiles (NO participants reference!)
CREATE POLICY "conv_insert" ON public.conversations FOR INSERT TO authenticated WITH CHECK (TRUE);

CREATE POLICY "conv_select" ON public.conversations FOR SELECT TO authenticated
  USING (
    created_by = auth.uid()  -- Creator can see
    OR EXISTS (SELECT 1 FROM public.user_profiles WHERE user_id = auth.uid())  -- Employees see all
  );

CREATE POLICY "conv_update" ON public.conversations FOR UPDATE TO authenticated
  USING (
    created_by = auth.uid()
    OR EXISTS (SELECT 1 FROM public.user_profiles WHERE user_id = auth.uid())
  );

-- 3. PARTICIPANTS - Only check user_id directly (NO conversations reference!)
CREATE POLICY "part_select" ON public.conversation_participants FOR SELECT TO authenticated
  USING (
    user_id = auth.uid()  -- Can see your own participations
    OR EXISTS (SELECT 1 FROM public.user_profiles WHERE user_id = auth.uid())  -- Employees see all
  );

CREATE POLICY "part_insert" ON public.conversation_participants FOR INSERT TO authenticated
  WITH CHECK (
    user_id = auth.uid()  -- Can only add yourself
    OR EXISTS (SELECT 1 FROM public.user_profiles WHERE user_id = auth.uid())  -- Employees can add anyone
  );

-- 4. MESSAGES - Reference conversations only for created_by (safe, no circular)
CREATE POLICY "msg_select" ON public.messages FOR SELECT TO authenticated
  USING (
    sender_id = auth.uid()  -- Can see your own messages
    OR EXISTS (SELECT 1 FROM public.user_profiles WHERE user_id = auth.uid())  -- Employees see all
  );

CREATE POLICY "msg_insert" ON public.messages FOR INSERT TO authenticated
  WITH CHECK (
    sender_id = auth.uid()  -- Must be sender
  );

-- 5. CONTEXTS - Simple employee-only
CREATE POLICY "ctx_select" ON public.conversation_contexts FOR SELECT TO authenticated
  USING (
    EXISTS (SELECT 1 FROM public.user_profiles WHERE user_id = auth.uid())
    OR added_by = auth.uid()
  );

CREATE POLICY "ctx_insert" ON public.conversation_contexts FOR INSERT TO authenticated
  WITH CHECK (
    added_by = auth.uid()
    OR EXISTS (SELECT 1 FROM public.user_profiles WHERE user_id = auth.uid())
  );

-- Verify
SELECT tablename, policyname FROM pg_policies 
WHERE tablename IN ('conversations', 'conversation_participants', 'messages', 'conversation_contexts')
ORDER BY tablename, policyname;
