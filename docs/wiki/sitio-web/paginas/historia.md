---
titulo: Historia y decisiones
resumen: cómo llegó vinabike.cl a ser lo que es — de Odoo a Flutter en Firebase, los refactors del editor, el diagnóstico de septiembre — y las decisiones del dueño que siguen vigentes
fuentes: [repositorio, consolas-google]
archivos: [docs/archive/2025-12/MIGRATE_DOMAIN_TO_FIREBASE.md, docs/development/WEBSITE_BUILDER_PROGRESSIVE_ARCHITECTURE_REFACTOR_PLAN_2026-07-29.md, docs/development/WEBSITE_BUILDER_RESPONSIVE_AUTHORING_MASTER_PLAN_2026-08-03.md]
tablas: [website_settings]
revisado: 2026-10-04
---

# Historia y decisiones

## Línea de tiempo

| Fecha | Qué pasó |
|---|---|
| 2025-10-20 | primeros commits del módulo de comercio (`ecommerce-module 1.0.x`): la tienda nace dentro del ERP en Flutter |
| 2025-12 | el dominio vinabike.cl deja Odoo y pasa a Firebase Hosting (DNS en Cloudflare) |
| 2025-12-05 | se guardan sin elegir los colores iniciales del editor (verde `#2E7D32`, naranjo `#FF6F00`) |
| 2025-12-25 | Worker de Cloudflare `vinabike-edge-cache` para los datos de portada |
| 2025-12-27 | Merchant rechaza la apelación por «Información engañosa» |
| 2026-01 | primer refactor del editor (hoy histórico) |
| 2026-04-23 | optimización de egreso: lecturas por vista previa y páginas |
| 2026-05-01 | pedidos online + mensajería interna (WhatsApp) en el ERP |
| 2026-06-11 | catálogo de WhatsApp y comercio |
| 2026-07-13 / 17 | espacio de trabajo unificado del Website Builder; reconstrucción de la UX del editor |
| 2026-07-19 / 20 | último pedido web antes de la caída del checkout (19-jul); Merchant pasa a la Merchant API (20-jul) |
| 2026-07-22 → 30 | refactor progresivo del Website Builder (contrato del editor, dueños, catálogo, categorías) |
| 2026-08-03 / 04 | autoría responsiva y del teléfono; fases de Canvas (7A, 7B) |
| 2026-09-02 | `/app/open`: página puente para abrir la app desde un enlace |
| **2026-09-23** | **diagnóstico de punta a punta** pedido por el dueño, con dos revisiones independientes; el mismo día se cierran las fugas de costos, vuelve el checkout, los agotados recuperan su ficha, se corrigen textos y se envía el sitemap |
| 2026-09-24 | semántica para rastreadores (0 → 11 enlaces en el render de Google), 125 redirecciones de `/shop`, página instantánea, portada instantánea, build diario |
| 2026-09-24 → 26 | portal de clientes rehecho; dirección «Sendero» aprobada y aplicada |
| 2026-09-26 | primario del sitio a navy `#123F68` |
| 2026-09-27 | el diseño de todo el ERP queda a criterio del agente |
| 2026-10-03 | nace este wiki |
| 2026-10-04 | plan de migración del sitio y su editor a HTML, con una ficha de prueba en Dart medida (2,6 s contra 23,9 s); el dueño la aprueba el mismo día y empieza la fase 0 |

`[Repo]` `[Consola]`

## Decisiones del dueño que siguen vigentes

| Fecha | Decisión |
|---|---|
| 2026-09-23 | la ruta de Merchant es sanear y pedir revisión, nunca una cuenta nueva |
| 2026-09-24 | el aspecto del sitio público lo decide el agente: serio, pro, con personalidad, nada «AI'ish» |
| 2026-09-24 | ~~no rehacer las páginas públicas como HTML todavía~~ — reemplazada el 2026-10-04 |
| 2026-09-25 | sin ramas ni PR: push directo a `main` (publica la web) |
| 2026-09-27 | el diseño de todo el ERP, incluido el editor, queda abierto; Design es para proponer, no un requisito |
| 2026-10-03 | el conocimiento del sitio vive en este wiki y se escribe en la misma tarea |
| 2026-10-04 | migrar el sitio y su editor a HTML por fases («ok, aprobado, arranca con la fase 0»); el editor sigue dentro del ERP y lo que cambia en el ERP se ve en segundos |
| 2026-10-04 | **el sitio tiene que ser gratis**: nada que cobre un costo mensual (por ejemplo, Cloud Run con una instancia siempre despierta) se enciende sin su decisión explícita; el servidor HTML corre con `min-instances 0`, dentro de la cuota gratis |

`[Dueño]`

## Lo que enseñó el diagnóstico de septiembre

- La primera versión del informe mezcló denominadores (todas las URL conocidas
  contra las del sitemap) y atribuyó causas sin segmentar; la segunda contó dos
  veces una fila. De ahí las reglas de lectura de [seo-tecnico](seo-tecnico.md).
- Una fuga de RLS se revisa también para el rol `authenticated` y con el registro
  abierto: ahí estaba la segunda puerta de los costos.
- El checkout llevaba dos meses caído y nadie lo vio: la tienda no mandaba
  eventos de comercio a GA4 (los primeros, `view_item`, `add_to_cart`,
  `begin_checkout`, `purchase`, nacen el 2026-09-23) y no había alerta de «cero
  pedidos». Una caída así hoy se vería como `begin_checkout` sin `purchase`.

## En el código y la base

- Planes y estados con fecha: `docs/development/WEBSITE_BUILDER_*`,
  `docs/architecture/website-builder-refactor-status-2026-07-22.md`.
- Archivo: `docs/archive/2025-12/`, `2026-01/`, `2026-04/`, `2026-05/`, `2026-06/`.
