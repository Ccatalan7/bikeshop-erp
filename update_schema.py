import re

file_path = r'C:\\dev\\ProjectVinabike\\supabase\\sql\\core_schema.sql'
with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

# Add to CREATE TABLE suppliers
create_pattern = r"(create table if not exists suppliers \([\s\S]*?)(is_active boolean not null default true,)"
create_replacement = r\"\1image_url text,\n    portal_username text,\n    portal_password text,\n    sales_rep_name text,\n    sales_rep_phone text,\n    sales_rep_email text,\n    purchase_instructions text,\n    \2\"
content = re.sub(create_pattern, create_replacement, content)

# Add to ALTER TABLE suppliers
alter_pattern = r"(alter table public\.suppliers[\s\S]*?)(add column if not exists is_active boolean not null default true,)"
alter_replacement = r\"\1add column if not exists image_url text,\n  add column if not exists portal_username text,\n  add column if not exists portal_password text,\n  add column if not exists sales_rep_name text,\n  add column if not exists sales_rep_phone text,\n  add column if not exists sales_rep_email text,\n  add column if not exists purchase_instructions text,\n  \2\"
content = re.sub(alter_pattern, alter_replacement, content)

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(content)

print('Updated core_schema.sql')
