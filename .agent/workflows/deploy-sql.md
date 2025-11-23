---
description: Deploy SQL to vinabike-staging Supabase project
---

# Deploy SQL to Supabase

This workflow deploys SQL files directly to the **vinabike-staging** Supabase project without manual copy-pasting.

## Quick Deploy (Recommended)

Use the automated deploy script:
```bash
# turbo
./scripts/deploy_sql.sh
```

**First time setup:**
1. Go to Supabase Dashboard → Settings → Database
2. Find your database password (or reset it if needed)
3. Either:
   - Enter it when the script prompts you, OR
   - Set it as an environment variable: `export SUPABASE_DB_PASSWORD='your-password'`

**What it does:**
- ✅ Deploys `core_schema_compat.sql` directly to vinabike-staging (not as a migration!)
- ✅ Shows SQL errors immediately with line numbers
- ✅ No copy-paste needed!
- ✅ No migration files created!

## Deploy a Different SQL File

```bash
./scripts/deploy_sql.sh supabase/sql/your_file.sql
```

## Save Password (Optional)

To avoid entering the password every time:

```bash
# Add to your shell config (~/.zshrc or ~/.bashrc)
echo 'export SUPABASE_DB_PASSWORD="your-password"' >> ~/.zshrc
source ~/.zshrc
```

## Troubleshooting

- **Error: "psql: command not found"** → Install PostgreSQL client: `brew install postgresql`
- **Error: "password authentication failed"** → Check your database password in Supabase Dashboard → Settings → Database
- **SQL errors** → Check the error output, fix the SQL, and run the script again

## Tips

- The script deploys the SQL file **directly** - it does NOT create migration files
- Perfect for iterating on schema changes during development
- The script automatically targets **vinabike-staging** (project ref: kyvgmapifacpzuyreasy)
- Much faster than copy-pasting to Supabase editor!
