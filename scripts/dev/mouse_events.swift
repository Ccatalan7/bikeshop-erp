// Real CGEvent mouse driver for driving the macOS app during agent
// verification. AppleScript's `click at` is NOT delivered to a Flutter
// window (the engine ignores it), so input must be posted as HID events.
//
// Compiled on demand by scripts/dev/app_control.sh into .tmp/dev-tools/mouse.
//
// Usage: mouse X Y [click|move|scroll DY|drag X2 Y2]
//   Coordinates are absolute screen points (origin top-left).
import CoreGraphics
import Foundation

let args = CommandLine.arguments
guard args.count >= 3, let x = Double(args[1]), let y = Double(args[2]) else {
  FileHandle.standardError.write(
    "usage: mouse X Y [click|move|scroll DY|drag X2 Y2]\n".data(using: .utf8)!)
  exit(1)
}

let point = CGPoint(x: x, y: y)
let mode = args.count > 3 ? args[3] : "click"
let source = CGEventSource(stateID: .hidSystemState)

func post(_ type: CGEventType, at location: CGPoint) {
  guard let event = CGEvent(
    mouseEventSource: source,
    mouseType: type,
    mouseCursorPosition: location,
    mouseButton: .left
  ) else { return }
  event.post(tap: .cghidEventTap)
}

switch mode {
case "move":
  post(.mouseMoved, at: point)

case "scroll":
  // Negative scrolls the content down (reveals what is below).
  let lines = args.count > 4 ? (Int32(args[4]) ?? -3) : -3
  post(.mouseMoved, at: point)
  usleep(60_000)
  if let event = CGEvent(
    scrollWheelEvent2Source: source,
    units: .line,
    wheelCount: 1,
    wheel1: lines, wheel2: 0, wheel3: 0
  ) {
    event.location = point
    event.post(tap: .cghidEventTap)
  }

case "drag":
  guard args.count >= 6, let x2 = Double(args[4]), let y2 = Double(args[5]) else {
    FileHandle.standardError.write("drag needs X2 Y2\n".data(using: .utf8)!)
    exit(1)
  }
  let target = CGPoint(x: x2, y: y2)
  post(.mouseMoved, at: point)
  usleep(40_000)
  post(.leftMouseDown, at: point)
  // Interpolate so Flutter sees a gesture, not a teleport.
  for step in 1...10 {
    let t = Double(step) / 10.0
    post(.leftMouseDragged, at: CGPoint(
      x: point.x + (target.x - point.x) * t,
      y: point.y + (target.y - point.y) * t))
    usleep(16_000)
  }
  post(.leftMouseUp, at: target)

default:
  post(.mouseMoved, at: point)
  usleep(40_000)
  post(.leftMouseDown, at: point)
  usleep(40_000)
  post(.leftMouseUp, at: point)
}

usleep(120_000)
