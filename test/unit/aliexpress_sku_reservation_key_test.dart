import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/inventory/services/aliexpress_sku_reservation.dart';

/// The reservation RPC is idempotent **by operation key**. That is what makes a
/// lost response safe to retry, and it is exactly what made a shared key
/// dangerous once rows started reserving one at a time: reserving row A and
/// then row B under the cached key replayed A's answer, and both rows got the
/// same `AE0xxx`.
///
/// These tests drive the real authority against a fake sequence, with
/// `Completer`s where the timing is the point. A test that only greps the
/// source cannot tell whether two rows raced onto one number.
void main() {
  group('la reserva es de la fila, no del lote', () {
    test('dos filas idénticas byte a byte reciben SKUs distintos', () async {
      final service = _FakeSkuService();
      final authority = _authorityOf(service);

      // Same title, same listing, same variant, same price. Only the position
      // in the document tells them apart — and it must be enough.
      final first = await authority.reserveFor(_row(0));
      final second = await authority.reserveFor(_row(1));

      expect(first.sku, isNot(second.sku));
      expect(first.operationKey, isNot(second.operationKey));
      expect(service.calls.length, 2);
    });

    test('reintentar la misma fila no gasta otra llamada ni otro SKU',
        () async {
      final service = _FakeSkuService();
      final authority = _authorityOf(service);

      final first = await authority.reserveFor(_row(0));
      final again = await authority.reserveFor(_row(0));

      expect(again.sku, first.sku);
      expect(again.operationKey, first.operationKey);
      expect(service.calls.length, 1,
          reason: 'el operador ya escribió ese número en la caja');
      expect(authority.reservationCalls, 1);
    });

    test('dos filas elegidas a la vez se serializan y no colisionan', () async {
      final service = _FakeSkuService(manual: true);
      final authority = _authorityOf(service);

      final a = authority.reserveFor(_row(0));
      final b = authority.reserveFor(_row(1));
      await Future<void>.delayed(Duration.zero);

      // Nothing may be in flight twice: the AE namespace is one sequence.
      expect(service.pending.length, 1);
      service.releaseNext();
      await Future<void>.delayed(Duration.zero);
      expect(service.pending.length, 1);
      service.releaseNext();

      final skus = <String>{(await a).sku, (await b).sku};
      expect(skus.length, 2);
    });

    test('el mismo documento reimportado mañana replica, no quema secuencia',
        () async {
      final today = _FakeSkuService();
      final firstRun = _authorityOf(today);
      final granted = await firstRun.reserveFor(_row(0));

      final tomorrow = _FakeSkuService();
      final secondRun = _authorityOf(tomorrow);
      await secondRun.reserveFor(_row(0));

      expect(tomorrow.calls.single, granted.operationKey,
          reason: 'la clave se deriva del documento, no de la sesión');
    });
  });

  group('un número ocupado se descarta, nunca se muestra', () {
    test('una colisión ajena fuerza una reserva nueva bajo otra clave',
        () async {
      final service = _FakeSkuService(taken: <String>{'AE0001'});
      final authority = _authorityOf(service);

      final granted = await authority.reserveFor(_row(0));

      expect(granted.sku, 'AE0002');
      expect(granted.generation, 1);
      expect(service.calls.length, 2);
      expect(service.calls.first, isNot(service.calls.last));
    });

    test('un SKU repetido por la RPC se rechaza aunque nadie lo tenga',
        () async {
      // A replayed or reset sequence handing the same number twice is the
      // failure this class exists to make impossible, whatever its cause.
      final service =
          _FakeSkuService(scripted: <String>['AE0007', 'AE0007', 'AE0008']);
      final authority = _authorityOf(service);

      final first = await authority.reserveFor(_row(0));
      final second = await authority.reserveFor(_row(1));

      expect(first.sku, 'AE0007');
      expect(second.sku, 'AE0008');
    });

    test('invalidar una fila la deja pedir otro número, no el ocupado',
        () async {
      final service = _FakeSkuService();
      final authority = _authorityOf(service);

      final first = await authority.reserveFor(_row(0));
      final next = authority.invalidate(_row(0));
      final second = await authority.reserveFor(next);

      expect(second.sku, isNot(first.sku));
      expect(next.generation, first.generation + 1);
    });

    test('se rinde con un error claro en vez de entregar un SKU ocupado',
        () async {
      final service = _FakeSkuService(takeEverything: true);
      final authority = AliExpressSkuReservationAuthority(
        reserve: service.reserve,
        isSkuTaken: service.isTaken,
        maxCollisionRetries: 3,
      );

      await expectLater(
        authority.reserveFor(_row(0)),
        throwsA(isA<StateError>()),
      );
      expect(service.calls.length, 3);
    });
  });

  group('un fallo parcial deja el resto sano', () {
    test('la fila que falló puede reintentar; la que no, conserva su SKU',
        () async {
      final service = _FakeSkuService(failOnCall: <int>{2});
      final authority = _authorityOf(service);

      final good = await authority.reserveFor(_row(0));
      await expectLater(
        authority.reserveFor(_row(1)),
        throwsA(isA<Exception>()),
      );
      final recovered = await authority.reserveFor(_row(1));

      expect(authority.reservationFor(_row(0))!.sku, good.sku);
      expect(recovered.sku, isNot(good.sku));
    });

    test('un error no rompe la cola: la fila siguiente sigue reservando',
        () async {
      final service = _FakeSkuService(failOnCall: <int>{1});
      final authority = _authorityOf(service);

      final failing = authority.reserveFor(_row(0));
      final following = authority.reserveFor(_row(1));

      await expectLater(failing, throwsA(isA<Exception>()));
      expect((await following).sku, isNotEmpty);
    });
  });
}

