/// How strongly a bank line names the same party as an ERP operation.
enum BankIdentityStrength {
  /// One side has no usable name ("Cliente Mostrador", a bank deposit).
  unknown,

  /// Both sides name people or companies and share nothing distinctive.
  conflict,

  /// Only a short or common token agrees ("Pia", "Carlos").
  weak,

  /// One distinctive token agrees out of several.
  medium,

  /// The names agree: two distinctive tokens, or a distinctive single name.
  strong,
}

class BankIdentityMatch {
  const BankIdentityMatch(this.strength, {this.matchedName});

  static const unknown = BankIdentityMatch(BankIdentityStrength.unknown);

  final BankIdentityStrength strength;
  final String? matchedName;

  bool get isStrong => strength == BankIdentityStrength.strong;
  bool get isConflict => strength == BankIdentityStrength.conflict;
}

/// Compares the names a Chilean bank statement prints with ERP names.
///
/// Banco de Chile prints the holder's legal name, reorders it ("Bravo
/// Espinoza Carolina Antonia" for "Carolina Bravo"), inserts the channel
/// ("Internet"), truncates it ("Comercializadora Bicicletas Univer") and
/// drops accents. People also misspell names in the ERP ("Natero" for
/// "Nattero"). The comparison is therefore token based, order free,
/// prefix tolerant for truncation and edit-distance tolerant for spelling.
class BankCounterpartyIdentity {
  const BankCounterpartyIdentity._();

  /// Words the bank adds to every line; they identify nobody.
  static const Set<String> _channelNoise = <String>{
    'internet',
    'app',
    'traspaso',
    'traspasos',
    'transferencia',
    'transf',
    'pago',
    'pagos',
    'abono',
    'abonos',
    'cargo',
    'de',
    'a',
    'al',
    'del',
    'la',
    'las',
    'los',
    'el',
    'y',
    'e',
    'en',
    'por',
    'para',
    'con',
    'renca',
    'santiago',
    'oficina',
    'central',
    'chile',
    'cl',
    'com',
    'www',
    'nro',
    'n',
  };

  /// Legal forms and company words shared by unrelated businesses.
  static const Set<String> _genericWords = <String>{
    'spa',
    'sa',
    's',
    'ltda',
    'limitada',
    'eirl',
    'cia',
    'compania',
    'sociedad',
    'comercial',
    'comercializadora',
    'importadora',
    'importaciones',
    'inversiones',
    'servicios',
    'distribuidora',
    'empresa',
    'empresas',
    'industrial',
    'industriales',
    'group',
    'grupo',
    'store',
    'tienda',
    'bicicletas',
    'bicicleteria',
    'bike',
    'bikes',
    'cycles',
    'dos',
    'uno',
  };

  /// ERP placeholders that stand for "no identified party".
  static const Set<String> _placeholderNames = <String>{
    'cliente',
    'clientes',
    'mostrador',
    'cliente mostrador',
    'sin registro',
    'proveedor',
    'proveedores',
    'consumidor final',
    'varios',
    'sin nombre',
  };

