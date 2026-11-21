/// Un modelo con tallas y colores en el ERP (20261120230000): lo que la ficha
/// del producto muestra en «Modelo y variantes» y lo que el equipo arma ahí.
///
/// Cada variante sigue siendo su producto; el modelo dice qué cambia entre
/// ellas (sus ejes, «Color» y «Talla», con los valores en orden) y cada una
/// cuál es (sus opciones). La base valida lo mismo al guardar
/// (`product_model_save_v1`): un producto de la tienda que no es servicio,
/// en un modelo a lo más, un valor de cada eje y ninguna combinación
/// repetida.
library;

/// Un eje del modelo y sus valores, en el orden en que se muestran.
class ProductModelAxis {
  const ProductModelAxis({required this.name, required this.values});

  factory ProductModelAxis.fromJson(Map<String, dynamic> json) =>
      ProductModelAxis(
        name: (json['name'] ?? '').toString().trim(),
        values: [
          for (final value in (json['values'] as List?) ?? const [])
            if (value.toString().trim().isNotEmpty) value.toString().trim(),
        ],
      );

  final String name;
  final List<String> values;

  Map<String, Object?> toJson() => {'name': name, 'values': values};

  ProductModelAxis copyWith({String? name, List<String>? values}) =>
      ProductModelAxis(name: name ?? this.name, values: values ?? this.values);
}

/// Una variante: su producto, lo que el equipo necesita ver de él y cuál es.
class ProductModelMember {
  const ProductModelMember({
    required this.productId,
    required this.name,
    required this.options,
    this.sku = '',
    this.price = 0,
    this.stock = 0,
    this.trackStock = true,
    this.isActive = true,
    this.onWebsite = false,
    this.image,
  });

  factory ProductModelMember.fromJson(Map<String, dynamic> json) =>
      ProductModelMember(
        productId: (json['product_id'] ?? '').toString(),
        name: (json['name'] ?? '').toString(),
        sku: (json['sku'] ?? '').toString(),
        options: {
          if (json['options'] is Map)
            for (final entry in (json['options'] as Map).entries)
              '${entry.key}': '${entry.value}'.trim(),
        },
        price: _toDouble(json['price']),
        stock: _toDouble(json['stock']).round(),
        trackStock: json['track_stock'] != false,
        isActive: json['is_active'] != false,
        onWebsite: json['on_website'] == true,
        image: _blankToNull(json['image']),
      );

  final String productId;
  final String name;
  final String sku;
  final Map<String, String> options;
  final double price;
  final int stock;
  final bool trackStock;
  final bool isActive;
  final bool onWebsite;
  final String? image;

  ProductModelMember withOptions(Map<String, String> options) =>
      ProductModelMember(
        productId: productId,
        name: name,
        sku: sku,
        options: options,
        price: price,
        stock: stock,
        trackStock: trackStock,
        isActive: isActive,
        onWebsite: onWebsite,
        image: image,
      );
}

/// Un modelo guardado.
class ProductModel {
  const ProductModel({
    required this.id,
    required this.name,
    required this.axes,
    required this.members,
    this.updatedAt,
  });

  static ProductModel? fromJson(Object? json) {
    if (json is! Map) return null;
    final map = Map<String, dynamic>.from(json);
    final id = (map['id'] ?? '').toString();
    if (id.isEmpty) return null;
    return ProductModel(
      id: id,
      name: (map['name'] ?? '').toString(),
      updatedAt: _blankToNull(map['updated_at']),
      axes: [
        for (final axis in (map['axes'] as List?) ?? const [])
          if (axis is Map) ProductModelAxis.fromJson(Map.from(axis)),
      ],
      members: [
        for (final member in (map['members'] as List?) ?? const [])
          if (member is Map) ProductModelMember.fromJson(Map.from(member)),
      ],
    );
  }

  final String id;
  final String name;

  /// Lo que la base devolvió al leer o guardar: si otra persona lo cambia
  /// después, el guardado se niega (`product_model_stale`).
  final String? updatedAt;
  final List<ProductModelAxis> axes;
  final List<ProductModelMember> members;
}

