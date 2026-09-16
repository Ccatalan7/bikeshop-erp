# Adjudicación de propiedad en frenos

La propuesta de Claude 221 fue rechazada; la corrección 222 conserva avances
pero todavía no es publicable. Ningún cambio D2 está aplicado.

**Cerrada el 2026-09-16:** la revisión 223 se publicó como `20260916130000_brake_presentations.sql` con los dos errores de propiedad resueltos y las condiciones de aceptación probadas o declaradas como límite del motor; ver [brake-presentations-adjudication-2026-09-16.md](brake-presentations-adjudication-2026-09-16.md).

Se acepta: identificar explícitamente la presentación, separar el circuito de
sus piezas, dirigir conexiones a IDs de filas y conservar como legacy los
campos ambiguos que realmente existen. Un campo ausente no demuestra pieza
única. «Hidráulico» describe accionamiento, no una pieza incluida; la ficha de
freno mecánico completo no se convierte por interpretación en cáliper suelto.
Puertos y uniones pertenecen a extremos físicos. Fluido admitido por una pieza
y fluido contenido en un circuito son afirmaciones distintas, con fuentes.

Quedan dos errores de propiedad en 222: el tamaño de herramienta de un cáliper
no puede quedarse global porque su ficha aún carezca del campo, y los dos
mecanismos de un par de frenos de llanta tampoco comparten automáticamente
marca, posición o medidas. Se debe completar el dueño correcto o conservar el
dato histórico sin editar; no abrir una excepción a la regla por conveniencia.

No se añade a manetas el viejo selector de puertos como sustituto de interfaces
precisas. Antes de publicar frenos completos, adjudicar también los sucesores
de maneta/cáliper y el esquema de cada extremo; usar una plantilla activa no
certifica que su arquitectura antigua sea suficiente.

Una colección comercial y la pieza individual son conceptos distintos. Para
conjuntos heterogéneos (tres cierres de rueda/asiento, tuercas+rodamientos, par de
manetas) evaluar un dueño explícito de conjunto que apunte a las fichas de las
piezas, evitando duplicar plantillas físicas o convertir falta de filas en
«unidad». No habilitar recursión de perfiles mediante supuestos sobre la UI.
El framework actual resuelve perfiles de primer nivel; el motor no compara
medidas entre perfiles ni valida por sí solo compatibilidad de un circuito.

La siguiente implementación debe demostrar cambio de presentación sin borrado,
propiedad de herramientas/puertos/fluido por pieza, dos unidades del mismo
modelo con hechos distintos, conexiones a la pieza correcta y un estado
pendiente cuando falte evidencia. Son condiciones de aceptación concretas;
las fuentes y la matriz propuesta están en
`brake-member-ownership-proposal-2026-09-15.md` (revisión 222).
