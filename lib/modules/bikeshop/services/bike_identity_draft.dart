import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/bikeshop_models.dart';
import 'bikeshop_service.dart';

/// Donde viven las fotos de las bicis: `<taller>/<bici>/<nombre al azar>`.
const String kBikeImagesBucket = 'bike-images';

/// La extensión del archivo elegido, si es una que el depósito acepta.
String bikeImageExtension(String fileName) {
  final dot = fileName.lastIndexOf('.');
  final extension = dot < 0 ? '' : fileName.substring(dot + 1).toLowerCase();
  return const {'jpg', 'jpeg', 'png', 'webp', 'heic', 'heif'}
          .contains(extension)
      ? '.$extension'
      : '.jpg';
}

/// Lo que se edita de la bici fuera de la ficha técnica: quién es (en la
/// columna de la bici) y su compra y notas (en Notas).
enum BikeIdentityField {
  brand('Marca'),
  model('Modelo'),
  year('Año'),
  color('Color'),
  serialNumber('N° de serie'),
  photos('Fotos'),
  notes('Notas de la bici'),
  purchaseDate('Fecha de compra'),
  purchasePrice('Precio de compra'),
  warrantyUntil('Garantía hasta');

  const BikeIdentityField(this.label);

  final String label;
}

/// Una marca o un modelo como queda en la bici: el enlace al catálogo, si lo
/// hay, y el nombre escrito.
@immutable
class BikeCatalogPick {
  const BikeCatalogPick({this.id, required this.name});

  final String? id;
  final String name;

  @override
  bool operator ==(Object other) =>
      other is BikeCatalogPick && other.id == id && other.name == name;

  @override
  int get hashCode => Object.hash(id, name);
}

/// Una foto elegida en este equipo, que se sube al guardar.
@immutable
class BikeNewPhoto {
  const BikeNewPhoto({required this.bytes, required this.name});

  final Uint8List bytes;
  final String name;
}

/// La bici mientras se edita en su propia página (dueño, 2026-10-02: «aplica
/// 2» del lienzo «Bicicletas — lo que falta»). El formulario flotante queda
/// sólo para crear una bici.
///
/// Igual que la ficha técnica en su lugar ([BikeSpecDraft]): cada dato sabe
/// si cambió, se deshace por separado y **sólo se escribe lo que cambió**;
/// lo demás viaja tal como lo leyó la edición, y el servidor rechaza el
/// guardado si otro cambió la bici entre medio.
class BikeIdentityDraft {
  BikeIdentityDraft.fromBike(this.bike)
      : _original = Map.unmodifiable(_read(bike)) {
    _values.addAll(_original);
  }

  final Bike bike;
  final Map<BikeIdentityField, Object?> _original;
  final Map<BikeIdentityField, Object?> _values = {};

  /// Las fotos nuevas, en el orden en que se eligieron.
  final List<BikeNewPhoto> _newPhotos = [];

  /// Lo que [rebasedOn] no pudo llevar encima de lo que guardó otro.
  final Set<BikeIdentityField> droppedOnRebase = {};

  /// La misma marca: por su id, o por su nombre si ninguna tiene id.
  static bool _sameBrand(BikeCatalogPick? a, BikeCatalogPick? b) {
    if (a == null || b == null) return a == b;
    if (a.id != null || b.id != null) return a.id == b.id;
    return a.name.toLowerCase() == b.name.toLowerCase();
  }

  static Map<BikeIdentityField, Object?> _read(Bike bike) {
    BikeCatalogPick? pick(String? id, String? name) {
      final text = name?.trim() ?? '';
      if ((id == null || id.isEmpty) && text.isEmpty) return null;
      return BikeCatalogPick(
          id: id == null || id.isEmpty ? null : id, name: text);
    }

    return {
      BikeIdentityField.brand: pick(bike.brandId, bike.brand),
      BikeIdentityField.model: pick(bike.modelId, bike.model),
      BikeIdentityField.year: bike.year?.toString(),
      BikeIdentityField.color: _text(bike.color),
      BikeIdentityField.serialNumber: _text(bike.serialNumber),
      BikeIdentityField.photos: List<String>.unmodifiable(photosOf(bike)),
      BikeIdentityField.notes: _text(bike.notes),
      BikeIdentityField.purchaseDate: _day(bike.purchaseDate),
      BikeIdentityField.purchasePrice:
          bike.purchasePrice == null ? null : _formatPrice(bike.purchasePrice!),
      BikeIdentityField.warrantyUntil: _day(bike.warrantyUntil),
    };
  }

