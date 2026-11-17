import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// La libreta del campo «Para» del correo integrado.
///
/// El dueño (2026-11-16): «la lista de correos como de destinatarios posibles
/// que aparezcan ahí en nuestro correo que está integrado, aparezcan todos los
/// correos que tú agregaste a los proveedores formales… aparte de los que
/// vayamos usando y vayamos agregando como contacto y como en cualquier otra
/// aplicación de email».
///
/// La arma el servidor en una sola lectura (`mail_recipient_directory_v1`,
/// 20261116220000): proveedores activos con su correo, su vendedor y sus
/// contactos; clientes activos; y las direcciones a las que el taller ya
/// escribió. Lo enviado desde la app se suma acá al tiro, porque `mail-sync`
/// lo trae al servidor unos minutos después.

/// De dónde sale una dirección de la libreta.
enum MailRecipientKind { supplier, customer, sent }

@immutable
class MailRecipient {
  const MailRecipient({
    required this.address,
    required this.kind,
    this.name,
    this.org,
    this.logoUrl,
    this.uses = 0,
    this.lastUsed,
  });

  factory MailRecipient.fromJson(Map<String, dynamic> json) {
    final kind = switch (json['kind']) {
      'supplier' => MailRecipientKind.supplier,
      'customer' => MailRecipientKind.customer,
      _ => MailRecipientKind.sent,
    };
    return MailRecipient(
      address: (json['address'] as String? ?? '').trim().toLowerCase(),
      kind: kind,
      name: _blankToNull(json['name']),
      org: _blankToNull(json['org']),
      logoUrl: _blankToNull(json['logo']),
      uses: (json['uses'] as num?)?.toInt() ?? 0,
      lastUsed: DateTime.tryParse(json['last_used'] as String? ?? ''),
    );
  }

  /// Siempre en minúsculas y sin espacios.
  final String address;
  final MailRecipientKind kind;

  /// La persona o el proveedor; sin nombre conocido, null.
  final String? name;

  /// De quién es la dirección cuando no es el mismo nombre: el proveedor de
  /// un contacto, o lo que el correo sabe del dominio (un banco, un courier).
  final String? org;

  /// El logo del proveedor o la foto del cliente.
  final String? logoUrl;

  /// Cuántas veces le escribió el taller, y la última.
  final int uses;
  final DateTime? lastUsed;

  /// Lo que se lee primero: el nombre, o la dirección si no hay nombre.
  String get title => name ?? address;

