import 'bike_part_taxonomy.dart';
import 'product_identity_profile.dart';

/// Raw text about one product, from either side of a comparison.
/// Words that appear in a `brand` column but do not name a manufacturer.
///
/// A catalog row typed `Aliexpress` says where the shop bought it; a row typed
/// `Genérico` or `Sin marca` says nobody wrote one down. Reading either as an
/// assertion made the manufacturer gate fail against every real maker — and it
/// is exactly how `Postiza AE 001`, the product the invoice was actually for,
/// was ruled out as «Otro fabricante: Ztto ≠ Aliexpress».
///
/// These are not brands to be matched. They are the absence of one.
const Set<String> nonManufacturerBrandWords = <String>{
  'aliexpress',
  'ali express',
  'alibaba',
  'ebay',
  'amazon',
  'temu',
  'shein',
  'generico',
  'generica',
  'genericos',
  'generic',
  'sin marca',
  'sinmarca',
  'no brand',
  'nobrand',
  'oem',
  'china',
  'importado',
  'varios',
  'otro',
  'otros',
  'na',
};

class ProductIdentityInput {
  const ProductIdentityInput({
    required this.name,
    this.description,
    this.rawText,
    this.brandHint,
    this.brandIsAsserted = false,
    this.modelHint,
    this.categoryPath,
    this.knownBrands = const <String>[],
  });

  final String name;
  final String? description;
  final String? rawText;

  /// A brand the caller believes applies. It is a *hint*: it is promoted to an
  /// assertion only when the identity text confirms it. An AI reading
  /// `Compatible con SHIMANO/SRAM` used to return `Shimano` here.
  final String? brandHint;

  /// Whether [brandHint] is the shop's own statement rather than a guess.
  ///
  /// A catalog row's `brand` column was chosen by a person and is an
  /// assertion. An OCR or AI reading of a supplier title is not: it produced
  /// `Shimano` for `IXF … Compatible con SHIMANO/SRAM`. Treating both the same
  /// way meant a Shimano crankset never conflicted with an IXF one, because
  /// neither side's brand was ever asserted.
  final bool brandIsAsserted;

  final String? modelHint;

  /// `Componentes / Ruedas / Mazas / Maza` or a single leaf name.
  final String? categoryPath;

  /// Brand names that really exist for this tenant, plus manufacturers the
  /// shop buys from that are not yet rows in `product_brands`.
  final Iterable<String> knownBrands;
}

/// Turns supplier prose and catalog rows into typed, comparable evidence.
///
/// Every rule here replaces a measured failure of the previous bag-of-words
/// approach; the failing case is named at the rule.
class ProductIdentityExtractor {
  const ProductIdentityExtractor._();

  /// Manufacturers the shop buys that may be absent from `product_brands`.
  /// A missing brand row must never stop the matcher from finding the right
  /// product: `IXF` had no row while `AE0093 Volante IXF` sat in the catalog.
  static const Set<String> externalManufacturers = <String>{
    'ixf',
    'ztto',
    'bucklos',
    'risk',
    'novatec',
    'wake',
    'shimano',
    'sram',
    'riderace',
    'rideace',
    'deemount',
    'muqzi',
    'meroca',
    'toopre',
    'mana',
    'arc',
    'betta',
    'tanke',
    'west biking',
    'giyo',
    'kenda',
    'maxxis',
    'chaoyang',
    'arisun',
    'ralco',
    'duro',
    'cst',
    'vp',
    'neco',
    'lebycle',
    'ozono',
    'prowheel',
    'microshift',
    'sunrace',
    'kmc',
    'tektro',
    'zoom',
    'wellgo',
    'stronglight',
  };

  /// Words that introduce what a product *fits*, not what it *is*.
  static final RegExp _fitmentMarker = RegExp(
    r'\b(?:compatible(?:s)?(?:\s+(?:con|with|para))?|compatibilidad(?:\s+con)?'
    r'|apto(?:s)?\s+para|sirve\s+para|works?\s+with|fits?(?:\s+for)?'
    r'|para(?:\s+uso)?|for)\b',
  );

  /// Words that introduce something *included with* the product. What comes
  /// after is a bundled accessory, never the product's own family:
  /// `Volante IXF Integrado Black 170Mm + Motor BSA + Corona 34T` is a
  /// crankset, and reading `Motor` as its family deleted the only correct
  /// candidate in the catalog.
  static final RegExp _inclusionMarker = RegExp(
    r'\b(?:incluye|incluido(?:s)?|con\s+su|mas|plus)\b|\+',
  );

