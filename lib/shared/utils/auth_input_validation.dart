abstract final class AuthInputValidation {
  static const String strongPasswordHelper =
      'Mínimo 8 caracteres, con al menos una letra y un número';
  static const String adminManagedPasswordHelper =
      '12 a 128 caracteres, con mayúscula, minúscula, número y símbolo';

  static String? validateEmail(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) {
      return 'Por favor ingrese su correo electrónico';
    }
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      return 'Por favor ingrese un correo válido';
    }
    return null;
  }

  static String? validatePassword(
    String? value, {
    required bool isNewPassword,
  }) {
    final password = value ?? '';
    if (password.isEmpty) {
      return 'Por favor ingrese su contraseña';
    }

    if (!isNewPassword) {
      if (password.length < 6) {
        return 'La contraseña debe tener al menos 6 caracteres';
      }
      return null;
    }

    if (password.length < 8) {
      return 'La contraseña debe tener al menos 8 caracteres';
    }
    if (!RegExp(r'[A-Za-z]').hasMatch(password) ||
        !RegExp(r'[0-9]').hasMatch(password)) {
      return 'Incluye al menos una letra y un número';
    }
    return null;
  }

  static String? validatePasswordConfirmation(
    String? value, {
    required String password,
  }) {
    if (value == null || value.isEmpty) {
      return 'Por favor confirme su contraseña';
    }
    if (value != password) {
      return 'Las contraseñas no coinciden';
    }
    return null;
  }

  /// Password policy for credentials set by an ERP administrator.
  ///
  /// These credentials are immediately usable by another person, so they use
  /// a stricter policy than self-service account passwords. The value is
  /// validated exactly as entered; callers must not trim or otherwise mutate
  /// it before sending it to the server.
  static String? validateAdminManagedPassword(String? value) {
    final password = value ?? '';
    if (password.isEmpty) {
      return 'Ingrese una contraseña';
    }
    if (password.length < 12 || password.length > 128) {
      return 'La contraseña debe tener entre 12 y 128 caracteres';
    }
    if (RegExp(r'[\x00-\x1F\x7F]').hasMatch(password)) {
      return 'La contraseña contiene caracteres de control no permitidos';
    }
    if (!RegExp(r'[A-Z]').hasMatch(password) ||
        !RegExp(r'[a-z]').hasMatch(password) ||
        !RegExp(r'[0-9]').hasMatch(password) ||
        !RegExp(r'[^A-Za-z0-9\s]').hasMatch(password)) {
      return 'Incluye mayúscula, minúscula, número y símbolo';
    }
    return null;
  }

  static String? validateShopName(String? value) {
    final shopName = value?.trim() ?? '';
    if (shopName.isEmpty) {
      return 'Por favor ingrese el nombre de su tienda';
    }
    if (shopName.length < 3) {
      return 'El nombre debe tener al menos 3 caracteres';
    }
    if (tenantSubdomain(shopName).length < 2) {
      return 'Incluye al menos dos letras o números en el nombre';
    }
    return null;
  }

  static String tenantSubdomain(String shopName) {
    var normalized = shopName.trim().toLowerCase();
    const replacements = <String, String>{
      'á': 'a',
      'é': 'e',
      'í': 'i',
      'ó': 'o',
      'ú': 'u',
      'ü': 'u',
      'ñ': 'n',
    };
    for (final replacement in replacements.entries) {
      normalized = normalized.replaceAll(replacement.key, replacement.value);
    }

    var slug = normalized
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '')
        .replaceAll(RegExp(r'-+'), '-');
    if (slug.length > 48) {
      slug = slug.substring(0, 48).replaceFirst(RegExp(r'-+$'), '');
    }
    return slug;
  }
}
