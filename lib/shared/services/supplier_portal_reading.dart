/// Cómo se lee lo que dijo el portal de un proveedor.
///
/// Vive aparte del navegador a propósito: son reglas de negocio, se prueban sin
/// una pantalla, y son las mismas para todos los portales aunque cada uno hable
/// distinto.
///
/// La regla que gobierna todo esto: **el estado que parece un cero casi nunca
/// es un cero.** Una sesión caída, un producto agotado escondido por un filtro
/// y un código que cambió producen la misma pantalla vacía, y cada uno pide una
/// acción distinta.
library;

/// Lo que la sonda encontró en la página, sin interpretar.
class SupplierPortalObservation {
  const SupplierPortalObservation({
    required this.code,
    required this.url,
    required this.bodyText,
    required this.hasPasswordField,
  });

  final String code;
  final String url;
  final String bodyText;
  final bool hasPasswordField;
}

/// Cómo consultar e interpretar UN portal. Es la fila de configuración.
class SupplierPortalProbe {
  const SupplierPortalProbe({
    required this.searchUrlTemplate,
    this.loggedOutPattern,
    this.notFoundPattern,
    this.pricePattern,
    this.stockPattern,
    this.outOfStockPattern,
  });

  final String searchUrlTemplate;
  final String? loggedOutPattern;
  final String? notFoundPattern;
  final String? pricePattern;
  final String? stockPattern;
  final String? outOfStockPattern;

  /// El código va codificado: un código con espacios o `&` rompería la consulta
  /// y devolvería la página equivocada sin avisar.
  String urlForCode(String code) => searchUrlTemplate.replaceAll(
        '{code}',
        Uri.encodeQueryComponent(code.trim()),
      );
}

enum SupplierAvailabilityStatus {
  available,
  outOfStock,
  notFound,
  sessionExpired,
  unreadable,
}

extension SupplierAvailabilityStatusWire on SupplierAvailabilityStatus {
  String get wireName => switch (this) {
        SupplierAvailabilityStatus.available => 'available',
        SupplierAvailabilityStatus.outOfStock => 'out_of_stock',
        SupplierAvailabilityStatus.notFound => 'not_found',
        SupplierAvailabilityStatus.sessionExpired => 'session_expired',
        SupplierAvailabilityStatus.unreadable => 'unreadable',
      };
}

class SupplierPortalReading {
  const SupplierPortalReading({
    required this.status,
    this.priceNet,
    this.stockQuantity,
  });

  final SupplierAvailabilityStatus status;
  final double? priceNet;
  final double? stockQuantity;

  /// Los estados sin prueba no llevan números. La base lo rechaza igual, pero
  /// la regla se escribe donde se decide, no sólo donde se guarda.
  bool get carriesNumbers =>
      status == SupplierAvailabilityStatus.available ||
      status == SupplierAvailabilityStatus.outOfStock;
}

/// Lee la observación con la configuración de ese portal.
///
/// El orden importa y es de la afirmación más fuerte a la más débil:
///
///  1. **¿Hay sesión?** Sin sesión no hay nada que interpretar, y contar eso
///     como cero haría comprar de más. Es lo primero que se pregunta.
///  2. **¿El portal lo mostró?** Si no, es `not_found` — y eso significa
///     exactamente «no lo mostró», nunca «no lo vende».
///  3. **¿Dijo cero?** Un cero LEÍDO es un cero demostrado.
///  4. **¿Cuánto hay y a qué precio?** Un portal que no publica cantidad
///     —RBX— informa presencia y precio, y la cantidad queda nula. Nula no es
///     cero.
SupplierPortalReading readSupplierPortal(
  SupplierPortalObservation observation,
  SupplierPortalProbe probe,
) {
  final body = observation.bodyText;

  bool matches(String? pattern) {
    if (pattern == null || pattern.trim().isEmpty) return false;
    try {
      return RegExp(pattern, caseSensitive: false, unicode: true)
          .hasMatch(body);
    } catch (_) {
      // Una expresión mal escrita en la configuración no puede hacer pasar por
      // verdadera una condición que nadie comprobó.
      return false;
    }
  }

  if (observation.hasPasswordField || matches(probe.loggedOutPattern)) {
    return const SupplierPortalReading(
      status: SupplierAvailabilityStatus.sessionExpired,
    );
  }

  if (matches(probe.notFoundPattern)) {
    return const SupplierPortalReading(
      status: SupplierAvailabilityStatus.notFound,
    );
  }

  // El código tiene que aparecer como palabra: «1128» dentro de «11285»
  // respondería por un producto que no es el que se preguntó.
  final code = observation.code.trim();
  if (code.isNotEmpty) {
    final escaped = RegExp.escape(code);
    final seen = RegExp('(^|[^0-9A-Za-z])$escaped([^0-9A-Za-z]|\$)',
            caseSensitive: false)
        .hasMatch(body);
    if (!seen) {
      return const SupplierPortalReading(
        status: SupplierAvailabilityStatus.notFound,
      );
    }
  }

  final stock = _lastNumber(body, probe.stockPattern);
  final price = _lastNumber(body, probe.pricePattern);

  if (matches(probe.outOfStockPattern) || (stock != null && stock <= 0)) {
    return SupplierPortalReading(
      status: SupplierAvailabilityStatus.outOfStock,
      stockQuantity: 0,
      priceNet: price,
    );
  }

  // Sin precio ni cantidad la página respondió algo que la sonda no supo leer.
  // Decir «disponible» ahí sería afirmar sobre nada.
  if (price == null && stock == null) {
    return const SupplierPortalReading(
      status: SupplierAvailabilityStatus.unreadable,
    );
  }

  return SupplierPortalReading(
    status: SupplierAvailabilityStatus.available,
    priceNet: price,
    stockQuantity: stock,
  );
}

/// La ÚLTIMA coincidencia, no la primera.
///
/// Una ficha con descuento muestra «Antes $8.850» y después «$6.195». La
/// segunda es la que se paga; tomar la primera informaría un precio 43% más
/// alto que el real (medido en MKR, 2026-08-23).
double? _lastNumber(String body, String? pattern) {
  if (pattern == null || pattern.trim().isEmpty) return null;
  RegExp expression;
  try {
    expression = RegExp(pattern, caseSensitive: false, unicode: true);
  } catch (_) {
    return null;
  }
  String? raw;
  for (final match in expression.allMatches(body)) {
    if (match.groupCount < 1) continue;
    final value = match.group(1);
    if (value != null && value.trim().isNotEmpty) raw = value.trim();
  }
  if (raw == null) return null;
  // «$ 8.850» es ocho mil ochocientos cincuenta, no ocho con ochenta y cinco:
  // el punto es separador de miles en Chile.
  final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return null;
  return double.tryParse(digits);
}
