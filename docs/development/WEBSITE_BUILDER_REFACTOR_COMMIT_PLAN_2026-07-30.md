# Plan de commit/push/deploy — refactor Website Builder (2026-07-30)

**Estado:** el index de git de `/Users/Claudio/Dev/bikeshop-erp` quedó staged
exactamente con los paths/hunks del refactor Website (140 archivos). La sesión
Claude que lo preparó no puede ejecutar `git commit`/`git push`/
`firebase deploy`: el guard `PreToolUse`
(`.claude/hooks/guard-dangerous-bash.sh`) los deniega mecánicamente en
sesiones bypass, por diseño. Este documento deja la ejecución lista para el
owner o Codex.

## Qué está staged

- Núcleo Website + storefront + partición física (`editor_panel/`,
  `store_layout/`, parts del service), FSM F5, sanitización F4D.
- Tests del refactor + `test/support/library_source.dart` + migraciones de
  source-reads (12 completos y 3 por hunks propios).
- Docs: tracker (178/178), contrato del editor, handoff de agentes,
  guardrails, handoff de continuidad, este plan, y hunks Website de
  `copilot-instructions.md` y `canonical-ui-surfaces.md`.
- DB: migración `20260729010000_atomic_replace_page_blocks.sql` (ya
  productiva y registrada desde el 2026-07-29), su pgTAP y el hunk `\ir` del
  espejo `core_schema.sql`.
- `app_router.dart` sólo con hunks Website (guard scope, shell boundary,
  checkout scope); los hunks ErpAuthorizationGate/Payroll quedaron sin stagear
  para sus owners.

Respaldo reproducible: `.tmp/website_refactor_staging/*.patch` más
`canonical-ui-surfaces.staged.md`. Si otro agente perturba el index, se
reconstruye con `git add` de los paths completos + `git apply --cached` de los
patches.

## Qué NO está staged (deliberado, ownership concurrente)

Payroll/HR, checkout/carrito/MercadoPago, catálogo (`product_catalog_page`,
`public_category_publication`), SEO center, preload/appearance, mensajería,
stock, `lib/main.dart`, `erp_routes_barrel.dart`, workflows CI, y los tests de
esos dominios (incluidas las reparaciones
`public_order_access_architecture_test.dart` y
`public_tenant_directory_client_contract_test.dart`, que asertan estado de lib
concurrente y deben viajar con esos commits).

## Verificación de compilación del árbol staged (hecha 2026-07-30)

El index staged fue materializado con `git checkout-index` y analizado
completo (`flutter analyze lib test`). Resultado: **exactamente 4 errores,
todos una única costura** con el dominio concurrente del carrito:

- `lib/public_store/widgets/public_store_bootstrap.dart:38` →
  `CartProvider.restore` (la restauración post-proyección de tenant del
  refactor usa la API de durabilidad del carrito)
- `test/widgets/public_store_authenticated_scope_lifecycle_test.dart`
  (3 usos de `CartProvider(store: …)`)

Ambos símbolos los aporta `lib/public_store/providers/cart_provider.dart` y
su cierre (cart_store, cart_lock*, modelos tax/projection, páginas
cart/checkout), que pertenecen al commit del owner del carrito/checkout.

## Secuencia de ejecución (owner/Codex, sesión no-bypass)

**Orden obligatorio: el dominio carrito/checkout commitea PRIMERO**, y este
commit Website va inmediatamente después — así cada SHA de la rama compila.

```bash
cd /Users/Claudio/Dev/bikeshop-erp
git diff --cached --stat   # revisar: ~150 archivos, sólo alcance Website+storefront
git commit -F .tmp/website_refactor_staging/commit_message.txt
git push origin smartpegas1.0
```

Si el owner prefiere un único commit de integración, puede ampliar este index
con el dominio carrito/checkout antes de commitear; lo que no debe hacerse es
mezclar Payroll/HR u otros dominios no relacionados.

Nota CI: hasta que los owners concurrentes commiteen sus dominios restantes,
los 4 tests concurrentes atribuidos en el tracker fallarían en un run de
suite completa sobre el tip. El build del STORE no depende de esos dominios.

## Deploy del storefront (ya autorizado; artefacto del árbol de trabajo)

El bundle release ya está construido y dentro del presupuesto
(`build/web_store`, gate verde 2026-07-30). Secuencia canónica completa:

```bash
./scripts/sync_seo_index.sh --check
```

```bash
fvm flutter build web --release --pwa-strategy=none -t lib/main_store.dart -o build/web_store
```

```bash
fvm dart run scripts/generate_product_seo_snapshots.dart --build-dir build/web_store --tenant-id 5443b130-cc28-45af-a420-cd500b288890 --expected-store-url https://vinabike.cl --product-scope published
```

```bash
firebase deploy --only hosting:store
```

Verificación post-deploy mínima (contratos del repo): `release.json`/SHA del
artefacto publicado, `curl -sS 'https://vinabike.cl/sitemap.xml' | head`,
recarga de `https://vinabike.cl` y `?preview=true`/`?edit=true` con la sesión
del owner para el smoke autenticado del editor (guardar real + round-trip),
que quedó registrado en el tracker como el único paso visual pendiente de
sesión autenticada.

## Cross-review

Los hallazgos para el paquete Codex están en el tracker (sección Fase 6 y
matriz de validación): 3 reparaciones mecánicas de expectativas, el defecto
del gate de readiness de `website_link_value_editor.dart` con su evidencia, y
la reconciliación DB completa.
