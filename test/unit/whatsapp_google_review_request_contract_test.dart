import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// El pedido de reseña lo arma la base (`process_whatsapp_review_requests_v1`)
/// y Meta aprueba el cuerpo de `whatsapp_templates.ts`. Si los dos textos se
/// separan, la bandeja del taller archiva una cosa y el cliente recibe otra
/// (ya pasó con las tildes de «está lista», 2026-08-21).
void main() {
  final templates = File('supabase/functions/_shared/whatsapp_templates.ts')
      .readAsStringSync();
  final migration = File(
    'supabase/migrations/20261008200000_whatsapp_google_review_requests.sql',
  ).readAsStringSync();

  test('the inbox copy is the exact body Meta approves', () {
    final body = RegExp(
      r'name: reviewRequestTemplateName,[\s\S]*?body:\s*"([^"]+)"',
    ).firstMatch(templates)?.group(1);
    expect(body, isNotNull);

    final caption = RegExp(
      r"'caption', format\(\s*'([^']+)'",
    ).firstMatch(migration)?.group(1);
    expect(caption, isNotNull);

    var placeholder = 0;
    final asTemplate = caption!.replaceAllMapped(
      RegExp('%s'),
      (_) => '{{${++placeholder}}}',
    );
    expect(asTemplate, body);
    expect(
        templates, contains('reviewRequestTemplateName = "resena_google_v1"'));
    expect(migration, contains("'templateName', 'resena_google_v1'"));
  });

  test('the customer is greeted by first name like every other template', () {
    final greeting = File(
      'supabase/functions/_shared/whatsapp_template_greeting.ts',
    ).readAsStringSync();
    expect(greeting, contains('"google_review_request"'));
    expect(migration, contains("'template_purpose', 'google_review_request'"));
  });
}
