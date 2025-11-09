import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import '../../modules/sales/models/sales_models.dart';
import '../../modules/bikeshop/models/bikeshop_models.dart';
import '../widgets/whatsapp_web_viewer.dart';

/// WhatsApp messaging service for customer communication
/// Opens WhatsApp Web in embedded WebView (desktop) or external app (mobile)
class WhatsAppService {
  static final WhatsAppService _instance = WhatsAppService._internal();
  factory WhatsAppService() => _instance;
  WhatsAppService._internal();

  final _currencyFormat = NumberFormat.currency(
    symbol: '\$',
    decimalDigits: 0,
    locale: 'es_CL',
  );

  final _dateFormat = DateFormat('dd/MM/yyyy', 'es_CL');

  /// Format Chilean phone number (remove spaces, dashes, +56 prefix)
  String _formatPhoneNumber(String phone) {
    // Remove all non-numeric characters
    String cleaned = phone.replaceAll(RegExp(r'[^0-9]'), '');
    
    // Remove leading 56 if present (Chile country code)
    if (cleaned.startsWith('56') && cleaned.length > 9) {
      cleaned = cleaned.substring(2);
    }
    
    // Ensure it starts with 9 (Chilean mobile format)
    if (!cleaned.startsWith('9')) {
      cleaned = '9$cleaned';
    }
    
    // Return with country code
    return '56$cleaned';
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
      print('❌ Error opening WhatsApp: $e');
      // Fallback: Try opening in external browser
      try {
        final formattedPhone = _formatPhoneNumber(phoneNumber);
        final encodedMessage = Uri.encodeComponent(message);
        final url = 'https://wa.me/$formattedPhone?text=$encodedMessage';
        
        final uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) {
          return await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      } catch (fallbackError) {
        print('❌ Fallback error: $fallbackError');
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

    return await _openWhatsApp(context, customerPhone, message);
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

    return await _openWhatsApp(context, customerPhone, message);
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

${job.deadline != null ? '⏰ Fecha estimada: ${_dateFormat.format(job.deadline!)}\n' : ''}${job.notes != null && job.notes!.isNotEmpty ? '📝 Notas: ${job.notes}\n' : ''}
¿Alguna duda? ¡Escríbenos! 📞

Viña Bike - Tu taller de confianza 🔧
    ''';

    return await _openWhatsApp(context, customerPhone, message);
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

    return await _openWhatsApp(context, customerPhone, message);
  }

  /// Send generic message
  Future<bool> sendMessage({
    required BuildContext context,
    required String customerPhone,
    required String message,
  }) async {
    return await _openWhatsApp(context, customerPhone, message);
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
        return '�';
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
