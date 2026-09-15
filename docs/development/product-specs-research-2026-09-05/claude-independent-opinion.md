# Opinión independiente de Claude antes de implementar

Fecha local: 2026-09-05. Estado: consulta respondida; **sin implementación**.

## Consulta y alcance

El dueño pidió un chat nuevo en Claude, Fable 5.1 y Ultracode, para obtener su
diagnóstico y posible solución sin conocer las conclusiones de Codex.

- Chat: **Diagnóstico fichas técnicas Viñabike**.
- URL observada: `claude.ai/epitaxy/local_3946be48-2ee1-4f75-a046-95f15862b7ab`.
- Preflight visible antes de enviar: Code seleccionado, repositorio
  `bikeshop-erp`, rama `smartpegas1.0`, Fable 5.1, Effort: Ultracode, modo Auto.
- Envío y respuesta final verificados en esa misma conversación.
- Entrada: las dos capturas del editor, las selecciones observadas y la
  preocupación del dueño por identidad, prerrequisitos y compatibilidad.
  Se aclaró que eran momentos distintos, que el modelo exacto no estaba
  identificado y que no se había demostrado un guardado simultáneo.
- Se exigieron Sheldon Brown y Park Tool como fuentes base, con fabricantes
  como complemento. No se compartieron el diagnóstico, la auditoría del
  resolvedor ni la arquitectura de Codex.
- Primera pasada limitada a capturas y fuentes externas. Se pidió no leer
  código, documentación técnica, memorias ni otras conversaciones, y no editar,
  escribir datos, controlar la app ni implementar.

## Independencia y exposición automática

Claude declaró que recibió automáticamente el índice de memoria y `git status`.
Vio títulos breves y nombres de archivos como `product-spec-family-matrix.md`
y `product-technical-specifications-contract.md`, pero afirmó no abrirlos ni
conocer las conclusiones. La UI mostró lectura de las dos imágenes y búsquedas
web. Esto sustenta una primera opinión sin entrega de nuestras conclusiones;
no demuestra una sesión completamente libre de metadatos del proyecto.

## Síntesis de su opinión, no reglas aprobadas

Su hipótesis principal es un solapamiento de conceptos entre velocidades,
familia de ancho, ancho externo y perfiles genéricos, combinado con inferencias
y bloqueos que producen estados contradictorios. Considera que los campos de
ecosistema necesitan un significado mecánico específico según la familia.

Propone separar identidad/hechos primarios, datos derivados por reglas con
fuentes y declaraciones del fabricante con procedencia. Sugiere identificar
marca/modelo mediante referencias de catálogo, preguntar mínimos por familia
cuando esa referencia no exista, y presentar causas de derivación y conflictos.
Su modelo conceptual incluye tipos, cardinalidad, unidades, dominios, roles,
prerrequisitos y reglas por familia. Comparó reglas en código, reglas como datos,
catálogo curado e IA como asistencia. Sugirió casos reales documentados para
validar el resultado y una auditoría posterior de las fichas existentes.

Separó la compatibilidad entre marcas de la interpretación de «Perfil
Campagnolo» y consideró que 6/7/8 simultáneas pueden describir una cadena real.
También propuso generalizaciones por velocidades y bandas de ancho. **Estas
últimas no quedan aprobadas por recibir esta opinión:** siguen pendientes de
contraste con referencias exactas, excepciones y significado de cada medida.
Los valores físicos, las capacidades declaradas y la compatibilidad de montaje
no deben tratarse como hechos equivalentes sin esa comprobación.

## Incertidumbre reconocida y siguiente límite

Claude dejó pendientes el significado real de los campos y vocabularios, el
origen de filtros y ayudas, el posible descarte del 7,1, la persistencia de
«Desconocido», la cobertura del catálogo y los consumidores de compatibilidad.
No inspeccionó código o datos en esta primera pasada; sus afirmaciones de causa
interna son hipótesis, aunque algunas se expresen con firmeza.

No se envió un segundo mensaje con el diagnóstico de Codex. No se adoptaron
sus reglas ni se inició implementación. El contraste de ambas propuestas queda
como trabajo posterior a esta consulta.
