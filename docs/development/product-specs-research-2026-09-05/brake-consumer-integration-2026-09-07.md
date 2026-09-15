# Consumidor de frenos: fluido, accionamiento y superficie

2026-09-07: corrección local integrada en
`BikeProductCompatibilityService.buildAutocompleteAssessments`. No publicación
del catálogo ni cambios de hechos. Las 49 pruebas de su suite pasan (9 nuevas);
el analizador informa una recomendación `const` anterior, sin errores/warnings.

## Causa y cambio

La ruta de detalle trataba cualquier `fluid_type` reconocido como prueba de
que el producto exigía una bici con `brakeType=hydraulic_disc`. Es falso para
dos modelos documentados:

- [TRP HY/RD, ficha y manual enlazado](https://eu.trpcycling.com/products/hy-rd):
  entrada por cable, circuito hidráulico dentro del cáliper. Que use aceite
  no convierte su entrada en conexión para una manilla hidráulica.
- [MAGURA HS33](https://magura.com/product/hs/) y
  [manual HS](https://api.magura.com/medias/sys_master/maguracom-medias/h4c/hd0/9603888545822/hs_manual_2017_en/hs-manual-2017-en.pdf):
  freno hidráulico de llanta. El fluido no determina superficie de disco.

Se retiró esa inferencia. La superficie `Disco`/`Llanta`, cuando está declarada
en ambos extremos, sí puede producir una discrepancia concreta. El fluido
conserva un aviso para verificar el modelo y sus componentes; ni la misma
clase de aceite ni el mismo diámetro certifican el conjunto.

La ruta por familia tenía un segundo atajo independiente: `brake_caliper`
significaba siempre cáliper de disco y rechazaba una bicicleta con freno de
llanta aun sin datos del producto. Se retiró también. Una familia genérica
deja superficie, entrada y montaje por confirmar; las dos superficies
explícitas opuestas siguen produciendo una discrepancia.

Esto respeta la separación de interfaces de
[Sheldon Brown, cables](https://www.sheldonbrown.com/cables.html) y de
[manillas para direct-pull](https://www.sheldonbrown.com/canti-direct.html).
[Park Tool, servicio hidráulico](https://www.parktool.com/en-us/blog/repair-help/shimano-hydraulic-brake-service-and-adjustment)
requiere el fluido específico del sistema, sin intercambiar DOT/mineral, y
remite al procedimiento del modelo. Ninguna regla nueva deduce aceite por
marca o intercambia DOT 5 con DOT 5.1.

## Evidencia y límites

- Reproductor independiente anterior: `.tmp/product-spec-catalog/brake-packet-review-probe.dart`.
  Sus dos primeras aserciones describen el defecto anterior; no deben usarse
  como expectativa actual.
- Regresiones activas: `test/unit/bike_product_compatibility_service_test.dart`.
  HY/RD y HS33 pasan a aviso, sin aprobar instalación; fluido solo es aviso
  frente a llanta, disco mecánico o disco hidráulico. Dos superficies explícitas
  opuestas siguen rechazadas.
- `.tmp/product-spec-catalog/brake-consumer-integration-test.log`: 49/49.
- `.tmp/product-spec-catalog/brake-consumer-analyze.log`: 0 errores/warnings.
- Sesión nativa `payroll`, PID 90499: recarga de 43/5382 bibliotecas en
  4.685 s; `.tmp/product-spec-catalog/brake-consumer-native-reload.log`.
  Es evidencia de integración del servicio, sin atribuir al frame una
  prueba de montajes ni del catálogo ampliado aún no publicado.

Queda abierto conectar las declaraciones de interfaces schema2 con una
configuración instalada tipada. El revisor demostró que hoy se resumen pero
no se evalúan en esta ruta. No se arregla mezclando indiscriminadamente hechos
del producto con los de la bici: primero hay que definir qué extremo aporta
cada campo, conservar la identidad del modelo instalado y resolver unknown.
También siguen pendientes campos de tiro, conexiones, pastillas y adaptadores
del paquete global. Este cambio no declara terminada la familia de frenos.
