-- =====================================================
-- Quick Create Account 1155: Inventario en Tránsito
-- =====================================================
-- Run this in Supabase SQL Editor
-- =====================================================

INSERT INTO accounts (
  id,
  code,
  name,
  type,
  is_active,
  created_at,
  updated_at
)
VALUES (
  gen_random_uuid(),
  '1155',
  'Inventario en Tránsito',
  'asset',
  true,
  NOW(),
  NOW()
)
ON CONFLICT (code) DO UPDATE
SET 
  name = EXCLUDED.name,
  type = EXCLUDED.type,
  is_active = EXCLUDED.is_active,
  updated_at = NOW();

-- Verify it was created
SELECT code, name, type, is_active 
FROM accounts 
WHERE code = '1155';