  static const Set<String> _stopWords = <String>{
    'de',
    'del',
    'la',
    'el',
    'los',
    'las',
    'un',
    'una',
    'unos',
    'unas',
    'y',
    'o',
    'a',
    'en',
    'al',
    'por',
    'con',
    'sin',
    'su',
    'sus',
    'lo',
    'and',
    'the',
    'for',
    'with',
    'of',
    'to',
    'in',
    'on',
    'bicicleta',
    'bicicletas',
    'bike',
    'bikes',
    'bicycle',
    'cycling',
    'mtb',
    'ruta',
    'carretera',
    'montana',
    'road',
    'bmx',
    'dh',
    'aliexpress',
    'marketplace',
    'china',
    'chile',
    'clp',
    'unidad',
    'unidades',
    'pcs',
    'pza',
    'pzas',
    'set',
    'kit',
    'nuevo',
    'nueva',
    'original',
    'calidad',
    'alta',
    'ligero',
    'ligera',
    'universal',
    'accesorio',
    'accesorios',
    'pieza',
    'piezas',
    'repuesto',
    'repuestos',
    'item',
    'id',
    'sku',
    'ae',
    'color',
    'size',
    'talla',
  };

  /// Colour words, mapped to one canonical value so `rojo`/`red` compare.
  static const Map<String, String> _colors = <String, String>{
    'negro': 'negro',
    'negra': 'negro',
    'black': 'negro',
    'blanco': 'blanco',
    'blanca': 'blanco',
    'white': 'blanco',
    'rojo': 'rojo',
    'roja': 'rojo',
    'red': 'rojo',
    'azul': 'azul',
    'blue': 'azul',
    'verde': 'verde',
    'green': 'verde',
    'morado': 'morado',
    'morada': 'morado',
    'purple': 'morado',
    'purpura': 'morado',
    'violeta': 'morado',
    'dorado': 'dorado',
    'dorada': 'dorado',
    'gold': 'dorado',
    'golden': 'dorado',
    'oro': 'dorado',
    'plateado': 'plateado',
    'plata': 'plateado',
    'silver': 'plateado',
    'gris': 'gris',
    'grey': 'gris',
    'gray': 'gris',
    'naranjo': 'naranjo',
    'naranja': 'naranjo',
    'orange': 'naranjo',
    'amarillo': 'amarillo',
    'yellow': 'amarillo',
    'rosado': 'rosado',
    'rosa': 'rosado',
    'pink': 'rosado',
    'celeste': 'celeste',
    'titanio': 'titanio',
    'titanium': 'titanio',
  };

  /// Families whose dimensions in `NNxNN` form describe an axle.
  static const Set<String> _axleFamilies = <String>{'hub', 'wheelset'};

  /// Families for which the valve standard is a decisive property. An adapter
  /// legitimately names both standards, so gating it there would make every
  /// adapter conflict with itself.
  static const Set<String> _valveScopedFamilies = <String>{
    'tube',
    'tire',
    'tubeless_valve',
    'valve_core',
    'rim',
  };

