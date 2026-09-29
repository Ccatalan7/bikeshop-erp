package com.vinabike.erp

import android.content.ContentResolver
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.ImageDecoder
import android.net.Uri
import android.os.Build
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.util.UUID
import kotlin.math.max
import kotlin.math.roundToInt

/** Un archivo que otra app compartió, ya copiado dentro de la caché del ERP. */
data class IncomingShareFile(
    val path: String,
    val name: String,
    val mimeType: String,
    val sizeBytes: Long,
)

/** Lo que no se pudo traer, con la razón que el operador tiene que leer. */
data class IncomingShareSkip(val name: String, val reason: String)

data class IncomingShareBatch(
    val id: String,
    val files: List<IncomingShareFile>,
    val skipped: List<IncomingShareSkip>,
    /** Qué entrada del menú Compartir eligió el operador. */
    val target: String,
) {
    fun toChannelMap(): Map<String, Any> = mapOf(
        "id" to id,
        "target" to target,
        "files" to files.map {
            mapOf(
                "path" to it.path,
                "name" to it.name,
                "mimeType" to it.mimeType,
                "sizeBytes" to it.sizeBytes,
            )
        },
        "skipped" to skipped.map { mapOf("name" to it.name, "reason" to it.reason) },
    )
}

/**
 * Dueño de los archivos que llegan desde el menú «Compartir» del teléfono.
 *
 * **Por qué los copia quien recibe y no la pantalla del ERP.** El permiso para
 * leer un `content://` ajeno vale mientras vive la actividad que lo recibió.
 * [IncomingShareReceiverActivity] copia los bytes antes de terminar, así el ERP
 * nunca depende de reenviar un permiso temporal de otra app.
 *
 * **Por qué no en `cacheDir`.** Android purga la caché cuando falta espacio,
 * sin avisar: en el emulador borró un lote de fotos un minuto después de
 * compartirlo, mientras la app esperaba el inicio de sesión (2026-09-29). Las
 * copias van a `noBackupFilesDir`, que el sistema no toca, y las borra este
 * dueño: al enviar/guardar/descartar ([release]), cuando un envío nuevo
 * reemplaza a uno que nadie abrió ([publish]) y las de más de una hora
 * ([sweepStale]).
 *
 * **Por qué vive en memoria del proceso.** `MainActivity` está exportada: si el
 * lote viajara como ruta dentro del intent, cualquier app podría pedirle al ERP
 * que «compartiera» un archivo interno suyo. El lote sólo lo publica el
 * receptor, en este mismo proceso; el intent hacia `MainActivity` no lleva
 * datos, sólo avisa.
 */
object IncomingShareStore {
    const val ACTION_INCOMING_SHARE = "com.vinabike.erp.action.INCOMING_SHARE"

    /** «WhatsApp ERP»: directo a los chats. */
    const val TARGET_WHATSAPP = "whatsapp"

    /** «Viñabike ERP»: el menú con todos los destinos. */
    const val TARGET_HUB = "hub"

    /** Lo mismo que acepta un envío del chat (`maxAttachmentsPerBatch`). */
    const val MAX_FILES = 8

    // Topes de copia. Los límites finos por tipo los aplica la validación del
    // chat en Dart; esto sólo evita copiar lo que nunca se aceptará.
    private const val MAX_DOCUMENT_BYTES = 20L * 1024 * 1024
    private const val MAX_IMAGE_SOURCE_BYTES = 48L * 1024 * 1024
    // Un video de teléfono pasa fácil los 16 MB de WhatsApp; se copia entero
    // para comprimirlo (VideoCompressor.kt). La copia se borra con el lote.
    private const val MAX_VIDEO_SOURCE_BYTES = 400L * 1024 * 1024

    // WhatsApp Cloud API acepta imágenes de hasta 5 MB y sólo JPEG/PNG/WEBP.
    // Una foto de teléfono suele pasarlo o venir en HEIC.
    private const val MAX_IMAGE_BYTES = 5L * 1024 * 1024
    private const val MAX_IMAGE_DIMENSION = 2560
    private val sendableImageTypes = setOf("image/jpeg", "image/png", "image/webp", "image/gif")

    private const val ROOT_DIRECTORY = "incoming_share"

    // Nadie tarda una hora en elegir el chat: un lote así quedó de un proceso
    // que murió antes de enviar. Por edad y no «todo menos el pendiente», para
    // no borrar el lote que Dart ya tomó y el operador está mirando.
    private const val STALE_AFTER_MILLIS = 60L * 60 * 1000

    @Volatile
    private var pending: IncomingShareBatch? = null

    @Synchronized
    fun publish(context: Context, batch: IncomingShareBatch) {
        val replaced = pending
        pending = batch
        // Nadie alcanzó a abrir el anterior: lo último compartido manda.
        if (replaced != null && replaced.id != batch.id) release(context, replaced.id)
    }

