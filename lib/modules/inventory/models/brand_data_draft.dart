import 'brand_models.dart';

/// Los datos de una marca que se editan en su página.
enum BrandDataField {
  name,
  website,
  country,
  description,
  active;

  String get label => switch (this) {
        BrandDataField.name => 'Nombre',
        BrandDataField.website => 'Sitio web',
        BrandDataField.country => 'País',
        BrandDataField.description => 'Descripción',
        BrandDataField.active => 'Estado',
      };

  /// «el nombre», «el sitio web»: cómo se nombra en un aviso.
  String get phrase => switch (this) {
        BrandDataField.name => 'el nombre',
        BrandDataField.website => 'el sitio web',
        BrandDataField.country => 'el país',
        BrandDataField.description => 'la descripción',
        BrandDataField.active => 'el estado',
      };
}

/// La edición en su lugar de los datos de una marca del taller: lo que se
/// escribió, lo que cambió contra lo guardado, y lo que no se puede guardar.
///
/// Usa las mismas reglas del formulario de la marca (nombre de al menos dos
/// letras, sitio con su `https://`) y se guarda con el mismo comando
/// (`BrandService.updateBrand`): la página no inventa otra forma de guardar
/// (`.github/GUI_DESIGN_PRINCIPLES.md`, «Un dato se edita donde se lee»).
class BrandDataDraft {
  BrandDataDraft(this.original)
      : _values = {
          BrandDataField.name: original.name,
          BrandDataField.website: original.website ?? '',
          BrandDataField.country: original.country ?? '',
          BrandDataField.description: original.description ?? '',
        },
        _active = original.isActive;

  final ProductBrand original;
  final Map<BrandDataField, String> _values;
  bool _active;

  String text(BrandDataField field) => _values[field] ?? '';
  bool get isActive => _active;

  void setText(BrandDataField field, String value) => _values[field] = value;
  void setActive(bool value) => _active = value;

  String _originalText(BrandDataField field) => switch (field) {
        BrandDataField.name => original.name,
        BrandDataField.website => original.website ?? '',
        BrandDataField.country => original.country ?? '',
        BrandDataField.description => original.description ?? '',
        BrandDataField.active => '',
      };

  /// Lo guardado, para mostrar «Antes: …».
  String before(BrandDataField field) => field == BrandDataField.active
      ? (original.isActive ? 'Activa' : 'Inactiva')
      : _originalText(field);

  bool isChanged(BrandDataField field) => field == BrandDataField.active
      ? _active != original.isActive
      : text(field).trim() != _originalText(field).trim();

  Set<BrandDataField> get changed => {
        for (final field in BrandDataField.values)
          if (isChanged(field)) field,
      };

  int get changeCount => changed.length;

  void revert(BrandDataField field) {
    if (field == BrandDataField.active) {
      _active = original.isActive;
    } else {
      _values[field] = _originalText(field);
    }
  }

  /// Lo que impide guardar, por campo.
  Map<BrandDataField, String> get problems {
    final problems = <BrandDataField, String>{};
    final name = text(BrandDataField.name).trim();
    if (name.isEmpty) {
      problems[BrandDataField.name] = 'El nombre es obligatorio.';
    } else if (name.length < 2) {
      problems[BrandDataField.name] =
          'El nombre debe tener al menos 2 caracteres.';
    }
    final website = text(BrandDataField.website).trim();
    if (website.isNotEmpty) {
      final uri = Uri.tryParse(website);
      if (uri == null || (!uri.hasScheme && !uri.hasAuthority)) {
        problems[BrandDataField.website] =
            'Escribe la dirección completa, con https://';
      }
    }
    return problems;
  }

  /// La marca como queda al guardar. Un campo vacío se guarda vacío; el logo
  /// no se toca aquí (se cambia aparte).
  ProductBrand toBrand() {
    String? optional(BrandDataField field) {
      final value = text(field).trim();
      return value.isEmpty ? null : value;
    }

    return ProductBrand(
      id: original.id,
      tenantId: original.tenantId,
      name: text(BrandDataField.name).trim(),
      description: optional(BrandDataField.description),
      website: optional(BrandDataField.website),
      country: optional(BrandDataField.country),
      logoUrl: original.logoUrl,
      isActive: _active,
      createdAt: original.createdAt,
      updatedAt: DateTime.now(),
    );
  }
}