  // Every pattern is compiled once. Building them inside the extraction call
  // recompiled roughly two hundred regular expressions per product per invoice
  // line, which is most of the 550–700 ms a single line used to cost against
  // the real 1555-product catalog.
  static final RegExp _accentA = RegExp('[áàäâãå]');
  static final RegExp _accentE = RegExp('[éèëê]');
  static final RegExp _accentI = RegExp('[íìïî]');
  static final RegExp _accentO = RegExp('[óòöôõ]');
  static final RegExp _accentU = RegExp('[úùüû]');
  static final RegExp _decimalComma = RegExp(r'(\d),(\d)');
  static final RegExp _nonTextual = RegExp(r'[^a-z0-9.+~]+');
  static final RegExp _strayPoint = RegExp(r'(?<![0-9])\.|\.(?![0-9])');
  static final RegExp _clauseRun = RegExp(r'(?:\s*~\s*)+');
  static final RegExp _whitespace = RegExp(r'\s+');
  static final RegExp _splitUnit =
      RegExp(r'(\d(?:\.\d+)?)\s+(mm|cm|t|h|pcs|psi)\b');
  static final RegExp _clauseSplit = RegExp(r'\s*~\s*');
  static final RegExp _clauseBoundary = RegExp(r'[,;:()\[\]\n]+');
  static final RegExp _spokeExplicit = RegExp(r'\b(\d{2})h\b');
  static final RegExp _spokeCounted =
      RegExp(r'\b(\d{2})\s*(?:agujeros?|hoyos?|holes?)\b');
  static final RegExp _spokeOptionList =
      RegExp(r'\b\d{2}(?:\s+\d{2}){1,}\s*(?:agujeros?|hoyos?|holes?)\b');
  static final RegExp _teeth = RegExp(r'\b(\d{2,3})t\b');
  static final RegExp _boltCircle =
      RegExp(r'\b(?:bcd\s*(\d{2,3})|(\d{2,3})\s*bcd)\b');
  static final RegExp _speeds =
      RegExp(r'\b(\d{1,2})\s*(?:v|vel|velocidades|speed|speeds)\b');
  static final RegExp _rotorDiameter =
      RegExp(r'\b(140|160|180|200|203|220)mm\b');
  static final RegExp _sixBolt =
      RegExp(r'\b(?:6\s*pernos|6\s*bolt|six\s*bolt)\b');
  static final RegExp _centerLock = RegExp(r'\bcenter\s*lock\b|\bcenterlock\b');
  static final RegExp _clampDiameter = RegExp(r'\b(25\.4|31\.8|35)mm\b');
  static final RegExp _postDiameter =
      RegExp(r'\b(25\.4|27\.2|28\.6|30\.9|31\.6|34\.9)mm\b');
  static final RegExp _crankLength =
      RegExp(r'\b(150|155|160|165|170|172\.5|175|180)mm\b');
  static final RegExp _shellBsa = RegExp(r'\bbsa\b');
  static final RegExp _shellBb30 = RegExp(r'\bbb30\b');
  static final RegExp _shellPressfit = RegExp(r'\b(?:pressfit|pf30)\b');
  static final RegExp _wheelSize = RegExp(
    r'\b(?:aro\s*)?(12|14|16|20|24|26|27\.5|28|29|650|700)\b'
    r'(?=\s*(?:x|c\b|pulgadas)|\s*$)',
  );
  static final RegExp _axleDimensions =
      RegExp(r'\b(\d{2,3})\s*x\s*(\d{1,2})(?:mm)?\b');
  static final RegExp _boost = RegExp(r'\bboost\b');
  static final RegExp _microSpline =
      RegExp(r'\bmicro\s*spline\b|\bmicrospline\b');
  static final RegExp _driverXdr = RegExp(r'\bxdr\b');
  static final RegExp _driverXd = RegExp(r'\bxd\b');
  static final RegExp _freewheel =
      RegExp(r'\b(?:freewheel|rueda\s+libre|roscad[ao])\b');
  static final RegExp _driverHg = RegExp(r'\bhg\b');
  static final RegExp _presta = RegExp(r'\b(?:presta|francesa|f\s*v|fv)\b');
  static final RegExp _schrader =
      RegExp(r'\b(?:schrader|americana|auto|a\s*v|av)\b');
  static final RegExp _front =
      RegExp(r'\b(?:delantera?o?|delanteras?|front)\b');
  static final RegExp _rear =
      RegExp(r'\b(?:trasera?o?|traseras?|rear|posterior)\b');
  static final RegExp _packCount =
      RegExp(r'\b(\d{1,3})\s*(?:pcs|un|uds|unidades|pares)\b');
  static final RegExp _valveLength = RegExp(r'\b(\d{2,3})mm\b');
  static final RegExp _hasLetter = RegExp('[a-z]');
  static final RegExp _hasDigit = RegExp('[0-9]');
  static final RegExp _nonAlphanumeric = RegExp(r'[^a-z0-9]');
  static final RegExp _bareMeasurement =
      RegExp(r'^\d+(?:mm|cm|t|h|v|w|c|pcs|psi|mah|wh)$');
  static final RegExp _bcdToken = RegExp(r'^(?:\d{2,3}bcd|bcd\d{2,3})$');
  static final RegExp _onlyLetters = RegExp(r'^[a-z]+$');
  static final RegExp _onlyDigits = RegExp(r'^\d+$');
  static final RegExp _collapse = RegExp(r'\s+');

  /// One compiled matcher per colour word, built once.
  /// A colour written in the plural is the same colour.
  ///
  /// The shop names a product `Puños ODI-1 **Negros** 135mm` and the supplier
  /// variant says `(UPGRADE-Black)`. Matching only the singular meant neither
  /// side stated a colour, nothing conflicted, and the purple pair ranked
  /// exactly as well as the black one the invoice was for. Spanish colours
  /// pluralise with `s` or `es`; allowing that suffix is cheaper and more
  /// general than listing every form.
  static final List<MapEntry<RegExp, String>> _colorPatterns = _colors.entries
      .map((entry) => MapEntry(
            RegExp('\\b${entry.key}(?:es|s)?\\b'),
            entry.value,
          ))
      .toList(growable: false);

  /// Canonical normalization. Every identity comparison in the ERP — profile
  /// text, brand aliases, category names — must go through this one function,
  /// otherwise two spellings of the same word stop comparing.
  static String normalize(String value) => _normalize(value);

