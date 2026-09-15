# Llenado del catálogo completo: preparación — plan de Claude, 2026-09-06

Autor: Claude (Fable 5.1, modo Code). Encargo ampliado por Claudio: Codex y
Claude investigan y rellenan lo máximo posible de todo el catálogo; el dueño
no lo hace a mano. Esta ronda prepara la ejecución; no escribe en producción.
Archivo propio de Claude; Codex conserva código, SQL, migraciones y auditoría.

Cifras de partida, leídas en producción el 2026-09-06 para el tenant
`vinabike`, productos activos no servicio:

| Medida | Valor |
|---|---|
| Productos | 1 558 |
| Con marca / con modelo / con MPN / con GTIN o código de barras | 1 279 / 12 / 0 / 10 |
| Con plantilla técnica / sin plantilla | 852 / 706 |
| Con algún hecho / con referencia | 461 / 0 |
| Publicados en la web | 1 525 |
| Hechos por procedencia | supplier_text 1 128, import 282, inferred 229, name_reading 14 |

Lo que esos números dicen: la identidad estructurada casi no existe, los hechos
que hay son nominales copiados del texto del proveedor, y casi la mitad del
catálogo no tiene familia técnica. El llenado no es «completar formularios»:
es resolver identidad, encontrar la edición OEM y sembrarla, y para lo que no
tiene OEM, dejar hechos nominales honestos sin claims.

## 1. Unidad de trabajo

Un producto se trabaja en este orden, y cada paso registra qué lo respalda:

1. **Marca real.** Distinguir fabricante (Shimano, KMC, Maxxis) de importador
   o marca de tienda (Andes Industrial, MKR, Radical Mountain, Ozono, «Taiwan»,
   «China», «Aliexpress», «Genérico»). Sólo la primera clase tiene documentación
   OEM. Un registro por marca, `brand-sources.json`, guarda dominios oficiales,
   catálogos PDF fechados, método de lectura y veredicto «OEM / sin OEM».
2. **Modelo.** Sale del nombre por el extractor canónico, con confirmación; del
   envase; o del proveedor. Nunca por parecido. Hoy 12 productos tienen modelo;
   los nombres con código reconocible son 98 en Shimano, 19 en KMC, 14 en
   Weinmann, 12 en Vuelta, 10 en SunRace, 54 entre los 279 sin marca.
3. **Variante y edición.** Mercado, acabado, EPT/anti-óxido, revisión. Una
   edición es una referencia inmutable con su página y fecha.
4. **Presentación.** Eslabones, unidades, caja/display/rollo. Distinta
   presentación es distinta referencia; una referencia de modelo sin
   presentación se marca así y no fija cantidades.
5. **Vínculo producto → referencia.** Sólo con MPN o GTIN en el envase, o con
   modelo y presentación confirmados. Si sólo se conoce el modelo, el vínculo
   es a la referencia de modelo y los hechos de presentación quedan manuales.
6. **Hechos y claims.** De la referencia; lo que la página no dice queda
   ausente. Los claims separan cobertura, sistemas declarados, exclusividad y
   exclusiones.

## 2. Qué evidencia permite cada hecho y cada vínculo

| Evidencia | Permite | No permite |
|---|---|---|
| Página OEM del modelo, catálogo OEM fechado, manual del fabricante | Referencia inmutable con hechos, claims y presentación; vínculo con MPN/GTIN o presentación confirmada | Extender a otra edición, mercado o presentación |
| Envase o etiqueta del producto en tienda, con foto archivada | Referencia con `sources: [envase, foto]` cuando no hay página OEM; MPN y GTIN; presentación real | Claims de compatibilidad que el envase no imprime |
| Sheldon Brown y Park Tool | Reglas generales por familia, vocabulario, dependencias y lo que una medida no prueba | Ningún hecho de un modelo concreto; nunca fuente de una referencia |
| Nombre del producto y texto del proveedor | Sugerencia de modelo y denominaciones nominales impresas (1/2×1/8, 700×35C, 27.5, 116 eslabones), vía la lectura del nombre con cita | Marca real, compatibilidad, cantidades de envase, reutilización |
| Minorista o distribuidor | Existencia del modelo y dónde buscar la página OEM | Ningún hecho; ninguna cita en `sources` |
| Medición del mecánico sobre la pieza | Hecho medido con método y tolerancia | Nada fuera del ejemplar medido; no es tarea de investigación |
| Hechos `inferred` existentes | Nada por sí solos: pendientes de revisión hasta coincidir con otra evidencia | Vincular ni publicar como declarados |

