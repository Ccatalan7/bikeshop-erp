---
titulo: Documentación de Google Analytics 4
resumen: eventos de comercio recomendados y sus parámetros; cómo GA4 cuenta una compra
tipo: externa
revisado: 2026-10-03
---

# Google Analytics 4 `[GA]`

`developers.google.com/analytics/devguides/collection/ga4`.

## Consultado el 2026-10-03

| Página | URL | Qué se tomó |
|---|---|---|
| Medir comercio electrónico | `/analytics/devguides/collection/ga4/ecommerce` | embudo recomendado `view_item_list` → `select_item` → `view_item` → `add_to_cart` / `remove_from_cart` → `view_cart` → `begin_checkout` → `add_shipping_info` → `add_payment_info` → `purchase` (y `refund`); `purchase` exige `transaction_id`, `value`, `currency`, `items` (máx. 200); `transaction_id` evita contar dos veces la misma compra |

## Cómo leerla

- Los nombres recomendados activan los informes de comercio; un nombre propio
  (`store_ready`) sólo sirve para exploraciones y dimensiones personalizadas.
- Un evento nuevo tarda hasta ~24 h en aparecer para marcarlo como evento clave.
