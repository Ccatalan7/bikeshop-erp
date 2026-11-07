import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/services/tenant_service.dart';
import '../../../shared/services/whatsapp_service.dart';

/// Los cuatro momentos en que el taller le avisa al cliente
/// (20261105130000).
enum WorkshopNoticeKind {
  received(
    code: 'received',
    title: 'Bici recibida',
    when: 'Al crear el trabajo',
    templateName: WhatsAppService.workshopReceivedTemplateName,
    fallbackTemplateNames: [WhatsAppService.workshopReceivedV1TemplateName],
  ),
  quoteReady(
    code: 'quote_ready',
    title: 'Presupuesto listo',
    when: 'Al pasar a «Esperando aprobación»',
    templateName: WhatsAppService.workshopQuotePdfTemplateName,
    fallbackTemplateNames: [
      WhatsAppService.workshopQuoteReadyTemplateName,
      WhatsAppService.workshopQuoteReadyV1TemplateName,
      'seguimiento_presupuesto_bicicleta',
    ],
    ownTemplateNames: [
      WhatsAppService.workshopQuotePdfTemplateName,
      WhatsAppService.workshopQuoteReadyTemplateName,
    ],
  ),
  ready(
    code: 'ready',
    title: 'Lista para retirar',
    when: 'Al terminar el trabajo, si no la retiran en 10 minutos',
    templateName: WhatsAppService.workshopReadyTemplateName,
    fallbackTemplateNames: [
      WhatsAppService.workshopReadyV2TemplateName,
      WhatsAppService.workshopReadyV1TemplateName,
      'bicicleta_lista_retiro',
    ],
  ),
  delivered(
    code: 'delivered',
    title: 'Entregada',
    when: 'Al entregarla, con el comprobante y la garantía',
    templateName: WhatsAppService.workshopDeliveredPdfTemplateName,
    fallbackTemplateNames: [
      WhatsAppService.workshopDeliveredTemplateName,
      WhatsAppService.workshopDeliveredV1TemplateName,
    ],
    ownTemplateNames: [
      WhatsAppService.workshopDeliveredPdfTemplateName,
      WhatsAppService.workshopDeliveredTemplateName,
    ],
  );

  const WorkshopNoticeKind({
    required this.code,
    required this.title,
    required this.when,
    required this.templateName,
    this.fallbackTemplateNames = const [],
    this.ownTemplateNames,
  });

  final String code;
  final String title;
  final String when;

  /// La plantilla con título, pie y botón (20261107120000).
  final String templateName;

  /// Las ya aprobadas con que sale mientras Meta revisa [templateName], en
  /// el orden en que la base las prefiere.
  final List<String> fallbackTemplateNames;

  final List<String>? ownTemplateNames;

  /// Las que crea «Crear plantillas en Meta»: la mejor y, cuando esa lleva
  /// PDF, también la de botón con que sale un trabajo que no puede llevarlo.
  List<String> get createdTemplateNames => ownTemplateNames ?? [templateName];

  static WorkshopNoticeKind? fromCode(String? code) {
    for (final kind in values) {
      if (kind.code == code) return kind;
    }
    return null;
  }
}

enum WorkshopNoticeChannel {
  email('email', 'Correo'),
  whatsapp('whatsapp', 'WhatsApp');

  const WorkshopNoticeChannel(this.code, this.label);

  final String code;
  final String label;

  static WorkshopNoticeChannel? fromCode(String? code) {
    for (final channel in values) {
      if (channel.code == code) return channel;
    }
    return null;
  }
}

/// Lo que pasó con los avisos de un momento por un canal en 30 días.
class WorkshopNoticeTally {
  const WorkshopNoticeTally({
    this.sent = 0,
    this.waiting = 0,
    this.failed = 0,
    this.skipped = const {},
  });

  final int sent;
  final int waiting;
  final int failed;

  /// Omitidos, por motivo.
  final Map<String, int> skipped;

  int get skippedTotal => skipped.values.fold(0, (sum, count) => sum + count);

