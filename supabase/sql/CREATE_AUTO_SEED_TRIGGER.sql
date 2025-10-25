-- ============================================================================
-- AUTO-SEED TRIGGER: Create default data for new tenants
-- ============================================================================
-- This trigger automatically seeds essential data when a new tenant is created
-- Ensures every tenant starts with payment methods, departments, categories, etc.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.seed_tenant_defaults()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RAISE NOTICE 'Seeding default data for new tenant: % (%)', NEW.name, NEW.id;
  
  -- ============================================================================
  -- Default Payment Methods (Chilean standard payment options)
  -- ============================================================================
  INSERT INTO payment_methods (tenant_id, code, name, description, active, created_at)
  VALUES 
    (NEW.id, 'CASH', 'Efectivo', 'Pago en efectivo', true, now()),
    (NEW.id, 'TRANSFER', 'Transferencia', 'Transferencia bancaria', true, now()),
    (NEW.id, 'CARD', 'Tarjeta', 'Tarjeta de débito/crédito', true, now()),
    (NEW.id, 'MERCADOPAGO', 'MercadoPago', 'Pago con MercadoPago', true, now()),
    (NEW.id, 'CHECK', 'Cheque', 'Pago con cheque', false, now());
  
  RAISE NOTICE '✓ Created 5 default payment methods';
  
  -- ============================================================================
  -- Default Expense Categories (Chilean business expenses)
  -- ============================================================================
  INSERT INTO expense_categories (tenant_id, name, description, created_at)
  VALUES
    (NEW.id, 'Arriendo', 'Arriendo de local comercial', now()),
    (NEW.id, 'Servicios Básicos', 'Luz, agua, internet, teléfono', now()),
    (NEW.id, 'Sueldos y Honorarios', 'Remuneraciones y pagos a trabajadores', now()),
    (NEW.id, 'Insumos y Materiales', 'Material de oficina y consumibles', now()),
    (NEW.id, 'Publicidad y Marketing', 'Gastos de promoción y publicidad', now()),
    (NEW.id, 'Transporte', 'Combustible, peajes, fletes', now()),
    (NEW.id, 'Mantenimiento', 'Reparaciones y mantención', now()),
    (NEW.id, 'Impuestos', 'Patente, contribuciones, IVA', now()),
    (NEW.id, 'Gastos Financieros', 'Intereses, comisiones bancarias', now()),
    (NEW.id, 'Otros Gastos', 'Gastos varios no categorizados', now());
  
  RAISE NOTICE '✓ Created 10 default expense categories';
  
  -- ============================================================================
  -- Default Departments (Chilean business structure)
  -- ============================================================================
  INSERT INTO departments (tenant_id, name, description, active, created_at)
  VALUES
    (NEW.id, 'Ventas', 'Departamento de ventas y atención al cliente', true, now()),
    (NEW.id, 'Taller', 'Taller mecánico y servicio técnico', true, now()),
    (NEW.id, 'Administración', 'Administración y contabilidad', true, now()),
    (NEW.id, 'Bodega', 'Inventario y almacenamiento', true, now());
  
  RAISE NOTICE '✓ Created 4 default departments';
  
  -- ============================================================================
  -- Default Company Settings
  -- ============================================================================
  INSERT INTO company_settings (tenant_id, key, value, created_at)
  VALUES
    (NEW.id, 'home_icon', 'store', now()),
    (NEW.id, 'company_name', NEW.name, now()),
    (NEW.id, 'currency', 'CLP', now()),
    (NEW.id, 'tax_rate', '19', now()),
    (NEW.id, 'timezone', 'America/Santiago', now()),
    (NEW.id, 'date_format', 'DD/MM/YYYY', now()),
    (NEW.id, 'language', 'es', now()),
    (NEW.id, 'invoice_prefix', 'FV', now()),
    (NEW.id, 'purchase_prefix', 'FC', now()),
    (NEW.id, 'expense_prefix', 'GTO', now());
  
  RAISE NOTICE '✓ Created 10 default company settings';
  
  -- ============================================================================
  -- Default Work Schedule (45h week - Chilean labor law standard)
  -- ============================================================================
  INSERT INTO work_schedules (
    tenant_id, name, description,
    monday_start, monday_end,
    tuesday_start, tuesday_end,
    wednesday_start, wednesday_end,
    thursday_start, thursday_end,
    friday_start, friday_end,
    saturday_start, saturday_end,
    sunday_start, sunday_end,
    weekly_hours, timezone, active, created_at
  )
  VALUES (
    NEW.id,
    'Horario Estándar',
    'Lunes a Viernes 9:00-18:00, 45 horas semanales',
    '09:00', '18:00',  -- Monday
    '09:00', '18:00',  -- Tuesday
    '09:00', '18:00',  -- Wednesday
    '09:00', '18:00',  -- Thursday
    '09:00', '18:00',  -- Friday
    NULL, NULL,        -- Saturday off
    NULL, NULL,        -- Sunday off
    45.00,
    'America/Santiago',
    true,
    now()
  );
  
  RAISE NOTICE '✓ Created default work schedule (45h week)';
  
  -- ============================================================================
  -- Default Product Brands (common bike brands)
  -- ============================================================================
  INSERT INTO product_brands (tenant_id, name, description, active, created_at)
  VALUES
    (NEW.id, 'Sin Marca', 'Productos sin marca específica', true, now()),
    (NEW.id, 'Trek', 'Trek Bicycle Corporation', true, now()),
    (NEW.id, 'Specialized', 'Specialized Bicycle Components', true, now()),
    (NEW.id, 'Giant', 'Giant Manufacturing Co.', true, now()),
    (NEW.id, 'Shimano', 'Shimano Inc. (componentes)', true, now()),
    (NEW.id, 'Oxford', 'Marca Oxford (Chile)', true, now()),
    (NEW.id, 'Bianchi', 'Bianchi Bicycles', true, now()),
    (NEW.id, 'Genérico', 'Productos genéricos', true, now());
  
  RAISE NOTICE '✓ Created 8 default product brands';
  
  -- ============================================================================
  -- Default Service Packages (bike shop services)
  -- ============================================================================
  INSERT INTO service_packages (
    tenant_id, name, description, 
    estimated_hours, base_price, active, created_at
  )
  VALUES
    (NEW.id, 'Mantenimiento Básico', 'Limpieza, lubricación, ajustes básicos', 1.0, 15000, true, now()),
    (NEW.id, 'Mantenimiento Completo', 'Revisión completa, ajuste de cambios y frenos', 2.0, 30000, true, now()),
    (NEW.id, 'Reparación de Neumático', 'Parche o cambio de cámara', 0.5, 5000, true, now()),
    (NEW.id, 'Cambio de Frenos', 'Instalación de pastillas/zapatas nuevas', 1.0, 20000, true, now()),
    (NEW.id, 'Ajuste de Cambios', 'Calibración de cambios delanteros y traseros', 0.5, 10000, true, now()),
    (NEW.id, 'Armado de Bicicleta', 'Armado completo desde caja', 2.5, 45000, true, now());
  
  RAISE NOTICE '✓ Created 6 default service packages';
  
  -- ============================================================================
  -- Default Website Settings (ecommerce configuration)
  -- ============================================================================
  INSERT INTO website_settings (tenant_id, key, value, description, updated_at)
  VALUES
    (NEW.id, 'store_name', NEW.name, 'Nombre de la tienda online', now()),
    (NEW.id, 'store_tagline', 'Tu tienda de bicicletas', 'Eslogan de la tienda', now()),
    (NEW.id, 'store_enabled', 'false', 'Habilitar tienda online (cambiar a true cuando esté lista)', now()),
    (NEW.id, 'shipping_enabled', 'false', 'Habilitar envíos', now()),
    (NEW.id, 'shipping_cost', '0', 'Costo de envío estándar (CLP)', now()),
    (NEW.id, 'free_shipping_threshold', '50000', 'Envío gratis sobre (CLP)', now()),
    (NEW.id, 'contact_email', 'contacto@' || lower(replace(NEW.name, ' ', '')) || '.cl', 'Email de contacto', now()),
    (NEW.id, 'contact_phone', '+569 1234 5678', 'Teléfono de contacto', now()),
    (NEW.id, 'contact_address', 'Santiago, Chile', 'Dirección física', now()),
    (NEW.id, 'social_facebook', '', 'URL Facebook', now()),
    (NEW.id, 'social_instagram', '', 'URL Instagram', now()),
    (NEW.id, 'social_whatsapp', '+569 1234 5678', 'WhatsApp', now()),
    (NEW.id, 'theme_primary_color', '#2563eb', 'Color primario del tema', now()),
    (NEW.id, 'theme_secondary_color', '#10b981', 'Color secundario del tema', now()),
    (NEW.id, 'seo_meta_title', NEW.name || ' - Tienda de Bicicletas', 'Meta título SEO', now()),
    (NEW.id, 'seo_meta_description', 'Encuentra las mejores bicicletas y accesorios en ' || NEW.name, 'Meta descripción SEO', now()),
    (NEW.id, 'seo_keywords', 'bicicletas,bikes,accesorios,repuestos,servicio técnico', 'Palabras clave SEO', now());
  
  RAISE NOTICE '✓ Created 17 default website settings';
  
  -- ============================================================================
  -- Default Website Template: "Modern Bike Shop"
  -- This creates a basic homepage with hero, products, services, and contact
  -- ============================================================================
  
  -- Hero block
  INSERT INTO website_blocks (tenant_id, block_type, block_data, is_visible, order_index, created_at)
  VALUES (
    NEW.id,
    'hero',
    jsonb_build_object(
      'title', '¡Bienvenido a ' || NEW.name || '!',
      'subtitle', 'Las mejores bicicletas y servicio técnico especializado',
      'ctaText', 'Ver Productos',
      'ctaLink', '/products',
      'backgroundImage', '',
      'textAlign', 'center'
    ),
    true,
    1,
    now()
  );
  
  -- Products block (featured products)
  INSERT INTO website_blocks (tenant_id, block_type, block_data, is_visible, order_index, created_at)
  VALUES (
    NEW.id,
    'products',
    jsonb_build_object(
      'title', 'Productos Destacados',
      'subtitle', 'Descubre nuestra selección de bicicletas y accesorios',
      'displayMode', 'grid',
      'itemsToShow', 8,
      'showFeaturedOnly', true
    ),
    true,
    2,
    now()
  );
  
  -- Services block
  INSERT INTO website_blocks (tenant_id, block_type, block_data, is_visible, order_index, created_at)
  VALUES (
    NEW.id,
    'services',
    jsonb_build_object(
      'title', 'Nuestros Servicios',
      'subtitle', 'Mantenimiento y reparación especializada',
      'services', jsonb_build_array(
        jsonb_build_object(
          'icon', 'build',
          'title', 'Mantenimiento',
          'description', 'Servicio completo y revisión técnica'
        ),
        jsonb_build_object(
          'icon', 'settings',
          'title', 'Reparaciones',
          'description', 'Reparación de frenos, cambios y más'
        ),
        jsonb_build_object(
          'icon', 'star',
          'title', 'Asesoría',
          'description', 'Te ayudamos a elegir la bici perfecta'
        )
      )
    ),
    true,
    3,
    now()
  );
  
  -- About block
  INSERT INTO website_blocks (tenant_id, block_type, block_data, is_visible, order_index, created_at)
  VALUES (
    NEW.id,
    'about',
    jsonb_build_object(
      'title', 'Sobre Nosotros',
      'content', '<p>En <strong>' || NEW.name || '</strong> somos apasionados por las bicicletas. Ofrecemos las mejores marcas, servicio técnico especializado y asesoría personalizada.</p><p>Con años de experiencia, nos hemos convertido en la tienda de confianza para ciclistas de todos los niveles.</p>',
      'imageUrl', '',
      'layout', 'image-left'
    ),
    true,
    4,
    now()
  );
  
  -- Features block
  INSERT INTO website_blocks (tenant_id, block_type, block_data, is_visible, order_index, created_at)
  VALUES (
    NEW.id,
    'features',
    jsonb_build_object(
      'title', '¿Por qué elegirnos?',
      'features', jsonb_build_array(
        jsonb_build_object(
          'icon', 'verified',
          'title', 'Garantía',
          'description', 'Todos nuestros productos con garantía oficial'
        ),
        jsonb_build_object(
          'icon', 'local_shipping',
          'title', 'Envíos',
          'description', 'Despacho a todo Chile'
        ),
        jsonb_build_object(
          'icon', 'support_agent',
          'title', 'Soporte',
          'description', 'Atención personalizada y asesoría experta'
        ),
        jsonb_build_object(
          'icon', 'workspace_premium',
          'title', 'Calidad',
          'description', 'Solo trabajamos con las mejores marcas'
        )
      )
    ),
    true,
    5,
    now()
  );
  
  -- Contact block
  INSERT INTO website_blocks (tenant_id, block_type, block_data, is_visible, order_index, created_at)
  VALUES (
    NEW.id,
    'contact',
    jsonb_build_object(
      'title', 'Contáctanos',
      'subtitle', 'Estamos aquí para ayudarte',
      'email', 'contacto@' || lower(replace(NEW.name, ' ', '')) || '.cl',
      'phone', '+569 1234 5678',
      'address', 'Santiago, Chile',
      'showMap', false,
      'mapUrl', ''
    ),
    true,
    6,
    now()
  );
  
  RAISE NOTICE '✓ Created default website template with 6 blocks';
  
  -- ============================================================================
  -- Success notification
  -- ============================================================================
  RAISE NOTICE '========================================';
  RAISE NOTICE '✅ Tenant seeding complete for: %', NEW.name;
  RAISE NOTICE '   - 5 payment methods';
  RAISE NOTICE '   - 10 expense categories';
  RAISE NOTICE '   - 4 departments';
  RAISE NOTICE '   - 10 company settings';
  RAISE NOTICE '   - 1 work schedule';
  RAISE NOTICE '   - 8 product brands';
  RAISE NOTICE '   - 6 service packages';
  RAISE NOTICE '   - 17 website settings';
  RAISE NOTICE '   - 6 website blocks (homepage template)';
  RAISE NOTICE '========================================';
  RAISE NOTICE '📝 NEXT STEPS FOR NEW TENANT:';
  RAISE NOTICE '   1. Add products to inventory';
  RAISE NOTICE '   2. Mark 3-5 products as "featured" for homepage';
  RAISE NOTICE '   3. Customize website blocks in editor';
  RAISE NOTICE '   4. Upload logo and product images';
  RAISE NOTICE '   5. Set store_enabled=true when ready to go live';
  RAISE NOTICE '========================================';
  
  RETURN NEW;
  
