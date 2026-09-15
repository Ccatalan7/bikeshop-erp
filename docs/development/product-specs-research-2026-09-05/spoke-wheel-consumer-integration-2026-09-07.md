# Conteos de rueda y datos de armado en el consumidor

Implementado localmente, con 57 pruebas del consumidor aprobadas. Aún sin
recarga ni prueba del flujo completo de taller. Catálogo ampliado sin publicar;
ninguna ficha rellenada.

Claude revisó la preimagen real en `spoke-wheel-consumer-review-2026-09-07.md`
(SHA `cf852da5dfafbb2661eb3c42508000be941f0048edf2f4607b70ad4856bd4616`).
Su corrección de la premisa es importante: este consumidor no compara largos
con una tolerancia de ±1 mm. El nombre estaba en la lista de claves; la regla
criticada pertenecía al blueprint. No se introduce esa tolerancia.

Root acepta P1–P4 con dos correcciones de integración. Una diferencia de
agujeros en la maza o llanta exige identificar la contraparte y receta del
armado; el texto no asegura que «sirve» ni que el componente actual se
reutiliza. El resultado sigue evaluando válvula, tamaño y otros requisitos;
un aviso temprano no oculta los demás ejes. Los conflictos existentes de
ancho y driver mantienen su precedencia.

`bike.spokeCount` se conserva como dato agregado sin rueda. Sólo los valores
explícitos `frontSpokeHoles` y `rearSpokeHoles` alimentan sus respectivos lados;
un agregado no produce coincidencia ni incompatibilidad por lado. Para rayos
se explicita que hacen falta ERD, offset, geometría por lado, patrón, niple,
calibre y rosca. No se declara aprobado un largo sin receta.

Fuentes verificadas de nuevo por root el 2026-09-07:

- [Park Tool, determinación del largo](https://www.parktool.com/en-us/blog/repair-help/determining-spoke-length-for-wheel-building): conteo entre aro y maza, ERD, offset, dimensiones de bridas por lado y patrón; el método de niple influye en ERD. Su ejemplo de redondeo no crea una tolerancia universal para aprobar productos.
- [Sheldon Brown / John Allen, armado](https://www.sheldonbrown.com/wheelbuild.html): combinaciones de aro y maza, conteos distintos entre ruedas y cálculo de largos según componentes/patrón. Estas bases justifican separar el par de armado de la bicicleta.

Ocho regresiones nuevas cubren diferencia de conteo, avisos concurrentes de
BSD/válvula, agregado sin lado en maza y llanta, valor trasero explícito,
largo sin receta y conservación de conflictos por ancho/driver. Continúan
pendientes la receta con procedencia del cálculo y el consumidor de relaciones
OEM entre productos. La búsqueda `findCompatibleSpokes` de otro servicio
devuelve candidatos con tolerancia; su nombre no constituye certificación.
