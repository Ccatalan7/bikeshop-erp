---
titulo: Documentación de Flutter para web
resumen: qué hace bien y qué no Flutter web (la tecnología de la tienda); su propia advertencia sobre SEO
tipo: externa
revisado: 2026-10-03
---

# Documentación de Flutter `[FL]`

`docs.flutter.dev/platform-integration/web`. La tienda pública es una app
Flutter web; esta documentación dice para qué sirve y para qué no.

## Consultado el 2026-10-03

| Página | URL | Qué se tomó |
|---|---|---|
| Web FAQ (actualizada 2026-09-21) | `docs.flutter.dev/platform-integration/web/faq` | Flutter web **no es adecuado para contenido crítico de SEO** ni para sitios de texto; sirve para PWA, SPA y apps; recomienda separar las páginas de aterrizaje (HTML) de la experiencia de app; Firebase Hosting usa `max-age=3600` por defecto y conviene `max-age=0, must-revalidate` o nombres con huella; Wasm exige `dart.library.js_interop` |

## Cómo leerla

- Esa advertencia es la razón de ser de los snapshots HTML, la página
  instantánea y la semántica para rastreadores
  ([seo-tecnico](../paginas/seo-tecnico.md), [rendimiento](../paginas/rendimiento.md)).
- Flutter mismo publica su sitio con Jaspr (HTML). Rehacer las páginas públicas
  en HTML está **permitido** por el repo («HTML-first storefront evolution is
  allowed»), pero el dueño decidió el 2026-09-24 no hacerlo todavía.
