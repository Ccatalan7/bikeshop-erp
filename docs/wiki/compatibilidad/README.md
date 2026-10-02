# Wiki de compatibilidad — cómo funciona y cómo se mantiene

Este wiki es el conocimiento de compatibilidad de partes de bicicleta del
taller: qué calza con qué, por qué, con qué condiciones y dónde lo guarda
Vinabike. Lo escriben y lo mantienen los agentes (Claude o Codex); el dueño lo
lee cuando quiere. Sigue el patrón «LLM Wiki» de Andrej Karpathy
(`gist.github.com/karpathy/442a6bf555914893e9891c11519de94f`), adaptado a este
repositorio. Empieza por [index.md](index.md).

Lo pidió el dueño el 2026-10-02: un experto en compatibilidad y en el Master
Schema, con **Sheldon Brown** y **Park Tool** como fuentes principales y una
investigación a fondo de **Bike Matrix** (bikematrix.io), «aunque creo que bike
matrix es más simple de lo que queremos aplicar en nuestro caso».

## Las tres capas

| Capa | Dónde | Quién la cambia |
|---|---|---|
| **Fuentes** | [fuentes/](fuentes/) — una ficha por sitio o fabricante: qué páginas se consultaron, qué cubren, cuándo y con qué cuidado leerlas | se agrega al ingerir; no se reescribe lo ya consultado |
| **Páginas** | [paginas/](paginas/) — una página por tema (ruedas, núcleos, pedalier…), escrita con palabras propias | el agente, cada vez que aprende algo |
| **Esquema** | este archivo y la skill `.claude/skills/compatibilidad/SKILL.md` | sólo cuando el método cambia |

Hay además dos registros que ya existían y que este wiki **no reemplaza**:

- **Registro de evidencia K01–K52** en
  [`docs/architecture/bicycle-compatibility-knowledge.md`](../../architecture/bicycle-compatibility-knowledge.md):
  afirmaciones acotadas con su fuente exacta (modelo, mercado, fecha). Las
  páginas las citan como `[K14]`. Una afirmación nueva con evidencia de un
  modelo concreto va allá con el número siguiente; la página la resume.
- **El contrato de fichas** en
  [`docs/architecture/product-technical-specifications-contract.md`](../../architecture/product-technical-specifications-contract.md)
  y el **Master Schema** (`BIKE_WORKSHOP_MASTER_SCHEMA.md`): cómo el sistema
  guarda y juzga. El wiki explica el oficio y apunta a esas secciones; no
  copia sus reglas.

## Reglas de escritura

1. **Palabras propias, nunca copia.** Sheldon Brown y Park Tool tienen derechos
   de autor y el repositorio es público. Se guardan hechos (medidas, códigos,
   reglas) y un enlace a la página; nunca párrafos, tablas completas copiadas
   ni imágenes. Un número de una norma es un hecho; la redacción del artículo
   no.
2. **Cada afirmación dice de dónde sale**, con una etiqueta al final:
   - `[SB]` Sheldon Brown, `[PT]` Park Tool, `[BM]` Bike Matrix,
   - `[Fab]` tabla o ficha del fabricante (el modelo concreto manda),
   - `[K##]` registro de evidencia,
   - `[Taller]` criterio de mecánico experto, sin documento detrás. Vale: el
     dueño decidió el 2026-10-01 que un dato no necesita fuente documentada
     («nadie pidió eso»). La etiqueta sólo dice cómo se sabe, para que quien
     dude sepa qué revisar.
3. **El alcance manda.** Una guía general describe; la tabla del fabricante de
   **ese** modelo y revisión certifica. Si se contradicen, se anotan las dos
   con su alcance y se explica; no se vota ([K07], [K31], [K36]).
4. **No hay bandas mágicas.** Un ancho, una velocidad o un diámetro no deducen
   por sí solos un modelo ni una compatibilidad ([K03], [K32]). Una medida
   nunca es un modelo (contrato de identidad de producto).
