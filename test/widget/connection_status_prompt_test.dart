import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:vinabike_erp/shared/services/network/network_resilience.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';
import 'package:vinabike_erp/shared/widgets/connection_status_prompt.dart';

class _MemoryStore implements UnsavedChangesStore {
  final Map<String, String> values = {};
  @override
  Future<Map<String, String>> readAll() async => Map.of(values);
  @override
  Future<void> remove(String id) async => values.remove(id);
  @override
  Future<void> write(String id, String value) async => values[id] = value;
}

/// Lo que el ERP muestra de la conexión: nunca «guardado» si no llegó.
void main() {
  late ConnectionStatus status;
  late UnsavedChangesJournal journal;

  setUp(() {
    status = ConnectionStatus(slowAfter: const Duration(milliseconds: 50));
    journal = UnsavedChangesJournal(
      store: _MemoryStore(),
      currentUserId: () => 'usuario-1',
      currentAccessToken: () => 'token',
      apiKey: 'llave',
    );
  });

  tearDown(() {
    journal.dispose();
    status.dispose();
  });

  Future<void> pump(WidgetTester tester,
      {Brightness brightness = Brightness.light}) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.resolve(
        preset: AppearancePresets.all.first,
        brightness: brightness,
      ),
      home: Scaffold(
        body: Stack(children: [
          const SizedBox.expand(),
          ConnectionStatusPrompt(status: status, journal: journal),
        ]),
      ),
    ));
  }

  Future<void> recordFailure(String name, {bool notSent = false}) async {
    final request = http.Request(
      'POST',
      Uri.parse('https://demo.supabase.co/rest/v1/customers'),
    )..body = jsonEncode({'name': name});
    await journal.record(
      request: request,
      safety: classifyRequest('POST', request.url, body: request.bodyBytes),
      body: request.bodyBytes,
      notSent: notSent,
      error: 'SocketException: Connection reset by peer',
    );
  }

  testWidgets('sin nada que decir no ocupa lugar', (tester) async {
    await pump(tester);
    expect(find.textContaining('Sin conexión'), findsNothing);
    expect(find.textContaining('sin guardar'), findsNothing);
  });

  for (final brightness in Brightness.values) {
    testWidgets('sin conexión dice que reintenta (${brightness.name})',
        (tester) async {
      await pump(tester, brightness: brightness);
      status.reportUnreachable();
      await tester.pumpAndSettle();
      expect(find.textContaining('Sin conexión'), findsOneWidget);
      expect(find.textContaining('Reintentando'), findsOneWidget);
      expect(find.text('Probar ahora'), findsOneWidget);
      // El lector de pantalla no oye «Reintentando….».
      expect(
        find.bySemanticsLabel('Sin conexión. Reintentando… Probar ahora'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('al volver avisa y después se va', (tester) async {
    await pump(tester);
    status.reportUnreachable();
    await tester.pumpAndSettle();
    status.reportReachable();
    await tester.pump();
    expect(find.textContaining('Conexión recuperada'), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(find.textContaining('Conexión recuperada'), findsNothing);
  });

  testWidgets('un guardado lento lo dice mientras espera', (tester) async {
    await pump(tester);
    final token = status.beginWrite();
    await tester.pump(const Duration(milliseconds: 80));
    expect(find.textContaining('Guardando'), findsOneWidget);
    expect(find.textContaining('lenta'), findsOneWidget);
    status.endWrite(token);
    await tester.pumpAndSettle();
    expect(find.textContaining('Guardando'), findsNothing);
  });

  testWidgets('lo que no llegó queda a la vista hasta que se resuelve',
      (tester) async {
    await pump(tester);
    await recordFailure('Juan Pérez');
    await tester.pumpAndSettle();
    expect(find.textContaining('1 cambio sin guardar', findRichText: true),
        findsOneWidget);

    await tester
        .tap(find.textContaining('1 cambio sin guardar', findRichText: true));
    await tester.pumpAndSettle();
    expect(find.text('Cliente · Juan Pérez'), findsOneWidget);
    expect(find.textContaining('Puede que haya llegado'), findsOneWidget);
    expect(
        find.textContaining('revisa que no esté ya guardado'), findsOneWidget);

    await tester.tap(find.text('Descartar'));
    await tester.pumpAndSettle();
    expect(find.text('¿Descartarlo? No se va a guardar.'), findsOneWidget);
    await tester.tap(find.text('Descartar'));
    await tester.pumpAndSettle();
    expect(journal.pendingCount, 0);
    expect(
        find.text('No queda nada pendiente en este equipo.'), findsOneWidget);
  });

  testWidgets('en el teléfono lo que no se corta es cuánto quedó sin guardar',
      (tester) async {
    // El ancho que lee la pantalla es el de la vista, no el de la superficie.
    tester.view
      ..physicalSize = const Size(400, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.resolve(
        preset: AppearancePresets.all.first,
        brightness: Brightness.dark,
      ),
      home: Scaffold(
        body: Stack(children: [
          const SizedBox.expand(),
          ConnectionStatusPrompt(status: status, journal: journal),
        ]),
      ),
    ));
    await recordFailure('Ana', notSent: true);
    status.reportUnreachable();
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Sin conexión. 1 sin guardar. Revisar'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sin conexión y con pendientes, el aviso lleva a revisarlos',
      (tester) async {
    await pump(tester);
    await recordFailure('Ana', notSent: true);
    status.reportUnreachable();
    await tester.pumpAndSettle();
    expect(find.textContaining('1 sin guardar', findRichText: true),
        findsOneWidget);
    expect(find.text('Revisar'), findsOneWidget);
  });
}
