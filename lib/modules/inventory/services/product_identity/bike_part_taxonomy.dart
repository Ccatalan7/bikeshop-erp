/// Canonical taxonomy of the physical bicycle parts this shop actually buys
/// and sells.
///
/// It exists because the previous matcher inferred a product family from a
/// bag of words over the whole title. A real catalog title names more than one
/// part: `Volante IXF Integrado Black 170Mm + Motor BSA + Corona 34T` names
/// the crankset it *is*, the bottom bracket it *includes*, and the chainring
/// it *carries*. Bag-of-words classified that crankset as a bottom bracket and
/// the fail-closed gate then deleted the only correct candidate in the
/// catalog (measured 2026-08-09 against the 1555 active production products).
///
/// Two ideas fix that class of failure and both live here:
///
/// * a family is identified by its **head noun**, and every head noun carries
///   the position at which it was found, so the earliest, most specific noun
///   in the identity segment wins over a part merely mentioned later;
/// * families belong to a **physical class**. Two families in different
///   classes are never the same object no matter how similar their text is,
///   which is what lets the matcher refuse a candidate instead of padding a
///   top-k with something absurd.
library;

/// A group of families that describe the same kind of physical object.
///
/// Sharing a class is not a match — a hub and a rim are both `wheel` — but
/// *not* sharing one is a proven mismatch. The classes are deliberately coarse
/// so that a genuine synonym pair (`maza` / `buje`) can never fall on opposite
/// sides of the gate.
enum PartPhysicalClass {
  steering,
  seating,
  drivetrain,
  braking,
  wheel,
  tyre,
  valve,
  suspension,
  frame,
  control,
  lighting,
  security,
  carrying,
  hydration,
  protection,
  tool,
  consumable,
  apparel,
  accessory,
  unknown,
}

/// One recognizable family of parts.
class BikePartFamily {
  const BikePartFamily({
    required this.id,
    required this.physicalClass,
    required this.label,
    required this.heads,
    this.negativeHeads = const <String>[],
    this.absorbs = const <String>[],
    this.ambiguousHeads = const <String>[],
    this.contextWords = const <String>[],
    this.genericHeads = const <String>[],
  });

  /// Stable identifier used by profiles, explanations and tests.
  final String id;

  /// The physical object class this family belongs to.
  final PartPhysicalClass physicalClass;

  /// Operator-facing name, in the shop's own Chilean vocabulary.
  final String label;

  /// Head nouns that identify the family, normalized and space separated.
  /// A head matches on a whole-word boundary; plurals are listed explicitly
  /// rather than derived, because Spanish stemming produced the false hits
  /// that made `rotores` match `rotor de freno` but also `motor`.
  final List<String> heads;

  /// Phrases that, when present, mean the head noun is describing something
  /// else. `porta bidon` is not a `bidon`; `adaptador de tija` is not a
  /// `tija`.
  final List<String> negativeHeads;

  /// Heads that name this family only when the sentence corroborates them.
  ///
  /// `Pinza` is a caliper on a bicycle and a pair of pliers on a workbench,
  /// and a shop buys both. Listing every tool phrase as a negative is a race
  /// nobody wins — `pinzas industriales`, `pinza de precisión`, the next one
  /// somebody invents. An ambiguous head instead has to be *earned*: it counts
  /// only when a word from [contextWords] appears in the same text, and is
  /// simply not a head otherwise.
  final List<String> ambiguousHeads;

  /// What has to appear for [ambiguousHeads] to count.
  final List<String> contextWords;

  /// Families this one supersedes when both match the identity segment.
  /// A crankset sold with its bottom bracket is still a crankset.
  final List<String> absorbs;

  /// Catch-all nouns that name only the broad class, not a concrete object.
  ///
  /// When a title also contains a specific family in the same physical class,
  /// these heads are semantically dominated. `Herramienta` beside `extractor
  /// de núcleo de válvula` does not make the source ambiguous; `shifter`
  /// beside `terminal de cable` still does because both are concrete objects.
  /// This is head-scoped rather than family-scoped because `sacabielas` is a
  /// real object even though the same legacy family also owns `extractor`.
  final List<String> genericHeads;
}

/// The registry. Order is irrelevant: resolution is by head-noun position and
/// specificity, never by declaration order.
class BikePartTaxonomy {
  const BikePartTaxonomy._();