  static ProductIdentityProfile extract(ProductIdentityInput input) {
    final normalizedName = _normalize(input.name);
    final normalizedDescription = _normalize(input.description ?? '');
    final normalizedRaw = _normalize(input.rawText ?? '');
    final fullText = <String>[
      normalizedName,
      normalizedDescription,
      normalizedRaw,
    ].where((value) => value.isNotEmpty).join(' ~ ');

    final segments = _segment('$normalizedName ~ $normalizedDescription');
    final identityText = segments.identity;
    final fitmentText = <String>[segments.fitment, normalizedRaw]
        .where((value) => value.trim().isNotEmpty)
        .join(' ');

    var heads = _detectHeads(identityText);
    if (heads.winner == null && fitmentText.isNotEmpty) {
      // Segmentation must never leave the identity without a head noun.
      //
      // `para` usually introduces fitment (`Tee para bicicleta`), but it also
      // introduces the object itself (`Repuesto para caliper de freno`). When
      // the cut removes the only head noun in the title, the cut was wrong:
      // fall back to the whole clause rather than declare the object unknown.
      // Brands and model codes keep their own segments, so a compatibility
      // claim still cannot become identity.
      heads = _detectHeads('$identityText $fitmentText');
    }
    final familyId = heads.winner;

    final consumed = _Consumption(fullText);
    final specs = _extractSpecs(
      fullText,
      familyId,
      consumed,
      nameLength: normalizedName.length,
    );

    final brands = _detectBrands(
      identityText: identityText,
      fitmentText: fitmentText,
      knownBrands: input.knownBrands,
      brandHint: input.brandHint,
      brandIsAsserted: input.brandIsAsserted,
      consumed: consumed,
    );

    final models = _extractModelCodes(
      consumed: consumed,
      modelHint: input.modelHint,
      specs: specs,
      identityText: identityText,
      nameText: normalizedName,
    );

    return ProductIdentityProfile(
      identityText: identityText,
      fitmentText: fitmentText,
      familyId: familyId,
      familyCandidates: heads.candidates,
      assertedBrand: brands.asserted,
      compatibilityBrands: brands.compatibility,
      modelCodes: models.identity,
      primaryModelCodes: models.primary,
      compatibilityModelCodes: models.compatibility,
      specs: specs,
      descriptorTokens: _descriptorTokens(consumed.remainingText),
      categoryPath: _categoryPath(input.categoryPath),
    );
  }

  // ── Normalization ─────────────────────────────────────────────────────

  /// Lowercase, accent-free, punctuation-free text where decimal numbers keep
  /// their point (`31,8mm` and `31.8 mm` both become `31.8mm`).
  static String _normalize(String value) {
    if (value.trim().isEmpty) return '';
    var text = value.toLowerCase();
    text = text
        .replaceAll(_accentA, 'a')
        .replaceAll(_accentE, 'e')
        .replaceAll(_accentI, 'i')
        .replaceAll(_accentO, 'o')
        .replaceAll(_accentU, 'u')
        .replaceAll('ñ', 'n')
        .replaceAll('ç', 'c');
    // Decimal comma before the character filter erases it.
    text = text.replaceAllMapped(
      _decimalComma,
      (match) => '${match.group(1)}.${match.group(2)}',
    );
    // `+` marks a bundled extra and must survive as its own token.
    text = text.replaceAll('+', ' + ');
    // Clause boundaries have to survive the character filter. A supplier title
    // is one long comma-separated sentence: erasing its commas first made
    // `Adaptador Presta a Schrader para bicicleta, adaptador de válvula …` a
    // single clause, so the `para` cut also removed the head noun that names
    // the product, and the row found nothing.
    text = text.replaceAll(_clauseBoundary, ' ~ ');
    text = text.replaceAll(_nonTextual, ' ');
    // A point that is not a decimal separator ends a sentence, which is also
    // a clause boundary.
    text = text.replaceAll(_strayPoint, ' ~ ');
    text = text.replaceAll(_clauseRun, ' ~ ');
    text = text.replaceAll(_whitespace, ' ').trim();
    // `31.8 mm` and `160 mm` are one measurement, not two tokens.
    text = text.replaceAllMapped(
      _splitUnit,
      (match) => '${match.group(1)}${match.group(2)}',
    );
    return _expandCompounds(text);
  }

  /// Splits supplier spellings that join a two-word head noun.
  ///
  /// `Cortacadena RIDERACE` and `Corta cadena RiderAce Negro` are the same
  /// tool; without this the invoice line shared exactly one token with its own
  /// catalog product and the matcher returned nothing.
  static String _expandCompounds(String text) {
    if (text.isEmpty) return text;
    final tokens = text.split(' ');
    var changed = false;
    for (var index = 0; index < tokens.length; index++) {
      final expansion = BikePartTaxonomy.compoundExpansions[tokens[index]];
      if (expansion != null) {
        tokens[index] = expansion;
        changed = true;
      }
    }
    return changed ? tokens.join(' ') : text;
  }

  // ── Identity vs fitment ───────────────────────────────────────────────

  static _Segments _segment(String text) {
    final identity = StringBuffer();
    final fitment = StringBuffer();
    for (final clause in text.split(_clauseSplit)) {
      final trimmed = clause.trim();
      if (trimmed.isEmpty) continue;
      var head = trimmed;
      var tail = '';
      final fitmentMatch = _fitmentMarker.firstMatch(trimmed);
      final inclusionMatch = _inclusionMarker.firstMatch(trimmed);
      final cut = <int>[
        if (fitmentMatch != null) fitmentMatch.start,
        if (inclusionMatch != null) inclusionMatch.start,
      ];
      if (cut.isNotEmpty) {
        final at = cut.reduce((a, b) => a < b ? a : b);
        head = trimmed.substring(0, at).trim();
        tail = trimmed.substring(at).trim();
      }
      if (head.isNotEmpty) identity.write('$head ');
      if (tail.isNotEmpty) fitment.write('$tail ');
    }
    return _Segments(
      identity: identity.toString().trim(),
      fitment: fitment.toString().trim(),
    );
  }

