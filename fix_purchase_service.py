import re

with open('lib/modules/purchases/services/purchase_service.dart', 'r') as f:
    content = f.read()

content = content.replace("await _db.client", "await _supabase")
content = content.replace("eq('tenant_id', _db.tenantId)", "eq('tenant_id', await _tenantService.getTenantId() ?? '')")
content = content.replace("order('issue_date', ascending: false)", "order('date', ascending: false)")

with open('lib/modules/purchases/services/purchase_service.dart', 'w') as f:
    f.write(content)
