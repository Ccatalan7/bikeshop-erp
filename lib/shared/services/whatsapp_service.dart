import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import '../../modules/sales/models/sales_models.dart';
import '../../modules/bikeshop/models/bikeshop_models.dart';
import '../services/tenant_service.dart';
import '../widgets/whatsapp_web_viewer.dart';

enum WhatsAppDeliveryMethod {
  cloudApi,
  manualFallback,
  failed,
}

enum WhatsAppTemplatePurpose {
  firstContact,
  jobUpdate,
  readyForPickup,
  quoteFollowUp,
}

class WhatsAppTemplateOption {
  final WhatsAppTemplatePurpose purpose;
  final String key;
  final String label;
  final String description;
  final String defaultTemplateName;
  final String defaultLanguage;
  final String templateNameSettingKey;
  final String templateLanguageSettingKey;
  final IconData icon;

  const WhatsAppTemplateOption({
    required this.purpose,
    required this.key,
    required this.label,
    required this.description,
    required this.defaultTemplateName,
    required this.defaultLanguage,
    required this.templateNameSettingKey,
    required this.templateLanguageSettingKey,
    required this.icon,
  });
}

/// WhatsApp messaging service for customer communication
/// Sends through WhatsApp Cloud API and falls back to manual WhatsApp Web if needed.
class WhatsAppService {
  static final WhatsAppService _instance = WhatsAppService._internal();
  static const String firstContactTemplateName =
      'seguimiento_servicio_bicicleta';
  static const String firstContactTemplateLanguage = 'es_CL';
  static const String firstContactTemplateNameSettingKey =
      'whatsapp_first_contact_template_name';
  static const String firstContactTemplateLanguageSettingKey =
      'whatsapp_first_contact_template_language';
  static const List<WhatsAppTemplateOption> templateOptions = [
    WhatsAppTemplateOption(
      purpose: WhatsAppTemplatePurpose.firstContact,
      key: 'first_contact',
      label: 'Primer contacto',
      description: 'Abre una conversación nueva con el cliente.',
      defaultTemplateName: firstContactTemplateName,
      defaultLanguage: firstContactTemplateLanguage,
      templateNameSettingKey: firstContactTemplateNameSettingKey,
      templateLanguageSettingKey: firstContactTemplateLanguageSettingKey,
      icon: Icons.waving_hand_outlined,
    ),
    WhatsAppTemplateOption(
      purpose: WhatsAppTemplatePurpose.jobUpdate,
      key: 'job_update',
      label: 'Actualización de taller',
      description: 'Reabre una conversación por una actualización del trabajo.',
      defaultTemplateName: 'actualizacion_servicio_bicicleta',
      defaultLanguage: firstContactTemplateLanguage,
      templateNameSettingKey: 'whatsapp_job_update_template_name',
      templateLanguageSettingKey: 'whatsapp_job_update_template_language',
      icon: Icons.build_outlined,
    ),
    WhatsAppTemplateOption(
      purpose: WhatsAppTemplatePurpose.readyForPickup,
      key: 'ready_for_pickup',
      label: 'Lista para retiro',
      description: 'Avisa que la bicicleta está lista o requiere coordinación.',
      defaultTemplateName: 'bicicleta_lista_retiro',
      defaultLanguage: firstContactTemplateLanguage,
      templateNameSettingKey: 'whatsapp_ready_pickup_template_name',
      templateLanguageSettingKey: 'whatsapp_ready_pickup_template_language',
      icon: Icons.task_alt_outlined,
    ),
    WhatsAppTemplateOption(
      purpose: WhatsAppTemplatePurpose.quoteFollowUp,
      key: 'quote_follow_up',
      label: 'Presupuesto / aprobación',
      description: 'Pide respuesta sobre presupuesto, aprobación o pendiente.',
      defaultTemplateName: 'seguimiento_presupuesto_bicicleta',
      defaultLanguage: firstContactTemplateLanguage,
      templateNameSettingKey: 'whatsapp_quote_follow_up_template_name',
      templateLanguageSettingKey: 'whatsapp_quote_follow_up_template_language',
      icon: Icons.request_quote_outlined,
    ),
  ];
  static const int _reengagementErrorCode = 131047;
  static const int _expiredAccessTokenErrorCode = 190;