  // ── Family ────────────────────────────────────────────────────────────

  static _HeadDetection _detectHeads(String identityText) {
    if (identityText.isEmpty) {
      return const _HeadDetection(winner: null, candidates: <String>{});
    }
    final haystack = ' $identityText ';
    final taken = List<bool>.filled(haystack.length, false);
    final positions = <String, int>{};
    final lengths = <String, int>{};

    for (final head in BikePartTaxonomy.orderedHeads) {
      final needle = ' ${head.phrase} ';
      var from = 0;
      while (true) {
        final at = haystack.indexOf(needle, from);
        if (at < 0) break;
        // The trailing space is shared with the next word, so only the phrase
        // body is consumed.
        final bodyStart = at + 1;
        final bodyEnd = bodyStart + head.phrase.length;
        var free = true;
        for (var i = bodyStart; i < bodyEnd; i++) {
          if (taken[i]) {
            free = false;
            break;
          }
        }
        if (free) {
          for (var i = bodyStart; i < bodyEnd; i++) {
            taken[i] = true;
          }
          final existing = positions[head.familyId];
          if (existing == null || bodyStart < existing) {
            positions[head.familyId] = bodyStart;
            lengths[head.familyId] = head.phrase.length;
          }
        }
        from = at + 1;
      }
    }

    // A negative phrase means the head describes a different object.
    for (final familyId in positions.keys.toList()) {
      final family = BikePartTaxonomy.byId(familyId);
      if (family == null) continue;
      for (final negative in family.negativeHeads) {
        if (haystack.contains(' $negative ')) {
          positions.remove(familyId);
          lengths.remove(familyId);
          break;
        }
      }
    }

    // A part that absorbs another is still itself when both are named.
    for (final familyId in positions.keys.toList()) {
      final family = BikePartTaxonomy.byId(familyId);
      if (family == null) continue;
      for (final absorbed in family.absorbs) {
        final absorbedAt = positions[absorbed];
        final selfAt = positions[familyId];
        if (absorbedAt != null && selfAt != null && selfAt < absorbedAt) {
          positions.remove(absorbed);
          lengths.remove(absorbed);
        }
      }
    }

    if (positions.isEmpty) {
      return const _HeadDetection(winner: null, candidates: <String>{});
    }

    final ranked = positions.keys.toList()
      ..sort((left, right) {
        final byPosition = positions[left]!.compareTo(positions[right]!);
        if (byPosition != 0) return byPosition;
        final byLength = lengths[right]!.compareTo(lengths[left]!);
        if (byLength != 0) return byLength;
        return left.compareTo(right);
      });

    return _HeadDetection(
      winner: ranked.first,
      candidates: Set<String>.unmodifiable(ranked),
    );
  }

  // ── Specifications ────────────────────────────────────────────────────

