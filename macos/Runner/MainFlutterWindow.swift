import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var htmlPDFRenderer: HTMLPDFRenderer?
  private var htmlPDFRendererChannel: FlutterMethodChannel?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // macOS marca una ventana tapada como "ocluida" y WebKit entonces
    // SUSPENDE la página del WKWebView: sus timers dejan de correr y hasta el
    // JavaScript que se le pide evaluar queda encolado sin ejecutarse.
    //
    // Para el ERP eso no es una optimización, es una falla: la importación de
    // «Compras del día» de AliExpress recorre el listado dentro del WebView y
    // se congelaba indefinidamente en cuanto el usuario ponía otra ventana
    // encima —el diálogo seguía girando y sólo «revivía» al volver a mirar la
    // pantalla— (diagnosticado el 2026-08-06 con un latido en la página que no
    // emitió un solo tick durante el cuelgue).
    //
    // `preventsOcclusion` desactiva esa optimización para esta ventana. El
    // costo es que la app sigue dibujando en segundo plano; el beneficio es
    // que cualquier trabajo dentro de un WebView termina aunque el usuario se
    // vaya a otra aplicación.
    // Comprobado por selector: `setValue(_:forKey:)` a secas lanza
    // NSUnknownKeyException —no capturable desde Swift— y la app no llega ni a
    // abrir si una versión de macOS deja de exponer la propiedad.
    let preventsOcclusionSelector = NSSelectorFromString("setPreventsOcclusion:")
    if self.responds(to: preventsOcclusionSelector) {
      self.perform(preventsOcclusionSelector, with: true as NSNumber)
    }

    RegisterGeneratedPlugins(registry: flutterViewController)
    registerHTMLPDFRenderer(on: flutterViewController)
    super.awakeFromNib()
  }

  private func registerHTMLPDFRenderer(
    on flutterViewController: FlutterViewController
  ) {
    htmlPDFRenderer = HTMLPDFRenderer()
    let channel = FlutterMethodChannel(
      name: "com.vinabike.erp/html_pdf_renderer",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "renderHtml" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let renderer = self?.htmlPDFRenderer,
            let arguments = call.arguments as? [String: Any],
            let html = arguments["html"] as? String,
            let viewportWidth = arguments["viewportWidth"] as? NSNumber,
            let viewportHeight = arguments["viewportHeight"] as? NSNumber else {
        result(
          FlutterError(
            code: "invalid_html_pdf_request",
            message: "Faltan los datos necesarios para generar el PDF.",
            details: nil
          )
        )
        return
      }

      renderer.render(
        html: html,
        viewportSize: NSSize(
          width: viewportWidth.doubleValue,
          height: viewportHeight.doubleValue
        ),
        readySelector: arguments["readySelector"] as? String,
        readyFlag: arguments["readyFlag"] as? String
      ) { outcome in
        switch outcome {
        case .success(let data):
          result(FlutterStandardTypedData(bytes: data))
        case .failure(let error):
          result(
            FlutterError(
              code: "html_pdf_render_failed",
              message: error.localizedDescription,
              details: error.channelDetails
            )
          )
        }
      }
    }
    htmlPDFRendererChannel = channel
  }
}
