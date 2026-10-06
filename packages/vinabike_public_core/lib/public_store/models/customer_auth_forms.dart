// The way into the account, «Iniciar sesión» (2026-10-06): what the login
// page says in each of its modes, what each field asks for and the words it
// answers with. The Flutter page and the HTML store's login use these, so a
// rule or a message changes in one place.
import '../../shared/utils/auth_input_validation.dart';

/// What the page is doing: entering, creating an account, or one of the two
/// e-mail links that set a password (only Flutter draws those).
enum CustomerAuthMode { login, register, recovery, invitation }

const customerAuthEyebrow = 'CUENTA VINABIKE';

/// The intro's headline, beside (or above) the form.
String customerAuthHeadline(CustomerAuthMode mode) => switch (mode) {
  CustomerAuthMode.invitation =>
    'Crea tu primera contraseña para activar el acceso.',
  CustomerAuthMode.recovery =>
    'Crea una nueva contraseña para recuperar tu acceso.',
  CustomerAuthMode.login =>
    'Ingresa para revisar pedidos, bicicletas y soporte desde un solo lugar.',
  CustomerAuthMode.register =>
    'Crea tu cuenta para guardar tus datos, seguir tus pedidos y acceder a '
        'tu historial.',
};

String customerAuthLead(CustomerAuthMode mode) => switch (mode) {
  CustomerAuthMode.invitation =>
    'Este enlace de invitación confirma tu correo. Define una clave fuerte y '
        'luego inicia sesión.',
  CustomerAuthMode.recovery =>
    'Este enlace seguro confirma tu identidad. Define una clave nueva y '
        'entrarás directo a tu cuenta.',
  CustomerAuthMode.login =>
    'Una experiencia más ordenada, rápida y clara que el checkout improvisado '
        'de invitado.',
  CustomerAuthMode.register =>
    'Todo queda asociado a tu cuenta para futuras compras, seguimiento y '
        'atención postventa.',
};

/// The three things an account gives, in order: the icon's name (Material's
/// outlined set), the title and the line under it.
const customerAuthBenefits = <(String, String, String)>[
  (
    'shopping_bag',
    'Pedidos y seguimiento',
    'Consulta compras, estados y confirmaciones en un solo panel.',
  ),
  (
    'pedal_bike',
    'Historial de bicicletas',
    'Accede a tus bicicletas registradas y próximos servicios.',
  ),
  (
    'support_agent',
    'Atención más rápida',
    'Mantén tus datos listos para soporte, mensajes y futuras compras.',
  ),
];

const customerAuthBackHome = 'Volver al inicio';

String customerAuthFormTitle(CustomerAuthMode mode) => switch (mode) {
  CustomerAuthMode.invitation => 'Crea tu contraseña',
  CustomerAuthMode.recovery => 'Nueva contraseña',
  CustomerAuthMode.login => 'Iniciar sesión',
  CustomerAuthMode.register => 'Crear cuenta',
};

String customerAuthFormLead(CustomerAuthMode mode) => switch (mode) {
  CustomerAuthMode.invitation =>
    'Define una contraseña segura para terminar de activar tu cuenta.',
  CustomerAuthMode.recovery =>
    'Ingresa una contraseña nueva para terminar la recuperación.',
  CustomerAuthMode.login => 'Usa tu correo y contraseña para continuar.',
  CustomerAuthMode.register =>
    'Completa tus datos para guardar tus compras e historial.',
};

// ================================================================ the fields

const customerAuthNameLabel = 'Nombre completo';
const customerAuthNameHint = 'Tu nombre y apellido';
const customerAuthEmailLabel = 'Correo electrónico';
const customerAuthEmailHint = 'nombre@correo.com';
const customerAuthPhoneLabel = 'Teléfono';
const customerAuthPhoneHint = '+56 9 1234 5678';
const customerAuthPasswordLabel = 'Contraseña';

String customerAuthPasswordHint(CustomerAuthMode mode) =>
    mode == CustomerAuthMode.login
    ? 'Tu contraseña'
    : AuthInputValidation.strongPasswordHelper;

String? customerAuthNameError(String? value) =>
    value == null || value.trim().isEmpty ? 'El nombre es requerido' : null;

String? customerAuthEmailError(String? value) {
  if (value == null || value.trim().isEmpty) return 'El correo es requerido';
  if (!value.contains('@')) return 'Ingresa un correo válido';
  return null;
}

/// A new account's password is held to the strong rule; entering, to the
/// one every existing account met.
String? customerAuthPasswordError(String? value, CustomerAuthMode mode) =>
    AuthInputValidation.validatePassword(
      value,
      isNewPassword: mode != CustomerAuthMode.login,
    );

