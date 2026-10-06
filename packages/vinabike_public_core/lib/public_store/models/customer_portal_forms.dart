// The portal's forms (2026-10-06): what «Perfil y seguridad» and
// «Direcciones» ask for, the words they answer with and what a save writes.
// The Flutter pages and the HTML store's portal use these, so a rule or a
// message changes in one place.
import '../../shared/models/customer_address.dart';
import '../../shared/utils/self_password_rules.dart';

// =============================================================== the profile

/// «Nombre completo» is the one field a customer must fill.
String? customerProfileNameError(String? value) =>
    value == null || value.trim().isEmpty ? 'Escribe tu nombre' : null;

/// The columns «Guardar cambios» writes, trimmed. An emptied RUT or phone is
/// cleared (before 2026-10-06 it was kept, so the old value came back). The
/// database lets a customer change only these (`guard_customer_identity_update`).
Map<String, Object?> customerProfileChanges({
  required String name,
  required String phone,
  required String rut,
  required DateTime now,
}) {
  String? optional(String value) {
    final text = value.trim();
    return text.isEmpty ? null : text;
  }

  return {
    'name': name.trim(),
    'phone': optional(phone),
    'rut': optional(rut),
    'updated_at': now.toUtc().toIso8601String(),
  };
}

const customerProfileSaved = 'Guardamos tus datos.';
const customerProfileSaveFailed =
    'No pudimos guardar tus datos. Inténtalo nuevamente.';

// ============================================================ the password

const customerPasswordIntro =
    'Elige una contraseña nueva. Si tu sesión requiere una verificación '
    'adicional, te enviaremos un código.';
const customerPasswordUpdated =
    'Contraseña actualizada y demás sesiones cerradas.';
const customerPasswordUpdateFailed =
    'No pudimos actualizar la contraseña. Inténtalo nuevamente.';
const customerVerificationSent =
    'Enviamos un código de verificación a tu correo asociado.';
const customerVerificationResent =
    'Enviamos un código nuevo. Usa solamente el último recibido.';
const customerVerificationSendFailedOffline =
    'No pudimos enviar el código. Revisa tu conexión e inténtalo nuevamente.';
const customerVerificationCheckFailed =
    'No pudimos verificar el código. Inténtalo nuevamente.';
const customerRevocationIntro =
    'No pudimos cerrar las demás sesiones. Puedes reintentar solamente ese '
    'cierre; no necesitas volver a ingresar ni cambiar tu contraseña.';
const customerRevocationRetryFailed =
    'La contraseña sigue actualizada, pero no pudimos cerrar las demás '
    'sesiones. Revisa tu conexión y reintenta.';
const customerRevocationRetryBroken =
    'La contraseña sigue actualizada, pero no pudimos cerrar las demás '
    'sesiones. Reintenta desde Seguridad.';
const customerRevocationPendingTitle =
    'Quedó pendiente cerrar las demás sesiones.';
const customerRevocationPendingMessage =
    'No vuelvas a cambiar la contraseña: puedes reintentar solamente el '
    'cierre de sesiones.';

/// The answer when Auth refuses the new password itself.
String customerPasswordIssueMessage(SelfPasswordUpdateIssue issue) =>
    issue == SelfPasswordUpdateIssue.samePassword
    ? 'La nueva contraseña debe ser distinta a la contraseña actual.'
    : customerPasswordUpdateFailed;

/// The answer when Auth refuses the verification code.
String customerVerificationIssueMessage(SelfPasswordUpdateIssue issue) =>
    switch (issue) {
      SelfPasswordUpdateIssue.invalidVerificationCode =>
        'El código no es válido. Revísalo e inténtalo nuevamente.',
      SelfPasswordUpdateIssue.expiredVerificationCode =>
        'El código venció. Solicita uno nuevo para continuar.',
      SelfPasswordUpdateIssue.reauthenticationRequired =>
        'El código venció o ya no es válido. Solicita uno nuevo.',
      SelfPasswordUpdateIssue.samePassword =>
        'La nueva contraseña debe ser distinta a la contraseña actual.',
      SelfPasswordUpdateIssue.unknown => customerVerificationCheckFailed,
    };

