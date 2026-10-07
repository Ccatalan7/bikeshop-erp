import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:vinabike_erp/modules/website/providers/website_edit_mode_provider.dart';
import 'package:vinabike_erp/shared/routes/public_store_shell_page.dart';

/// Stands for a store page whose data or images keep arriving after the
/// operator has already opened the next page.
class _ChangingPage extends StatefulWidget {
  const _ChangingPage({
    required this.changes,
    required this.label,
    required this.alive,
  });

  final ValueNotifier<int> changes;
  final String label;
  final Set<String> alive;

  @override
  State<_ChangingPage> createState() => _ChangingPageState();
}

class _ChangingPageState extends State<_ChangingPage> {
  @override
  void initState() {
    super.initState();
    widget.alive.add(widget.label);
    widget.changes.addListener(_onChange);
  }

  void _onChange() => setState(() {});

  @override
  void dispose() {
    widget.changes.removeListener(_onChange);
    widget.alive.remove(widget.label);
    super.dispose();
  }

  // A different root on every change, like loading → content.
  @override
  Widget build(BuildContext context) => widget.changes.value.isEven
      ? SizedBox(height: 300, child: Text(widget.label))
      : ColoredBox(
          color: Colors.black12,
          child: SizedBox(height: 500, child: Text(widget.label)),
        );
}

void main() {
  // The ERP-mounted store puts the shell's navigator inside one scroll view,
  // so its overlay is sized by the page on top and never lays out a covered
  // one. With a kept (`maintainState`) page, the second change of the covered
  // catalog threw `_debugRelayoutBoundaryAlreadyMarkedNeedsLayout` during
  // layout and froze the debug app (Flutter 3.38.5, 2026-10-06).
  testWidgets(
      'a store page covered by the next one is not kept, and comes back '
      'when the operator returns', (tester) async {
    final catalogChanges = ValueNotifier<int>(0);
    final categoryChanges = ValueNotifier<int>(0);
    addTearDown(catalogChanges.dispose);
    addTearDown(categoryChanges.dispose);
    final alive = <String>{};

    final router = GoRouter(
      initialLocation: '/tienda/productos',
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, shell) => Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [const SizedBox(height: 80), shell],
              ),
            ),
          ),
          branches: [
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/tienda/productos',
                  pageBuilder: (context, state) => buildPublicStoreShellPage(
                    'productos',
                    _ChangingPage(
                      changes: catalogChanges,
                      label: 'catalogo',
                      alive: alive,
                    ),
                  ),
                  routes: [
                    GoRoute(
                      path: 'categoria/:category',
                      pageBuilder: (context, state) =>
                          buildPublicStoreShellPage(
                        'categoria',
                        _ChangingPage(
                          changes: categoryChanges,
                          label: 'categoria',
                          alive: alive,
                        ),
                      ),
                    ),
                    GoRoute(
                      path: ':slug/:sku',
                      pageBuilder: (context, state) =>
                          buildPublicStoreShellPage(
                        'producto',
                        const SizedBox(height: 400, child: Text('ficha')),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    final editMode = WebsiteEditModeProvider();
    addTearDown(editMode.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: editMode,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('catalogo'), findsOneWidget);

    router.go('/tienda/productos/categoria/accesorios');
    await tester.pumpAndSettle();
    expect(find.text('categoria'), findsOneWidget);
    expect(find.text('catalogo', skipOffstage: false), findsNothing);
    expect(alive, {'categoria'});

    // What used to freeze the app: the covered catalog changing twice.
    for (var i = 0; i < 2; i++) {
      catalogChanges.value++;
      categoryChanges.value++;
      await tester.pump();
      expect(tester.takeException(), isNull);
    }

    router.go('/tienda/productos/horquilla-suntour/SKU-1');
    await tester.pumpAndSettle();
    expect(find.text('ficha'), findsOneWidget);
    expect(alive, isEmpty);
    for (var i = 0; i < 2; i++) {
      categoryChanges.value++;
      await tester.pump();
      expect(tester.takeException(), isNull);
    }

    router.go('/tienda/productos');
    await tester.pumpAndSettle();
    expect(find.text('catalogo'), findsOneWidget);
    expect(alive, {'catalogo'});
    expect(tester.takeException(), isNull);
  });
}
