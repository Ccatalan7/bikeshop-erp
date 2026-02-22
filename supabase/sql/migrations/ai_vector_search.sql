-- Enable the pgvector extension to work with embedding vectors
create extension if not exists vector
with
  schema public;

-- Add embedding column to products table (Gemini text-embedding-004 uses 768 dimensions)
alter table products add column if not exists embedding vector(768);

-- Create an index to speed up vector searches (using HNSW)
-- We're creating the index concurrently to not lock the table if it's large
create index concurrently if not exists products_embedding_idx on products using hnsw (embedding vector_cosine_ops);

-- Create a function to search for products using semantic matching
-- Drop the function first to ensure we replace it cleanly
drop function if exists match_products_semantic;

create or replace function match_products_semantic (
  query_embedding vector(768),
  match_threshold float,
  match_count int,
  p_tenant_id uuid
)
returns table (
  id uuid,
  tenant_id uuid,
  name text,
  sku text,
  price numeric(12,2),
  cost numeric(12,2),
  brand_id uuid,
  inventory_qty integer,
  brand text,
  category_name text,
  image_urls text[],
  similarity float
)
language plpgsql
as $$
begin
  return query
  select
    products.id,
    products.tenant_id,
    products.name,
    products.sku,
    products.price,
    products.cost,
    products.brand_id,
    products.inventory_qty,
    products.brand,
    products.category_name,
    products.image_urls,
    1 - (products.embedding <=> query_embedding) as similarity
  from products
  where products.tenant_id = p_tenant_id
    and products.embedding is not null
    and 1 - (products.embedding <=> query_embedding) > match_threshold
  order by products.embedding <=> query_embedding
  limit match_count;
end;
$$;
