@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:vinabike_erp/shared/services/network/stage_aware_sender_io.dart';
import 'package:vinabike_erp/shared/services/network/transport_failure.dart';

/// El emisor de escritorio contra sockets reales: lo único que el equipo sabe
/// con certeza es si la conexión llegó a abrirse.
void main() {
  late IoStageAwareSender sender;

  setUp(() => sender = IoStageAwareSender());
  tearDown(() => sender.close());

  Future<TransportFailure> failureOf(Future<Object?> send) async {
    try {
      await send;
    } on TransportFailure catch (failure) {
      return failure;
    }
    fail('Se esperaba un TransportFailure');
  }

  test('a un puerto cerrado no sale nada: se puede reintentar siempre',
      () async {
    final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = probe.port;
    await probe.close();

    final failure = await failureOf(sender.send(
      http.Request(
          'POST', Uri.parse('http://127.0.0.1:$port/rest/v1/customers'))
        ..body = '{"name":"Ana"}',
      headerTimeout: const Duration(seconds: 5),
      idleTimeout: const Duration(seconds: 5),
      freshConnection: true,
    ));
    expect(failure.notSent, isTrue);
  });

  test('si el servidor corta después de recibir, no se sabe si llegó',
      () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final accepted = server.listen((socket) {
      socket.listen((_) => socket.destroy());
    });
    addTearDown(() async {
      await accepted.cancel();
      await server.close();
    });

    final failure = await failureOf(sender.send(
      http.Request('POST',
          Uri.parse('http://127.0.0.1:${server.port}/rest/v1/customers'))
        ..body = '{"name":"Ana"}',
      headerTimeout: const Duration(seconds: 5),
      idleTimeout: const Duration(seconds: 5),
      freshConnection: true,
    ));
    expect(failure.notSent, isFalse);
    expect(failure.toClientException(), isA<http.ClientException>());
  });

  test('si la respuesta no llega a tiempo, se corta y no se sabe si llegó',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requests = server.listen((request) async {
      await Future<void>.delayed(const Duration(seconds: 3));
      request.response.statusCode = 200;
      await request.response.close();
    });
    addTearDown(() async {
      await requests.cancel();
      await server.close(force: true);
    });

    final failure = await failureOf(sender.send(
      http.Request(
          'GET', Uri.parse('http://127.0.0.1:${server.port}/rest/v1/products')),
      headerTimeout: const Duration(milliseconds: 300),
      idleTimeout: const Duration(seconds: 5),
    ));
    expect(failure.timedOut, isTrue);
    expect(failure.notSent, isFalse);
  });

  test('una respuesta normal llega entera, con sus encabezados', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requests = server.listen((request) async {
      final body = await utf8DecoderStream(request);
      request.response
        ..statusCode = 201
        ..headers.set('content-range', '0-0/1')
        ..write('{"echo":$body}');
      await request.response.close();
    });
    addTearDown(() async {
      await requests.cancel();
      await server.close(force: true);
    });

    final response = await sender.send(
      http.Request('POST',
          Uri.parse('http://127.0.0.1:${server.port}/rest/v1/customers'))
        ..headers['content-type'] = 'application/json'
        ..body = '{"name":"Ana"}',
      headerTimeout: const Duration(seconds: 5),
      idleTimeout: const Duration(seconds: 5),
      freshConnection: true,
    );
    expect(response.statusCode, 201);
    expect(response.headers['content-range'], '0-0/1');
    expect(await response.stream.bytesToString(), '{"echo":{"name":"Ana"}}');
  });
}

Future<String> utf8DecoderStream(HttpRequest request) =>
    request.cast<List<int>>().transform(const SystemEncoding().decoder).join();
