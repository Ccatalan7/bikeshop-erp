import Cocoa
import FlutterMacOS
import Vision

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    let payrollOcrChannel = FlutterMethodChannel(
      name: "com.vinabike.erp/payroll_statement_ocr",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    payrollOcrChannel.setMethodCallHandler { call, result in
      guard call.method == "recognizeText" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let typedData = call.arguments as? FlutterStandardTypedData else {
        result(
          FlutterError(
            code: "invalid_image",
            message: "La imagen OCR no es válida.",
            details: nil
          )
        )
        return
      }

      DispatchQueue.global(qos: .userInitiated).async {
        do {
          let text = try Self.recognizePayrollText(in: typedData.data)
          DispatchQueue.main.async { result(text) }
        } catch {
          DispatchQueue.main.async {
            result(
              FlutterError(
                code: "ocr_failed",
                message: "No se pudo reconocer el texto de la cartola.",
                details: nil
              )
            )
          }
        }
      }
    }

    super.awakeFromNib()
  }

  private static func recognizePayrollText(in data: Data) throws -> String {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    request.recognitionLanguages = ["es-CL", "en-US"]
    request.minimumTextHeight = 0.004

    let handler = VNImageRequestHandler(data: data, options: [:])
    try handler.perform([request])
    let observations = request.results ?? []
    let ordered = observations.sorted { left, right in
      let verticalDistance = abs(left.boundingBox.midY - right.boundingBox.midY)
      if verticalDistance < 0.012 {
        return left.boundingBox.minX < right.boundingBox.minX
      }
      return left.boundingBox.midY > right.boundingBox.midY
    }
    return ordered.compactMap { observation in
      observation.topCandidates(1).first?.string
    }.joined(separator: "\n")
  }
}
