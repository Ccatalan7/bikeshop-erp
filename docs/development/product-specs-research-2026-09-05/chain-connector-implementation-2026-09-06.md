# Segunda entrega: cadenas y conectores — 2026-09-06

Estado: segunda entrega implementada, aplicada y verificada. Continúa la base aplicada
`20260906070000`; esa migración permanece inmutable.

## Decisiones contrastadas con Claude

La [propuesta independiente](chain-connector-claude-review-2026-09-06.md)
aporta el flujo propio del conector, los modelos objetivo, reutilización por
modelo y el límite incorrecto de 7,8 mm. Se aceptan esos puntos. El inventario
verificado por `chain-connector-audit.sql` contiene 31 cadenas y 9 conectores;
los 40 carecen de modelo/MPN estructurado. No se hace backfill desde sus nombres.

Se ajustan estas conclusiones antes de implementarlas:

- Un conector se evalúa contra la cadena instalada. El contexto actual del
  taller no contiene esa identidad; se muestra el alcance OEM y la necesidad
  de confirmarla, sin enfrentar la clase de cadena al número de piñones de la
  bicicleta (SM-CN900-11 también sirve a cadenas LINKGLIDE).
- No se deriva un hecho OEM de `Single speed / BMX / IGH` ni del ancho. Un
  producto puede tener varias aplicaciones y el IGH tiene marchas internas.
  Se conserva la captura manual, con requisitos explícitos y sin ciclos.
- No se renombra toda plataforma a «exclusiva»: una declaración no demuestra
  exclusividad. Ésta sigue perteneciendo a un claim con fuente y alcance.
- Ocultar preguntas por comodidad no es una prohibición mecánica. En este
  contrato `visibility_rules=false` sí bloquea valores presentes; por eso no
  se introducen las ocultaciones propuestas por velocidad o modo sin respaldo.
