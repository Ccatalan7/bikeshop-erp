package com.vinabike.erp

import android.content.Context
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Handler
import android.os.Looper
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.effect.Presentation
import androidx.media3.transformer.Composition
import androidx.media3.transformer.DefaultEncoderFactory
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.ProgressHolder
import androidx.media3.transformer.Transformer
import androidx.media3.transformer.VideoEncoderSettings
import java.io.File
import kotlin.math.roundToInt

/**
 * Deja un video bajo el tope de WhatsApp Cloud API (16 MB) re-codificándolo en
 * H.264 + AAC, que es lo que WhatsApp acepta en cualquier teléfono.
 *
 * **La tasa sale de la duración, no de un preset.** Un preset fijo («720p») deja
 * un video de un minuto en 30 MB y uno de diez segundos innecesariamente feo. Se
 * reparte el presupuesto (≈ 15 MB) entre los segundos que dura. Si ni con la
 * tasa mínima legible cabe, el video es demasiado largo y se dice así: no se
 * manda algo irreconocible.
 *
 * Transformer vive en el hilo principal (sus callbacks llegan por el looper con
 * que se construye) y hace el trabajo pesado en sus propios hilos.
 */
class VideoCompressor(private val context: Context) {
    interface Callback {
        fun onProgress(percent: Int)
        fun onDone(output: File)
        fun onError(code: String, message: String)
    }

    private val handler = Handler(Looper.getMainLooper())
    private val active = mutableMapOf<String, Transformer>()
    private val callbacks = mutableMapOf<String, Callback>()
    private val outputs = mutableMapOf<String, File>()

    fun compress(id: String, input: File, maxBytes: Long, callback: Callback) {
        val metadata = readMetadata(input)
        val durationMs = metadata?.durationMs
        if (metadata == null || durationMs == null || durationMs <= 0) {
            callback.onError("unreadable", "No se pudo leer el video.")
            return
        }
        // Margen del 10 %: el contenedor y el audio no se reparten exacto.
        val budgetBits = maxBytes * 8.0 * 0.9
        val videoBitrate = (budgetBits / (durationMs / 1000.0) - AUDIO_BITRATE).toInt()
        if (videoBitrate < MIN_VIDEO_BITRATE) {
            val maxSeconds = (budgetBits / (MIN_VIDEO_BITRATE + AUDIO_BITRATE)).toInt()
            callback.onError(
                "too_long",
                "El video dura demasiado para WhatsApp: comprimido cabe hasta " +
                    "${maxSeconds / 60} min ${maxSeconds % 60} s.",
            )
            return
        }
        val bitrate = videoBitrate.coerceAtMost(MAX_VIDEO_BITRATE)
        // Con poca tasa, 720 px se ve peor que 480 nítidos.
        val shortSide = if (bitrate < 1_200_000) 480 else 720

        val output = File(outputDirectory(input), input.nameWithoutExtension + ".mp4")
        output.parentFile?.mkdirs()
        output.delete()

        val transformer = Transformer.Builder(context)
            .setVideoMimeType(MimeTypes.VIDEO_H264)
            .setAudioMimeType(MimeTypes.AUDIO_AAC)
            .setEncoderFactory(
                DefaultEncoderFactory.Builder(context)
                    .setRequestedVideoEncoderSettings(
                        VideoEncoderSettings.Builder().setBitrate(bitrate).build(),
                    )
                    .setEnableFallback(true)
                    .build(),
            )
            .addListener(object : Transformer.Listener {
                override fun onCompleted(composition: Composition, exportResult: ExportResult) {
                    active.remove(id)
                    callbacks.remove(id)
                    outputs.remove(id)
                    if (!output.isFile || output.length() > maxBytes) {
                        output.delete()
                        callback.onError(
                            "too_large",
                            "Comprimido sigue pasando los 16 MB de WhatsApp.",
                        )
                    } else {
                        callback.onDone(output)
                    }
                }

                override fun onError(
                    composition: Composition,
                    exportResult: ExportResult,
                    exportException: ExportException,
                ) {
                    active.remove(id)
                    callbacks.remove(id)
                    outputs.remove(id)
                    output.delete()
                    callback.onError("failed", "El teléfono no pudo comprimir este video.")
                }
            })
            .build()

        val item = EditedMediaItem.Builder(MediaItem.fromUri(Uri.fromFile(input)))
            .setEffects(Effects(emptyList(), listOfNotNull(presentationFor(metadata, shortSide))))
            .build()
        active[id] = transformer
        callbacks[id] = callback
        outputs[id] = output
        transformer.start(item, output.path)
        pollProgress(id, transformer, callback)
    }

