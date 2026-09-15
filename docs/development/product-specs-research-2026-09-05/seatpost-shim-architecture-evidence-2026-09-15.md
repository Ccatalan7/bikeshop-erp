# Casquillos de tija: alcance que falta cubrir

Los SKU AE0266 y AE0274 identifican adaptadores de tija. **Corrección 05:27 UTC:**
la lectura de producción encontró `seatpost_shim_length_mm` ya unido a
`seatpost`, con dominio positivo y flags públicos/filtrables deshabilitados.
**Corrección de Claude, 2026-09-15 (ronda 230, H1):** la rama heredada de
`seatpost` ya representa las dos interfaces con `shim_inner_diameter_mm`
(`fa6ff71e-7b9b-5415-8669-a0dfe586d6c8`) y `shim_outer_diameter_mm`
(`f091e753-d9f4-5b85-9f1b-2556821054ec`), obligatorias bajo
`seatpost_kind = Suplemento (shim)`; lo que le falta es orden estricto,
geometría, perfil OEM y condiciones con fuente. El compilador reutiliza esas
dos definiciones y la de longitud byte a byte, con etiquetas propias del
nuevo dueño; ya no crea `seatpost_shim_post_diameter_mm` ni
`seatpost_shim_frame_bore_mm`. Uso productivo leído el 2026-09-15: cero hechos,
referencias y criterios sobre las tres claves; cero usos de la opción.
`spacer` modela
separadores axiales de dirección/pedalier: su longitud/espesor no sustituye
las dos superficies de ajuste de un casquillo reductor.

