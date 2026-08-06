import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
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
    super.awakeFromNib()
  }
}