/// Un producto que se puede sumar a un modelo (`product_model_candidates_v1`).
class ProductModelCandidate {
  const ProductModelCandidate({
    required this.productId,
    required this.name,
    this.sku = '',
    this.price = 0,
    this.stock = 0,
    this.onWebsite = false,
    this.image,
    this.modelId,
    this.modelName,
  });

  factory ProductModelCandidate.fromJson(Map<String, dynamic> json) =>
      ProductModelCandidate(
        productId: (json['product_id'] ?? '').toString(),
        name: (json['name'] ?? '').toString(),
        sku: (json['sku'] ?? '').toString(),
        price: _toDouble(json['price']),
        stock: _toDouble(json['stock']).round(),
        onWebsite: json['on_website'] == true,
        image: _blankToNull(json['image']),
        modelId: _blankToNull(json['model_id']),
        modelName: _blankToNull(json['model_name']),
      );

  final String productId;
  final String name;
  final String sku;
  final double price;
  final int stock;
  final bool onWebsite;
  final String? image;

  /// El modelo en que ya está, si está en uno.
  final String? modelId;
  final String? modelName;

  ProductModelMember toMember() => ProductModelMember(
        productId: productId,
        name: name,
        sku: sku,
        price: price,
        stock: stock,
        onWebsite: onWebsite,
        image: image,
        options: const {},
      );
}

/// Lo que el equipo está armando en «Modelo y variantes»: inmutable, cada
/// cambio devuelve otro borrador.
class ProductModelDraft {
  const ProductModelDraft({
    required this.name,
    required this.axes,
    required this.members,
    this.id,
    this.updatedAt,
  });

  factory ProductModelDraft.fromModel(ProductModel model) => ProductModelDraft(
        id: model.id,
        updatedAt: model.updatedAt,
        name: model.name,
        axes: model.axes,
        members: model.members,
      );

  /// Los límites que la base hace cumplir.
  static const maxAxes = 3;
  static const maxValues = 40;
  static const maxMembers = 60;

  final String? id;
  final String? updatedAt;
  final String name;
  final List<ProductModelAxis> axes;
  final List<ProductModelMember> members;

  ProductModelDraft copyWith({
    String? name,
    List<ProductModelAxis>? axes,
    List<ProductModelMember>? members,
  }) =>
      ProductModelDraft(
        id: id,
        updatedAt: updatedAt,
        name: name ?? this.name,
        axes: axes ?? this.axes,
        members: members ?? this.members,
      );

