// ignore_for_file: prefer_const_literals_to_create_immutables

import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vinabike_erp/modules/purchases/models/supplier_foundation.dart';
import 'package:vinabike_erp/modules/purchases/services/supplier_relationship_service.dart';
import 'package:vinabike_erp/shared/models/supplier.dart';
import 'package:vinabike_erp/shared/models/supplier_ocr_template.dart';
import 'package:vinabike_erp/shared/services/authority_scoped_cache.dart';
import 'package:vinabike_erp/shared/services/tenant_service.dart';

void main() {
  const tenantA = '10000000-0000-0000-0000-000000000001';
  const tenantB = '90000000-0000-0000-0000-000000000009';

  test('profile list paginates deterministically beyond one server page',
      () async {
    final repository = _FakeRelationshipRepository(
      profiles: List.generate(
        501,
        (index) => _profileRow(
          tenantId: tenantA,
          supplierId: _uuid(index + 1),
          partyId: _uuid(index + 1001),
          name: 'Supplier ${index.toString().padLeft(4, '0')}',
        ),
      ),
    );
    final service = SupplierRelationshipService(
      tenantService: _tenantService({'user-a': tenantA}),
      repository: repository,
      legacyRepository: _FakeLegacyRepository(),
    );

    final profiles = await service.listSupplierProfiles();

    expect(profiles, hasLength(501));
    expect(repository.profileOffsets, [0, 500]);
    expect(repository.profileLimits, [501, 501]);
  });

  test('profile list keeps one authority lease across every page', () async {
    var currentUserId = 'user-a';
    final repository = _FakeRelationshipRepository(
      profileLoader: ({
        required tenantId,
        required activeOnly,
        required offset,
        required limit,
      }) async {
        if (offset == 0) {
          return _AfterAnyList(
            List.generate(
              501,
              (index) => _profileRow(
                tenantId: tenantA,
                supplierId: _uuid(index + 1),
                partyId: _uuid(index + 1001),
                name: 'Tenant A $index',
              ),
            ),
            () => currentUserId = 'user-b',
          );
        }
        return [
          _profileRow(
            tenantId: tenantId,
            supplierId: _uuid(9001),
            partyId: _uuid(9002),
            name: 'Tenant B result',
          ),
        ];
      },
    );
    final service = SupplierRelationshipService(
      tenantService: TenantService.testing(
        currentUserId: () => currentUserId,
        profileLookup: (userId) async => [
          {
            'tenant_id': userId == 'user-a' ? tenantA : tenantB,
            'role': 'admin',
            'permissions': const {},
          },
        ],
      ),
      repository: repository,
      legacyRepository: _FakeLegacyRepository(),
    );

    await expectLater(
      service.listSupplierProfiles(),
      throwsA(isA<AuthorityScopeChangedException>()),
    );

    expect(repository.profileTenantIds, [tenantA]);
  });

  test('missing foundation uses explicit secret-free legacy read-only profile',
      () async {
    final now = DateTime.utc(2026, 8, 8);
    final legacyRepository = _FakeLegacyRepository(
      suppliers: [
        Supplier(
          id: _uuid(1),
          tenantId: tenantA,
          name: 'Legacy supplier',
          createdAt: now,
          updatedAt: now,
        ),
      ],
    );
    final service = SupplierRelationshipService(
      tenantService: _tenantService({'user-a': tenantA}),
      repository: _FakeRelationshipRepository(foundationMissing: true),
      legacyRepository: legacyRepository,
    );

    final page = await service.listSupplierProfilesPage();

    expect(page.items, hasLength(1));
    expect(
        page.items.single.dataSource, SupplierProfileDataSource.legacyReadOnly);
    expect(page.items.single.classificationWritesAvailable, isFalse);
  });

  test('profile timeout preserves the secret-free legacy directory', () async {
    final now = DateTime.utc(2026, 8, 9);
    final legacyRepository = _FakeLegacyRepository(
      suppliers: [
        Supplier(
          id: _uuid(11),
          tenantId: tenantA,
          name: 'Available during profile rollout',
          createdAt: now,
          updatedAt: now,
        ),
      ],
    );
    final service = SupplierRelationshipService(
      tenantService: _tenantService({'user-a': tenantA}),
      repository: _FakeRelationshipRepository(
        profileLoader: ({
          required tenantId,
          required activeOnly,
          required offset,
          required limit,
        }) async =>
            throw const PostgrestException(
          message: 'canceling statement due to statement timeout',
          code: '57014',
        ),
      ),
      legacyRepository: legacyRepository,
    );

    final page = await service.listSupplierProfilesPage();

    expect(page.items, hasLength(1));
    expect(
      page.items.single.dataSource,
      SupplierProfileDataSource.legacyReadOnly,
    );
    expect(page.items.single.displayName, 'Available during profile rollout');
  });

  test('generic PGRST200 relationship errors never masquerade as migration',
      () async {
    final service = SupplierRelationshipService(
      tenantService: _tenantService({'user-a': tenantA}),
      repository: _FakeRelationshipRepository(
        profileLoader: ({
          required tenantId,
          required activeOnly,
          required offset,
          required limit,
        }) async =>
            throw const PostgrestException(
          message: 'Could not find a relationship between resources',
          code: 'PGRST200',
        ),
      ),
      legacyRepository: _FakeLegacyRepository(
        suppliers: [
          Supplier(
            id: _uuid(12),
            tenantId: tenantA,
            name: 'Must not mask failure',
            createdAt: DateTime(2026, 8, 8),
            updatedAt: DateTime(2026, 8, 8),
          ),
        ],
      ),
    );

    await expectLater(
      service.listSupplierProfilesPage(),
      throwsA(
        isA<PostgrestException>().having(
          (error) => error.code,
          'code',
          'PGRST200',
        ),
      ),
    );
  });

  test('economic timeline has a scoped empty page for inactive suppliers',
      () async {
    final supplierId = _uuid(20);
    final service = SupplierRelationshipService(
      tenantService: _tenantService({'user-a': tenantA}),
      repository: _FakeRelationshipRepository(),
      legacyRepository: _FakeLegacyRepository(),
    );

    final page = await service.getEconomicTimelinePage(supplierId);

    expect(page.timeline.tenantId, tenantA);
    expect(page.timeline.supplierId, supplierId);
    expect(page.timeline.activities, isEmpty);
    expect(page.hasMore, isFalse);
  });

  test('economic timeline paginates recognized activity before applying limit',
      () async {
    final supplierId = _uuid(21);
    final repository = _FakeRelationshipRepository(
      economicTimeline: [
        for (var index = 0; index < 50; index++)
          _economicRow(
            tenantId: tenantA,
            supplierId: supplierId,
            eventId: _uuid(index + 4000),
            recognized: false,
          ),
        _economicRow(
          tenantId: tenantA,
          supplierId: supplierId,
          eventId: _uuid(4999),
          recognized: true,
        ),
      ],
    );
    final service = SupplierRelationshipService(
      tenantService: _tenantService({'user-a': tenantA}),
      repository: repository,
      legacyRepository: _FakeLegacyRepository(),
    );

    final page = await service.getEconomicTimelinePage(
      supplierId,
      limit: 50,
    );

    expect(repository.timelineRecognizedOnly, [true]);
    expect(page.timeline.activities, hasLength(1));
    expect(page.timeline.activities.single.id, _uuid(4999));
  });

  test('late list response cannot cross an auth and tenant lease', () async {
    var currentUserId = 'user-a';
    final completer = Completer<List<Map<String, dynamic>>>();
    final repository = _FakeRelationshipRepository(
      profileLoader: ({
        required tenantId,
        required activeOnly,
        required offset,
        required limit,
      }) =>
          completer.future,
    );
    final tenantService = TenantService.testing(
      currentUserId: () => currentUserId,
      profileLookup: (userId) async => [
        {
          'tenant_id': userId == 'user-a' ? tenantA : tenantB,
          'role': 'admin',
          'permissions': const {},
        },
      ],
    );
    final service = SupplierRelationshipService(
      tenantService: tenantService,
      repository: repository,
      legacyRepository: _FakeLegacyRepository(),
    );

    final pending = service.listSupplierProfilesPage();
    await repository.profileRequestStarted.future;
    currentUserId = 'user-b';
    completer.complete([
      _profileRow(
        tenantId: tenantA,
        supplierId: _uuid(1),
        partyId: _uuid(2),
        name: 'Old authority',
      ),
    ]);

    await expectLater(
      pending,
      throwsA(isA<AuthorityScopeChangedException>()),
    );
  });

  test('classification catalog returns tenant definitions, not free strings',
      () async {
    final repository = _FakeRelationshipRepository(
      definitions: {
        SupplierClassificationDefinitionKind.role: [
          _definitionRow(
            tenantId: tenantA,
            id: _uuid(40),
            code: 'goods_vendor',
            label: 'Proveedor de bienes',
          ),
        ],
      },
    );
    final service = SupplierRelationshipService(
      tenantService: _tenantService({'user-a': tenantA}),
      repository: repository,
      legacyRepository: _FakeLegacyRepository(),
    );

    final catalog = await service.getClassificationCatalog();

    expect(catalog.roles.single.id, _uuid(40));
    expect(catalog.roles.single.code, 'goods_vendor');
    expect(catalog.roles.single.label, 'Proveedor de bienes');
    expect(
        catalog.roles.single.kind, SupplierClassificationDefinitionKind.role);
  });

  test('classification definition command uses an idempotent versioned receipt',
      () async {
    final operationId = _uuid(43);
    final appliedUpdatedAt = DateTime.utc(2026, 8, 8, 20);
    final currentUpdatedAt = DateTime.utc(2026, 8, 8, 21);
    final command = UpsertSupplierClassificationDefinitionCommand(
      operationId: operationId,
      kind: SupplierClassificationDefinitionKind.role,
      code: 'logistics_provider',
      label: 'Transporte',
      expectedUpdatedAt: DateTime.utc(2026, 8, 8, 19),
    );
    final gateway = _FakeCommandGateway(
      operationResponses: {
        'upsertClassificationDefinition': {
          'operation_id': operationId,
          'idempotent_replay': true,
          'vocabulary': 'role',
          'action': 'update',
          'applied_definition': {
            ..._definitionRow(
              tenantId: tenantA,
              id: _uuid(44),
              code: 'logistics_provider',
              label: 'Transporte',
            ),
            'updated_at': appliedUpdatedAt.toIso8601String(),
          },
          'current_definition': {
            ..._definitionRow(
              tenantId: tenantA,
              id: _uuid(44),
              code: 'logistics_provider',
              label: 'Transporte y flete',
            ),
            'updated_at': currentUpdatedAt.toIso8601String(),
          },
        },
      },
    );
    final service = SupplierRelationshipService(
      tenantService: _tenantService({'user-a': tenantA}),
      repository: _FakeRelationshipRepository(),
      legacyRepository: _FakeLegacyRepository(),
      commandGateway: gateway,
    );

    final result = await service.upsertClassificationDefinition(command);

    expect(gateway.calls['upsertClassificationDefinition'], 1);
    expect(gateway.lastCommand, same(command));
    expect(result.operationId, operationId);
    expect(
      result.action,
      SupplierClassificationDefinitionCommandAction.update,
    );
    expect(result.appliedDefinition.label, 'Transporte');
    expect(result.appliedDefinition.updatedAt, appliedUpdatedAt);
    expect(result.currentDefinition.label, 'Transporte y flete');
    expect(result.currentDefinition.updatedAt, currentUpdatedAt);
    expect(result.idempotentReplay, isTrue);
  });

  test('profile list consumes the server-owned service relationship summary',
      () async {
    final repository = _FakeRelationshipRepository(
      profiles: [
        _profileRow(
          tenantId: tenantA,
          supplierId: _uuid(41),
          partyId: _uuid(42),
          name: 'Google',
          serviceRelationshipSummary: 'Workspace · Local 1 y 2 más',
        ),
      ],
    );
    final service = SupplierRelationshipService(
      tenantService: _tenantService({'user-a': tenantA}),
      repository: repository,
      legacyRepository: _FakeLegacyRepository(),
    );

    final profile = (await service.listSupplierProfiles()).single;

    expect(
      profile.serviceRelationshipSummary,
      'Workspace · Local 1 y 2 más',
    );
    expect(
      SupplierProfile.fromJson(
        _profileRow(
          tenantId: tenantA,
          supplierId: _uuid(43),
          partyId: _uuid(44),
          name: 'Sin resumen publicado',
        ),
      ).serviceRelationshipSummary,
      isNull,
    );
  });

  test('classification candidate queue is typed, filtered, and paged',
      () async {
    final supplierId = _uuid(120);
    final repository = _FakeRelationshipRepository(
      classificationCandidates: [
        _candidateRow(
          tenantId: tenantA,
          candidateId: _uuid(121),
          supplierId: supplierId,
          targetVocabulary: 'role',
          sourceValue: 'local',
        ),
        _candidateRow(
          tenantId: tenantA,
          candidateId: _uuid(122),
          supplierId: supplierId,
          targetVocabulary: 'role',
          sourceValue: 'importador',
        ),
        _candidateRow(
          tenantId: tenantA,
          candidateId: _uuid(123),
          supplierId: supplierId,
          targetVocabulary: 'role',
          sourceValue: 'cerrado',
          status: 'confirmed',
        ),
      ],
    );
    final service = SupplierRelationshipService(
      tenantService: _tenantService({'user-a': tenantA}),
      repository: repository,
      legacyRepository: _FakeLegacyRepository(),
    );

    final firstPage = await service.listClassificationCandidatesPage(
      targetVocabulary: SupplierClassificationDefinitionKind.role,
      supplierId: supplierId,
      limit: 1,
    );
    final pending = await service.listClassificationCandidates(
      targetVocabulary: SupplierClassificationDefinitionKind.role,
      supplierId: supplierId,
    );

    expect(firstPage.items.single.id, _uuid(121));
    expect(firstPage.hasMore, isTrue);
    expect(firstPage.nextOffset, 1);
    expect(pending.map((item) => item.id), [_uuid(121), _uuid(122)]);
    expect(
      pending.singleWhere((item) => item.id == _uuid(121)).sourceKind,
      SupplierClassificationCandidateSourceKind.legacySupplierType,
    );
  });

  test('candidate queue keeps one authority lease across every page', () async {
    var currentUserId = 'user-a';
    final repository = _FakeRelationshipRepository(
      candidateLoader: ({
        required tenantId,
        required status,
        required targetVocabulary,
        required supplierId,
        required offset,
        required limit,
      }) async {
        if (offset == 0) {
          return _AfterAnyList(
            List.generate(
              501,
              (index) => _candidateRow(
                tenantId: tenantA,
                candidateId: _uuid(index + 2000),
                supplierId: _uuid(index + 3000),
                targetVocabulary: 'role',
                sourceValue: 'candidate-$index',
              ),
            ),
            () => currentUserId = 'user-b',
          );
        }
        return [
          _candidateRow(
            tenantId: tenantId,
            candidateId: _uuid(9991),
            supplierId: _uuid(9992),
            targetVocabulary: 'role',
            sourceValue: 'tenant-b-result',
          ),
        ];
      },
    );
    final service = SupplierRelationshipService(
      tenantService: TenantService.testing(
        currentUserId: () => currentUserId,
        profileLookup: (userId) async => [
          {
            'tenant_id': userId == 'user-a' ? tenantA : tenantB,
            'role': 'admin',
            'permissions': const {},
          },
        ],
      ),
      repository: repository,
      legacyRepository: _FakeLegacyRepository(),
    );

    await expectLater(
      service.listClassificationCandidates(),
      throwsA(isA<AuthorityScopeChangedException>()),
    );

    expect(repository.candidateTenantIds, [tenantA]);
  });

  test('candidate review is authority-scoped and exposes idempotent replay',
      () async {
    final candidateId = _uuid(124);
    final gateway = _FakeCommandGateway(
      operationResponses: {
        'reviewClassificationCandidate': {
          ..._candidateRow(
            tenantId: tenantA,
            candidateId: candidateId,
            supplierId: _uuid(125),
            targetVocabulary: 'role',
            sourceValue: 'local',
            status: 'confirmed',
          ),
          'id': candidateId,
          'candidate_id': null,
          'suggested_code': 'goods_vendor',
          'rationale': 'Revisado con documentos',
          'reviewed_by': 'user-a',
          'reviewed_at': '2026-08-08T20:00:00Z',
          'idempotent_replay': true,
        },
      },
    );
    final service = SupplierRelationshipService(
      tenantService: _tenantService({'user-a': tenantA}),
      repository: _FakeRelationshipRepository(),
      legacyRepository: _FakeLegacyRepository(),
      commandGateway: gateway,
    );
    final command = ReviewSupplierClassificationCandidateCommand(
      candidateId: candidateId,
      decision: SupplierClassificationCandidateStatus.confirmed,
      canonicalCode: 'goods_vendor',
      rationale: '  Revisado con documentos  ',
    );

    final result = await service.reviewClassificationCandidate(command);

    expect(gateway.calls['reviewClassificationCandidate'], 1);
    expect(result.candidate.id, candidateId);
    expect(result.candidate.suggestedCode, 'goods_vendor');
    expect(result.idempotentReplay, isTrue);
    expect(
      () => ReviewSupplierClassificationCandidateCommand(
        candidateId: candidateId,
        decision: SupplierClassificationCandidateStatus.rejected,
        canonicalCode: 'goods_vendor',
      ),
      throwsArgumentError,
    );
  });

  test('engagement editor can list active tenant business sites', () async {
    final repository = _FakeRelationshipRepository(
      businessSites: [
        {
          'id': _uuid(30),
          'tenant_id': tenantA,
          'code': 'local_1',
          'name': 'Local 1',
          'site_kind': 'store',
          'country_code': 'CL',
          'is_active': true,
          'metadata': const {},
        },
        {
          'id': _uuid(31),
          'tenant_id': tenantA,
          'code': 'old_store',
          'name': 'Local anterior',
          'site_kind': 'store',
          'country_code': 'CL',
          'is_active': false,
          'metadata': const {},
        },
      ],
    );
    final service = SupplierRelationshipService(
      tenantService: _tenantService({'user-a': tenantA}),
      repository: repository,
      legacyRepository: _FakeLegacyRepository(),
    );

    final sites = await service.listBusinessSites();

    expect(sites, hasLength(1));
    expect(sites.single.id, _uuid(30));
    expect(sites.single.name, 'Local 1');
  });

  test('detail keeps expired classifications in history, never active edits',
      () async {
    final supplierId = _uuid(45);
    final partyId = _uuid(46);
    final repository = _FakeRelationshipRepository(
      profiles: [
        _profileRow(
          tenantId: tenantA,
          supplierId: supplierId,
          partyId: partyId,
          name: 'Proveedor histórico',
          relationshipRoles: [
            {
              'id': _uuid(50),
              'definition_id': _uuid(48),
              'code': 'service_provider',
              'label': 'Proveedor de servicios',
              'valid_from': '2026-08-01',
              'source': 'manual',
              'metadata': const {},
            },
          ],
        ),
      ],
      definitions: {
        SupplierClassificationDefinitionKind.role: [
          _definitionRow(
            tenantId: tenantA,
            id: _uuid(47),
            code: 'goods_vendor',
            label: 'Proveedor de bienes',
          ),
          _definitionRow(
            tenantId: tenantA,
            id: _uuid(48),
            code: 'service_provider',
            label: 'Proveedor de servicios',
          ),
        ],
      },
      roles: [
        {
          'id': _uuid(49),
          'tenant_id': tenantA,
          'supplier_id': supplierId,
          'role_code': 'goods_vendor',
          'valid_from': '2026-01-01',
          'valid_to': '2026-07-31',
          'assignment_source': 'manual',
          'metadata': const {},
        },
        {
          'id': _uuid(50),
          'tenant_id': tenantA,
          'supplier_id': supplierId,
          'role_code': 'service_provider',
          'valid_from': '2026-08-01',
          'assignment_source': 'manual',
          'metadata': const {},
        },
      ],
    );
    final service = SupplierRelationshipService(
      tenantService: _tenantService({'user-a': tenantA}),
      repository: repository,
      legacyRepository: _FakeLegacyRepository(),
    );

    final profile = await service.getSupplierProfile(supplierId);

    expect(profile?.relationship.roles.map((role) => role.code), [
      'service_provider',
    ]);
    expect(profile?.classificationHistory.roles, hasLength(2));
    expect(
      profile?.classificationHistory.roles
          .where((role) => role.code == 'goods_vendor')
          .single
          .validUntil,
      DateTime(2026, 7, 31),
    );
  });

  test('detail never promotes observed classification history into edits',
      () async {
    final supplierId = _uuid(51);
    final partyId = _uuid(52);
    final repository = _FakeRelationshipRepository(
      profiles: [
        _profileRow(
          tenantId: tenantA,
          supplierId: supplierId,
          partyId: partyId,
          name: 'Inferencia pendiente',
        ),
      ],
      definitions: {
        SupplierClassificationDefinitionKind.role: [
          _definitionRow(
            tenantId: tenantA,
            id: _uuid(53),
            code: 'service_provider',
            label: 'Proveedor de servicios',
          ),
        ],
      },
      roles: [
        {
          'id': _uuid(54),
          'tenant_id': tenantA,
          'supplier_id': supplierId,
          'role_code': 'service_provider',
          'valid_from': '2026-08-01',
          'assignment_source': 'observed',
          'metadata': const {},
        },
      ],
    );
    final service = SupplierRelationshipService(
      tenantService: _tenantService({'user-a': tenantA}),
      repository: repository,
      legacyRepository: _FakeLegacyRepository(),
    );

    final profile = await service.getSupplierProfile(supplierId);

    expect(profile?.relationship.roles, isEmpty);
    expect(profile?.classificationHistory.roles, hasLength(1));
    expect(
      profile?.classificationHistory.roles.single.assignmentSource,
      'observed',
    );
  });

  test('legacy supplier cache pagination has a stable database tie-breaker',
      () {
    final source = File(
      'lib/modules/purchases/services/purchase_service.dart',
    ).readAsStringSync();
    final method = source.substring(
      source.indexOf('Future<List<shared_supplier.Supplier>> getSuppliers'),
      source.indexOf('Future<shared_supplier.Supplier?> getSupplier'),
    );

    expect(method, contains("orderBy: 'id'"));
    expect(method, contains('a.id.compareTo(b.id)'));
    expect(method, contains('Supplier.secretFreeSelect'));
  });

  test('profile save is one atomic RPC with catalog-backed assignments',
      () async {
    final supplierId = _uuid(60);
    final partyId = _uuid(61);
    final definition = SupplierClassificationDefinition.fromJson(
      _definitionRow(
        tenantId: tenantA,
        id: _uuid(62),
        code: 'goods_vendor',
        label: 'Proveedor de bienes',
      ),
      kind: SupplierClassificationDefinitionKind.role,
    );
    final command = SaveSupplierRelationshipProfileCommand(
      operationId: _uuid(64),
      supplierId: supplierId,
      expectedUpdatedAt: DateTime.utc(2026, 8, 8, 12),
      party: ExternalParty(
        id: partyId,
        tenantId: tenantA,
        kind: ExternalPartyKind.organization,
        name: 'Andes Industrial',
      ),
      relationship: SupplierRelationship(
        id: supplierId,
        tenantId: tenantA,
        externalPartyId: partyId,
        name: 'Andes Industrial',
        status: SupplierRelationshipStatus.active,
      ),
      roles: [SupplierClassificationSelection(definition: definition)],
    );
    final gateway = _FakeCommandGateway(
      response: {
        ..._profileRow(
          tenantId: tenantA,
          supplierId: supplierId,
          partyId: partyId,
          name: 'Andes Industrial',
        ),
        'party_kind': 'organization',
        'relationship_roles': [
          {
            'id': _uuid(63),
            'definition_id': definition.id,
            'code': definition.code,
            'label': definition.label,
            'valid_from': '2026-08-08',
            'source': 'manual',
            'metadata': const {},
          },
        ],
      },
    );
    final service = SupplierRelationshipService(
      tenantService: _tenantService({'user-a': tenantA}),
      repository: _FakeRelationshipRepository(),
      legacyRepository: _FakeLegacyRepository(),
      commandGateway: gateway,
    );

    final saved = await service.saveProfile(command);

    expect(gateway.saveProfileCalls, 1);
    expect(gateway.lastTenantId, tenantA);
    expect(identical(gateway.lastCommand, command), isTrue);
    expect(saved.profile.relationship.id, supplierId);
    expect(saved.profile.relationship.roles.single.id, _uuid(63));
    expect(
      saved.profile.relationship.roles.single.definitionId,
      definition.id,
    );
    expect(saved.idempotentReplay, isFalse);
  });

  test('full profile payload keeps nullable keys so fields can be cleared', () {
    final supplierId = _uuid(70);
    final partyId = _uuid(71);
    final command = SaveSupplierRelationshipProfileCommand(
      operationId: _uuid(72),
      supplierId: supplierId,
      expectedUpdatedAt: DateTime.utc(2026, 8, 8),
      party: ExternalParty(
        id: partyId,
        tenantId: tenantA,
        kind: ExternalPartyKind.organization,
        name: 'Proveedor limpio',
      ),
      relationship: SupplierRelationship(
        id: supplierId,
        tenantId: tenantA,
        externalPartyId: partyId,
        name: 'Proveedor limpio',
        status: SupplierRelationshipStatus.active,
      ),
    );

    final payload = command.toProfileRpcJson();

    expect(payload['operation_id'], _uuid(72));

    for (final field in [
      'legal_name',
      'trade_name',
      'country_code',
      'party_notes',
      'tax_identifier',
      'tax_country_code',
      'email',
      'phone',
      'address',
      'city',
      'region',
      'comuna',
      'contact_person',
      'website',
      'notes',
      'legacy_type',
      'payment_terms',
      'default_tax_treatment',
    ]) {
      expect(payload.containsKey(field), isTrue, reason: field);
      expect(payload[field], isNull, reason: field);
    }
  });

  test('sales rep update is a narrow replay-safe supplier command', () async {
    final supplierId = _uuid(75);
    final operationId = _uuid(76);
    final command = UpdateSupplierSalesRepCommand(
      operationId: operationId,
      supplierId: supplierId,
      expectedUpdatedAt: DateTime.utc(2026, 9, 2, 12),
      name: ' Victor ',
      phone: '+56934867574',
      email: '   ',
    );
    // Un espacio en blanco es «sin dato»; el nombre se guarda sin espacios.
    expect(command.toJson(), {
      'name': 'Victor',
      'phone': '+56934867574',
      'email': null,
    });
    final gateway = _FakeCommandGateway(
      operationResponses: {
        'updateSalesRep': {
          'tenant_id': tenantA,
          'supplier_id': supplierId,
          'operation_id': operationId,
          'updated_at': '2026-09-02T12:05:00Z',
          'sales_rep': {
            'name': 'Victor',
            'phone': '+56934867574',
            'email': null,
          },
          'idempotent_replay': false,
        },
      },
    );
    final service = SupplierRelationshipService(
      tenantService: _tenantService({'user-a': tenantA}),
      repository: _FakeRelationshipRepository(),
      legacyRepository: _FakeLegacyRepository(),
      commandGateway: gateway,
    );

    final result = await service.updateSalesRep(command);

    expect(gateway.lastOperation, 'updateSalesRep');
    expect(gateway.lastTenantId, tenantA);
    expect(identical(gateway.lastCommand, command), isTrue);
    expect(result.supplierId, supplierId);
    expect(result.operationId, operationId);
    expect(result.name, 'Victor');
    expect(result.phone, '+56934867574');
    expect(result.email, isNull);
    expect(result.updatedAt, DateTime.utc(2026, 9, 2, 12, 5));
    expect(result.idempotentReplay, isFalse);
  });

  test('OCR template update is a narrow replay-safe supplier command',
      () async {
    final supplierId = _uuid(73);
    final operationId = _uuid(74);
    final command = UpdateSupplierOcrTemplateCommand(
      operationId: operationId,
      supplierId: supplierId,
      expectedUpdatedAt: DateTime.utc(2026, 8, 8, 12),
      template: const SupplierOcrTemplate(
        enabled: true,
        discountParser: SupplierOcrDiscountParser.anchoredTrailingNumeric,
      ),
    );
    final gateway = _FakeCommandGateway(
      operationResponses: {
        'updateOcrTemplate': {
          'tenant_id': tenantA,
          'supplier_id': supplierId,
          'operation_id': operationId,
          'updated_at': '2026-08-08T12:05:00Z',
          'ocr_template': {
            'enabled': true,
            'discount_parser': 'anchoredTrailingNumeric',
          },
          'idempotent_replay': false,
        },
      },
    );
    final service = SupplierRelationshipService(
      tenantService: _tenantService({'user-a': tenantA}),
      repository: _FakeRelationshipRepository(),
      legacyRepository: _FakeLegacyRepository(),
      commandGateway: gateway,
    );

    final result = await service.updateOcrTemplate(command);

    expect(gateway.lastOperation, 'updateOcrTemplate');
    expect(gateway.lastTenantId, tenantA);
    expect(identical(gateway.lastCommand, command), isTrue);
    expect(result.supplierId, supplierId);
    expect(result.operationId, operationId);
    expect(result.template.enabled, isTrue);
    expect(
      result.template.discountParser,
      SupplierOcrDiscountParser.anchoredTrailingNumeric,
    );
    expect(result.updatedAt, DateTime.utc(2026, 8, 8, 12, 5));
  });

  test('accounting version append is one RPC and returns closed history',
      () async {
    final supplierId = _uuid(80);
    final policyId = _uuid(81);
    final oldVersionId = _uuid(82);
    final newVersionId = _uuid(83);
    final currentVersionId = _uuid(88);
    final nature = SupplierClassificationDefinition.fromJson(
      {
        ..._definitionRow(
          tenantId: tenantA,
          id: _uuid(84),
          code: 'inventory_merchandise',
          label: 'Mercadería para reventa',
        ),
        'nature_group': 'inventory',
      },
      kind: SupplierClassificationDefinitionKind.operationalNature,
    );
    final command = AppendSupplierAccountingPolicyVersionCommand(
      operationId: _uuid(87),
      policyId: policyId,
      version: SupplierAccountingPolicyVersionInput(
        effectiveFrom: DateTime(2026, 9),
        operationalNature: nature,
        debitAccountId: _uuid(85),
      ),
      rules: [
        SupplierAccountingRuleInput(
          kind: SupplierAccountingRuleKind.documentType,
          operator: SupplierAccountingRuleOperator.equals,
          operand: {'document_type': '33'},
        ),
      ],
    );
    final gateway = _FakeCommandGateway(
      operationResponses: {
        'appendAccountingPolicyVersion': {
          'policy': {
            'id': policyId,
            'tenant_id': tenantA,
            'supplier_id': supplierId,
            'code': 'inventory-default',
            'name': 'Inventario',
            'status': 'active',
            'priority': 100,
            'allow_exact_autofill': false,
            'operation_id': _uuid(79),
          },
          'closed_version': {
            'id': oldVersionId,
            'tenant_id': tenantA,
            'policy_id': policyId,
            'version_number': 1,
            'effective_from': '2026-08-01',
            'effective_to': '2026-08-31',
            'operational_nature_code': nature.code,
            'operation_id': _uuid(78),
          },
          'applied_version': {
            'id': newVersionId,
            'tenant_id': tenantA,
            'policy_id': policyId,
            'version_number': 2,
            'effective_from': '2026-09-01',
            'operational_nature_code': nature.code,
            'operation_id': _uuid(87),
          },
          'current_version': {
            'id': currentVersionId,
            'tenant_id': tenantA,
            'policy_id': policyId,
            'version_number': 3,
            'effective_from': '2026-10-01',
            'operational_nature_code': nature.code,
            'operation_id': _uuid(89),
          },
          'rules': [
            {
              'id': _uuid(86),
              'tenant_id': tenantA,
              'policy_version_id': newVersionId,
              'rule_kind': 'document_type',
              'operator': 'equals',
              'operand': {'document_type': '33'},
              'priority': 100,
              'is_active': true,
            },
          ],
          'idempotent_replay': true,
        },
      },
    );
    final service = SupplierRelationshipService(
      tenantService: _tenantService({'user-a': tenantA}),
      repository: _FakeRelationshipRepository(),
      legacyRepository: _FakeLegacyRepository(),
      commandGateway: gateway,
    );

    final result = await service.appendAccountingPolicyVersion(command);

    expect(gateway.calls['appendAccountingPolicyVersion'], 1);
    expect(gateway.calls.length, 1);
    expect(result.closedVersion?.id, oldVersionId);
    expect(result.closedVersion?.effectiveUntil, DateTime(2026, 8, 31));
    expect(result.appliedVersion.id, newVersionId);
    expect(result.currentVersion.id, currentVersionId);
    expect(result.appliedVersion.operationalNatureDefinitionId, nature.id);
    expect(result.rules.single.policyVersionId, newVersionId);
    expect(result.idempotentReplay, isTrue);
  });

  test('evidence append sends no derived authority fields and maps snapshots',
      () async {
    final supplierId = _uuid(90);
    final nature = SupplierClassificationDefinition.fromJson(
      {
        ..._definitionRow(
          tenantId: tenantA,
          id: _uuid(91),
          code: 'digital_service',
          label: 'Servicio digital',
        ),
        'nature_group': 'service',
      },
      kind: SupplierClassificationDefinitionKind.operationalNature,
    );
    final command = AppendSupplierAccountingEvidenceCommand(
      operationId: _uuid(99),
      supplierId: supplierId,
      sourceType: SupplierAccountingEvidenceSourceType.expense,
      sourceId: _uuid(92),
      decision: SupplierAccountingEvidenceDecision.accepted,
      operationalNature: nature,
      debitAccountId: _uuid(93),
      legacyExpenseCategoryId: _uuid(94),
      publicEvidence: {
        'signals': [
          {'matched': true},
        ],
      },
    );
    final payload = command.toRpcJson();
    for (final serverOwned in [
      'applied_by',
      'applied_at',
      'operational_nature_label',
      'debit_account_code',
      'liability_account_code',
      'legacy_expense_category_name',
    ]) {
      expect(payload.containsKey(serverOwned), isFalse, reason: serverOwned);
    }
    final gateway = _FakeCommandGateway(
      operationResponses: {
        'appendAccountingEvidence': {
          'id': _uuid(95),
          'tenant_id': tenantA,
          'supplier_id': supplierId,
          'operation_id': _uuid(99),
          'source_type': 'expense',
          'source_id': _uuid(92),
          'decision': 'accepted',
          'operational_nature_code': nature.code,
          'operational_nature_label': nature.label,
          'debit_account_id': _uuid(93),
          'debit_account_code': '510100',
          'legacy_expense_category_id': _uuid(94),
          'legacy_expense_category_name': 'Servicios web',
          'evidence': payload['evidence'],
          'applied_at': '2026-08-08T20:00:00Z',
          'idempotent_replay': true,
        },
      },
    );
    final service = SupplierRelationshipService(
      tenantService: _tenantService({'user-a': tenantA}),
      repository: _FakeRelationshipRepository(),
      legacyRepository: _FakeLegacyRepository(),
      commandGateway: gateway,
    );

    final result = await service.appendAccountingEvidence(command);

    expect(gateway.calls['appendAccountingEvidence'], 1);
    expect(result.operationalNatureLabel, nature.label);
    expect(result.debitAccountCode, '510100');
    expect(result.legacyExpenseCategoryName, 'Servicios web');
    expect(payload['operation_id'], _uuid(99));
    expect(result.operationId, _uuid(99));
    expect(result.idempotentReplay, isTrue);
  });

  test('client cannot author server-reserved auto-filled evidence', () {
    final nature = SupplierClassificationDefinition.fromJson(
      {
        ..._definitionRow(
          tenantId: tenantA,
          id: _uuid(96),
          code: 'digital_service',
          label: 'Servicio digital',
        ),
        'nature_group': 'service',
      },
      kind: SupplierClassificationDefinitionKind.operationalNature,
    );

    expect(
      () => AppendSupplierAccountingEvidenceCommand(
        operationId: _uuid(100),
        supplierId: _uuid(97),
        sourceType: SupplierAccountingEvidenceSourceType.manual,
        sourceId: _uuid(98),
        decision: SupplierAccountingEvidenceDecision.autoFilled,
        operationalNature: nature,
      ),
      throwsArgumentError,
    );
  });
}