  /// Las fotos de [bike]: la de portada antigua (`image_url`) primero, sin
  /// repetir.
  static List<String> photosOf(Bike bike) {
    final cover = _text(bike.imageUrl);
    return [
      if (cover != null) cover,
      for (final url in bike.imageUrls)
        if (url.trim().isNotEmpty && url.trim() != cover) url.trim(),
    ];
  }

  BikeCatalogPick? get brand =>
      _values[BikeIdentityField.brand] as BikeCatalogPick?;
  BikeCatalogPick? get model =>
      _values[BikeIdentityField.model] as BikeCatalogPick?;

  /// El texto de [field] (año, color, serie, notas, precio).
  String? text(BikeIdentityField field) => _values[field] as String?;

  DateTime? date(BikeIdentityField field) => _values[field] as DateTime?;

  List<String> get photos =>
      (_values[BikeIdentityField.photos] as List<String>?) ?? const [];

  List<BikeNewPhoto> get newPhotos => List.unmodifiable(_newPhotos);

  /// Lo que tenía [field] antes de esta edición, como lo dice el taller.
  String? originalLabel(BikeIdentityField field) =>
      _label(field, _original[field]);

  bool isChanged(BikeIdentityField field) {
    if (field == BikeIdentityField.photos) {
      return _newPhotos.isNotEmpty ||
          !listEquals(photos, _original[field] as List<String>?);
    }
    return _values[field] != _original[field];
  }

  Set<BikeIdentityField> get changedFields => {
        for (final field in BikeIdentityField.values)
          if (isChanged(field)) field,
      };

  int get changeCount => changedFields.length;

  bool get hasChanges => changeCount > 0;

  /// Otra marca deja la bici sin modelo: los modelos son de cada marca, y el
  /// servidor rechaza un modelo del catálogo con la marca de otro. La misma
  /// marca escrita de otra forma («TREK» y «Trek» del catálogo) no es otra.
  /// Volver a la marca que tenía vuelve a su modelo.
  void setBrand(BikeCatalogPick? value) {
    final next = _clean(value);
    final current = brand;
    if (next == current) return;
    _values[BikeIdentityField.brand] = next;
    if (_sameBrand(next, current)) return;
    _values[BikeIdentityField.model] =
        next == _original[BikeIdentityField.brand]
            ? _original[BikeIdentityField.model]
            : null;
  }

  void setModel(BikeCatalogPick? value) {
    _values[BikeIdentityField.model] = _clean(value);
  }

  /// Año, color, serie, notas o precio, como se escribió.
  void setText(BikeIdentityField field, String? value) {
    assert(const {
      BikeIdentityField.year,
      BikeIdentityField.color,
      BikeIdentityField.serialNumber,
      BikeIdentityField.notes,
      BikeIdentityField.purchasePrice,
    }.contains(field));
    var next = _text(value);
    if (next != null && field == BikeIdentityField.purchasePrice) {
      final digits = next.replaceAll(RegExp(r'[^0-9]'), '');
      next = digits.isEmpty ? null : _formatPrice(double.parse(digits));
    }
    _values[field] = next;
  }

  void setDate(BikeIdentityField field, DateTime? value) {
    assert(field == BikeIdentityField.purchaseDate ||
        field == BikeIdentityField.warrantyUntil);
    _values[field] = _day(value);
  }

  void addPhoto(BikeNewPhoto photo) => _newPhotos.add(photo);

  void removeNewPhoto(BikeNewPhoto photo) => _newPhotos.remove(photo);

  void removePhoto(String url) {
    _values[BikeIdentityField.photos] =
        List<String>.unmodifiable(photos.where((photo) => photo != url));
  }