Regla de oro: un vínculo exige identidad exacta; un hecho exige la fuente que
lo imprime; un claim exige la frase del fabricante. Falta de fuente deja el
campo ausente, nunca «Otro» ni un valor plausible.

## 3. Productos genéricos

Marcas sin documentación técnica: sin marca 279, Genérico 110, Aliexpress 48,
Andes Industrial 46, Taiwan 36, MKR 34, Radical Mountain 30, RBX 25, Best 23,
Ozono 19, Eclipse 18, 10Ten 18, Deemount 14, China 13, y «Nescafé» 19, una
anomalía que la auditoría investiga antes de calificarla (corregido el
2026-09-06: no es un error que el nombre permita afirmar). El «cerca del
45 %» es una estimación sin verificar.

Tratamiento:

- Identidad `family_known`, sin referencia, sin claims. El taller los ve como
  «sin confirmar», que es la verdad.
- Hechos nominales que el envase o el nombre imprimen, con cita, por el
  pipeline de lectura del nombre ya existente. Para cámaras y neumáticos eso
  es casi toda la ficha útil: ETRTO, ancho, válvula. Para rayos: largo y
  calibre. Para cadenas: denominación 1/2×1/8 o 3/32.
- Para cada marca importadora, una búsqueda acotada única de ficha técnica,
  registrada en `brand-sources.json` con veredicto; no se repite por producto.
- Lo que sólo existe en la pieza física (medidas) se lista como «requiere
  medición» por familia, para un flujo de medición en recepción que no es
  parte de esta investigación y que alguien deberá ejecutar en taller.

## 4. Discrepancias

| Caso | Política |
|---|---|
| Dos fuentes OEM del mismo fabricante difieren (web 5/6 frente a catálogo 6 en Z6) | Se siembran sólo los hechos en que coinciden; el campo disputado queda ausente y la discrepancia va a `discrepancies.md` con ambas citas y fechas. Si hace falta elegir, el catálogo fechado más reciente manda, y aun así el campo no se siembra hasta resolverlo |
| Referencia OEM contra hecho existente `supplier_text`, `import` o `inferred` | La referencia gana sólo con identidad exacta; el valor anterior se guarda en el registro del lote y se reemplaza en el mismo guardado. Sin identidad exacta no se vincula |
| Referencia OEM contra hecho `mechanic`, `name_reading` con recibo o medición | Nunca se sobrescribe en automático. Va a una lista de conflictos que Codex y Claude resuelven con evidencia; sin evidencia queda sin vincular |
| OEM del modelo contra regla general de Sheldon o Park | El modelo manda para ese modelo; la regla sigue general. Se documenta como caso acotado, como hizo K07 |
| Página OEM inaccesible por bloqueo automático | Se lee con el navegador integrado y se cita el texto renderizado; si tampoco así, hueco registrado, no inventado |

## 5. Lotes

Orden por rendimiento OEM esperado y valor para el taller. Cada lote entrega
`references.json` con evidencia, `discrepancies.md`, informe de simulación
sin escritura, aplicación por RPC con recibos y read-back.

