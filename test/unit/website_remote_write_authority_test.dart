import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:vinabike_erp/modules/website/models/website_editor_capability.dart';
import 'package:vinabike_erp/modules/website/models/website_page_models.dart';
import 'package:vinabike_erp/modules/website/providers/website_edit_mode_provider.dart';
import 'package:vinabike_erp/modules/website/services/website_service.dart';
import 'package:vinabike_erp/modules/website/widgets/website_editor_navigation_guard.dart';
import 'package:vinabike_erp/shared/services/tenant_service.dart';

const _tenantA = '00000000-0000-4000-8000-00000000000a';

WebsitePage _page() => WebsitePage(
      id: '',
      tenantId: _tenantA,
      slug: 'autoridad-remota',
      title: 'Autoridad remota',
      isPublished: true,
      createdAt: DateTime.utc(2026, 8, 9),
      updatedAt: DateTime.utc(2026, 8, 9),
    );

WebsiteService _service(http.Client client) => WebsiteService(
      supabase: SupabaseClient(
        'https://example.supabase.co',
        'test-anon-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: client,
      ),
      tenantService: TenantService.testing(
        currentUserId: () => null,
        profileLookup: (_) async => const <Map<String, dynamic>>[],
      ),
    );

void main() {
  test('authority is one-shot and its guard revalidates every checkpoint', () {
    var current = true;
    var claimCalls = 0;
    var currentChecks = 0;
    final authority = WebsiteEditorRemoteWriteAuthority(
      tenantId: _tenantA,
      operation: 'prueba',
      claimOwner: () {
        claimCalls++;
        return true;
      },
      isCurrent: () {
        currentChecks++;
        return current;
      },
    );

    final guard = authority.claimForWrite();
    guard();
    guard();
    expect(claimCalls, 1);
    expect(currentChecks, 4,
        reason: 'pre-claim, post-claim and both service checkpoints');

    expect(
      authority.claimForWrite,
      throwsA(isA<WebsiteEditorWriteSupersededException>()),
    );

    current = false;
    expect(
      guard,
      throwsA(isA<WebsiteEditorWriteSupersededException>()),
    );
  });

  test('host revision rejects A to B to A even when identities look equal', () {
    var hostRevision = 7;
    const capturedRevision = 7;
    final authority = WebsiteEditorRemoteWriteAuthority(
      tenantId: _tenantA,
      operation: 'prueba ABA',
      claimOwner: () => true,
      isCurrent: () => hostRevision == capturedRevision,
    );

    hostRevision = 8; // The host mounted B and then mounted A again.
    expect(
      authority.claimForWrite,
      throwsA(isA<WebsiteEditorWriteSupersededException>()),
    );
  });

  test('serial queue preserves rapid publication intent completion order',
      () async {
    final queue = WebsiteEditorRemoteWriteSerialQueue();
    final releaseFirst = Completer<void>();
    final events = <String>[];

    final publish = queue.schedule(() async {
      events.add('publish:start');
      await releaseFirst.future;
      events.add('publish:end');
    });
    final unpublish = queue.schedule(() async {
      events.add('unpublish:start');
      events.add('unpublish:end');
    });

    await Future<void>.delayed(Duration.zero);
    expect(events, const <String>['publish:start']);
    releaseFirst.complete();
    await Future.wait<void>(<Future<void>>[publish, unpublish]);
    expect(
      events,
      const <String>[
        'publish:start',
        'publish:end',
        'unpublish:start',
        'unpublish:end',
      ],
    );
  });

  test('a failed queued command cannot skip the next one', () async {
    final queue = WebsiteEditorRemoteWriteSerialQueue();
    final events = <String>[];
    final first = queue.schedule<void>(() async {
      events.add('first');
      throw StateError('network');
    });
    final second = queue.schedule<void>(() async {
      events.add('second');
    });

    await expectLater(first, throwsStateError);
    await second;
    expect(events, const <String>['first', 'second']);
  });

  test('publication and quick-create call only tenant-explicit guarded APIs',
      () {
    final source = File(
      'lib/public_store/widgets/public_store_layout.dart',
    ).readAsStringSync();
    final publicationStart = source.indexOf('Future<void> _setSitePublished(');
    final publicationEnd = source.indexOf(
      'void _toggleEditorMode(',
      publicationStart,
    );
    final publication = source.substring(publicationStart, publicationEnd);
    expect(
      publication.indexOf('captureSitewideAsyncIntent('),
      lessThan(publication.indexOf('_sitePublicationQueue.schedule(')),
    );
    expect(publication, contains('saveSettingsForTenant('));
    expect(publication, contains('authority.tenantId'));
    expect(publication, contains('writeGuard: writeGuard'));
    expect(
        publication, isNot(contains("saveSetting(\n      'site_published'")));

    final createStart =
        source.indexOf('Future<void> _showQuickCreatePageDialog(');
    final createEnd = source.indexOf(
      'Future<void> _loadPaymentCapabilities(',
      createStart,
    );
    final quickCreate = source.substring(createStart, createEnd);
    expect(
      quickCreate.indexOf('final tenantId ='),
      lessThan(quickCreate.indexOf('await showDialog<WebsitePage>(')),
    );
    expect(
      quickCreate.indexOf('final writeGuard = authority.claimForWrite()'),
      lessThan(quickCreate.indexOf('await websiteService.createPage(')),
    );
    expect(quickCreate, contains('tenantId: authority.tenantId'));
    expect(quickCreate, contains('writeGuard: writeGuard'));
  });

  test('custom-domain dialog claims the exact tenant owner before its write',
      () {
    final source = File(
      'lib/public_store/widgets/public_store_layout.dart',
    ).readAsStringSync();
    final start = source.indexOf('Future<void> _showDomainAndUrlDialog(');
    final end = source.indexOf(
      'Widget _buildUnpublishedSiteScaffold(',
      start,
    );
    final domain = source.substring(start, end);

    expect(domain, contains('captureSitewideAsyncIntent('));
    expect(domain, contains("sourceKeys: const <String>['custom_domain']"));
    expect(domain, contains('showDialog<_DomainDialogResult>('));
    expect(domain, contains('final writeGuard = authority.claimForWrite()'));
    expect(domain, contains("supabase.from('tenants').update"));
    expect(domain, contains(".eq('id', authority.tenantId)"));
    expect(domain, contains("isFilter('custom_domain', null)"));
    expect(
      domain.indexOf('captureSitewideAsyncIntent('),
      lessThan(domain.indexOf(".select('subdomain, custom_domain')")),
    );
    expect(
      domain.indexOf('showDialog<_DomainDialogResult>('),
      lessThan(domain.indexOf('final writeGuard = authority.claimForWrite()')),
    );
    expect(
      domain.indexOf('final writeGuard = authority.claimForWrite()'),
      lessThan(domain.indexOf("supabase.from('tenants').update")),
    );
    expect(domain, isNot(contains('_resolveTenantIdForSave')));
  });

  test('valid publication is one atomic tenant-A mutable statement', () async {
    final mutableBodies = <String>[];
    final service = _service(MockClient((request) async {
      if (request.method == 'POST') mutableBodies.add(request.body);
      return http.Response(
        request.method == 'GET' ? '[]' : '',
        200,
        headers: {'content-type': 'application/json'},
        request: request,
      );
    }));
    addTearDown(service.dispose);
    var current = true;
    var claims = 0;
    final authority = WebsiteEditorRemoteWriteAuthority(
      tenantId: _tenantA,
      operation: 'publicar',
      claimOwner: () {
        claims++;
        return true;
      },
      isCurrent: () => current,
    );

    await service.saveSettingsForTenant(
      authority.tenantId,
      const <String, String>{'site_published': 'true'},
      writeGuard: authority.claimForWrite(),
    );

    expect(claims, 1);
    expect(mutableBodies, hasLength(1));
    final rows = jsonDecode(mutableBodies.single) as List<dynamic>;
    expect(rows, hasLength(1));
    expect(rows.single['tenant_id'], _tenantA);
    expect(rows.single['key'], 'site_published');
    expect(rows.single['value'], 'true');

    current = false;
    expect(
      authority.ensureCurrent,
      throwsA(isA<WebsiteEditorWriteSupersededException>()),
    );
  });

  test('createPage guard rejection before request performs zero writes',
      () async {
    var requests = 0;
    final service = _service(MockClient((request) async {
      requests++;
      return http.Response('{}', 200);
    }));
    addTearDown(service.dispose);

    await expectLater(
      service.createPage(
        _page(),
        tenantId: _tenantA,
        writeGuard: () => throw const WebsiteEditorWriteSupersededException(
          'provider changed',
        ),
      ),
      throwsA(isA<WebsiteEditorWriteSupersededException>()),
    );
    expect(requests, 0);
  });

  test('quick-create provider supersession is rejected before remote write',
      () async {
    final providerA = WebsiteEditModeProvider()
      ..enterEditMode(
        const <Map<String, dynamic>>[],
        const <String, dynamic>{},
        pageId: 'home',
        pageSlug: '',
      );
    final providerB = WebsiteEditModeProvider()
      ..enterEditMode(
        const <Map<String, dynamic>>[],
        const <String, dynamic>{},
        pageId: 'home',
        pageSlug: '',
      );
    addTearDown(providerA.dispose);
    addTearDown(providerB.dispose);
    WebsiteEditModeProvider active = providerA;
    final decision = WebsiteEditorNavigationGuard.decisionForTesting(
      provider: providerA,
      intent: WebsiteEditorNavigationIntent.switchPage,
      discardOnCommit: false,
      resolveLiveProvider: () => active,
    );
    final authority = WebsiteEditorRemoteWriteAuthority(
      tenantId: _tenantA,
      operation: 'crear página',
      claimOwner: decision.claim,
      isCurrent: () => identical(active, providerA) && decision.isCurrent,
    );
    var requests = 0;
    final service = _service(MockClient((request) async {
      requests++;
      return http.Response('{}', 200);
    }));
    addTearDown(service.dispose);

    active = providerB;
    await expectLater(
      () async {
        final guard = authority.claimForWrite();
        await service.createPage(
          _page(),
          tenantId: authority.tenantId,
          writeGuard: guard,
        );
      }(),
      throwsA(isA<WebsiteEditorWriteSupersededException>()),
    );
    expect(requests, 0);
  });

  test('valid quick-create is one tenant-explicit insert', () async {
    var requests = 0;
    String? requestBody;
    final service = _service(MockClient((request) async {
      requests++;
      requestBody = request.body;
      return http.Response(
        jsonEncode(<String, dynamic>{
          'id': '00000000-0000-4000-8000-000000000099',
          'tenant_id': _tenantA,
          'slug': 'autoridad-remota',
          'title': 'Autoridad remota',
          'is_published': true,
          'is_home': false,
          'is_system': false,
          'template': 'default',
          'created_at': '2026-08-09T00:00:00.000Z',
          'updated_at': '2026-08-09T00:00:00.000Z',
        }),
        201,
        headers: {'content-type': 'application/json'},
        request: request,
      );
    }));
    addTearDown(service.dispose);
    final authority = WebsiteEditorRemoteWriteAuthority(
      tenantId: _tenantA,
      operation: 'crear página',
      claimOwner: () => true,
      isCurrent: () => true,
    );

    final created = await service.createPage(
      _page(),
      tenantId: authority.tenantId,
      writeGuard: authority.claimForWrite(),
    );

    expect(requests, 1);
    expect(created.tenantId, _tenantA);
    final inserted = jsonDecode(requestBody!) as Map<String, dynamic>;
    expect(inserted['tenant_id'], _tenantA);
  });

  test('createPage late A result is typed superseded and never adopted',
      () async {
    var requests = 0;
    final responseStarted = Completer<void>();
    final releaseResponse = Completer<void>();
    final service = _service(MockClient((request) async {
      requests++;
      responseStarted.complete();
      await releaseResponse.future;
      return http.Response(
        jsonEncode(<String, dynamic>{
          'id': '00000000-0000-4000-8000-000000000099',
          'tenant_id': _tenantA,
          'slug': 'autoridad-remota',
          'title': 'Autoridad remota',
          'is_published': true,
          'is_home': false,
          'is_system': false,
          'template': 'default',
          'created_at': '2026-08-09T00:00:00.000Z',
          'updated_at': '2026-08-09T00:00:00.000Z',
        }),
        201,
        headers: {'content-type': 'application/json'},
        request: request,
      );
    }));
    addTearDown(service.dispose);

    var current = true;
    final future = service.createPage(
      _page(),
      tenantId: _tenantA,
      writeGuard: () {
        if (!current) {
          throw const WebsiteEditorWriteSupersededException('tenant changed');
        }
      },
    );
    await responseStarted.future;
    current = false;
    releaseResponse.complete();

    await expectLater(
      future,
      throwsA(isA<WebsiteEditorWriteSupersededException>()),
    );
    expect(requests, 1,
        reason: 'the already-issued A request may be durable server-side');
    expect(service.pages, isEmpty,
        reason: 'A response must never be adopted into the live projection');
  });
}