  /// Ya subida y guardada en la bandeja: pasa a ser una foto más.
  void markPhotoUploaded(BikeNewPhoto photo, String url) {
    if (!_newPhotos.remove(photo)) return;
    _values[BikeIdentityField.photos] =
        List<String>.unmodifiable([...photos, url]);
  }

  /// Vuelve [field] a lo que tenía la bici. La marca y el modelo vuelven
  /// juntos si la marca cambió: el modelo de antes es de la marca de antes.
  void revert(BikeIdentityField field) {
    switch (field) {
      case BikeIdentityField.photos:
        _newPhotos.clear();
        _values[field] = _original[field];
      case BikeIdentityField.brand || BikeIdentityField.model
          when isChanged(BikeIdentityField.brand):
        _values[BikeIdentityField.brand] = _original[BikeIdentityField.brand];
        _values[BikeIdentityField.model] = _original[BikeIdentityField.model];
      default:
        _values[field] = _original[field];
    }
  }

  /// Lo que impide guardar, dicho para el mecánico; `null` si se puede.
  String? get blockingMessage {
    final yearText = text(BikeIdentityField.year);
    if (isChanged(BikeIdentityField.year) && yearText != null) {
      final year = int.tryParse(yearText);
      final next = DateTime.now().year + 1;
      if (year == null || year < 1950 || year > next) {
        return 'El año va con cuatro cifras, entre 1950 y $next.';
      }
    }
    final bought = date(BikeIdentityField.purchaseDate);
    final warranty = date(BikeIdentityField.warrantyUntil);
    if ((isChanged(BikeIdentityField.purchaseDate) ||
            isChanged(BikeIdentityField.warrantyUntil)) &&
        bought != null &&
        warranty != null &&
        warranty.isBefore(bought)) {
      return 'La garantía no puede terminar antes de la compra.';
    }
    return null;
  }

  /// La bici como queda, para `saveBikeAggregate`, con los enlaces del
  /// catálogo que el guardado vacía a propósito. Las fotos nuevas se suben
  /// antes ([markPhotoUploaded]); las que siguen sin subir no van.
  ({Bike bike, Set<String> clearCatalogLinks}) build() {
    final json = bike.toJson();
    final cleared = <String>{};
    if (isChanged(BikeIdentityField.brand)) {
      json['brand_id'] = brand?.id;
      json['brand'] = brand?.name ?? '';
      if (brand?.id == null) cleared.add('brand_id');
    }
    if (isChanged(BikeIdentityField.model)) {
      json['model_id'] = model?.id;
      json['model'] = model?.name ?? '';
      if (model?.id == null) cleared.add('model_id');
    }
    if (isChanged(BikeIdentityField.year)) {
      json['year'] = int.tryParse(text(BikeIdentityField.year) ?? '');
    }
    if (isChanged(BikeIdentityField.color)) {
      json['color'] = text(BikeIdentityField.color);
    }
    if (isChanged(BikeIdentityField.serialNumber)) {
      json['serial_number'] = text(BikeIdentityField.serialNumber);
    }
    if (isChanged(BikeIdentityField.notes)) {
      json['notes'] = text(BikeIdentityField.notes);
    }
    if (isChanged(BikeIdentityField.purchasePrice)) {
      json['purchase_price'] =
          _parsePrice(text(BikeIdentityField.purchasePrice));
    }
    if (isChanged(BikeIdentityField.purchaseDate)) {
      json['purchase_date'] = _isoDay(date(BikeIdentityField.purchaseDate));
    }
    if (isChanged(BikeIdentityField.warrantyUntil)) {
      json['warranty_until'] = _isoDay(date(BikeIdentityField.warrantyUntil));
    }
    if (isChanged(BikeIdentityField.photos)) {
      // La primera es la portada: la que el dibujo deja de mostrar.
      json['image_urls'] = photos;
      json['image_url'] = photos.isEmpty ? null : photos.first;
    }
    return (bike: Bike.fromJson(json), clearCatalogLinks: cleared);
  }