  /// La línea de abajo: la dirección (si arriba va un nombre) y de quién es.
  String? get detail {
    final owner = org ??
        switch (kind) {
          MailRecipientKind.supplier => 'Proveedor',
          MailRecipientKind.customer => 'Cliente',
          MailRecipientKind.sent => null,
        };
    final parts = [if (name != null) address, if (owner != null) owner];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  /// Lo que dibuja la marca: el logo es del proveedor, así que sus iniciales
  /// lo reemplazan si la imagen no carga; sin logo, la persona.
  String get markName =>
      logoUrl != null ? (org ?? name ?? address) : (name ?? org ?? address);

  MailRecipient usedAt(DateTime at, {int times = 1}) => MailRecipient(
        address: address,
        kind: kind,
        name: name,
        org: org,
        logoUrl: logoUrl,
        uses: uses + times,
        lastUsed: lastUsed == null || at.isAfter(lastUsed!) ? at : lastUsed,
      );
}

String? _blankToNull(Object? value) {
  final text = (value as String?)?.trim();
  return text == null || text.isEmpty ? null : text;
}

List<MailRecipient> parseMailRecipients(Object? raw) {
  if (raw is! List) return const [];
  return raw
      .whereType<Map>()
      .map((row) => MailRecipient.fromJson(Map<String, dynamic>.from(row)))
      .where((recipient) => recipient.address.contains('@'))
      .toList(growable: false);
}

/// Minúsculas y sin tildes, como buscan los demás buscadores del ERP.
String foldMailSearch(String value) => value
    .toLowerCase()
    .replaceAll('á', 'a')
    .replaceAll('é', 'e')
    .replaceAll('í', 'i')
    .replaceAll('ó', 'o')
    .replaceAll('ú', 'u')
    .replaceAll('ü', 'u')
    .replaceAll('ñ', 'n');

final _wordSplit = RegExp(r'[^a-z0-9]+');

Iterable<String> _words(String? value) => value == null
    ? const []
    : foldMailSearch(value).split(_wordSplit).where((word) => word.isNotEmpty);

/// Qué tan bien calza [recipient] con lo escrito: 3 si la dirección o el
/// nombre empiezan así, 2 si cada palabra escrita empieza una palabra del
/// nombre, de su dueño o de la dirección, 1 si lo escrito con @ o punto está
/// dentro de la dirección, 0 si no calza.
int mailRecipientMatch(MailRecipient recipient, String query) {
  final folded = foldMailSearch(query.trim());
  if (folded.isEmpty) return 0;
  if (recipient.address.startsWith(folded)) return 3;
  final name = recipient.name == null ? null : foldMailSearch(recipient.name!);
  if (name != null && name.startsWith(folded)) return 3;
  final typed =
      folded.split(_wordSplit).where((word) => word.isNotEmpty).toList();
  final words = <String>{
    ..._words(recipient.name),
    ..._words(recipient.org),
    ..._words(recipient.address),
  };
  if (typed.isNotEmpty &&
      typed.every((part) => words.any((word) => word.startsWith(part)))) {
    return 2;
  }
  if ((folded.contains('@') || folded.contains('.')) &&
      recipient.address.contains(folded)) {
    return 1;
  }
  return 0;
}

/// Las sugerencias para lo que se está escribiendo: lo más usado primero,
/// después lo que mejor calza, lo más reciente, los proveedores antes que los
/// clientes, y por nombre.
List<MailRecipient> suggestMailRecipients(
  Iterable<MailRecipient> directory,
  String query, {
  Set<String> exclude = const {},
  int limit = 6,
}) {
  if (foldMailSearch(query.trim()).isEmpty) return const [];
  final scored = <(MailRecipient, int)>[];
  for (final recipient in directory) {
    if (exclude.contains(recipient.address)) continue;
    final score = mailRecipientMatch(recipient, query);
    if (score > 0) scored.add((recipient, score));
  }
  final never = DateTime.fromMillisecondsSinceEpoch(0);
  scored.sort((a, b) {
    final uses = b.$1.uses.compareTo(a.$1.uses);
    if (uses != 0) return uses;
    final match = b.$2.compareTo(a.$2);
    if (match != 0) return match;
    final last = (b.$1.lastUsed ?? never).compareTo(a.$1.lastUsed ?? never);
    if (last != 0) return last;
    final kind = a.$1.kind.index.compareTo(b.$1.kind.index);
    if (kind != 0) return kind;
    return foldMailSearch(a.$1.title).compareTo(foldMailSearch(b.$1.title));
  });
  return scored.take(limit).map((entry) => entry.$1).toList(growable: false);
}

bool _isRecipientSeparator(String char) => char == ',' || char == ';';

/// El destinatario que se está escribiendo: el trozo entre separadores donde
/// está el cursor.
@immutable
class MailRecipientToken {
  const MailRecipientToken(this.start, this.end, this.text);