5. **«No sé» no es «no calza».** Falta de dato es *sin confirmar*; sólo una
   contradicción demostrada es *incompatible*.
6. **Cada página termina en «En Vinabike»**: qué campo de la ficha de la bici y
   qué claves de la ficha del producto guardan ese concepto, qué juzga hoy el
   motor y qué falta. Así el wiki es también el mapa del Master Schema.
7. Español de taller chileno para explicar; los nombres de estándar en su forma
   original (Boost, Microspline, post mount, BSA).

## Plantilla de página

```markdown
---
titulo: Núcleos y cassettes
resumen: una línea que diga para qué sirve la página
fuentes: [sheldon-brown, park-tool]
k: [K08, K09]
claves_bici: [freehubType]
claves_producto: [freehub_type, cassette_spline_standard]
revisado: 2026-10-02
---

# Núcleos y cassettes

## Lo esencial
## (tablas y reglas del tema)
## Trampas frecuentes
## En Vinabike
## Fuentes
```

`claves_bici` son claves de `bike_profiles.technical_profile` o de `bikes`;
`claves_producto` son `spec_definitions.key` globales. El lint comprueba que
existan.

## Cómo se asegura que se use (2026-10-02)

El dueño preguntó cómo evitar que esto quede «como una carpeta paralela que será
olvidada». Hay cuatro capas, de la más suave a la que no se puede saltar:

1. **Al empezar cada sesión de Claude**, `.claude/hooks/session-context.sh` dice
   que la compatibilidad pasa por la skill `compatibilidad`. Codex lo lee en
   `AGENTS.md`; los dos lo tienen en la tabla de rutas de `CLAUDE.md` y en el
   protocolo de investigación del Master Schema.
2. **Cuando el pedido trata de compatibilidad**, el hook
   `.claude/hooks/compat_wiki_router.py` (UserPromptSubmit) le recuerda a Claude
   usar la skill, una vez por sesión. La skill misma se invoca sola por su
   descripción (cassette, núcleo, pedalier, rotor, ficha de la bici…).
3. **Cuando se edita el motor, la ficha de la bici, las fichas o el Master
   Schema**, el mismo hook (PostToolUse) recuerda actualizar la página y correr el
   lint, una vez por sesión.
4. **En cada publicación** (gate de CI, para Claude y Codex por igual),
   `test/unit/compatibility_wiki_contract_test.dart` falla si el motor juzga una
   familia o lee un campo de la bici que el wiki no nombra, o si una página no
   está en el índice. Ésta es la que no depende de la memoria de nadie.

El lint con `--db production` revisa además que las claves de ficha citadas sigan
existiendo en la base.

## Las tres operaciones

**Consultar.** Leer [index.md](index.md), abrir las páginas del tema, seguir
sus `[K##]` si hace falta el modelo exacto, y **contrastar con los datos
vivos** (`scripts/db/query.sh`) antes de afirmar que algo calza en una bici o
producto real. Si la respuesta enseña algo que el wiki no tenía, se archiva en
la página que corresponde (no se pierde en el chat).

**Ingerir.** Una fuente nueva (página de Sheldon, artículo de Park, tabla de
Shimano, una lección del taller):
1. agregar la consulta a su ficha en `fuentes/` (URL, fecha, qué cubre);
2. actualizar **todas** las páginas que toca, no sólo una;
3. si es evidencia de un modelo concreto, agregar la `K` siguiente al registro;
4. una línea en [log.md](log.md) y, si nace una página, en [index.md](index.md).

**Revisar (lint).** `python3 scripts/knowledge/lint_compat_wiki.py` revisa:
páginas fuera del índice o índice roto, enlaces internos, campos de la
plantilla, `K##` y fuentes que no existen, y con `--db production` que cada
clave de producto exista en `spec_definitions` y cada clave de bici en el
código. Además, a mano: contradicciones entre páginas, afirmaciones viejas que
un dato nuevo superó y huecos (un concepto que el motor juzga sin página).