  static String normalize(String value) {
    const replacements = <String, String>{
      'á': 'a',
      'à': 'a',
      'ä': 'a',
      'â': 'a',
      'é': 'e',
      'è': 'e',
      'ë': 'e',
      'ê': 'e',
      'í': 'i',
      'ì': 'i',
      'ï': 'i',
      'î': 'i',
      'ó': 'o',
      'ò': 'o',
      'ö': 'o',
      'ô': 'o',
      'ú': 'u',
      'ù': 'u',
      'ü': 'u',
      'û': 'u',
      'ñ': 'n',
      'ç': 'c',
    };
    var result = value.toLowerCase();
    for (final entry in replacements.entries) {
      result = result.replaceAll(entry.key, entry.value);
    }
    // The bank prints "Compa#ia" and "Andr;s" for characters it cannot encode.
    return result
        .replaceAll(RegExp(r'[#;]'), 'n')
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static List<String> tokens(String value) => normalize(value)
      .split(' ')
      .where((token) => token.isNotEmpty && !_channelNoise.contains(token))
      .toList(growable: false);

  static bool isPlaceholder(String name) {
    final normalized = normalize(name);
    if (normalized.isEmpty) return true;
    if (_placeholderNames.contains(normalized)) return true;
    final meaningful = tokens(name)
        .where((token) => !_genericWords.contains(token))
        .where((token) => !_placeholderNames.contains(token));
    return meaningful.isEmpty;
  }

  /// Best agreement between the bank text and any of the ERP names.
  static BankIdentityMatch compare(String bankText, Iterable<String> names) {
    final bankTokens = tokens(bankText);
    if (bankTokens.isEmpty) return BankIdentityMatch.unknown;
    var best = BankIdentityMatch.unknown;
    var sawComparableName = false;
    for (final name in names) {
      if (isPlaceholder(name)) continue;
      final match = _compareOne(bankTokens, name);
      if (match.strength != BankIdentityStrength.unknown) {
        sawComparableName = true;
      }
      if (match.strength.index > best.strength.index) best = match;
    }
    if (!sawComparableName) return BankIdentityMatch.unknown;
    return best;
  }

  static BankIdentityMatch _compareOne(List<String> bankTokens, String name) {
    final nameTokens = tokens(name)
        .where((token) => !_placeholderNames.contains(token))
        .toList(growable: false);
    if (nameTokens.isEmpty) return BankIdentityMatch.unknown;
    final distinctive = nameTokens
        .where((token) => !_genericWords.contains(token) && token.length >= 3)
        .toList(growable: false);
    if (distinctive.isEmpty) return BankIdentityMatch.unknown;

    final used = <int>{};
    var strongHits = 0;
    var longestHit = 0;
    for (final token in distinctive) {
      var bestScore = 0.0;
      var bestIndex = -1;
      for (var index = 0; index < bankTokens.length; index++) {
        if (used.contains(index)) continue;
        final score = tokenSimilarity(
          bankTokens[index],
          token,
          bankTokenMayBeCut: index == bankTokens.length - 1,
        );
        if (score > bestScore) {
          bestScore = score;
          bestIndex = index;
        }
      }
      if (bestScore >= 0.85 && bestIndex >= 0) {
        used.add(bestIndex);
        strongHits++;
        if (token.length > longestHit) longestHit = token.length;
      }
    }

    final bankDistinctive = bankTokens
        .where((token) => !_genericWords.contains(token) && token.length >= 3)
        .length;
    if (strongHits >= 2) {
      return BankIdentityMatch(BankIdentityStrength.strong, matchedName: name);
    }
    if (strongHits == 1) {
      // A single distinctive business or family name ("Teknobike", "Vittal",
      // "Andes Industrial") identifies the party; a lone first name does not.
      if (distinctive.length == 1 && longestHit >= 5) {
        return BankIdentityMatch(BankIdentityStrength.strong,
            matchedName: name);
      }
      if (longestHit >= 5) {
        return BankIdentityMatch(BankIdentityStrength.medium,
            matchedName: name);
      }
      return BankIdentityMatch(BankIdentityStrength.weak, matchedName: name);
    }
    if (distinctive.length >= 2 && bankDistinctive >= 2) {
      return BankIdentityMatch(BankIdentityStrength.conflict,
          matchedName: name);
    }
    return BankIdentityMatch.unknown;
  }

  /// 1 for equal tokens; high for truncation, nicknames or one-letter
  /// misspellings.
  ///
  /// The bank cuts the whole line at a fixed width, so only its last token
  /// can be a cut word ("Univer" for "Universal"). Anywhere else a prefix is
  /// another word ("Ciclo" is not "CicloBar"). An ERP name of four letters
  /// that starts a bank token is a nickname ("Cata" for "Catalina").
  static double tokenSimilarity(
    String bank,
    String erp, {
    bool bankTokenMayBeCut = false,
  }) {
    if (bank == erp) return 1;
    if (bankTokenMayBeCut && bank.length >= 4 && erp.startsWith(bank)) {
      return 0.9;
    }
    if (erp.length == 4 && bank.length > 4 && bank.startsWith(erp)) {
      return 0.85;
    }
    final shorter = bank.length <= erp.length ? bank : erp;
    if (shorter.length >= 5) {
      final distance = _editDistance(bank, erp, limit: 2);
      if (distance == 1) return 0.85;
      if (distance == 2 && shorter.length >= 8) return 0.7;
    }
    return 0;
  }

  static int _editDistance(String left, String right, {required int limit}) {
    if ((left.length - right.length).abs() > limit) return limit + 1;
    var previous = List<int>.generate(right.length + 1, (index) => index);
    for (var i = 1; i <= left.length; i++) {
      final current = List<int>.filled(right.length + 1, 0)..[0] = i;
      var rowMinimum = current[0];
      for (var j = 1; j <= right.length; j++) {
        final cost = left.codeUnitAt(i - 1) == right.codeUnitAt(j - 1) ? 0 : 1;
        current[j] = [
          previous[j] + 1,
          current[j - 1] + 1,
          previous[j - 1] + cost,
        ].reduce((a, b) => a < b ? a : b);
        if (current[j] < rowMinimum) rowMinimum = current[j];
      }
      if (rowMinimum > limit) return limit + 1;
      previous = current;
    }
    return previous[right.length];
  }
}
