-- ============================================================================
-- DESACTIVAR MODO TEST DE MERCADOPAGO
-- Fuerza el modo de producción para MercadoPago
-- ============================================================================

-- Establecer test_mode = false
INSERT INTO website_settings (key, value)
VALUES ('mercadopago_test_mode', 'false')
ON CONFLICT (key) 
DO UPDATE SET value = 'false';

-- Verificar configuración completa
SELECT 
  key,
  CASE 
    WHEN key LIKE '%token%' THEN 'APP_USR-****-****' 
    ELSE value 
  END as value_display
FROM website_settings
WHERE key LIKE 'mercadopago%'
ORDER BY key;
