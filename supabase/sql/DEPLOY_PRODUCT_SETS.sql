-- ============================================================================
-- PRODUCT SETS SYSTEM - Juegos/Sets de Productos
-- ============================================================================
-- Allows products to be defined as "sets" containing multiple components.
-- Example: "Juego Mazas Shimano Deore" = Front Hub + Rear Hub
-- Stock is tracked at component level, not at set level.
-- ============================================================================

-- Add set-related columns to products table
DO $$
BEGIN
  -- is_set: True if this product is a parent set product
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'products' AND column_name = 'is_set') THEN
    ALTER TABLE products ADD COLUMN is_set BOOLEAN NOT NULL DEFAULT FALSE;
  END IF;

  -- set_type: Type of set for UI hints ('pair', 'front_rear', 'left_right', 'custom')
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'products' AND column_name = 'set_type') THEN
    ALTER TABLE products ADD COLUMN set_type TEXT;
  END IF;

  -- parent_set_id: If this is a component, references the parent set
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'products' AND column_name = 'parent_set_id') THEN
    ALTER TABLE products ADD COLUMN parent_set_id UUID REFERENCES products(id) ON DELETE SET NULL;
  END IF;

  -- component_label: For components, stores the label like "Delantero", "Trasero"
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'products' AND column_name = 'component_label') THEN
    ALTER TABLE products ADD COLUMN component_label TEXT;
  END IF;

  -- component_position: For ordering components in the set (1, 2, 3...)
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'products' AND column_name = 'component_position') THEN
    ALTER TABLE products ADD COLUMN component_position INTEGER;
  END IF;
END $$;

-- Indexes for fast lookups
CREATE INDEX IF NOT EXISTS idx_products_parent_set 
  ON products(parent_set_id) WHERE parent_set_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_products_is_set 
  ON products(is_set) WHERE is_set = TRUE;

