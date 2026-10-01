import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vinabike_erp/shared/routes/workspace_page_key.dart';

/// Con PG-00596 abierto, elegir PG-00594 en el buscador global no cambiaba la
/// pantalla (dueño, 2026-10-01): el buscador navega con `go`, y go_router le
/// da a toda ficha `/taller/pegas/:id` la misma `pageKey`, así que la página
/// y su `State` —que lee su trabajo en `initState`— se reutilizaban.

/// Una ficha que, como el formulario del trabajo, lee su registro una vez.
class _Record extends StatefulWidget {
  const _Record(this.id);

  final String id;

  @override
  State<_Record> createState() => _RecordState();
}

class _RecordState extends State<_Record> {
  late final String loaded = widget.id;

  @override
  Widget build(BuildContext context) => Text('ficha $loaded');
}

GoRouter _router(LocalKey Function(GoRouterState state) key) => GoRouter(
      initialLocation: '/taller/pegas/596',
      routes: [
        GoRoute(
          path: '/taller/pegas/:id',
          pageBuilder: (context, state) => NoTransitionPage<void>(
            key: key(state),
            child: _Record(state.pathParameters['id']!),
          ),
        ),
      ],
    );

Future<GoRouter> _pump(
  WidgetTester tester,
  LocalKey Function(GoRouterState state) key,
) async {
  final router = _router(key);
  addTearDown(router.dispose);
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.pumpAndSettle();
  return router;
}

void main() {
  testWidgets('con la llave de go_router, ir a otra ficha deja la primera',
      (tester) async {
    // El mecanismo, para que la razón no se pierda.
    final router = await _pump(tester, (state) => state.pageKey);
    router.go('/taller/pegas/594');
    await tester.pumpAndSettle();
    expect(find.text('ficha 596'), findsOneWidget);
  });

  testWidgets('con la ruta concreta, ir a otra ficha la abre', (tester) async {
    final router = await _pump(tester, workspacePageKey);
    expect(find.text('ficha 596'), findsOneWidget);
    router.go('/taller/pegas/594');
    await tester.pumpAndSettle();
    expect(find.text('ficha 594'), findsOneWidget);
  });

  testWidgets('la misma ficha conserva su estado y push sigue siendo único',
      (tester) async {
    final router = await _pump(tester, workspacePageKey);
    // Otra pestaña de la misma ficha (sólo cambia la consulta) no la reinicia.
    router.go('/taller/pegas/596?tab=productos');
    await tester.pumpAndSettle();
    expect(find.text('ficha 596'), findsOneWidget);
    // La misma ficha apilada dos veces no choca por llave duplicada.
    router.push('/taller/pegas/596');
    await tester.pumpAndSettle();
    router.push('/taller/pegas/596');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('ficha 596', skipOffstage: false), findsNWidgets(3));
  });
}