typedef _ProfileLoader = Future<List<Map<String, dynamic>>> Function({
  required String tenantId,
  required bool activeOnly,
  required int offset,
  required int limit,
});

typedef _CandidateLoader = Future<List<Map<String, dynamic>>> Function({
  required String tenantId,
  required SupplierClassificationCandidateStatus? status,
  required SupplierClassificationDefinitionKind? targetVocabulary,
  required String? supplierId,
  required int offset,
  required int limit,
});

class _FakeRelationshipRepository implements SupplierRelationshipRepository {
  @override
  Future<List<Map<String, dynamic>>> fetchContactRows({
    required String tenantId,
    required String supplierId,
  }) async =>
      const [];

  _FakeRelationshipRepository({
    this.profiles = const [],
    this.definitions = const {},
    this.classificationCandidates = const [],
    this.roles = const [],
    this.businessSites = const [],
    this.economicTimeline = const [],
    this.foundationMissing = false,
    this.profileLoader,
    this.candidateLoader,
  });

  final List<Map<String, dynamic>> profiles;
  final Map<SupplierClassificationDefinitionKind, List<Map<String, dynamic>>>
      definitions;
  final List<Map<String, dynamic>> classificationCandidates;
  final List<Map<String, dynamic>> roles;
  final List<Map<String, dynamic>> businessSites;
  final List<Map<String, dynamic>> economicTimeline;
  final bool foundationMissing;
  final _ProfileLoader? profileLoader;
  final _CandidateLoader? candidateLoader;
  final List<int> profileOffsets = [];
  final List<int> profileLimits = [];
  final List<String> profileTenantIds = [];
  final List<String> candidateTenantIds = [];
  final List<bool> timelineRecognizedOnly = [];
  final Completer<void> profileRequestStarted = Completer<void>();