    /** Lo entrega UNA vez: el mismo lote no debe volver a abrirse al reanudar. */
    @Synchronized
    fun take(): IncomingShareBatch? {
        val batch = pending
        pending = null
        return batch
    }

    @Synchronized
    fun hasPending(): Boolean = pending != null

    /** Borra la copia de un lote ya enviado, guardado o descartado. */
    fun release(context: Context, batchId: String) {
        if (!batchId.matches(Regex("^[0-9a-f-]{36}$"))) return
        File(root(context), batchId).deleteRecursively()
    }

    /**
     * Borra copias de más de una hora que quedaron de un proceso anterior (la
     * app se cerró antes de enviar). Nunca toca el lote que espera ser abierto.
     */
    @Synchronized
    fun sweepStale(context: Context) {
        val keep = pending?.id
        val cutoff = System.currentTimeMillis() - STALE_AFTER_MILLIS
        root(context).listFiles()?.forEach { directory ->
            if (directory.name != keep && directory.lastModified() < cutoff) {
                directory.deleteRecursively()
            }
        }
    }

    /**
     * Copia cada archivo compartido a `no_backup/incoming_share/<lote>/<n>/<nombre>`.
     * Corre fuera del hilo principal: una foto grande puede tardar en decodificarse.
     */
    fun copyBatch(
        context: Context,
        uris: List<Uri>,
        declaredType: String?,
        target: String,
    ): IncomingShareBatch {
        val batchId = UUID.randomUUID().toString()
        val batchDirectory = File(root(context), batchId)
        val files = mutableListOf<IncomingShareFile>()
        val skipped = mutableListOf<IncomingShareSkip>()
        val resolver = context.contentResolver

        uris.forEachIndexed { index, uri ->
            val metadata = queryMetadata(resolver, uri)
            val mimeType = normalizedMime(resolver.getType(uri) ?: singleTypeOrNull(declaredType))
            val name = fileNameFor(metadata.displayName, mimeType, index)
            if (index >= MAX_FILES) {
                skipped += IncomingShareSkip(name, "limit")
                return@forEachIndexed
            }
            try {
                val isImage = mimeType.startsWith("image/")
                val cap = when {
                    isImage -> MAX_IMAGE_SOURCE_BYTES
                    mimeType.startsWith("video/") -> MAX_VIDEO_SOURCE_BYTES
                    else -> MAX_DOCUMENT_BYTES
                }
                val knownSize = metadata.sizeBytes
                if (knownSize != null && knownSize > cap) {
                    skipped += IncomingShareSkip(name, "too_large")
                    return@forEachIndexed
                }
                val fileDirectory = File(batchDirectory, index.toString()).apply { mkdirs() }
                val copied = File(fileDirectory, name)
                if (!copyWithCap(resolver, uri, copied, cap)) {
                    fileDirectory.deleteRecursively()
                    skipped += IncomingShareSkip(name, "too_large")
                    return@forEachIndexed
                }
                val sendable = if (isImage && needsImageNormalization(mimeType, copied.length())) {
                    normalizeImage(copied, fileDirectory) ?: IncomingShareFile(
                        copied.path, copied.name, mimeType, copied.length(),
                    )
                } else {
                    IncomingShareFile(copied.path, copied.name, mimeType, copied.length())
                }
                files += sendable
            } catch (error: SecurityException) {
                skipped += IncomingShareSkip(name, "unreadable")
            } catch (error: IOException) {
                skipped += IncomingShareSkip(name, "unreadable")
            }
        }

        return IncomingShareBatch(batchId, files, skipped, target)
    }

    private fun root(context: Context): File = File(context.noBackupFilesDir, ROOT_DIRECTORY)

    private data class UriMetadata(val displayName: String?, val sizeBytes: Long?)

