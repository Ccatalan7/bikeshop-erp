-- Reset top banner setting to force new default (false)
-- Run this in Supabase SQL Editor

-- Option 1: Delete the setting (will use default 'false')
delete from website_settings 
where setting_key = 'header_show_top_banner';

-- Option 2: Update to 'false' explicitly
-- update website_settings 
-- set setting_value = 'false'
-- where setting_key = 'header_show_top_banner';

-- Verify the change
select tenant_id, setting_key, setting_value 
from website_settings 
where setting_key = 'header_show_top_banner';
