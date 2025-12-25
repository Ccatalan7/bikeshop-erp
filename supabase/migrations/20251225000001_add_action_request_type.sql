-- Add 'action_request' to allowed message types
-- This is needed for Phase 3 - Customer Action Buttons feature

-- Drop the existing constraint
ALTER TABLE messages DROP CONSTRAINT IF EXISTS messages_type_check;

-- Add updated constraint with 'action_request' type
ALTER TABLE messages ADD CONSTRAINT messages_type_check 
  CHECK (type IN ('text', 'image', 'file', 'system', 'action_request'));