  WorkshopNoticeTally add(String state, String? reason, int count) {
    switch (state) {
      case 'sent':
        return WorkshopNoticeTally(
            sent: sent + count,
            waiting: waiting,
            failed: failed,
            skipped: skipped);
      case 'pending':
      case 'sending':
        return WorkshopNoticeTally(
            sent: sent,
            waiting: waiting + count,
            failed: failed,
            skipped: skipped);
      case 'failed':
        return WorkshopNoticeTally(
            sent: sent,
            waiting: waiting,
            failed: failed + count,
            skipped: skipped);
      default:
        final key = reason ?? 'skipped';
        return WorkshopNoticeTally(
          sent: sent,
          waiting: waiting,
          failed: failed,
          skipped: {...skipped, key: (skipped[key] ?? 0) + count},
        );
    }
  }
}

/// La plantilla con que sale hoy un aviso por WhatsApp.
enum WorkshopNoticeTemplateState {
  /// La del taller, aprobada.
  approved,

  /// La del taller está en revisión y sale con la aprobada de antes.
  fallback,

  /// En revisión de Meta y sin una anterior: espera.
  pending,

  /// Meta la rechazó.
  rejected,

  /// Meta la rechazó y sale con la aprobada de antes.
  rejectedFallback,

  /// Todavía no existe en Meta.
  missing,

  /// Todavía no existe en Meta y sale con la aprobada de antes.
  missingFallback,

  /// Meta la dejó como publicidad (MARKETING) y un aviso no sale con ella
  /// (20261107140000): sin una anterior, el aviso espera.
  marketing,

  /// Meta la dejó como publicidad y sale con la aprobada de antes.
  marketingFallback,

  /// No se pudo preguntar a Meta.
  unknown,
}

class WorkshopNoticeOverview {
  const WorkshopNoticeOverview({
    required this.startedAt,
    required this.canEdit,
    required this.emailSwitch,
    required this.whatsappSwitch,
    required this.emailReady,
    required this.whatsappReady,
    required this.tallies,
    required this.lastSentAt,
    required this.templates,
    required this.templateCheckFailed,
    required this.serviceWarrantyDays,
    required this.partsWarrantyMonths,
  });

  factory WorkshopNoticeOverview.fromMap(
    Map<String, dynamic> data, {
    required bool templateCheckFailed,
  }) {
    final tallies =
        <(WorkshopNoticeKind, WorkshopNoticeChannel), WorkshopNoticeTally>{};
    for (final raw in data['counts'] as List? ?? const []) {
      if (raw is! Map) continue;
      final kind = WorkshopNoticeKind.fromCode(raw['kind']?.toString());
      final channel =
          WorkshopNoticeChannel.fromCode(raw['channel']?.toString());
      if (kind == null || channel == null) continue;
      final key = (kind, channel);
      tallies[key] = (tallies[key] ?? const WorkshopNoticeTally()).add(
        raw['state']?.toString() ?? '',
        raw['reason']?.toString(),
        (raw['count'] as num?)?.toInt() ?? 0,
      );
    }
    final templates = <String, WhatsAppTemplateReviewStatus>{};
    for (final raw in data['templates'] as List? ?? const []) {
      if (raw is! Map) continue;
      final name = raw['name']?.toString();
      if (name == null || name.isEmpty) continue;
      templates[name] = WhatsAppTemplateReviewStatus.fromMap(raw);
    }
    final warranty = data['warranty'] is Map
        ? Map<String, dynamic>.from(data['warranty'] as Map)
        : const <String, dynamic>{};
    return WorkshopNoticeOverview(
      startedAt: DateTime.tryParse('${data['started_at'] ?? ''}')?.toLocal(),
      canEdit: data['can_edit'] == true,
      emailSwitch: data['email_switch'] != false,
      whatsappSwitch: data['whatsapp_switch'] != false,
      emailReady: data['email_ready'] == true,
      whatsappReady: data['whatsapp_ready'] == true,
      tallies: tallies,
      lastSentAt: DateTime.tryParse('${data['last_sent_at'] ?? ''}')?.toLocal(),
      templates: templates,
      templateCheckFailed: templateCheckFailed,
      serviceWarrantyDays: (warranty['service_days'] as num?)?.toInt() ?? 14,
      partsWarrantyMonths: (warranty['parts_months'] as num?)?.toInt() ?? 2,
    );
  }

