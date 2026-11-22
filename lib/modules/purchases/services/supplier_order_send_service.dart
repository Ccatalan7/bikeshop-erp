import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/services/tenant_service.dart';

export '../../../shared/utils/supplier_order_when.dart';

/// **A qué hora le sale solo el pedido a un proveedor** (20261122030000).
///
/// Lo vendido a pedido se junta en el pedido abierto del proveedor y la base
/// se lo manda por WhatsApp, con su PDF, el primer día hábil a esta hora
/// (09:30 si nadie la cambió). Sin hora, lo manda una persona desde «Enviar
/// al proveedor». Lo leen y lo cambian la ficha del proveedor
/// (`supplier_order_send_settings_v1`, `set_supplier_order_send_time_v1`).
class SupplierOrderSendSettings {
  const SupplierOrderSendSettings({
    required this.sendTime,
    required this.sellsOnOrder,
    required this.autoSendEnabled,
    this.openOrderId,
    this.openOrderNumber,
    this.openOrderSendAt,
  });

  factory SupplierOrderSendSettings.fromJson(Map<String, dynamic> json) {
    final open = json['open_order'];
    return SupplierOrderSendSettings(
      sendTime: _text(json['send_time']),
      sellsOnOrder: json['sells_on_order'] == true,
      autoSendEnabled: json['auto_send_enabled'] == true,
      openOrderId: open is Map ? _text(open['id']) : null,
      openOrderNumber: open is Map ? _text(open['number']) : null,
      openOrderSendAt: open is Map ? _date(open['send_at']) : null,
    );
  }

  /// `HH:MM`; null: «Lo mando yo».
  final String? sendTime;

  /// Tiene productos que se venden a pedido: sin ellos no hay pedido que
  /// salga solo, y la ficha no ocupa lugar con esto.
  final bool sellsOnOrder;

  /// La tienda lo encendió (después de desplegar el PDF del servidor).
  final bool autoSendEnabled;

  final String? openOrderId;
  final String? openOrderNumber;

  /// Cuándo sale solo el pedido abierto; null si no sale solo.
  final DateTime? openOrderSendAt;

  /// Las horas que se ofrecen a la vista, en la mañana: el proveedor tiene
  /// que procesarlo y despacharlo el mismo día (dueño, 2026-11-21).
  static const choices = <String>[
    '08:00',
    '08:30',
    '09:00',
    '09:30',
    '10:00',
    '10:30',
    '11:00',
    '12:00',
  ];

  static String? _text(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  static DateTime? _date(Object? value) =>
      value == null ? null : DateTime.tryParse(value.toString());
}

/// Lee y cambia la hora de un proveedor.
abstract interface class SupplierOrderSendSource {
  Future<SupplierOrderSendSettings> read(String supplierId);

  /// [sendTime] `HH:MM`, o null para «Lo mando yo».
  Future<SupplierOrderSendSettings> setSendTime(
    String supplierId,
    String? sendTime,
  );
}

class SupabaseSupplierOrderSendSource implements SupplierOrderSendSource {
  SupabaseSupplierOrderSendSource({
    SupabaseClient? client,
    TenantService? tenantService,
  })  : _client = client,
        _tenantService = tenantService ?? TenantService();

  final SupabaseClient? _client;
  final TenantService _tenantService;

  SupabaseClient get _supabase => _client ?? Supabase.instance.client;

  Future<String> _tenantId() async {
    final tenantId = await _tenantService.getTenantId();
    if (tenantId == null || tenantId.isEmpty) {
      throw StateError('No se pudo resolver la tienda.');
    }
    return tenantId;
  }

  @override
  Future<SupplierOrderSendSettings> read(String supplierId) async {
    final response = await _supabase.rpc(
      'supplier_order_send_settings_v1',
      params: {'p_tenant_id': await _tenantId(), 'p_supplier_id': supplierId},
    );
    return SupplierOrderSendSettings.fromJson(
      Map<String, dynamic>.from(response as Map),
    );
  }

  @override
  Future<SupplierOrderSendSettings> setSendTime(
    String supplierId,
    String? sendTime,
  ) async {
    final response = await _supabase.rpc(
      'set_supplier_order_send_time_v1',
      params: {
        'p_tenant_id': await _tenantId(),
        'p_supplier_id': supplierId,
        'p_send_time': sendTime,
      },
    );
    return SupplierOrderSendSettings.fromJson(
      Map<String, dynamic>.from(response as Map),
    );
  }
}
