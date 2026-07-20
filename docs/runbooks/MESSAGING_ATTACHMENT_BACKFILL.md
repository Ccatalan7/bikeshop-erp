# Backfill privado de adjuntos de mensajería

Este procedimiento migra únicamente los objetos históricos de
`vinabike-assets/chat` y `vinabike-assets/whatsapp-media`. No enumera otros
prefijos del bucket ni imprime nombres de archivo, rutas, URLs o datos de
clientes.

## Contrato de seguridad

- La migración `20260719163000_private_messaging_attachments.sql` debe estar
  desplegada y verificada antes del backfill.
- El modo predeterminado es solo lectura. Descarga los objetos legados, verifica
  tamaño/MIME, calcula SHA-256 y escribe un recibo sin PII bajo
  `.tmp/messaging-attachments/`.
- La ejecución exige dos confirmaciones y el fingerprint exacto del dry-run.
- Cada copia usa un UUID determinista, se relee byte a byte y recién entonces
  un RPC atómico registra el adjunto y elimina las URLs del mensaje.
- Ningún objeto público se borra hasta que todos los mensajes referenciados
  tengan registry y metadata privados verificados.
- Un objeto sin referencia actual no se considera descartable. Primero se
  copia byte a byte al bucket privado `messaging-attachment-quarantine`, bajo
  `legacy-orphans/<SHA-256-del-contenido>`, y se registra un recibo durable que
  guarda únicamente hashes, tamaño y timestamps; nunca la ruta pública ni PII.
- Antes de borrar, cada objeto se descarga nuevamente y su SHA-256 debe seguir
  siendo idéntico. Un huérfano solo se elimina si además existe y fue releída
  su copia privada de cuarentena. Solo se eliminan objetos con al menos 24
  horas.
- Un retry tras perder el ACK reutiliza el mismo objeto privado y verifica sus
  bytes. Si el commit de DB ya ocurrió, el objeto público reaparece como
  huérfano y se limpia en la siguiente ejecución.

## 1. Dry-run obligatorio

```bash
bash scripts/messaging/backfill_private_attachments.sh
```

Conserva el `Fingerprint` y el SHA-256 del recibo. La salida contiene solamente
conteos, hashes y la ruta local del recibo.

## 2. Ejecución

```bash
VINABIKE_STORAGE_BACKFILL_CONFIRM=production \
  bash scripts/messaging/backfill_private_attachments.sh \
  --execute \
  --confirm production \
  --expected-fingerprint <SHA256_DEL_DRY_RUN>
```

Si el fingerprint cambió, el script falla cerrado: vuelve a ejecutar el
dry-run y revisa los nuevos conteos antes de autorizar otro intento.

## 3. Criterio de cierre

El recibo final debe indicar:

- `remaining_legacy_references: 0`;
- ningún objeto eliminado vuelve a aparecer en el readback de Storage;
- `quarantined_orphan_objects` coincide con los huérfanos del preflight y cada
  huérfano eliminado figura en
  `deleted_orphan_objects_with_private_receipt`;
- cada mensaje migrado tiene una fila `attached` en
  `messaging_attachments`, SHA-256 coincidente y metadata sin campos URL;
- `remaining_public_scope_objects` solo puede ser distinto de cero si el
  recibo reporta objetos demasiado recientes para el umbral seguro.

La cuarentena no se expone al cliente Flutter y no tiene policies para roles
de aplicación. Para investigar un objeto conocido, el operador autorizado
calcula localmente el SHA-256 de su antigua ruta y lo compara con
`source_path_sha256`; el nombre y la ruta histórica nunca se almacenan en el
recibo.

Nunca copies el contenido del recibo a tickets públicos si una futura versión
agrega identificadores adicionales. Los recibos actuales se diseñaron sin
rutas ni PII.
