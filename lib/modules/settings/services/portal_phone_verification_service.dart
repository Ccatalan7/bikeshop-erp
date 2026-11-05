import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/services/tenant_service.dart';
import '../../../shared/services/whatsapp_service.dart';

/// Lo que muestra la tarjeta «Confirmar teléfono en el portal» de
/// Configuración › WhatsApp.
class PortalPhoneVerificationState {
  const PortalPhoneVerificationState({
    required this.enabled,
    required this.templateStatus,
    required this.templateCheckFailed,
    required this.sent30d,
    required this.confirmed30d,
    required this.failed30d,
    required this.lastSentAt,
  });

  final bool enabled;

  /// `null` cuando la plantilla todavía no existe en Meta.
  final WhatsAppTemplateReviewStatus? templateStatus;

  /// Meta no respondió: no se sabe si la plantilla existe.
  final bool templateCheckFailed;
  final int sent30d;
  final int confirmed30d;
  final int failed30d;
  final DateTime? lastSentAt;

  bool get templateApproved => templateStatus?.isApproved == true;
}

/// La confirmación del teléfono en el portal (20261105010000): la cuenta pide
/// un código por WhatsApp y, al escribirlo, queda con su ficha del taller. Se
/// enciende por tienda en `company_settings` y sólo cuando Meta ya aprobó la
/// plantilla de autenticación: antes, cada código saldría y Meta lo
/// rechazaría.
class PortalPhoneVerificationService {
  PortalPhoneVerificationService(
      {SupabaseClient? client, WhatsAppService? whatsApp})
      : _client = client,
        _whatsApp = whatsApp;

  static const String enabledSettingKey =
      'customer_portal_phone_verification_enabled';

  final SupabaseClient? _client;
  final WhatsAppService? _whatsApp;

  SupabaseClient get _supabase => _client ?? Supabase.instance.client;
  WhatsAppService get _templates => _whatsApp ?? WhatsAppService();

  Future<PortalPhoneVerificationState> load() async {
    final tenantId = await _requireTenantId();
    final results = await Future.wait<Object?>([
      _supabase
          .from('company_settings')
          .select('value')
          .eq('tenant_id', tenantId)
          .eq('key', enabledSettingKey)
          .maybeSingle(),
      _supabase.rpc(
        'customer_phone_verification_stats_v1',
        params: {'p_tenant_id': tenantId},
      ),
      _templateStatus(),
    ]);
    final setting = results[0] as Map<String, dynamic>?;
    final stats = results[1] is Map
        ? Map<String, dynamic>.from(results[1] as Map)
        : const <String, dynamic>{};
    final template =
        results[2] as ({WhatsAppTemplateReviewStatus? status, bool failed});
    int count(String key) => (stats[key] as num?)?.toInt() ?? 0;
    return PortalPhoneVerificationState(
      enabled: setting?['value']?.toString().trim() == 'true',
      templateStatus: template.status,
      templateCheckFailed: template.failed,
      sent30d: count('sent_30d'),
      confirmed30d: count('confirmed_30d'),
      failed30d: count('failed_30d'),
      lastSentAt:
          DateTime.tryParse('${stats['last_sent_at'] ?? ''}')?.toLocal(),
    );
  }

  Future<void> setEnabled(bool enabled) async {
    final tenantId = await _requireTenantId();
    final value = enabled ? 'true' : 'false';
    final now = DateTime.now().toUtc().toIso8601String();
    final updated = await _supabase
        .from('company_settings')
        .update({'value': value, 'updated_at': now})
        .eq('tenant_id', tenantId)
        .eq('key', enabledSettingKey)
        .select('id');
    if ((updated as List).isNotEmpty) return;
    await _supabase.from('company_settings').insert({
      'tenant_id': tenantId,
      'key': enabledSettingKey,
      'value': value,
      'updated_at': now,
    });
  }

  Future<WhatsAppTemplateReviewStatus> createTemplate() =>
      _templates.createTemplateInMeta(
        WhatsAppService.phoneVerificationTemplateName,
      );

  Future<({WhatsAppTemplateReviewStatus? status, bool failed})>
      _templateStatus() async {
    try {
      final statuses = await _templates.getSupplierTemplateReviewStatuses();
      return (
        status: statuses[WhatsAppService.phoneVerificationTemplateName],
        failed: false,
      );
    } catch (error) {
      debugPrint('[PortalPhoneVerification] estado de la plantilla: $error');
      return (status: null, failed: true);
    }
  }

  Future<String> _requireTenantId() async {
    final tenantId = await TenantService().getTenantId();
    if (tenantId == null || tenantId.isEmpty) {
      throw StateError('No hay una tienda activa en la sesión.');
    }
    return tenantId;
  }
}