EXCEPTION
  WHEN OTHERS THEN
    RAISE EXCEPTION 'Failed to seed tenant defaults for %: %', NEW.name, SQLERRM;
END;
$$;

-- ============================================================================
-- Drop existing trigger if it exists and create new one
-- ============================================================================
DROP TRIGGER IF EXISTS trigger_seed_tenant_defaults ON tenants;

CREATE TRIGGER trigger_seed_tenant_defaults
  AFTER INSERT ON tenants
  FOR EACH ROW
  EXECUTE FUNCTION public.seed_tenant_defaults();

-- ============================================================================
-- TRIGGER INSTALLED SUCCESSFULLY
-- ============================================================================
-- Every new tenant will now automatically receive:
-- - Default payment methods (Cash, Transfer, Card, MercadoPago, Check)
-- - Default expense categories (Rent, Utilities, Salaries, etc.)
-- - Default departments (Sales, Workshop, Admin, Warehouse)
-- - Default company settings (currency, tax rate, timezone, etc.)
-- - Default work schedule (45h week, Mon-Fri 9-18)
-- - Default product brands (Trek, Specialized, Giant, etc.)
-- - Default service packages (Basic service, Full service, etc.)
-- - Default website settings (17 ecommerce configurations)
-- - Default website template ("Modern Bike Shop" with 6 blocks)
-- ============================================================================

