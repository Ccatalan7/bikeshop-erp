/// Cómo se saluda a una persona en un mensaje: «Hola <esto>, buen día».
///
/// Lo elige quien la conoce, en su ficha. Antes lo adivinaba una regla de
/// nombres compuestos, y el dueño (2026-11-19): «nunca la achunta. hay
/// personas que le dice los 2 nombres a los cuales solo hay que decirles 1 y
/// a los que hay que decirles 2 les dice 1». Se guarda en
/// `supplier_contacts.greeting_style` / `greeting_custom_name`
/// (20261119200000).
enum ContactGreetingStyle {
  /// La primera palabra del nombre. Es lo que se usa si nadie eligió.
  firstName('first_name'),

  /// Los dos primeros nombres, con los «de», «del», «la», «las» o «los» que
  /// haya entremedio: «María José», «María de los Ángeles».
  twoNames('two_names'),

  /// Un texto propio, tal cual: «Majo», «Don Pedro».
  custom('custom');

  const ContactGreetingStyle(this.wireValue);

  /// El valor de `greeting_style` en la base.
  final String wireValue;

  static ContactGreetingStyle fromWire(Object? value) {
    final text = value?.toString().trim();
    for (final style in values) {
      if (style.wireValue == text) return style;
    }
    return firstName;
  }
}

/// El texto personalizado máximo; el mismo tope que la tabla.
const int contactGreetingCustomMaxLength = 60;

final RegExp _firstWord = RegExp(r'^\S+');
final RegExp _twoGivenNames = RegExp(
  r'^\S+(?:\s+(?:de|del|la|las|los))*\s+\S+',
  caseSensitive: false,
);

/// Deja un texto en una sola línea con espacios simples: así viaja dentro de
/// una plantilla de WhatsApp, que rechaza saltos de línea y espacios
/// repetidos. Es la misma limpieza que hace `save_supplier_contact`.
String normalizeContactGreeting(String value) =>
    value.replaceAll(RegExp(r'\s+'), ' ').trim();

/// El nombre con que se saluda a [fullName] según [style].
///
/// Es la única regla: la usan el formulario del contacto mientras se elige,
/// el chat del proveedor y la orden de compra. Un personalizado sin texto
/// vuelve al primer nombre; un nombre de una sola palabra es el mismo con
/// uno o con dos nombres.
String contactGreetingName({
  required String fullName,
  required ContactGreetingStyle style,
  String? customName,
}) {
  final name = normalizeContactGreeting(fullName);
  if (style == ContactGreetingStyle.custom) {
    final custom = normalizeContactGreeting(customName ?? '');
    if (custom.isNotEmpty) return custom;
  }
  if (style == ContactGreetingStyle.twoNames) {
    final two = _twoGivenNames.firstMatch(name)?.group(0);
    if (two != null) return two;
  }
  return _firstWord.firstMatch(name)?.group(0) ?? '';
}

/// El nombre que el ERP le pone a una persona que conoció sólo por un chat de
/// WhatsApp y a la que nadie ha nombrado (20260903103000, 20261013190000).
/// No es un nombre: no se saluda con él.
const String unnamedWhatsAppContactName = 'Contacto de WhatsApp';

/// [contactGreetingName], o null cuando no hay con qué saludar: sin nombre,
/// o con el nombre provisorio de un contacto que nadie ha nombrado (salvo
/// que le hayan escrito un saludo propio).
String? usableContactGreetingName({
  required String fullName,
  required ContactGreetingStyle style,
  String? customName,
}) {
  final greeting = contactGreetingName(
    fullName: fullName,
    style: style,
    customName: customName,
  );
  if (greeting.isEmpty) return null;
  final namedByHand = style == ContactGreetingStyle.custom &&
      normalizeContactGreeting(customName ?? '').isNotEmpty;
  if (!namedByHand &&
      normalizeContactGreeting(fullName) == unnamedWhatsAppContactName) {
    return null;
  }
  return greeting;
}
