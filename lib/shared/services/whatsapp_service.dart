import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import '../../modules/sales/models/sales_models.dart';
import '../../modules/bikeshop/models/bikeshop_models.dart';
import '../widgets/whatsapp_web_viewer.dart';

enum WhatsAppDeliveryMethod {
  cloudApi,
  manualFallback,
  failed,
}

/// WhatsApp messaging service for customer communication
/// Sends through WhatsApp Cloud API and falls back to manual WhatsApp Web if needed.
class WhatsAppService {
  static final WhatsAppService _instance = WhatsAppService._internal();
  static const String firstContactTemplateName =
      'seguimiento_servicio_bicicleta';
  static const String _firstContactTemplateLanguage = 'es_CL';
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

  WhatsAppDeliveryMethod get lastDeliveryMethod => _lastDeliveryMethod;
  int? get lastErrorCode => _lastErrorCode;
  bool get lastUsedFirstContactTemplate => _lastUsedFirstContactTemplate;
  String? get lastResolvedMessageText => _lastResolvedMessageText;

  bool get lastErrorRequiresServerFix =>
      _lastErrorCode == _expiredAccessTokenErrorCode;

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

  String _resolveCurrentAgentName() {
    final user = _client.auth.currentUser;
    final metadata = user?.userMetadata;

    final fullName = metadata?['full_name']?.toString().trim();
    if (fullName != null && fullName.isNotEmpty) {
      return fullName;
    }

    final name = metadata?['name']?.toString().trim();
    if (name != null && name.isNotEmpty) {
      return name;
    }

    final email = user?.email?.trim();
    if (email != null && email.isNotEmpty) {
      return email.split('@').first;
    }

    return 'Viñabike';
  }

  String _buildFirstContactTemplateText({
    required String customerName,
    required String agentName,
  }) {
    return 'Hola $customerName, buen día. Soy $agentName de Viñabike y te escribo por el servicio de tu bicicleta.';
  }

  void _resetLastAttemptState({String? resolvedMessageText}) {
    _lastErrorCode = null;
    _lastUsedFirstContactTemplate = false;
    _lastResolvedMessageText = resolvedMessageText;
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
      return true;
    }

    return DateTime.now().toUtc().difference(lastInboundAt.toUtc()) <
        const Duration(hours: 24);
  }

  Future<bool> _sendViaCloud(Map<String, dynamic> body) async {
    try {
      final response = await _client.functions.invoke(
        'whatsapp-send',
        body: body,
      );

      final status = response.status;
      if (status >= 200 && status < 300) {
        _lastErrorCode = null;
        _lastDeliveryMethod = WhatsAppDeliveryMethod.cloudApi;
        debugPrint('✅ [WhatsAppService] Message sent via Cloud API');
        return true;
      }

      _lastErrorCode = _extractErrorCode(response.data);

      debugPrint(
        '❌ [WhatsAppService] Cloud API failed: status=$status data=${response.data}',
      );
    } catch (error) {
      _lastErrorCode = null;
      debugPrint('❌ [WhatsAppService] Cloud API error: $error');
    }

    return false;
  }

  Future<bool> _sendWithFallback({
    required BuildContext context,
    required String phoneNumber,
    required String message,
    required Map<String, dynamic> cloudBody,
  }) async {
    if (await _sendViaCloud(cloudBody)) {
      return true;
    }

    if (_shouldSkipManualFallback()) {
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
  }) async {
    final resolvedAgentName = (agentName != null && agentName.trim().isNotEmpty)
        ? agentName.trim()
        : _resolveCurrentAgentName();
    final renderedMessage = _buildFirstContactTemplateText(
      customerName: customerName,
      agentName: resolvedAgentName,
    );

    _resetLastAttemptState(resolvedMessageText: renderedMessage);

    final success = await _sendViaCloud({
      'conversationId': conversationId,
      'phoneNumber': _formatPhoneNumber(customerPhone),
      'contactName': customerName,
      'contextType': contextType,
      'contextId': contextId,
      'type': 'template',
      'templateName': firstContactTemplateName,
      'templateLanguage': _firstContactTemplateLanguage,
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
              'text': resolvedAgentName,
            },
          ],
        },
      ],
      'metadata': {
        'source': 'flutter_erp',
        'template_purpose': 'first_contact',
      },
    });

    if (success) {
      _lastUsedFirstContactTemplate = true;
    } else {
      _lastDeliveryMethod = WhatsAppDeliveryMethod.failed;
    }

    return success;
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