  factory WhatsAppService() => _instance;
  WhatsAppService._internal();

  final SupabaseClient _client = Supabase.instance.client;

  final _currencyFormat = NumberFormat.currency(
    symbol: '\$',
    decimalDigits: 0,
    locale: 'es_CL',
  );

  final _dateFormat = DateFormat('dd/MM/yyyy', 'es_CL');

  WhatsAppDeliveryMethod _lastDeliveryMethod = WhatsAppDeliveryMethod.failed;
  int? _lastErrorCode;
  bool _lastUsedFirstContactTemplate = false;
  String? _lastResolvedMessageText;
  String? _lastExternalMessageId;

  WhatsAppDeliveryMethod get lastDeliveryMethod => _lastDeliveryMethod;
  int? get lastErrorCode => _lastErrorCode;
  bool get lastUsedFirstContactTemplate => _lastUsedFirstContactTemplate;
  String? get lastResolvedMessageText => _lastResolvedMessageText;
  String? get lastExternalMessageId => _lastExternalMessageId;

  bool get lastErrorRequiresServerFix =>
      _lastErrorCode == _expiredAccessTokenErrorCode;
  bool get lastErrorRequiresCustomerReply =>
      _lastErrorCode == _reengagementErrorCode;

  /// Format Chilean phone number (remove spaces, dashes, +56 prefix)
  String _formatPhoneNumber(String phone) {
    String cleaned = phone.replaceAll(RegExp(r'[^0-9]'), '');

    if (cleaned.startsWith('56') && cleaned.length > 9) {
      cleaned = cleaned.substring(2);
    }

    if (!cleaned.startsWith('9')) {
      cleaned = '9$cleaned';
    }

    return '56$cleaned';
  }

  Future<String> _resolveBusinessName() async {
    try {
      final tenant = await TenantService().getCurrentTenant();
      final shopName = tenant?['shop_name']?.toString().trim();
      if (shopName != null && shopName.isNotEmpty) {
        return shopName;
      }
    } catch (error) {
      debugPrint('⚠️ [WhatsAppService] Could not resolve tenant name: $error');
    }

    return 'Viñabike';
  }

  String _buildFirstContactTemplateText({
    required String customerName,
    required String businessName,
  }) {
    return 'Hola $customerName, buen día. Soy parte del equipo de $businessName y te escribo por el servicio de tu bicicleta.';
  }

  String buildTemplatePreviewText({
    required WhatsAppTemplateOption option,
    required String customerName,
    required String businessName,
  }) {
    return switch (option.purpose) {
      WhatsAppTemplatePurpose.firstContact => _buildFirstContactTemplateText(
          customerName: customerName,
          businessName: businessName,
        ),
      WhatsAppTemplatePurpose.jobUpdate =>
        'Hola $customerName, tenemos una actualización sobre tu bicicleta en $businessName. Responde este mensaje para continuar la conversación.',
      WhatsAppTemplatePurpose.readyForPickup =>
        'Hola $customerName, tu bicicleta está lista para retiro en $businessName. Responde este mensaje si necesitas coordinar algo.',
      WhatsAppTemplatePurpose.quoteFollowUp =>
        'Hola $customerName, necesitamos tu respuesta sobre un presupuesto o aprobación pendiente en $businessName. Responde este mensaje para continuar.',
    };
  }

  void _resetLastAttemptState({String? resolvedMessageText}) {
    _lastErrorCode = null;
    _lastUsedFirstContactTemplate = false;
    _lastResolvedMessageText = resolvedMessageText;
    _lastExternalMessageId = null;
  }

