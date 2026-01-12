-- Enable the pg_trgm extension for fuzzy matching
create extension if not exists pg_trgm;

-- Create a search function that uses trigram similarity
create or replace function search_products(
  p_search_term text,
  p_tenant_id uuid,
  p_limit int default 10
)
returns setof products
language sql
security definer
set search_path = public
as $$
  select *
  from products
  where tenant_id = p_tenant_id
    and is_active = true
    and inventory_qty > 0
    and (
      -- Exact/Substring match (fastest)
      name ilike '%' || p_search_term || '%'
      or sku ilike '%' || p_search_term || '%'
      -- Fuzzy match (handles typos)
      or similarity(name, p_search_term) > 0.1
      or similarity(description, p_search_term) > 0.1
    )
  order by
    -- Prioritize exact matches in name
    case when name ilike '%' || p_search_term || '%' then 1 else 0 end desc,
    -- Then similarity score
    similarity(name, p_search_term) desc,
    similarity(sku, p_search_term) desc
  limit p_limit;
$$;
