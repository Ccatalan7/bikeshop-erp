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
    ),
    BikePartFamily(
      id: 'seatpost',
      physicalClass: PartPhysicalClass.seating,
      label: 'Tija',
      heads: ['tija', 'tijas', 'seatpost', 'seat post'],
      negativeHeads: ['adaptador de tija', 'adaptador tija'],
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
        'mando de cambio',
        'palanca de cambio',
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
        'brake lever',
        'brake levers',
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
      negativeHeads: ['protector de neumatico', 'palanca de neumatico'],
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

    // ── Válvulas ──────────────────────────────────────────────────────────
    BikePartFamily(
      id: 'tubeless_valve',
      physicalClass: PartPhysicalClass.valve,
      label: 'Válvula tubeless',
      heads: ['valvula tubeless', 'valvulas tubeless', 'tubeless valve'],
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
      heads: ['timbre', 'timbres', 'bell', 'bocina'],
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
        'portabotella',
        'bottle cage',
      ],
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
    ),
    BikePartFamily(
      id: 'phone_mount',
      physicalClass: PartPhysicalClass.carrying,
      label: 'Porta celular',
      heads: [
        'porta celular',
        'portacelular',
        'soporte de celular',
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
          BikePartHeadPhrase(phrase: head, familyId: family.id),
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
  });

  final String phrase;
  final String familyId;

  /// The phrase names this family only when one of the family's context words
  /// is present in the same text.
  final bool requiresContext;
}
