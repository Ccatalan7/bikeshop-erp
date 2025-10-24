-- ============================================================================
-- CONFIGURAR CREDENCIALES DE PRODUCCIÓN DE MERCADOPAGO
-- Actualiza las claves de MercadoPago a las credenciales de producción
-- ============================================================================

-- Actualizar Public Key de MercadoPago (producción)
INSERT INTO website_settings (key, value)
VALUES (
  'mercadopago_public_key',
  'APP_USR-73f83cae-12eb-4dc5-a7dc-93615fadb8db'
)
ON CONFLICT (key) 
DO UPDATE SET 
  value = 'APP_USR-73f83cae-12eb-4dc5-a7dc-93615fadb8db';

-- Actualizar Access Token de MercadoPago (producción)
INSERT INTO website_settings (key, value)
VALUES (
  'mercadopago_access_token',
  'APP_USR-2960680225825722-102402-93226a83be4b75488dc04de7327649cf-1104915860'
)
ON CONFLICT (key) 
DO UPDATE SET 
  value = 'APP_USR-2960680225825722-102402-93226a83be4b75488dc04de7327649cf-1104915860';

-- Verificar que las credenciales se guardaron correctamente
SELECT 
  key,
  CASE 
    WHEN key LIKE '%token%' THEN 'APP_USR-****-****' 
    ELSE value 
  END as value_masked
FROM website_settings
WHERE key IN ('mercadopago_public_key', 'mercadopago_access_token')
ORDER BY key;

-- IMPORTANTE: Verificar las URLs de notificación en MercadoPago
-- Asegúrate de configurar en tu cuenta de MercadoPago:
-- 
-- Notification URL (webhook):
-- https://[YOUR-PROJECT-ID].supabase.co/functions/v1/mercadopago-webhook
--
-- Success URL:
-- https://vinabike-store.web.app/tienda/pedido/{order_id}
--
-- Failure URL:
-- https://vinabike-store.web.app/tienda/checkout
--
-- Pending URL:
-- https://vinabike-store.web.app/tienda/pedido/{order_id}
