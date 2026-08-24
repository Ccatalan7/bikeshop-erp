import 'package:flutter/material.dart';

import '../models/purchase_order_message.dart';
import 'purchase_visual_language.dart';

/// **Cómo se va a ver el mensaje cuando le llegue al proveedor.**
///
/// Una burbuja de verdad, con el adjunto como lo va a recibir: el operador no
/// tiene que imaginarse nada. Y el texto es **editable acá mismo** — descubrir
/// que quería agregar una frase y tener que volver al pedido para lograrlo es
/// justo lo que no queremos.
///
/// Debajo, lo que de verdad va a pasar al enviar. WhatsApp sólo permite texto
/// libre dentro de las 24 h siguientes al último mensaje del proveedor; fuera
/// de eso sale una plantilla. Dibujar la burbuja sin decirlo mostraría un
/// mensaje que el proveedor no va a leer.
class PurchaseOrderMessagePreview extends StatelessWidget {
  const PurchaseOrderMessagePreview({
    super.key,
    required this.message,
    required this.bodyController,
    required this.sending,
    required this.onBack,
    required this.onSend,
  });

  final PurchaseOrderMessage message;
  final TextEditingController bodyController;
  final bool sending;
  final VoidCallback onBack;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final tokens = PurchaseTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Así le va a llegar',
                style: PurchaseType.rowTitle.copyWith(color: tokens.ink),
              ),
            ),
            Text(
              '${message.recipientName} · ${message.recipientPhone}',
              style: PurchaseType.meta.copyWith(color: tokens.inkFaint),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              // El lienzo del chat, para que la burbuja se lea como burbuja y
              // no como una caja de texto más de la pantalla.
              color: const Color(0xFF0B141A),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: tokens.border),
            ),
            clipBehavior: Clip.antiAlias,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(14),
              child: Align(
                alignment: Alignment.centerRight,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 380),
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Color(0xFF005C4B),
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(10),
                        topRight: Radius.circular(10),
                        bottomLeft: Radius.circular(10),
                        bottomRight: Radius.circular(3),
                      ),
                    ),
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _Attachment(name: message.attachmentName),
                        const SizedBox(height: 7),
                        // El cuerpo se edita en la burbuja: lo que se ve es lo
                        // que se manda, incluso mientras se corrige.
                        TextSelectionTheme(
                          data: const TextSelectionThemeData(
                            cursorColor: Color(0xFFE9EDEF),
                            selectionColor: Color(0x5525D366),
                            selectionHandleColor: Color(0xFF25D366),
                          ),
                          child: TextField(
                            controller: bodyController,
                            maxLines: null,
                            style: PurchaseType.body.copyWith(
                              color: const Color(0xFFE9EDEF),
                              height: 1.35,
                            ),
                            cursorColor: const Color(0xFFE9EDEF),
                            decoration: const InputDecoration(
                              isDense: true,
                              // `filled: false` explícito: el tema de la app
                              // rellena sus campos, y ese relleno claro dentro de
                              // la burbuja tapaba el texto del mensaje. La
                              // burbuja tiene que verse como la va a ver el
                              // proveedor, no como un formulario del ERP.
                              filled: false,
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              disabledBorder: InputBorder.none,
                              errorBorder: InputBorder.none,
                              focusedErrorBorder: InputBorder.none,
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                TimeOfDay.now().format(context),
                                style: PurchaseType.meta.copyWith(
                                  color: const Color(0xFF8FA5AC),
                                  fontSize: 9,
                                ),
                              ),
                              const SizedBox(width: 3),
                              const Icon(
                                Icons.done_all,
                                size: 12,
                                color: Color(0xFF8FA5AC),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
          decoration: BoxDecoration(
            color: tokens.sunken,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(
              color: message.windowIsOpen ? tokens.hair : tokens.borderStrong,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                message.windowIsOpen
                    ? Icons.check_circle_outline
                    : Icons.schedule,
                size: 14,
                color: message.windowIsOpen ? tokens.act : tokens.inkMuted,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  message.deliveryCaveat,
                  style: PurchaseType.meta.copyWith(color: tokens.inkMuted),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 14,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            PurchasePrimaryButton(
              key: const ValueKey('order-message-send'),
              label: sending ? 'Enviando…' : 'Enviar ahora',
              onPressed: sending ? null : onSend,
            ),
            PurchaseInlineAction(
              key: const ValueKey('order-message-back'),
              label: 'Volver al pedido',
              onPressed: sending ? null : onBack,
            ),
          ],
        ),
      ],
    );
  }
}

class _Attachment extends StatelessWidget {
  const _Attachment({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF025144),
        borderRadius: BorderRadius.circular(7),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 9),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: const Color(0xFFD93F3F),
              borderRadius: BorderRadius.circular(5),
            ),
            alignment: Alignment.center,
            child: Text(
              'PDF',
              style: PurchaseType.label.copyWith(
                color: Colors.white,
                fontSize: 8,
              ),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PurchaseType.meta.copyWith(
                    color: const Color(0xFFE9EDEF),
                  ),
                ),
                Text(
                  'Documento PDF',
                  style: PurchaseType.meta.copyWith(
                    color: const Color(0xFF8FA5AC),
                    fontSize: 9,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
