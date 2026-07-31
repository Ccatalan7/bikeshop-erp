import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('preload keeps parallel fan-out and binds every cache owner', () {
    final source = File('lib/shared/services/data_preload_service.dart')
        .readAsStringSync();

    expect(
      source,
      contains('await Future.wait<ErpAuthorityScopeKey?>(['),
    );
    for (final binding in const [
      '_bikeshopService?.bindAuthorityScope(',
      '_categoryService?.bindAuthorityScope(',
      '_brandService?.bindAuthorityScope(',
      '_purchaseService?.bindSupplierAuthorityScope(',
      '_taskService?.bindAuthorityScope(',
    ]) {
      expect(source, contains(binding), reason: 'Missing $binding');
    }
    expect(source, contains('_bindAuthority(userId: null, tenantId: null)'));
    expect(
      source,
      contains(
        'final publishedScope = await service.fetchTasksForPreload();',
      ),
    );
    expect(source, contains('_bindCacheOwnersToAuthority(lease.scope);'));
    expect(source, contains('_ownsCurrentAuthority(lease)'));
  });

  test('every preloaded cache uses generation-owned in-flight work', () {
    for (final path in const [
      'lib/modules/bikeshop/services/bikeshop_service.dart',
      'lib/modules/inventory/services/category_service.dart',
      'lib/modules/inventory/services/brand_service.dart',
      'lib/modules/purchases/services/purchase_service.dart',
      'lib/modules/tasks/services/task_service.dart',
    ]) {
      final source = File(path).readAsStringSync();
      expect(
        source,
        contains('AuthorityScopedLoad<'),
        reason: '$path must reject late work from an obsolete authority',
      );
    }
  });

  test('lazy cache access rejects same-user tenant disagreement', () {
    for (final path in const [
      'lib/modules/bikeshop/services/bikeshop_service.dart',
      'lib/modules/inventory/services/category_service.dart',
      'lib/modules/inventory/services/brand_service.dart',
      'lib/modules/tasks/services/task_service.dart',
    ]) {
      final source = File(path).readAsStringSync();
      expect(source, contains('_cacheScope.resolve('));
      expect(
        source,
        contains('AuthorityScopeResolution.rejectedTenantChange'),
      );
    }

    final purchase =
        File('lib/modules/purchases/services/purchase_service.dart')
            .readAsStringSync();
    expect(purchase, contains('_supplierCacheScope.resolve('));
    expect(
      purchase,
      contains('AuthorityScopeResolution.rejectedTenantChange'),
    );
  });

  test('task teardown detaches synchronously before unsubscribe completes', () {
    final source =
        File('lib/modules/tasks/services/task_service.dart').readAsStringSync();
    final bindStart = source.indexOf('void bindAuthorityScope({');
    final bindEnd = source.indexOf('Future<void> init(', bindStart);
    final bindBody = source.substring(bindStart, bindEnd);

    expect(bindBody, contains('final oldChannel = _detachTasksRealtime();'));
    expect(bindBody, contains('_tasks = [];'));
    expect(bindBody, contains('unawaited(oldChannel.unsubscribe())'));
    expect(
      bindBody.indexOf('_tasks = [];'),
      lessThan(bindBody.indexOf('unawaited(oldChannel.unsubscribe())')),
    );
    expect(source, isNot(contains('while (_isLoading')));
  });

  test('task init accepts only the lease that its own fetch published', () {
    final source =
        File('lib/modules/tasks/services/task_service.dart').readAsStringSync();
    final initStart = source.indexOf('Future<void> init(');
    final initEnd = source.indexOf('Future<void> fetchTasks()', initStart);
    final initBody = source.substring(initStart, initEnd);

    expect(
      initBody,
      contains(
        'loadedLease = await _fetchTasksForCurrentAuthority();',
      ),
    );
    expect(initBody, contains('loadedLease == null'));
    expect(initBody, contains('!_cacheScope.owns(loadedLease)'));
  });
}