- La regla de cadena 1/8 + desviador + cobertura 5…13 se aplica sólo con los
  tres datos presentes. [Sheldon](https://www.sheldonbrown.com/gloss_ch.html)
  distingue las cadenas para más de tres piñones, y el
  [glosario KMC](https://www.kmcchain.eu/service/glossary) reserva las anchas
  para single/IGH. No se extrapola a montajes históricos de 2–3 piñones.
- Los rangos orientativos de un glosario no son límites físicos universales.
  Se retiran 5,2…7,8 mm y 72…136 eslabones como prohibiciones, manteniendo
  medidas positivas y conteos enteros positivos. KMC documenta anchas de
  8–10 mm y rollos; Shimano comercializa cadenas de 138 eslabones.
- «2 piezas» puede ser un único cierre de dos mitades. Cantidad significa
  conectores completos; nunca se infiere desde ese texto.
- CN-HG701-11 declara peso por 114 eslabones: no se toma eso como longitud
  vendida. No se siembra esa presentación sin SKU confirmado.
- Z6 BZ06G0114 tiene discrepancia OEM: la página declara 5/6, el catálogo
  europeo 2026 de junio declara 6. Se registra y queda fuera del nuevo seed.

## Entrega concreta

1. Conector: tipo primero; clase de cadena después; fuente antes de modelos
   objetivo/reutilización/dirección. Retirar modo y ecosistemas genéricos de
   la captura del conector, conservando sus valores anteriores para revisar.
2. Reglas compartidas Dart/SQL: requisitos tipados, validación numérica,
   prohibición estrechamente acotada de 1/8 y pasador desechable.
3. Referencias OEM inmutables por modelo o presentación. El alcance se muestra
   expresamente; una referencia sin MPN no borra un MPN del operador.
4. Ayuda de identidad a partir del extractor canónico: sugerir sólo modelos
   del producto, requerir confirmación y nunca vincular una variante por nombre.
5. Pruebas de contrato, persistencia local, compatibilidad y frame real en la
   sesión `payroll`; revisión crítica de Claude, deploy mínimo y read-back.

## Evidencia de fuentes

- Bases: [Park Tool, reemplazo de cadena](https://www.parktool.com/en-us/blog/repair-help/chain-replacement-derailleur-bikes),
  [Sheldon, uniones](https://www.sheldonbrown.com/chains.html).
- [Catálogo KMC Europa 2026, revisión 12 de junio](https://www.datocms-assets.com/104526/1781274377-kmc-2026-dealer-catalogue-en-260612.pdf),
  obtenido desde [descargas oficiales](https://www.kmcchain.eu/service/downloads),
  página PDF 30 / impresa 59 inspeccionada visualmente: Z8.3 BZ08NG114 114,
  Z7 BZ07GB114 114, Z6 BZ06G0114 114; presentaciones DISPLAY 116 y rollos
  separados, con sus propios códigos. No combinar cajas distintas.
- HV408/HV410/K710 y Risk/ZTTO: búsqueda acotada sin ficha OEM exacta. Se
  conservan manuales; no se sustituye HV408 por X8.

## Resolución de la revisión crítica

- La regla local antigua `Single speed → velocidades [1]` no existía en
  producción ni pertenecía a la nueva migración. La migración ahora elimina
  explícitamente esa heurística en ambas plantillas. Se reaplicaron en local
  la migración base exacta y la nueva, conservando el fixture histórico del
  repositorio; no se reconstruyó todo el historial. La fixture se reexportó
  desde ese resultado. La comparación con el inventario de metadatos previo
  sólo muestra diferencias escritas explícitamente por esta entrega.
- La regla del pasador cita Sheldon además de Park: la fuente debe sostener
  precisamente el atributo prohibido, no sólo tratar el mismo tema.
- `spec_evidence_source` es evidencia del operador, no una propiedad física
  que deba coincidir literalmente con la URL de la referencia. Se excluye
  del conflicto de referencia en SQL/Dart, permanece editable en el formulario
  y el writer conserva su procedencia `mechanic` cuando se envía manualmente.
  Las fuentes inmutables OEM permanecen en la referencia. Sin corregir también
  esa procedencia, al reabrir/desvincular se perdía la nota por considerarla
  automática; la regresión cubre todo ese recorrido. La revisión final extendió
  la conservación a **todos** los hechos enviados explícitamente: una observación
  previa igual al catálogo conserva fuente, lecturas y timestamp al vincularlo.
- Las dos nuevas cadenas usan `claims.coverage` para la cobertura amplia;
  `platform` se reserva para un sistema técnico y no recibe esa prosa.
  Las tres referencias ya aplicadas permanecen inmutables.
- El read-back compara las dos plantillas completas (campos, orden, reglas,
  fuentes, tipos), las ocho ediciones completas y ambas funciones privadas.
  También comprueba ACL, opción `clip`, discrepancias y evidencia independiente.
  Las revisiones de plantilla son contadores del entorno, no hashes de contenido.

## Resultado y comprobaciones

- **99 pgTAP** (44 de esta entrega y 55 del contrato base), incluidos guardado
  atómico, rechazo, reintento, lectura de procedencia y desvinculación.
- **78 Flutter** de contrato, compatibilidad, booleanos y navegación. Tras
  añadir etiquetas accesibles y claves estables a los campos de texto/número,
  se repitieron los 28 casos afectados y pasaron. Analizador: cero errores y
  advertencias; permanecen los avisos informativos del código existente.
- Migración `20260906103000_chain_connector_spec_contract.sql` aplicada y
  registrada, verificada a **2026-09-06T21:24:46Z**. SHA-256:
  `f56318fe926b2620ceb143aeeb490cb6d07585a9a3de64c268ffd99d6f066eeb`.
  El read-back ejecutable verifica plantillas, ocho ediciones, funciones
  completas, ACL y comportamiento; SHA-256 del verificador:
  `601a9f949e340b3c5c3f3975ab5d7b26056ec951ab9faa5b3c1a9d06450c7cd0`.
- Comparación antes/después: los **40 productos activos de cadenas/conectores
  permanecieron idénticos**, incluidos identidad, referencia, revisión y hechos.
  No hubo backfill ni guardados de prueba en producción.
- Sesión macOS `payroll` reutilizada y recargada. En un espacio nuevo se abrió
  CL573R y se comprobó sugerencia de modelo con confirmación explícita,
  referencia limitada al modelo, nota manual conservada al desvincular,
  requisitos deshabilitados y rechazo de 1,5 conectores. El escenario `Pin`
  fue un borrador temporal para probar el control; no es una especificación
  atribuida a CL573R. La app dejó `Sin dato` seleccionado y `Sí` deshabilitado. Al
  terminar se cerró sólo ese espacio de prueba, se restauraron Claro y la
  geometría original, y se verificó intacto el borrador HV408 del dueño
  (11/128 y 7,1 mm) en su espacio original.
- [Frames y semántica](evidence/chain-connector/) en escritorio (1821), ancho
  intermedio (1000) y compacto (430), claro/oscuro. Compacto comprueba composición
  en la ventana macOS; no se ejecutó un nuevo ensayo táctil de iOS ni una nueva
  distribución de la app. Los controles siguen siendo los propietarios comunes
  S-04/S-05/S-06 y `VbFormSection`, sin variantes visuales locales.
- Claude verificó las fuentes OEM, encontró la deriva local y los dos defectos
  de procedencia, y dejó veredicto final **sin bloqueo** sobre el writer corregido.

## Continuación autorizada

La arquitectura por familias y el catálogo documental siguen incompletos.
Esta entrega agrega seis modelos de conector y dos presentaciones de cadena;
no certifica todo KMC ni rellena productos automáticamente. El dueño encargó
también a ambos agentes investigar y rellenar el catálogo completo: quedan
preparados el [plan de ejecución](catalog-fill-execution-plan-2026-09-06.md),
las consultas de cobertura y una cola regenerable de 1.605 productos. El
simulador/aplicador con evidencia por campo es el siguiente requisito antes
del primer lote productivo.
