import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/services/memory_hygiene.dart';

/// Contrato del guard central de memoria (incidente de 41 GB, 2026-08-05):
/// libera todas las cachés registradas, un fallo aislado no corta la limpieza
/// y las corridas en ráfaga se antirrebotan.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(MemoryHygiene.debugResetForTest);
  tearDown(MemoryHygiene.debugResetForTest);

  test('libera todas las cachés registradas y antirrebota la segunda corrida',
      () async {
    var posCacheClears = 0;
    var matcherCacheClears = 0;
    MemoryHygiene.registerTransientCache(() => posCacheClears++);
    MemoryHygiene.registerTransientCache(() => matcherCacheClears++);

    await MemoryHygiene.releaseTransientMemory(reason: 'test');
    expect(posCacheClears, 1);
    expect(matcherCacheClears, 1);

    await MemoryHygiene.releaseTransientMemory(reason: 'test');
    expect(posCacheClears, 1,
        reason: 'una corrida dentro de la ventana de antirrebote no repite');
    expect(matcherCacheClears, 1);
  });

  test('una caché que lanza no impide vaciar las demás', () async {
    var laterCacheCleared = false;
    MemoryHygiene.registerTransientCache(() => throw StateError('caché rota'));
    MemoryHygiene.registerTransientCache(() => laterCacheCleared = true);

    await MemoryHygiene.releaseTransientMemory(reason: 'test');
    expect(laterCacheCleared, isTrue);
  });
}