  static Map<PartSpecKind, String> _extractSpecs(
    String text,
    String? familyId,
    _Consumption consumed, {
    int nameLength = 0,
  }) {
    final specs = <PartSpecKind, String>{};
    final fromName = <PartSpecKind>{};
    // Once a menu has proved the row does not state one value, a later option
    // must not become the answer. `9v 10v 11v` cancelled on the second match
    // and then quietly adopted the third.
    final cancelled = <PartSpecKind>{};
    final family = BikePartTaxonomy.byId(familyId);
    final physicalClass = family?.physicalClass ?? PartPhysicalClass.unknown;

    void put(PartSpecKind kind, String value, RegExpMatch match) {
      if (!specs.containsKey(kind) && match.start < nameLength) {
        fromName.add(kind);
      }
      specs.putIfAbsent(kind, () => value);
      consumed.take(match.start, match.end);
    }

    /// A single-valued match. When the same kind appears with two different
    /// values the listing is offering options (`28/32/36 agujeros`) and the
    /// property is unknown for this row rather than equal to the first option.
    ///
    /// With one exception, and it is the difference between a decision and a
    /// menu: the product's **own name** — which carries the chosen variant —
    /// outranks the listing body. `Eslabón rápido RISK 9v` states nine speeds;
    /// the body of that same AliExpress listing offers 6/7/8/9/10/11/12,
    /// because one listing sells them all. Letting the menu cancel the name
    /// left every speed equally possible, and a 12-speed master link was
    /// offered as the match for a 9-speed purchase.
    void putUnique(PartSpecKind kind, String value, RegExpMatch match) {
      final matchedInName = match.start < nameLength;
      if (cancelled.contains(kind) && !matchedInName) {
        consumed.take(match.start, match.end);
        return;
      }
      final existing = specs[kind];
      if (existing != null && existing != value) {
        if (fromName.contains(kind) && !matchedInName) {
          consumed.take(match.start, match.end);
          return;
        }
        specs.remove(kind);
        fromName.remove(kind);
        cancelled.add(kind);
        consumed.take(match.start, match.end);
        return;
      }
      if (existing == null && matchedInName) fromName.add(kind);
      specs[kind] = value;
      consumed.take(match.start, match.end);
    }

    // Spoke holes. `32H` is the explicit form and wins over a bare count.
    for (final match in _spokeExplicit.allMatches(text)) {
      put(PartSpecKind.spokeCount, match.group(1)!, match);
    }
    // `28/32/36 agujeros` offers three drillings; the row does not state one.
    // Reading the last number as the answer is how a 36-hole hub became an
    // exact match for a 32-hole purchase.
    if (!specs.containsKey(PartSpecKind.spokeCount) &&
        !_spokeOptionList.hasMatch(text)) {
      for (final match in _spokeCounted.allMatches(text)) {
        putUnique(PartSpecKind.spokeCount, match.group(1)!, match);
      }
    }

    // Teeth and bolt-circle diameter: interface standards, never models.
    for (final match in _teeth.allMatches(text)) {
      put(PartSpecKind.teeth, match.group(1)!, match);
    }
    for (final match in _boltCircle.allMatches(text)) {
      put(
        PartSpecKind.boltCircleMm,
        match.group(1) ?? match.group(2)!,
        match,
      );
    }

    // Speeds.
    for (final match in _speeds.allMatches(text)) {
      putUnique(PartSpecKind.speeds, match.group(1)!, match);
    }

    if (physicalClass == PartPhysicalClass.braking || familyId == 'brake_pad') {
      for (final match in _rotorDiameter.allMatches(text)) {
        putUnique(PartSpecKind.rotorDiameterMm, match.group(1)!, match);
      }
      final sixBolt = _sixBolt.firstMatch(text);
      final centerLock = _centerLock.firstMatch(text);
      if (sixBolt != null) {
        specs[PartSpecKind.brakeMount] = 'sixbolt';
        consumed.take(sixBolt.start, sixBolt.end);
      } else if (centerLock != null) {
        specs[PartSpecKind.brakeMount] = 'centerlock';
        consumed.take(centerLock.start, centerLock.end);
      }
    }

    if (familyId == 'stem' || familyId == 'handlebar') {
      for (final match in _clampDiameter.allMatches(text)) {
        putUnique(PartSpecKind.clampDiameterMm, match.group(1)!, match);
      }
    }

    if (familyId == 'seatpost' || familyId == 'seat_clamp') {
      for (final match in _postDiameter.allMatches(text)) {
        putUnique(PartSpecKind.postDiameterMm, match.group(1)!, match);
      }
    }

    if (familyId == 'crankset') {
      for (final match in _crankLength.allMatches(text)) {
        putUnique(PartSpecKind.crankLengthMm, match.group(1)!, match);
      }
      if (_shellBsa.hasMatch(text)) {
        specs[PartSpecKind.shellStandard] = 'bsa';
      } else if (_shellBb30.hasMatch(text)) {
        specs[PartSpecKind.shellStandard] = 'bb30';
      } else if (_shellPressfit.hasMatch(text)) {
        specs[PartSpecKind.shellStandard] = 'pressfit';
      }
    }

    if (physicalClass == PartPhysicalClass.tyre ||
        physicalClass == PartPhysicalClass.wheel) {
      for (final match in _wheelSize.allMatches(text)) {
        putUnique(PartSpecKind.wheelSize, match.group(1)!, match);
      }
    }

    if (_axleFamilies.contains(familyId)) {
      for (final match in _axleDimensions.allMatches(text)) {
        final width = match.group(1)!;
        final diameter = match.group(2)!;
        putUnique(PartSpecKind.axleWidthMm, width, match);
        specs.putIfAbsent(PartSpecKind.axleDiameterMm, () => diameter);
      }
      if (_boost.hasMatch(text)) {
        specs[PartSpecKind.axleWidthMm] = '148';
      }
      if (_microSpline.hasMatch(text)) {
        specs[PartSpecKind.freehubStandard] = 'microspline';
      } else if (_driverXdr.hasMatch(text)) {
        specs[PartSpecKind.freehubStandard] = 'xdr';
      } else if (_driverXd.hasMatch(text)) {
        specs[PartSpecKind.freehubStandard] = 'xd';
      } else if (_freewheel.hasMatch(text)) {
        specs[PartSpecKind.freehubStandard] = 'freewheel';
      } else if (_driverHg.hasMatch(text)) {
        specs[PartSpecKind.freehubStandard] = 'hg';
      }
    }

    if (_valveScopedFamilies.contains(familyId) ||
        familyId == 'valve_adapter') {
      final presta = _presta.hasMatch(text);
      final schrader = _schrader.hasMatch(text);
      if (familyId == 'valve_adapter') {
        // An adapter is defined by the pair it converts. `Presta a Schrader`,
        // `F/V a A/V` and `Válvula Francesa/Auto` are the same object written
        // three ways; a scooter valve adapter is not.
        if (presta && schrader) {
          specs[PartSpecKind.valveType] = 'presta_schrader';
        } else if (presta) {
          specs[PartSpecKind.valveType] = 'presta';
        } else if (schrader) {
          specs[PartSpecKind.valveType] = 'schrader';
        }
      } else if (presta && !schrader) {
        specs[PartSpecKind.valveType] = 'presta';
      } else if (schrader && !presta) {
        specs[PartSpecKind.valveType] = 'schrader';
      }
    }

    // Front / rear. A hub, wheel, rotor, derailleur or fender that states its
    // end is not interchangeable with the other one.
    final hasFront = _front.hasMatch(text);
    final hasRear = _rear.hasMatch(text);
    if (hasFront != hasRear) {
      specs[PartSpecKind.position] = hasFront ? 'front' : 'rear';
    }

    // Package size, kept out of the model-code pool.
    for (final match in _packCount.allMatches(text)) {
      put(PartSpecKind.packCount, match.group(1)!, match);
    }

    // Free length: only after every scoped dimension had its chance.
    if (familyId == 'tubeless_valve' || familyId == 'valve_core') {
      for (final match in _valveLength.allMatches(text)) {
        putUnique(PartSpecKind.lengthMm, match.group(1)!, match);
      }
    }

    for (final entry in _colorPatterns) {
      if (entry.key.hasMatch(text)) {
        specs.putIfAbsent(PartSpecKind.colorVariant, () => entry.value);
        break;
      }
    }

    return Map<PartSpecKind, String>.unmodifiable(specs);
  }

