/// Stub Windows notification details.
class WindowsNotificationDetails {
  /// Creates [WindowsNotificationDetails].
  const WindowsNotificationDetails({
    this.actions,
    this.audio,
    this.bindings,
    this.duration,
    this.group,
    this.inputs,
    this.progressBar,
    this.rows,
    this.scenario,
    this.subtitle,
    this.timestamp,
  });

  /// The actions to display.
  final List<Object>? actions;

  /// The audio to play.
  final Object? audio;

  /// Custom data bindings.
  final Map<String, String>? bindings;

  /// The notification duration.
  final Object? duration;

  /// The notification group.
  final Object? group;

  /// Text inputs.
  final List<Object>? inputs;

  /// A progress bar.
  final Object? progressBar;

  /// Rows of content.
  final List<Object>? rows;

  /// The notification scenario.
  final Object? scenario;

  /// An optional subtitle.
  final String? subtitle;

  /// An optional timestamp.
  final DateTime? timestamp;
}
