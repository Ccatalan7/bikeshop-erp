import 'package:flutter_test/flutter_test.dart';

import 'package:vinabike_erp/shared/services/gemini_proxy_service.dart';

/// Qué significa cada falla de la IA y qué se le dice al operador.
///
/// 2026-11-06 → 14: Google exigió prepago a la cuenta de Gemini y respondió 402
/// a todo durante ocho días. El asistente decía «alta demanda», la conciliación
/// «límite por minuto» y el despacho mostraba la excepción cruda; además cada
/// llamada se reintentaba tres veces.
void main() {
  // Así llega desde `gemini-proxy`: la función responde 502 y trae en el
  // cuerpo el estado de Google.
  const withoutCredit = GeminiProxyException(
    message: 'AI provider is unavailable',
    statusCode: 402,
    functionStatus: 502,
    apiStatus: 'RESOURCE_EXHAUSTED',
    proxyCode: 'provider_unavailable',
  );

  test('a 402 from the provider is an account without credit', () {
    expect(withoutCredit.isOutOfCredit, isTrue);
    expect(withoutCredit.userMessage, GeminiProxyException.outOfCreditMessage);
    expect(withoutCredit.userMessage, contains('sin saldo'));
    expect(withoutCredit.userMessage, contains('aistudio.google.com'));
  });

  test('no retry can fix an account without credit', () {
    // El mensaje del proxy dice «unavailable», que por sí solo cuenta como
    // pasajero: el 402 manda.
    expect(withoutCredit.isTransient, isFalse);
  });

  test('a 402 of the function itself is another account', () {
    // La pasarela de Supabase también puede responder 402 (su facturación):
    // ahí no hay cuerpo del proxy y no es el saldo de Google.
    const gateway = GeminiProxyException(
      message: 'Payment Required',
      statusCode: 402,
      functionStatus: 402,
    );
    expect(gateway.isOutOfCredit, isFalse);
    expect(gateway.userMessage, isNot(contains('Google')));
  });

  test('the per-minute limit is still worth retrying and says so', () {
    const limited = GeminiProxyException(
      message: 'AI provider is unavailable',
      statusCode: 429,
      functionStatus: 429,
      apiStatus: 'RESOURCE_EXHAUSTED',
      proxyCode: 'provider_unavailable',
    );
    expect(limited.isOutOfCredit, isFalse);
    expect(limited.isTransient, isTrue);
    expect(limited.userMessage, contains('límite de consultas por minuto'));
  });

  test('an overloaded provider is retried and asks to try again', () {
    const overloaded = GeminiProxyException(
      message: 'AI provider is unavailable',
      statusCode: 503,
      functionStatus: 502,
      apiStatus: 'UNAVAILABLE',
      proxyCode: 'provider_unavailable',
    );
    expect(overloaded.isTransient, isTrue);
    expect(overloaded.userMessage, contains('Intenta de nuevo'));
  });

  test('no message shows the exception to the operator', () {
    const failures = [
      withoutCredit,
      GeminiProxyException(message: 'Authentication required', statusCode: 401),
      GeminiProxyException(
        message: 'AI service is not configured',
        statusCode: 500,
      ),
      GeminiProxyException(
        message: 'AI provider rejected the request',
        statusCode: 400,
        proxyCode: 'provider_rejected_request',
      ),
    ];
    for (final failure in failures) {
      expect(failure.userMessage, isNot(contains('Exception')));
      expect(failure.userMessage, isNot(contains('statusCode')));
      expect(failure.userMessage, isNot(contains('provider')));
    }
  });
}