  // ── Brands ────────────────────────────────────────────────────────────

  static _BrandDetection _detectBrands({
    required String identityText,
    required String fitmentText,
    required Iterable<String> knownBrands,
    required String? brandHint,
    required bool brandIsAsserted,
    required _Consumption consumed,
  }) {
    final aliases = <String>{
      ...externalManufacturers,
      for (final brand in knownBrands)
        if (brand.trim().isNotEmpty) _normalize(brand),
    }
      ..removeWhere((alias) => alias.length < 2)
      // A marketplace or a placeholder in the brand column is not a
      // manufacturer to be matched; it is the absence of one.
      ..removeWhere(nonManufacturerBrandWords.contains);

    final ordered = aliases.toList()
      ..sort((left, right) => right.length.compareTo(left.length));

    String? asserted;
    final compatibility = <String>{};
    final identityHay = ' $identityText ';
    final fitmentHay = ' $fitmentText ';

    for (final alias in ordered) {
      final needle = ' $alias ';
      if (asserted == null && identityHay.contains(needle)) {
        asserted = alias;
        final at = identityHay.indexOf(needle);
        consumed.takeToken(alias, from: at);
        continue;
      }
      if (fitmentHay.contains(needle)) compatibility.add(alias);
    }

    // The hint is only ever a confirmation. `IXF … Compatible con
    // SHIMANO/SRAM` produced the hint `Shimano`; accepting it made a Shimano
    // crankset the recommended duplicate of an IXF one.
    final normalizedHint = brandHint == null ? '' : _normalize(brandHint);
    if (asserted == null &&
        normalizedHint.isNotEmpty &&
        !nonManufacturerBrandWords.contains(normalizedHint)) {
      if (brandIsAsserted || identityHay.contains(' $normalizedHint ')) {
        asserted = normalizedHint;
      } else {
        compatibility.add(normalizedHint);
      }
    }

    compatibility.remove(asserted);
    return _BrandDetection(
      asserted: asserted,
      compatibility: Set<String>.unmodifiable(compatibility),
    );
  }

  // ── Model codes ───────────────────────────────────────────────────────