  Never _missing() => throw const PostgrestException(
        message: 'Could not find supplier_profile_read_model',
        code: 'PGRST205',
      );

  @override
  Future<List<Map<String, dynamic>>> fetchProfileRows({
    required String tenantId,
    required bool activeOnly,
    required int offset,
    required int limit,
  }) async {
    if (foundationMissing) _missing();
    profileOffsets.add(offset);
    profileLimits.add(limit);
    profileTenantIds.add(tenantId);
    if (!profileRequestStarted.isCompleted) profileRequestStarted.complete();
    final loader = profileLoader;
    if (loader != null) {
      return loader(
        tenantId: tenantId,
        activeOnly: activeOnly,
        offset: offset,
        limit: limit,
      );
    }
    return profiles.skip(offset).take(limit).toList(growable: false);
  }

  @override
  Future<Map<String, dynamic>?> fetchProfileRow({
    required String tenantId,
    required String supplierId,
  }) async {
    if (foundationMissing) _missing();
    return profiles.cast<Map<String, dynamic>?>().firstWhere(
          (row) => row?['supplier_id'] == supplierId,
          orElse: () => null,
        );
  }

  @override
  Future<List<Map<String, dynamic>>> fetchDefinitionRows({
    required String tenantId,
    required SupplierClassificationDefinitionKind kind,
    required bool activeOnly,
  }) async {
    if (foundationMissing) _missing();
    return definitions[kind] ?? const [];
  }

