package com.vinabike.erp

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val updateChannelName = "com.vinabike.erp/android_update"
    private val htmlPdfChannelName = "com.vinabike.erp/html_pdf_renderer"
    private var pendingInstallerPath: String? = null
    private var htmlPdfRenderer: HtmlPdfRenderer? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        configureHtmlPdfRenderer(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            updateChannelName,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getInstalledVersionCode" -> {
                    result.success(installedVersionCode())
                }

                "installApk" -> {
                    val apkPath = call.argument<String>("path")
                    if (apkPath.isNullOrBlank()) {
                        result.error(
                            "invalid_path",
                            "The downloaded APK path is missing.",
                            null,
                        )
                        return@setMethodCallHandler
                    }

                    try {
                        val apk = validatedUpdateFile(apkPath)
                        if (
                            Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                            !packageManager.canRequestPackageInstalls()
                        ) {
                            pendingInstallerPath = apk.path
                            startActivity(
                                Intent(
                                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                    Uri.parse("package:$packageName"),
                                ),
                            )
                            result.success("permission_requested")
                        } else {
                            openSystemInstaller(apk)
                            result.success("installer_opened")
                        }
                    } catch (error: Exception) {
                        result.error(
                            "install_failed",
                            error.message ?: "Android could not open the installer.",
                            null,
                        )
                    }
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun configureHtmlPdfRenderer(flutterEngine: FlutterEngine) {
        val renderer = htmlPdfRenderer ?: HtmlPdfRenderer(applicationContext).also {
            htmlPdfRenderer = it
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            htmlPdfChannelName,
        ).setMethodCallHandler { call, result ->
            if (call.method != "renderHtml") {
                result.notImplemented()
                return@setMethodCallHandler
            }

            val html = call.argument<String>("html")
            val viewportWidth = call.argument<Double>("viewportWidth")
            val viewportHeight = call.argument<Double>("viewportHeight")
            if (html.isNullOrBlank() || viewportWidth == null || viewportHeight == null) {
                result.error(
                    "invalid_html_pdf_request",
                    "Faltan los datos necesarios para generar el PDF.",
                    null,
                )
                return@setMethodCallHandler
            }

            renderer.render(
                html = html,
                viewportWidthPoints = viewportWidth,
                viewportHeightPoints = viewportHeight,
                readySelector = call.argument<String>("readySelector"),
                readyFlag = call.argument<String>("readyFlag"),
                timeoutMillis = (call.argument<Number>("timeoutMillis")?.toLong() ?: 25_000L),
                result = object : HtmlPdfRenderer.Result {
                    override fun onSuccess(document: ByteArray) {
                        result.success(document)
                    }

                    override fun onError(code: String, message: String) {
                        result.error(code, message, null)
                    }
                },
            )
        }
    }

    override fun onResume() {
        super.onResume()

        val path = pendingInstallerPath ?: return
        if (
            Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
            packageManager.canRequestPackageInstalls()
        ) {
            pendingInstallerPath = null
            window.decorView.post {
                runCatching {
                    openSystemInstaller(validatedUpdateFile(path))
                }
            }
        }
    }

    private fun validatedUpdateFile(rawPath: String): File {
        val apk = File(rawPath).canonicalFile
        val cacheRoot = cacheDir.canonicalFile
        val isInsideCache =
            apk.path.startsWith("${cacheRoot.path}${File.separator}")

        require(isInsideCache) {
            "The APK must be inside the application cache."
        }
        require(apk.isFile && apk.name.endsWith(".apk", ignoreCase = true)) {
            "The downloaded APK is missing or invalid."
        }

        return apk
    }

    @Suppress("DEPRECATION")
    private fun installedVersionCode(): Long {
        val packageInfo = packageManager.getPackageInfo(packageName, 0)
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            packageInfo.longVersionCode
        } else {
            packageInfo.versionCode.toLong()
        }
    }

    private fun openSystemInstaller(apk: File) {
        val contentUri = FileProvider.getUriForFile(
            this,
            "$packageName.fileprovider",
            apk,
        )
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(
                contentUri,
                "application/vnd.android.package-archive",
            )
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(intent)
    }
}
