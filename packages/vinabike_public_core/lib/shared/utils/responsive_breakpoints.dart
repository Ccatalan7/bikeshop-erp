/// Shared logical-viewport boundaries for application-level composition.
///
/// These values are measured before `WindowZoomScope` applies the desktop
/// browser-style transform. They are logical Flutter/CSS pixels, not hardware
/// panel pixels.
abstract final class ResponsiveBreakpoints {
  static const double phoneMaxExclusive = 600;
  static const double desktopMin = 900;
}