  @override
  Future<List<Map<String, dynamic>>> fetchClassificationCandidateRows({
    required String tenantId,
    required SupplierClassificationCandidateStatus? status,
    required SupplierClassificationDefinitionKind? targetVocabulary,
    required String? supplierId,
    required int offset,
    required int limit,
  }) async {
    if (foundationMissing) _missing();
    candidateTenantIds.add(tenantId);
    final loader = candidateLoader;
    if (loader != null) {
      return loader(
        tenantId: tenantId,
        status: status,
        targetVocabulary: targetVocabulary,
        supplierId: supplierId,
        offset: offset,
        limit: limit,
      );
    }
    return classificationCandidates
        .where((row) => row['tenant_id'] == tenantId)
        .where((row) => status == null || row['status'] == status.name)
        .where(
          (row) =>
              targetVocabulary == null ||
              row['target_vocabulary'] == targetVocabulary.dbValue,
        )
        .where(
          (row) => supplierId == null || row['supplier_id'] == supplierId,
        )
        .skip(offset)
        .take(limit)
        .toList(growable: false);
  }

  @override
  Future<Map<String, dynamic>?> fetchExternalPartyRow({
    required String tenantId,
    required String partyId,
  }) async =>
      null;

  @override
  Future<List<Map<String, dynamic>>> fetchIdentifierRows({
    required String tenantId,
    required String partyId,
  }) async =>
      const [];

