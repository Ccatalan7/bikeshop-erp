import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/services/tenant_service.dart';
import '../../../shared/services/whatsapp_service.dart';

/// Lo que muestra la tarjeta «Reseñas de Google» de Configuración › WhatsApp.
class GoogleReviewRequestState {
  const GoogleReviewRequestState({
    required this.enabled,
    required this.templateStatus,
    required this.templateCheckFailed,
    required this.sent30d,
    required this.skipped30d,
    required this.skippedByReason,
    required this.lastSentAt,
  });

  final bool enabled;

  /// `null` cuando la plantilla todavía no existe en Meta.
  final WhatsAppTemplateReviewStatus? templateStatus;

  /// Meta no respondió: no se sabe si la plantilla existe.
  final bool templateCheckFailed;
  final int sent30d;
  final int skipped30d;

  /// Motivo legible → cantidad, de mayor a menor.
  final List<MapEntry<String, int>> skippedByReason;
  final DateTime? lastSentAt;

  bool get templateApproved => templateStatus?.isApproved == true;
}

/// El pedido automático de reseña de Google después de una entrega
/// (`process_whatsapp_review_requests_v1`, 2026-10-08). Se enciende por tienda
/// en `company_settings` y sólo cuando Meta ya aprobó la plantilla: antes, el
/// mensaje saldría de la cola y Meta lo rechazaría sin reintento.
class GoogleReviewRequestService {
  static const String enabledSettingKey = 'whatsapp_review_request_enabled';

  SupabaseClient get _supabase => Supabase.instance.client;

  Future<GoogleReviewRequestState> load() async {
    final tenantId = await _requireTenantId();
    final since30d = DateTime.now().toUtc().subtract(const Duration(days: 30));

    final results = await Future.wait<Object?>([
      _supabase
          .from('company_settings')
          .select('value')
          .eq('tenant_id', tenantId)
          .eq('key', enabledSettingKey)
          .maybeSingle(),
      _supabase
          .from('whatsapp_review_requests')
          .select('status, reason, created_at')
          .eq('tenant_id', tenantId)
          .gte('created_at', since30d.toIso8601String())
          .order('created_at', ascending: false)
          .limit(500),
      _templateStatus(),
    ]);

    final setting = results[0] as Map<String, dynamic>?;
    final rows = List<Map<String, dynamic>>.from(results[1] as List);
    final template =
        results[2] as ({WhatsAppTemplateReviewStatus? status, bool failed});

    var sent = 0;
    var skipped = 0;
    DateTime? lastSentAt;
    final reasons = <String, int>{};
    for (final row in rows) {
      if (row['status'] == 'sent') {
        sent += 1;
        final createdAt = DateTime.tryParse('${row['created_at']}');
        if (createdAt != null &&
            (lastSentAt == null || createdAt.isAfter(lastSentAt))) {
          lastSentAt = createdAt;
        }
      } else {
        skipped += 1;
        final label = skipReasonLabel(row['reason']?.toString());
        reasons[label] = (reasons[label] ?? 0) + 1;
      }
    }
    final byReason = reasons.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return GoogleReviewRequestState(
      enabled: setting?['value']?.toString().trim() == 'true',
      templateStatus: template.status,
      templateCheckFailed: template.failed,
      sent30d: sent,
      skipped30d: skipped,
      skippedByReason: byReason,
      lastSentAt: lastSentAt?.toLocal(),
    );
  }

  Future<void> setEnabled(bool enabled) async {
    final tenantId = await _requireTenantId();
    final value = enabled ? 'true' : 'false';
    final updated = await _supabase
        .from('company_settings')
        .update({
          'value': value,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('tenant_id', tenantId)
        .eq('key', enabledSettingKey)
        .select('id');
    if ((updated as List).isNotEmpty) return;
    await _supabase.from('company_settings').insert({
      'tenant_id': tenantId,
      'key': enabledSettingKey,
      'value': value,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<WhatsAppTemplateReviewStatus> createTemplate() =>
      WhatsAppService().createTemplateInMeta(
        WhatsAppService.reviewRequestTemplateName,
      );

  /// El motivo guardado por la base, en palabras del taller.
  static String skipReasonLabel(String? reason) {
    final value = reason ?? '';
    if (value.startsWith('send_failed') || value == 'send_not_accepted') {
      return 'no se pudo enviar';
    }
    return switch (value) {
      'asked_this_year' => 'ya se le pidió este año',
      'no_mobile' => 'sin celular',
      'no_customer' => 'sin cliente',
      'job_not_delivered' => 'ya no figuraba entregado',
      'no_actor' => 'sin quién entregó',
      'no_review_link' => 'el sitio no tiene su lugar de Google',
      'no_channel' => 'sin canal de WhatsApp activo',
      _ => 'otro motivo',
    };
  }

  Future<({WhatsAppTemplateReviewStatus? status, bool failed})>
      _templateStatus() async {
    try {
      final statuses =
          await WhatsAppService().getSupplierTemplateReviewStatuses();
      return (
        status: statuses[WhatsAppService.reviewRequestTemplateName],
        failed: false,
      );
    } catch (error) {
      debugPrint('[GoogleReviewRequest] estado de la plantilla: $error');
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
