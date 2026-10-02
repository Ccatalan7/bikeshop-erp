select key, form_contract->'allowed_options' ao
from public.spec_templates
where tenant_id is null and is_active and form_contract ? 'allowed_options'