  /// Un modelo nuevo a partir de los nombres de sus productos: el nombre que
  /// comparten es el del modelo, y lo que cambia se reparte en color, talla
  /// y medida («Rodillera Leatt 3DF 5.0 Blanco/Negro S/M» y «… Negra XXL»:
  /// modelo «Rodillera Leatt 3DF 5.0», Color Blanco/Negro y Negra, Talla
  /// S/M y XXL). Un eje con un solo valor no es eje. Lo que no se pudo leer
  /// queda vacío para que el equipo lo elija.
  factory ProductModelDraft.suggest(List<ProductModelMember> products) {
    if (products.isEmpty) {
      return const ProductModelDraft(name: '', axes: [], members: []);
    }
    final tokens = [for (final product in products) _words(product.name)];
    var prefix = 0;
    while (tokens.every((words) => words.length > prefix + 1) &&
        tokens.every(
          (words) =>
              words[prefix].toLowerCase() == tokens.first[prefix].toLowerCase(),
        )) {
      prefix++;
    }
    var suffix = 0;
    while (tokens.every((words) => words.length > prefix + suffix + 1) &&
        tokens.every(
          (words) =>
              words[words.length - 1 - suffix].toLowerCase() ==
              tokens.first[tokens.first.length - 1 - suffix].toLowerCase(),
        )) {
      suffix++;
    }
    final name = [
      ...tokens.first.take(prefix),
      ...tokens.first.skip(tokens.first.length - suffix),
    ].join(' ');

    final parsed = [
      for (final words in tokens)
        _parseRest(words.sublist(prefix, words.length - suffix)),
    ];
    List<String> distinct(String Function(_ParsedRest rest) of) {
      final seen = <String>{};
      final values = <String>[];
      for (final rest in parsed) {
        final value = of(rest);
        if (value.isNotEmpty && seen.add(value.toLowerCase())) {
          values.add(value);
        }
      }
      return values;
    }

    final colors = distinct((rest) => rest.color);
    final sizes = distinct((rest) => rest.size)..sort(_compareSizes);
    final measures = distinct((rest) => rest.measure)..sort(_compareMeasures);
    final axes = <ProductModelAxis>[
      if (colors.length > 1) ProductModelAxis(name: 'Color', values: colors),
      if (sizes.length > 1) ProductModelAxis(name: 'Talla', values: sizes),
      if (measures.length > 1)
        ProductModelAxis(name: 'Medida', values: measures),
    ];
    String combination(int i) => [
          for (final axis in axes)
            switch (axis.name) {
              'Color' => parsed[i].color.toLowerCase(),
              'Talla' => parsed[i].size.toLowerCase(),
              _ => parsed[i].measure.toLowerCase(),
            },
        ].join('\u0000');
    final distinguishes =
        {for (var i = 0; i < parsed.length; i++) combination(i)}.length ==
            parsed.length;
    if (axes.isEmpty ||
        !distinguishes ||
        distinct((rest) => rest.other).length > 1) {
      // Nada que se reconozca como color, talla o medida, o algo más que
      // cambia (un código): lo que cambia en el nombre es la variante.
      final rests = distinct((rest) => rest.whole);
      final values = rests.isEmpty
          ? [for (final product in products) product.name]
          : rests;
      return ProductModelDraft(
        name: name.isEmpty ? products.first.name : name,
        axes: [ProductModelAxis(name: 'Variante', values: values)],
        members: [
          for (var i = 0; i < products.length; i++)
            products[i].withOptions({
              'Variante': parsed[i].whole.isEmpty
                  ? products[i].name
                  : _matching(values, parsed[i].whole) ?? '',
            }),
        ],
      ).sortedMembers();
    }
    return ProductModelDraft(
      name: name.isEmpty ? products.first.name : name,
      axes: axes,
      members: [
        for (var i = 0; i < products.length; i++)
          products[i].withOptions({
            for (final axis in axes)
              axis.name: _matching(
                      axis.values,
                      switch (axis.name) {
                        'Color' => parsed[i].color,
                        'Talla' => parsed[i].size,
                        _ => parsed[i].measure,
                      }) ??
                  '',
          }),
      ],
    ).sortedMembers();
  }

  /// Las variantes en el orden de los ejes: primero el color, después la
  /// talla, como las muestra la tienda.
  ProductModelDraft sortedMembers() {
    int rank(ProductModelMember member, ProductModelAxis axis) {
      final index = axis.values.indexOf(member.options[axis.name] ?? '');
      return index < 0 ? axis.values.length : index;
    }

    final sorted = [...members]..sort((a, b) {
        for (final axis in axes) {
          final order = rank(a, axis).compareTo(rank(b, axis));
          if (order != 0) return order;
        }
        return a.name.compareTo(b.name);
      });
    return copyWith(members: sorted);
  }

  /// Suma un producto y le pone, de cada eje, el valor que su nombre dice
  /// («… Negra XXL» queda Color Negra, Talla XXL). Lo que el nombre no dice
  /// queda vacío.
  ProductModelDraft withMember(ProductModelMember product) {
    if (members.any((member) => member.productId == product.productId)) {
      return this;
    }
    return copyWith(
      members: [
        ...members,
        product.withOptions({
          for (final axis in axes)
            axis.name: inferValue(product.name, axis) ?? '',
        }),
      ],
    );
  }

  ProductModelDraft withoutMember(String productId) => copyWith(
        members: [
          for (final member in members)
            if (member.productId != productId) member,
        ],
      );

  ProductModelDraft withOption(String productId, String axis, String value) =>
      copyWith(
        members: [
          for (final member in members)
            member.productId == productId
                ? member.withOptions({...member.options, axis: value})
                : member,
        ],
      );