| Lote | Alcance | Productos | Fuentes | Rendimiento esperado | Prerrequisito |
|---|---|---|---|---|---|
| L0 Herramientas | Registro de marcas, esquema de hoja de investigación, simulador de vínculos, aplicador por lotes, informe de cobertura, auditoría de `inferred` y del dato «Nescafé» | — | — | — | Codex; sin escritura productiva |
| L1 Shimano | Cambios traseros 34, delanteros 15, mandos 32, cassettes 29, bielas 27, frenos de llanta 24, manillas 15, cálipers 11, ruedas libres 28, rotores 18, pastillas 49 | ~110 Shimano, 98 con código en el nombre | `productinfo.shimano.com`, `bike.shimano.com`, manuales SI; ambos bloquean el fetch: navegador integrado | Alto: la mayoría con página por modelo | L0 |
| L2 Neumáticos y cámaras | 113 + 132, todos con hechos nominales | Maxxis 29, Kenda 16, Chaoyang 22, Arisun 26; el resto genérico | Páginas OEM con ETRTO, talón, TPI, tubeless; para genéricos, sólo lectura del nombre con K14 | Medio: OEM en ~90; nominal en el resto | L0 |
| L3 KMC, SunRace, Weinmann, Vuelta, Neco, On Guard | Cadenas restantes, cassettes y ruedas libres SunRace 17, llantas 16 + 14, direcciones y pedalieres Neco 22, candados 21 | ~115 | KMC EU/US/global y catálogo 2026; SunRace, Weinmann, Vuelta, Neco: catálogos PDF | Medio-alto | L0; cadenas ya hechas |
| L4 Ruedas, mazas, rayos, rodamientos | 48 + 48 + 41 + 9 | Casi todo genérico; mazas Shimano por productinfo | Bajo en OEM; nominal en rayos ya existe | L1 para lo Shimano |
| L5 Categorías sin plantilla | 706 productos en 75 hojas | Primero familia y plantilla según la matriz §3, empezando por las de calce mecánico: pedales, tijas, tees y manubrios, puños, horquillas, adaptadores de freno, mangueras y fittings, cables y fundas | Depende de cada familia | Plantillas nuevas por Codex; no clasificar por analogía |

Lo que no entra en ningún lote como llenado: accesorios sin interfaz mecánica
(cascos, guantes, poleras, luces, botellas). Reciben familia con atributos
propios cuando exista plantilla; no reciben claims.

## 6. Revisión independiente

- Reparto sin archivos compartidos: Claude investiga y escribe
  `research/<lote>/references.json`, `evidence.md` y `discrepancies.md` en un
  directorio propio; Codex convierte a migración, siembra y aplica. Para los
  lotes que Codex investigue, Claude revisa antes de la migración.
- Revisión obligatoria del 100 % en: toda referencia con claim exclusivo o con
  exclusiones, todo MPN y GTIN, toda presentación con cantidad, y toda
  resolución de conflicto contra un hecho `mechanic` o con recibo.
- Muestra aleatoria del 20 % en hechos simples; una discrepancia en la muestra
  amplía la revisión al lote completo.
- Cada referencia lleva: URL o catálogo y página, fecha de consulta, método
  (fetch, navegador, PDF), citas literales de cada hecho y claim, mercado y
  edición, presentación o «por confirmar».
- Nada que el motor pueda convertir en «incompatible» entra sin dos lecturas.

## 7. Cobertura

Se mide por producto y se agrega por familia y lote; nunca como porcentaje de
formulario lleno.

| Indicador | Definición |
|---|---|
| Estado de identidad | `unresolved`, `family_known`, `model_resolved`, `variant_resolved`, `conflicting` |
| Vínculo | Con referencia; de modelo o de presentación |
| Hechos críticos | Los que la matriz marca como decisión inicial y dependencias de esa familia; no todos los campos |
| Claims | Presentes con fuente; exclusivos y exclusiones aparte |
| Sin OEM | Conteo honesto de productos cuya marca no publica ficha |
| Requiere medición | Hechos críticos que sólo existen en la pieza |

