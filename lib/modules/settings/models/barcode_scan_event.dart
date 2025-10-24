/// Model for barcode scan events transmitted via Supabase Realtime
class BarcodeScanEvent {
  final String barcode;
  final String deviceId;
  final String deviceName;
  final DateTime timestamp;
  final String? targetModule; // 'inventory', 'pos', 'sales', etc.
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
    // Handle nested payload structure from Supabase broadcast
    final data = json.containsKey('payload') ? json['payload'] as Map<String, dynamic> : json;
    
    return BarcodeScanEvent(
      barcode: data['barcode'] as String,
      deviceId: data['device_id'] as String,
      deviceName: data['device_name'] as String,
      timestamp: DateTime.parse(data['timestamp'] as String),
      targetModule: data['target_module'] as String?,
      metadata: data['metadata'] as Map<String, dynamic>?,
    );
  }

  @override
  String toString() =>
      'BarcodeScanEvent(barcode: $barcode, device: $deviceName, module: $targetModule)';
}