    /** `Transformer.cancel()` no avisa a nadie: sin esto Dart esperaría para siempre. */
    fun cancel(id: String) {
        val transformer = active.remove(id) ?: return
        transformer.cancel()
        outputs.remove(id)?.delete()
        callbacks.remove(id)?.onError("cancelled", "Compresión cancelada.")
    }

    private fun pollProgress(id: String, transformer: Transformer, callback: Callback) {
        val holder = ProgressHolder()
        val tick = object : Runnable {
            override fun run() {
                if (active[id] !== transformer) return
                if (transformer.getProgress(holder) == Transformer.PROGRESS_STATE_AVAILABLE) {
                    callback.onProgress(holder.progress)
                }
                handler.postDelayed(this, 400)
            }
        }
        handler.post(tick)
    }

    private data class Metadata(val durationMs: Long?, val width: Int, val height: Int)

    /** Tamaño como se ve (ya girado): un video vertical de teléfono viene
     *  grabado 1920×1080 con rotación 90. */
    private fun readMetadata(input: File): Metadata? = try {
        MediaMetadataRetriever().run {
            try {
                setDataSource(input.path)
                fun int(key: Int) = extractMetadata(key)?.toIntOrNull() ?: 0
                val rotation = int(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)
                val rawWidth = int(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)
                val rawHeight = int(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)
                val turned = rotation % 180 != 0
                Metadata(
                    durationMs = extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                        ?.toLongOrNull(),
                    width = if (turned) rawHeight else rawWidth,
                    height = if (turned) rawWidth else rawHeight,
                )
            } finally {
                release()
            }
        }
    } catch (error: Exception) {
        null
    }

    /**
     * Achica por el lado corto, así un video vertical y uno horizontal quedan
     * igual de nítidos. Media3 entrega a los efectos el cuadro ya girado
     * (`VideoFrameProcessingWrapper.getDecodedSize` intercambia ancho y alto con
     * rotación 90/270), por eso se usa el tamaño como se ve. Nunca agranda.
     */
    private fun presentationFor(metadata: Metadata, shortSide: Int): Presentation? {
        val (width, height) = metadata.width to metadata.height
        if (width <= 0 || height <= 0 || minOf(width, height) <= shortSide) return null
        fun even(value: Double) = (value / 2).roundToInt() * 2
        val (targetWidth, targetHeight) = if (width <= height) {
            shortSide to even(shortSide * height.toDouble() / width)
        } else {
            even(shortSide * width.toDouble() / height) to shortSide
        }
        return Presentation.createForWidthAndHeight(
            targetWidth,
            targetHeight,
            Presentation.LAYOUT_SCALE_TO_FIT,
        )
    }

    /** Junto al original si es del ERP (se borra con su lote); si no, en la caché. */
    private fun outputDirectory(input: File): File {
        val parent = input.parentFile ?: context.cacheDir
        return File(parent, "comprimido")
    }

    companion object {
        private const val AUDIO_BITRATE = 128_000
        private const val MIN_VIDEO_BITRATE = 350_000
        private const val MAX_VIDEO_BITRATE = 4_000_000
    }
}
