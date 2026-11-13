package com.vinabike.erp

import android.content.ContentValues
import android.content.Context
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.webkit.MimeTypeMap
import java.io.File
import java.io.IOException

/**
 * Deja una copia de un archivo de la app en «Descargas», la carpeta pública
 * del teléfono que abre «Archivos».
 *
 * `getDownloadsDirectory()` de Flutter devuelve en Android
 * `Android/data/com.vinabike.erp/files/downloads`: una carpeta propia de la
 * app que «Archivos» no muestra desde Android 11. El dueño bajó una etiqueta de
 * despacho el 2026-11-13 y no la encontró. La colección `MediaStore.Downloads`
 * es la única puerta a la carpeta pública sin pedir permisos, y existe desde
 * Android 10; en versiones anteriores [save] devuelve `null` y quien llama
 * conserva su carpeta de siempre.
 */
object PublicDownloads {
    /**
     * Copia [source] a «Descargas» con el nombre [fileName] y devuelve la ruta
     * donde quedó. Si ya había un archivo con ese nombre, Android le agrega
     * «(1)»: por eso la ruta se arma con el nombre que quedó, no con el pedido.
     */
    @Suppress("DEPRECATION")
    fun save(
        context: Context,
        source: File,
        fileName: String,
        mimeType: String?,
    ): String? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return null

        val resolver = context.contentResolver
        val collection =
            MediaStore.Downloads.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
            put(MediaStore.MediaColumns.MIME_TYPE, resolvedMimeType(fileName, mimeType))
            put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val uri = resolver.insert(collection, values)
            ?: throw IOException("Android no pudo crear el archivo en Descargas.")

        try {
            val output = resolver.openOutputStream(uri)
                ?: throw IOException("Android no pudo abrir el archivo en Descargas.")
            output.use { target ->
                source.inputStream().use { it.copyTo(target) }
            }
            resolver.update(
                uri,
                ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) },
                null,
                null,
            )
        } catch (error: Exception) {
            // Un archivo a medias en Descargas es peor que ninguno.
            runCatching { resolver.delete(uri, null, null) }
            throw error
        }

        val savedName = resolver.query(
            uri,
            arrayOf(MediaStore.MediaColumns.DISPLAY_NAME),
            null,
            null,
            null,
        )?.use { cursor ->
            if (cursor.moveToFirst()) cursor.getString(0) else null
        } ?: fileName

        return File(
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS),
            savedName,
        ).path
    }

    /**
     * El tipo que corresponde a la extensión manda sobre el declarado: si no
     * calzan, MediaStore le cambia la extensión al archivo («datos.csv» con
     * `text/plain` queda «datos.csv.txt»).
     */
    private fun resolvedMimeType(fileName: String, declared: String?): String {
        val extension = fileName.substringAfterLast('.', "").lowercase()
        val fromExtension = if (extension.isEmpty()) {
            null
        } else {
            MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension)
        }
        return fromExtension
            ?: declared?.substringBefore(';')?.trim()?.takeIf { it.isNotEmpty() }
            ?: "application/octet-stream"
    }
}