  String? _extractExternalMessageId(dynamic data) {
    if (data is! Map<String, dynamic>) {
      return null;
    }

    final directId = data['external_message_id']?.toString().trim();
    if (directId != null && directId.isNotEmpty) {
      return directId;
    }

    final graphResult = data['graph_result'];
    if (graphResult is Map<String, dynamic>) {
      final messages = graphResult['messages'];
      if (messages is List && messages.isNotEmpty) {
        final firstMessage = messages.first;
        if (firstMessage is Map<String, dynamic>) {
          final id = firstMessage['id']?.toString().trim();
          if (id != null && id.isNotEmpty) {
            return id;
          }
        }
      }
    }

    return null;
  }

  int? _extractErrorCode(dynamic data) {
    if (data is Map<String, dynamic>) {
      final directDetails = data['details'];
      if (directDetails is Map<String, dynamic>) {
        final error = directDetails['error'];
        if (error is Map<String, dynamic>) {
          final code = error['code'];
          if (code is num) {
            return code.toInt();
          }
        }
      }

      final errors = data['errors'];
      if (errors is List && errors.isNotEmpty) {
        final first = errors.first;
        if (first is Map<String, dynamic>) {
          final code = first['code'];
          if (code is num) {
            return code.toInt();
          }
        }
      }
    }

    return null;
  }

  bool _shouldSkipManualFallback() {
    return _lastErrorCode == _expiredAccessTokenErrorCode;
  }

  bool _isCustomerServiceWindowOpen(DateTime? lastInboundAt) {
    if (lastInboundAt == null) {
      return false;
    }

    return DateTime.now().toUtc().difference(lastInboundAt.toUtc()) <
        const Duration(hours: 24);
  }

  Future<({String templateName, String templateLanguage})>
      _loadFirstContactTemplateSettings() async {
    return _loadTemplateSettings(templateOptions.first);
  }

  Future<({String templateName, String templateLanguage})>
      _loadTemplateSettings(WhatsAppTemplateOption option) async {
    try {
      final tenantId = await TenantService().getTenantId();
      if (tenantId == null || tenantId.isEmpty) {
        return (
          templateName: option.defaultTemplateName,
          templateLanguage: option.defaultLanguage,
        );
      }

      final rows = await _client
          .from('company_settings')
          .select('key, value')
          .eq('tenant_id', tenantId)
          .inFilter('key', [
        option.templateNameSettingKey,
        option.templateLanguageSettingKey,
      ]);

      String templateName = option.defaultTemplateName;
      String templateLanguage = option.defaultLanguage;

      for (final row in rows) {
        final key = row['key']?.toString();
        final value = row['value']?.toString().trim();
        if (value == null || value.isEmpty) {
          continue;
        }

        if (key == option.templateNameSettingKey) {
          templateName = value;
        } else if (key == option.templateLanguageSettingKey) {
          templateLanguage = value;
        }
      }

      return (
        templateName: templateName,
        templateLanguage: templateLanguage,
      );
    } catch (error) {
      debugPrint(
        '⚠️ [WhatsAppService] Falling back to default WhatsApp template settings: $error',
      );
      return (
        templateName: option.defaultTemplateName,
        templateLanguage: option.defaultLanguage,
      );
    }
  }