  static const List<BikePartFamily> families = <BikePartFamily>[
    // ── Dirección ─────────────────────────────────────────────────────────
    BikePartFamily(
      id: 'stem',
      physicalClass: PartPhysicalClass.steering,
      label: 'Tee',
      heads: ['tee', 'tees', 'potencia', 'potencias', 'stem', 'vastago'],
      negativeHeads: ['adaptador de tee', 'adaptador tee'],
    ),
    BikePartFamily(
      id: 'stem_spacer',
      physicalClass: PartPhysicalClass.steering,
      label: 'Espaciador de dirección',
      heads: [
        'espaciador de vastago',
        'espaciadores de vastago',
        'espaciador de direccion',
        'espaciadores de direccion',
        'espaciador de tee',
        'espaciadores de tee',
        'headset spacer',
        'headset spacers',
        'stem spacer',
        'stem spacers',
        'espaciador',
        'espaciadores',
        'spacer',
        'spacers',
      ],
      // A bare spacer in this catalog is a steering spacer unless a longer,
      // explicit object phrase claims it (for example `cassette spacer`).
      // Treat the noun as generic so concrete steering peers dominate it.
      genericHeads: ['espaciador', 'espaciadores', 'spacer', 'spacers'],
      negativeHeads: [
        'espaciador de motor',
        'espaciador motor',
        'espaciador para motor',
        'motor spacer',
      ],
    ),
    BikePartFamily(
      id: 'handlebar',
      physicalClass: PartPhysicalClass.steering,
      label: 'Manubrio',
      heads: ['manubrio', 'manubrios', 'manillar', 'manillares', 'handlebar'],
    ),
    BikePartFamily(
      id: 'headset',
      physicalClass: PartPhysicalClass.steering,
      label: 'Juego de dirección',
      heads: [
        'juego de direccion',
        'juego direccion',
        'headset',
        'direccion',
      ],
    ),
    BikePartFamily(
      id: 'grip',
      physicalClass: PartPhysicalClass.steering,
      label: 'Puños',
      heads: ['puno', 'punos', 'grip', 'grips', 'empunadura', 'empunaduras'],
    ),
    BikePartFamily(
      id: 'bar_end',
      physicalClass: PartPhysicalClass.steering,
      label: 'Cachos',
      heads: ['cacho', 'cachos', 'bar end', 'bar ends'],
    ),

    // ── Asiento ───────────────────────────────────────────────────────────
    BikePartFamily(
      id: 'saddle',
      physicalClass: PartPhysicalClass.seating,
      label: 'Sillín',
      heads: ['sillin', 'sillines', 'saddle', 'asiento', 'asientos'],
      negativeHeads: [
        'funda de asiento',
        'fundas de asiento',
        'funda de sillin',
        'cubre asiento',
        'cubre asientos',
        'saddle cover',
        'seat cover',
      ],
    ),
    BikePartFamily(
      id: 'saddle_cover',
      physicalClass: PartPhysicalClass.seating,
      label: 'Cubre asiento',
      heads: [
        'funda de asiento',
        'fundas de asiento',
        'funda de sillin',
        'fundas de sillin',
        'cubre asiento',
        'cubre asientos',
        'cubre sillin',
        'saddle cover',
        'seat cover',
        'seat cushion cover',
      ],
    ),
    BikePartFamily(
      id: 'seatpost',
      physicalClass: PartPhysicalClass.seating,
      label: 'Tija',
      heads: ['tija', 'tijas', 'seatpost', 'seat post'],
      negativeHeads: ['adaptador de tija', 'adaptador tija'],
    ),
    BikePartFamily(
      id: 'seatpost_shim',
      physicalClass: PartPhysicalClass.seating,
      label: 'Adaptador de tija',
      heads: [
        'adaptador de tija de asiento',
        'adaptador de tija',
        'adaptador tija',
        'adaptador de tubo de poste de asiento',
        'adaptador de tubo de sillin',
        'adaptador de tubo de asiento',
        'cuna de sillin',
        'cuna de asiento',
        'reductor de tija',
        'casquillo de tija',
        'seatpost shim',
        'seat post shim',
        'seat tube adapter',
      ],
      absorbs: ['saddle', 'seatpost'],
    ),
    BikePartFamily(
      id: 'seat_clamp',
      physicalClass: PartPhysicalClass.seating,
      label: 'Abrazadera de tija',
      heads: [
        'abrazadera de tija',
        'abrazadera tija',
        'collarin',
        'seat clamp',
      ],
    ),

    // ── Transmisión ───────────────────────────────────────────────────────
    BikePartFamily(
      id: 'crankset',
      physicalClass: PartPhysicalClass.drivetrain,
      label: 'Volante',
      heads: [
        'volante',
        'volantes',
        'biela',
        'bielas',
        'crankset',
        'crank set',
        'pedivela',
        'juego de bielas',
        'plato de manivela',
        'platos de manivela',
        'platos y bielas',
        'plato y biela',
      ],
      negativeHeads: [
        'extractor de biela',
        'extractor de bielas',
        'protector de biela',
        'protector de bielas',
        'cubierta protectora',
      ],
      absorbs: ['bottom_bracket', 'chainring'],
    ),
    BikePartFamily(
      id: 'crank_arm',
      physicalClass: PartPhysicalClass.drivetrain,
      label: 'Biela suelta',
      heads: [
        'biela izquierda',
        'biela derecha',
        'bielas izquierdas',
        'pedivela izquierda',
        'pedivela derecha',
        'crank arm',
        'left crank',
        'right crank',
      ],
    ),
    BikePartFamily(
      id: 'chainring',
      physicalClass: PartPhysicalClass.drivetrain,
      label: 'Plato',
      heads: [
        'plato',
        'platos',
        'corona',
        'coronas',
        'chainring',
        'chain ring',
      ],
      negativeHeads: ['protector de plato', 'guarda plato'],
    ),
    BikePartFamily(
      id: 'chainring_guard',
      physicalClass: PartPhysicalClass.protection,
      label: 'Protector de plato',
      heads: [
        'protector de plato',
        'protector de platos',
        'protector de biela',
        'protector de bielas',
        'cubierta protectora',
        'guarda plato',
        'bash guard',
        'chainring guard',
        'crank guard',
      ],
    ),
    BikePartFamily(
      id: 'chain_guide',
      physicalClass: PartPhysicalClass.drivetrain,
      label: 'Guía de cadena',
      heads: ['guia de cadena', 'guia cadena', 'chain guide', 'iscg'],
    ),
    BikePartFamily(
      id: 'bottom_bracket',
      physicalClass: PartPhysicalClass.drivetrain,
      label: 'Motor / caja pedalera',
      heads: [
        'motor',
        'motores',
        'bottom bracket',
        'movimiento central',
        'caja pedalera',
        'pedalier',
        'eje de motor',
      ],
      negativeHeads: ['motor electrico', 'bicicleta electrica'],
    ),
    BikePartFamily(
      id: 'pedal',
      physicalClass: PartPhysicalClass.drivetrain,
      label: 'Pedales',
      heads: ['pedal', 'pedales', 'pedals'],
    ),
    BikePartFamily(
      id: 'chain',
      physicalClass: PartPhysicalClass.drivetrain,
      label: 'Cadena',
      heads: ['cadena', 'cadenas', 'chain'],
      negativeHeads: [
        'corta cadena',
        'guia de cadena',
        'candado de cadena',
        'aceite de cadena',
        'limpiador de cadena',
      ],
    ),
    BikePartFamily(
      id: 'chain_link',
      physicalClass: PartPhysicalClass.drivetrain,
      label: 'Missinglink',
      heads: [
        'missinglink',
        'missing link',
        'eslabon rapido',
        'eslabones rapidos',
        'eslabon',
        'eslabones',
        'enlace rapido',
        'conector de cadena',
        'conector de enlace rapido',
        'junta de conector de enlace rapido',
        'master link',
        'masterlink',
        'power link',
        'powerlink',
        'quick link',
        'quicklink',
        'chain quick link',
        'chain quick link connector',
        'quick link connector',
        'chain link connector',
      ],
      negativeHeads: [
        'sticker protector',
        'protector de cadena',
        'cubre cadena',
      ],
    ),
    BikePartFamily(
      id: 'surface_protector',
      physicalClass: PartPhysicalClass.protection,
      label: 'Sticker protector',
      heads: [
        'sticker protector',
        'sticker',
        'stickers',
        'calcomania',
        'calcomanias',
        'protector de marco',
        'protector de cadena',
        'protector de vaina',
        'cubre vaina',
        'cubre cadena',
        'lamina protectora',
      ],
      negativeHeads: [
        'protector de plato',
        'protector de platos',
        'protector de biela',
        'protector de bielas',
        'protector de llanta',
        'protector de neumatico',
      ],
    ),
    BikePartFamily(
      id: 'cassette',
      physicalClass: PartPhysicalClass.drivetrain,
      label: 'Cassette',
      heads: [
        'cassette',
        'casete',
        'pinon',
        'pinones',
        'freewheel',
        'rueda libre',
      ],
      negativeHeads: [
        'espaciador de cassette',
        'espaciadores de cassette',
        'extractor de cassette',
        'latiguillo de cassette',
      ],
    ),
    BikePartFamily(
      id: 'cassette_spacer',
      physicalClass: PartPhysicalClass.accessory,
      label: 'Espaciador de cassette',
      heads: [
        'espaciador de cassette',
        'espaciadores de cassette',
        'espaciador cassette',
        'espaciador de pinon',
        'cassette spacer',
      ],
    ),
    BikePartFamily(
      id: 'derailleur',
      physicalClass: PartPhysicalClass.drivetrain,
      label: 'Desviador',
      heads: [
        'desviador',
        'desviadores',
        'cambiador',
        'cambiadores',
        'derailleur',
        'cambio trasero',
        'cambio delantero',
      ],
      negativeHeads: [
        'patilla de cambio',
        'percha de cambio',
        'gancho de cambio',
      ],
    ),
    BikePartFamily(
      id: 'derailleur_hanger',
      physicalClass: PartPhysicalClass.frame,
      label: 'Patilla de cambio',
      heads: [
        'patilla de cambio',
        'patilla cambio',
        'percha',
        'perchas',
        'postiza',
        'postizas',
        'gancho de cambio',
        'derailleur hanger',
        'mech hanger',
      ],
      negativeHeads: [
        'extension de postiza',
        'extension para postiza',
        'extensor de postiza',
        'extensor de patilla',
        'hanger extender',
        'derailleur extender',
      ],
    ),
    BikePartFamily(
      // The hanger and the piece that lengthens it are two products, exactly
      // as a cassette and its spacer are. They live in the same catalog leaf
      // and share a manufacturer, so nothing but the object itself separates
      // them: reading `postiza` inside `Extensión para Postiza ZTTO` made the
      // extender the recommended match for a plain hanger.
      id: 'derailleur_hanger_extender',
      physicalClass: PartPhysicalClass.drivetrain,
      label: 'Extensión de postiza',
      heads: [
        'extension de postiza',
        'extension para postiza',
        'extensor de postiza',
        'extensor de patilla',
        'extension de patilla',
        'hanger extender',
        'derailleur extender',
        'extensor de desviador',
        'extensor de suspension de desviador',
      ],
    ),
    BikePartFamily(
      id: 'pulley',
      physicalClass: PartPhysicalClass.drivetrain,
      label: 'Poleas',
      heads: ['polea', 'poleas', 'roldana', 'roldanas', 'pulley', 'pulleys'],
    ),
    BikePartFamily(
      id: 'shifter',
      physicalClass: PartPhysicalClass.control,
      label: 'Shifter',
      heads: [
        'shifter',
        'shifters',
        'manilla de cambio',
        'manillas de cambio',
        'mando de cambio',
        'mandos de cambio',
        'palanca de cambio',
        'palancas de cambio',
        'palanca de cambios',
        'palancas de cambios',
      ],
    ),

    // ── Frenos ────────────────────────────────────────────────────────────
    BikePartFamily(
      id: 'brake_rotor',
      physicalClass: PartPhysicalClass.braking,
      label: 'Rotor',
      heads: [
        'rotor',
        'rotores',
        'disco de freno',
        'disco freno',
        'brake rotor',
        'brake disc',
      ],
      negativeHeads: ['adaptador de rotor', 'adaptador rotor'],
    ),
    BikePartFamily(
      id: 'brake_pad',
      physicalClass: PartPhysicalClass.braking,
      label: 'Pastillas',
      heads: [
        'pastilla',
        'pastillas',
        'brake pad',
        'brake pads',
        'zapata',
        'zapatas',
        'patin de freno',
        'patines de freno',
        // Bare, because the shop writes `patines de frenos` in the plural and
        // the exact phrase then misses. With no pad head left, `v brake` won
        // the title and a set of brake shoes was read as a brake arm.
        'patin',
        'patines',
      ],
      // The system name in `patines ... V-Brake` describes fitment; the sold
      // object is still the replaceable shoe/pad, never the brake arm.
      absorbs: ['rim_brake_arm'],
    ),
    BikePartFamily(
      id: 'brake_caliper',
      physicalClass: PartPhysicalClass.braking,
      label: 'Caliper',
      heads: [
        'caliper',
        'calipers',
        'brake caliper',
        'mordaza de freno',
        // `Pinza` is what the shop and the supplier both call a caliper, on
        // disc and on rim brakes alike. Without it a caliper had no family at
        // all, so nothing could eliminate anything and the AI's guessed name
        // decided the object.
        'pinza de freno',
        'pinzas de freno',
      ],
      // Bare `pinza` is the word the supplier uses for a caliper — and the
      // word a tool catalogue uses for pliers. It counts only next to
      // something that makes it a brake.
      ambiguousHeads: ['pinza', 'pinzas'],
      negativeHeads: [
        // `Pinzas de doble pivote` es un freno de aro: en esta tienda se llama
        // herradura de tiro lateral, no caliper.
        'doble pivote',
        'tiro lateral',
      ],
      contextWords: [
        'freno',
        'frenos',
        'disco',
        'discos',
        'v brake',
        'vbrake',
        'doble pivote',
        'hidraulico',
        'hidraulica',
        'mecanico',
        'mecanica',
        'bicicleta',
      ],
    ),
    BikePartFamily(
      // A complete hydraulic brake is the sold assembly (lever, hose and
      // caliper), not whichever visible component a photo happens to name.
      // Keep the heads precise: bare `freno` is a system word and must never
      // turn every brake-related replacement into a complete brake.
      id: 'hydraulic_brake_assembly',
      physicalClass: PartPhysicalClass.braking,
      label: 'Freno hidráulico completo',
      heads: [
        'freno de disco hidraulico',
        'frenos de disco hidraulicos',
        'freno hidraulico completo',
        'frenos hidraulicos completos',
        'freno hidraulico',
        'frenos hidraulicos',
        'juego de freno hidraulico',
        'juego de frenos hidraulicos',
        'set de freno hidraulico',
        'set de frenos hidraulicos',
        'conjunto de freno hidraulico',
        'conjunto de frenos hidraulicos',
        'hydraulic disc brake set',
        'hydraulic disc brake',
        'hydraulic brake set',
        'hydraulic brakes',
        'hydraulic brake',
      ],
      negativeHeads: [
        'pastilla de freno hidraulico',
        'pastillas de freno hidraulico',
        'hydraulic brake pad',
        'hydraulic brake pads',
        'manilla de freno hidraulico',
        'manillas de freno hidraulico',
        'maneta de freno hidraulico',
        'manetas de freno hidraulico',
        'hydraulic brake lever',
        'hydraulic brake levers',
        'caliper de freno hidraulico',
        'pinza de freno hidraulico',
        'hydraulic brake caliper',
        'hydraulic brake calipers',
        'adaptador de freno hidraulico',
        'manguera de freno hidraulico',
        'latiguillo de freno hidraulico',
        'hydraulic brake hose',
        'hydraulic brake hoses',
        'hydraulic brake line',
        'hydraulic brake lines',
        'kit de purga',
        'aceite mineral',
        'liquido de freno',
      ],
      absorbs: ['brake_caliper', 'brake_lever'],
    ),
    // A `herradura` is the arm pair of a rim brake. It is not a disc caliper,
    // and the catalog keeps them in different leaves
    // (`… / Frenos / Calipers` vs `… / Frenos / V-Brake / Herraduras`).
    // Folding both into one family made the two interchangeable, which is the
    // same class of error as calling either of them «Frenos».
    BikePartFamily(
      id: 'rim_brake_arm',
      physicalClass: PartPhysicalClass.braking,
      label: 'Herradura',
      heads: [
        'herradura',
        'herraduras',
        'tiro lateral',
        'v brake',
        'vbrake',
        'brazo de freno',
        'brazos de freno',
        'cantilever',
        // Un freno de tiro lateral o de doble pivote es, en el catálogo de
        // esta tienda, una «Herradura»: `Herradura de Tiro Lateral ZTTO ASA
        // 2.5D`. El catálogo manda sobre la taxonomía — mandarlo a `Calipers`
        // hizo que la compuerta rechazara justo el producto correcto.
        'doble pivote',
        'frenos c',
      ],
      negativeHeads: [
        'goma v brake',
        'gomas v brake',
        'zapata v brake',
        'zapatas v brake',
        'patin v brake',
      ],
    ),
    BikePartFamily(
      id: 'brake_lever',
      physicalClass: PartPhysicalClass.control,
      label: 'Manilla de freno',
      heads: [
        'manilla de freno',
        'manillas de freno',
        'maneta de freno',
        'manetas de freno',
        'brake lever',
        'brake levers',
        'brake handle',
        'brake handles',
        'brake handle grip',
        'brake handle grips',
        'palanca de freno',
      ],
    ),
    BikePartFamily(
      id: 'brake_adapter',
      physicalClass: PartPhysicalClass.accessory,
      label: 'Adaptador de freno',
      heads: [
        'adaptador de freno',
        'adaptador freno',
        'adaptador de disco de freno',
        'adaptador disco de freno',
        'adaptador de rotor',
        'adaptador rotor',
        'brake adapter',
      ],
    ),

    // ── Ruedas ────────────────────────────────────────────────────────────
    BikePartFamily(
      id: 'hub',
      physicalClass: PartPhysicalClass.wheel,
      label: 'Maza',
      heads: ['maza', 'mazas', 'buje', 'bujes', 'hub', 'hubs'],
      negativeHeads: ['cono de maza', 'eje de maza', 'rodamiento de maza'],
    ),
    BikePartFamily(
      id: 'rim',
      physicalClass: PartPhysicalClass.wheel,
      label: 'Llanta',
      heads: ['llanta', 'llantas', 'aro', 'aros', 'rim', 'rims'],
      negativeHeads: ['cinta de llanta', 'protector de llanta'],
    ),
    BikePartFamily(
      id: 'wheelset',
      physicalClass: PartPhysicalClass.wheel,
      label: 'Rueda armada',
      heads: [
        'rueda armada',
        'ruedas armadas',
        'wheelset',
        'juego de ruedas',
      ],
    ),
    BikePartFamily(
      id: 'spoke',
      physicalClass: PartPhysicalClass.wheel,
      label: 'Rayos',
      heads: ['rayo', 'rayos', 'spoke', 'spokes', 'radio', 'radios'],
    ),
    BikePartFamily(
      id: 'bearing',
      physicalClass: PartPhysicalClass.accessory,
      label: 'Rodamiento',
      heads: [
        'rodamiento',
        'rodamientos',
        'balin',
        'balines',
        'bearing',
        'bearings',
        'cono',
        'conos',
      ],
    ),
    BikePartFamily(
      id: 'axle',
      physicalClass: PartPhysicalClass.accessory,
      label: 'Eje',
      heads: ['eje', 'ejes', 'axle', 'perno pasante'],
      negativeHeads: ['eje de motor', 'ejes de motor'],
    ),
    BikePartFamily(
      id: 'axle_adapter',
      physicalClass: PartPhysicalClass.accessory,
      label: 'Adaptador de eje',
      heads: [
        'adaptador de eje',
        'adaptadores de eje',
        'casquillo de eje',
        'manguito de eje',
        'axle adapter',
        'axle bushing',
        'bushing',
      ],
    ),
    BikePartFamily(
      id: 'bolt',
      physicalClass: PartPhysicalClass.accessory,
      label: 'Pernos',
      heads: ['perno', 'pernos', 'tornillo', 'tornillos', 'bolt', 'bolts'],
      negativeHeads: ['6 pernos', 'seis pernos'],
    ),
    BikePartFamily(
      id: 'rim_tape',
      physicalClass: PartPhysicalClass.accessory,
      label: 'Cinta de llanta',
      heads: ['cinta de llanta', 'cinta llanta', 'rim tape', 'fondo de llanta'],
    ),

    // ── Neumáticos y cámaras ──────────────────────────────────────────────
    BikePartFamily(
      id: 'tire',
      physicalClass: PartPhysicalClass.tyre,
      label: 'Neumático',
      heads: [
        'neumatico',
        'neumaticos',
        'cubierta',
        'cubiertas',
        'tire',
        'tires',
        'tyre',
      ],
      negativeHeads: [
        'protector de neumatico',
        'palanca de neumatico',
        'tapa basica',
        'tapas basicas',
        'shift cap',
        'cable cap',
      ],
    ),
    BikePartFamily(
      id: 'tube',
      physicalClass: PartPhysicalClass.tyre,
      label: 'Cámara',
      heads: ['camara', 'camaras', 'tube', 'tubes', 'inner tube'],
      negativeHeads: ['protector de camara', 'parche de camara'],
    ),
    BikePartFamily(
      id: 'tyre_liner',
      physicalClass: PartPhysicalClass.protection,
      label: 'Protector antipinchazo',
      heads: [
        'protector de neumatico',
        'protector de camara',
        'antipinchazo',
        'tyre liner',
      ],
    ),
    BikePartFamily(
      id: 'patch',
      physicalClass: PartPhysicalClass.consumable,
      label: 'Parches',
      heads: ['parche', 'parches', 'patch', 'patches'],
    ),
    BikePartFamily(
      id: 'sealant',
      physicalClass: PartPhysicalClass.consumable,
      label: 'Sellante',
      heads: ['sellante', 'sellantes', 'liquido sellante', 'sealant'],
    ),
    BikePartFamily(
      id: 'tubeless_repair_kit',
      physicalClass: PartPhysicalClass.tool,
      label: 'Kit de reparación tubeless',
      heads: [
        'herramienta de reparacion de bicicletas sin camara',
        'herramienta de reparacion de neumaticos sin camara',
        'herramienta de reparacion tubeless',
        'herramienta reparacion tubeless',
        'kit de reparacion tubeless',
        'kit reparacion tubeless',
        'kit tubeless tripas',
        'tubeless repair tool',
        'tubeless repair kit',
        'tire plug kit',
      ],
    ),

    // ── Válvulas ──────────────────────────────────────────────────────────
    BikePartFamily(
      id: 'tubeless_valve',
      physicalClass: PartPhysicalClass.valve,
      label: 'Válvula tubeless',
      heads: [
        'valvula tubeless',
        'valvulas tubeless',
        'valvula presta',
        'valvulas presta',
        'valvula francesa',
        'presta valve',
        'tubeless valve',
      ],
    ),
    BikePartFamily(
      id: 'valve_core',
      physicalClass: PartPhysicalClass.valve,
      label: 'Obús',
      heads: [
        'obus',
        'obuses',
        'nucleo de valvula',
        'valve core',
        'nucleo valvula',
      ],
    ),
    BikePartFamily(
      id: 'valve_adapter',
      physicalClass: PartPhysicalClass.accessory,
      label: 'Adaptador de válvula',
      heads: [
        'adaptador de valvula',
        'adaptador valvula',
        'adaptador de valvulas',
        'adaptador presta',
        'adaptador de presta',
        'valve adapter',
        'convertidor de valvula',
        'conector de valvula',
        'conectores de valvula',
      ],
    ),

    // ── Suspensión y cuadro ───────────────────────────────────────────────
    BikePartFamily(
      id: 'fork',
      physicalClass: PartPhysicalClass.suspension,
      label: 'Horquilla',
      heads: ['horquilla', 'horquillas', 'fork', 'forks', 'suspension'],
    ),
    BikePartFamily(
      id: 'shock',
      physicalClass: PartPhysicalClass.suspension,
      label: 'Amortiguador',
      heads: ['amortiguador', 'amortiguadores', 'shock', 'rear shock'],
    ),
    BikePartFamily(
      id: 'frame',
      physicalClass: PartPhysicalClass.frame,
      label: 'Cuadro',
      heads: ['cuadro', 'cuadros', 'frame', 'marco'],
    ),

    // ── Cables, luces, seguridad, carga ───────────────────────────────────
    BikePartFamily(
      id: 'cable_end_cap',
      physicalClass: PartPhysicalClass.control,
      label: 'Terminal o tope de piola',
      heads: [
        'terminal de piola',
        'terminales de piola',
        'terminal de cable',
        'terminales de cable',
        'tope de funda',
        'topes de funda',
        'tope terminal',
        'tapa basica',
        'tapas basicas',
        'tapa para cable',
        'tapas para cable',
        'tapa de extremo de cable exterior',
        'tapas de extremo de cable exterior',
        'tapa de extremos de cable exterior',
        'tapas de extremos de cable exterior',
        'punta de cable',
        'puntas de cable',
        'carcasa de punta de cable',
        'carcasas de punta de cable',
        'punta de piola',
        'puntas de piola',
        'capuchon de piola',
        'capuchones de piola',
        'capuchon piola',
        'capuchones piola',
        'inner cable tip',
        'inner cable tips',
        'cable tip',
        'cable tips',
        'cable crimp',
        'cable crimps',
        'cable end cap',
        'cable end caps',
        'cable cap',
        'cable caps',
        'housing ferrule',
        'housing ferrules',
        'cable ferrule',
        'cable ferrules',
        'shift cable cap',
        'shift cable caps',
        'shift cap',
        'shift caps',
        'brake cable cap',
        'brake cable caps',
        'brake cap',
        'brake caps',
      ],
      absorbs: ['cable_housing'],
    ),
    BikePartFamily(
      id: 'cable_housing',
      physicalClass: PartPhysicalClass.control,
      label: 'Piola y funda',
      heads: [
        'piola',
        'piolas',
        'funda',
        'fundas',
        'cable de freno',
        'cable de cambio',
        'housing',
        'cable interior',
      ],
      negativeHeads: [
        'funda de asiento',
        'fundas de asiento',
        'funda de sillin',
        'cubre asiento',
        'cubre asientos',
        'saddle cover',
        'seat cover',
      ],
    ),
    BikePartFamily(
      id: 'light',
      physicalClass: PartPhysicalClass.lighting,
      label: 'Luz',
      heads: ['luz', 'luces', 'foco', 'focos', 'light', 'headlight'],
    ),
    BikePartFamily(
      id: 'lock',
      physicalClass: PartPhysicalClass.security,
      label: 'Candado',
      heads: ['candado', 'candados', 'lock', 'locks'],
    ),
    BikePartFamily(
      id: 'bell',
      physicalClass: PartPhysicalClass.accessory,
      label: 'Timbre',
      heads: [
        'timbre',
        'timbres',
        'campanilla',
        'campanillas',
        'claxon',
        'claxones',
        'bell',
        'bocina',
        'horn',
      ],
    ),
    BikePartFamily(
      id: 'mirror',
      physicalClass: PartPhysicalClass.accessory,
      label: 'Espejo',
      heads: ['espejo', 'espejos', 'mirror'],
    ),
    BikePartFamily(
      id: 'bottle_cage',
      physicalClass: PartPhysicalClass.hydration,
      label: 'Porta caramañola',
      heads: [
        'porta caramagiola',
        'porta caramanola',
        'portacaramagiola',
        'porta bidon',
        'portabidon',
        'porta botella',
        'porta botellas',
        'portabotella',
        'portabotellas',
        'soporte de botella de agua',
        'soportes de botella de agua',
        'soporte para botella de agua',
        'soportes para botella de agua',
        'soporte de botella',
        'soportes de botella',
        'soporte para botella',
        'soportes para botella',
        'water bottle cage',
        'water bottle holder',
        'bottle cage',
        'bottle cages',
        'bottle holder',
        'bottle holders',
      ],
    ),
    BikePartFamily(
      id: 'applicator_bottle',
      physicalClass: PartPhysicalClass.accessory,
      label: 'Botella aplicadora',
      heads: [
        'botella aplicadora',
        'botellas aplicadoras',
        'botella dosificadora',
        'botellas dosificadoras',
        'squeeze bottle',
        'squeeze bottles',
        'applicator bottle',
        'applicator bottles',
        'squirt container',
        'squirt containers',
        'glue bottle',
        'glue bottles',
      ],
      absorbs: ['bottle'],
    ),
    BikePartFamily(
      id: 'bottle',
      physicalClass: PartPhysicalClass.hydration,
      label: 'Botella',
      heads: [
        'botella',
        'botellas',
        'bidon',
        'bidones',
        'caramagiola',
        'water bottle',
      ],
      negativeHeads: [
        'porta botella',
        'porta botellas',
        'portabotella',
        'portabotellas',
        'soporte de botella',
        'soportes de botella',
        'soporte para botella',
        'soportes para botella',
        'water bottle cage',
        'water bottle holder',
        'bottle cage',
        'bottle cages',
        'bottle holder',
        'bottle holders',
        'botella aplicadora',
        'botellas aplicadoras',
        'botella dosificadora',
        'botellas dosificadoras',
        'squeeze bottle',
        'squeeze bottles',
        'applicator bottle',
        'applicator bottles',
        'squirt container',
        'squirt containers',
        'glue bottle',
        'glue bottles',
      ],
    ),
    BikePartFamily(
      id: 'phone_mount',
      physicalClass: PartPhysicalClass.carrying,
      label: 'Porta celular',
      heads: [
        'porta celular',
        'portacelular',
        'soporte de celular',
        'soportes de celular',
        'soporte para celular',
        'soportes para celular',
        'soporte celular',
        'soportes celulares',
        'porta telefono',
        'porta telefonos',
        'portatelefono',
        'portatelefonos',
        'soporte de telefono',
        'soportes de telefono',
        'soporte para telefono',
        'soportes para telefono',
        'soporte telefono',
        'soportes telefonos',
        'smartphone mount',
        'smartphone holder',
        'mobile phone mount',
        'mobile phone holder',
        'phone mount',
        'phone holder',
      ],
    ),
    BikePartFamily(
      id: 'bag',
      physicalClass: PartPhysicalClass.carrying,
      label: 'Bolso',
      heads: [
        'bolso',
        'bolsos',
        'alforja',
        'alforjas',
        'mochila',
        'mochilas',
        'pannier',
      ],
    ),
    BikePartFamily(
      id: 'rack',
      physicalClass: PartPhysicalClass.carrying,
      label: 'Parrilla',
      heads: ['parrilla', 'parrillas', 'portaequipaje', 'rear rack'],
    ),
    BikePartFamily(
      id: 'fender',
      physicalClass: PartPhysicalClass.protection,
      label: 'Barrofango',
      heads: [
        'barrofango',
        'barrofangos',
        'guardabarro',
        'guardabarros',
        'fender',
        'mudguard',
      ],
    ),
    BikePartFamily(
      id: 'kickstand',
      physicalClass: PartPhysicalClass.accessory,
      label: 'Pata de apoyo',
      heads: ['pata de apoyo', 'pata lateral', 'kickstand', 'caballete'],
    ),
    BikePartFamily(
      id: 'helmet',
      physicalClass: PartPhysicalClass.apparel,
      label: 'Casco',
      heads: ['casco', 'cascos', 'helmet', 'helmets'],
    ),
    BikePartFamily(
      id: 'glove',
      physicalClass: PartPhysicalClass.apparel,
      label: 'Guantes',
      heads: ['guante', 'guantes', 'glove', 'gloves'],
    ),

    // ── Herramientas y químicos ───────────────────────────────────────────
    BikePartFamily(
      id: 'chain_tool',
      physicalClass: PartPhysicalClass.tool,
      label: 'Corta cadena',
      heads: [
        'corta cadena',
        'corta cadenas',
        'chain tool',
        'chain breaker',
        'tronchacadena',
      ],
    ),
    BikePartFamily(
      id: 'valve_core_tool',
      physicalClass: PartPhysicalClass.tool,
      label: 'Extractor de obús',
      heads: [
        'extractor de nucleo de valvula',
        'extractor nucleo de valvula',
        'extractor de obus',
        'extractor obus',
        'herramienta de nucleo de valvula',
        'valve core remover',
        'valve core tool',
      ],
    ),
    BikePartFamily(
      id: 'puller_tool',
      physicalClass: PartPhysicalClass.tool,
      label: 'Extractor',
      heads: [
        'extractor',
        'extractores',
        'puller',
        'sacabielas',
        'saca bielas',
      ],
      genericHeads: ['extractor', 'extractores', 'puller'],
    ),
    BikePartFamily(
      id: 'pump',
      physicalClass: PartPhysicalClass.tool,
      label: 'Bombín',
      heads: ['bombin', 'bombines', 'inflador', 'infladores', 'pump'],
    ),
    BikePartFamily(
      id: 'tool',
      physicalClass: PartPhysicalClass.tool,
      label: 'Herramienta',
      heads: [
        'herramienta',
        'herramientas',
        'llave allen',
        'llave torx',
        'destornillador',
        'alicate',
        'alicates',
        'tool',
        'tools',
      ],
      genericHeads: ['herramienta', 'herramientas', 'tool', 'tools'],
    ),
    BikePartFamily(
      id: 'lubricant',
      physicalClass: PartPhysicalClass.consumable,
      label: 'Lubricante',
      heads: [
        'lubricante',
        'lubricantes',
        'aceite',
        'aceites',
        'grasa',
        'desengrasante',
        'limpiador',
      ],
    ),
  ];

