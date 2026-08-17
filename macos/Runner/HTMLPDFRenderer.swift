import AppKit
import Foundation
import PDFKit
import WebKit

enum HTMLPDFRendererError: LocalizedError {
  case invalidRequest(String)
  case navigationFailed(domain: String, code: Int, description: String)
  case contentProcessTerminated
  case contentNotReady([String: Any])
  case renderingFailed(domain: String, code: Int, description: String)
  case invalidPDF

  var errorDescription: String? {
    switch self {
    case .invalidRequest(let reason):
      return "No se pudo preparar el documento HTML: \(reason)"
    case .navigationFailed(_, _, let description):
      return "La plantilla HTML no terminó de cargar: \(description)"
    case .contentProcessTerminated:
      return "WebKit cerró el proceso que estaba preparando la plantilla."
    case .contentNotReady(let state):
      let documentState = state["documentState"] as? String ?? "desconocido"
      let fontsState = state["fontsState"] as? String ?? "desconocido"
      let pendingImages = (state["pendingImages"] as? NSNumber)?.intValue ?? -1
      return "La plantilla no quedó lista antes del tiempo límite "
        + "(documento: \(documentState), fuentes: \(fontsState), "
        + "imágenes pendientes: \(pendingImages))."
    case .renderingFailed(let domain, let code, let description):
      return "WebKit no pudo generar el PDF (\(domain) \(code)): \(description)"
    case .invalidPDF:
      return "WebKit terminó, pero no devolvió un PDF válido."
    }
  }

  var channelDetails: [String: Any] {
    switch self {
    case .navigationFailed(let domain, let code, _),
         .renderingFailed(let domain, let code, _):
      return ["domain": domain, "code": code]
    case .contentNotReady(let state):
      return state
    default:
      return [:]
    }
  }
}

/// Owns all active HTML-to-PDF jobs so their WKWebViews remain alive until
/// WebKit completes. Every job uses a non-persistent store and an off-screen,
/// attached window; a detached WKWebView can fail with WKErrorUnknown on some
/// Macs even when the same build succeeds on another machine.
final class HTMLPDFRenderer {
  private var activeJobs: [UUID: HTMLPDFRenderJob] = [:]

  func render(
    html: String,
    viewportSize: NSSize,
    readySelector: String?,
    readyFlag: String?,
    timeout: TimeInterval = 20,
    completion: @escaping (Result<Data, HTMLPDFRendererError>) -> Void
  ) {
    guard Thread.isMainThread else {
      DispatchQueue.main.async { [weak self] in
        self?.render(
          html: html,
          viewportSize: viewportSize,
          readySelector: readySelector,
          readyFlag: readyFlag,
          timeout: timeout,
          completion: completion
        )
      }
      return
    }

    let identifier = UUID()
    do {
      let job = try HTMLPDFRenderJob(
        html: html,
        viewportSize: viewportSize,
        readySelector: readySelector,
        readyFlag: readyFlag,
        timeout: timeout
      ) { [weak self] outcome in
        self?.activeJobs.removeValue(forKey: identifier)
        completion(outcome)
      }
      activeJobs[identifier] = job
      job.start()
    } catch let error as HTMLPDFRendererError {
      completion(.failure(error))
    } catch {
      completion(.failure(.invalidRequest(error.localizedDescription)))
    }
  }
}

private final class HTMLPDFRenderJob: NSObject, WKNavigationDelegate {
  private static let pollingInterval: TimeInterval = 0.05
  private static let offscreenOrigin = NSPoint(x: -20_000, y: -20_000)

  private let html: String
  private let viewportSize: NSSize
  private let readySelector: String?
  private let readyFlag: String?
  private let timeout: TimeInterval
  private let completion: (Result<Data, HTMLPDFRendererError>) -> Void

  private var renderWindow: NSWindow?
  private var webView: WKWebView?
  private var timeoutWorkItem: DispatchWorkItem?
  private var lastReadinessState: [String: Any] = [:]
  private var completed = false
  private var rendering = false