COMMENT ON FUNCTION public.seed_tenant_defaults() IS 
'Automatically seeds essential default data for new tenants. Creates payment methods, expense categories, departments, company settings, work schedules, product brands, service packages, website settings, and a complete homepage template with hero, products, services, about, features, and contact blocks.';

-- ============================================================================
-- Test the trigger (optional - uncomment to test)
-- ============================================================================
/*
-- Create a test tenant to verify auto-seeding works
INSERT INTO tenants (name, slug, active)
VALUES ('Test Bikeshop', 'test-bikeshop-' || floor(random() * 10000), true)
RETURNING id, name;

-- Check seeded data
SELECT 
  'payment_methods' as table_name,
  COUNT(*) as record_count
FROM payment_methods 
WHERE tenant_id = (SELECT id FROM tenants WHERE slug LIKE 'test-bikeshop-%' ORDER BY created_at DESC LIMIT 1)
UNION ALL
SELECT 'departments', COUNT(*) FROM departments
WHERE tenant_id = (SELECT id FROM tenants WHERE slug LIKE 'test-bikeshop-%' ORDER BY created_at DESC LIMIT 1)
UNION ALL
SELECT 'service_packages', COUNT(*) FROM service_packages
WHERE tenant_id = (SELECT id FROM tenants WHERE slug LIKE 'test-bikeshop-%' ORDER BY created_at DESC LIMIT 1);
*/
