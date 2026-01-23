/// Stub Windows initialization settings.
class WindowsInitializationSettings {
  /// Creates a new [WindowsInitializationSettings].
  const WindowsInitializationSettings({
    this.appName,
    this.appUserModelId,
    this.guid,
  });

  /// The application's name.
  final String? appName;

  /// The application user model ID.
  final String? appUserModelId;

  /// An optional GUID to associate with this app's notifications.
  final String? guid;
}
