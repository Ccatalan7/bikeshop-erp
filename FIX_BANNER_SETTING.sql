-- Fix the top banner setting that's stuck on 'true'
-- Run this in Supabase SQL Editor

-- Update to 'false' for your tenant
update website_settings 
set value = 'false', 
    updated_at = now()
where key = 'header_show_top_banner'
  and tenant_id = '5443b130-cc28-45af-a420-cd500b288890';

-- Verify the change
select tenant_id, key, value, updated_at 
from website_settings 
where key = 'header_show_top_banner'
  and tenant_id = '5443b130-cc28-45af-a420-cd500b288890';