Objetivo realista tras L1–L3: referencias para unos 300 a 350 productos, hechos
nominales conservados o completados en unos 600, identidad de familia para los
706 sin plantilla a medida que L5 cree sus plantillas. El resto es «sin OEM»
o «requiere medición», y se reporta con esos nombres.

## 8. Conservación de observaciones existentes

- Toda escritura pasa por `save_product_with_specs_v1` con `p_expected_revision`,
  `p_expected_updated_at` y clave `catalog-fill/<lote>/<producto>/<n>`. El
  writer ya conserva fuente y `updated_at` de un hecho explícito igual al de la
  referencia; los vínculos no reatribuyen observaciones.
- Nunca se borran ni sobrescriben `mechanic`, `name_reading` con recibo ni
  mediciones. `supplier_text`, `import` e `inferred` sólo ceden ante
  identidad exacta, con el valor anterior en el registro del lote.
- Cada lote corre primero en simulación: lista de vínculos propuestos,
  hechos que cambiarían, conflictos y productos sin acción. Sólo después se
  aplica, y el read-back compara conteos y muestras contra la simulación.
- Por lote se archiva el antes y después de cada producto tocado, para poder
  restaurar sus hechos con otro guardado. Las referencias son inmutables; un
  vínculo se deshace desvinculando.
- Los 229 hechos `inferred` se auditan en L0: los que coinciden con envase,
  nombre u OEM se conservan con esa evidencia; los demás quedan marcados
  pendientes, no se borran.

## 9. Límites reales

- Shimano y SRAM bloquean la lectura automática; por modelo son uno o dos
  minutos de navegador. L1 es el lote más valioso y el más lento.
- Cerca del 45 % del catálogo no tendrá referencia porque su marca no publica
  fichas; ahí el techo son los hechos nominales del envase.
- La identidad estructurada parte de cero: modelo en 12 productos, MPN en
  ninguno. El extractor ayuda donde el nombre trae código; el resto necesita
  el envase, que hay que fotografiar en tienda.
- Las medidas que sólo existen en la pieza no se investigan; se listan.
- Las 37 plantillas no son el catálogo: 706 productos necesitan familia y
  plantilla antes de cualquier hecho, y eso es trabajo de diseño por familia,
  no de llenado.
- Cada lote cambia `contract_version` cuando toca plantillas; los editores
  abiertos recargan, como ya ocurre.

## 10. Primeros pasos

Codex, esta semana: L0 completo; auditoría de marcas y del dato «Nescafé»;
simulador y aplicador con recibos; informe de cobertura como wrapper de lectura.

Claude, esta semana: `brand-sources.json` para las 30 marcas principales con
veredicto OEM; hoja de investigación de L1 empezando por cambios traseros y
mandos Shimano, con cita literal por hecho; `discrepancies.md` vacío con el
formato acordado; revisión del primer `references.json` de Codex cuando exista.

Ambos: acordar el esquema de `references.json` extendido con `evidence` antes
de la primera hoja, para que la migración lo consuma sin transformar.

---

## Observaciones finales sobre el plan integrado y el preparador — 2026-09-06, 16:00 PDT

Revisé `catalog-fill-execution-plan-2026-09-06.md`, `catalog-fill-coverage.sql`,
`catalog-fill-manifest.sql` y `scripts/inventory/prepare_product_spec_research.py`,
con lecturas de producción sobre el tenant `vinabike`. Sin cambios de código,
SQL ni datos.

### Ajustes que acepto

Los seis ajustes de Codex son correctos y corrigen afirmaciones mías: una marca
importadora se comprueba antes de declararla sin ficha; «Nescafé» es una
anomalía por investigar, no un error que yo pueda afirmar por el nombre; ropa,
accesorios y herramientas entran con atributos propios; el distribuidor es
evidencia nominal atribuida, no descartable; `inferred`, `import` y
`supplier_text` no se sobrescriben por su etiqueta; y el read-back compara el
100 % de campos escritos. El «45 % sin OEM» y las «300–350 referencias» quedan
como estimaciones mías sin verificar.

