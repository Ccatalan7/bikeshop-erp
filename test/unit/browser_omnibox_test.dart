import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/utils/browser_omnibox.dart';

void main() {
  test('visited supplier domains rank from a short prefix', () {
    expect(
      browserSiteMatchRank(
        query: 'comer',
        host: 'comercialciclo.cl',
        title: 'Comercial Ciclo',
        url: 'https://comercialciclo.cl',
      ),
      1,
    );
    expect(
      browserSiteMatchRank(
        query: 'comercialciclo.cl',
        host: 'www.comercialciclo.cl',
        title: 'Comercial Ciclo',
        url: 'https://www.comercialciclo.cl',
      ),
      0,
    );
  });

  test('title and URL matches remain available without false positives', () {
    expect(
      browserSiteMatchRank(
        query: 'comercial',
        host: 'proveedor.example',
        title: 'Comercial Ciclo',
        url: 'https://proveedor.example/catalogo',
      ),
      2,
    );
    expect(
      browserSiteMatchRank(
        query: 'shimano',
        host: 'comercialciclo.cl',
        title: 'Comercial Ciclo',
        url: 'https://comercialciclo.cl',
      ),
      -1,
    );
  });

  test('inline completion selects only the untyped domain suffix', () {
    final completion = browserInlineHostCompletion(
      query: 'com',
      rankedHosts: const [
        'google.com',
        'www.comercialciclo.cl',
        'comercialotro.cl',
      ],
    );

    expect(completion, isNotNull);
    expect(completion!.value, 'comercialciclo.cl');
    expect(completion.selectionStart, 3);
    expect(completion.selectionEnd, 'comercialciclo.cl'.length);
  });

  test('inline completion preserves an explicitly typed www prefix', () {
    final completion = browserInlineHostCompletion(
      query: 'www.com',
      rankedHosts: const ['www.comercialciclo.cl'],
    );

    expect(completion?.value, 'www.comercialciclo.cl');
    expect(completion?.selectionStart, 'www.com'.length);
  });

  test('inline completion ignores searches and completed domains', () {
    expect(
      browserInlineHostCompletion(
        query: 'comercial ciclo',
        rankedHosts: const ['comercialciclo.cl'],
      ),
      isNull,
    );
    expect(
      browserInlineHostCompletion(
        query: 'comercialciclo.cl',
        rankedHosts: const ['comercialciclo.cl'],
      ),
      isNull,
    );
  });
}