  final DateTime? startedAt;
  final bool canEdit;
  final bool emailSwitch;
  final bool whatsappSwitch;

  /// La tienda tiene el remitente de correo listo.
  final bool emailReady;

  /// La tienda tiene un número de WhatsApp activo.
  final bool whatsappReady;
  final Map<(WorkshopNoticeKind, WorkshopNoticeChannel), WorkshopNoticeTally>
      tallies;
  final DateTime? lastSentAt;
  final Map<String, WhatsAppTemplateReviewStatus> templates;
  final bool templateCheckFailed;
  final int serviceWarrantyDays;
  final int partsWarrantyMonths;

  bool get emailOn => emailSwitch && emailReady;
  bool get whatsappOn => whatsappSwitch && whatsappReady;

  WorkshopNoticeTally tally(
          WorkshopNoticeKind kind, WorkshopNoticeChannel channel) =>
      tallies[(kind, channel)] ?? const WorkshopNoticeTally();

  int get sentTotal => tallies.values.fold(0, (sum, tally) => sum + tally.sent);

  /// Una plantilla con que un aviso puede salir: aprobada y de servicio,
  /// como la elige la base (`workshop_notice_template_usable_internal`,
  /// 20261107140000). Meta dejó `taller_lista_v2` como MARKETING al crearla;
  /// una revisión sin categoría sigue valiendo.
  static bool _usable(WhatsAppTemplateReviewStatus? review) =>
      review != null && review.isApproved && !_notUtility(review);

  static bool _notUtility(WhatsAppTemplateReviewStatus review) =>
      review.category != null && review.category != 'UTILITY';

  WorkshopNoticeTemplateState templateState(WorkshopNoticeKind kind) {
    final own = templates[kind.templateName];
    if (_usable(own)) return WorkshopNoticeTemplateState.approved;
    // Una anterior aprobada cubre el aviso, pero no dice nada de la nueva:
    // falta, está en revisión o la rechazaron (2026-11-07, al llegar las
    // `_v2` todas faltaban y la tarjeta las daba «en revisión»).
    final covered =
        kind.fallbackTemplateNames.any((name) => _usable(templates[name]));
    if (own == null) {
      if (templateCheckFailed) return WorkshopNoticeTemplateState.unknown;
      return covered
          ? WorkshopNoticeTemplateState.missingFallback
          : WorkshopNoticeTemplateState.missing;
    }
    if (own.status == 'REJECTED') {
      return covered
          ? WorkshopNoticeTemplateState.rejectedFallback
          : WorkshopNoticeTemplateState.rejected;
    }
    if (_notUtility(own)) {
      return covered
          ? WorkshopNoticeTemplateState.marketingFallback
          : WorkshopNoticeTemplateState.marketing;
    }
    return covered
        ? WorkshopNoticeTemplateState.fallback
        : WorkshopNoticeTemplateState.pending;
  }

  /// Las plantillas del taller que todavía no existen en Meta.
  List<String> get missingTemplates => [
        if (!templateCheckFailed)
          for (final kind in WorkshopNoticeKind.values)
            for (final name in kind.createdTemplateNames)
              if (!templates.containsKey(name)) name,
      ];
}

/// Un aviso enviado u omitido, para la lista de lo último.
class WorkshopNoticeRecord {
  const WorkshopNoticeRecord({
    required this.id,
    required this.jobId,
    required this.kind,
    required this.channel,
    required this.state,
    required this.reason,
    required this.createdAt,
    required this.sentAt,
    this.jobNumber,
    this.customerName,
  });

