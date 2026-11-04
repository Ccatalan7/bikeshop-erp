import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'transport_failure.dart';

StageAwareSender createStageAwareSender() => IoStageAwareSender();

/// El emisor de escritorio y teléfono: sabe si la conexión llegó a abrirse.
///
/// `HttpClient.openUrl` resuelve el nombre, conecta y termina el TLS antes de
/// devolver la petición; lo que falla ahí nunca salió del equipo. Lo que falla
/// después ya pudo llegar.
///
/// Una conexión reusada (keep-alive) puede estar muerta sin saberlo: entonces
/// `openUrl` vuelve al tiro y el fallo aparece recién al mandar, cuando ya no
/// se sabe nada. Por eso las peticiones que no se pueden repetir salen por un
/// cliente que nunca reusa conexiones ([freshConnection]): cada una abre la
/// suya, y si no hay red lo dice en la etapa en que es seguro reintentar.
class IoStageAwareSender implements StageAwareSender {
  IoStageAwareSender({HttpClient? pooled, HttpClient? fresh})
      : _pooled = pooled ?? _newClient(),
        _fresh = fresh ?? _newClient();

  static const Duration connectTimeout = Duration(seconds: 10);

  final HttpClient _pooled;
  final HttpClient _fresh;

  static HttpClient _newClient() => HttpClient()
    ..connectionTimeout = connectTimeout
    ..idleTimeout = const Duration(seconds: 10);

  @override
  Future<http.StreamedResponse> send(
    http.BaseRequest request, {
    required Duration headerTimeout,
    required Duration idleTimeout,
    bool freshConnection = false,
  }) async {
    final client = freshConnection ? _fresh : _pooled;
    final stream = request.finalize();
    HttpClientRequest ioRequest;
    try {
      ioRequest = await client
          .openUrl(request.method, request.url)
          .timeout(connectTimeout + const Duration(seconds: 5));
    } on TimeoutException catch (error) {
      throw TransportFailure(
        uri: request.url,
        cause: error,
        notSent: true,
        timedOut: true,
      );
    } on SocketException catch (error) {
      throw TransportFailure(uri: request.url, cause: error, notSent: true);
    } on TlsException catch (error) {
      throw TransportFailure(uri: request.url, cause: error, notSent: true);
    } on HttpException catch (error) {
      throw TransportFailure(uri: request.url, cause: error, notSent: true);
    }

    ioRequest
      ..followRedirects = request.followRedirects
      ..maxRedirects = request.maxRedirects
      ..contentLength = request.contentLength ?? -1
      ..persistentConnection =
          freshConnection ? false : request.persistentConnection;
    request.headers.forEach(ioRequest.headers.set);

    HttpClientResponse response;
    try {
      response = await stream.pipe(ioRequest).timeout(headerTimeout)
          as HttpClientResponse;
    } on TimeoutException catch (error) {
      ioRequest.abort(error);
      throw TransportFailure(
        uri: request.url,
        cause: error,
        notSent: false,
        timedOut: true,
      );
    } on SocketException catch (error) {
      throw TransportFailure(uri: request.url, cause: error, notSent: false);
    } on TlsException catch (error) {
      throw TransportFailure(uri: request.url, cause: error, notSent: false);
    } on HttpException catch (error) {
      throw TransportFailure(uri: request.url, cause: error, notSent: false);
    }

    final headers = <String, String>{};
    response.headers.forEach((key, values) {
      headers[key] = values.map((value) => value.trimRight()).join(',');
    });

    final body = response.timeout(
      idleTimeout,
      onTimeout: (sink) {
        sink.addError(
          http.ClientException('El servidor dejó de responder', request.url),
        );
        sink.close();
      },
    ).handleError(
      (Object error) => throw http.ClientException('$error', request.url),
      test: (error) => error is HttpException || error is SocketException,
    );

    return http.StreamedResponse(
      body,
      response.statusCode,
      contentLength:
          response.contentLength == -1 ? null : response.contentLength,
      request: request,
      headers: headers,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
      reasonPhrase: response.reasonPhrase,
    );
  }

  @override
  void close() {
    _pooled.close(force: true);
    _fresh.close(force: true);
  }
}