-- ============================================================================
-- PRODUCT SET COMPONENTS TABLE
-- Links parent sets to their child component products with additional metadata
-- ============================================================================
CREATE TABLE IF NOT EXISTS product_set_components (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID REFERENCES tenants(id) ON DELETE CASCADE NOT NULL,
  
  -- Parent set product
  set_product_id UUID REFERENCES products(id) ON DELETE CASCADE NOT NULL,
  
  -- Child component product
  component_product_id UUID REFERENCES products(id) ON DELETE CASCADE NOT NULL,
  
  -- Component metadata
  component_label TEXT NOT NULL,        -- "Delantero", "Trasero", "Izquierdo", "Derecho"
  component_position INTEGER NOT NULL,  -- Order: 1, 2, 3...
  quantity_in_set INTEGER NOT NULL DEFAULT 1,  -- Usually 1, could be 2 for "par de pedales"
  
  -- Pricing ratios (for calculating component prices from set price)
  -- If null, will use equal division or manual prices
  cost_ratio NUMERIC(5,4),   -- 0.4 = 40% of set cost goes to this component
  price_ratio NUMERIC(5,4),  -- 0.6 = 60% of set price goes to this component
  
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  
  -- Constraints
  UNIQUE(set_product_id, component_product_id),
  UNIQUE(set_product_id, component_position)
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_product_set_components_tenant 
  ON product_set_components(tenant_id);
CREATE INDEX IF NOT EXISTS idx_product_set_components_set 
  ON product_set_components(set_product_id);
CREATE INDEX IF NOT EXISTS idx_product_set_components_component 
  ON product_set_components(component_product_id);

-- Enable RLS
ALTER TABLE product_set_components ENABLE ROW LEVEL SECURITY;

-- RLS Policies
DROP POLICY IF EXISTS "product_set_components_select" ON product_set_components;
DROP POLICY IF EXISTS "product_set_components_insert" ON product_set_components;
DROP POLICY IF EXISTS "product_set_components_update" ON product_set_components;
DROP POLICY IF EXISTS "product_set_components_delete" ON product_set_components;

CREATE POLICY "product_set_components_select" ON product_set_components
  FOR SELECT TO authenticated
  USING (tenant_id = public.user_tenant_id());

CREATE POLICY "product_set_components_insert" ON product_set_components
  FOR INSERT TO authenticated
  WITH CHECK (tenant_id = public.user_tenant_id());

CREATE POLICY "product_set_components_update" ON product_set_components
  FOR UPDATE TO authenticated
  USING (tenant_id = public.user_tenant_id());

CREATE POLICY "product_set_components_delete" ON product_set_components
  FOR DELETE TO authenticated
  USING (tenant_id = public.user_tenant_id());

-- Trigger for updated_at
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_product_set_components_updated_at') THEN
    CREATE TRIGGER trg_product_set_components_updated_at 
      BEFORE UPDATE ON product_set_components
      FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
  END IF;
END $$;

-- ============================================================================
-- HELPER FUNCTIONS FOR PRODUCT SETS
-- ============================================================================

-- Function: Get component availability for a set
-- Returns the minimum stock across all components (= max full sets available)
CREATE OR REPLACE FUNCTION public.get_set_availability(p_set_product_id UUID)
RETURNS TABLE (
  component_id UUID,
  component_name TEXT,
  component_label TEXT,
  component_position INTEGER,
  stock_quantity INTEGER,
  quantity_needed INTEGER
)
LANGUAGE plpgsql
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    psc.component_product_id AS component_id,
    p.name AS component_name,
    psc.component_label,
    psc.component_position,
    COALESCE(p.stock_quantity, p.inventory_qty, 0)::INTEGER AS stock_quantity,
    psc.quantity_in_set AS quantity_needed
  FROM product_set_components psc
  JOIN products p ON p.id = psc.component_product_id
  WHERE psc.set_product_id = p_set_product_id
  ORDER BY psc.component_position;
END;
$$;

-- Function: Get full sets available (min stock across all components)
CREATE OR REPLACE FUNCTION public.get_full_sets_count(p_set_product_id UUID)
RETURNS INTEGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_min_sets INTEGER;
BEGIN
  SELECT MIN(
    FLOOR(COALESCE(p.stock_quantity, p.inventory_qty, 0)::NUMERIC / psc.quantity_in_set)
  )::INTEGER
  INTO v_min_sets
  FROM product_set_components psc
  JOIN products p ON p.id = psc.component_product_id
  WHERE psc.set_product_id = p_set_product_id;
  
  RETURN COALESCE(v_min_sets, 0);
END;
$$;

-- Function: Check if set has partial availability
CREATE OR REPLACE FUNCTION public.is_set_partial(p_set_product_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
DECLARE
  v_has_stock BOOLEAN;
  v_missing_stock BOOLEAN;
BEGIN
  -- Check if at least one component has stock
  SELECT EXISTS (
    SELECT 1 FROM product_set_components psc
    JOIN products p ON p.id = psc.component_product_id
    WHERE psc.set_product_id = p_set_product_id
      AND COALESCE(p.stock_quantity, p.inventory_qty, 0) >= psc.quantity_in_set
  ) INTO v_has_stock;
  
  -- Check if at least one component is missing stock
  SELECT EXISTS (
    SELECT 1 FROM product_set_components psc
    JOIN products p ON p.id = psc.component_product_id
    WHERE psc.set_product_id = p_set_product_id
      AND COALESCE(p.stock_quantity, p.inventory_qty, 0) < psc.quantity_in_set
  ) INTO v_missing_stock;
  
  -- Partial = some have stock AND some don't
  RETURN v_has_stock AND v_missing_stock;
END;
$$;

-- ============================================================================
-- VIEW: Products with set information
-- Enriches products with component data for sets
-- ============================================================================
CREATE OR REPLACE VIEW public.products_with_sets AS
SELECT 
  p.*,
  -- For sets: aggregate component info
  CASE WHEN p.is_set THEN
    (SELECT json_agg(
      json_build_object(
        'id', psc.id,
        'component_product_id', psc.component_product_id,
        'component_label', psc.component_label,
        'component_position', psc.component_position,
        'component_name', cp.name,
        'component_sku', cp.sku,
        'stock_quantity', COALESCE(cp.stock_quantity, cp.inventory_qty, 0),
        'quantity_in_set', psc.quantity_in_set,
        'cost_ratio', psc.cost_ratio,
        'price_ratio', psc.price_ratio
      ) ORDER BY psc.component_position
    )
    FROM product_set_components psc
    JOIN products cp ON cp.id = psc.component_product_id
    WHERE psc.set_product_id = p.id)
  END AS set_components,
  -- For sets: calculate availability
  CASE WHEN p.is_set THEN public.get_full_sets_count(p.id) END AS full_sets_available,
  CASE WHEN p.is_set THEN public.is_set_partial(p.id) END AS is_partial,
  -- For components: get parent set info
  CASE WHEN p.parent_set_id IS NOT NULL THEN
    (SELECT json_build_object(
      'id', ps.id,
      'name', ps.name,
      'sku', ps.sku
    ) FROM products ps WHERE ps.id = p.parent_set_id)
  END AS parent_set_info
FROM products p;