    private fun queryMetadata(resolver: ContentResolver, uri: Uri): UriMetadata {
        return try {
            resolver.query(
                uri,
                arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE),
                null,
                null,
                null,
            )?.use { cursor ->
                if (!cursor.moveToFirst()) return@use UriMetadata(null, null)
                val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                val sizeIndex = cursor.getColumnIndex(OpenableColumns.SIZE)
                UriMetadata(
                    if (nameIndex >= 0 && !cursor.isNull(nameIndex)) cursor.getString(nameIndex) else null,
                    if (sizeIndex >= 0 && !cursor.isNull(sizeIndex)) cursor.getLong(sizeIndex) else null,
                )
            } ?: UriMetadata(null, null)
        } catch (error: Exception) {
            UriMetadata(null, null)
        }
    }

    // El tipo del intent sólo sirve si nombra uno concreto, no un comodín
    // como «image/cualquiera» de una selección mezclada.
    private fun singleTypeOrNull(type: String?): String? =
        type?.takeUnless { it.endsWith("/*") || it == "*/*" }

    private fun normalizedMime(type: String?): String =
        type?.substringBefore(';')?.trim()?.lowercase()?.takeIf { it.contains('/') }
            ?: "application/octet-stream"

    private fun fileNameFor(displayName: String?, mimeType: String, index: Int): String {
        val cleaned = (displayName ?: "")
            .substringAfterLast('/')
            .replace(Regex("[\\\\:*?\"<>|\\u0000-\\u001F]"), "_")
            .trim()
            .trimStart('.')
        var name = cleaned.ifBlank { "archivo-${index + 1}" }
        val hasExtension = name.substringAfterLast('.', "").isNotEmpty()
        if (!hasExtension) {
            extensionFor(mimeType)?.let { name = "$name.$it" }
        }
        if (name.length > 120) {
            val extension = name.substringAfterLast('.', "")
            val keep = 120 - extension.length - 1
            name = if (extension.isNotEmpty() && keep > 0) {
                "${name.take(keep)}.$extension"
            } else {
                name.take(120)
            }
        }
        return name
    }

    private fun extensionFor(mimeType: String): String? {
        val extension = MimeTypeMap.getSingleton().getExtensionFromMimeType(mimeType)?.lowercase()
        return if (extension == "jpeg") "jpg" else extension
    }

    private fun copyWithCap(resolver: ContentResolver, uri: Uri, target: File, cap: Long): Boolean {
        val input = resolver.openInputStream(uri) ?: throw IOException("No stream for $uri")
        input.use { source ->
            FileOutputStream(target).use { sink ->
                val buffer = ByteArray(64 * 1024)
                var total = 0L
                while (true) {
                    val read = source.read(buffer)
                    if (read < 0) break
                    total += read
                    if (total > cap) {
                        sink.close()
                        target.delete()
                        return false
                    }
                    sink.write(buffer, 0, read)
                }
            }
        }
        return true
    }

    private fun needsImageNormalization(mimeType: String, sizeBytes: Long): Boolean {
        // Un GIF grande se decodificaría a su primer cuadro: mejor que el chat
        // lo rechace con su mensaje que mandar una foto fija sin avisar.
        if (mimeType == "image/gif") return false
        return mimeType !in sendableImageTypes || sizeBytes > MAX_IMAGE_BYTES
    }

    /**
     * Deja la imagen en un JPEG que WhatsApp acepta: HEIC/AVIF de la cámara o
     * una foto de más de 5 MB. `ImageDecoder` aplica la orientación EXIF, así
     * que la foto no sale acostada. Antes de Android 9 no hay decodificador
     * para HEIC; la copia queda tal cual y el chat explica por qué no se envía.
     */
    private fun normalizeImage(source: File, directory: File): IncomingShareFile? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) return null
        return try {
            val decoded = ImageDecoder.decodeBitmap(ImageDecoder.createSource(source)) { decoder, info, _ ->
                decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
                val width = info.size.width
                val height = info.size.height
                val longest = max(width, height)
                if (longest > MAX_IMAGE_DIMENSION) {
                    val scale = MAX_IMAGE_DIMENSION.toDouble() / longest
                    decoder.setTargetSize(
                        (width * scale).roundToInt().coerceAtLeast(1),
                        (height * scale).roundToInt().coerceAtLeast(1),
                    )
                }
            }
            // JPEG no tiene transparencia: sin un fondo blanco explícito, lo
            // transparente de una captura sale negro.
            val opaque = if (decoded.hasAlpha()) {
                Bitmap.createBitmap(decoded.width, decoded.height, Bitmap.Config.ARGB_8888).also {
                    Canvas(it).apply {
                        drawColor(Color.WHITE)
                        drawBitmap(decoded, 0f, 0f, null)
                    }
                    decoded.recycle()
                }
            } else {
                decoded
            }
            // Se escribe aparte y se renombra al final: si nada cabe en 5 MB, la
            // copia original sigue intacta para que el chat diga por qué no va.
            val encoded = File(directory, ".normalized.tmp")
            var written = false
            for (quality in intArrayOf(86, 72, 60)) {
                FileOutputStream(encoded).use { opaque.compress(Bitmap.CompressFormat.JPEG, quality, it) }
                if (encoded.length() <= MAX_IMAGE_BYTES) {
                    written = true
                    break
                }
            }
            opaque.recycle()
            if (!written) {
                encoded.delete()
                return null
            }
            val baseName = source.name.substringBeforeLast('.').ifBlank { "imagen" }
            val target = File(directory, "$baseName.jpg")
            source.delete()
            if (!encoded.renameTo(target)) {
                encoded.delete()
                return null
            }
            IncomingShareFile(target.path, target.name, "image/jpeg", target.length())
        } catch (error: Exception) {
            null
        }
    }
}
