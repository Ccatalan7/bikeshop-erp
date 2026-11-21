/// Cómo se saluda a una persona en un mensaje: «Hola …, buen día».
///
/// Lo elige quien la conoce: el taller en la ficha (un contacto de proveedor
/// o un cliente) y el cliente mismo en «Mi cuenta» de la tienda. Antes lo
/// adivinaba una regla de nombres compuestos, y el dueño (2026-11-19):
/// «nunca la achunta. hay personas que le dice los 2 nombres a los cuales
/// solo hay que decirles 1 y a los que hay que decirles 2 les dice 1».
///
/// Se guarda en `supplier_contacts` (20261119200000) y en `customers`
/// (20261121200000) como `greeting_style` / `greeting_custom_name`. La misma
/// regla vive en la base como `contact_greeting_name_internal`, para los
/// avisos y correos que arma el servidor: las dos se prueban con los mismos
/// casos (`test/unit/contact_greeting_test.dart` y
/// `supabase/tests/customer_greeting.sql`).
enum ContactGreetingStyle {
  /// La primera palabra del nombre. Es lo que se usa si nadie eligió.
  firstName('first_name', 'Primer nombre'),

  /// Los dos primeros nombres, con los «de», «del», «la», «las» o «los» que
  /// haya entremedio: «María José», «María de los Ángeles».
  twoNames('two_names', 'Dos nombres'),

  /// Sólo el segundo nombre: «José» de «María José».
  secondName('second_name', 'Segundo nombre'),

  /// El nombre tal como quedó registrado, entero.
  fullName('full_name', 'Nombre completo'),

  /// Un texto propio, tal cual: «Majo», «Don Pedro».
  custom('custom', 'Personalizado');

  const ContactGreetingStyle(this.wireValue, this.label);

  /// El valor de `greeting_style` en la base.
  final String wireValue;

  /// Cómo se nombra la opción («Dos nombres»).
  final String label;

  static ContactGreetingStyle fromWire(Object? value) {
    final text = value?.toString().trim();
    for (final style in values) {
      if (style.wireValue == text) return style;
    }
    return firstName;
  }
}

/// Lo que se puede elegir para un contacto de proveedor (20261119200000).
const List<ContactGreetingStyle> supplierContactGreetingStyles = [
  ContactGreetingStyle.firstName,
  ContactGreetingStyle.twoNames,
  ContactGreetingStyle.custom,
];

/// El texto personalizado máximo; el mismo tope que las tablas.
const int contactGreetingCustomMaxLength = 60;

const Set<String> _particles = {'de', 'del', 'la', 'las', 'los'};

/// Deja un texto en una sola línea con espacios simples: así viaja dentro de
/// una plantilla de WhatsApp, que rechaza saltos de línea y espacios
/// repetidos. Es la misma limpieza que hacen los guardados de la base.
String normalizeContactGreeting(String value) =>
    value.replaceAll(RegExp(r'\s+'), ' ').trim();

bool _isParticle(String word) => _particles.contains(word.toLowerCase());

/// Una palabra del nombre como se escribe en un saludo: «JUAN» y «juan» son
/// «Juan»; un «de» entremedio queda en minúscula; lo que mezcla mayúsculas
/// («McDonald», «De La Cruz») queda como lo escribieron.
String _tidyWord(String word, int index) {
  final upper = word.toUpperCase();
  final lower = word.toLowerCase();
  if (upper == lower) return word;
  final allUpper = word == upper && word.length > 1;
  final allLower = word == lower;
  if (!allUpper && !allLower) return word;
  if (index > 0 && _isParticle(word)) return lower;
  final first = String.fromCharCode(word.runes.first);
  return first.toUpperCase() + word.substring(first.length).toLowerCase();
}

String _tidy(List<String> words, int from, int to) => [
      for (var i = from; i <= to; i++) _tidyWord(words[i], i),
    ].join(' ');

/// El nombre con que se saluda a [fullName] según [style].
///
/// Es la única regla: la usan los formularios mientras se elige, el chat, la
/// orden de compra y el portal. Un personalizado sin texto vuelve al primer
/// nombre; un nombre de una sola palabra es el mismo con cualquier opción.
String contactGreetingName({
  required String fullName,
  required ContactGreetingStyle style,
  String? customName,
}) {
  if (style == ContactGreetingStyle.custom) {
    final custom = normalizeContactGreeting(customName ?? '');
    if (custom.isNotEmpty) return custom;
  }
  final name = normalizeContactGreeting(fullName);
  if (name.isEmpty) return '';
  final words = name.split(' ');
  // El segundo nombre es la primera palabra después de la primera que no es
  // un «de», «del», «la», «las» o «los» (o la última, si sólo quedan ésos).
  var second = 1;
  while (second < words.length - 1 && _isParticle(words[second])) {
    second++;
  }
  final hasSecond = second < words.length;
  return switch (style) {
    ContactGreetingStyle.twoNames when hasSecond => _tidy(words, 0, second),
    ContactGreetingStyle.secondName when hasSecond =>
      _tidyWord(words[second], second),
    ContactGreetingStyle.fullName => _tidy(words, 0, words.length - 1),
    _ => _tidyWord(words.first, 0),
  };
}

/// Una opción para elegir: cómo se llama y el saludo que da.
class ContactGreetingChoice {
  const ContactGreetingChoice(this.style, this.greeting);

  final ContactGreetingStyle style;

  /// El nombre del saludo con esta opción; vacío para «Personalizado».
  final String greeting;
}

/// Las opciones que vale la pena mostrar para [fullName], en orden: cada
/// nombre una sola vez («Pedro Soto» con dos nombres y completo es el mismo
/// saludo) y «Personalizado» al final. Se eligen mirando el nombre, no la
/// etiqueta: «María», «María José», «José».
List<ContactGreetingChoice> contactGreetingChoices(
  String fullName, {
  List<ContactGreetingStyle> styles = ContactGreetingStyle.values,
}) {
  final seen = <String>{};
  final choices = <ContactGreetingChoice>[];
  for (final style in styles) {
    if (style == ContactGreetingStyle.custom) continue;
    final greeting = contactGreetingName(fullName: fullName, style: style);
    if (greeting.isEmpty || !seen.add(greeting.toLowerCase())) continue;
    choices.add(ContactGreetingChoice(style, greeting));
  }
  if (styles.contains(ContactGreetingStyle.custom)) {
    choices.add(const ContactGreetingChoice(ContactGreetingStyle.custom, ''));
  }
  return choices;
}

/// La opción que se ve elegida: la de [style], o la primera que da el mismo
/// saludo cuando ésa no se muestra por repetida.
ContactGreetingStyle shownContactGreetingStyle(
  String fullName,
  ContactGreetingStyle style, {
  List<ContactGreetingStyle> styles = ContactGreetingStyle.values,
}) {
  if (style == ContactGreetingStyle.custom) return style;
  final greeting = contactGreetingName(fullName: fullName, style: style);
  for (final choice in contactGreetingChoices(fullName, styles: styles)) {
    if (choice.style == style) return style;
    if (choice.greeting.toLowerCase() == greeting.toLowerCase()) {
      return choice.style;
    }
  }
  return style;
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
