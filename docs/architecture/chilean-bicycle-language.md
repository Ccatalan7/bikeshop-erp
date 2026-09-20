# Lenguaje chileno para fichas técnicas de bicicleta

Estado: contrato de palabras para la interfaz, 2026-09-19.

Este documento decide **cómo se nombra una pieza o una medida frente al
operador chileno**. No decide compatibilidad mecánica. Para eso siguen mandando
`bicycle-compatibility-knowledge.md`, la ficha exacta del fabricante y el
contrato de especificaciones.

## Regla

La etiqueta empieza por la palabra que usa una tienda o un taller chileno. Una
sigla o nombre de estándar se conserva sólo cuando sirve para reconocer la
ficha del fabricante, después de la explicación en castellano o dentro de la
ayuda.

Ejemplos:

| Evitar como etiqueta | Usar en la interfaz | Dónde queda el término técnico |
|---|---|---|
| `PCD brida izquierda` | `Diámetro del círculo de hoyos izquierdo` | La ayuda dice que puede aparecer como `PCD` |
| `Centro a brida` | `Del centro al círculo de hoyos` | La ayuda explica el plano exacto de medición |
| `OLD` | `Ancho de la maza entre apoyos (OLD)` | Se conserva `OLD` para comparar catálogos |
| `Reach` / `Drop` / `Rise` | `Alcance` / `Caída` / `Elevación del manubrio` | El nombre OEM puede seguir en la fuente |
| `Freehub / driver` | `Tipo de núcleo` | `HG`, `Micro Spline`, `XD` o `driver BMX` quedan como valores exactos |
| `J-bend / straight pull` | `Rayo con codo / recto` | La ayuda muestra los nombres del fabricante |
| `Direct mount` | `Montaje directo` | La generación OEM exacta sigue siendo obligatoria |
| `Hooked / hookless` | `Aro con gancho / sin gancho` | La ayuda conserva el estándar publicado |
| `Brida` cuando significa `cable tie` | `Amarra plástica` | En una maza, `flange` se explica como `círculo de hoyos`; el nombre literal del fabricante puede seguir en la fuente |
| `Tija` / `sillín` | `Poste de asiento` / `asiento` | `Tubo de asiento` queda reservado para el tubo del cuadro |
| `Patilla` / `hanger` | `Postiza` o `fusible de cambio` | En Chile `pata de cambio` suele nombrar el cambio trasero completo; no confundirlo con la postiza que lo une al cuadro |
| `Manillar` / `maneta` | `Manubrio` / `manilla` | El término importado sigue sirviendo como alias de lectura |
| `Portabidón` / `portacaramagiola` | `Portabotella` | El nombre comercial no cambia |
| `Guardabarros` | `Tapabarros` | La ficha conserva cualquier estándar o modelo OEM |

Las marcas, modelos, códigos, normas y valores importados se conservan
literales. Esta regla cambia el rótulo y la explicación; nunca cambia un token
de compatibilidad para que suene mejor.

## Evidencia de uso en Chile

Se usaron páginas chilenas de tiendas, talleres y distribuidores con fichas
técnicas reales. Ninguna de ellas manda sobre la mecánica de compatibilidad;
sirven para observar las palabras que ve el comprador y usa el taller local.

- [Oxford Store, Cyclotour 26](https://oxfordstore.cl/products/bicicleta-oxford-26-cyclotour-6v): `maza`, `rayos`, `volante / biela`, `piñón`, `manubrio`, `tee`, `asiento` y `tubo sillín`.
- [Specialized Chile, Turbo Como SL 5.0](https://www.specialized.com/cl/es/turbo-como-sl-50/p/218238): una ficha oficial localizada usa `maza delantera`, `maza trasera`, `manubrio`, `asiento` y `poste de asiento`; esta última forma evita confundir la pieza móvil con el tubo del cuadro.
- [Decathlon Chile, portabotella 500](https://www.decathlon.cl/p/porta-botella-bicicleta-500-negro/349442/c382m8826618) y su [categoría de tapabarros](https://www.decathlon.cl/deportes/ciclismo/tapabarros): usa `portabotella`, `manubrio`, `neumático` y `tapabarros` en textos dirigidos al comprador chileno.
- [Decathlon Chile, postiza de bicicleta](https://www.decathlon.cl/p/postiza-de-bicicleta/100599/m8329146), [Biking Chile](https://biking.cl/collections/pata-de-cambio) y [Derman](https://derman.cl/1405-postizas): separan la `postiza` o `fusible` reemplazable de la `pata de cambio`, que en el comercio chileno suele ser el cambio trasero completo.
- [Derman al Mayor, categoría mazas](https://dermanalmayor.cl/categoria-producto/articulos-sin-categoria/ciclismo/componentes/maza/): `maza`, `hoyos`, `rodamiento sellado` y `núcleo`.
- [Be Quick, Trek Marlin 7](https://bequick.cl/products/trek-marlin-7-29-gen-3-negro-m-2026): `maza`, `cierre rápido`, `rueda libre`, `llanta`, `neumático` y `agujeros`; conserva `Tubeless Ready` como declaración comercial.
- [Faucon Bikes, Shimano FH-MT410](https://www.fauconbikes.cl/products/maza-trasera-fh-mt410-32h-12v-old-142mm-centerlock): muestra `OLD`, `PCD` y `offset` copiados de la tabla OEM junto con palabras locales. Esto justifica conservar la sigla en la ayuda, no usarla como explicación principal.
- [Race Bike Chile, Hope Pro 5](https://www.racebikechile.com/products/masa-trasera-hope-pro-5): `maza`, `6 pernos` y `núcleo`.
- [Bikehouse Chile, Cube Touring](https://bikehouse.cl/products/bicicleta-cube-touring-one-easy-entry): `pata de cambio`, `bielas`, `manillar/manubrio`, `piñón`, `llantas` y `maza/buje`.
- [Mi Bicio, taller](https://mibicio.cl/taller/) y [Austral Bikes, taller](https://australbikes.cl/es/workshop/): `mantención de maza`, `rayos` y `enrayado` en servicios dirigidos al público chileno.

Las páginas también contienen traducciones automáticas y anglicismos. Una
aparición aislada no basta para copiar una palabra. Se prioriza el término que
se repite en varias fuentes y que describe la acción o medida sin obligar al
operador a conocer una sigla.

## Aplicación

Cada ficha mantiene alineados estos lugares:

1. `spec_definitions.label`, compartido por editor, tienda, taller y mensajes
   de validación.
2. `spec_templates.name` y `description`, usados para presentar la familia.
3. `spec_definitions.validation_rules` y los esquemas de filas, porque una
   tabla repetible no puede volver a mostrar `brida`, `tija` o `maneta`.
4. `spec_templates.form_contract.helpers`, donde se explica cómo reconocer o
   medir el dato.
5. Dibujos y textos locales de widgets, que no pueden reintroducir la jerga que
   ya se retiró de la metadata.

Los nombres técnicos que controlan reglas (`key`, códigos e identificadores de
opciones) no son texto de interfaz y permanecen estables. Una etiqueta de
opción sí puede cambiar, pero conserva su id, su código y el término anterior
como alias de lectura; los contratos y valores guardados cambian juntos en una
sola migración.