La ficha debe distinguir tija aceptada, alojamiento interior del cuadro,
geometría y longitud del casquillo, e indicaciones de montaje con fuente.
No usar el diámetro exterior del tubo del cuadro como alojamiento de la tija.
[Sheldon Brown](https://www.sheldonbrown.com/seatpost-sizes.html) distingue esas
medidas y recomienda medir el tubo/poste reales frente a una tabla por modelo.

[WOOdman Seatpost Shim](https://woodmancomponents.com/products/woodman-post-shim)
publica variantes ID27.2/OD30.9 e ID27.2/OD31.6. Son pares concretos por variante,
no un producto compatible con cualquier diámetro entre ellos. No se copian esas
medidas ni su material a los productos MUQZI del inventario.

[Wolf Tooth Resolve](https://www.wolftoothcomponents.com/products/resolve-dropper-post)
declara una aplicación 31.6→34.9 con casquillo no incluido y exige respetar la
inserción mínima del cuadro cuando supere la de esa tija. Diámetros que coinciden
no bastan para declarar montaje seguro; esta evidencia tampoco autoriza trasladar
sus longitudes mínimas a otras marcas/modelos.

Propuesta de Root: una ficha de pieza `seatpost_shim` con un único par de
diámetros nominales. No una tabla de variantes editables como si pertenecieran
todas al mismo producto. Geometría circular requiere ambos diámetros; un perfil
OEM específico requiere su interfaz y excluye esos diámetros. La geometría
desconocida conserva pendientes. No
rellenar automáticamente longitud de apoyo ni convertir el título 30 mm en
30.9 mm. La ausencia de ese dato permanece pendiente. Cero valores copiados a
productos. `compile_seatpost_shim.py` prepara diez campos, cuatro definiciones
nuevas y seis reutilizadas (las tres de la rama heredada más fuente, material y
peso). No está publicado ni asignado; la coexistencia
con la rama heredada de `seatpost` requiere adjudicación antes del rollout.

[Park Tool, instalación de tijas](https://www.parktool.com/en-us/blog/repair-help/how-to-remove-and-install-a-seatpost)
separa medida física y tamaño nominal, geometrías propietarias e inserción. No
se convierte su orientación general de inserción en una regla OEM universal ni
se usa una tolerancia genérica para aceptar variantes vecinas. La longitud útil
del casquillo no puede superar su longitud total; ninguna de ambas determina
por sí sola la inserción de la tija.

El diámetro nominal interior del reductor debe ser **menor**, no igual, al
exterior de ajuste. El motor anterior sólo disponía de orden escalar inclusivo.
Candidato acotado `compile_product_spec_strict_scalar.py`: un par de dos claves
sigue significando ≤; un tercer elemento explícito `lt` exige <. Los clientes
anteriores rechazan el formato de tres elementos, evitando que lo interpreten
silenciosamente como ≤. La prueba SQL ejecuta ese rechazo del predecesor. Se
conservan pares heredados y se evita duplicarlos al declarar orden estricto.
No se reescribe ninguna ficha, hecho ni permiso al actualizar esas funciones.


Validación local del candidato (05:37 UTC): 25 pruebas Dart de la plantilla
(una plantilla +24 casos), 24 casos SQL de publicación/repetición y nueve
aserciones del escritor autenticado: acepta un par único, conserva decimales,
rechaza igualdad, inversión, diámetros circulares en perfil específico, apoyo
mayor que longitud y una opción textil ajena; los fallos conservan el valor
anterior. Motor: 91 pruebas Dart entre comparación y regresiones de coherencia,
11 valores SQL, trece rechazos de metadatos, rechazo del predecesor, herencia
sin duplicación y conservación de igualdad en rangos normales. Publicador:
forward/replay exacto; rechazo de estado mixto y de modo de función alterado.
Analizador limpio. No son pruebas de compatibilidad OEM ni llenado.

El vocabulario compartido de material incluye ropa y otros objetos; el contrato
lo restringe al casquillo sin cambiar la definición global. Los materiales del
cuadro y la tija no se derivan del material del casquillo. Las definiciones ya
publicadas de longitud, peso, fuente y material se conservan íntegramente,
incluidos sus flags; no se declara que el filtrado de longitud esté resuelto.

## Cierre de la ronda 230 por Claude (propiedad en solitario, 2026-09-15)

- **F1:** la migración generada exige, además del validador `ac0738d5…`, los
  cuatro md5 nuevos del motor publicados por `20260915200000`; si faltan,
  falla con «Strict scalar order extension 20260915200000 is not published».
- **F2:** la fuente sigue obligatoria y precede a los números. La longitud
  total pasa a opcional (`required_when never`): WOOdman no la publica y una
  pieza con fuente completa no debe quedar pendiente por un dato que la fuente
  no da; el caso `no_published_length` lo fija. El apoyo útil sigue opcional,
  acotado por la longitud total y sin fuente OEM en las cuatro consultadas: es
  una construcción propia que sólo se llena si un fabricante lo declara.
- **Superficie:** las tres definiciones reutilizadas siguen invisibles y no
  filtrables; las cuatro nuevas nacen visibles (escalar y selección
  filtrables). La decisión de flags de las reutilizadas queda abierta, igual
  que en frenos.
- Regenerado desde preimagen productiva de las 19:48:40Z
  (`a9ab487c4cf97254…`): catálogo
  `c92456b25dd5a692…`, casos
  `eefd42623faf4982…` (25), paquete
  `f8767700cbaa1a57…`, candidato
  `30b3937e23230b4a…`, verificador
  `3120a487990f5af7…`. Ensayo SQL local: forward,
  réplica exacta, 25 · 1, 9 aserciones del escritor autenticado, rollback.
  Arnés Dart 26/26. Verificador contra producción antes de publicar: falla
  (división por cero), sin colisiones de clave ni de id.
- Sigue sin llenado: cero hechos escritos; AE0266 y AE0274 no se asignan hasta
  el saneamiento de la rama heredada y la comprobación del cliente.
- **Publicado** `20260915203000` (plantilla `bdd99089-75c5-5370-919c-38a6cdefd892` v11) y
  `20260915210000` (rama heredada de `seatpost` a legacy, v27), ambos con
  verificador exacto y read-back; cero productos asignados, cero hechos.