### Lo que está bien en la preparación

- Las dos consultas acotan por `tenants.subdomain = 'vinabike'`, incluyen
  inactivos y excluyen servicios; no hay productos con `is_active` nulo, así
  que preparador y cobertura cuentan igual.
- El preparador no toca la base, exige `spec_revision` y `updated_at` por fila,
  agrupa lo sin plantilla por categoría sin inventar familia, y ordena
  conectores y cadenas primero.
- Comprobé que los 10 hechos `catalog` y los `mechanic` que existen en
  producción pertenecen a bicicletas, no a productos: el inventario de fichas
  de producto sigue sin relleno.

### Omisiones concretas para iniciar el primer lote

Ordenadas por lo que bloquean. Las tres primeras bloquean **investigar y
revisar** research-001 a 003; las siguientes bloquean **aplicar**.

1. **El manifiesto no trae los valores actuales de los hechos, sólo su
   procedencia.** El contrato de investigación exige «valor actual y
   procedencia» por campo y el revisor necesita detectar conflictos sin base.
   Añadir a `catalog-fill-manifest.sql` la proyección
   `spec_payload_display_internal_v1(spec_product_payload_internal_v1(p.id))`
   junto a `existing_observations`.
2. **El manifiesto no trae las referencias disponibles ni el proveedor.**
   `reference_candidate` nace vacío sin lista de candidatas; y 1 385 productos
   tienen `supplier_id`, que es la pista para catálogos de distribuidor, pero
   la columna no sale. Añadir nombre del proveedor, `supplier_reference` y
   `supplier_code` al manifiesto, y una consulta `catalog-fill-references.sql`
   con id, familia, marca, modelo, MPN, etiqueta, hechos proyectados, claims y
   fuentes de las once referencias vigentes. `manufacturer` está vacío en todo
   el catálogo; no aporta hoy.
3. **No hay esquema de propuesta por campo.** La cola deja `proposals: []` sin
   forma, y dos agentes van a escribir archivos que el simulador tendrá que
   consumir. Propongo fijar ahora este mínimo por producto:
   `identity {brand, model, manufacturer_sku, gtin, evidence[]}`;
   `reference {id | null, binding_level: model | presentation, evidence}`;
   `facts[] {key, current {value, source}, proposed, unit, method,
   evidence {kind: oem_page | oem_catalogue | packaging_photo | distributor |
   name_quote | measurement, url | file, page, fetched_at, quote}, scope,
   reason}`; `conflicts[]`; `review {by, verdict, date}`. Y `references.json`
   con `evidence` por hecho con la misma forma.
4. **La procedencia que el servidor admite no cubre la investigación.**
   `spec_facts_source_known` sólo acepta `mechanic`, `catalog`,
   `supplier_text`, `inferred`, `import` y `name_reading`. El comando de
   guardado marca `mechanic` todo hecho explícito y `catalog` lo derivado de
   referencia; `record_product_spec_reading_v1` sólo acepta citas que estén
   en nombre o descripción del producto. Un hecho nominal tomado de un
   distribuidor o de la foto del envase no puede escribirse hoy con su
   atribución: quedaría como `mechanic`, que es falso. Antes de aplicar el
   primer lote hay que decidir una de dos: ampliar la restricción y el writer
   con procedencias `research`, `packaging` y `distributor` con identificador
   de lote, o limitar la aplicación del lote a vínculos de referencia
   (`catalog`) y citas del nombre (`name_reading`). Lo primero es una
   migración pequeña; lo segundo deja fuera la evidencia de distribuidor que
   el plan quiere aprovechar.
