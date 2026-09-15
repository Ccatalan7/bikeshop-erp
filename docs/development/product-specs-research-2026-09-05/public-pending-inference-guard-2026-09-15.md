# Inferencias pendientes en la ficha pública

Aplicado y verificado el 2026-09-15 a las 03:26 UTC. Migración inmutable
`20260915034000_public_specs_pending_inferences.sql`, cuerpo revisado SHA-256
`d7e1f2e0bd9bbcbc1872d27dd2bd0af9a7386ef9190fb1eaaabda52da2e61b43`.
Claude 223 aprobó el delta y agregó 23 comprobaciones locales; el despliegue
cerró verificación y registro productivo. La cámara pendiente de asignación está
activa, publicada y visible en web. Asignar su ficha expondría dos observaciones
antiguas `inferred / confirmed=false` como material y sellante. La función
pública vigente no distingue esa procedencia; el editor sí conserva el origen.

El cambio propuesto excluye únicamente inferencias pendientes de la salida
pública. No cambia valores, procedencia ni confirmación guardados; no altera
lectores internos ni establece que todo `confirmed=false` sea falso o inválido.
Afirmaciones de proveedor, mecánico y otros orígenes conservan su política
actual. Una inferencia ya confirmada conserva el comportamiento anterior.
No se presenta este filtro como el contrato epistemológico completo de §4.2.

Alcance productivo candidato: 227 campos de 132 cámaras actualmente visibles,
todos de material/sellante. Es el conjunto potencial por metadatos y procedencia,
no 227 filas cuya renderización completa se haya comprobado. Dos consultas
agregadas del renderizador llegaron al límite de sentencia; no se prolongó ese
límite. La consulta de procedencia sí terminó y las muestras se leen por separado.

Prueba local: preimagen reproduce ambos valores públicos; el candidato y su
repetición exacta pasan 15 aserciones, con hechos, producto, proyección interna
y permisos intactos. Conserva false, cero, exclusión legacy, tenant y visibilidad.
La prueba negativa sin el candidato falla exactamente en las tres aserciones
que deben cambiar. Todo termina en rollback.

Evidencia privada: `.tmp/product-spec-catalog/public-inference-guard-20260915/`.
Preimagen MD5 `89e21f13bb41bdac92b17e62b059df06`; postimagen `4d42285fdfc0bc9c33fce0fe6d9d40a3`.
Candidato SHA-256 `8a6b8938a01c05e99e7047a571e6c89f7927938807c5c72e42d54eff74a3d1ef`.
El verificador productivo dio rojo antes y verde después. Lecturas HTTP anónimas
reales: cámara `000ca591…` pasa de seis a cuatro filas, retirando únicamente las
dos inferencias pendientes. Control `0ad47d4b…` (16003): material declarado por
proveedor y otras cinco filas permanecen idénticas; sólo desaparece el sellante
inferido (siete a seis). La consulta no encontró una cámara visible con material
de proveedor y cero inferencias; por eso no se afirma una respuesta completa sin
cambios. Los dos snapshots internos autenticados completos son idénticos antes
y después: valores, origen, confirmación y datos comerciales conservados.
Evidencia `verified-comparison.json` y recibo de migración. Ningún llenado ni
escritura de producto se efectuó como parte de este filtro.