  @override
  Future<List<Map<String, dynamic>>> fetchRoleRows({
    required String tenantId,
    required String supplierId,
  }) async =>
      roles;

  @override
  Future<List<Map<String, dynamic>>> fetchCapabilityRows({
    required String tenantId,
    required String supplierId,
  }) async =>
      const [];

  @override
  Future<List<Map<String, dynamic>>> fetchTagRows({
    required String tenantId,
    required String supplierId,
  }) async =>
      const [];

  @override
  Future<List<Map<String, dynamic>>> fetchEngagementRows({
    required String tenantId,
    required String supplierId,
  }) async =>
      const [];

  @override
  Future<List<Map<String, dynamic>>> fetchEngagementVersionRows({
    required String tenantId,
    required List<String> engagementIds,
  }) async =>
      const [];

  @override
  Future<List<Map<String, dynamic>>> fetchSiteRows({
    required String tenantId,
    required List<String> siteIds,
  }) async =>
      const [];

  @override
  Future<List<Map<String, dynamic>>> fetchBusinessSiteRows({
    required String tenantId,
  }) async =>
      businessSites
          .where((row) => row['is_active'] == true)
          .toList(growable: false);

  @override
  Future<List<Map<String, dynamic>>> fetchPolicyRows({
    required String tenantId,
    required String supplierId,
  }) async =>
      const [];

