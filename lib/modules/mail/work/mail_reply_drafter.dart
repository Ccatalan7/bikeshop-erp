import 'package:flutter/foundation.dart';

import '../../../shared/services/gemini_proxy_service.dart';
import 'mail_work_models.dart';
import 'mail_work_words.dart';

/// Escribe el borrador de una respuesta (etapa 4 de Correo que trabaja): a un
/// cliente que escribió, o a una reseña de Google. Una persona del equipo lo
/// revisa y lo envía; nada sale solo.
///
/// La voz es la de la marca con los clientes (dueño, 2026-11-04): tuteo,
/// corto y seguro; ni frases de app ni el «usted» de notaría. Y nunca inventa
/// lo que no está en el correo ni en el ERP (precios, stock, plazos).
class MailReplyDrafter {
  MailReplyDrafter({GeminiProxyService? proxy})
      : _proxy = proxy ?? GeminiProxyService();

  final GeminiProxyService _proxy;

  /// El modelo con que el ERP lee con criterio (Conciliación, fichas).
  static const String model = 'gemini-2.5-flash';

  static const int _maxBody = 4000;

  static const String _voice = 'Voz: tuteo, cercana y segura, corta. Nada de '
      'frases de app («¡Hola! 👋», «Estamos aquí para ayudarte», «No dudes en '
      'contactarnos»), nada de «usted» ni fórmulas largas de cortesía, sin '
      'emojis ni signos de exclamación seguidos.';

  static const String _honesty = 'Nunca inventes precios, stock, plazos, '
      'horarios, garantías ni promesas. Si el correo pide algo que no está en '
      'los datos de abajo, di que lo revisas y respondes, o pide el dato que '
      'falta.';

  /// El cuerpo de la respuesta a un cliente, o null si no se pudo escribir.
  Future<String?> customerReply(MailItem item) async {
    const system = 'Atiendes el correo de Viñabike, taller y tienda de '
        'bicicletas en Viña del Mar, Chile. Escribes la respuesta a un correo '
        'para que una persona del equipo la revise y la envíe. $_voice '
        '$_honesty Entre 2 y 5 frases. Responde sólo el cuerpo del correo, '
        'sin asunto ni comillas, y firma «Equipo Viñabike».';
    return _draft(system, _context(item));
  }

  /// Una respuesta pública a una reseña de Google, o null.
  Future<String?> reviewReply(MailItem item) async {
    const system = 'Respondes en nombre de Viñabike, taller y tienda de '
        'bicicletas en Viña del Mar, una reseña de Google. La respuesta es '
        'pública. $_voice Agradece por el nombre de quien escribió si '
        'aparece; si la reseña cuenta un problema, reconócelo sin excusas e '
        'invita a escribir al taller. Entre 1 y 3 frases. Responde sólo el '
        'texto de la respuesta, sin comillas ni firma.';
    return _draft(system, _context(item));
  }

  String _context(MailItem item) {
    final body = MailWords.readable(item.bodyText ?? item.snippet ?? '');
    final records = [
      for (final link in item.links)
        if ((link.label ?? '').isNotEmpty)
          '${MailWords.linkTitle(link)}: ${link.label}'
              '${(link.detail ?? '').isEmpty ? '' : ' (${link.detail})'}',
    ];
    return [
      'De: ${item.senderTitle} <${item.fromAddress}>',
      'Asunto: ${item.subject}',
      if (records.isNotEmpty) 'Lo que el ERP sabe: ${records.join('; ')}',
      '',
      'Correo:',
      body.length > _maxBody ? body.substring(0, _maxBody) : body,
    ].join('\n');
  }

  Future<String?> _draft(String system, String prompt) async {
    try {
      final result = await _proxy.generateContent(
        model: model,
        systemInstruction: {
          'parts': [
            {'text': system},
          ],
        },
        contents: [
          {
            'role': 'user',
            'parts': [
              {'text': prompt},
            ],
          },
        ],
        generationConfig: const {'temperature': 0.4},
      );
      final text = result.text.trim();
      if (text.isEmpty) {
        debugPrint('[Correo] el borrador volvió vacío '
            '(${result.finishReason ?? 'sin motivo'})');
        return null;
      }
      return _clean(text);
    } catch (error) {
      // Sin borrador, la respuesta se abre vacía: el operador escribe.
      debugPrint('[Correo] no se pudo escribir el borrador: $error');
      return null;
    }
  }

  /// Sin comillas envolventes ni un «Asunto:» que el modelo agregue de más.
  static String _clean(String text) {
    var out = text.trim();
    if (out.length > 1 &&
        (out.startsWith('"') && out.endsWith('"') ||
            out.startsWith('«') && out.endsWith('»'))) {
      out = out.substring(1, out.length - 1).trim();
    }
    out = out.replaceFirst(
        RegExp(r'^asunto:[^\n]*\n+', caseSensitive: false), '');
    return out.trim();
  }
}
