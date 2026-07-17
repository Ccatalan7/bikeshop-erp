import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vinabike_erp/shared/services/browser_site_memory_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('a supplier visited in one tab is available to the next tab', () async {
    await BrowserSiteMemoryService.recordVisit(
      userId: 'staff-a',
      url: 'https://www.comercialciclo.cl/productos/cadenas',
      title: 'Comercial Ciclo',
      visitedAt: DateTime.utc(2026, 7, 17, 10),
    );

    final sitesFromAnotherTab = await BrowserSiteMemoryService.load('staff-a');

    expect(sitesFromAnotherTab, hasLength(1));
    expect(sitesFromAnotherTab.single.host, 'www.comercialciclo.cl');
    expect(
      sitesFromAnotherTab.single.origin,
      'https://www.comercialciclo.cl',
    );
    expect(
      sitesFromAnotherTab.single.lastUrl,
      'https://www.comercialciclo.cl/productos/cadenas',
    );
    expect(sitesFromAnotherTab.single.title, 'Comercial Ciclo');
    expect(await BrowserSiteMemoryService.load('staff-b'), isEmpty);
  });

  test('repeat visits strengthen one domain instead of duplicating it',
      () async {
    await BrowserSiteMemoryService.recordVisit(
      userId: 'staff-repeat',
      url: 'https://comercialciclo.cl/',
      title: 'Comercial Ciclo',
    );
    await BrowserSiteMemoryService.recordVisit(
      userId: 'staff-repeat',
      url: 'https://comercialciclo.cl/catalogo',
      title: 'Catálogo Comercial Ciclo',
    );

    final sites = await BrowserSiteMemoryService.load('staff-repeat');
    expect(sites, hasLength(1));
    expect(sites.single.visitCount, 2);
    expect(sites.single.title, 'Catálogo Comercial Ciclo');
    expect(sites.single.lastUrl, 'https://comercialciclo.cl/catalogo');
  });

  test('a root visit does not replace the last useful authenticated page',
      () async {
    await BrowserSiteMemoryService.recordVisit(
      userId: 'staff-session',
      url: 'https://www.comercialciclo.cl/Home?temporary=secret#account',
      title: 'Comercial Ciclo Home',
    );
    await BrowserSiteMemoryService.recordVisit(
      userId: 'staff-session',
      url: 'https://www.comercialciclo.cl/',
      title: 'Comercial Ciclo Inicio',
    );

    final site = (await BrowserSiteMemoryService.load('staff-session')).single;
    expect(site.lastUrl, 'https://www.comercialciclo.cl/Home');
    expect(site.title, 'Comercial Ciclo Home');
  });

  test('legacy domain memory without a last URL remains readable', () {
    final legacy = BrowserSiteMemoryEntry.tryDecode(
      '{"origin":"https://comercialciclo.cl","host":"comercialciclo.cl",'
      '"title":"Comercial Ciclo","lastVisitedAt":"2026-07-17T10:00:00Z",'
      '"visitCount":2}',
    );

    expect(legacy?.lastUrl, 'https://comercialciclo.cl');
  });

  test('existing URL history seeds the domain memory once', () async {
    final sites = await BrowserSiteMemoryService.mergeFromHistory(
      userId: 'staff-legacy',
      history: [
        BrowserVisitedPage(
          url: 'https://comercialciclo.cl/productos',
          title: 'Productos',
          visitedAt: DateTime.utc(2026, 7, 16),
        ),
      ],
    );

    expect(sites.single.origin, 'https://comercialciclo.cl');
    expect(sites.single.lastUrl, 'https://comercialciclo.cl/productos');
    expect(
      await BrowserSiteMemoryService.mergeFromHistory(
        userId: 'staff-legacy',
        history: const [],
      ),
      hasLength(1),
    );
  });

  test('legacy root-only memory adopts a useful route without recounting',
      () async {
    SharedPreferences.setMockInitialValues({
      'vinabike_browser_sites_v1::staff-migrate': [
        '{"origin":"https://www.comercialciclo.cl",'
            '"host":"www.comercialciclo.cl",'
            '"title":"Comercial Ciclo",'
            '"lastVisitedAt":"2026-07-17T10:00:00Z",'
            '"visitCount":4}',
      ],
    });

    final sites = await BrowserSiteMemoryService.mergeFromHistory(
      userId: 'staff-migrate',
      history: [
        BrowserVisitedPage(
          url: 'https://www.comercialciclo.cl/Home?temporary=secret',
          title: 'Comercial Ciclo Home',
          visitedAt: DateTime.utc(2026, 7, 17, 11),
        ),
      ],
    );

    expect(sites.single.lastUrl, 'https://www.comercialciclo.cl/Home');
    expect(sites.single.title, 'Comercial Ciclo Home');
    expect(sites.single.visitCount, 4);
  });
}
