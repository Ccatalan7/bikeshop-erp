enum PublicCheckoutPaymentCode {
  mercadopago('mercadopago'),
  transfer('transfer');

  const PublicCheckoutPaymentCode(this.wireValue);

  final String wireValue;

  static PublicCheckoutPaymentCode? tryParse(Object? value) {
    final normalized = value?.toString().trim().toLowerCase();
    for (final code in values) {
      if (code.wireValue == normalized) return code;
    }
    return null;
  }
}

enum PublicCheckoutCapabilityReason {
  available('available'),
  configurationIncomplete('configuration_incomplete'),
  storeOriginInvalid('store_origin_invalid'),
  storefrontUnavailable('storefront_unavailable');

  const PublicCheckoutCapabilityReason(this.wireValue);

  final String wireValue;

  static PublicCheckoutCapabilityReason? tryParse(Object? value) {
    final normalized = value?.toString().trim().toLowerCase();
    for (final reason in values) {
      if (reason.wireValue == normalized) return reason;
    }
    return null;
  }
}

class PublicCheckoutPaymentCapability {
  const PublicCheckoutPaymentCapability({
    required this.code,
    required this.available,
    required this.reason,
  });

  final PublicCheckoutPaymentCode code;
  final bool available;
  final PublicCheckoutCapabilityReason reason;

  factory PublicCheckoutPaymentCapability.fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException('Medio de pago público inválido.');
    }
    final json = Map<String, dynamic>.from(value);
    final code = PublicCheckoutPaymentCode.tryParse(json['code']);
    final reason = PublicCheckoutCapabilityReason.tryParse(json['reasonCode']);
    final available = json['available'];
    if (code == null || reason == null || available is! bool) {
      throw const FormatException('Medio de pago público incompleto.');
    }
    if (available != (reason == PublicCheckoutCapabilityReason.available)) {
      throw const FormatException('Disponibilidad de pago incoherente.');
    }
    return PublicCheckoutPaymentCapability(
      code: code,
      available: available,
      reason: reason,
    );
  }
}

class PublicCheckoutCapabilities {
  const PublicCheckoutCapabilities({
    required this.methods,
  });

  final List<PublicCheckoutPaymentCapability> methods;

  List<PublicCheckoutPaymentCode> get availableMethods => methods
      .where((method) => method.available)
      .map((method) => method.code)
      .toList(growable: false);

  bool isAvailable(String wireValue) {
    final code = PublicCheckoutPaymentCode.tryParse(wireValue);
    return code != null &&
        methods.any((method) => method.code == code && method.available);
  }

  factory PublicCheckoutCapabilities.fromRpc(Object? value) {
    if (value is! Map) {
      throw const FormatException(
        'La configuración pública de pagos no es válida.',
      );
    }
    final json = Map<String, dynamic>.from(value);
    if (json['schemaVersion'] != 1 || json['methods'] is! List) {
      throw const FormatException(
        'La configuración pública de pagos es incompatible.',
      );
    }

    final methods = (json['methods'] as List)
        .map(PublicCheckoutPaymentCapability.fromJson)
        .toList(growable: false);
    final uniqueCodes = methods.map((method) => method.code).toSet();
    if (methods.length != PublicCheckoutPaymentCode.values.length ||
        uniqueCodes.length != PublicCheckoutPaymentCode.values.length) {
      throw const FormatException(
        'La configuración pública de pagos está incompleta.',
      );
    }
    return PublicCheckoutCapabilities(methods: methods);
  }
}
