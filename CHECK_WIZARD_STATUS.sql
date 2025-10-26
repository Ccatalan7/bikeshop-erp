-- Check if wizard completed and saved template
-- Run this in Supabase SQL Editor

-- 1. Check website status
SELECT 
  tenant_id,
  website_status,
  website_enabled,
  website_subdomain,
  website_url
FROM company_settings
WHERE website_status IS NOT NULL OR website_enabled = true;

-- 2. Check if home page exists for any tenant
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
WHERE page_name = 'home'
ORDER BY created_at DESC;

-- 3. If no pages exist, check if wizard settings were saved
SELECT 
  tenant_id,
  key,
  value,
  updated_at
FROM company_settings
WHERE key IN ('website_shop_name', 'website_template', 'website_description')
ORDER BY tenant_id, key;

-- 4. Get your tenant_id (replace with your email)
SELECT 
  id as tenant_id,
  email
FROM auth.users
WHERE email = 'YOUR_EMAIL_HERE'
LIMIT 1;
