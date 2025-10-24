/// Model for barcode scan events transmitted via Supabase Realtime
class BarcodeScanEvent {
  final String barcode;
  final String deviceId;
  final String deviceName;
  final DateTime timestamp;
  final String? targetModule;
  final Map<String, dynamic>? metadata;

  BarcodeScanEvent({
    required this.barcode,
    required this.deviceId,
    required this.deviceName,
    required this.timestamp,
    this.targetModule,
    this.metadata,
  });

  Map<String, dynamic> toJson() => {
        'barcode': barcode,
        'device_id': deviceId,
        'device_name': deviceName,
        'timestamp': timestamp.toIso8601String(),
        'target_module': targetModule,
        'metadata': metadata,
      };

  factory BarcodeScanEvent.fromJson(Map<String, dynamic> json) {
    return BarcodeScanEvent(
      barcode: json['barcode'] as String,
      deviceId: json['device_id'] as String,
      deviceName: json['device_name'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      targetModule: json['target_module'] as String?,
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }
}

/// Model for scan history item
class ScanHistoryItem {
  final String barcode;
  final DateTime timestamp;
  final String? targetModule;
  final bool sent;

  ScanHistoryItem({
    required this.barcode,
    required this.timestamp,
    this.targetModule,
    this.sent = false,
  });
}
