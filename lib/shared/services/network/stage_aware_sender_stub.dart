import 'dart:async';

import 'package:http/http.dart' as http;

import 'transport_failure.dart';

StageAwareSender createStageAwareSender() => BrowserStageAwareSender();

/// El emisor del navegador. El navegador no dice en qué etapa falló una
/// petición (todo llega como «XMLHttpRequest error»), así que ningún fallo
/// cuenta como «no salió»: sólo se reintenta lo que se puede repetir.
class BrowserStageAwareSender implements StageAwareSender {
  BrowserStageAwareSender({http.Client? inner})
      : _inner = inner ?? http.Client();

  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(
    http.BaseRequest request, {
    required Duration headerTimeout,
    required Duration idleTimeout,
    bool freshConnection = false,
  }) async {
    http.StreamedResponse response;
    try {
      response = await _inner.send(request).timeout(headerTimeout);
    } on TimeoutException catch (error) {
      throw TransportFailure(
        uri: request.url,
        cause: error,
        notSent: false,
        timedOut: true,
      );
    } on http.ClientException catch (error) {
      throw TransportFailure(uri: request.url, cause: error, notSent: false);
    }
    final body = response.stream.timeout(
      idleTimeout,
      onTimeout: (sink) {
        sink.addError(
          http.ClientException('El servidor dejó de responder', request.url),
        );
        sink.close();
      },
    );
    return http.StreamedResponse(
      body,
      response.statusCode,
      contentLength: response.contentLength,
      request: request,
      headers: response.headers,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
      reasonPhrase: response.reasonPhrase,
    );
  }

  @override
  void close() => _inner.close();
}