  static final Map<String, BikePartFamily> _byId = <String, BikePartFamily>{
    for (final family in families) family.id: family,
  };

  static BikePartFamily? byId(String? id) => id == null ? null : _byId[id];

  static PartPhysicalClass classOf(String? id) =>
      byId(id)?.physicalClass ?? PartPhysicalClass.unknown;

  static String labelOf(String? id) => byId(id)?.label ?? 'Sin familia';

  /// Every head phrase in the taxonomy, longest first.
  ///
  /// Longest-first is the whole reason a multi-word head can beat a single
  /// word inside it: `espaciador de cassette` must be found before `cassette`,
  /// otherwise a spacer is classified as the sprocket set it merely fits.
  static final List<BikePartHeadPhrase> orderedHeads = () {
    final phrases = <BikePartHeadPhrase>[
      for (final family in families)
        for (final head in family.heads)
          BikePartHeadPhrase(
            phrase: head,
            familyId: family.id,
            isGenericWithinClass: family.genericHeads.contains(head),
          ),
      for (final family in families)
        for (final head in family.ambiguousHeads)
          BikePartHeadPhrase(
            phrase: head,
            familyId: family.id,
            requiresContext: true,
          ),
    ];
    phrases.sort((left, right) {
      final byLength = right.phrase.length.compareTo(left.phrase.length);
      if (byLength != 0) return byLength;
      return left.phrase.compareTo(right.phrase);
    });
    return List<BikePartHeadPhrase>.unmodifiable(phrases);
  }();

