// This executable scratch test is outside test/, so the analyzer cannot infer
// its test-only use of SharedPreferences.setMockInitialValues.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vinabike_erp/modules/ai_assistant/services/ai_agent_gateway_client.dart';
import 'package:vinabike_erp/modules/messaging/providers/chat_provider.dart';
import 'package:vinabike_erp/modules/purchases/models/intelligent_purchasing_models.dart';
import 'package:vinabike_erp/modules/purchases/pages/intelligent_purchasing_workspace_page.dart';
import 'package:vinabike_erp/modules/purchases/services/intelligent_purchasing_service.dart';
import 'package:vinabike_erp/modules/settings/services/appearance_service.dart';
import 'package:vinabike_erp/shared/services/current_user_profile_service.dart';
import 'package:vinabike_erp/shared/services/navigation_service.dart';
import 'package:vinabike_erp/shared/services/workspace_manager.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';

// Independent integration checks of the new evidence-retention boundary.
// All business responses below are explicit fakes; no production write or AI
// request is made. The actual public editor and retry controls are exercised.
class _NoAI implements AIAgentGatewayTransport {
  @override
  Future<Object?> send(Map<String, Object?> body,
          {required Future<void> abortTrigger}) =>
      throw StateError('This test must not request AI');
}

class _EvidenceService extends IntelligentPurchasingService {
  _EvidenceService({
    this.rankFailures = 0,
    this.firstRankRelease,
    this.firstCriteriaRelease,
  });

  int rankFailures;
  final Completer<void>? firstRankRelease;
  final Completer<void>? firstCriteriaRelease;
  int criteriaCalls = 0;
  final rankQueries = <String?>[];
  var need = _need('Pastillas de freno', 1, 6);

  static SupplyNeed _need(String description, int version, double quantity) =>
      SupplyNeed.fromJson(<String, dynamic>{
        'id': 'same-need-id',
        'origin_kind': 'ad_hoc',
        'original_description': description,
        'quantity': quantity,
        'unit': 'unit',
        'identity_state': 'pending',
        'supply_state': 'open',
        'version': version,
        'created_at': '2026-08-30T12:00:00Z',
      });

  @override
  Future<List<SupplyNeed>> fetchOpenNeeds({String? mechanicJobId}) async =>
      <SupplyNeed>[need];

  @override
  Future<SupplyNeed?> fetchNeed(String needId) async => need;

  @override
  Future<List<PurchasePrioritySuggestion>> fetchPurchasePriority({
    int limit = 40,
    int rotationDays = 120,
  }) async =>
      const <PurchasePrioritySuggestion>[];

  @override
  Future<PurchasePlanDraft?> fetchOpenDraftPlan() async => null;

  @override
  Future<SupplyNeedCriteria> fetchNeedCriteria(String needId) async {
    if (firstCriteriaRelease == null) return SupplyNeedCriteria.empty;
    criteriaCalls += 1;
    final version = need.version;
    if (criteriaCalls == 1) await firstCriteriaRelease!.future;
    return SupplyNeedCriteria(
      predicates: const <SupplyNeedPredicate>[],
      commercialPreference: 'Criterios de versión $version',
      revisionNo: version,
    );
  }

  @override
  Future<SupplyStockResolution> stockResolution(String needId,
          {int limit = 20, int offset = 0}) async =>
      throw StateError('canceling statement due to statement timeout');

  @override
  Future<SupplyNeed> updateNeed(
    SupplyNeed current, {
    required String description,
    required String? productId,
    double? quantity,
    String? unit,
  }) async {
    need =
        _need(description, current.version + 1, quantity ?? current.quantity);
    return need;
  }

  @override
  Future<SupplierConcentrationReport> rankSuppliers({
    String? query,
    String? category,
    String? brand,
    int limit = 4,
  }) async {
    rankQueries.add(query);
    if (rankQueries.length == 1 && firstRankRelease != null) {
      await firstRankRelease!.future;
    }
    if (rankFailures > 0) {
      rankFailures--;
      throw StateError('temporary supplier history failure');
    }
    return SupplierConcentrationReport.fromJson(<String, dynamic>{
      'hasMore': false,
      'items': <Map<String, dynamic>>[
        <String, dynamic>{
          'entityId': 'supplier-test',
          'supplierName': 'Proveedor para $query',
          'spendSharePercent': 100,
          'purchaseLines': 3,
          'purchaseInvoices': 2,
          'distinctProducts': 2,
          'evidencePurchaseLines': 3,
          'evidenceSuppliers': 1,
        },
      ],
    });
  }
}