  @override
  Future<List<Map<String, dynamic>>> fetchPolicyVersionRows({
    required String tenantId,
    required List<String> policyIds,
  }) async =>
      const [];

  @override
  Future<List<Map<String, dynamic>>> fetchRuleRows({
    required String tenantId,
    required List<String> policyVersionIds,
  }) async =>
      const [];

  @override
  Future<List<Map<String, dynamic>>> fetchEvidenceRows({
    required String tenantId,
    required String supplierId,
    required int limit,
  }) async =>
      const [];

  @override
  Future<List<Map<String, dynamic>>> fetchReceivedTaxDocumentRows({
    required String tenantId,
    required String supplierId,
  }) async =>
      const [];

  @override
  Future<List<Map<String, dynamic>>> fetchEconomicSummaryRows({
    required String tenantId,
    required String supplierId,
  }) async {
    if (foundationMissing) _missing();
    return const [];
  }

  @override
  Future<List<Map<String, dynamic>>> fetchEconomicTimelineRows({
    required String tenantId,
    required String supplierId,
    required bool recognizedOnly,
    required int offset,
    required int limit,
  }) async {
    if (foundationMissing) _missing();
    timelineRecognizedOnly.add(recognizedOnly);
    return economicTimeline
        .where((row) => row['tenant_id'] == tenantId)
        .where((row) => row['supplier_id'] == supplierId)
        .where((row) => !recognizedOnly || row['is_recognized'] == true)
        .skip(offset)
        .take(limit)
        .toList(growable: false);
  }
}

