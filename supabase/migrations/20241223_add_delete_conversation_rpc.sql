-- Migration: Add delete_conversation RPC function
-- This function allows users to delete conversations they are participants of

CREATE OR REPLACE FUNCTION delete_conversation(p_conversation_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_is_participant BOOLEAN;
BEGIN
    -- Check if user is a participant of this conversation
    SELECT EXISTS(
        SELECT 1 FROM conversation_participants
        WHERE conversation_id = p_conversation_id
        AND user_id = v_user_id
    ) INTO v_is_participant;
    
    IF NOT v_is_participant THEN
        RAISE EXCEPTION 'User is not a participant of this conversation';
    END IF;
    
    -- Delete messages first (foreign key constraint)
    DELETE FROM messages WHERE conversation_id = p_conversation_id;
    
    -- Delete participants
    DELETE FROM conversation_participants WHERE conversation_id = p_conversation_id;
    
    -- Delete the conversation
    DELETE FROM conversations WHERE id = p_conversation_id;
END;
$$;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION delete_conversation(UUID) TO authenticated;