  /// Agrega un eje (sin valores) a todas las variantes.
  ProductModelDraft withAxis(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty ||
        axes.length >= maxAxes ||
        axes.any((axis) => axis.name.toLowerCase() == trimmed.toLowerCase())) {
      return this;
    }
    return copyWith(
      axes: [...axes, ProductModelAxis(name: trimmed, values: const [])],
      members: [
        for (final member in members)
          member.withOptions({...member.options, trimmed: ''}),
      ],
    );
  }

  ProductModelDraft withoutAxis(String name) => copyWith(
        axes: [
          for (final axis in axes)
            if (axis.name != name) axis,
        ],
        members: [
          for (final member in members)
            member.withOptions({...member.options}..remove(name)),
        ],
      );

  /// Agrega un valor a un eje, y se lo pone a las variantes cuyo nombre lo
  /// dice y que todavía no tienen valor en ese eje.
  ProductModelDraft withAxisValue(String axisName, String value) {
    final trimmed = value.trim();
    final index = axes.indexWhere((axis) => axis.name == axisName);
    if (trimmed.isEmpty || index < 0) return this;
    final axis = axes[index];
    if (axis.values.length >= maxValues ||
        axis.values.any((v) => v.toLowerCase() == trimmed.toLowerCase())) {
      return this;
    }
    final updated = axis.copyWith(values: [...axis.values, trimmed]);
    return copyWith(
      axes: [
        for (var i = 0; i < axes.length; i++) i == index ? updated : axes[i],
      ],
      members: [
        for (final member in members)
          (member.options[axisName] ?? '').isEmpty &&
                  inferValue(
                          member.name,
                          ProductModelAxis(
                            name: axisName,
                            values: [trimmed],
                          )) !=
                      null
              ? member.withOptions({...member.options, axisName: trimmed})
              : member,
      ],
    );
  }

  /// Quita un valor de un eje; las variantes que lo tenían quedan sin valor.
  ProductModelDraft withoutAxisValue(String axisName, String value) => copyWith(
        axes: [
          for (final axis in axes)
            axis.name == axisName
                ? axis.copyWith(
                    values: [
                      for (final v in axis.values)
                        if (v != value) v,
                    ],
                  )
                : axis,
        ],
        members: [
          for (final member in members)
            member.options[axisName] == value
                ? member.withOptions({...member.options, axisName: ''})
                : member,
        ],
      );

  /// Lo que falta para guardar, en palabras del taller; vacío si se puede.
  List<String> get problems {
    final found = <String>[];
    if (name.trim().isEmpty) found.add('Falta el nombre del modelo.');
    if (axes.isEmpty) found.add('Falta al menos un eje, como Color o Talla.');
    for (final axis in axes) {
      if (axis.values.isEmpty) found.add('«${axis.name}» no tiene valores.');
    }
    if (members.length < 2) {
      found.add('Un modelo junta dos productos o más.');
    }
    for (final member in members) {
      for (final axis in axes) {
        if ((member.options[axis.name] ?? '').isEmpty) {
          found.add(
            'Falta ${axis.name.toLowerCase()} de «${member.name}».',
          );
        }
      }
    }
    final seen = <String, String>{};
    for (final member in members) {
      final key = [
        for (final axis in axes) member.options[axis.name] ?? '',
      ].join('\u0000');
      if (key.replaceAll('\u0000', '').isEmpty) continue;
      final other = seen[key];
      if (other != null) {
        found.add('«${member.name}» y «$other» son la misma combinación.');
      } else {
        seen[key] = member.name;
      }
    }
    return found;
  }

  bool get canSave => problems.isEmpty;

  /// Lo que recibe `product_model_save_v1`.
  Map<String, Object?> toJson() => {
        if (id != null) 'id': id,
        if (updatedAt != null) 'updated_at': updatedAt,
        'name': name.trim(),
        'axes': [for (final axis in axes) axis.toJson()],
        'members': [
          for (final member in members)
            {
              'product_id': member.productId,
              'options': {
                for (final axis in axes)
                  axis.name: member.options[axis.name] ?? '',
              },
            },
        ],
      };

  /// El valor de [axis] que el nombre de un producto dice, el más largo si
  /// dice varios («Negra» no gana sobre «Blanco/Negro» en «… Blanco/Negro
  /// XXL»); null si no dice ninguno.
  static String? inferValue(String productName, ProductModelAxis axis) {
    final words = _words(productName).map((w) => w.toLowerCase()).toList();
    String? best;
    for (final value in axis.values) {
      final valueWords = _words(value).map((w) => w.toLowerCase()).toList();
      if (valueWords.isEmpty) continue;
      for (var start = 0; start + valueWords.length <= words.length; start++) {
        var same = true;
        for (var i = 0; i < valueWords.length; i++) {
          if (words[start + i] != valueWords[i]) {
            same = false;
            break;
          }
        }
        if (same) {
          if (best == null || value.length > best.length) best = value;
          break;
        }
      }
    }
    return best;
  }
}

