# Llenado experto del catálogo · tanda `catalogo-experto-2026-10-01`

El dueño, 2026-10-01: «nadie pidió eso de que los datos tuvieran que sí o sí
ser respaldados con fuente documentada». Esta tanda completa la ficha técnica
de los productos publicados con lo que un vendedor experto sabe de cada uno
(nombre, descripción, marca, modelo, línea del fabricante), sin documento ni
URL. Lo que no se sabe con certeza quedó vacío. Contrato: §7.6 de
`docs/architecture/product-technical-specifications-contract.md`.

## Qué hay aquí

| Archivo | Qué es |
|---|---|
| `fills/<familia>.txt` | La fuente revisable: una línea por producto (`<id8> campo=valor; …`), `*` para toda la familia, `@reason` con la razón que queda en el recibo. |
| `candidates.json` | Lo que se escribe: 2.938 valores en 1.175 productos de 59 familias, ya ensayados. |
| `residual.json` | 116 valores que las reglas de la ficha declaran «no corresponde» (un par de mandos no tiene una abrazadera, un juego de mazas no tiene un OLD): no se escriben. |
| `compile.py`, `finalize.py`, `ws.py` | Compilador (tipos, opciones de la ficha, filas), descarte de lo que no aplica y hoja de trabajo por familia. Leen `fields.json`, `products.json` y `allowed.json` exportados con `fields.sql`, `products.sql` y `allowed.sql` por `scripts/db/query.sh production --format json`. |

## Ensayo (2026-10-01, producción con `rollback`)

`scripts/inventory/fill_expert_values.py --mode dry --prelude <cuerpo de
20261002150000>`: 2.938 de 2.938 «recorded». La primera pasada (3.062) dejó
169 rechazos que corrigieron el compilador: la versión de cada tabla no es
siempre 1, y el material y otras opciones se acotan por ficha
(`form_contract.allowed_options`), no por definición.

## Cómo se aplica

Después de desplegar `20261002140000` y `20261002150000`:

```
python3 scripts/inventory/fill_expert_values.py \
  --candidates docs/development/product-specs-research-2026-09-05/expert-fill-2026-10-01/candidates.json \
  --actor 7bb76d88-5455-462e-a838-5f78af922914 --batch catalogo-experto-2026-10-01 \
  --output <dir> --mode commit
```

Read-back: `select count(*) from public.spec_fact_expert_fills where batch =
'catalogo-experto-2026-10-01'` igual a los «recorded». Para deshacerla:
`select public.discard_product_spec_expert_batch_v1('catalogo-experto-2026-10-01')`
como el mismo actor.

## Efecto medido

De 1.534 publicados con ficha: con 3 datos o más, de 504 a 1.151; sin ningún
dato, de 281 a 79. Lo que queda sin datos son familias cuyos datos útiles
viven en tablas sin vista de tienda (adaptadores de freno, líquidos, olivas,
cubetas de motor) o productos cuyo nombre no dice lo suficiente.