class _FakeLegacyRepository implements LegacySupplierReadRepository {
  _FakeLegacyRepository({this.suppliers = const []});

  final List<Supplier> suppliers;

  @override
  Future<List<Supplier>> fetchPage({
    required String tenantId,
    required bool activeOnly,
    required int offset,
    required int limit,
  }) async {
    return suppliers
        .where((supplier) => !activeOnly || supplier.isActive)
        .skip(offset)
        .take(limit)
        .toList(growable: false);
  }

  @override
  Future<Supplier?> fetchOne({
    required String tenantId,
    required String supplierId,
  }) async {
    for (final supplier in suppliers) {
      if (supplier.id == supplierId) return supplier;
    }
    return null;
  }
}

class _FakeCommandGateway implements SupplierRelationshipCommandGateway {
  _FakeCommandGateway({
    this.response = const {},
    this.operationResponses = const {},
  });

  final Map<String, dynamic> response;
  final Map<String, Map<String, dynamic>> operationResponses;
  int saveProfileCalls = 0;
  String? lastTenantId;
  Object? lastCommand;
  String? lastOperation;
  final Map<String, int> calls = {};

  Map<String, dynamic> _record(
    String operation,
    String tenantId,
    Object command,
  ) {
    calls[operation] = (calls[operation] ?? 0) + 1;
    lastOperation = operation;
    lastTenantId = tenantId;
    lastCommand = command;
    return operationResponses[operation] ?? response;
  }

  @override
  Future<Map<String, dynamic>> saveProfile({
    required String tenantId,
    required SaveSupplierRelationshipProfileCommand command,
  }) async {
    saveProfileCalls++;
    return _record('saveProfile', tenantId, command);
  }

  @override
  Future<Map<String, dynamic>> saveContact({
    required String tenantId,
    required SaveSupplierContactCommand command,
  }) async =>
      _record('saveContact', tenantId, command);

  @override
  Future<Map<String, dynamic>> setContactStatus({
    required String tenantId,
    required SetSupplierContactStatusCommand command,
  }) async =>
      _record('setContactStatus', tenantId, command);

