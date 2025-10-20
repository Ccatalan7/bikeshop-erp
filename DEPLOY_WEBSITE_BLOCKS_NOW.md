# 🚨 URGENT: Deploy website_blocks Table

## Error You're Seeing

```
PostgrestException: Could not find the table 'public.website_blocks'
```

## Quick Fix - Deploy Now!

### ⚡ Option 1: Supabase Dashboard (Easiest - 2 minutes)

1. **Go to**: https://app.supabase.com
2. **Select your project**
3. **Go to**: SQL Editor (left sidebar)
4. **Click**: "New Query"
5. **Paste this SQL**:

```sql
-- Create website_blocks table
CREATE TABLE IF NOT EXISTS public.website_blocks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  block_type TEXT NOT NULL,
  block_data JSONB NOT NULL DEFAULT '{}'::jsonb,
  is_visible BOOLEAN DEFAULT true,
  order_index INTEGER DEFAULT 0,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_website_blocks_visible 
  ON public.website_blocks(is_visible, order_index);
  
CREATE INDEX IF NOT EXISTS idx_website_blocks_type 
  ON public.website_blocks(block_type);

-- Enable RLS
ALTER TABLE public.website_blocks ENABLE ROW LEVEL SECURITY;

-- Public can read visible blocks
DROP POLICY IF EXISTS "Public can read visible blocks" ON public.website_blocks;
CREATE POLICY "Public can read visible blocks"
  ON public.website_blocks
  FOR SELECT
  USING (is_visible = true);

-- Authenticated users can manage all blocks
DROP POLICY IF EXISTS "Authenticated can manage blocks" ON public.website_blocks;
CREATE POLICY "Authenticated can manage blocks"
  ON public.website_blocks
  FOR ALL
  TO authenticated
  USING (auth.role() = 'authenticated')
  WITH CHECK (auth.role() = 'authenticated');

-- Refresh schema cache
NOTIFY pgrst, 'reload schema';
```

6. **Click**: "Run" (or press Cmd+Enter / Ctrl+Enter)
7. **You should see**: "Success. No rows returned"

### ⚡ Option 2: Supabase CLI (If installed)

```bash
cd /Users/Claudio/Dev/bikeshop-erp
supabase db push
```

---

## ✅ Verify It Worked

Run this query in SQL Editor:

```sql
-- Check table exists
SELECT table_name 
FROM information_schema.tables 
WHERE table_schema = 'public' 
AND table_name = 'website_blocks';

-- Should return: website_blocks
```

---

## 🔄 After Deployment

1. **Go back to your app** (localhost:52010)
2. **Hard refresh**: Cmd+Shift+R (Mac) or Ctrl+Shift+R (Windows)
3. **Open editor** from Website module
4. **Should load without errors now!** ✅

---

## 🎯 What This Table Does

The `website_blocks` table stores all the content you edit in the Odoo-style editor:

- **Hero banners** with title, subtitle, images
- **Product sections** with layout settings
- **Service cards** with icons and descriptions
- **About sections** with content and images
- And all other block types

**Each save** in the editor updates this table, and the **public store** reads from it to render your website.

---

## 🐛 Still Getting Errors?

### Error: "relation 'website_blocks' does not exist"
**Solution**: Run the SQL above in Supabase Dashboard

### Error: "permission denied for table website_blocks"
**Solution**: RLS policies not created. Run the full SQL above including the POLICY commands

### Error: "cache out of date"
**Solution**: Run this in SQL Editor:
```sql
NOTIFY pgrst, 'reload schema';
```

---

## 📊 Expected Result

After deployment:
- ✅ Editor loads default blocks
- ✅ Can edit and save changes
- ✅ Changes persist after refresh
- ✅ Preview shows saved content
- ✅ Public store renders from database

---

**🚀 Deploy now and your editor will be fully functional!**
