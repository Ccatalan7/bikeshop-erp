import '../../../shared/utils/contact_greeting.dart';
import '../models/purchase_order_document.dart';

/// El chat de WhatsApp del proveedor donde va el PDF del pedido, y si el
/// proveedor escribió en las últimas 24 h. Sin chat no hay dónde adjuntarlo.
class PurchaseOrderSupplierChat {
  const PurchaseOrderSupplierChat({
    required this.conversationId,
    required this.windowOpen,
  });

  final String? conversationId;
  final bool windowOpen;
}

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
    required this.greetingName,
    this.templateText,
  });

  final String recipientName;

  /// Cómo se saluda a quien recibe el pedido: lo que dice «Cómo saludarle»
  /// en la ficha de su contacto. Va en el texto y, fuera de las 24 h, en la
  /// plantilla. Vacío cuando no hay a quién nombrar.
  final String greetingName;
  final String recipientPhone;
  final String body;
  final String attachmentName;

  /// **WhatsApp sólo deja mandar texto libre dentro de las 24 h siguientes al
  /// último mensaje del proveedor.** Fuera de esa ventana sale una plantilla
  /// aprobada, no este texto. Mostrar la burbuja como si fuera a salir tal cual
  /// sería mentir sobre lo que el proveedor va a leer.
  final bool windowIsOpen;

  /// Lo que sale fuera de las 24 h: la plantilla de documento, con el PDF
  /// del pedido arriba (`documento_adjunto_v1`). Dentro de la ventana es
  /// null y sale [body], seguido del PDF.
  final String? templateText;

  String get deliveryCaveat => windowIsOpen
      ? 'Sale este mensaje y, enseguida, el PDF del pedido.'
      : 'No ha escrito en las últimas 24 horas, así que WhatsApp sólo permite '
          'una plantilla aprobada: sale el PDF del pedido con este saludo. El '
          'detalle va en el PDF.';

  static PurchaseOrderMessage forDocument(
    PurchaseOrderDocument document, {
    required String recipientName,
    required String recipientPhone,
    required String attachmentName,
    required bool windowIsOpen,
    String? greetingName,
    String Function(String name, {bool greetingIsChosen})? documentTemplate,
  }) {
    // Sin el saludo de la ficha, el primer nombre: lo mismo que un contacto
    // al que nadie le eligió otro.
    final greeting = normalizeContactGreeting(greetingName ?? '').isNotEmpty
        ? normalizeContactGreeting(greetingName!)
        : contactGreetingName(
            fullName: recipientName,
            style: ContactGreetingStyle.firstName,
          );
    final saludo = greeting.isEmpty ? 'Hola' : 'Hola $greeting';
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
      greetingName: greeting,
      // La plantilla saluda igual que el envío: con el saludo de la ficha o,
      // si no hay a quién nombrar, con el nombre de quien recibe.
      templateText: windowIsOpen || documentTemplate == null
          ? null
          : documentTemplate(
              greeting.isNotEmpty ? greeting : recipientName,
              greetingIsChosen: greeting.isNotEmpty,
            ),
    );
  }

  PurchaseOrderMessage copyWith({String? body}) => PurchaseOrderMessage(
        recipientName: recipientName,
        recipientPhone: recipientPhone,
        body: body ?? this.body,
        attachmentName: attachmentName,
        windowIsOpen: windowIsOpen,
        greetingName: greetingName,
        templateText: templateText,
      );
}