AliExpressSkuReservationAuthority _authorityOf(_FakeSkuService service) =>
    AliExpressSkuReservationAuthority(
      reserve: service.reserve,
      isSkuTaken: service.isTaken,
    );

/// Two rows of one order that differ in nothing a title can see.
AliExpressSkuRowIdentity _row(int index) => AliExpressSkuRowIdentity(
      documentFingerprint: 'v2|AE160326|2026-03-16T00:00:00.000|supplier-ali',
      sourceRowIndex: index,
      listingId: '1005006',
      variantKey: 'negro-32h',
    );

class _FakeSkuService {
  _FakeSkuService({
    this.manual = false,
    this.taken = const <String>{},
    this.takeEverything = false,
    this.failOnCall = const <int>{},
    this.scripted,
  });

  final bool manual;
  final Set<String> taken;
  final bool takeEverything;
  final Set<int> failOnCall;
  final List<String>? scripted;

  final List<String> calls = <String>[];
  final List<Completer<List<String>>> pending = <Completer<List<String>>>[];
  int _next = 0;

  Future<List<String>> reserve({
    required int count,
    required String operationKey,
  }) {
    calls.add(operationKey);
    if (failOnCall.contains(calls.length)) {
      return Future<List<String>>.error(
        Exception('la reserva no respondió'),
      );
    }
    final answer = <String>[
      for (var i = 0; i < count; i++) _nextSku(),
    ];
    if (!manual) return Future<List<String>>.value(answer);
    final completer = Completer<List<String>>();
    pending.add(completer);
    return completer.future.then((_) => answer);
  }

  String _nextSku() {
    final script = scripted;
    if (script != null && _next < script.length) return script[_next++];
    _next++;
    return 'AE${_next.toString().padLeft(4, '0')}';
  }

  Future<bool> isTaken(String sku) async =>
      takeEverything || taken.contains(sku);

  void releaseNext() {
    if (pending.isEmpty) return;
    pending.removeAt(0).complete(const <String>[]);
  }
}
