---
titulo: Contratos y documentos del repositorio
resumen: los documentos internos que mandan sobre el sitio y el editor, y los planes e informes que dejan historia
tipo: interna
revisado: 2026-10-03
---

# Contratos y documentos del repositorio `[Repo]`

## Mandan (se leen antes de cambiar)

| Documento | Qué decide |
|---|---|
| `docs/architecture/website-editor-contract.md` | contrato de ingeniería del editor: invariante dueño → control → operación → consumidor; paridad Edit/Preview/publicado; inspector; geometría; medios; dueños de cada espacio de administración; SEO en tres planos; verificación mínima |
| `docs/architecture/website-builder-agent-handoff.md` | equivalencia de acciones (lo que hace un agente lo hace igual que el editor), mapa de dueños, reglas por capacidad, plan de colecciones de catálogo |
| `docs/architecture/storefront-instant-page.md` | página instantánea: rutas, traspaso a Flutter, frescura, medición, rollback |
| `docs/architecture/canonical-ui-surfaces.md` | registro de cada superficie del editor y la tienda (filas «Website …», «Public …», «Customer portal», «Storefront …») |
| `docs/runbooks/ONLINE_ORDER_OPERATIONS.md` | pedidos online: evidencias, Mercado Pago, boleta, reserva de stock, correcciones, correos, Merchant |
| `docs/development/WEB_PREVIEW.md` | cómo ver la tienda en un navegador real (`scripts/dev/web_preview.sh`) |
| `.github/copilot-instructions.md` | «Public Store Quality Bar», «Public Store Performance & Freshness Doctrine», «HTML-first storefront evolution is allowed», «EDITOR ARCHITECTURE» |
| `.github/GUI_DESIGN_PRINCIPLES.md` | «El sitio público no pasa por Design» (2026-09-24) y «El diseño del ERP es abierto» (2026-09-27) |
| `docs/user-guides/WEBSITE_ONLINE_SALES_USER_GUIDE.md` | el manual para el operador (el que abre el botón de ayuda del panel del sitio) |

## Historia (se leen para entender por qué)

- `docs/development/WEBSITE_BUILDER_PROGRESSIVE_ARCHITECTURE_REFACTOR_PLAN_2026-07-29.md`
  y `WEBSITE_BUILDER_RESPONSIVE_AUTHORING_MASTER_PLAN_2026-08-03.md`: fases del
  refactor de julio y agosto.
- `docs/architecture/website-builder-refactor-status-2026-07-22.md`,
  `website-builder-refactor-guardrails.md`.
- `docs/archive/2025-12/MIGRATE_DOMAIN_TO_FIREBASE.md`: cómo vinabike.cl llegó a
  Firebase Hosting.
- `docs/archive/2026-01/WEBSITE_EDITOR_REFACTOR_HANDOFF.md`,
  `docs/archive/2026-05/ONLINE_ORDERS_MESSAGING_HANDOFF_2026-05-01.md`,
  `docs/archive/2026-06/WHATSAPP_CATALOG_COMMERCE_HANDOFF_2026-06-11.md`.
- Informe «Diagnóstico vinabike.cl» (2026-09-23/24, Artifact privado del dueño):
  línea base de SEO, seguridad, checkout y rendimiento; lo implementado está en
  [historia](../paginas/historia.md).

## Cómo leerlos

- Un plan con fecha cuenta lo que se pensaba ese día; el estado real se mira en
  el código, en `release.json` y en producción.
- Una migración en git no prueba que esté aplicada: `scripts/db/migration_status.sh`.
