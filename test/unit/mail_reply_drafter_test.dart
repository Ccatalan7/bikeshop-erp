import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vinabike_erp/modules/mail/work/mail_reply_drafter.dart';
import 'package:vinabike_erp/modules/mail/work/mail_work_models.dart';
import 'package:vinabike_erp/shared/services/gemini_proxy_service.dart';

/// El borrador de respuesta (Correo que trabaja, etapa 4): la voz de la marca,
/// nada inventado y lo que el ERP sabe del registro. Todo es inventado.
class _FakeProxy extends GeminiProxyService {
  _FakeProxy(this.reply, {this.fail = false})
      : super(
          client: SupabaseClient('https://example.supabase.co', 'test-anon'),
        );

  final String reply;
  final bool fail;
  String? system;
  String? prompt;
  String? model;

  @override
  Future<GeminiProxyGenerateResult> generateContent({
    required String model,
    required List<Map<String, dynamic>> contents,
    Map<String, dynamic>? systemInstruction,
    List<Map<String, dynamic>> tools = const [],
    Map<String, dynamic>? generationConfig,
  }) async {
    this.model = model;
    system =
        ((systemInstruction?['parts'] as List).first as Map)['text'] as String;
    prompt =
        (((contents.first['parts'] as List).first) as Map)['text'] as String;
    if (fail) {
      throw GeminiProxyException(
        statusCode: 402,
        message: 'AI provider is unavailable',
      );
    }
    return GeminiProxyGenerateResult(text: reply, functionCalls: const []);
  }
}

MailItem _customerMail() => MailItem.fromJson({
      'id': 'm-1',
      'mailbox': 'taller@ejemplo.invalid',
      'provider': 'gmail',
      'provider_message_id': 'p-1',
      'from_address': 'persona@ejemplo.invalid',
      'from_name': 'Persona Inventada',
      'subject': '¿Está lista mi bici?',
      'received_at': '2026-11-06T13:00:00Z',
      'kind': 'customer',
      'body_text': 'Hola, dejé la bici el lunes. ¿Ya está lista?',
      'links': [
        {
          'type': 'job',
          'id': 'job-1',
          'label': 'Trabajo #1234',
          'detail': 'En reparación',
        },
      ],
    });

void main() {
  test('a customer reply carries the brand voice and the record', () async {
    final proxy = _FakeProxy('"Hola Persona, tu bici sigue en reparación. '
        'Te avisamos apenas esté.\n\nEquipo Viñabike"');
    final draft =
        await MailReplyDrafter(proxy: proxy).customerReply(_customerMail());

    expect(
        draft,
        'Hola Persona, tu bici sigue en reparación. '
        'Te avisamos apenas esté.\n\nEquipo Viñabike');
    expect(proxy.system, contains('tuteo'));
    expect(proxy.system, contains('Nunca inventes precios'));
    expect(proxy.system, contains('Equipo Viñabike'));
    expect(proxy.prompt, contains('Trabajo: Trabajo #1234 (En reparación)'));
    expect(proxy.prompt, contains('¿Ya está lista?'));
    expect(proxy.model, MailReplyDrafter.model);
  });

  test('a subject line the model adds is dropped', () async {
    final proxy =
        _FakeProxy('Asunto: Re: tu bici\n\nHola, sigue en el taller.');
    final draft =
        await MailReplyDrafter(proxy: proxy).customerReply(_customerMail());
    expect(draft, 'Hola, sigue en el taller.');
  });

  test('without the AI there is no draft, and nothing breaks', () async {
    final proxy = _FakeProxy('', fail: true);
    expect(await MailReplyDrafter(proxy: proxy).customerReply(_customerMail()),
        isNull);
  });

  test('a review reply is public, short and unsigned', () async {
    final proxy = _FakeProxy('Gracias, Ana, por tu reseña.');
    final draft =
        await MailReplyDrafter(proxy: proxy).reviewReply(_customerMail());
    expect(draft, 'Gracias, Ana, por tu reseña.');
    expect(proxy.system, contains('pública'));
    expect(proxy.system, contains('sin comillas ni firma'));
  });
}
