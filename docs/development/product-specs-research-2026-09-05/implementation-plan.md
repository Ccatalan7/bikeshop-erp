# Fichas técnicas: implementación y revisión independiente

Estado: implementación autorizada por Claudio el 2026-09-05. Este documento
complementa el contrato de arquitectura; no convierte el diagnóstico en prueba
de funcionamiento.

Actualización 2026-09-06: la base descrita en los pasos 1–4 está integrada en
código y en el servidor, con el alcance y las verificaciones del
[resultado](implementation-result.md). El catálogo mecánico completo por
familias sigue siendo trabajo explícito de la matriz, no una consecuencia de
que las 37 plantillas compartan el motor.

## Qué cambia tras la opinión de Claude

Se adopta su aporte principal: la ficha debe pedir menos decisiones. La identidad
y los hechos primarios se editan; una propiedad derivada se muestra con su origen;
una declaración del fabricante conserva su alcance. Presentar cuatro selectores
como cuatro decisiones independientes hace incoherente la ficha aunque cada uno
tenga un filtro. La propuesta anterior explicaba mejor la integridad que esta
simplificación del trabajo del operador.

Verificado en el código: se borraban respuestas manuales al cambiar requisitos,
la intersección vacía recuperaba opciones, las lecturas fallidas parecían una ficha
vacía y producto/ficha se escribían en transacciones separadas.

No se convierten las generalizaciones mecánicas de la respuesta en bloqueos:
[Park Tool](https://www.parktool.com/en-us/blog/repair-help/chain-compatibility)
describe anchos nominales; [Sheldon Brown](https://www.sheldonbrown.com/speeds.html)
documenta algunos usos de cadenas más estrechas en transmisiones anteriores.
[KMC X11](https://kmcchain.us/products/x11) declara las tres marcas y
[eGlide](https://kmcchain.us/products/eglide) limita 9/10/11 a LINKGLIDE.
Por tanto no hay umbral universal de ancho exterior, exclusión de Campagnolo
por ser KMC, ni regla universal de velocidades contiguas. Una medida física,
una denominación nominal y una declaración de montaje siguen siendo hechos
distintos, aunque no necesiten tres preguntas obligatorias.

## Orden de ejecución

1. **Motor común y borrador seguro.** Condiciones tipadas de tres estados,
   requisitos explícitos, validación completa independiente de los widgets,
   intersección vacía como conflicto y conservación de respuestas manuales.
   Aplicar el mismo contrato a las 37 plantillas observadas, sin certificar por
   ello los catálogos mecánicos de las 36 familias.
2. **Identidad y presentación.** Referencias de fabricante versionadas y
   seleccionadas explícitamente. Datos primarios primero, valores de referencia
   con fuente y declaraciones por separado. Retirar para cadenas las inferencias
   circulares de marca/ecosistema/perfil/ancho. Booleanos sin responder conservan
   su tercer estado. Los valores anteriores en conflicto permanecen visibles y
   se corrigen o retiran expresamente.
3. **Persistencia.** Referencias y reglas en servidor; valores de lista por UUID;
   validación de plantilla, tipo, opciones y requisitos antes de escribir.
   Comando atómico de identidad y ficha con revisión y recibo de operación,
   incluyendo la ruta de juegos. Lectura fallida o respuesta de categoría anterior
   no puede vaciar la ficha. No corregir masivamente fichas existentes.
4. **Verificación e integración.** Casos mecánicos independientes con fuente,
   paridad Dart/SQL, guardado inválido sin cambios parciales, aislamiento de tenant,
   revisión obsoleta y reintento idempotente. Analizador de lib/test, pruebas
   afectadas, migración mínima con read-back e historia, y comprobación visual en
   la sesión canónica `payroll`. Registrar superficies y evidencia real.

## Criterios de aceptación

- Seleccionar una referencia exacta ofrece sus propiedades, sin pedir versiones
  contradictorias del mismo dato. Cambiar marca/modelo deja visible el conflicto
  con esa referencia y no altera silenciosamente valores del producto.
- Una KMC con declaración explícita multimarcas es válida. eGlide no se convierte
  en una cadena universal 9/10/11. Ancho exterior por sí solo no decide velocidades.
- Cambiar un requisito no borra una respuesta manual; el formulario explica qué
  debe revisarse y el servidor rechaza un estado contradictorio.
- Una lectura fallida no equivale a cero hechos. El guardado no adelanta la
  identidad si falla la ficha, ni pisa una revisión más reciente.
- No se presenta una familia sin reglas de fabricante como compatibilidad
  comprobada. La cobertura por modelos y las familias todavía pendientes se
  mantienen explícitas en la matriz y en la evidencia de cierre.

## Recuperación

Migración aditiva y funciones versionadas; mantener datos existentes. Probar en
local antes del despliegue guardado. Un fallo de validación conserva el borrador.
Una reversión de comportamiento requiere otra migración hacia delante; no editar
una migración ya aplicada ni borrar hechos para que pase una validación.

## Fuente visual y decisiones de composición

Se leyó el contenido de `GUÍA GENERAL Viñabike - Componentes` recuperado de un
`DesignSync get_file` del 2026-08-27, proyecto
`a0fa3196-6315-4b96-bde7-7cc801e7a74e`. Ruta de la copia:
`/private/tmp/claude-502/-Users-Claudio-Dev-bikeshop-erp/698d4a4c-c95c-41fa-a3a1-9d4c76e19df8/scratchpad/guia.html`.
SHA-256: `ba4c0745912e4a65d7d3069c901067d433e3a1bad3d7c11d34a33d03899f4cc3`.
La respuesta estaba truncada a 262144 bytes. No hubo autenticación DesignSync
vigente; no se presenta esta copia como una lectura actual ni se estimaron
valores de una captura de Design.

| Decisión | Aplicación y motivo |
|---|---|
| Adoptar F-02/F-04 y anatomía de panel S-04 | `VbFormSection` compartido: radio 10, borde hairline 1, padding vertical 16/horizontal 18, título IBM Plex Sans 13.5/600; colores del tema. Se conserva la contención, no se convierte en una receta para todos los módulos. |
| Adoptar I-01 | Rótulo sobre el control mediante el owner existente; ayudas completas en compacto. No se inventa otro campo flotante para specs. |
| Adoptar S-04/S-05/S-06 | Booleano de tres estados en S-04; selector corto en S-05 dentro de su límite y búsqueda en S-06 para listas largas/referencias. `Sin dato` cabe en compacto y sigue significando null. |
| Adoptar E-04 | Un aviso de superficie; pendientes en tono de advertencia y conflictos explícitos en error. El helper de cada campo nombra su requisito o conflicto. |
| Descartar la jerarquía de la captura inicial | Ecosistema singular y perfil heredado de cadena dejan de ser decisiones activas. El screenshot muestra el problema, no una autoridad mecánica o visual. |
| Agregar identidad antes de referencia | La variante sólo se ofrece para marca/modelo confirmados; elegirla completa MPN y no cambia el modelo silenciosamente. En compacto la actualización baja debajo del nombre. |
| Mantener legibles los datos derivados | Referencia, hechos y fuente se muestran como lectura. El patrón de borde discontinuo no era legible en la copia, así que no se inventó un patrón visual. |

La revisión contra negocio, terminología, backend, navegación, claro/oscuro y
hosts, y owner compartido produjo esta composición. Los frames reales y sus
límites están en el resultado: macOS a tres anchos, pruebas del control en seis
celdas; no se afirma comparación con un canvas específico de módulo ni ejecución
en iOS Simulator.
