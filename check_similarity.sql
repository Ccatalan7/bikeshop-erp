SELECT name, 1 - (embedding <=> 'null') as similarity FROM products WHERE embedding IS NOT NULL ORDER BY similarity DESC LIMIT 10;
