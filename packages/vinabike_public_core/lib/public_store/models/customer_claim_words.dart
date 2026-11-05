/// Lo que dice la página del QR (`/cuenta/vincular`), donde el cliente crea
/// su cuenta desde la recepción o el comprobante de entrega.
///
/// Con la voz de la marca: tuteo, corto y seguro; ni frases de app ni de
/// notaría, y sin contar el mecanismo (dueño, 2026-11-04). El dueño: «lo
/// importante es que el flujo de creación de cliente sea extremadamente
/// intuitivo y fácil… que pueda leer el QR y en cosa de segundos tenga creada
/// la cuenta».
library;

const customerClaimEyebrow = 'Tu cuenta';

/// «Hola, Dora» cuando el código lo sabe; «Crea tu cuenta» si no.
String customerClaimGreeting(String? firstName) {
  final name = firstName?.trim() ?? '';
  return name.isEmpty ? 'Crea tu cuenta' : 'Hola, $name';
}

/// «Trek Marlin 7 · Servicio PG-26-00412», o lo que se sepa de eso.
String? customerClaimSubject({String? bike, String? jobNumber}) {
  final parts = [
    if ((bike ?? '').trim().isNotEmpty) bike!.trim(),
    if ((jobNumber ?? '').trim().isNotEmpty) 'Servicio ${jobNumber!.trim()}',
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}

const customerClaimLead =
    'Sigue tu servicio, aprueba presupuestos y revisa tu garantía.';

const customerClaimBenefits = [
  ('pedal_bike', 'El estado de tu servicio'),
  ('fact_check', 'Presupuestos y facturas'),
  ('verified', 'Tu garantía'),
];

const customerClaimFormTitle = 'Crea tu cuenta';
const customerClaimPhoneLabel = 'Teléfono';
const customerClaimPhoneHint = '+56 9 1234 5678';
const customerClaimGoogle = 'Continuar con Google';
const customerClaimOr = 'o';
const customerClaimEmailToggle = 'Continuar con correo';
const customerClaimEmailLabel = 'Correo';
const customerClaimEmailHint = 'tu@correo.cl';
const customerClaimPasswordLabel = 'Contraseña';
const customerClaimPasswordHint = 'Mínimo 8 caracteres';
const customerClaimCreate = 'CREAR CUENTA';
const customerClaimHaveAccount = '¿Ya tienes cuenta?';
const customerClaimSignIn = 'Inicia sesión';

/// Con sesión abierta: la cuenta con que se liga.
String customerClaimSessionLine(String email) => 'Entraste como $email.';
const customerClaimLinkAccount = 'LIGAR A MI CUENTA';

const customerClaimChecking = 'Revisando el código…';
const customerClaimLinking = 'Creando tu cuenta…';
const customerClaimDone = 'Listo, tu cuenta quedó creada.';

const customerClaimVerifyTitle = 'Revisa tu correo';
String customerClaimVerifyBody(String email) =>
    'Te enviamos un enlace a $email. Al confirmarlo, tu cuenta queda lista.';

const customerClaimPhoneMissing = 'Ingresa tu teléfono.';

/// Lo que se le dice al cliente por cada respuesta que no liga.
String customerClaimProblem(String status) => switch (status) {
  'expired' => 'Este código venció. Pide uno nuevo en el taller.',
  'linked' => 'Esta ficha ya tiene cuenta. Inicia sesión para verla.',
  'phone_mismatch' =>
    'El teléfono no coincide con el registrado en el taller.',
  'linked_elsewhere' => 'Esta ficha ya está ligada a otra cuenta.',
  'account_has_history' || 'email_in_other_record' =>
    'Tu correo ya está en otra ficha de la tienda. Escríbenos y las unimos.',
  'too_many_attempts' => 'Demasiados intentos. Prueba de nuevo en una hora.',
  'unavailable' => 'No pudimos revisar el código. Intenta de nuevo.',
  _ => 'Este código no es válido. Pide uno nuevo en el taller.',
};

/// Las respuestas que dejan reintentar en la misma página (corregir el
/// teléfono, volver a probar); las demás cierran el formulario.
bool customerClaimProblemIsRetryable(String status) =>
    status == 'phone_mismatch' || status == 'unavailable';