  /// Splits candidate codes three ways.
  ///
  /// * **primary** — codes printed in the product's own name. Only these may
  ///   establish a strong duplicate: the name is where a shop writes what it
  ///   is selling.
  /// * **identity** — primary plus codes from the rest of the identity text.
  /// * **compatibility** — codes that appear only in a fitment clause. A
  ///   rotor whose copy says `compatible M610 M6000` is not an M610: two such
  ///   rotors from different manufacturers would otherwise "share a model"
  ///   and outrank the RT56 the invoice actually names.
  static _ModelCodes _extractModelCodes({
    required _Consumption consumed,
    required String? modelHint,
    required Map<PartSpecKind, String> specs,
    required String identityText,
    required String nameText,
  }) {
    final codes = <String>{};

    void consider(String token) {
      final canonical = token.replaceAll(_nonAlphanumeric, '');
      if (canonical.length < 3 || canonical.length > 24) return;
      if (!_hasLetter.hasMatch(canonical)) return;
      if (!_hasDigit.hasMatch(canonical)) return;
      // A bare measurement is never a model. Anything with a unit suffix was
      // already consumed as a spec; this catches the residue.
      if (_bareMeasurement.hasMatch(canonical)) return;
      if (_bcdToken.hasMatch(canonical)) return;
      if (_stopWords.contains(canonical)) return;
      codes.add(canonical);
    }

    for (final token in consumed.remainingText.split(' ')) {
      if (token.isEmpty) continue;
      consider(token);
    }

    // Two adjacent tokens can be one code written apart (`RT 56`, `D 042SB`).
    final tokens = consumed.remainingText
        .split(' ')
        .where((token) => token.isNotEmpty)
        .toList(growable: false);
    for (var index = 0; index + 1 < tokens.length; index++) {
      final left = tokens[index];
      final right = tokens[index + 1];
      final leftIsShortLetters = left.length <= 4 &&
          left.length >= 2 &&
          _onlyLetters.hasMatch(left) &&
          !_stopWords.contains(left);
      if (leftIsShortLetters && _hasDigit.hasMatch(right)) {
        consider('$left$right');
      }
    }

    final normalizedHint = modelHint == null ? '' : _normalize(modelHint);
    if (normalizedHint.isNotEmpty) {
      consider(normalizedHint.replaceAll(' ', ''));
      for (final token in normalizedHint.split(' ')) {
        consider(token);
      }
    }

    // A value the extractor already understands as a measurement cannot also
    // be a model, even when the hint restated it (`104BCD`, `32H`).
    for (final entry in specs.entries) {
      codes.remove(entry.value);
      codes.remove('${entry.value}h');
      codes.remove('${entry.value}t');
      codes.remove('${entry.value}mm');
      codes.remove('${entry.value}bcd');
      codes.remove('bcd${entry.value}');
    }

    final identityHay = ' ${identityText.replaceAll(_nonAlphanumeric, ' ')} ';
    final nameHay = ' ${nameText.replaceAll(_nonAlphanumeric, ' ')} ';
    final hintCode = modelHint == null
        ? ''
        : _normalize(modelHint).replaceAll(_nonAlphanumeric, '');

    bool appearsIn(String hay, String code) {
      if (hay.contains(' $code ')) return true;
      // `d042sb` is written `D042SB`; `rt56` may be written `rt 56`.
      final spaced = code.replaceAllMapped(
        RegExp(r'([a-z]+)(\d+)'),
        (match) => '${match.group(1)} ${match.group(2)}',
      );
      return hay.contains(' $spaced ');
    }

    final primary = <String>{};
    final identity = <String>{};
    final compatibility = <String>{};
    for (final code in codes) {
      // An explicit model field is the shop's own statement of identity.
      final fromHint = hintCode.isNotEmpty && code == hintCode;
      if (fromHint || appearsIn(nameHay, code)) {
        primary.add(code);
        identity.add(code);
      } else if (appearsIn(identityHay, code)) {
        identity.add(code);
      } else {
        compatibility.add(code);
      }
    }

    return _ModelCodes(
      primary: Set<String>.unmodifiable(primary),
      identity: Set<String>.unmodifiable(identity),
      compatibility: Set<String>.unmodifiable(compatibility),
    );
  }

  static Set<String> _descriptorTokens(String remainingText) {
    final tokens = <String>{};
    for (final token in remainingText.split(' ')) {
      if (token.length < 3) continue;
      if (_stopWords.contains(token)) continue;
      if (_onlyDigits.hasMatch(token)) continue;
      tokens.add(token);
    }
    return Set<String>.unmodifiable(tokens);
  }

  static List<String> _categoryPath(String? path) {
    if (path == null || path.trim().isEmpty) return const <String>[];
    return List<String>.unmodifiable(
      path
          .split('/')
          .map(_normalize)
          .where((segment) => segment.isNotEmpty)
          .toList(growable: false),
    );
  }
}

class _Segments {
  const _Segments({required this.identity, required this.fitment});

  final String identity;
  final String fitment;
}

class _HeadDetection {
  const _HeadDetection({required this.winner, required this.candidates});

  final String? winner;
  final Set<String> candidates;
}

class _BrandDetection {
  const _BrandDetection({required this.asserted, required this.compatibility});

  final String? asserted;
  final Set<String> compatibility;
}

/// Tracks which characters of the normalized text have already been explained
/// by a typed extractor, so a measurement can never be re-read as a model
/// code and a brand can never be re-read as a descriptor.
class _Consumption {
  _Consumption(this._text) : _taken = List<bool>.filled(_text.length, false);

  final String _text;
  final List<bool> _taken;

  void take(int start, int end) {
    final from = start.clamp(0, _text.length);
    final to = end.clamp(0, _text.length);
    for (var index = from; index < to; index++) {
      _taken[index] = true;
    }
  }

  void takeToken(String token, {int from = 0}) {
    final at = _text.indexOf(token, from.clamp(0, _text.length));
    if (at < 0) return;
    take(at, at + token.length);
  }

  String get remainingText {
    final buffer = StringBuffer();
    for (var index = 0; index < _text.length; index++) {
      buffer.write(_taken[index] ? ' ' : _text[index]);
    }
    return buffer
        .toString()
        .replaceAll(ProductIdentityExtractor._collapse, ' ')
        .trim();
  }
}

class _ModelCodes {
  const _ModelCodes({
    required this.primary,
    required this.identity,
    required this.compatibility,
  });

  final Set<String> primary;
  final Set<String> identity;
  final Set<String> compatibility;
}
