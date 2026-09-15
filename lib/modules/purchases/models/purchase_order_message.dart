import '../models/purchase_order_document.dart';

/// **El mensaje que le va a llegar al proveedor.**
///
/// Se arma acá y no en el momento de enviar, porque el operador tiene que ver
/// exactamente esto antes de apretar. Un «se envió el pedido» sin haber visto
/// el texto es firmar en blanco.
class PurchaseOrderMessage {
  const PurchaseOrderMessage({
    required this.recipientName,
    required this.recipientPhone,
    required this.body,
    required this.attachmentName,
    required this.windowIsOpen,
  });

  final String recipientName;
  final String recipientPhone;
  final String body;
  final String attachmentName;

  /// **WhatsApp sólo deja mandar texto libre dentro de las 24 h siguientes al
  /// último mensaje del proveedor.** Fuera de esa ventana sale una plantilla
  /// aprobada, no este texto. Mostrar la burbuja como si fuera a salir tal cual
  /// sería mentir sobre lo que el proveedor va a leer.
  final bool windowIsOpen;

  String get deliveryCaveat => windowIsOpen
      ? 'Sale tal cual, como mensaje directo.'
      : 'El proveedor no ha escrito en las últimas 24 horas, así que WhatsApp '
          'sólo permite una plantilla aprobada. Sale la plantilla de contacto '
          'con tu nombre, y este texto queda en la conversación para cuando '
          'responda.';

  static PurchaseOrderMessage forDocument(
    PurchaseOrderDocument document, {
    required String recipientName,
    required String recipientPhone,
    required String attachmentName,
    required bool windowIsOpen,
  }) {
    final saludo = recipientName.trim().isEmpty
        ? 'Hola'
        : 'Hola ${recipientName.trim().split(' ').first}';
    final lineas = document.lines.length;
    final cuerpo = StringBuffer()
      ..writeln('$saludo, te mando un pedido desde ${document.buyerName}.')
      ..writeln()
      ..writeln('Pedido ${document.orderNumber} · ${document.issuedOn}')
      ..writeln(
        '$lineas ${lineas == 1 ? 'producto' : 'productos'} · '
        '${document.unitCount} unidades · Total ${document.total} IVA incluido',
      );
    // Las tres primeras líneas van en el texto: un adjunto que no se abre no
    // dice nada, y un mensaje que sólo dice «te mando un pedido» obliga al
    // proveedor a abrirlo para saber si le interesa.
    final muestra = document.lines.take(3);
    if (muestra.isNotEmpty) {
      cuerpo.writeln();
      for (final line in muestra) {
        cuerpo.writeln('• ${line.quantity} × ${line.name}');
      }
      if (document.lines.length > muestra.length) {
        final resto = document.lines.length - muestra.length;
        cuerpo.writeln(
          '• y $resto ${resto == 1 ? 'producto más' : 'productos más'} '
          'en el archivo',
        );
      }
    }
    cuerpo
      ..writeln()
      ..write('El detalle completo va en el PDF adjunto. '
          'Cualquier cosa me avisas por acá.');
    return PurchaseOrderMessage(
      recipientName: recipientName,
      recipientPhone: recipientPhone,
      body: cuerpo.toString().trimRight(),
      attachmentName: attachmentName,
      windowIsOpen: windowIsOpen,
    );
  }

  PurchaseOrderMessage copyWith({String? body}) => PurchaseOrderMessage(
        recipientName: recipientName,
        recipientPhone: recipientPhone,
        body: body ?? this.body,
        attachmentName: attachmentName,
        windowIsOpen: windowIsOpen,
      );
}
