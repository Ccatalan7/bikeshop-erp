-- Fix delete_conversation RPC to allow employees to delete support chats
-- even if they are not explicitly participants (shared inbox scenario)

CREATE OR REPLACE FUNCTION delete_conversation(p_conversation_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_is_participant BOOLEAN;
    v_is_employee BOOLEAN;
    v_user_role TEXT;
    v_chat_type TEXT;
BEGIN
    -- Get conversation details
    SELECT type INTO v_chat_type 
    FROM conversations 
    WHERE id = p_conversation_id;
    
    IF v_chat_type IS NULL THEN
        RETURN; -- Conversation does not exist
    END IF;

    -- Check if user is a participant using a more direct query
    IF EXISTS (
        SELECT 1 FROM conversation_participants
        WHERE conversation_id = p_conversation_id
        AND user_id = v_user_id
    ) THEN
        v_is_participant := true;
    ELSE
        v_is_participant := false;
    END IF;

    -- Check if user is an employee
    IF EXISTS (SELECT 1 FROM employees WHERE user_id = v_user_id) THEN
        v_is_employee := true;
    ELSE
        v_is_employee := false;
    END IF;

    -- Get user role
    SELECT role INTO v_user_role FROM user_profiles WHERE user_id = v_user_id;
    
    -- AUTH LOGIC:
    -- 1. Participant can delete (Standard)
    -- 2. Employee can delete 'support' chats (Shared Inbox)
    -- 3. Admins/Managers can delete any chat
    
    IF v_is_participant 
       OR (v_is_employee AND v_chat_type = 'support')
       OR (v_user_role IN ('admin', 'owner', 'manager')) THEN
        -- Allowed
        NULL;
    ELSE
        RAISE EXCEPTION 'User is not authorized to delete this conversation (Code: P0001)';
    END IF;
    
    -- DELETE OPERATIONS
    
    -- 1. Messages (Foreign Key)
    DELETE FROM messages WHERE conversation_id = p_conversation_id;
    
    -- 2. Participants
    DELETE FROM conversation_participants WHERE conversation_id = p_conversation_id;
    
    -- 3. Conversation
    DELETE FROM conversations WHERE id = p_conversation_id;
    
END;
$$;

GRANT EXECUTE ON FUNCTION delete_conversation(UUID) TO authenticated;
