/// Lo que dice el portal para confirmar el teléfono con un código por
/// WhatsApp y quedar con la ficha del taller (20261105010000).
///
/// Con la voz de la marca: tuteo, corto y seguro; sin contar el mecanismo
/// (dueño, 2026-11-04).
library;

const customerPhoneOfferTitle = '¿Ya te atendiste en el taller?';
const customerPhoneOfferBody =
    'Confirma tu teléfono y verás tus servicios, garantías y facturas.';
const customerPhoneOfferAction = 'Confirmar teléfono';

const customerPhoneDialogTitle = 'Confirma tu teléfono';
const customerPhoneDialogIntro = 'Te enviaremos un código por WhatsApp.';
const customerPhoneLabel = 'Teléfono';
const customerPhoneHint = '+56 9 1234 5678';
const customerPhoneSendAction = 'Enviar código';

/// Después de enviarlo: adónde, sin el número entero.
String customerPhoneCodeIntro(String? hint) =>
    hint == null || hint.trim().isEmpty
    ? 'Escribe el código que te enviamos por WhatsApp.'
    : 'Escribe el código que enviamos a ${hint.trim()} por WhatsApp.';
const customerPhoneCodeLabel = 'Código';
const customerPhoneConfirmAction = 'Confirmar';
const customerPhoneResendAction = 'Enviar otro código';
const customerPhoneCodeMissing = 'Escribe los 6 dígitos del código.';

/// Las respuestas que confirman el teléfono: el portal se vuelve a dibujar.
bool customerPhoneConfirmed(String status) =>
    status == 'linked' || status.startsWith('verified');

/// Lo que se le dice al cliente cuando el teléfono quedó confirmado.
String customerPhoneOutcome(String status) => switch (status) {
  'linked' => 'Listo, ya ves tus servicios del taller.',
  'verified_ambiguous' =>
    'Teléfono confirmado. Está en más de una ficha del taller: pide tu QR en '
        'el taller para ver la tuya.',
  'verified_has_history' =>
    'Teléfono confirmado. Escríbenos y unimos tu historial del taller.',
  _ =>
    'Teléfono confirmado. Cuando traigas tu bici, tus servicios aparecerán '
        'aquí.',
};

/// Lo que se le dice cuando el código no salió o no sirvió.
String customerPhoneProblem(
  String status, {
  int? attemptsLeft,
  int? retryAfterSeconds,
}) => switch (status) {
  'wrong_code' when attemptsLeft == 1 =>
    'Código incorrecto. Te queda 1 intento.',
  'wrong_code' when attemptsLeft != null =>
    'Código incorrecto. Te quedan $attemptsLeft intentos.',
  'wrong_code' => 'Código incorrecto.',
  'expired' => 'El código venció. Pide otro.',
  'too_many_attempts' => 'Demasiados intentos. Pide otro código.',
  'invalid_phone' => 'Revisa el número: tiene que ser un celular.',
  'too_soon' when retryAfterSeconds != null =>
    'Espera $retryAfterSeconds segundos para pedir otro.',
  'too_soon' => 'Espera un minuto para pedir otro.',
  'too_many_requests' => 'Ya pediste varios códigos. Prueba de nuevo mañana.',
  'not_sent' =>
    'No pudimos enviar el código a ese número. Revisa que tenga WhatsApp.',
  _ => 'No pudimos enviar el código. Intenta de nuevo.',
};