/// Lo que cambia en el nombre de un producto, repartido.
class _ParsedRest {
  const _ParsedRest({
    required this.color,
    required this.size,
    required this.measure,
    required this.other,
    required this.whole,
  });

  final String color;
  final String size;
  final String measure;

  /// Lo que no es color, talla ni medida (un código como «J50013»).
  final String other;
  final String whole;
}

final _letterSize = RegExp(
  r'^(xxs|xs|s|m|l|xl|xxl|xxxl|2xl|3xl|xs/s|s/m|m/l|l/xl|xl/xxl|xxl/xxxl)$',
  caseSensitive: false,
);
final _sizeDescriptor = RegExp(
  r'^\(?\d{1,2}([.,]\d)?(us|eu|uk)\)?$',
  caseSensitive: false,
);
final _measure = RegExp(
  r'^\(?\d+([.,]\d+)?(-\d+([.,]\d+)?)?(mm|cm|")\)?$',
  caseSensitive: false,
);
final _packCount = RegExp(r'^\d+(u|pcs?|un)$', caseSensitive: false);

final _colorWord = RegExp(r"^[\p{L}/'-]+$", unicode: true);

_ParsedRest _parseRest(List<String> words) {
  final color = <String>[];
  final other = <String>[];
  var size = '';
  var measure = '';
  for (final word in words) {
    if (size.isEmpty && _letterSize.hasMatch(word)) {
      size = word.toUpperCase();
    } else if (_sizeDescriptor.hasMatch(word) || _packCount.hasMatch(word)) {
      continue;
    } else if (measure.isEmpty && _measure.hasMatch(word)) {
      measure = word.replaceAll(RegExp(r'[()]'), '');
    } else if (_colorWord.hasMatch(word)) {
      color.add(word);
    } else {
      other.add(word);
    }
  }
  return _ParsedRest(
    color: color.join(' '),
    size: size,
    measure: measure,
    other: other.join(' '),
    whole: words.join(' '),
  );
}

const _sizeOrder = [
  'XXS',
  'XS',
  'XS/S',
  'S',
  'S/M',
  'M',
  'M/L',
  'L',
  'L/XL',
  'XL',
  'XL/XXL',
  'XXL',
  '2XL',
  'XXL/XXXL',
  'XXXL',
  '3XL',
];

int _compareSizes(String a, String b) {
  final ia = _sizeOrder.indexOf(a.toUpperCase());
  final ib = _sizeOrder.indexOf(b.toUpperCase());
  return (ia < 0 ? 99 : ia).compareTo(ib < 0 ? 99 : ib);
}

int _compareMeasures(String a, String b) {
  double number(String text) =>
      double.tryParse(
        RegExp(r'\d+([.,]\d+)?')
                .firstMatch(text)
                ?.group(0)
                ?.replaceAll(',', '.') ??
            '',
      ) ??
      0;
  return number(a).compareTo(number(b));
}

String? _matching(List<String> values, String text) {
  for (final value in values) {
    if (value.toLowerCase() == text.toLowerCase()) return value;
  }
  return null;
}

List<String> _words(String text) =>
    text.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();

double _toDouble(Object? value) =>
    value is num ? value.toDouble() : double.tryParse('${value ?? ''}') ?? 0;

String? _blankToNull(Object? value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}
