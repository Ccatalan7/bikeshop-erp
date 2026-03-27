import sys

file_path = r'C:\\dev\\ProjectVinabike\\supabase\\sql\\core_schema.sql'
with open(file_path, 'r', encoding='utf-8') as f:
    lines = f.readlines()

out_lines = []
for line in lines:
    if line.strip() == "is_active boolean not null default true," and "notes text," in out_lines[-1]:
        out_lines.append("    image_url text,\n")
        out_lines.append("    portal_username text,\n")
        out_lines.append("    portal_password text,\n")
        out_lines.append("    sales_rep_name text,\n")
        out_lines.append("    sales_rep_phone text,\n")
        out_lines.append("    sales_rep_email text,\n")
        out_lines.append("    purchase_instructions text,\n")
    if line.strip() == "add column if not exists is_active boolean not null default true," and "add column if not exists notes text," in out_lines[-1]:
        out_lines.append("  add column if not exists image_url text,\n")
        out_lines.append("  add column if not exists portal_username text,\n")
        out_lines.append("  add column if not exists portal_password text,\n")
        out_lines.append("  add column if not exists sales_rep_name text,\n")
        out_lines.append("  add column if not exists sales_rep_phone text,\n")
        out_lines.append("  add column if not exists sales_rep_email text,\n")
        out_lines.append("  add column if not exists purchase_instructions text,\n")
    out_lines.append(line)

with open(file_path, 'w', encoding='utf-8') as f:
    f.writelines(out_lines)
print('Updated core_schema.sql success')
