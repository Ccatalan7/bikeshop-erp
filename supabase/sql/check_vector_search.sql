-- Check if pgvector extension is enabled
SELECT * FROM pg_extension WHERE extname = 'vector';

-- Check if embedding column exists on products
SELECT column_name, data_type, udt_name
FROM information_schema.columns
WHERE table_name = 'products' AND column_name = 'embedding';

-- Count products WITH embeddings vs WITHOUT
SELECT
  COUNT(*) AS total_products,
  COUNT(embedding) AS with_embedding,
  COUNT(*) - COUNT(embedding) AS without_embedding
FROM products;
