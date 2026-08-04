import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/ai_assistant/models/ai_assistant_session_state.dart';
import 'package:vinabike_erp/modules/ai_assistant/services/ai_assistant_session_service.dart';
import 'package:vinabike_erp/modules/ai_assistant/services/ai_service.dart';
import 'package:vinabike_erp/modules/bikeshop/models/bikeshop_models.dart';
import 'package:vinabike_erp/modules/crm/services/customer_service.dart';
import 'package:vinabike_erp/modules/inventory/services/inventory_service.dart';
import 'package:vinabike_erp/modules/purchases/services/purchase_service.dart';
import 'package:vinabike_erp/modules/sales/services/sales_service.dart';
import 'package:vinabike_erp/modules/tasks/services/task_service.dart';
import 'package:vinabike_erp/modules/bikeshop/services/bikeshop_service.dart';
import 'package:vinabike_erp/shared/models/current_user_profile.dart';
import 'package:vinabike_erp/shared/services/current_user_profile_service.dart';

/// Records what the session hands the engine, and lets a turn be held open so
/// the lease behaviour can be observed instead of inferred.
class _FakeEngine extends AIAssistantService {
  int sendCount = 0;
  int resetCount = 0;
  Completer<AIAssistantResponse>? pending;
  AIAssistantResponse next = const AIAssistantResponse(text: 'respuesta');

  List<MechanicJob>? lastJobs;
  bool? lastSourceUnavailable;
  bool? lastAllowJobCacheFallback;
  String? lastAuthorityTenantId;

  @override
  Future<AIAssistantResponse> sendMessage(
    String message, {
    List<MechanicJob>? jobs,
    CustomerService? customerService,
    InventoryService? inventoryService,
    BikeshopService? bikeshopService,
    bool jobsAreCurrentView = false,
    String? jobSummaryScopeLabel,
    PurchaseService? purchaseService,
    SalesService? salesService,
    bool allowJobCacheFallback = true,
    bool visibleJobsSourceUnavailable = false,
    TaskService? taskService,
    required AIAssistantTurnAuthority authority,
  }) {
    sendCount++;
    lastJobs = jobs;
    lastSourceUnavailable = visibleJobsSourceUnavailable;
    lastAllowJobCacheFallback = allowJobCacheFallback;
    lastAuthorityTenantId = authority.tenantId;
    final held = pending;
    if (held != null) return held.future;
    return Future<AIAssistantResponse>.value(next);
  }

  @override
  void resetChat() {
    resetCount++;
  }
}

CurrentUserProfile _profile({
  required String userId,
  required String tenantId,
  String role = 'owner',
  Map<String, bool> permissions = const {'manage_users': true},
}) {
  return CurrentUserProfile(
    userId: userId,
    email: '$userId@vinabike.cl',
    emailVerified: true,
    displayName: 'Persona $userId',
    tenantId: tenantId,
    tenantName: 'Taller $tenantId',
    tenantSubdomain: null,
    role: role,
    permissions: permissions,
    employeeLinkState: EmployeeLinkState.unlinked,
    employee: null,
  );
}

MechanicJob _job({required String tenantId, String id = 'job-1'}) {
  return MechanicJob(
    id: id,
    tenantId: tenantId,
    jobNumber: 'PG-$id',
    customerId: 'customer-1',
    status: JobStatus.pendiente,
    clientRequest: 'Revisar frenos',
    totalCost: 0,
  );
}