  /// Multi-word heads whose parts are also written joined in real supplier
  /// text (`cortacadena`, `portabidon`, `guardabarros`). Used by the extractor
  /// to split a compound token before head detection runs.
  static final Set<String> compoundHeads = () {
    final compounds = <String>{};
    for (final family in families) {
      for (final head in family.heads) {
        if (!head.contains(' ')) continue;
        final joined = head.replaceAll(' ', '');
        if (joined.length >= 8) compounds.add(joined);
      }
    }
    return Set<String>.unmodifiable(compounds);
  }();

  /// Maps a joined compound back to its spaced head (`cortacadena` →
  /// `corta cadena`).
  static final Map<String, String> compoundExpansions = () {
    final expansions = <String, String>{};
    for (final family in families) {
      for (final head in family.heads) {
        if (!head.contains(' ')) continue;
        final joined = head.replaceAll(' ', '');
        if (joined.length >= 8) expansions[joined] = head;
      }
    }
    // Real supplier spellings that are not a simple join of a canonical head.
    expansions.addAll(const <String, String>{
      'cortacadenas': 'corta cadena',
      'sacabielas': 'extractor de bielas',
      'guardabarros': 'guardabarro',
      'portaequipajes': 'portaequipaje',
      'antipinchazos': 'antipinchazo',
    });
    return Map<String, String>.unmodifiable(expansions);
  }();
}

/// One head noun and the family it identifies.
class BikePartHeadPhrase {
  const BikePartHeadPhrase({
    required this.phrase,
    required this.familyId,
    this.requiresContext = false,
    this.isGenericWithinClass = false,
  });

  final String phrase;
  final String familyId;

  /// The phrase names this family only when one of the family's context words
  /// is present in the same text.
  final bool requiresContext;

  /// Whether this phrase is only a catch-all for its physical class.
  final bool isGenericWithinClass;
}
