---
titulo: web.dev (Google Chrome)
resumen: métricas de experiencia (Core Web Vitals) y cómo medirlas; la vara de rendimiento que usa Search
tipo: externa
revisado: 2026-10-03
---

# web.dev `[WD]`

`web.dev/articles`. Define las Core Web Vitals que Google usa como señal de
experiencia y cómo se miden en campo y en laboratorio.

## Consultado el 2026-10-03

| Página | URL | Qué se tomó |
|---|---|---|
| Web Vitals | `web.dev/articles/vitals` | LCP bueno ≤ 2,5 s (malo > 4 s); INP bueno ≤ 200 ms (malo > 500 ms); CLS bueno ≤ 0,1 (malo > 0,25); se juzga el percentil 75, móvil y escritorio por separado; campo = CrUX, PageSpeed Insights, Search Console; laboratorio = Lighthouse, DevTools; INP no se mide en laboratorio (TBT es su aproximación) |

## Cómo leerla

- **Campo manda sobre laboratorio.** Un puntaje de Lighthouse es una simulación;
  la evaluación de Search Console sale de usuarios reales (CrUX), y un sitio con
  poco tráfico puede no tener datos de campo.
- Lighthouse cuenta como LCP el elemento más grande pintado; un `<canvas>` de
  Flutter no es candidato ([rendimiento](../paginas/rendimiento.md)).
