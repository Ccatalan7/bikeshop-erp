-- FIX: Infinite recursion in conversation_participants RLS
-- The is_conversation_participant() function queries conversation_participants,
-- which triggers its RLS policy, which might call the function again = LOOP

-- Solution: Make policies NOT use recursive function calls

-- 1. Drop all existing problematic policies
DROP POLICY IF EXISTS "Users can view conversations they participate in" ON public.conversations;
DROP POLICY IF EXISTS "Users can create conversations" ON public.conversations;
DROP POLICY IF EXISTS "Users can update their conversations" ON public.conversations;
DROP POLICY IF EXISTS "Users can view participants of their conversations" ON public.conversation_participants;
DROP POLICY IF EXISTS "Users can join conversations" ON public.conversation_participants;
DROP POLICY IF EXISTS "Users can add themselves as participants" ON public.conversation_participants;
DROP POLICY IF EXISTS "Users can view messages in their conversations" ON public.messages;
DROP POLICY IF EXISTS "Users can insert messages in their conversations" ON public.messages;
DROP POLICY IF EXISTS "Users can send messages" ON public.messages;

-- 2. CONVERSATIONS policies (simple, no recursion)
CREATE POLICY "Users can create conversations"
  ON public.conversations FOR INSERT
  TO authenticated
  WITH CHECK (TRUE);  -- Any authenticated user can create

CREATE POLICY "Users can view conversations they participate in"
  ON public.conversations FOR SELECT
  TO authenticated
  USING (
    created_by = auth.uid()
    OR id IN (SELECT conversation_id FROM public.conversation_participants WHERE user_id = auth.uid())
    OR (type = 'support' AND EXISTS (SELECT 1 FROM public.user_profiles WHERE user_id = auth.uid()))
  );

CREATE POLICY "Users can update their conversations"
  ON public.conversations FOR UPDATE
  TO authenticated
  USING (
    created_by = auth.uid()
    OR id IN (SELECT conversation_id FROM public.conversation_participants WHERE user_id = auth.uid())
    OR EXISTS (SELECT 1 FROM public.user_profiles WHERE user_id = auth.uid())
  );

-- 3. CONVERSATION_PARTICIPANTS policies (CRITICAL: must not reference itself!)
CREATE POLICY "Users can view participants of their conversations"
  ON public.conversation_participants FOR SELECT
  TO authenticated
  USING (
    user_id = auth.uid()  -- Can see your own participations
    OR conversation_id IN (
      SELECT id FROM public.conversations WHERE created_by = auth.uid()
    )  -- Can see participants of conversations you created
    OR EXISTS (SELECT 1 FROM public.user_profiles WHERE user_id = auth.uid())  -- Employees see all
  );

CREATE POLICY "Users can add themselves as participants"
  ON public.conversation_participants FOR INSERT
  TO authenticated
  WITH CHECK (
    user_id = auth.uid()  -- Can only add yourself
    OR EXISTS (SELECT 1 FROM public.user_profiles WHERE user_id = auth.uid())  -- Or employees can add anyone
  );

-- 4. MESSAGES policies
CREATE POLICY "Users can view messages in their conversations"
  ON public.messages FOR SELECT
  TO authenticated
  USING (
    conversation_id IN (
      SELECT id FROM public.conversations WHERE created_by = auth.uid()
    )
    OR conversation_id IN (
      SELECT conversation_id FROM public.conversation_participants WHERE user_id = auth.uid()
    )
    OR (
      conversation_id IN (SELECT id FROM public.conversations WHERE type = 'support')
      AND EXISTS (SELECT 1 FROM public.user_profiles WHERE user_id = auth.uid())
    )
  );

CREATE POLICY "Users can send messages"
  ON public.messages FOR INSERT
  TO authenticated
  WITH CHECK (
    sender_id = auth.uid()
    AND (
      conversation_id IN (SELECT id FROM public.conversations WHERE created_by = auth.uid())
      OR conversation_id IN (SELECT conversation_id FROM public.conversation_participants WHERE user_id = auth.uid())
      OR EXISTS (SELECT 1 FROM public.user_profiles WHERE user_id = auth.uid())
    )
  );