  Future<bool> _sendViaCloud(Map<String, dynamic> body) async {
    final stopwatch = Stopwatch()..start();
    final metadata = body['metadata'];
    final clientMessageId =
        metadata is Map ? metadata['client_message_id']?.toString() : null;
    debugPrint(
      '⏱️ [WhatsAppService] cloud_invoke_start type=${body['type']} conversation=${body['conversationId']} client=$clientMessageId',
    );

    try {
      final response = await _client.functions.invoke(
        'whatsapp-send',
        body: body,
      );
      stopwatch.stop();

      final status = response.status;
      if (status >= 200 && status < 300) {
        _lastErrorCode = null;
        _lastDeliveryMethod = WhatsAppDeliveryMethod.cloudApi;
        _lastExternalMessageId = _extractExternalMessageId(response.data);
        debugPrint(
          '✅ [WhatsAppService] cloud_invoke_done status=$status elapsed=${stopwatch.elapsedMilliseconds}ms client=$clientMessageId external=$_lastExternalMessageId',
        );
        return true;
      }

      _lastErrorCode = _extractErrorCode(response.data);

      debugPrint(
        '❌ [WhatsAppService] cloud_invoke_failed status=$status elapsed=${stopwatch.elapsedMilliseconds}ms client=$clientMessageId error=$_lastErrorCode data=${response.data}',
      );
    } catch (error) {
      stopwatch.stop();
      _lastErrorCode = null;
      debugPrint(
        '❌ [WhatsAppService] cloud_invoke_error elapsed=${stopwatch.elapsedMilliseconds}ms client=$clientMessageId error=$error',
      );
    }

    return false;
  }

  Future<bool> _sendWithFallback({
    required BuildContext context,
    required String phoneNumber,
    required String message,
    required Map<String, dynamic> cloudBody,
    bool allowManualFallback = true,
  }) async {
    if (await _sendViaCloud(cloudBody)) {
      return true;
    }

    if (!allowManualFallback || _shouldSkipManualFallback()) {
      _lastDeliveryMethod = WhatsAppDeliveryMethod.failed;
      return false;
    }

    final opened = await _openWhatsApp(context, phoneNumber, message);
    _lastDeliveryMethod = opened
        ? WhatsAppDeliveryMethod.manualFallback
        : WhatsAppDeliveryMethod.failed;
    return opened;
  }

  /// Open WhatsApp with pre-filled message
  /// On desktop: Opens WhatsApp Web in WebView
  /// On mobile: Opens WhatsApp app
  Future<bool> _openWhatsApp(
    BuildContext context,
    String phoneNumber,
    String message,
  ) async {
    try {
      final formattedPhone = _formatPhoneNumber(phoneNumber);
      final encodedMessage = Uri.encodeComponent(message);
      final uri = Uri.parse(
        'https://wa.me/$formattedPhone?text=$encodedMessage',
      );

      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.macOS) {
        if (await canLaunchUrl(uri)) {
          return await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      }

      // Open WhatsApp Web in WebView (desktop) or app (mobile)
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => WhatsAppWebViewer(
            phoneNumber: formattedPhone,
            message: message,
          ),
        ),
      );

