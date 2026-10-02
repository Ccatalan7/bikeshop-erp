---
name: compatibilidad
description: Experto en compatibilidad de partes de bicicleta y en cómo Vinabike la guarda (ficha de la bici, ficha técnica, motor, Master Schema). Úsala para cualquier pregunta de «¿calza?», para elegir repuestos, para cambiar campos de ficha, opciones o reglas del motor de compatibilidad, y para ingerir una fuente nueva (Sheldon Brown, Park Tool, fabricante) en el wiki.
disable-model-invocation: false
---

# Compatibilidad (wiki + datos vivos)

El conocimiento vive en `docs/wiki/compatibilidad/` (patrón «LLM Wiki» de
Karpathy). Esta skill es el método para usarlo y mantenerlo. El esquema completo
está en `docs/wiki/compatibilidad/README.md`.

## Responder una pregunta de compatibilidad

1. Leer `docs/wiki/compatibilidad/index.md` y abrir las páginas del tema.
   Siempre `paginas/principios.md` si el veredicto no es obvio.
2. Si la respuesta depende de un modelo concreto, buscar su `[K##]` en
   `docs/architecture/bicycle-compatibility-knowledge.md` o la tabla del
   fabricante; manda el modelo exacto sobre la guía general.
3. Si es sobre una bici o un producto reales, **leer los datos vivos** con
   `scripts/db/query.sh` (ficha de la bici en `bike_profiles.technical_profile`
   y `bikes`; ficha del producto en `spec_facts`; siempre filtrando `tenant_id`).
   El mapa de claves está en `paginas/modelo-vinabike.md`.
4. Responder con: **veredicto** (compatible / con condiciones / incompatible /
   sin confirmar / en conflicto), **la condición** si la hay (qué separador,
   adaptador o laina), **qué falta saber** si no está confirmado, y de dónde sale
   cada afirmación ([SB], [PT], [Fab], [K##], [Taller]). En español de taller.
5. Si la respuesta enseñó algo que el wiki no tenía, **archivarlo** en la página
   que corresponde y una línea en `log.md`.

## Cambiar fichas, opciones o el motor

- Antes: leer las páginas del tema y `paginas/modelo-vinabike.md`, mirar
  producción (forma real de los datos) y cumplir el «Mandatory External Technical
  Research Protocol» del Master Schema. El wiki es el primer paso de esa
  investigación, no un reemplazo de mirar los datos.
- Después: actualizar la sección «En Vinabike» de cada página tocada y la tabla
  del mapa en `modelo-vinabike.md`; correr el lint.

## Ingerir una fuente

1. Registrar la consulta en su ficha de `fuentes/` (URL, fecha, qué cubre,
   lectura completa o resumen).
2. Actualizar **todas** las páginas que toca, con palabras propias (nunca copiar
   texto ni tablas completas: el repositorio es público).
3. Evidencia de un modelo concreto → la `K` siguiente del registro.
4. Línea en `log.md`; página nueva → `index.md`.

## Revisar

```bash
python3 scripts/knowledge/lint_compat_wiki.py --db production
```

Revisa índice, enlaces, plantilla, fuentes, `K##`, claves de bici en `lib/` y
claves de producto en `spec_definitions`. A mano: contradicciones entre páginas,
datos que un hallazgo nuevo superó y conceptos que el motor juzga sin página.

## Límites

- No convertir una posibilidad mecánica en aprobación; lo que sólo funciona con
  trucos no se ofrece como compatible.
- «No sé» es *sin confirmar*, nunca *incompatible*.
- Un número de medida nunca identifica un modelo.
