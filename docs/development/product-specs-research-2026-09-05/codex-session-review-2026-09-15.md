# Revisión de la sesión de Codex «Diseña fichas técnicas compatibles» (2026-09-15)

Revisión hecha por Claude al tomar la propiedad en solitario. Fuente primaria:
la transcripción local completa de la sesión
(`~/.codex/sessions/2026/09/05/rollout-2026-09-05T21-05-04-01a074e4-289d-7873-8237-8c36773bae5f.jsonl`,
643 MB, 40.561 registros, 2026-09-06T04:05Z → 2026-09-15T19:36Z, 41 mensajes del
dueño, 526 respuestas de Codex, 4.706 llamadas a herramientas, 67 compactaciones),
contrastada con la pantalla de la app, el repositorio, git y producción en
sólo lectura. El handoff revisado es
[`claude-solo-handoff-2026-09-15.md`](claude-solo-handoff-2026-09-15.md)
(`ef2c38312325f2b5…`).

## 1. Qué hizo Codex, verificado contra evidencia

| Día | Trabajo | Evidencia que lo confirma |
|---|---|---|
| 09-06 | Diagnóstico de compatibilidad (identidad → variante → interfaces → campos), motor común, cadenas/conectores; abrió y consultó una sesión de Claude por indicación del dueño | migraciones `20260906070000`…`20260906200000` aplicadas y con stamp |
| 09-07 | Lecturas exactas del editor, coherencia de filas, dominios numéricos, snapshot de investigación, cardinalidad; 68 plantillas nuevas por lotes; release macOS 1.0.3 (177) y Android 65 desde un clon aislado (`.tmp/releases/checkpoint-20260907`, commit `f51f3777`) | stamps `20260907010000`…`20260908032000`; `checkpoint-20260907-live-status.json` `published_and_verified` |
| 09-08 | Orden estricto en el DSL de filas | `20260908185800` aplicada |
| 09-14 | Perfiles por miembro, writer tipado legacy, detalle de incidencias, respaldo legacy `20260914T220049Z-pre-fill` | `20260914213000/222500/225500`; respaldo presente, `product-specs.vbspec` SHA `717f574e…` coincide |
| 09-15 | Opt-ins, kit de transmisión, guardia pública, `component_set`, pinza/pastilla/rotor, maneta; 720 asignaciones con recibo; handoff | `20260915004000`…`20260915054000` con stamp; explícitas en producción = 720 |

Ningún `git commit`, `git push`, `reset`, `clean` ni `checkout` en toda la
sesión sobre el checkout compartido; los deploys (20) pasaron todos por
`deploy_migration.sh` con verificador. Las lecturas y escrituras productivas
quedaron en el diario de `query.sh`.

## 2. Hallazgos de la revisión

1. **Migraciones aplicadas sin resguardo en git.** Las 40 migraciones de fichas
   desde el 09-06 (más dos de nómina/ventas del 09-10) están aplicadas en
   producción y sin seguimiento en este checkout. `origin/smartpegas1.0`
   (`f51f3777`) contiene 17 (hasta `20260907026000`) porque el release del
   09-07 se hizo desde un clon; las 23 restantes (`20260907222000` →
   `20260915054000`, más `20260910123000/133000`) sólo existen en este árbol de
   trabajo. El checkout local (`71926a11`) está tres commits por detrás de
   `origin` y 46 de sus 55 archivos modificados coinciden con archivos que
   esos commits tocaron: un fast-forward no es posible sin reconciliar. Es la
   decisión más urgente del dueño; no la tomo yo.
2. **ID erróneo en el handoff.** `shim_outer_diameter_mm` es
   `f091e753-d9f4-5b85-9f1b-2556821054ec` en producción, no
   `f091e753-d9f4-5b7d-bbd3-e270e77023cb`. Los otros dos IDs son correctos.
   Todo trabajo usa los IDs leídos de producción, nunca los del documento.
3. **Cobertura: 26, como dice el handoff.** Viñabike hoy: 1.673 productos, 59
   servicios, 1.588 con plantilla efectiva (explícita o por categoría), 26 sin
   ella. Mi primera lectura dio 27 y 1.674 porque no filtraba tenant: el
   registro extra (`TES-NEU-03153`) pertenece al tenant de pruebas `testbike`
   y queda fuera del alcance. Corregido el 2026-09-16.
4. **Uso real de la rama heredada de `seatpost`.** 14 productos explícitos,
   0 hechos en ellos, 0 hechos/referencias sobre `shim_inner_diameter_mm`,
   `shim_outer_diameter_mm` y `seatpost_shim_length_mm`, 0 usos de la opción
   «Suplemento (shim)». AE0266 y AE0274 no tienen plantilla explícita ni
   efectiva (categoría «Adaptadores de tija» sin mapeo).
5. **Estimaciones de avance.** Codex dio 35–40% (09-07 05:31Z), luego las
   retiró (09-07 17:55Z), repitió 64,8% como global (09-14) y lo corrigió; el
   dueño lo señaló dos veces. El handoff final separa frentes y deja
   `overall_percent = null`; esa es la forma correcta y se conserva.
6. **Sin deriva del motor.** Las cuatro funciones de coherencia y el
   validador (`ac0738d5…`) siguen iguales a la preimagen de la ronda 230;
   una preimagen fresca de producción es idéntica.

## 3. Qué cambia de la ronda 230 con propiedad en solitario

Los archivos de Root pasan a mi propiedad. El dictamen de 230 sigue vigente:
orden escalar estricto aprobado (`e25ce520…`); casquillo no publicable hasta
corregir H1 con los IDs de producción y decidir F1/F2. Cada paso siguiente
deja checkpoint en esta carpeta, SHA de todo y read-back autenticado.
