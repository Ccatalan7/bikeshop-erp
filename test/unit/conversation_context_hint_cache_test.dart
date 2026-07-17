import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vinabike_erp/modules/messaging/models/conversation_context_hint.dart';
import 'package:vinabike_erp/modules/messaging/services/conversation_context_hint_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('context hint cache round-trips the last rendered workshop context',
      () async {
    final cache = ConversationContextHintCache();
    const hint = ConversationContextHint(
      customerId: 'customer-1',
      customerName: 'Claudio Catalán',
      jobId: 'job-1',
      jobNumber: 'PG-00199',
      jobStatus: 'Entregado',
      jobStatusColor: '#16A34A',
      bikeId: 'bike-1',
      bikeName: 'Rockrider ST100',
    );

    await cache.write(
      tenantId: 'tenant-a',
      userId: 'user-a',
      hints: const {'conversation-1': hint},
    );

    final restored = await cache.read(
      tenantId: 'tenant-a',
      userId: 'user-a',
    );
    expect(restored.keys, ['conversation-1']);
    expect(restored['conversation-1']?.jobNumber, 'PG-00199');
    expect(restored['conversation-1']?.jobStatus, 'Entregado');
    expect(restored['conversation-1']?.bikeName, 'Rockrider ST100');
  });

  test('context hint cache is isolated by tenant and ERP user', () async {
    final cache = ConversationContextHintCache();
    await cache.write(
      tenantId: 'tenant-a',
      userId: 'user-a',
      hints: const {
        'conversation-1': ConversationContextHint(
          jobId: 'job-1',
          jobNumber: 'PG-00199',
        ),
      },
    );

    expect(
      await cache.read(tenantId: 'tenant-b', userId: 'user-a'),
      isEmpty,
    );
    expect(
      await cache.read(tenantId: 'tenant-a', userId: 'user-b'),
      isEmpty,
    );
  });
}
