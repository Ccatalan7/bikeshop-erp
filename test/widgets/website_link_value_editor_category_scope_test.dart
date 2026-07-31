import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vinabike_erp/modules/website/widgets/website_link_value_editor.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://127.0.0.1:54321',
      anonKey: 'test-anon-key',
    );
  });

  Future<void> pumpEditor(
    WidgetTester tester, {
    required String value,
    required ValueChanged<String> onChanged,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 520,
            child: WebsiteLinkValueEditor(
              label: '',
              value: value,
              onChanged: onChanged,
              categoryLoader: () async => const [
                WebsiteLinkCategoryOptionData(
                  id: 'cat-1',
                  name: 'Categoría de prueba',
                  fullPath: 'Categoría de prueba',
                  showOnWebsite: true,
                  markedWebProductCount: 1,
                  subtreeMarkedWebProductCount: 1,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('summary makes subtree and direct category semantics explicit',
      (tester) async {
    await pumpEditor(
      tester,
      value: '/productos/categoria/cadenas',
      onChanged: (_) {},
    );
    expect(find.text('Categoría y subcategorías'), findsOneWidget);

    await pumpEditor(
      tester,
      value: '/productos/categoria/cadenas?category_scope=direct&q=shimano',
      onChanged: (_) {},
    );
    expect(
      find.text('Solo productos asignados a esta categoría · "shimano"'),
      findsOneWidget,
    );
  });

  testWidgets('category destination hydrates and saves the selected scope',
      (tester) async {
    String? changedHref;
    await pumpEditor(
      tester,
      value: '/productos?category=cat-1&category_scope=direct',
      onChanged: (value) => changedHref = value,
    );

    await tester.tap(find.text('Solo productos asignados a esta categoría'));
    await tester.pumpAndSettle();

    final scopeField =
        find.byKey(const ValueKey<String>('website-catalog-category-scope'));
    expect(scopeField, findsOneWidget);
    await tester.tap(scopeField);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Categoría y subcategorías').last);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Aplicar'));
    await tester.pumpAndSettle();

    expect(changedHref, '/productos?category=cat-1');
  });

  testWidgets('composite catalog filter preserves direct category scope',
      (tester) async {
    String? changedHref;
    await pumpEditor(
      tester,
      value: '/productos?category=cat-1&search=maxxis&category_scope=direct',
      onChanged: (value) => changedHref = value,
    );

    await tester.tap(
      find.text('Solo productos asignados a esta categoría · "maxxis"'),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(
        const ValueKey<String>('website-catalog-category-scope'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Aplicar'));
    await tester.pumpAndSettle();

    expect(
      changedHref,
      '/productos?category=cat-1&q=maxxis&category_scope=direct',
    );
  });
}
