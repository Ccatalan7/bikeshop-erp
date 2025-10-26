-- Check if website_pages has data after wizard completion
-- Run in Supabase SQL Editor: https://supabase.com/dashboard/project/xzdvtzdqjeyqxnkqprtf/sql

-- Check your tenant's website pages
SELECT 
  id,
  tenant_id,
  page_name,
  LENGTH(html_content) as html_length,
  LENGTH(css_content) as css_length,
  is_published,
  created_at,
  updated_at
FROM website_pages
WHERE tenant_id = '5fb195aa-2ec5-4a5d-b057-ed61156312ec'
ORDER BY created_at DESC;
-- Expected: 1 row with page_name='home', html_length > 0, css_length > 0

-- If no data, check if the table even has any rows
SELECT COUNT(*) as total_rows FROM website_pages;

-- Check RLS policies are not blocking
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims TO '{"tenant_id": "5fb195aa-2ec5-4a5d-b057-ed61156312ec"}';

SELECT * FROM website_pages 
WHERE tenant_id = '5fb195aa-2ec5-4a5d-b057-ed61156312ec'
  AND page_name = 'home';