Future<void> _mount(WidgetTester tester, _EvidenceService service) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1400, 900);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final navigation = NavigationService();
  final workspaces = WorkspaceManager(sessionIdentity: 'evidence-boundary');
  final appearance = AppearanceService();
  final chat = ChatProvider();
  final profile = CurrentUserProfileService();
  addTearDown(navigation.dispose);
  addTearDown(workspaces.dispose);
  addTearDown(appearance.dispose);
  addTearDown(chat.dispose);
  addTearDown(profile.dispose);
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<NavigationService>.value(value: navigation),
      ChangeNotifierProvider<WorkspaceManager>.value(value: workspaces),
      ChangeNotifierProvider<AppearanceService>.value(value: appearance),
      ChangeNotifierProvider<ChatProvider>.value(value: chat),
      ChangeNotifierProvider<CurrentUserProfileService>.value(value: profile),
      Provider<Workspace>.value(value: workspaces.activeWorkspace!),
    ],
    child: MaterialApp(
      theme: AppTheme.resolve(
        preset: AppearancePresets.all.first,
        brightness: Brightness.light,
      ),
      home: IntelligentPurchasingWorkspacePage(
        initialNeedId: service.need.id,
        service: service,
        gatewayClient: AIAgentGatewayClient(transport: _NoAI()),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    WidgetController.hitTestWarningShouldBeFatal = true;
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://127.0.0.1:54321',
      anonKey: 'test-anon-key',
    );
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('same-need retry preserves successfully loaded evidence',
      (tester) async {
    final service = _EvidenceService();
    await _mount(tester, service);
    expect(service.rankQueries, <String>['Pastillas de freno']);
    expect(find.text('Proveedor para Pastillas de freno'), findsWidgets);
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('decision-load-failed'))).dy,
      lessThan(tester
          .getTopLeft(find.text('Proveedor para Pastillas de freno').first)
          .dy),
      reason: 'stock failure must be visible before supplier choices',
    );
    await tester.tap(find.byKey(const ValueKey('retry-decision-load')));
    await tester.pumpAndSettle();
    expect(service.rankQueries, hasLength(1));
    expect(find.text('Proveedor para Pastillas de freno'), findsWidgets);
  });

  testWidgets('editing the description does not reuse the old supplier query',
      (tester) async {
    final service = _EvidenceService();
    await _mount(tester, service);
    expect(service.rankQueries, <String>['Pastillas de freno']);
    await tester.tap(find.byKey(const ValueKey('edit-supply-need-inline')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('need-inline-description')),
        'Rodamientos para maza');
    await tester.tap(find.byKey(const ValueKey('need-inline-save')));
    await tester.pumpAndSettle();
    expect(service.need.description, 'Rodamientos para maza');
    expect(service.need.id, 'same-need-id');
    expect(service.rankQueries,
        <String>['Pastillas de freno', 'Rodamientos para maza']);
    expect(find.text('Proveedor para Rodamientos para maza'), findsWidgets);
    expect(find.text('Proveedor para Pastillas de freno'), findsNothing);
  });

  testWidgets('failed history is retried rather than cached as success',
      (tester) async {
    final service = _EvidenceService(rankFailures: 1);
    await _mount(tester, service);
    expect(service.rankQueries, hasLength(1));
    await tester.tap(find.byKey(const ValueKey('retry-decision-load')));
    await tester.pumpAndSettle();
    expect(service.rankQueries, hasLength(2));
    expect(find.text('Proveedor para Pastillas de freno'), findsWidgets);
  });

  testWidgets('a late answer to the previous description cannot overwrite it',
      (tester) async {
    final release = Completer<void>();
    final service = _EvidenceService(firstRankRelease: release);
    await _mount(tester, service);
    expect(service.rankQueries, <String>['Pastillas de freno']);
    await tester.tap(find.byKey(const ValueKey('edit-supply-need-inline')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('need-inline-description')),
        'Rodamientos para maza');
    await tester.tap(find.byKey(const ValueKey('need-inline-save')));
    await tester.pumpAndSettle();
    expect(service.rankQueries,
        <String>['Pastillas de freno', 'Rodamientos para maza']);
    expect(find.text('Proveedor para Rodamientos para maza'), findsWidgets);
    release.complete();
    await tester.pumpAndSettle();
    expect(service.need.description, 'Rodamientos para maza');
    expect(find.text('Proveedor para Rodamientos para maza'), findsWidgets);
    expect(find.text('Proveedor para Pastillas de freno'), findsNothing);
  });

  testWidgets('late criteria cannot overwrite a newer version with same words',
      (tester) async {
    final release = Completer<void>();
    final service = _EvidenceService(firstCriteriaRelease: release);
    await _mount(tester, service);
    await tester.tap(find.byKey(const ValueKey('edit-supply-need-inline')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('need-inline-quantity')), '9');
    await tester.tap(find.byKey(const ValueKey('need-inline-save')));
    await tester.pumpAndSettle();
    expect(service.need.version, 2);
    expect(service.need.description, 'Pastillas de freno');
    expect(find.textContaining('Criterios de versión 2'), findsWidgets);
    release.complete();
    await tester.pumpAndSettle();
    expect(find.textContaining('Criterios de versión 2'), findsWidgets,
        reason: 'unchanged wording is not proof of a current criteria read');
    expect(find.textContaining('Criterios de versión 1'), findsNothing);
  });
}
