import 'package:flutter/foundation.dart';

import '../../utils/bike_finder_search.dart';

/// Prefijos de documento **vivos en producción**, leídos de
/// `get_next_document_number` el 2026-09-17 — no del comentario de
/// `NumberGenerationService`, que todavía dice `AS` para asientos cuando la
/// función publica `AC`.
///
/// El prefijo es por tenant configurable (`p_prefix`), así que esta tabla es el
/// **default** y sirve para interpretar lo que el operador teclea, nunca para
/// generar un número. Un tenant con prefijo propio sigue encontrando su
/// documento por el número, que es lo que la gente recuerda.
const Map<String, String> kGlobalSearchDocumentPrefixes = <String, String>{
  'fv': 'sales_invoice',
  'fc': 'purchase_invoice',
  'pv': 'sales_payment',
  'pc': 'purchase_payment',
  'ac': 'journal_entry',
  'pg': 'mechanic_job',
  'aj': 'stock_adjustment',
  'gto': 'expense',
};

/// Verbos con los que en el taller se pide **hacer** algo, no buscarlo.
///
/// Están en el idioma de la tienda, no en el del ERP: el dueño escribe «hacer
/// una factura», no «crear documento de venta». `emitir` y `sacar` entran por
/// lo mismo. La guía de GUI lo pide explícitamente — «una etiqueta que él no
/// entiende es un defecto» — y esto es su cara de entrada.
const Set<String> _createVerbs = <String>{
  'nuevo',
  'nueva',
  'crear',
  'agregar',
  'anadir',
  'registrar',
  'hacer',
  'emitir',
  'sacar',
  'abrir',
};

/// Palabras que sólo acompañan al verbo y no nombran nada.
const Set<String> _createStopWords = <String>{'un', 'una', 'el', 'la', 'de'};

final RegExp _documentWithPrefix = RegExp(r'^([a-z]{2,3})[\s-]?0*(\d{1,7})$');
final RegExp _bareNumber = RegExp(r'^0*(\d{1,7})$');
final RegExp _rut = RegExp(r'^(\d{7,8})-?([0-9k])$');
final RegExp _phone = RegExp(r'^(?:\+?56)?(9\d{8})$');
final RegExp _separators = RegExp(r'[^a-z0-9]+');

/// Lo que el operador escribió, ya interpretado.
///
/// El buscador global no adivina *qué* quiso decir: mide la **forma** de lo
/// tecleado y la usa para ordenar. `16448` tiene forma de SKU y de número de
/// documento a la vez, así que las dos lecturas salen y el puntaje decide;
/// nunca se descarta una en silencio.
@immutable
class GlobalSearchQuery {
  const GlobalSearchQuery({
    required this.raw,
    required this.normalized,
    required this.tokens,
    this.documentPrefix,
    this.documentNumber,
    this.rut,
    this.phone,
    this.createNoun,
    this.hasCreateVerb = false,
  });

  factory GlobalSearchQuery.parse(String input) {
    final raw = input.trim();
    final normalized = normalizeBikeFinderSearch(raw);
    if (normalized.isEmpty) {
      return GlobalSearchQuery(
        raw: raw,
        normalized: '',
        tokens: const <String>[],
      );
    }

    final tokens = normalized
        .split(_separators)
        .where((token) => token.isNotEmpty)
        .toList(growable: false);

    String? documentPrefix;
    int? documentNumber;
    String? rut;
    String? phone;
    String? createNoun;

    // Un documento se teclea de las tres formas en que se lee en pantalla y en
    // voz: `FV-01035`, `fv 1035` y `1035`. Las tres tienen que llegar al mismo
    // lugar, porque el operador no sabe cuál de ellas es «la correcta».
    final compact = normalized.replaceAll(RegExp(r'\s+'), ' ').trim();
    final prefixed = _documentWithPrefix.firstMatch(compact);
    if (prefixed != null &&
        kGlobalSearchDocumentPrefixes.containsKey(prefixed.group(1))) {
      documentPrefix = prefixed.group(1);
      documentNumber = int.tryParse(prefixed.group(2)!);
    } else {
      final bare = _bareNumber.firstMatch(compact);
      if (bare != null) {
        documentNumber = int.tryParse(bare.group(1)!);
      }
    }

    final compactDigits = compact.replaceAll(RegExp(r'[.\s]'), '');
    final rutMatch = _rut.firstMatch(compactDigits);
    if (rutMatch != null) {
      rut = '${rutMatch.group(1)}${rutMatch.group(2)}';
    }
    final phoneMatch = _phone.firstMatch(compactDigits);
    if (phoneMatch != null) {
      phone = phoneMatch.group(1);
    }

    final hasCreateVerb =
        tokens.isNotEmpty && _createVerbs.contains(tokens.first);
    if (hasCreateVerb && tokens.length >= 2) {
      final noun = tokens
          .skip(1)
          .where((token) => !_createStopWords.contains(token))
          .join(' ');
      if (noun.isNotEmpty) createNoun = noun;
    }

    return GlobalSearchQuery(
      raw: raw,
      normalized: normalized,
      tokens: tokens,
      documentPrefix: documentPrefix,
      documentNumber: documentNumber,
      rut: rut,
      phone: phone,
      createNoun: createNoun,
      hasCreateVerb: hasCreateVerb,
    );
  }

  /// Tal cual se tecleó, para repetirlo en un módulo o en el asistente.
  final String raw;

  /// Plegado: minúsculas, sin tildes y sin `ñ`.
  final String normalized;

  final List<String> tokens;

  /// `fv`, `pg`… cuando la forma lo nombra. `null` cuando el operador escribió
  /// sólo el número, que es lo habitual.
  final String? documentPrefix;

  /// El correlativo sin ceros a la izquierda: `FV-01035` y `1035` dan `1035`.
  final int? documentNumber;

  /// RUT sin puntos ni guion, con dígito verificador.
  final String? rut;

  /// Nueve dígitos del celular chileno, sin `+56`.
  final String? phone;

  /// Lo que se pidió **hacer**: `nueva factura` deja `factura`.
  final String? createNoun;

  /// La consulta empieza con un verbo de crear, aunque todavía no nombre qué.
  ///
  /// Escribir `nuevo` es ya una intención: mientras se teclea la segunda
  /// palabra, la lista no puede pasar de ofrecer acciones a ofrecer navegación
  /// y volver. Esa oscilación entre teclas es lo que hace que un buscador se
  /// sienta inestable.
  final bool hasCreateVerb;

  bool get isEmpty => normalized.isEmpty;

  /// Una sola letra no alcanza para afirmar nada: el índice completo pasaría
  /// el filtro y la lista saltaría con cada tecla.
  bool get isActionable => normalized.length >= 2 || documentNumber != null;

  bool get looksLikeDocument => documentNumber != null;
  bool get looksLikeCreate => hasCreateVerb;
  bool get looksLikeIdentity => rut != null || phone != null;
}