  @override
  Future<Map<String, dynamic>> updateImageUrl({
    required String tenantId,
    required String supplierId,
    required String? imageUrl,
  }) async =>
      _record('updateImageUrl', tenantId, {'id': supplierId, 'url': imageUrl});

  @override
  Future<Map<String, dynamic>> updateOcrTemplate({
    required String tenantId,
    required UpdateSupplierOcrTemplateCommand command,
  }) async {
    return _record('updateOcrTemplate', tenantId, command);
  }

  @override
  Future<Map<String, dynamic>> updateSalesRep({
    required String tenantId,
    required UpdateSupplierSalesRepCommand command,
  }) async {
    return _record('updateSalesRep', tenantId, command);
  }

  @override
  Future<Map<String, dynamic>> appendAccountingEvidence({
    required String tenantId,
    required AppendSupplierAccountingEvidenceCommand command,
  }) async {
    return _record('appendAccountingEvidence', tenantId, command);
  }

  @override
  Future<Map<String, dynamic>> appendAccountingPolicyVersion({
    required String tenantId,
    required AppendSupplierAccountingPolicyVersionCommand command,
  }) async {
    return _record('appendAccountingPolicyVersion', tenantId, command);
  }

  @override
  Future<Map<String, dynamic>> appendEngagementVersion({
    required String tenantId,
    required AppendSupplierEngagementVersionCommand command,
  }) async {
    return _record('appendEngagementVersion', tenantId, command);
  }

  @override
  Future<Map<String, dynamic>> createAccountingPolicy({
    required String tenantId,
    required CreateSupplierAccountingPolicyCommand command,
  }) async {
    return _record('createAccountingPolicy', tenantId, command);
  }

  @override
  Future<Map<String, dynamic>> createEngagement({
    required String tenantId,
    required CreateSupplierEngagementCommand command,
  }) async {
    return _record('createEngagement', tenantId, command);
  }

  @override
  Future<Map<String, dynamic>> updateAccountingPolicyShell({
    required String tenantId,
    required UpdateSupplierAccountingPolicyShellCommand command,
  }) async {
    return _record('updateAccountingPolicyShell', tenantId, command);
  }

  @override
  Future<Map<String, dynamic>> updateEngagementShell({
    required String tenantId,
    required UpdateSupplierEngagementShellCommand command,
  }) async {
    return _record('updateEngagementShell', tenantId, command);
  }

  @override
  Future<Map<String, dynamic>> upsertClassificationDefinition({
    required String tenantId,
    required UpsertSupplierClassificationDefinitionCommand command,
  }) async {
    return _record('upsertClassificationDefinition', tenantId, command);
  }

  @override
  Future<Map<String, dynamic>> reviewClassificationCandidate({
    required String tenantId,
    required ReviewSupplierClassificationCandidateCommand command,
  }) async {
    return _record('reviewClassificationCandidate', tenantId, command);
  }
}

TenantService _tenantService(Map<String, String> tenantByUser) {
  return TenantService.testing(
    currentUserId: () => tenantByUser.keys.first,
    profileLookup: (userId) async => [
      {
        'tenant_id': tenantByUser[userId],
        'role': 'admin',
        'permissions': const {},
      },
    ],
  );
}

Map<String, dynamic> _profileRow({
  required String tenantId,
  required String supplierId,
  required String partyId,
  required String name,
  String? serviceRelationshipSummary,
  List<Map<String, dynamic>> relationshipRoles = const [],
}) {
  return {
    'tenant_id': tenantId,
    'supplier_id': supplierId,
    'party_id': partyId,
    'party_kind': 'other',
    'display_name': name,
    'is_active': true,
    'relationship_roles': relationshipRoles,
    'relationship_capabilities': const [],
    'relationship_tags': const [],
    'active_engagement_count': 0,
    'active_policy_count': 0,
    'effective_business_date': '2026-08-08',
    if (serviceRelationshipSummary != null)
      'service_relationship_summary': serviceRelationshipSummary,
  };
}

Map<String, dynamic> _candidateRow({
  required String tenantId,
  required String candidateId,
  required String? supplierId,
  required String targetVocabulary,
  required String sourceValue,
  String status = 'pending',
}) {
  return {
    'tenant_id': tenantId,
    'candidate_id': candidateId,
    'supplier_id': supplierId,
    'supplier_display_name': supplierId == null ? null : 'Proveedor candidato',
    'source_kind': 'legacy_supplier_type',
    'source_id': supplierId,
    'source_value': sourceValue,
    'target_vocabulary': targetVocabulary,
    'suggested_code': null,
    'suggested_label': null,
    'status': status,
    'rationale': null,
    'reviewed_by': null,
    'reviewed_at': null,
    'metadata': const {'migration_source': 'suppliers.type'},
    'created_at': '2026-08-08T12:00:00Z',
    'updated_at': '2026-08-08T12:00:00Z',
  };
}

Map<String, dynamic> _economicRow({
  required String tenantId,
  required String supplierId,
  required String eventId,
  required bool recognized,
}) {
  return {
    'tenant_id': tenantId,
    'supplier_id': supplierId,
    'party_id': _uuid(3999),
    'event_id': eventId,
    'event_type': 'purchase_invoice',
    'event_date': '2026-08-08',
    'document_number': eventId,
    'currency_code': 'CLP',
    'gross_amount': 1000,
    'paid_amount': 0,
    'balance_amount': 1000,
    'payment_count': 0,
    'is_recognized': recognized,
    'data_quality_status': 'complete',
    'metadata': const {},
  };
}

Map<String, dynamic> _definitionRow({
  required String tenantId,
  required String id,
  required String code,
  required String label,
}) {
  return {
    'id': id,
    'tenant_id': tenantId,
    'code': code,
    'label': label,
    'aliases': const [],
    'is_active': true,
    'is_system': true,
    'metadata': const {},
  };
}

String _uuid(int value) {
  return '00000000-0000-0000-0000-${value.toString().padLeft(12, '0')}';
}

class _AfterAnyList<E> extends ListBase<E> {
  _AfterAnyList(this._values, this._afterAny);

  final List<E> _values;
  final void Function() _afterAny;
  bool _didRunAfterAny = false;

  @override
  int get length => _values.length;

  @override
  set length(int value) => throw UnsupportedError('Read-only test list');

  @override
  E operator [](int index) => _values[index];

  @override
  void operator []=(int index, E value) =>
      throw UnsupportedError('Read-only test list');

  @override
  bool any(bool Function(E element) test) {
    final result = _values.any(test);
    if (!_didRunAfterAny) {
      _didRunAfterAny = true;
      _afterAny();
    }
    return result;
  }
}
