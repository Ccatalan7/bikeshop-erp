import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/messaging/widgets/counterparty_avatar_image.dart';

/// El avatar de un chat llena el círculo, como WhatsApp, salvo un logotipo que
/// recortado dejaría las letras del medio.
///
/// Las proporciones son las reales (2026-09-18): los 53 logos de proveedor en
/// producción son cuadrados, y el primer logo de TeknoBike medía 415×77.
void main() {
  test('un logo cuadrado llena el círculo', () {
    expect(counterpartyImageFillsCircle(isMark: true, aspectRatio: 1), isTrue);
    // Un avatar de página que no es exactamente cuadrado (Bashka, 720×723).
    expect(
      counterpartyImageFillsCircle(isMark: true, aspectRatio: 720 / 723),
      isTrue,
    );
  });

  test('un logotipo apaisado se contiene', () {
    expect(
      counterpartyImageFillsCircle(isMark: true, aspectRatio: 415 / 77),
      isFalse,
    );
    expect(
      counterpartyImageFillsCircle(isMark: true, aspectRatio: 77 / 415),
      isFalse,
    );
  });

  test('una foto de persona siempre llena, sea cual sea su forma', () {
    expect(
      counterpartyImageFillsCircle(isMark: false, aspectRatio: 3 / 4),
      isTrue,
    );
    expect(
      counterpartyImageFillsCircle(isMark: false, aspectRatio: 16 / 9),
      isTrue,
    );
  });
}