  final int start;
  final int end;
  final String text;
}

MailRecipientToken currentMailRecipientToken(String text, int cursor) {
  final at = cursor < 0 || cursor > text.length ? text.length : cursor;
  var start = at;
  while (start > 0 && !_isRecipientSeparator(text[start - 1])) {
    start--;
  }
  var end = at;
  while (end < text.length && !_isRecipientSeparator(text[end])) {
    end++;
  }
  return MailRecipientToken(start, end, text.substring(start, end));
}

/// Pone [address] en lugar del destinatario que se está escribiendo y deja el
/// cursor listo para el siguiente («a@b.cl, »).
TextEditingValue acceptMailRecipient(TextEditingValue value, String address) {
  final text = value.text;
  final cursor =
      value.selection.isValid ? value.selection.baseOffset : text.length;
  final token = currentMailRecipientToken(text, cursor);
  final before = text.substring(0, token.start);
  final rest =
      text.substring(token.end).replaceFirst(RegExp(r'^\s*[,;]?\s*'), '');
  final lead = before.isEmpty || before.endsWith(' ') ? '' : ' ';
  final inserted = '$lead$address, ';
  return TextEditingValue(
    text: '$before$inserted$rest',
    selection: TextSelection.collapsed(offset: before.length + inserted.length),
  );
}

/// Las direcciones ya escritas en un campo, sin la que se está escribiendo.
Set<String> mailRecipientAddresses(String text, {MailRecipientToken? except}) {
  final addresses = <String>{};
  var start = 0;
  for (var i = 0; i <= text.length; i++) {
    if (i == text.length || _isRecipientSeparator(text[i])) {
      if (except == null || start != except.start) {
        final address = text.substring(start, i).trim().toLowerCase();
        if (address.isNotEmpty) addresses.add(address);
      }
      start = i + 1;
    }
  }
  return addresses;
}

/// La libreta del taller. Cada Redactar la vuelve a leer y, mientras llega,
/// muestra la lectura anterior ([cached]), así que abrir no espera al
/// servidor.
///
/// Hasta el 2026-11-17 una lectura valía 10 minutos. El dueño abrió Redactar
/// y no encontró a Álvaro, el vendedor de MKR. Le puso el correo en su
/// contacto, volvió a Redactar y tampoco lo encontró: seguía la lectura
/// anterior. Un correo recién agregado a un proveedor o cliente tiene que
/// aparecer la próxima vez que se abre Redactar.
class MailRecipientDirectory {
  MailRecipientDirectory({SupabaseClient? client, DateTime Function()? clock})
      : _client = client,
        _clock = clock ?? DateTime.now;

  /// La de la app: la comparten todas las ventanas de Redactar.
  static final MailRecipientDirectory shared = MailRecipientDirectory();

  /// Lo enviado desde la app se recuerda hasta que el servidor lo traiga.
  static const Duration rememberFor = Duration(minutes: 30);

  final SupabaseClient? _client;
  final DateTime Function() _clock;

  List<MailRecipient>? _server;
  Future<List<MailRecipient>>? _pending;

  /// Lo enviado desde esta app que el servidor todavía no trae: cuántas veces
  /// y cuándo fue la última.
  final Map<String, (int, DateTime)> _sentHere = {};

  /// Lo que ya se tiene, sin ir al servidor (vacío la primera vez).
  List<MailRecipient> get cached => _merged();

  /// Lee la libreta del servidor. Dos ventanas que la piden a la vez
  /// comparten la misma lectura.
  Future<List<MailRecipient>> load() =>
      _pending ??= _fetch().whenComplete(() => _pending = null);

  @protected
  Future<Object?> fetchDirectory() =>
      (_client ?? Supabase.instance.client).rpc('mail_recipient_directory_v1');

  Future<List<MailRecipient>> _fetch() async {
    final server = parseMailRecipients(await fetchDirectory());
    final now = _clock();
    final lastUsed = {
      for (final recipient in server) recipient.address: recipient.lastUsed,
    };
    // Lo que el servidor ya trae (con un minuto de holgura por la hora del
    // proveedor) o lo muy antiguo deja de sumarse aparte.
    _sentHere.removeWhere((address, sent) {
      if (now.difference(sent.$2) > rememberFor) return true;
      final known = lastUsed[address];
      return known != null &&
          !known.isBefore(sent.$2.subtract(const Duration(minutes: 1)));
    });
    _server = server;
    return _merged();
  }

  /// Suma lo recién enviado: sube al principio la próxima vez que se escriba.
  void remember(Iterable<String> addresses) {
    final now = _clock();
    for (final raw in addresses) {
      final address = raw.trim().toLowerCase();
      if (!address.contains('@')) continue;
      final previous = _sentHere[address];
      _sentHere[address] = ((previous?.$1 ?? 0) + 1, now);
    }
  }

  List<MailRecipient> _merged() {
    final server = _server ?? const <MailRecipient>[];
    if (_sentHere.isEmpty) return server;
    final known = <String>{};
    final result = <MailRecipient>[];
    for (final recipient in server) {
      known.add(recipient.address);
      final sent = _sentHere[recipient.address];
      result.add(
          sent == null ? recipient : recipient.usedAt(sent.$2, times: sent.$1));
    }
    for (final entry in _sentHere.entries) {
      if (known.contains(entry.key)) continue;
      result.add(MailRecipient(
        address: entry.key,
        kind: MailRecipientKind.sent,
        uses: entry.value.$1,
        lastUsed: entry.value.$2,
      ));
    }
    return result;
  }
}
