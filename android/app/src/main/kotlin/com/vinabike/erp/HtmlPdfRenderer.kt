package com.vinabike.erp

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.print.PrintAttributes
import android.print.PrintDocumentAdapter
import android.print.VinabikeHtmlPdf
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import org.json.JSONObject
import org.json.JSONTokener

/**
 * App owned HTML to PDF renderer for Android.
 *
 * The `printing` plugin cannot be used to file an invoice, because a
 * conversion of its that goes wrong says nothing at all:
 *
 * * `PrintingJob.convertHtml` builds its `WebView` as a local variable and
 *   stores it nowhere. `PrintingJob` has no field for it, so once the method
 *   returns nothing reachable from a GC root keeps the in-flight conversion
 *   alive.
 * * Its `PdfConvert` helper overrides only `onLayoutFinished` and
 *   `onWriteFinished`. `onLayoutFailed`, `onLayoutCancelled`, `onWriteFailed`
 *   and `onWriteCancelled` fall through to the empty base implementations.
 *
 * Either way the Dart future is simply never completed. The owner saw the
 * consequence as a progress dialog that span forever on
 * "Consolidando pedidos y generando el PDF" (2026-09-04); the same document in
 * the same process converted in 2.2 s on one run and hung on the next, and the
 * failures were not monotonic in document size.
 *
 * This renderer keeps every job referenced until it ends, enables JavaScript
 * so a template that draws itself still prints, waits for the same readiness
 * contract as the macOS host, carries its own deadline, and always answers
 * exactly once.
 */
class HtmlPdfRenderer(private val context: Context) {
    private val handler = Handler(Looper.getMainLooper())
    private val activeJobs = mutableSetOf<Job>()

    interface Result {
        fun onSuccess(document: ByteArray)

        fun onError(code: String, message: String)
    }

    fun render(
        html: String,
        viewportWidthPoints: Double,
        viewportHeightPoints: Double,
        readySelector: String?,
        readyFlag: String?,
        timeoutMillis: Long,
        result: Result,
    ) {
        if (html.isBlank()) {
            result.onError("invalid_html_pdf_request", "El documento HTML está vacío.")
            return
        }
        if (viewportWidthPoints <= 0 || viewportHeightPoints <= 0) {
            result.onError("invalid_html_pdf_request", "El tamaño de página no es válido.")
            return
        }

        handler.post {
            val job = Job(
                html = html,
                widthPoints = viewportWidthPoints,
                heightPoints = viewportHeightPoints,
                readySelector = readySelector?.trim()?.takeIf { it.isNotEmpty() },
                readyFlag = readyFlag?.trim()?.takeIf { it.isNotEmpty() },
                timeoutMillis = timeoutMillis,
                result = result,
            )
            activeJobs.add(job)
            job.start()
        }
    }

