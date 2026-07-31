import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import '../support/library_source.dart';

/// Single-writer contract for `product_categories.show_on_website`.
///
/// Publication has exactly one productive writer: Catálogo web →
/// `WebsiteService.replaceWebsiteCategoryVisibility` → the atomic, audited,
/// tenant-serialized RPC `replace_website_category_visibility`. History shows
/// how competing writers accumulate silently: a dormant row-by-row editor
/// save, two never-called CategoryService bulk methods, and a form
/// `toJson()` that let a stale in-memory copy overwrite a concurrent
/// publication change. This guard fails the build when any of them returns.
void main() {
  final libFiles = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'))
      .toList(growable: false);

  group('category publication single writer', () {
    test('the canonical wrapper delegates to the atomic RPC', () {
      final service = readLibrarySource('lib/modules/website/services/website_service.dart');
      final wrapper =
          service.split('Future<void> replaceWebsiteCategoryVisibility')[1];
      // El cierre del método es '}' en su propia línea; '}) async {' no.
      final wrapperBody = wrapper.split('\n  }\n')[0];
      expect(wrapperBody, contains('.rpc('));
      expect(
        wrapperBody,
        contains("'replace_website_category_visibility'"),
      );
      expect(wrapperBody, isNot(contains(".from('product_categories')")));
    });

    test('no lib file writes show_on_website near product_categories', () {
      // A write is the map-key form `'show_on_website':`. Read filters
      // (`.eq('show_on_website', …)`) and JSON parsing (`json['…']`) never
      // use the colon form. Proximity to the table name is what separates a
      // category write from the products-table publication commands, which
      // have their own canonical owner.
      const windowChars = 600;
      final offenders = <String>[];
      for (final file in libFiles) {
        final source = file.readAsStringSync();
        var searchFrom = 0;
        while (true) {
          final tableIndex = source.indexOf('product_categories', searchFrom);
          if (tableIndex < 0) break;
          final windowEnd = tableIndex + windowChars > source.length
              ? source.length
              : tableIndex + windowChars;
          if (source.substring(tableIndex, windowEnd).contains(
                "'show_on_website':",
              )) {
            offenders.add(file.path);
            break;
          }
          searchFrom = tableIndex + 1;
        }
      }
      expect(
        offenders,
        isEmpty,
        reason: 'show_on_website solo se escribe por el RPC canónico; usa '
            'WebsiteService.replaceWebsiteCategoryVisibility.',
      );
    });

    test('the dead CategoryService writers stay dead', () {
      final service =
          File('lib/modules/inventory/services/category_service.dart')
              .readAsStringSync();
      expect(service, isNot(contains('toggleWebsiteVisibility')));
      expect(service, isNot(contains('setWebsiteCategories')));
      expect(service, isNot(contains("'show_on_website':")));
      // Form saves persist through the explicit payload, never raw toJson.
      expect(service, contains('category.toPersistencePayload()'));
      expect(service, contains('updatedCategory.toPersistencePayload()'));
      expect(service, isNot(contains('.toJson()')));
    });

    test('the persistence payload cannot carry publication', () {
      final model = File('lib/modules/inventory/models/category_models.dart')
          .readAsStringSync();
      expect(
        model,
        contains("return toJson()..remove('show_on_website');"),
      );
      // The field stays readable for projections and diagnostics.
      expect(model, contains('showOnWebsite: json['));
      expect(model, contains('bool? showOnWebsite,'));
    });

    test('the editor keeps no dormant category-visibility state', () {
      final provider = File(
        'lib/modules/website/providers/website_edit_mode_provider.dart',
      ).readAsStringSync();
      expect(provider, isNot(contains('pendingCategoryVisibility')));
      expect(provider, isNot(contains('updateCategoryVisibility')));
      expect(provider, isNot(contains('hasCategoryChanges')));

      // Partitioned libraries are read whole (main + parts) so the physical
      // F6 partition can never weaken this contract.
      final saveConsumers = [
        'lib/public_store/widgets/public_store_layout.dart',
        'lib/public_store/widgets/persistent_editor_shell.dart',
        'lib/modules/website/services/website_service.dart',
      ];
      for (final path in saveConsumers) {
        expect(
          readLibrarySource(path),
          isNot(contains('pendingCategoryVisibility')),
          reason: path,
        );
      }
    });
  });
}