  init(
    html: String,
    viewportSize: NSSize,
    readySelector: String?,
    readyFlag: String?,
    timeout: TimeInterval,
    completion: @escaping (Result<Data, HTMLPDFRendererError>) -> Void
  ) throws {
    guard !html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw HTMLPDFRendererError.invalidRequest("el contenido está vacío")
    }
    guard viewportSize.width.isFinite,
          viewportSize.height.isFinite,
          (144 ... 2_000).contains(viewportSize.width),
          (144 ... 2_000).contains(viewportSize.height) else {
      throw HTMLPDFRendererError.invalidRequest("el tamaño de página no es válido")
    }
    guard timeout.isFinite, timeout > 0, timeout <= 60 else {
      throw HTMLPDFRendererError.invalidRequest("el tiempo límite no es válido")
    }
    self.html = html
    self.viewportSize = viewportSize
    self.readySelector = readySelector?.trimmingCharacters(in: .whitespacesAndNewlines)
    self.readyFlag = readyFlag?.trimmingCharacters(in: .whitespacesAndNewlines)
    self.timeout = timeout
    self.completion = completion
    super.init()
  }

  func start() {
    dispatchPrecondition(condition: .onQueue(.main))

    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = .nonPersistent()
    configuration.suppressesIncrementalRendering = true

    let frame = NSRect(origin: .zero, size: viewportSize)
    let webView = WKWebView(frame: frame, configuration: configuration)
    webView.navigationDelegate = self

    let window = NSWindow(
      contentRect: NSRect(origin: Self.offscreenOrigin, size: viewportSize),
      styleMask: [.borderless],
      backing: .buffered,
      defer: false
    )
    window.isReleasedWhenClosed = false
    window.isExcludedFromWindowsMenu = true
    window.ignoresMouseEvents = true
    window.hasShadow = false
    window.collectionBehavior = [.transient, .ignoresCycle]
    window.contentView = webView

    // WebKit may suspend an occluded/off-screen window. The main ERP window
    // uses this same guarded selector for long AliExpress collection runs.
    let preventsOcclusionSelector = NSSelectorFromString("setPreventsOcclusion:")
    if window.responds(to: preventsOcclusionSelector) {
      window.perform(preventsOcclusionSelector, with: true as NSNumber)
    }

    renderWindow = window
    self.webView = webView
    window.orderFront(nil)

    let timeoutWorkItem = DispatchWorkItem { [weak self] in
      guard let self else { return }
      self.finish(.failure(.contentNotReady(self.lastReadinessState)))
    }
    self.timeoutWorkItem = timeoutWorkItem
    DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: timeoutWorkItem)

    webView.loadHTMLString(html, baseURL: nil)
  }

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    pollReadiness()
  }

  func webView(
    _ webView: WKWebView,
    didFail navigation: WKNavigation!,
    withError error: Error
  ) {
    failNavigation(error)
  }

  func webView(
    _ webView: WKWebView,
    didFailProvisionalNavigation navigation: WKNavigation!,
    withError error: Error
  ) {
    failNavigation(error)
  }

  func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
    finish(.failure(.contentProcessTerminated))
  }

  private func failNavigation(_ error: Error) {
    let nativeError = error as NSError
    finish(
      .failure(
        .navigationFailed(
          domain: nativeError.domain,
          code: nativeError.code,
          description: nativeError.localizedDescription
        )
      )
    )
  }

  private func pollReadiness() {
    guard !completed, !rendering, let webView else { return }
    webView.evaluateJavaScript(readinessScript) { [weak self] value, error in
      guard let self, !self.completed, !self.rendering else { return }
      if let state = value as? [String: Any] {
        self.lastReadinessState = state
        if state["ready"] as? Bool == true {
          self.renderPDF()
          return
        }
      } else if let error {
        let nativeError = error as NSError
        self.lastReadinessState = [
          "documentState": "javascript-error",
          "fontsState": "unknown",
          "pendingImages": -1,
          "domain": nativeError.domain,
          "code": nativeError.code,
        ]
      }
      DispatchQueue.main.asyncAfter(
        deadline: .now() + Self.pollingInterval
      ) { [weak self] in
        self?.pollReadiness()
      }
    }
  }

  private var readinessScript: String {
    let selectorLiteral = Self.jsonLiteral(readySelector)
    let flagLiteral = Self.jsonLiteral(readyFlag)
    return """
      (() => {
        const selector = \(selectorLiteral);
        const readyFlag = \(flagLiteral);
        const required = selector ? document.querySelector(selector) : document.body;
        const requiredReady = Boolean(required) && (
          !selector ||
          required.childElementCount > 0 ||
          String(required.textContent || '').trim().length > 0
        );
        const images = Array.from(document.images || []);
        const pendingImages = images.filter((image) => !image.complete).length;
        const fontsState = document.fonts ? document.fonts.status : 'unsupported';
        const flagReady = !readyFlag || globalThis[readyFlag] === true;
        const documentState = document.readyState;
        return {
          ready: documentState === 'complete' &&
            (fontsState === 'loaded' || fontsState === 'unsupported') &&
            pendingImages === 0 &&
            requiredReady &&
            flagReady,
          documentState,
          fontsState,
          pendingImages,
          requiredReady,
          flagReady,
        };
      })()
      """
  }

  private func renderPDF() {
    guard !completed, !rendering, let webView else { return }
    rendering = true
    webView.createPDF { [weak self] outcome in
      guard let self else { return }
      switch outcome {
      case .success(let data):
        guard data.starts(with: Data("%PDF-".utf8)),
              let document = PDFDocument(data: data),
              document.pageCount > 0 else {
          self.finish(.failure(.invalidPDF))
          return
        }
        self.finish(.success(data))
      case .failure(let error):
        let nativeError = error as NSError
        self.finish(
          .failure(
            .renderingFailed(
              domain: nativeError.domain,
              code: nativeError.code,
              description: nativeError.localizedDescription
            )
          )
        )
      }
    }
  }

  private func finish(_ outcome: Result<Data, HTMLPDFRendererError>) {
    guard !completed else { return }
    completed = true
    timeoutWorkItem?.cancel()
    timeoutWorkItem = nil
    webView?.navigationDelegate = nil
    webView?.stopLoading()
    webView?.removeFromSuperview()
    webView = nil
    renderWindow?.orderOut(nil)
    renderWindow?.contentView = nil
    renderWindow?.close()
    renderWindow = nil
    completion(outcome)
  }

  private static func jsonLiteral(_ value: String?) -> String {
    guard let value, !value.isEmpty,
          let data = try? JSONSerialization.data(
            withJSONObject: value,
            options: [.fragmentsAllowed]
          ),
          let encoded = String(data: data, encoding: .utf8) else {
      return "null"
    }
    return encoded
  }
}