  final String id;
  final String jobId;
  final WorkshopNoticeKind kind;
  final WorkshopNoticeChannel channel;
  final String state;
  final String? reason;
  final DateTime createdAt;
  final DateTime? sentAt;
  final String? jobNumber;
  final String? customerName;

  WorkshopNoticeRecord withJob(String? number, String? customer) =>
      WorkshopNoticeRecord(
        id: id,
        jobId: jobId,
        kind: kind,
        channel: channel,
        state: state,
        reason: reason,
        createdAt: createdAt,
        sentAt: sentAt,
        jobNumber: number,
        customerName: customer,
      );
}

/// Avisos del taller al cliente y garantía del taller (Taller › Avisos y
/// garantía): qué se manda, por dónde, cómo van las plantillas en Meta y lo
/// que el taller garantiza en cada entrega.
class WorkshopCustomerNoticeService {
  WorkshopCustomerNoticeService({
    SupabaseClient? client,
    WhatsAppService? whatsApp,
    Future<String?> Function()? tenantId,
  })  : _client = client,
        _whatsApp = whatsApp,
        _tenantId = tenantId;

  final SupabaseClient? _client;
  final WhatsAppService? _whatsApp;
  final Future<String?> Function()? _tenantId;

  SupabaseClient get _supabase => _client ?? Supabase.instance.client;
  WhatsAppService get _templates => _whatsApp ?? WhatsAppService();

  static const serviceDaysRange = (min: 0, max: 365);
  static const partsMonthsRange = (min: 0, max: 24);

  /// El motivo de un aviso omitido, dicho al equipo.
  static String reasonLabel(String? reason) {
    final code = reason ?? '';
    if (code.startsWith('send_')) return 'No salió';
    return switch (code) {
      'no_email' => 'Sin correo',
      'no_mobile' => 'Sin celular',
      'customer_opted_out' => 'El cliente lo apagó',
      'job_moved_on' => 'El trabajo ya avanzó',
      'already_delivered' => 'Ya la retiraron',
      'template_not_approved' => 'Sin plantilla aprobada',
      'expired' => 'Venció sin salir',
      'channel_off' => 'Canal apagado',
      'no_customer' => 'Sin cliente',
      'job_deleted' => 'Trabajo archivado',
      'no_actor' => 'Sin quién lo mande',
      'no_channel' => 'Sin número de WhatsApp',
      'no_store_url' => 'Sin dirección de la tienda',
      'no_warranty' => 'Sin garantía registrada',
      'sender_not_enabled' => 'Correo sin remitente',
      _ => 'Omitido',
    };
  }

  Future<WorkshopNoticeOverview> load({bool refreshTemplates = true}) async {
    final tenantId = await _requireTenantId();
    var templateCheckFailed = false;
    if (refreshTemplates) {
      // Listar en Meta deja el estado de cada plantilla en la base, que es lo
      // que lee la pasada de los avisos.
      try {
        await _templates.getSupplierTemplateReviewStatuses();
      } catch (error) {
        debugPrint('[WorkshopNotices] estado de las plantillas: $error');
        templateCheckFailed = true;
      }
    }
    final data = await _supabase.rpc(
      'workshop_customer_notice_overview_v1',
      params: {'p_tenant_id': tenantId},
    );
    return WorkshopNoticeOverview.fromMap(
      data is Map ? Map<String, dynamic>.from(data) : const {},
      templateCheckFailed: templateCheckFailed,
    );
  }