5. **El aplicador no tiene identidad.** Los RPC exigen `auth.uid()` y
   `user_tenant_id()`; el patrón del contrato es
   `set_config('request.jwt.claims', {sub, role})` más
   `set_config('role','authenticated')`. Falta decidir el usuario: propongo
   una cuenta dedicada en `user_profiles` del tenant, distinta del dueño, para
   que cada escritura sea atribuible y separable en auditoría, con claves
   `catalog-fill/<lote>/<producto>/<n>` y `p_expected_revision` y
   `p_expected_updated_at` releídos en el momento de aplicar.
6. **No existe archivo de evidencia.** Falta la convención de dónde viven el
   texto renderizado de una página bloqueada, la extracción de una página de
   catálogo y la foto de un envase: propongo `research/<lote>/evidence/` con
   un archivo por referencia, fecha y método, y para PDF grandes sólo hash
   SHA-256 y texto de la página, no el archivo. De las 1 313 imágenes, 1 292
   están en el almacenamiento propio; eso no demuestra que sean fotos de la
   tienda, así que se registran como «imagen del ERP» y sólo aportan MPN o
   presentación cuando el envase es legible.
7. **Los hechos críticos por familia no están en ningún archivo legible por
   máquina.** El `pending` de la cola es genérico y la métrica de cobertura no
   puede calcularse. Para cadenas y conectores la lista ya está en mi revisión;
   conviene un `critical-fields.json` por familia, derivado de la matriz, que
   la consulta de cobertura consuma.

### Expectativa realista del primer lote, para no leerlo como fracaso

- Conectores: cuatro KMC del inventario pueden vincularse a referencia de
  modelo si el nombre o la foto identifican CL573R, CL566R, CL559R y CL555R;
  la cantidad por envase no se infiere de «2 pcs». Los cinco Risk quedan como
  familia conocida con clase de velocidad del nombre.
- Cadenas: cero vínculos sin foto de envase, porque las cinco referencias de
  cadena son presentaciones de 114 eslabones y los nombres dicen 116, DISPLAY
  o nada. Sí se puede confirmar modelo por código en unos quince nombres KMC y
  Shimano. X9, X10, Z6, HV410, K710 y S1 no tienen referencia todavía: el
  lote necesita el ciclo completo investigación → `references.json` →
  migración de siembra → aplicación, y la Z6 sigue con su discrepancia.
- Ninguna de estas dos cosas requiere al dueño; sí requieren el simulador y la
  decisión de procedencia de la omisión 4 antes de escribir.

---

## Veredicto sobre el primer borrador `catalog-fill-first-proposal-cl573r.json` — 2026-09-06

Revisado el archivo con SHA-256
`0bf9bf1cfdf99bee727bc62ce7eb7def33c5a808aa3e672cd8a6dac42a4a4818` contra la
fila del manifiesto regenerado, la referencia `kmc-cl573r-global-20260906`
exportada, la página OEM leída de nuevo hoy en el navegador integrado y la
imagen del ERP. Corrijo mi generalización anterior: eGlide US tiene 126
eslabones y X11 US 118; sólo tres de las cinco referencias de cadena son de 114.

**Veredicto: cambios solicitados. Identidad, vínculo y valores son correctos;
el borrador declara cinco hechos donde el servidor va a escribir seis.**

### Lo que está correcto

- `based_on` coincide con el manifiesto: `spec_revision` 0, `updated_at`
  2026-05-22, plantilla, contrato 24 y el SHA-256 del archivo exportado. Ojo:
  ese hash es del manifiesto completo, así que el archivo usado para el lote se
  conserva hasta aplicar; la guardia real al aplicar sigue siendo revisión y
  timestamp releídos.
- Modelo `CL573R` sale del nombre, que lo imprime tal cual; `current_values` y
  `existing_observations` están vacíos, así que no hay nada que preservar.
- Vínculo a nivel de modelo, sin MPN ni cantidad, es lo que la referencia
  permite: `manufacturer_sku` nulo, etiqueta «presentación por confirmar».