      return true;
    } catch (e) {
      debugPrint('❌ [WhatsAppService] Error opening WhatsApp WebView: $e');
      try {
        final formattedPhone = _formatPhoneNumber(phoneNumber);
        final encodedMessage = Uri.encodeComponent(message);
        final url = 'https://wa.me/$formattedPhone?text=$encodedMessage';

        final uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) {
          return await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      } catch (fallbackError) {
        debugPrint('❌ [WhatsAppService] Fallback launch error: $fallbackError');
      }
      return false;
    }
  }

  /// Send invoice via WhatsApp
  Future<bool> sendInvoice({
    required BuildContext context,
    required String customerPhone,
    required String customerName,
    required Invoice invoice,
  }) async {
    final message = '''
Hola $customerName! 👋

Aquí está tu presupuesto de Viña Bike:

*Factura N° ${invoice.invoiceNumber}*
Fecha: ${_dateFormat.format(invoice.date)}

📦 *Productos/Servicios:*
${invoice.items.map((item) => '• ${item.productName ?? item.description}\n  Cantidad: ${item.quantity} × ${_currencyFormat.format(item.unitPrice)}\n  Subtotal: ${_currencyFormat.format(item.lineTotal)}').join('\n\n')}

💰 *Resumen:*
Subtotal: ${_currencyFormat.format(invoice.subtotal)}
${invoice.total - invoice.subtotal - invoice.ivaAmount > 0 ? 'Descuento: -${_currencyFormat.format(invoice.total - invoice.subtotal - invoice.ivaAmount)}\n' : ''}IVA (19%): ${_currencyFormat.format(invoice.ivaAmount)}
━━━━━━━━━━━━━━━
*TOTAL: ${_currencyFormat.format(invoice.total)}*

Por favor confirma para proceder con el trabajo. 🔧

¿Alguna duda? ¡Escríbenos! 📞
    ''';

    return _sendWithFallback(
      context: context,
      phoneNumber: customerPhone,
      message: message,
      cloudBody: {
        'phoneNumber': _formatPhoneNumber(customerPhone),
        'contactName': customerName,
        'contextType': 'invoice',
        'contextId': invoice.id,
        'type': 'text',
        'text': message,
        'metadata': {
          'source': 'flutter_erp',
          'invoiceId': invoice.id,
          'invoiceNumber': invoice.invoiceNumber,
        },
      },
    );
  }

  /// Send payment confirmation receipt
  Future<bool> sendPaymentReceipt({
    required BuildContext context,
    required String customerPhone,
    required String customerName,
    required Payment payment,
    required Invoice invoice,
    required String paymentMethodName,
  }) async {
    final message = '''
Hola $customerName! 👋

✅ *Pago Recibido - Viña Bike*

*Factura N° ${invoice.invoiceNumber}*
Fecha de pago: ${_dateFormat.format(payment.date)}

💵 *Detalles del Pago:*
Monto pagado: ${_currencyFormat.format(payment.amount)}
Método: $paymentMethodName
${payment.reference != null && payment.reference!.isNotEmpty ? 'Referencia: ${payment.reference}\n' : ''}
━━━━━━━━━━━━━━━

📊 *Estado de la Factura:*
Total factura: ${_currencyFormat.format(invoice.total)}
${invoice.paidAmount > 0 ? 'Pagado anteriormente: ${_currencyFormat.format(invoice.paidAmount - payment.amount)}\n' : ''}Pago actual: ${_currencyFormat.format(payment.amount)}
*Saldo restante: ${_currencyFormat.format(invoice.balance)}*

${invoice.balance <= 0 ? '🎉 ¡Factura pagada completamente!' : '⚠️ Saldo pendiente: ${_currencyFormat.format(invoice.balance)}'}

¡Gracias por tu confianza! 🚴‍♂️
    ''';

    return _sendWithFallback(
      context: context,
      phoneNumber: customerPhone,
      message: message,
      cloudBody: {
        'phoneNumber': _formatPhoneNumber(customerPhone),
        'contactName': customerName,
        'contextType': 'invoice',
        'contextId': invoice.id,
        'type': 'text',
        'text': message,
        'metadata': {
          'source': 'flutter_erp',
          'invoiceId': invoice.id,
          'invoiceNumber': invoice.invoiceNumber,
          'paymentId': payment.id,
        },
      },
    );
  }

  /// Send mechanic job status update
  Future<bool> sendJobStatusUpdate({
    required BuildContext context,
    required String customerPhone,
    required String customerName,
    required MechanicJob job,
    required String bikeBrand,
    required String? bikeModel,
  }) async {
    final statusEmoji = _getStatusEmoji(job.status);
    final statusText = job.status.displayName;

    final message = '''
Hola $customerName! 👋

$statusEmoji *Actualización de tu bicicleta*

🚴 Bici: $bikeBrand${bikeModel != null ? ' $bikeModel' : ''}
📋 Trabajo: ${job.clientRequest ?? job.diagnosis ?? 'Servicio'}
📅 Estado: *$statusText*

${_getStatusMessage(job.status)}

${job.deliveryDeadline != null ? '⏰ Fecha estimada: ${_dateFormat.format(job.deliveryDeadline!)}\n' : ''}${job.notes != null && job.notes!.isNotEmpty ? '📝 Notas: ${job.notes}\n' : ''}
¿Alguna duda? ¡Escríbenos! 📞

Viña Bike - Tu taller de confianza 🔧
    ''';

    return _sendWithFallback(
      context: context,
      phoneNumber: customerPhone,
      message: message,
      cloudBody: {
        'phoneNumber': _formatPhoneNumber(customerPhone),
        'contactName': customerName,
        'contextType': job.id != null ? 'job' : null,
        'contextId': job.id,
        'jobId': job.id,
        'type': 'text',
        'text': message,
        'metadata': {
          'source': 'flutter_erp',
          'jobId': job.id,
          'jobStatus': job.status.name,
        },
      },
    );
  }

  /// Send bike ready for pickup notification
  Future<bool> sendReadyForPickup({
    required BuildContext context,
    required String customerPhone,
    required String customerName,
    required MechanicJob job,
    required String bikeBrand,
    required String? bikeModel,
  }) async {
    final message = '''
Hola $customerName! 👋

🎉 *¡Tu bicicleta está lista!*

🚴 Bici: $bikeBrand${bikeModel != null ? ' $bikeModel' : ''}
📋 Trabajo realizado: ${job.clientRequest ?? job.diagnosis ?? 'Servicio'}

✅ El trabajo ha sido completado y tu bici está lista para retiro.

${job.invoiceId != null ? '💰 *Recuerda:* Debes pagar la factura antes de retirar.\n' : ''}
📍 *Ubicación:* Viña del Mar
⏰ *Horario:* Lunes a Viernes 9:00-18:00

🔧 *Garantía:* 1 semana de prueba incluida

¡Te esperamos! 🚴‍♂️

Viña Bike
    ''';

    return _sendWithFallback(
      context: context,
      phoneNumber: customerPhone,
      message: message,
      cloudBody: {
        'phoneNumber': _formatPhoneNumber(customerPhone),
        'contactName': customerName,
        'contextType': job.id != null ? 'job' : null,
        'contextId': job.id,
        'jobId': job.id,
        'type': 'interactive',
        'text': message,
        'caption': message,
        'actionType': 'confirm_delivery',
        'actionKind': 'job',
        'actionTargetId': job.id,
        'metadata': {
          'source': 'flutter_erp',
          'jobId': job.id,
          'jobStatus': job.status.name,
        },
      },
    );
  }

  /// Send generic message
  Future<bool> sendMessage({
    required BuildContext context,
    required String customerPhone,
    required String message,
    String? contactName,
    String? conversationId,
    String? contextType,
    String? contextId,
    DateTime? lastInboundAt,
    String? clientMessageId,
  }) async {
    _resetLastAttemptState(resolvedMessageText: message);

    final customerDisplayName =
        (contactName != null && contactName.trim().isNotEmpty)
            ? contactName.trim()
            : 'cliente';

    if (!_isCustomerServiceWindowOpen(lastInboundAt)) {
      return sendFirstContactTemplate(
        customerPhone: customerPhone,
        customerName: customerDisplayName,
        conversationId: conversationId,
        contextType: contextType,
        contextId: contextId,
        clientMessageId: clientMessageId,
      );
    }

    final cloudBody = {
      'conversationId': conversationId,
      'phoneNumber': _formatPhoneNumber(customerPhone),
      'contactName': contactName,
      'contextType': contextType,
      'contextId': contextId,
      'type': 'text',
      'text': message,
      'metadata': {
        'source': 'flutter_erp',
        if (clientMessageId != null) 'client_message_id': clientMessageId,
      },
    };

    if (await _sendViaCloud(cloudBody)) {
      return true;
    }

    if (_lastErrorCode == _reengagementErrorCode) {
      final templateSuccess = await sendFirstContactTemplate(
        customerPhone: customerPhone,
        customerName: customerDisplayName,
        conversationId: conversationId,
        contextType: contextType,
        contextId: contextId,
        clientMessageId: clientMessageId,
      );

      if (templateSuccess) {
        return true;
      }
    }

    if (_shouldSkipManualFallback()) {
      _lastDeliveryMethod = WhatsAppDeliveryMethod.failed;
      return false;
    }

    final opened = await _openWhatsApp(context, customerPhone, message);
    _lastDeliveryMethod = opened
        ? WhatsAppDeliveryMethod.manualFallback
        : WhatsAppDeliveryMethod.failed;
    return opened;
  }

  Future<bool> sendFirstContactTemplate({
    required String customerPhone,
    required String customerName,
    String? agentName,
    String? conversationId,
    String? contextType,
    String? contextId,
    String? clientMessageId,
  }) async {
    return sendTemplateMessage(
      option: templateOptions.first,
      customerPhone: customerPhone,
      customerName: customerName,
      agentName: agentName,
      conversationId: conversationId,
      contextType: contextType,
      contextId: contextId,
      clientMessageId: clientMessageId,
    );
  }

  Future<bool> sendTemplateMessage({
    required WhatsAppTemplateOption option,
    required String customerPhone,
    required String customerName,
    String? agentName,
    String? conversationId,
    String? contextType,
    String? contextId,
    String? clientMessageId,
  }) async {
    final templateSettings =
        option.purpose == WhatsAppTemplatePurpose.firstContact
            ? await _loadFirstContactTemplateSettings()
            : await _loadTemplateSettings(option);
    final businessName = await _resolveBusinessName();
    final resolvedSenderLabel =
        (agentName != null && agentName.trim().isNotEmpty)
            ? agentName.trim()
            : 'parte del equipo';
    final renderedMessage = buildTemplatePreviewText(
      option: option,
      customerName: customerName,
      businessName: businessName,
    );
    final secondParameter =
        option.purpose == WhatsAppTemplatePurpose.firstContact
            ? resolvedSenderLabel
            : businessName;

    _resetLastAttemptState(resolvedMessageText: renderedMessage);

    final success = await _sendViaCloud({
      'conversationId': conversationId,
      'phoneNumber': _formatPhoneNumber(customerPhone),
      'contactName': customerName,
      'contextType': contextType,
      'contextId': contextId,
      'type': 'template',
      'templateName': templateSettings.templateName,
      'templateLanguage': templateSettings.templateLanguage,
      'caption': renderedMessage,
      'templateComponents': [
        {
          'type': 'body',
          'parameters': [
            {
              'type': 'text',
              'text': customerName,
            },
            {
              'type': 'text',
              'text': secondParameter,
            },
          ],
        },
      ],
      'metadata': {
        'source': 'flutter_erp',
        if (clientMessageId != null) 'client_message_id': clientMessageId,
        'template_purpose': option.key,
        'template_name': templateSettings.templateName,
        'template_language': templateSettings.templateLanguage,
      },
    });

    if (success) {
      _lastUsedFirstContactTemplate = true;
    } else {
      _lastDeliveryMethod = WhatsAppDeliveryMethod.failed;
    }

    return success;
  }

  Future<bool> sendAttachment({
    required BuildContext context,
    required String customerPhone,
    required String mediaUrl,
    required String filename,
    required String messageType,
    String? caption,
    String? contactName,
    String? conversationId,
    String? customerId,
    String? contextType,
    String? contextId,
    String? clientMessageId,
    Map<String, dynamic>? metadata,
  }) async {
    final isImage = messageType == 'image';
    final resolvedCaption = caption?.trim();
    final contentType = metadata?['contentType']?.toString() ??
        metadata?['content_type']?.toString();
    final fallbackMessage = [
      if (resolvedCaption != null && resolvedCaption.isNotEmpty)
        resolvedCaption
      else
        'Te compartimos $filename:',
      mediaUrl,
    ].join('\n');

    _resetLastAttemptState(resolvedMessageText: mediaUrl);

    return _sendWithFallback(
      context: context,
      phoneNumber: customerPhone,
      message: fallbackMessage,
      allowManualFallback: false,
      cloudBody: {
        'conversationId': conversationId,
        'customerId': customerId,
        'phoneNumber': _formatPhoneNumber(customerPhone),
        'contactName': contactName,
        'contextType': contextType,
        'contextId': contextId,
        'type': isImage ? 'image' : 'document',
        if (isImage) 'mediaUrl': mediaUrl,
        if (!isImage) 'documentUrl': mediaUrl,
        if (!isImage) 'documentFilename': filename,
        if (contentType != null && contentType.isNotEmpty)
          'contentType': contentType,
        if (resolvedCaption != null && resolvedCaption.isNotEmpty)
          'caption': resolvedCaption,
        'metadata': {
          'source': 'flutter_erp',
          'url': mediaUrl,
          if (isImage) 'media_url': mediaUrl,
          if (!isImage) 'documentUrl': mediaUrl,
          if (!isImage) 'document_url': mediaUrl,
          'filename': filename,
          if (clientMessageId != null) 'client_message_id': clientMessageId,
          ...?metadata,
        },
      },
    );
  }

  Future<bool> sendInteractiveAction({
    required BuildContext context,
    required String customerPhone,
    required String customerName,
    required String conversationId,
    required String actionType,
    required String actionKind,
    required String actionTargetId,
    required String message,
    String? customerId,
    String? contextType,
    String? contextId,
    String? jobId,
    double? amount,
    bool markQuoteSent = false,
    Map<String, dynamic>? metadata,
    String? documentUrl,
    String? documentFilename,
  }) async {
    return _sendWithFallback(
      context: context,
      phoneNumber: customerPhone,
      message: message,
      cloudBody: {
        'conversationId': conversationId,
        'customerId': customerId,
        'phoneNumber': _formatPhoneNumber(customerPhone),
        'contactName': customerName,
        'contextType': contextType,
        'contextId': contextId,
        'jobId': jobId,
        'type': 'interactive',
        'text': message,
        'caption': message,
        'actionType': actionType,
        'actionKind': actionKind,
        'actionTargetId': actionTargetId,
        'amount': amount,
        'markQuoteSent': markQuoteSent,
        if (documentUrl != null) 'documentUrl': documentUrl,
        if (documentFilename != null) 'documentFilename': documentFilename,
        'metadata': {
          'source': 'flutter_erp',
          ...?metadata,
        },
      },
    );
  }

  // Helper methods for status formatting
  String _getStatusEmoji(JobStatus status) {
    switch (status) {
      case JobStatus.pendiente:
        return '⏳';
      case JobStatus.diagnostico:
        return '🔍';
      case JobStatus.esperandoAprobacion:
        return '⏰';
      case JobStatus.esperandoRepuestos:
        return '📦';
      case JobStatus.enCurso:
        return '🔧';
      case JobStatus.finalizado:
        return '✅';
      case JobStatus.entregado:
        return '🎉';
      case JobStatus.cancelado:
        return '❌';
    }
  }

  String _getStatusMessage(JobStatus status) {
    switch (status) {
      case JobStatus.pendiente:
        return 'Estamos revisando los detalles de tu solicitud.';
      case JobStatus.diagnostico:
        return 'Estamos realizando el diagnóstico de tu bicicleta.';
      case JobStatus.esperandoAprobacion:
        return 'El diagnóstico está completo. Esperamos tu aprobación para continuar.';
      case JobStatus.esperandoRepuestos:
        return 'Estamos esperando que lleguen los repuestos necesarios.';
      case JobStatus.enCurso:
        return 'El trabajo está en progreso. Te avisaremos cuando esté listo.';
      case JobStatus.finalizado:
        return 'El trabajo ha sido completado. Estamos realizando las pruebas finales.';
      case JobStatus.entregado:
        return '¡Gracias por confiar en nosotros! Recuerda: tienes 1 semana de garantía para probar tu bici.';
      case JobStatus.cancelado:
        return 'El trabajo ha sido cancelado.';
    }
  }
}