  Future<List<WorkshopNoticeRecord>> recent({int limit = 12}) async {
    final tenantId = await _requireTenantId();
    final rows = await _supabase
        .from('workshop_customer_notices')
        .select('id, job_id, customer_id, kind, channel, state, reason, '
            'created_at, sent_at')
        .eq('tenant_id', tenantId)
        .order('created_at', ascending: false)
        .limit(limit);
    final records = <WorkshopNoticeRecord>[];
    final customerIds = <String>{};
    final customerOf = <String, String>{};
    for (final row in (rows as List).whereType<Map>()) {
      final kind = WorkshopNoticeKind.fromCode(row['kind']?.toString());
      final channel =
          WorkshopNoticeChannel.fromCode(row['channel']?.toString());
      final createdAt = DateTime.tryParse('${row['created_at'] ?? ''}');
      if (kind == null || channel == null || createdAt == null) continue;
      final customerId = row['customer_id']?.toString();
      if (customerId != null) {
        customerIds.add(customerId);
        customerOf[row['id'].toString()] = customerId;
      }
      records.add(WorkshopNoticeRecord(
        id: row['id'].toString(),
        jobId: row['job_id'].toString(),
        kind: kind,
        channel: channel,
        state: row['state']?.toString() ?? '',
        reason: row['reason']?.toString(),
        createdAt: createdAt.toLocal(),
        sentAt: DateTime.tryParse('${row['sent_at'] ?? ''}')?.toLocal(),
      ));
    }
    if (records.isEmpty) return records;

    final jobIds = {for (final record in records) record.jobId}.toList();
    final jobs = await _supabase
        .from('mechanic_jobs')
        .select('id, job_number')
        .eq('tenant_id', tenantId)
        .inFilter('id', jobIds);
    final numbers = {
      for (final row in (jobs as List).whereType<Map>())
        row['id'].toString(): row['job_number']?.toString(),
    };
    final names = <String, String?>{};
    if (customerIds.isNotEmpty) {
      final customers = await _supabase
          .from('customers')
          .select('id, name')
          .eq('tenant_id', tenantId)
          .inFilter('id', customerIds.toList());
      for (final row in (customers as List).whereType<Map>()) {
        names[row['id'].toString()] = row['name']?.toString();
      }
    }
    return [
      for (final record in records)
        record.withJob(
          numbers[record.jobId],
          names[customerOf[record.id]],
        ),
    ];
  }

  Future<WorkshopNoticeOverview> update({
    bool? emailEnabled,
    bool? whatsappEnabled,
    int? serviceWarrantyDays,
    int? partsWarrantyMonths,
  }) async {
    final tenantId = await _requireTenantId();
    final data = await _supabase.rpc(
      'update_workshop_customer_notice_settings_v1',
      params: {
        'p_tenant_id': tenantId,
        'p_settings': {
          if (emailEnabled != null) 'email_enabled': emailEnabled,
          if (whatsappEnabled != null) 'whatsapp_enabled': whatsappEnabled,
          if (serviceWarrantyDays != null)
            'service_warranty_days': serviceWarrantyDays,
          if (partsWarrantyMonths != null)
            'parts_warranty_months': partsWarrantyMonths,
        },
      },
    );
    return WorkshopNoticeOverview.fromMap(
      data is Map ? Map<String, dynamic>.from(data) : const {},
      templateCheckFailed: false,
    );
  }

  /// Manda a revisión de Meta las plantillas que faltan, una por una.
  /// Devuelve cuántas quedaron creadas.
  Future<int> createTemplates(Iterable<String> names) async {
    var created = 0;
    Object? lastError;
    for (final name in names) {
      try {
        await _templates.createTemplateInMeta(name);
        created++;
      } catch (error) {
        lastError = error;
      }
    }
    if (created == 0 && lastError != null) throw lastError;
    return created;
  }

  /// El error de la base dicho al equipo.
  static String describeError(Object error) {
    if (error is PostgrestException) {
      if (error.code == '42501') {
        return 'Sólo administración puede cambiar esto.';
      }
      if (error.code == '22023') return 'Revisa los valores.';
    }
    if (error is StateError) return error.message;
    return 'No se pudo guardar. Vuelve a intentarlo.';
  }

  Future<String> _requireTenantId() async {
    final tenantId = await (_tenantId?.call() ?? TenantService().getTenantId());
    if (tenantId == null || tenantId.isEmpty) {
      throw StateError('No hay una tienda activa en la sesión.');
    }
    return tenantId;
  }
}