- Los cinco valores propuestos son idénticos a los de la referencia, y la
  página OEM los sostiene hoy: «8 Speed 7 Speed 6 Speed», «Missinglink
  Reusable», «Non directional design», «Compatibility : KMC X8/ Z8.3/ Z7/ Z6
  chains».
- Cobertura contra `catalog-fill-critical-fields.json`: identidad 2 de 2 tras
  el modelo, técnicos 4 de 4, presentación 0 de 1, y eso último es correcto.

### Cambios necesarios antes de marcarlo `reviewed`

1. **Seis hechos, no cinco.** La referencia trae también
   `spec_evidence_source` con la URL de KMC, y el writer mezcla todas las
   claves de `fact_values` no cubiertas por valores explícitos y las marca
   `catalog` (migración 20260906103000, líneas 130–131 y 179). Al vincular, el
   producto recibirá seis hechos `catalog`; la propuesta y el read-back del
   100 % tienen que listar los seis. Añadir el hecho con `origin: reference`
   y la misma evidencia, o declarar un valor explícito distinto si no se
   quiere la URL como nota del operador.
2. **Archivar la evidencia OEM y poner su hash.** `sha256` va nulo y no hay
   copia bajo `research/<lote>/evidence/`; la convención nace muerta si el
   primer borrador no la cumple. El texto renderizado de la página tiene 513
   caracteres; basta guardarlo con fecha y URL. El `finding` debe citar lo que
   la página dice y no lo que se sabe del producto: la página no dice «dos
   placas» y sí dice «Colors: Gold», que hay que anotar porque el producto es
   «Plata».

### Cambios recomendados, no bloqueantes

- **Registrar la imagen del ERP como evidencia `erp_image`.** Es un render de
  fabricante, no una foto de tienda, y no prueba la variante en stock; pero
  muestra la cartela KMC MissingLink «RE-USABLE», «8/7/6 SPEED», «Silver», dos
  conectores, «Perfectly connecting KMC X8 / Z8.3 / Z7 / Z6 chains», «SHIMANO
  6/7/8 speed HG chains» y «Pin length: 7.30mm». Confirma color y coincide con
  «2p» sin permitir escribir la cantidad. El código de modelo no se lee en la
  cartela.
- **Anotar un conflicto en `conflicts` para `chain_connector_target`.** La
  página OEM limita la compatibilidad a KMC X8/Z8.3/Z7/Z6; la cartela OEM
  añade Shimano HG 6/7/8. Dos fuentes del mismo fabricante difieren; la
  referencia lleva sólo lo que coincide, que es lo correcto, y la discrepancia
  se registra en `discrepancies.md` sin cambiar la propuesta. El «Pin length
  7.30 mm» tampoco se propone: no es `chain_outer_width_mm` y no hay campo
  con ese significado.
- **Dejar una pista de presentación para el paso siguiente.** El `sku` y el
  `supplier_code` valen `4715575894768`, un EAN-13 válido con prefijo 471
  (Taiwán), la carpeta de la imagen lleva ese mismo número y el campo
  `barcode` está vacío. No se propone `gtin` sin una fuente que lo ate a CL573R
  plata 2 unidades, pero es la vía más corta hacia el vínculo por presentación.
- **Al aplicar, identidad y vínculo van en el mismo guardado.** El writer
  rechaza la referencia si `p_model` no coincide con `CL573R`; el aplicador
  debe enviar el modelo en `p_product` y el `p_reference_id` en la misma
  llamada, no en dos.

Con los dos cambios necesarios y sin otros, lo doy por aceptado sin otra
vuelta; Codex puede poner `review.by: claude`, `verdict: accepted` y el hash
del archivo corregido citando esta sección. Si cambia algo más, lo vuelvo a
leer. Nada de esto se aplicó ni debe aplicarse hasta resolver la procedencia
de investigación y el canal autenticado que el plan registra como trabajo
previo.
