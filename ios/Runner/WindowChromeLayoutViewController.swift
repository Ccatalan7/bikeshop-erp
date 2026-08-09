import Flutter
import UIKit

private struct WindowChromeLayoutSnapshot {
  let viewSize: CGSize
  let margins: UIEdgeInsets
  let revision: UInt64

  func hasSameGeometry(as other: WindowChromeLayoutSnapshot) -> Bool {
    viewSize == other.viewSize && margins == other.margins
  }

  var arguments: [String: Any] {
    [
      "width": Double(viewSize.width),
      "height": Double(viewSize.height),
      "left": Double(margins.left),
      "right": Double(margins.right),
      "revision": NSNumber(value: revision),
    ]
  }
}

/// Flutter host that exports iPadOS 26's adaptive Window Controls region.
///
/// UIKit updates this region during ordinary layout, including window resize
/// events where `safeAreaInsets` itself may remain unchanged. Dart receives
/// only geometry; business data and window titles never cross this channel.
@objc(WindowChromeLayoutViewController)
final class WindowChromeLayoutViewController: FlutterViewController {
  private static let channelName =
    "com.vinabike.erp/window_chrome_layout_region"
  private static let metricsChangedMethod = "metricsChanged"
  private static let getCurrentMetricsMethod = "getCurrentMetrics"

  private var layoutChannel: FlutterMethodChannel?
  private var latestSnapshot: WindowChromeLayoutSnapshot?
  private var revision: UInt64 = 0

  override func viewDidLoad() {
    super.viewDidLoad()
    let channel = FlutterMethodChannel(
      name: Self.channelName,
      binaryMessenger: binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == Self.getCurrentMetricsMethod else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let self else {
        result(nil)
        return
      }
      result(self.refreshSnapshot().arguments)
    }
    layoutChannel = channel
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    let previous = latestSnapshot
    let current = refreshSnapshot()
    guard previous == nil || !current.hasSameGeometry(as: previous!) else {
      return
    }
    layoutChannel?.invokeMethod(
      Self.metricsChangedMethod,
      arguments: current.arguments
    )
  }

  private func refreshSnapshot() -> WindowChromeLayoutSnapshot {
    let size = view.bounds.size
    let margins = currentAdaptedMargins()
    if let current = latestSnapshot,
       current.viewSize == size,
       current.margins == margins {
      return current
    }
    revision &+= 1
    let next = WindowChromeLayoutSnapshot(
      viewSize: size,
      margins: margins,
      revision: revision
    )
    latestSnapshot = next
    return next
  }

  private func currentAdaptedMargins() -> UIEdgeInsets {
    guard #available(iOS 26.0, *),
          traitCollection.userInterfaceIdiom == .pad else {
      return .zero
    }
    let region = view.edgeInsets(
      for: .margins(cornerAdaptation: .horizontal)
    )
    return UIEdgeInsets(
      top: 0,
      left: region.left.isFinite ? max(0, region.left) : 0,
      bottom: 0,
      right: region.right.isFinite ? max(0, region.right) : 0
    )
  }
}
