package com.vinabike.erp

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import kotlin.concurrent.thread

/**
 * La entrada «vb-ERP» del menú Compartir del teléfono.
 *
 * No tiene pantalla: copia lo compartido ([IncomingShareStore.copyBatch]) y le
 * pasa el turno a la única `MainActivity`. **Por qué no recibe `MainActivity`
 * directamente:** el menú Compartir abre la actividad dentro de la tarea de la
 * app que comparte (Fotos, Archivos…). Con `singleTop` eso crearía una segunda
 * `MainActivity` con un segundo motor de Flutter —otra sesión, otro realtime—
 * encima de Fotos. Este receptor vive un instante en esa tarea y trae al frente
 * la tarea del ERP que ya existe.
 */
class IncomingShareReceiverActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (savedInstanceState != null) {
            // Una recreación no trae un envío nuevo.
            finish()
            return
        }

        val uris = sharedUris(intent)
        if (uris.isEmpty()) {
            finish()
            return
        }

        val declaredType = intent.type
        val appContext = applicationContext
        thread(name = "incoming-share-copy") {
            IncomingShareStore.sweepStale(appContext)
            val batch = IncomingShareStore.copyBatch(appContext, uris, declaredType)
            runOnUiThread {
                // Volver atrás mientras copiaba es cancelar: no se abre el ERP
                // ni queda un lote esperando para aparecer después.
                if (isDestroyed) {
                    IncomingShareStore.release(appContext, batch.id)
                    return@runOnUiThread
                }
                IncomingShareStore.publish(appContext, batch)
                startActivity(
                    Intent(this, MainActivity::class.java).apply {
                        action = IncomingShareStore.ACTION_INCOMING_SHARE
                        // NEW_TASK busca la tarea cuya raíz ya es MainActivity;
                        // CLEAR_TOP + SINGLE_TOP la reutiliza (onNewIntent) en vez
                        // de apilar otra instancia sobre lo que hubiera encima.
                        addFlags(
                            Intent.FLAG_ACTIVITY_NEW_TASK or
                                Intent.FLAG_ACTIVITY_CLEAR_TOP or
                                Intent.FLAG_ACTIVITY_SINGLE_TOP,
                        )
                    },
                )
                finish()
            }
        }
    }

    private fun sharedUris(intent: Intent?): List<Uri> {
        if (intent == null) return emptyList()
        val found = LinkedHashSet<Uri>()
        when (intent.action) {
            Intent.ACTION_SEND -> streamExtra(intent)?.let(found::add)
            Intent.ACTION_SEND_MULTIPLE -> streamListExtra(intent)?.let(found::addAll)
        }
        // Algunas apps sólo llenan el ClipData.
        intent.clipData?.let { clip ->
            for (index in 0 until clip.itemCount) {
                clip.getItemAt(index).uri?.let(found::add)
            }
        }
        // Sólo `content://` de otra app: un `file://` o un proveedor propio harían
        // que el ERP leyera sus propios archivos internos en nombre de quien
        // comparte.
        return found.filter {
            it.scheme == "content" && it.authority?.startsWith(packageName) != true
        }
    }

    @Suppress("DEPRECATION")
    private fun streamExtra(intent: Intent): Uri? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            intent.getParcelableExtra(Intent.EXTRA_STREAM) as? Uri
        }

    @Suppress("DEPRECATION")
    private fun streamListExtra(intent: Intent): List<Uri>? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
        }
}
