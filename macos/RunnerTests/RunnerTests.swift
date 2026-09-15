import Cocoa
import FlutterMacOS
import PDFKit
import XCTest
@testable import vinabike_erp

class RunnerTests: XCTestCase {

  func testHTMLPDFRendererWaitsForReadyContentAndReturnsAValidPDF() {
    let rendered = expectation(description: "HTML rendered as PDF")
    let renderer = HTMLPDFRenderer()
    let html = """
      <!doctype html>
      <html>
        <body>
          <main id="invoiceRoot"></main>
          <script>
            setTimeout(() => {
              document.querySelector('#invoiceRoot').textContent = 'Pedido AliExpress';
              globalThis.__ALIEXPRESS_INVOICE_READY__ = true;
            }, 75);
          </script>
        </body>
      </html>
      """

    renderer.render(
      html: html,
      viewportSize: NSSize(width: 612, height: 792),
      readySelector: "#invoiceRoot",
      readyFlag: "__ALIEXPRESS_INVOICE_READY__",
      timeout: 5
    ) { outcome in
      switch outcome {
      case .success(let data):
        XCTAssertTrue(data.starts(with: Data("%PDF-".utf8)))
        XCTAssertGreaterThan(PDFDocument(data: data)?.pageCount ?? 0, 0)
      case .failure(let error):
        XCTFail("El renderizador falló: \(error.localizedDescription)")
      }
      rendered.fulfill()
    }

    wait(for: [rendered], timeout: 8)
  }
}
