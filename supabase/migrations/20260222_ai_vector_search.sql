-- ============================================================
-- AI Vector Search Migration
-- Enables semantic search for products using pgvector
-- ============================================================

-- 1. Enable pgvector extension
CREATE EXTENSION IF NOT EXISTS vector;

-- 2. Add embedding column to products table
-- Using 768 dimensions to match Gemini text-embedding-004 output
ALTER TABLE products
ADD COLUMN IF NOT EXISTS embedding vector(768);

-- 3. Create index for fast cosine similarity search
CREATE INDEX IF NOT EXISTS idx_products_embedding
ON products USING ivfflat (embedding vector_cosine_ops)
WITH (lists = 100);

-- 4. Create RPC function for semantic product search
CREATE OR REPLACE FUNCTION match_products_semantic(
  query_embedding vector(768),
  match_tenant_id uuid,
  match_threshold float DEFAULT 0.3,
  match_count int DEFAULT 10
)
RETURNS TABLE (
  id uuid,
  name text,
  sku text,
  brand text,
  category_name text,
  description text,
  price float,
  inventory_qty int,
  warehouse_location text,
  similarity float
)
LANGUAGE plpgsql
AS $$
BEGIN
  RETURN QUERY
  SELECT
    p.id,
    p.name,
    p.sku,
    p.brand,
    p.category_name,
    p.description,
    p.price::float,
    p.inventory_qty,
    p.warehouse_location,
    1 - (p.embedding <=> query_embedding) AS similarity
  FROM products p
  WHERE p.tenant_id = match_tenant_id
    AND p.embedding IS NOT NULL
    AND p.is_active = true
    AND 1 - (p.embedding <=> query_embedding) > match_threshold
  ORDER BY p.embedding <=> query_embedding
  LIMIT match_count;
END;
$$;

-- 5. Helper function to get products missing embeddings (for backfill)
CREATE OR REPLACE FUNCTION get_products_missing_embeddings(
  batch_limit int DEFAULT 1500
)
RETURNS TABLE (id uuid)
LANGUAGE sql
AS $$
  SELECT p.id
  FROM products p
  WHERE p.embedding IS NULL
    AND p.is_active = true
  ORDER BY p.updated_at DESC
  LIMIT batch_limit;
$$;
