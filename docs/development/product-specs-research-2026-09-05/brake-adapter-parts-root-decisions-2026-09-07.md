# Frenos y adaptadores: adjudicación root, 7 de septiembre de 2026

Candidato local no aplicado. Cuatro familias, 25 definiciones, 28 usos y 42 casos. Publicación prevista: 19 definiciones nuevas, 33 opciones, 28 usos y 6 definiciones compartidas conservadas exactamente desde la preimagen viva. 46 pruebas Dart y 42 casos SQL, más cinco regresiones del publicador, verdes. No escribe productos, hechos ni categorías; todas las banderas de cobertura global permanecen falsas.

## Decisiones e independencia de fuentes

1. Cada configuración de adaptador tiene modelo, identificador completo de configuración y ámbito de fuente propios. La clave compuesta impide duplicar una configuración resuelta con destinos contradictorios; no compara alias ni interpreta nombres. El ID debe distinguir posición, edición y montaje; no mezclar variantes por compartir marca.
2. Rosca de montaje a maza y rosca del anillo de cierre son puertos distintos, con celdas distintas. La primera sólo aplica a una maza de rosca especificada; la segunda también existe en sistemas de estrías. Se retiró `thread_owner`. RCF39 mueve la rosca conocida del anillo a su celda, conservando el resultado esperado. RCF38 y RCF39 declaran la función conocida Tipo de fijación: no se inventa un desplazamiento. RCF38 mantiene la rosca de maza sin resolver y el faltante visible.
3. El diámetro de rosca en pulgadas es numérico, separado del paso y su unidad. No duplicar paso en una etiqueta de diámetro. La cantidad física debe ser positiva.
4. Una entrada y salida ambas de seis pernos no demuestra que un adaptador sea inútil o incompatible. [Wolf Tooth Boostinator](https://www.wolftoothcomponents.com/products/boostinator) distingue kits traseros de seis pernos con endcap, separador, tornillos y aparaguado, límite de rotor 183 mm y modelos concretos. El caso Boostinator HR preserva el contexto completo Hope Pro2 EVO/Pro4, trasero, 12x142 y condiciones. No representa un separador suelto universal ni introduce un offset numérico deducido.
5. La función Posición del rotor tiene desplazamiento y datum propios; un cambio de tipo de fijación no los exige. [Shimano DM-MDBR001-05](https://si.shimano.com/en/pdfs/dm/MDBR001/DM-MDBR001-05-ENG.pdf), texto p.8, excluye SM-RT86/SM-RT76 con adaptador de aluminio para SM-RTAD05. Se usa la exclusión textual, no una interpretación de figuras o dimensiones no inspeccionadas.
6. Repuesto y kit contienen piezas, y cada pieza tiene tipo, material, cantidad y destino/edición/configuración propios. Un resorte o clip individual no lleva rosca estructurada; una bolsa con tornillería se descompone por pieza. Tipo/material/modelos globales quedan legacy, no se sobreescriben definiciones compartidas.
7. El freno de maza tiene mecanismo, actuación y posición por configuración. Sus interfaces de montaje enlazan esa configuración por row_id; OLD, diámetro de eje, paso, retención y reacción no se mezclan en un texto único. [Sheldon Brown, coaster brakes](https://www.sheldonbrown.com/coaster-brakes.html) respalda contrapedal, maza trasera y brazo de reacción sujeto; no impone una prohibición universal de actuación hidráulica a otros frenos de maza.
8. [Park Tool, mechanical disc brake alignment](https://www.parktool.com/en-us/blog/repair-help/mechanical-disc-brake-alignment) respalda nombres IS/Post/Flat, no valida las configuraciones sintéticas de fixtures. Sus enlaces fueron retirados de esas supuestas aprobaciones.
9. Las filas intrínsecas preceden a los campos legacy. Ediciones desconocidas permanecen pendientes, no cero ni una aprobación. Los claims no certifican por sí solos una instalación completa ni habilitan el fill.

## Evidencia y límites

Logs: `.tmp/product-spec-catalog/brake-adapter-parts-dart.log` y `.tmp/db/brake-adapter-parts-publication-tests.log`. Las comparaciones requieren identidad resuelta; los enlaces preservan ámbito pero no prueban verdad documental. Pendientes: dictamen independiente final, backup, verificador antes/después, publicación guardada, lectura autenticada y fingerprint. Sin prueba visual de las nuevas plantillas.

| Artefacto | SHA-256 |
|---|---|
| `scripts/inventory/compile_brake_adapter_parts_catalog.py` | `de9690621f54a8b6bf913fa1410e434875172ebd61e6155f84aa59bc55bf496f` |
| `scripts/inventory/compile_brake_adapter_parts_root.py` | `7dc9dddaafd83b557bc0e0c1557fdf208dc08219e68b421f7863d2d2854f8c69` |
| `scripts/inventory/compile_brake_adapter_parts_publication.py` | `61fb3ce728a5b772f98ba2299f55b09284ea651310956ba75f23156d29ddbb06` |
| `docs/development/product-specs-research-2026-09-05/brake-adapter-parts-catalog-2026-09-07.json` | `a5e3add682ae2ee881daaa158b55478d3762341de2f7fb35ddf05525a928897a` |
| `docs/development/product-specs-research-2026-09-05/brake-adapter-parts-cases-2026-09-07.json` | `44afed36113d8e87c755fdf438be1b96119f6a5d25e3f7fbd523466fce608135` |
| `docs/development/product-specs-research-2026-09-05/brake-adapter-parts-publication-preimage-2026-09-07.json` | `1732859b6960a51dee0ee5b7de7eec5c91aad57dc10f83515f63d491b7aefceb` |
| `docs/development/product-specs-research-2026-09-05/brake-adapter-parts-publication-packet-2026-09-07.json` | `ff81bded7371a74c2e497402f557be8c2512f0da4ae84e6f751b93834ca34ac8` |
| `supabase/migrations/20260908025000_brake_adapter_part_spec_templates.sql` | `0a635869bbc6459c645c361e46ea3bb3bbcd00233d744cfa408665b6f38bcc6b` |
| `supabase/manual_checks/verification/20260908025000_brake_adapter_part_spec_templates.sql` | `0c3eef4c2329e68d05b0ae2c0c7a7e1c90da21de5dcf6b05693b4f8c8fbb80c9` |