void main() {
  late _FakeEngine engine;
  late AIAssistantSessionService session;

  setUp(() {
    engine = _FakeEngine();
    session = AIAssistantSessionService(engineFactory: () => engine);
  });

  Future<void> bind({
    String userId = 'user-a',
    String tenantId = 'tenant-a',
    String role = 'owner',
    Map<String, bool> permissions = const {'manage_users': true},
  }) {
    return session.synchronize(
      authUserId: userId,
      profile: _profile(
        userId: userId,
        tenantId: tenantId,
        role: role,
        permissions: permissions,
      ),
      profileIsLoading: false,
      profileLoadIssue: null,
      cachedTenantId: tenantId,
      resolveTenantId: () async => tenantId,
    );
  }

  group('authority', () {
    test('a coherent user + tenant + profile becomes ready with a greeting',
        () async {
      await bind();

      expect(session.status, AIAssistantSessionStatus.ready);
      expect(session.canSend, isTrue);
      expect(session.transcript, hasLength(1));
      expect(
          session.transcript.single.role, AIAssistantTranscriptRole.assistant);
    });

    test('the same authority keeps the transcript across re-synchronization',
        () async {
      // Closing and reopening the panel, or any notify storm, re-runs the
      // provider update. A healthy session must survive it: this is the case
      // the old panel got wrong, wiping what the operator saw while the model
      // kept the history.
      await bind();
      await session.send('hola',
          services: const AIAssistantTurnServices(),
          visibleJobs: const [],
          hasVisibleJobsContext: false);
      expect(session.transcript, hasLength(3));

      await bind();

      expect(session.transcript, hasLength(3));
      expect(engine.resetCount, 0);
    });

    test('a different user clears everything', () async {
      await bind(userId: 'user-a', tenantId: 'tenant-a');
      await session.send('hola',
          services: const AIAssistantTurnServices(),
          visibleJobs: const [],
          hasVisibleJobsContext: false);

      await bind(userId: 'user-b', tenantId: 'tenant-b');

      expect(session.transcript, hasLength(1));
      expect(engine.resetCount, greaterThan(0));
    });

    test('logout clears and closes the composer', () async {
      await bind();
      await session.send('hola',
          services: const AIAssistantTurnServices(),
          visibleJobs: const [],
          hasVisibleJobsContext: false);

      await session.synchronize(
        authUserId: null,
        profile: null,
        profileIsLoading: false,
        profileLoadIssue: null,
        cachedTenantId: null,
        resolveTenantId: () async => null,
      );

      expect(session.status, AIAssistantSessionStatus.signedOut);
      expect(session.canSend, isFalse);
      expect(session.transcript, isEmpty);
    });

    test('a loading profile is fail-closed and shows nothing prior', () async {
      await bind();

      await session.synchronize(
        authUserId: 'user-a',
        profile: null,
        profileIsLoading: true,
        profileLoadIssue: null,
        cachedTenantId: 'tenant-a',
        resolveTenantId: () async => 'tenant-a',
      );

      expect(session.status, AIAssistantSessionStatus.resolving);
      expect(session.canSend, isFalse);
      expect(session.transcript, isEmpty);
    });

    test('a profile load issue is fail-closed', () async {
      await session.synchronize(
        authUserId: 'user-a',
        profile: null,
        profileIsLoading: false,
        profileLoadIssue: CurrentUserProfileLoadIssue.unavailable,
        cachedTenantId: 'tenant-a',
        resolveTenantId: () async => 'tenant-a',
      );

      expect(session.status, AIAssistantSessionStatus.unavailable);
      expect(session.canSend, isFalse);
    });

    test('a profile belonging to another user is fail-closed', () async {
      await session.synchronize(
        authUserId: 'user-a',
        profile: _profile(userId: 'user-b', tenantId: 'tenant-a'),
        profileIsLoading: false,
        profileLoadIssue: null,
        cachedTenantId: 'tenant-a',
        resolveTenantId: () async => 'tenant-a',
      );

      expect(session.status, AIAssistantSessionStatus.unavailable);
      expect(session.canSend, isFalse);
    });

    test('a profile disagreeing with the resolved tenant is fail-closed',
        () async {
      await session.synchronize(
        authUserId: 'user-a',
        profile: _profile(userId: 'user-a', tenantId: 'tenant-a'),
        profileIsLoading: false,
        profileLoadIssue: null,
        cachedTenantId: null,
        resolveTenantId: () async => 'tenant-z',
      );

      expect(session.status, AIAssistantSessionStatus.unavailable);
      expect(session.canSend, isFalse);
    });

    test('a failed tenant resolution is fail-closed, not silently allowed',
        () async {
      await session.synchronize(
        authUserId: 'user-a',
        profile: _profile(userId: 'user-a', tenantId: 'tenant-a'),
        profileIsLoading: false,
        profileLoadIssue: null,
        cachedTenantId: null,
        resolveTenantId: () async => throw StateError('offline'),
      );

      expect(session.status, AIAssistantSessionStatus.unavailable);
      expect(session.canSend, isFalse);
    });

    test('a missing tenant cache suspends instead of staying coherent',
        () async {
      // An absent cache is not agreement. Treating null as "nothing
      // disagrees" kept a session live on an authority nothing could confirm
      // any more — the exact state a tenant switch passes through.
      await bind(userId: 'user-a', tenantId: 'tenant-a');
      await session.send('hola',
          services: const AIAssistantTurnServices(),
          visibleJobs: const [],
          hasVisibleJobsContext: false);
      expect(session.transcript, hasLength(3));

      final resolutions = <String>[];
      await session.synchronize(
        authUserId: 'user-a',
        profile: _profile(userId: 'user-a', tenantId: 'tenant-a'),
        profileIsLoading: false,
        profileLoadIssue: null,
        cachedTenantId: null,
        resolveTenantId: () async {
          resolutions.add('resolved');
          return 'tenant-a';
        },
      );

      expect(resolutions, hasLength(1), reason: 'it must re-resolve');
      expect(session.transcript, hasLength(1));
    });

    test('a slow resolution for A cannot reinstall A after B won', () async {
      // A resolves slowly; B arrives and resolves first. When A finally
      // returns it must not rebind the session to the previous taller.
      final slowA = Completer<String?>();
      final pendingA = session.synchronize(
        authUserId: 'user-a',
        profile: _profile(userId: 'user-a', tenantId: 'tenant-a'),
        profileIsLoading: false,
        profileLoadIssue: null,
        cachedTenantId: null,
        resolveTenantId: () => slowA.future,
      );

      await bind(userId: 'user-b', tenantId: 'tenant-b');
      expect(session.authorityTenantId, 'tenant-b');

      slowA.complete('tenant-a');
      await pendingA;

      expect(session.authorityTenantId, 'tenant-b');
      expect(session.status, AIAssistantSessionStatus.ready);
    });

    test('a changed role rebuilds the session', () async {
      await bind(role: 'owner');
      await session.send('hola',
          services: const AIAssistantTurnServices(),
          visibleJobs: const [],
          hasVisibleJobsContext: false);
      expect(session.transcript, hasLength(3));

      await bind(role: 'mechanic');

      expect(session.transcript, hasLength(1));
      expect(engine.resetCount, greaterThan(0));
    });

    test('changed permissions rebuild the session', () async {
      await bind(permissions: const {'manage_users': true});
      await session.send('hola',
          services: const AIAssistantTurnServices(),
          visibleJobs: const [],
          hasVisibleJobsContext: false);

      await bind(permissions: const {'manage_users': false});

      expect(session.transcript, hasLength(1));
    });

    test('permission map ordering alone does not rebuild the session',
        () async {
      // A fingerprint that depended on map iteration order would recreate the
      // engine on an unrelated rebuild and silently drop the conversation.
      await bind(permissions: const {'a': true, 'b': false});
      await session.send('hola',
          services: const AIAssistantTurnServices(),
          visibleJobs: const [],
          hasVisibleJobsContext: false);
      expect(session.transcript, hasLength(3));

      await bind(permissions: const {'b': false, 'a': true});

      expect(session.transcript, hasLength(3));
    });
  });

  group('turn lease', () {
    test('a second send while one is in flight is refused', () async {
      await bind();
      engine.pending = Completer<AIAssistantResponse>();

      final first = session.send('uno',
          services: const AIAssistantTurnServices(),
          visibleJobs: const [],
          hasVisibleJobsContext: false);
      await session.send('dos',
          services: const AIAssistantTurnServices(),
          visibleJobs: const [],
          hasVisibleJobsContext: false);

      expect(engine.sendCount, 1);

      engine.pending!.complete(const AIAssistantResponse(text: 'ok'));
      await first;
    });

    test('a late turn from A cannot publish into B, and B still completes',
        () async {
      // Two engines, both held open at once. A finishes *after* B has started
      // its own turn: A must publish nothing, and — the part a single-engine
      // test cannot show — B must still be mid-turn rather than released by
      // A's completion.
      final engineA = _FakeEngine()..pending = Completer<AIAssistantResponse>();
      final engineB = _FakeEngine()..pending = Completer<AIAssistantResponse>();
      var built = 0;
      final twoEngine = AIAssistantSessionService(
        engineFactory: () => built++ == 0 ? engineA : engineB,
      );
      addTearDown(twoEngine.dispose);

      Future<void> bindTo(String user, String tenant) {
        return twoEngine.synchronize(
          authUserId: user,
          profile: _profile(userId: user, tenantId: tenant),
          profileIsLoading: false,
          profileLoadIssue: null,
          cachedTenantId: tenant,
          resolveTenantId: () async => tenant,
        );
      }

      await bindTo('user-a', 'tenant-a');
      final turnA = twoEngine.send('pregunta A',
          services: const AIAssistantTurnServices(),
          visibleJobs: const [],
          hasVisibleJobsContext: false);
      expect(twoEngine.isSending, isTrue);

      await bindTo('user-b', 'tenant-b');
      final turnB = twoEngine.send('pregunta B',
          services: const AIAssistantTurnServices(),
          visibleJobs: const [],
          hasVisibleJobsContext: false);
      expect(engineB.sendCount, 1);
      expect(twoEngine.isSending, isTrue);

      // A returns late.
      engineA.pending!.complete(const AIAssistantResponse(text: 'tarde A'));
      await turnA;

      expect(
        twoEngine.transcript.any((e) => e.text.contains('tarde A')),
        isFalse,
        reason: "A's answer reached B's transcript",
      );
      expect(
        twoEngine.isSending,
        isTrue,
        reason: "A's completion released B's turn",
      );

      engineB.pending!.complete(const AIAssistantResponse(text: 'respuesta B'));
      await turnB;

      expect(twoEngine.isSending, isFalse);
      expect(
        twoEngine.transcript.map((e) => e.text),
        contains('respuesta B'),
      );
      expect(twoEngine.authorityTenantId, 'tenant-b');
    });

    test('an unresolved session refuses to send at all', () async {
      await session.synchronize(
        authUserId: 'user-a',
        profile: null,
        profileIsLoading: true,
        profileLoadIssue: null,
        cachedTenantId: null,
        resolveTenantId: () async => null,
      );

      await session.send('hola',
          services: const AIAssistantTurnServices(),
          visibleJobs: const [],
          hasVisibleJobsContext: false);

      expect(engine.sendCount, 0);
      expect(session.transcript, isEmpty);
    });
  });

  group('published jobs are untrusted input', () {
    test('the turn carries its own authority into the engine', () async {
      // Every shared cache the engine reads is checked against this key, not
      // against whatever the service happens to be bound to.
      await bind(userId: 'user-a', tenantId: 'tenant-a');

      await session.send('busca camara 29',
          services: const AIAssistantTurnServices(),
          visibleJobs: const [],
          hasVisibleJobsContext: false);

      expect(engine.lastAuthorityTenantId, 'tenant-a');
    });

    test('rows from the authority tenant are passed through', () async {
      await bind(userId: 'user-a', tenantId: 'tenant-a');

      await session.send('resumen de trabajos',
          services: const AIAssistantTurnServices(),
          visibleJobs: [_job(tenantId: 'tenant-a')],
          hasVisibleJobsContext: true);

      expect(engine.lastJobs, hasLength(1));
      expect(engine.lastSourceUnavailable, isFalse);
      expect(
        session.transcript
            .where((e) => e.role == AIAssistantTranscriptRole.notice),
        isEmpty,
      );
    });

    test('one row from another tenant invalidates the whole source', () async {
      // Session A, then a page from session B publishes its rows. Filtering
      // the foreign row out silently would let that page decide what the
      // assistant answers from; dropping the source and saying so is the only
      // honest outcome.
      await bind(userId: 'user-a', tenantId: 'tenant-a');

      await session.send('resumen de trabajos',
          services: const AIAssistantTurnServices(),
          visibleJobs: [
            _job(tenantId: 'tenant-a', id: 'ok'),
            _job(tenantId: 'tenant-b', id: 'ajeno'),
          ],
          hasVisibleJobsContext: true);

      expect(engine.lastJobs, isEmpty);
      expect(engine.lastSourceUnavailable, isTrue);
      expect(engine.lastAllowJobCacheFallback, isFalse);

      final notices = session.transcript
          .where((e) => e.role == AIAssistantTranscriptRole.notice)
          .toList();
      expect(notices, hasLength(1));
      expect(notices.single.text, contains('no puedo confirmar'));
    });

    test('a row without a tenant invalidates the whole source', () async {
      await bind(userId: 'user-a', tenantId: 'tenant-a');

      await session.send('resumen de trabajos',
          services: const AIAssistantTurnServices(),
          visibleJobs: [_job(tenantId: '', id: 'sin-tenant')],
          hasVisibleJobsContext: true);

      expect(engine.lastJobs, isEmpty);
      expect(engine.lastSourceUnavailable, isTrue);
    });

    test('no published context is not the same as a rejected one', () async {
      await bind();

      await session.send('busca camara 29',
          services: const AIAssistantTurnServices(),
          visibleJobs: const [],
          hasVisibleJobsContext: false);

      expect(engine.lastSourceUnavailable, isFalse);
      expect(
        session.transcript
            .where((e) => e.role == AIAssistantTranscriptRole.notice),
        isEmpty,
      );
    });
  });
}
