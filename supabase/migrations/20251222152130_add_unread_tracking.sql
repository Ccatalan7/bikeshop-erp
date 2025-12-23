-- Add last_read_at column to track when each user last viewed a conversation
ALTER TABLE conversation_participants 
ADD COLUMN IF NOT EXISTS last_read_at TIMESTAMPTZ DEFAULT NOW();

-- Create index for performance on message queries
CREATE INDEX IF NOT EXISTS idx_messages_conversation_created 
ON messages(conversation_id, created_at);

-- Create view to calculate unread counts per user per conversation
CREATE OR REPLACE VIEW conversation_unread_counts AS
SELECT 
  cp.conversation_id,
  cp.user_id,
  COALESCE(COUNT(m.id), 0)::integer AS unread_count
FROM conversation_participants cp
LEFT JOIN messages m 
  ON m.conversation_id = cp.conversation_id 
  AND m.created_at > COALESCE(cp.last_read_at, '1970-01-01'::timestamptz)
  AND m.sender_id != cp.user_id  -- Don't count own messages as unread
GROUP BY cp.conversation_id, cp.user_id;

-- Grant access to the view
GRANT SELECT ON conversation_unread_counts TO authenticated;
