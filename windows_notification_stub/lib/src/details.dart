export 'initialization_settings.dart';
export 'notification_details.dart';

/// The result of updating a notification.
enum NotificationUpdateResult {
  /// The update was successful.
  success,

  /// There was an unexpected error updating the notification.
  error,

  /// No notification with the provided ID could be found.
  notFound,
}