/// The message under each field of [mode]'s form that does not pass, by the
/// field's name (`name`, `email`, `password`); empty when the form can go.
Map<String, String> customerAuthErrors(
  CustomerAuthMode mode,
  Map<String, String> values,
) => {
  if (mode == CustomerAuthMode.register)
    'name': ?customerAuthNameError(values['name']),
  'email': ?customerAuthEmailError(values['email']),
  'password': ?customerAuthPasswordError(values['password'], mode),
};

String customerAuthSubmit(CustomerAuthMode mode) => switch (mode) {
  CustomerAuthMode.invitation => 'CREAR CONTRASEÑA',
  CustomerAuthMode.recovery => 'ACTUALIZAR CONTRASEÑA',
  CustomerAuthMode.login => 'INICIAR SESIÓN',
  CustomerAuthMode.register => 'CREAR CUENTA',
};

const customerAuthOr = 'o continúa con';

String customerAuthGoogle(CustomerAuthMode mode) =>
    mode == CustomerAuthMode.login
    ? 'Continuar con Google'
    : 'Registrarse con Google';

String customerAuthSwitchQuestion(CustomerAuthMode mode) =>
    mode == CustomerAuthMode.login
    ? '¿No tienes cuenta?'
    : '¿Ya tienes cuenta?';

String customerAuthSwitchAction(CustomerAuthMode mode) =>
    mode == CustomerAuthMode.login ? 'Regístrate' : 'Inicia sesión';

const customerAuthForgot = '¿Olvidaste tu contraseña?';

// ============================================================ what it answers

const customerAuthSignInFailed =
    'No pudimos iniciar sesión. Revisa tus datos e inténtalo nuevamente.';
const customerAuthSignUpFailed =
    'No pudimos crear la cuenta con estos datos. Inténtalo nuevamente.';
const customerAuthGoogleFailed =
    'No pudimos iniciar sesión con Google. Inténtalo nuevamente.';

/// The bar after an account is created and its e-mail must be confirmed.
String customerAuthVerificationSent(String email) =>
    'Te enviamos un correo a $email para confirmar tu cuenta.';

const customerAuthConfirmedNotice =
    'Tu cuenta ha sido confirmada. Ahora puedes iniciar sesión.';
const customerAuthVerifyTitle = 'Confirma tu correo';

String customerAuthVerifyBody(String email) =>
    'Enviamos un correo a $email. Revisa tu bandeja de entrada y activa tu '
    'cuenta desde el enlace recibido.';

const customerAuthResend = 'Reenviar correo';
const customerAuthResent = 'Hemos reenviado el correo de verificación.';
const customerAuthResendFailed =
    'No pudimos reenviar el correo. Inténtalo nuevamente.';

/// What the page says when an e-mail link that set a password sends the
/// customer back to it (`?clave=`): Flutter draws those links, and the login
/// it returns to is the HTML store's.
const customerAuthPasswordRecovered =
    'Contraseña actualizada. Inicia sesión con tu nueva clave.';
const customerAuthPasswordCreated =
    'Contraseña creada. Inicia sesión para entrar a tu cuenta.';

/// `?clave=` of the login: which of the two messages above it shows.
const customerAuthPasswordNoticeParameter = 'clave';

String? customerAuthPasswordNotice(String? value) => switch (value) {
  'actualizada' => customerAuthPasswordRecovered,
  'creada' => customerAuthPasswordCreated,
  _ => null,
};

// ================================================== «¿Olvidaste tu contraseña?»

const customerResetTitle = 'Recuperar contraseña';
const customerResetBody =
    'Ingresa tu correo y enviaremos un enlace seguro para restablecer el '
    'acceso.';
const customerResetCancel = 'Cancelar';
const customerResetSend = 'Enviar enlace';

/// Said whether or not the address has an account, so the page never tells.
const customerResetSent =
    'Si existe una cuenta asociada, recibirás un correo para continuar con la '
    'recuperación.';
const customerResetRateLimited =
    'Demasiados intentos. Espera unos minutos y reintenta.';
const customerResetOffline =
    'No pudimos conectarnos al servicio. Revisa tu conexión e inténtalo '
    'nuevamente.';

/// Whether Supabase Auth refused a recovery e-mail for sending too many.
bool customerResetIsRateLimited({String? code, String message = ''}) {
  final text = '${code ?? ''} $message'.toLowerCase();
  return text.contains('rate limit') || text.contains('rate_limit');
}

// ============================================================== the account

/// The phone typed when the account was created, to keep in the store's
/// customer when it has none: Supabase keeps it with the account
/// (`user_metadata.phone`) until the e-mail is confirmed, and the customer
/// is created only then (`provision_current_public_store_customer`), without
/// it. Before 2026-10-06 only an account opened without confirmation kept it.
String? customerSignupPhone({
  required Object? profilePhone,
  required Object? userMetadata,
}) {
  if ((profilePhone?.toString().trim() ?? '').isNotEmpty) return null;
  final phone = userMetadata is Map ? userMetadata['phone'] : null;
  final text = phone is String ? phone.trim() : '';
  return text.isEmpty ? null : text;
}
