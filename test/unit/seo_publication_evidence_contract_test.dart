import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../scripts/generate_product_seo_snapshots.dart' as snapshots;

void main() {
  group('SEO publication source digests', () {
    test('are deterministic across owner row and map ordering', () {
      final baseline = _snapshot();
      final reordered = _snapshot(reverseRows: true);

      expect(reordered.ownerSourceRevision, baseline.ownerSourceRevision);
      expect(reordered.revision, baseline.revision);
      expect(reordered.ownerSourceSha256, baseline.ownerSourceSha256);
      expect(reordered.buildInputSha256, baseline.buildInputSha256);
      expect(
        baseline.ownerSourceSha256,
        sha256.convert(utf8.encode(baseline.ownerSourceRevision)).toString(),
      );
      expect(
        baseline.buildInputSha256,
        sha256.convert(utf8.encode(baseline.revision)).toString(),
      );
      expect(baseline.ownerSourceSha256, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(baseline.buildInputSha256, matches(RegExp(r'^[0-9a-f]{64}$')));
    });

    test('stock changes full build input but not the editorial owner source',
        () {
      final baseline = _snapshot(stock: 3);
      final stockChanged = _snapshot(stock: 2);

      expect(
        stockChanged.ownerSourceSha256,
        baseline.ownerSourceSha256,
      );
      expect(
        stockChanged.buildInputSha256,
        isNot(baseline.buildInputSha256),
      );
      expect(stockChanged.revision, isNot(baseline.revision));
    });

    test('an editorial owner change invalidates both digests', () {
      final baseline = _snapshot();
      final ownerChanged = _snapshot(storeName: 'Tienda revisada');

      expect(
        ownerChanged.ownerSourceSha256,
        isNot(baseline.ownerSourceSha256),
      );
      expect(
        ownerChanged.buildInputSha256,
        isNot(baseline.buildInputSha256),
      );
    });
  });

  group('generator publication evidence file', () {
    test('main writes evidence only after final CAS and before redirects', () {
      final source = File(
        'scripts/generate_product_seo_snapshots.dart',
      ).readAsStringSync();
      final finalCas = source.indexOf(
        'await assertSeoOwnerSourceSnapshotIsCurrent(',
      );
      final evidenceWrite = source.indexOf(
        'await writeSeoPublicationEvidenceFile(',
      );
      final redirectsApply = source.indexOf(
        'await firebaseRedirectPlan.apply();',
      );

      expect(finalCas, greaterThanOrEqualTo(0));
      expect(evidenceWrite, greaterThan(finalCas));
      expect(redirectsApply, greaterThan(evidenceWrite));
    });

    test('contains only both digests and replaces only prior valid evidence',
        () async {
      final temp = await Directory.systemTemp.createTemp(
        'seo-publication-evidence-',
      );
      addTearDown(() => temp.deleteSync(recursive: true));
      final output = File('${temp.path}/publication.json');
      final snapshot = _snapshot();

      await snapshots.writeSeoPublicationEvidenceFile(
        outputFile: output,
        ownerSourceSha256: snapshot.ownerSourceSha256,
        buildInputSha256: snapshot.buildInputSha256,
      );
      final decoded =
          jsonDecode(await output.readAsString()) as Map<String, dynamic>;
      expect(
        decoded,
        {
          'owner_source_sha256': snapshot.ownerSourceSha256,
          'build_input_sha256': snapshot.buildInputSha256,
        },
      );

      final prepared = snapshots.prepareSeoPublicationEvidenceOutput(
        output.path,
      );
      expect(prepared.path, output.path);
      expect(output.existsSync(), isFalse);
    });

    test('rejects malformed hashes and an unrelated existing output', () async {
      final temp = await Directory.systemTemp.createTemp(
        'seo-publication-invalid-',
      );
      addTearDown(() => temp.deleteSync(recursive: true));
      final output = File('${temp.path}/publication.json')
        ..writeAsStringSync('{"unrelated":true}\n');

      expect(
        () => snapshots.prepareSeoPublicationEvidenceOutput(output.path),
        throwsA(isA<FormatException>()),
      );
      expect(output.readAsStringSync(), '{"unrelated":true}\n');
      final malformed = File('${temp.path}/malformed.json')
        ..writeAsStringSync('private-marker-that-must-not-leak');
      try {
        snapshots.prepareSeoPublicationEvidenceOutput(malformed.path);
        fail('Malformed pre-existing evidence must fail closed.');
      } on FormatException catch (error) {
        expect(error.toString(), isNot(contains('private-marker')));
      }
      await expectLater(
        snapshots.writeSeoPublicationEvidenceFile(
          outputFile: File('${temp.path}/invalid.json'),
          ownerSourceSha256: 'not-a-hash',
          buildInputSha256: _digest('0'),
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('storefront release manifest v2', () {
    test('legacy push/manual invocation writes publication null', () async {
      final fixture = await _releaseFixture('legacy');
      addTearDown(() => fixture.root.deleteSync(recursive: true));

      final result = await _runReleaseWriter(
        fixture,
        [
          _commit('a'),
          'run-legacy',
          'github-actions',
          'false',
        ],
      );

      expect(result.exitCode, 0, reason: result.stderr.toString());
      final release = fixture.readRelease();
      expect(release['commit'], _commit('a'));
      expect(release['run'], 'run-legacy');
      expect(release['target'], 'store');
      expect(release['source'], 'github-actions');
      expect(release['dirty'], isFalse);
      expect(release['publication'], isNull);
      expect(release.containsKey('manifest_sha256'), isFalse);
      expect(fixture.checksumFile.readAsStringSync(), contains('release.json'));
    });

    test('publication metadata can be supplied through explicit environment',
        () async {
      final fixture = await _releaseFixture('publication');
      addTearDown(() => fixture.root.deleteSync(recursive: true));
      const requestId = '123e4567-e89b-12d3-a456-426614174000';

      final result = await _runReleaseWriter(
        fixture,
        [
          _commit('b'),
          'run-publication',
          'github-actions',
          'false',
        ],
        environment: {
          'STOREFRONT_PUBLICATION_REQUEST_ID': requestId.toUpperCase(),
          'STOREFRONT_PUBLICATION_OWNER_REVISION': '42',
          'STOREFRONT_OWNER_SOURCE_SHA256': _digest('A'),
          'STOREFRONT_BUILD_INPUT_SHA256': _digest('B'),
        },
      );

      expect(result.exitCode, 0, reason: result.stderr.toString());
      final publication =
          fixture.readRelease()['publication'] as Map<String, dynamic>;
      expect(publication, {
        'request_id': requestId,
        'owner_revision': 42,
        'owner_source_sha256': _digest('a'),
        'build_input_sha256': _digest('b'),
      });
    });

    test('rejects incomplete or invalid publication evidence before writing',
        () async {
      final cases = <List<String>>[
        [
          _commit('c'),
          'run-missing-request',
          'test',
          'false',
          '',
          '1',
          _digest('a'),
          _digest('b'),
        ],
        [
          _commit('c'),
          'run-invalid-request',
          'test',
          'false',
          'not-a-uuid',
          '1',
          _digest('a'),
          _digest('b'),
        ],
        [
          _commit('c'),
          'run-invalid-revision',
          'test',
          'false',
          '123e4567-e89b-12d3-a456-426614174000',
          '0',
          _digest('a'),
          _digest('b'),
        ],
        [
          _commit('c'),
          'run-invalid-hash',
          'test',
          'false',
          '123e4567-e89b-12d3-a456-426614174000',
          '1',
          'short',
          _digest('b'),
        ],
      ];

      for (var index = 0; index < cases.length; index++) {
        final fixture = await _releaseFixture('invalid-$index');
        addTearDown(() => fixture.root.deleteSync(recursive: true));
        final result = await _runReleaseWriter(fixture, cases[index]);

        expect(result.exitCode, 64, reason: 'case $index: ${result.stderr}');
        expect(fixture.releaseFile.existsSync(), isFalse);
      }
    });
  });
}

snapshots.SeoOwnerSourceSnapshot _snapshot({
  String storeName = 'Tienda',
  int stock = 3,
  bool reverseRows = false,
}) {
  List<Map<String, dynamic>> ordered(List<Map<String, dynamic>> rows) {
    return reverseRows ? rows.reversed.toList(growable: false) : rows;
  }

  final settings = snapshots.SeoWebsiteSettingsSource.fromRows(
    ordered([
      {
        'key': 'store_name',
        'value': storeName,
        'updated_at': '2026-07-28T10:00:00Z',
      },
      {
        'key': 'seo_meta_title',
        'value': 'Catálogo',
        'updated_at': '2026-07-28T10:01:00Z',
      },
    ]),
  );
  final products = ordered([
    {
      'id': 'product-1',
      'name': 'Producto uno',
      'price': 10000,
      'stock_quantity': stock,
      'inventory_qty': stock,
      'track_stock': true,
      'updated_at':
          stock == 3 ? '2026-07-28T10:02:00Z' : '2026-07-28T10:14:00Z',
    },
    {
      'id': 'product-2',
      'name': 'Producto dos',
      'price': 20000,
      'stock_quantity': 1,
      'inventory_qty': 1,
      'track_stock': true,
      'updated_at': '2026-07-28T10:03:00Z',
    },
  ]);
  final brands = ordered([
    {
      'id': 'brand-1',
      'name': 'Marca uno',
      'updated_at': '2026-07-28T10:04:00Z',
    },
    {
      'id': 'brand-2',
      'name': 'Marca dos',
      'updated_at': '2026-07-28T10:05:00Z',
    },
  ]);
  final categories = ordered([
    {
      'id': 'category-1',
      'name': 'Categoría uno',
      'show_on_website': true,
      'updated_at': '2026-07-28T10:06:00Z',
    },
    {
      'id': 'category-2',
      'name': 'Categoría dos',
      'show_on_website': false,
      'updated_at': '2026-07-28T10:07:00Z',
    },
  ]);
  final aliases = ordered([
    {
      'product_id': 'product-1',
      'alias_path': '/productos/producto-anterior',
      'created_at': '2026-07-28T10:08:00Z',
    },
    {
      'product_id': 'product-2',
      'alias_path': '/productos/producto-dos-anterior',
      'created_at': '2026-07-28T10:09:00Z',
    },
  ]);
  final pages = ordered([
    {
      'id': 'page-1',
      'slug': 'contacto',
      'title': 'Contacto',
      'updated_at': '2026-07-28T10:10:00Z',
    },
    {
      'id': 'page-2',
      'slug': 'nosotros',
      'title': 'Nosotros',
      'updated_at': '2026-07-28T10:11:00Z',
    },
  ]);
  final pageOneBlocks = ordered([
    {
      'id': 'block-1',
      'page_id': 'page-1',
      'block_type': 'text',
      'block_data': {'content': 'Contenido'},
      'updated_at': '2026-07-28T10:12:00Z',
    },
    {
      'id': 'block-2',
      'page_id': 'page-1',
      'block_type': 'text',
      'block_data': {'content': 'Otro contenido'},
      'updated_at': '2026-07-28T10:13:00Z',
    },
  ]);

  return snapshots.SeoOwnerSourceSnapshot(
    websiteSettings: settings,
    publishedProductOwners: products,
    publicAvailability: reverseRows
        ? {'product-2': 1, 'product-1': stock}
        : {'product-1': stock, 'product-2': 1},
    brandRows: brands,
    activeCategoryRows: categories,
    productUrlAliases: aliases,
    websiteContent: snapshots.SeoWebsiteContentSnapshot(
      pages: pages,
      pageBlocks: reverseRows
          ? {
              'page-2': const <Map<String, dynamic>>[],
              'page-1': pageOneBlocks,
            }
          : {
              'page-1': pageOneBlocks,
              'page-2': const <Map<String, dynamic>>[],
            },
    ),
  );
}

Future<_ReleaseFixture> _releaseFixture(String label) async {
  final root = await Directory.systemTemp.createTemp('release-v2-$label-');
  File('${root.path}/index.html').writeAsStringSync('<html></html>\n');
  return _ReleaseFixture(root);
}

Future<ProcessResult> _runReleaseWriter(
  _ReleaseFixture fixture,
  List<String> args, {
  Map<String, String> environment = const {},
}) {
  return Process.run(
    'bash',
    [
      File('scripts/write_storefront_release_evidence.sh').absolute.path,
      fixture.root.path,
      ...args,
    ],
    environment: environment,
    includeParentEnvironment: true,
  );
}

class _ReleaseFixture {
  const _ReleaseFixture(this.root);

  final Directory root;

  File get releaseFile => File('${root.path}/release.json');
  File get checksumFile => File('${root.path}/release.sha256');

  Map<String, dynamic> readRelease() {
    return jsonDecode(releaseFile.readAsStringSync()) as Map<String, dynamic>;
  }
}

String _commit(String character) => List<String>.filled(40, character).join();

String _digest(String character) => List<String>.filled(64, character).join();