    private inner class Job(
        private val html: String,
        private val widthPoints: Double,
        private val heightPoints: Double,
        private val readySelector: String?,
        private val readyFlag: String?,
        private val timeoutMillis: Long,
        private val result: Result,
    ) {
        private var webView: WebView? = null
        private var adapter: PrintDocumentAdapter? = null
        private var answered = false
        private var printing = false
        private var lastReadiness = "sin lectura"

        private val timeoutRunnable = Runnable {
            fail("html_pdf_timeout", "La plantilla no quedó lista a tiempo ($lastReadiness).")
        }

        fun start() {
            val configuration = android.content.res.Configuration(context.resources.configuration)
            configuration.fontScale = 1f
            val view = WebView(context.createConfigurationContext(configuration))
            webView = view

            @Suppress("SetJavaScriptEnabled")
            view.settings.javaScriptEnabled = true
            view.settings.loadsImagesAutomatically = true
            view.settings.blockNetworkImage = false
            view.settings.domStorageEnabled = true

            // The listener is installed before the load starts.
            view.webViewClient = object : WebViewClient() {
                override fun onPageFinished(view: WebView, url: String?) {
                    Log.d(TAG, "page finished")
                    pollReadiness(0)
                }

                override fun onReceivedError(
                    view: WebView,
                    request: WebResourceRequest,
                    error: WebResourceError,
                ) {
                    if (request.isForMainFrame) {
                        fail(
                            "html_pdf_load_failed",
                            "La plantilla no terminó de cargar: ${error.description}",
                        )
                    }
                }
            }

            handler.postDelayed(timeoutRunnable, timeoutMillis)
            Log.d(TAG, "load ${html.length} chars, deadline ${timeoutMillis}ms")
            view.loadDataWithBaseURL(null, html, "text/html", "utf-8", null)
        }

        private fun pollReadiness(elapsed: Long) {
            val view = webView ?: return
            if (answered || printing) {
                return
            }
            view.evaluateJavascript(readinessScript()) { value ->
                if (answered || printing) {
                    return@evaluateJavascript
                }
                val state = parseReadiness(value)
                if (state != null) {
                    lastReadiness = state.toString()
                    if (state.optBoolean("ready", false)) {
                        Log.d(TAG, "ready after ${elapsed}ms")
                        printDocument()
                        return@evaluateJavascript
                    }
                } else {
                    lastReadiness = "respuesta ilegible: $value"
                }
                handler.postDelayed({ pollReadiness(elapsed + POLL_INTERVAL_MS) }, POLL_INTERVAL_MS)
            }
        }

        private fun parseReadiness(value: String?): JSONObject? {
            val raw = value?.trim().orEmpty()
            if (raw.isEmpty() || raw == "null") {
                return null
            }
            val unwrapped = runCatching { JSONTokener(raw).nextValue() }.getOrNull()
            return when (unwrapped) {
                is JSONObject -> unwrapped
                is String -> runCatching { JSONObject(unwrapped) }.getOrNull()
                else -> null
            }
        }

        private fun readinessScript(): String {
            val selector = if (readySelector == null) "null" else JSONObject.quote(readySelector)
            val flag = if (readyFlag == null) "null" else JSONObject.quote(readyFlag)
            return """
                (function () {
                  var selector = $selector;
                  var readyFlag = $flag;
                  var required = selector ? document.querySelector(selector) : document.body;
                  var requiredReady = Boolean(required) && (
                    !selector ||
                    required.childElementCount > 0 ||
                    String(required.textContent || '').trim().length > 0
                  );
                  var images = Array.prototype.slice.call(document.images || []);
                  var pendingImages = images.filter(function (image) {
                    return !image.complete;
                  }).length;
                  var flagReady = !readyFlag || globalThis[readyFlag] === true;
                  var documentState = document.readyState;
                  return {
                    ready: documentState === 'complete' && pendingImages === 0 &&
                      requiredReady && flagReady,
                    documentState: documentState,
                    pendingImages: pendingImages,
                    requiredReady: requiredReady,
                    flagReady: flagReady
                  };
                })();
            """.trimIndent()
        }

        private fun printDocument() {
            val view = webView ?: return
            printing = true

            val mediaSize = PrintAttributes.MediaSize(
                "vinabike_invoice",
                "Viñabike",
                (widthPoints * MILS_PER_POINT).toInt(),
                (heightPoints * MILS_PER_POINT).toInt(),
            )
            val attributes = PrintAttributes.Builder()
                .setMediaSize(mediaSize)
                .setResolution(PrintAttributes.Resolution("pdf", "pdf", 600, 600))
                .setMinMargins(PrintAttributes.Margins.NO_MARGINS)
                .build()

            Log.d(TAG, "printing ${mediaSize.widthMils}x${mediaSize.heightMils} mils")
            val documentAdapter = view.createPrintDocumentAdapter("vinabike-invoice")
            adapter = documentAdapter

            VinabikeHtmlPdf.print(
                context,
                documentAdapter,
                attributes,
                object : VinabikeHtmlPdf.Result {
                    override fun onSuccess(document: ByteArray) {
                        handler.post {
                            if (document.size < PDF_HEADER.size ||
                                !document.copyOfRange(0, PDF_HEADER.size).contentEquals(PDF_HEADER)
                            ) {
                                fail(
                                    "html_pdf_render_failed",
                                    "Android devolvió un archivo que no es un PDF.",
                                )
                                return@post
                            }
                            Log.d(TAG, "produced ${document.size} bytes")
                            answer { result.onSuccess(document) }
                        }
                    }

                    override fun onError(message: String) {
                        handler.post { fail("html_pdf_render_failed", message) }
                    }
                },
            )
        }

        private fun fail(code: String, message: String) {
            Log.w(TAG, "$code: $message")
            answer { result.onError(code, message) }
        }

        private fun answer(deliver: () -> Unit) {
            if (answered) {
                return
            }
            answered = true
            handler.removeCallbacks(timeoutRunnable)
            runCatching { adapter?.onFinish() }
            adapter = null
            webView?.let { view ->
                runCatching {
                    view.stopLoading()
                    view.webViewClient = WebViewClient()
                    view.destroy()
                }
            }
            webView = null
            activeJobs.remove(this)
            deliver()
        }
    }

    private companion object {
        const val TAG = "VinabikeHtmlPdf"
        const val POLL_INTERVAL_MS = 80L
        const val MILS_PER_POINT = 1000.0 / 72.0
        val PDF_HEADER = byteArrayOf(0x25, 0x50, 0x44, 0x46, 0x2D)
    }
}