/// The answer when Auth refuses to send a code (`code` from its error).
String customerReauthenticationRequestMessage(String? code) =>
    selfPasswordRateLimited(code)
    ? 'Espera un momento antes de solicitar otro código.'
    : 'No pudimos enviar el código. Inténtalo nuevamente.';

/// The code Auth mails is six digits.
String? customerVerificationCodeError(String? value) {
  final code = value?.trim() ?? '';
  return RegExp(r'^\d{6}$').hasMatch(code)
      ? null
      : 'Ingresa los 6 dígitos del código.';
}

/// What the verification step says, with the address the code went to.
String customerVerificationPrompt(String? email) {
  final address = email?.trim() ?? '';
  return address.isNotEmpty
      ? 'Ingresa el código de 6 dígitos enviado a $address.'
      : 'Ingresa el código de 6 dígitos enviado a tu correo asociado.';
}

// =========================================================== the addresses

/// What an empty required field of the address form says.
const customerAddressRequired = 'Requerido';

/// The address form's required fields (`customer_addresses` columns).
const customerAddressRequiredFields = {
  'label',
  'recipient_name',
  'phone',
  'street_address',
  'comuna',
  'city',
  'region',
};

const customerAddressSaveFailed =
    'No pudimos guardar la dirección. Intenta de nuevo.';
const customerAddressDeleteFailed =
    'No pudimos eliminar la dirección. Intenta de nuevo.';
const customerAddressDefaultFailed =
    'No pudimos cambiar la principal. Intenta de nuevo.';
const customerAddressPlaceFailed = 'No pudimos cargar esa dirección';

/// The principal first, then as read (newest first).
List<CustomerAddress> customerAddressesInOrder(
  Iterable<CustomerAddress> addresses,
) =>
    List<CustomerAddress>.from(addresses)
      ..sort((a, b) => (b.isDefault ? 1 : 0) - (a.isDefault ? 1 : 0));

/// Who receives at an address, as its row shows it.
String customerAddressContact(CustomerAddress address) => [
  address.recipientName.trim(),
  address.phone.trim(),
].where((part) => part.isNotEmpty).join(' · ');

/// Whether an address already uses the account's name and phone, so «Usar
/// mis datos de cuenta» starts checked.
bool customerAddressUsesProfileContact(
  CustomerAddress? address, {
  required String profileName,
  required String profilePhone,
}) =>
    address != null &&
    profileName.isNotEmpty &&
    profilePhone.isNotEmpty &&
    address.recipientName.trim() == profileName &&
    address.phone.trim() == profilePhone;

/// What «Usar mis datos de cuenta» shows under its title.
String customerProfileContactLabel({
  required String profileName,
  required String profilePhone,
}) => profileName.isNotEmpty && profilePhone.isNotEmpty
    ? [profileName, profilePhone].join(' · ')
    : 'Agrega nombre y teléfono en tu perfil para reutilizarlos.';

/// The `customer_addresses` columns a save writes from the form's values
/// (trimmed; an empty optional field is `null`). The id, the customer and
/// the store are the caller's.
Map<String, Object?> customerAddressChanges(
  Map<String, String> values, {
  required bool isDefault,
  String? postalCode,
  required DateTime now,
}) {
  String text(String key) => (values[key] ?? '').trim();
  String? optional(String key) => text(key).isEmpty ? null : text(key);
  final postal = postalCode?.trim();
  return {
    'label': text('label'),
    'recipient_name': text('recipient_name'),
    'phone': text('phone'),
    'street_address': text('street_address'),
    'street_number': optional('street_number'),
    'apartment': optional('apartment'),
    'comuna': text('comuna'),
    'city': text('city'),
    'region': text('region'),
    'postal_code': postal == null || postal.isEmpty ? null : postal,
    'additional_info': optional('additional_info'),
    'is_default': isDefault,
    'updated_at': now.toUtc().toIso8601String(),
  };
}

/// A required field of the address form: spaces alone do not fill it (they
/// used to, and saved it empty).
String? customerAddressRequiredError(String? value) =>
    (value ?? '').trim().isEmpty ? customerAddressRequired : null;

/// The form's errors, by column; empty when it can be saved.
Map<String, String> customerAddressErrors(Map<String, String> values) => {
  for (final field in customerAddressRequiredFields)
    field: ?customerAddressRequiredError(values[field]),
};
