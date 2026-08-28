import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/conversation.dart';
import 'chat_window.dart';

/// Una conversación a pantalla completa en compacto.
///
/// **Por qué existe.** El módulo empujaba `ChatWindow` como un
/// `MaterialPageRoute` pelado: sin `Scaffold`, sin barra y sin nadie que
/// consumiera el inset superior. `ChatWindow` pinta su propio encabezado desde
/// el borde del viewport, así que el nombre del contacto y sus chips quedaban
/// debajo del reloj, la señal y la batería del sistema.
///
/// La guía móvil lo dice explícito: un hijo a pantalla completa **fuera del
/// shell** tiene que traer su propio contrato de inset. Eso es esta clase, y no
/// un `SafeArea` suelto en `ChatWindow`: la misma ventana se compone embebida
/// dentro del rail derecho y de la bitácora, donde el inset ya lo consumió el
/// shell y volver a consumirlo dejaría un hueco.
class CompactChatRoute extends StatelessWidget {
  const CompactChatRoute({
    super.key,
    required this.conversation,
    this.initialThreadRootMessageId,
  });

  final Conversation conversation;
  final String? initialThreadRootMessageId;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // La tinta de los iconos del sistema sale del MISMO lienzo semántico que
    // pinta la franja; anotar un estilo que no corresponda al color de abajo es
    // lo que deja iconos claros sobre superficie clara.
    final canvasIsDark = colorScheme.surface.computeLuminance() < 0.5;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness:
            canvasIsDark ? Brightness.light : Brightness.dark,
        statusBarBrightness: canvasIsDark ? Brightness.dark : Brightness.light,
      ),
      child: Scaffold(
        // El Scaffold pinta la franja del sistema con la misma superficie del
        // encabezado, así no queda una costura de otro color arriba.
        backgroundColor: colorScheme.surface,
        body: SafeArea(
          // Sólo arriba: el compositor de abajo ya resuelve el teclado y la
          // barra de gestos, y consumir el inferior le robaría alto.
          top: true,
          bottom: false,
          child: ChatWindow(
            conversation: conversation,
            compact: true,
            initialThreadRootMessageId: initialThreadRootMessageId,
          ),
        ),
      ),
    );
  }
}