  /// La firma de lo que se manda: con la misma firma, un reintento usa la
  /// misma llave de operación y el servidor no lo aplica dos veces.
  String contentSignature(Bike saved, Set<String> clearCatalogLinks) =>
      jsonEncode(<String, dynamic>{
        'bike_id': saved.id,
        'customer_id': saved.customerId,
        'expected_bike_updated_at': bike.updatedAt.toUtc().toIso8601String(),
        'bike': BikeshopService.bikeAggregatePayload(
          saved,
          clearCatalogLinks: clearCatalogLinks,
        ),
      });

  /// La misma edición sobre una versión más nueva de la bici: lo que el
  /// mecánico cambió se vuelve a poner encima.
  BikeIdentityDraft rebasedOn(Bike fresh) {
    final next = BikeIdentityDraft.fromBike(fresh);
    final brandChanged = isChanged(BikeIdentityField.brand);
    for (final field in changedFields) {
      if (field == BikeIdentityField.photos) continue;
      // Un modelo es de su marca: el que se eligió para la marca de antes no
      // va sobre la marca que guardó otro (revisión de Codex, 2026-10-02).
      if (field == BikeIdentityField.model &&
          !brandChanged &&
          !_sameBrand(next.brand, brand)) {
        next.droppedOnRebase.add(field);
        continue;
      }
      next._values[field] = _values[field];
    }
    // Y una marca cambiada lleva su modelo, aunque el modelo no haya cambiado:
    // si no, quedaría el modelo que el otro guardó para su marca.
    if (brandChanged) {
      next._values[BikeIdentityField.model] = _values[BikeIdentityField.model];
    }
    if (isChanged(BikeIdentityField.photos)) {
      final removed = (_original[BikeIdentityField.photos] as List<String>)
          .where((url) => !photos.contains(url))
          .toSet();
      final added = photos.where((url) =>
          !(_original[BikeIdentityField.photos] as List<String>).contains(url));
      next._values[BikeIdentityField.photos] = List<String>.unmodifiable([
        for (final url in next.photos)
          if (!removed.contains(url)) url,
        for (final url in added)
          if (!next.photos.contains(url)) url,
      ]);
      next._newPhotos.addAll(_newPhotos);
    }
    return next;
  }

  /// Cómo dice el taller el valor de [field].
  String? label(BikeIdentityField field) => _label(field, _values[field]);

  static String? _label(BikeIdentityField field, Object? value) {
    if (value == null) return null;
    return switch (value) {
      BikeCatalogPick(:final name) => name.isEmpty ? null : name,
      DateTime() => _dayLabel(value),
      List<String>() => value.isEmpty
          ? null
          : (value.length == 1 ? '1 foto' : '${value.length} fotos'),
      String() when field == BikeIdentityField.purchasePrice => '\$ $value',
      _ => value.toString(),
    };
  }

  static BikeCatalogPick? _clean(BikeCatalogPick? value) {
    if (value == null) return null;
    final name = value.name.trim();
    if (name.isEmpty && value.id == null) return null;
    return BikeCatalogPick(id: value.id, name: name);
  }
}

String? _text(String? value) {
  final text = value?.trim();
  return text == null || text.isEmpty ? null : text;
}

DateTime? _day(DateTime? value) =>
    value == null ? null : DateTime(value.year, value.month, value.day);

String? _isoDay(DateTime? value) {
  if (value == null) return null;
  String two(int part) => part.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)}';
}

const List<String> _months = [
  'ene', 'feb', 'mar', 'abr', 'may', 'jun', //
  'jul', 'ago', 'sept', 'oct', 'nov', 'dic',
];

String _dayLabel(DateTime value) =>
    '${value.day} ${_months[value.month - 1]} ${value.year}';

/// «1.290.000»: el precio en pesos con punto de miles, sin decimales.
String _formatPrice(double value) {
  final digits = value.round().toString();
  final buffer = StringBuffer();
  for (var index = 0; index < digits.length; index++) {
    if (index > 0 && (digits.length - index) % 3 == 0) buffer.write('.');
    buffer.write(digits[index]);
  }
  return buffer.toString();
}

double? _parsePrice(String? value) {
  final digits = value?.replaceAll(RegExp(r'[^0-9]'), '') ?? '';
  return digits.isEmpty ? null : double.parse(digits);
}
