-- Unified RPC for public store initial data
-- Returns settings AND home page blocks in a single call
-- This reduces 2 DB round-trips to 1, saving ~400-500ms

CREATE OR REPLACE FUNCTION get_public_store_data(p_tenant_id uuid)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_settings json;
  v_blocks json;
  v_home_page_id uuid;
BEGIN
  -- Get home page ID
  SELECT id INTO v_home_page_id
  FROM website_pages
  WHERE tenant_id = p_tenant_id
    AND is_home = true
    AND is_published = true
  LIMIT 1;
  
  -- Fallback to first published page if no home page
  IF v_home_page_id IS NULL THEN
    SELECT id INTO v_home_page_id
    FROM website_pages
    WHERE tenant_id = p_tenant_id
      AND is_published = true
    ORDER BY created_at
    LIMIT 1;
  END IF;
  
  -- Get all settings as JSON object
  SELECT json_object_agg(key, value)
  INTO v_settings
  FROM website_settings
  WHERE tenant_id = p_tenant_id;
  
  -- Get blocks for home page as JSON array
  SELECT COALESCE(json_agg(
    json_build_object(
      'id', id,
      'block_type', block_type,
      'block_data', block_data,
      'is_visible', is_visible,
      'order_index', order_index
    ) ORDER BY order_index
  ), '[]'::json)
  INTO v_blocks
  FROM website_blocks
  WHERE tenant_id = p_tenant_id
    AND page_id = v_home_page_id
    AND is_visible = true;
  
  -- Return combined result
  RETURN json_build_object(
    'settings', COALESCE(v_settings, '{}'::json),
    'blocks', COALESCE(v_blocks, '[]'::json),
    'home_page_id', v_home_page_id
  );
END;
$$;

-- Grant execute to anon role (public store visitors)
GRANT EXECUTE ON FUNCTION get_public_store_data(uuid) TO anon;
GRANT EXECUTE ON FUNCTION get_public_store_data(uuid) TO authenticated;
