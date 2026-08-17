import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vinabike_erp/modules/purchases/services/intelligent_purchasing_service.dart';
import 'package:vinabike_erp/modules/purchases/services/purchase_journey_controller.dart';

/// El contrato de navegación del handoff t23 pide una pila con índice que
/// conserve lo trabajado. La versión anterior del módulo tenía un booleano
/// (`_returnToScenarios`) puesto a mano en seis lugares, y todo el recorrido
/// dentro del `State` de la página: salir borraba todo.
///
/// Estas pruebas fijan las dos mitades: que el historial se comporte como el de
/// un navegador, y que moverse por él **no destruya** nada.
void main() {
  // El controlador sólo toca la red dentro de los `load*`, que estas pruebas no
  // ejercitan. Un cliente apuntado a localhost basta para construirlo sin
  // inicializar Supabase ni salir a ninguna parte.
  PurchaseJourneyController build() => PurchaseJourneyController(
        IntelligentPurchasingService(
          client: SupabaseClient('http://localhost', 'test-anon-key'),
        ),
      );

  test('arranca en Necesidad, sin atrás ni adelante', () {
    final journey = build();

    expect(journey.step, PurchaseStep.need);
    expect(journey.canGoBack, isFalse);
    expect(journey.canGoForward, isFalse);
  });

  test('avanzar habilita atrás, y volver habilita adelante', () {
    final journey = build();

    journey.goTo(PurchaseStep.providers, needId: 'need-1');
    expect(journey.step, PurchaseStep.providers);
    expect(journey.canGoBack, isTrue);
    expect(journey.canGoForward, isFalse);

    journey.back();
    expect(journey.step, PurchaseStep.need);
    expect(journey.canGoBack, isFalse);
    expect(journey.canGoForward, isTrue);

    journey.forward();
    expect(journey.step, PurchaseStep.providers);
    expect(journey.needId, 'need-1');
  });

  test('ir a donde ya se está no ensucia el historial', () {
    final journey = build();

    journey.goTo(PurchaseStep.stock, needId: 'need-1');
    journey.goTo(PurchaseStep.stock, needId: 'need-1');

    expect(journey.trail, hasLength(2));
    journey.back();
    expect(journey.step, PurchaseStep.need);
  });

  test('avanzar desde el medio descarta lo que venía adelante', () {
    final journey = build();

    journey.goTo(PurchaseStep.stock, needId: 'need-1');
    journey.goTo(PurchaseStep.providers, needId: 'need-1');
    journey.back();
    expect(journey.canGoForward, isTrue);

    journey.goTo(PurchaseStep.plan, needId: 'need-1');

    expect(journey.step, PurchaseStep.plan);
    expect(journey.canGoForward, isFalse,
        reason: 'Proveedores quedó descartado');
    journey.back();
    expect(journey.step, PurchaseStep.stock);
  });

  test('la necesidad se arrastra sola cuando no se nombra otra', () {
    final journey = build();

    journey.goTo(PurchaseStep.stock, needId: 'need-7');
    journey.goTo(PurchaseStep.providers);

    expect(journey.needId, 'need-7');
  });

  test('moverse por el historial no destruye nada de lo trabajado', () {
    final journey = build();

    journey.goTo(PurchaseStep.providers, needId: 'need-1');
    journey.setRankingProfile('profitability');
    journey.setInspectorWidth(512);
    journey.inspect('candidate-9');
    journey.rememberScroll(PurchaseStep.providers, 340);

    journey.back();
    journey.back();
    journey.forward();
    journey.forward();

    expect(journey.rankingProfile, 'profitability');
    expect(journey.inspectorWidth, 512);
    expect(journey.inspectedCandidateId, 'candidate-9');
    expect(journey.scrollOffsetFor(PurchaseStep.providers), 340);
  });

  test('cada superficie recuerda su propio scroll', () {
    final journey = build();

    journey.rememberScroll(PurchaseStep.stock, 120);
    journey.rememberScroll(PurchaseStep.plan, 80);

    expect(journey.scrollOffsetFor(PurchaseStep.stock), 120);
    expect(journey.scrollOffsetFor(PurchaseStep.plan), 80);
    expect(journey.scrollOffsetFor(PurchaseStep.providers), 0);
  });

  test('atrás y adelante avisan a quien escucha', () {
    final journey = build();
    var notifications = 0;
    journey.addListener(() => notifications++);

    journey.goTo(PurchaseStep.stock, needId: 'need-1');
    journey.back();
    journey.forward();

    expect(notifications, 3);
  });

  test('cambiar la gama invalida sólo el ranking de la necesidad en curso', () {
    final journey = build();

    journey.goTo(PurchaseStep.providers, needId: 'need-1');
    expect(journey.gama, isNull, reason: 'no se supone una gama por defecto');

    journey.setGama('economica');
    expect(journey.gama, 'economica');

    // La gama sobrevive al historial, como el perfil y el ancho del inspector.
    journey.back();
    journey.forward();
    expect(journey.gama, 'economica');

    journey.setGama(null);
    expect(journey.gama, isNull, reason: 'quitar la gama es una opción');
  });

  test('en los extremos, atrás y adelante no hacen nada', () {
    final journey = build();
    var notifications = 0;
    journey.addListener(() => notifications++);

    journey.back();
    journey.forward();

    expect(journey.step, PurchaseStep.need);
    expect(notifications, 0, reason: 'un no-movimiento no repinta');
  });
}
