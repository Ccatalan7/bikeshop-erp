import 'package:flutter/foundation.dart';

import '../../../shared/utils/chilean_utils.dart';

/// Los datos de un cliente que se escriben a mano en su hoja «Datos».
enum ClientDataField {
  name('Nombre', 'name', 'el nombre'),
  phone('Teléfono', 'phone', 'el teléfono'),
  email('Correo', 'email', 'el correo'),
  rut('RUT', 'rut', 'el RUT'),
  address('Dirección', 'address', 'la dirección'),
  city('Ciudad', 'city', 'la ciudad'),
  region('Región', 'region', 'la región'),
  notes('Notas del taller', 'notes', 'las notas');

  const ClientDataField(this.label, this.column, this.phrase);

  final String label;

  /// La columna de `customers`.
  final String column;

  /// Cómo se nombra en una frase: «revisa el correo y el RUT».
  final String phrase;
}

/// Las columnas que lee la hoja: las suyas y las del registro.
const String kClientRecordColumns =
    'id,tenant_id,auth_user_id,name,phone,email,rut,address,city,region,'
    'notes,is_active,created_at,updated_at';

/// La línea que dejó la importación desde Zoho en `notes` («Zoho ID: …»).
/// Las 1336 notas importadas son sólo eso (2026-10-03): no es una nota del
/// taller, es el origen del cliente.
final RegExp _zohoLine =
    RegExp(r'^\s*Zoho ID:\s*\S+\s*$', caseSensitive: false);

/// El cliente tal como lo leyó la hoja.
@immutable
class ClientRecord {
  const ClientRecord({
    required this.id,
    required this.tenantId,
    required this.name,
    required this.createdAt,
    required this.updatedAtToken,
    this.authUserId,
    this.phone,
    this.email,
    this.rut,
    this.address,
    this.city,
    this.region,
    this.notes,
    this.isActive = true,
  });

  factory ClientRecord.fromRow(Map<String, dynamic> row) {
    String? text(String key) {
      final value = row[key]?.toString().trim();
      return value == null || value.isEmpty ? null : value;
    }

    return ClientRecord(
      id: row['id'].toString(),
      tenantId: row['tenant_id']?.toString() ?? '',
      authUserId: text('auth_user_id'),
      name: row['name']?.toString().trim() ?? '',
      phone: text('phone'),
      email: text('email'),
      rut: text('rut'),
      address: text('address'),
      city: text('city'),
      region: text('region'),
      notes: row['notes']?.toString(),
      isActive: row['is_active'] as bool? ?? true,
      createdAt:
          DateTime.tryParse(row['created_at']?.toString() ?? '')?.toLocal() ??
              DateTime.now(),
      // El texto tal como lo guardó la base: comparar un DateTime de vuelta
      // pierde los microsegundos en la web y daría todo guardado por «viejo».
      updatedAtToken: row['updated_at']?.toString() ?? '',
    );
  }

  final String id;
  final String tenantId;
  final String? authUserId;
  final String name;
  final String? phone;
  final String? email;
  final String? rut;
  final String? address;
  final String? city;
  final String? region;

  /// `notes` completo, con la línea de Zoho si la tiene.
  final String? notes;
  final bool isActive;
  final DateTime createdAt;

  /// Con qué versión se edita: el guardado se rechaza si cambió.
  final String updatedAtToken;

  bool get hasPortalAccess => authUserId != null;

  /// La línea «Zoho ID: …», si el cliente vino de Zoho.
  String? get zohoLine {
    for (final line in (notes ?? '').split('\n')) {
      if (_zohoLine.hasMatch(line)) return line.trim();
    }
    return null;
  }

  bool get importedFromZoho => zohoLine != null;

  /// Lo que el taller escribió en las notas, sin la línea de Zoho.
  String? get shopNotes {
    final text = (notes ?? '')
        .split('\n')
        .where((line) => !_zohoLine.hasMatch(line))
        .join('\n')
        .trim();
    return text.isEmpty ? null : text;
  }

  String? valueOf(ClientDataField field) => switch (field) {
        ClientDataField.name => name.isEmpty ? null : name,
        ClientDataField.phone => phone,
        ClientDataField.email => email,
        ClientDataField.rut => rut,
        ClientDataField.address => address,
        ClientDataField.city => city,
        ClientDataField.region => region,
        ClientDataField.notes => shopNotes,
      };
}

/// Por qué un guardado no se hizo.
class ClientDataSaveException implements Exception {
  const ClientDataSaveException(this.message, {this.field});

  final String message;

  /// El dato que lo causó, para mostrarlo junto a él.
  final ClientDataField? field;

  @override
  String toString() => message;
}

/// Otro guardó este cliente después de que la hoja lo leyó.
class ClientDataStaleException implements Exception {
  const ClientDataStaleException();

  @override
  String toString() => 'El cliente cambió mientras se editaba.';
}

/// Los datos del cliente mientras se editan en su hoja (dueño, 2026-10-03:
/// «la primera cara visible del cliente deberían ser sus datos, esos campos
/// están escondidos detrás del botón editar»).
///
/// Igual que la bici en su lugar: cada dato sabe si cambió, se deshace por
/// separado y **sólo se escribe lo que cambió**, contra la versión que se
/// leyó. Un dato vacío se guarda como nulo: el correo tiene un índice único
/// por taller y un texto vacío chocaría con el de otro cliente.
class ClientDataDraft {
  ClientDataDraft(this.record)
      : _original = {
          for (final field in ClientDataField.values)
            field: record.valueOf(field),
        } {
    _values.addAll(_original);
  }

  final ClientRecord record;
  final Map<ClientDataField, String?> _original;
  final Map<ClientDataField, String?> _values = {};

  /// Los datos que también cambió otro mientras se editaba: queda lo de esta
  /// edición, para revisarlo antes de guardar de nuevo.
  final Set<ClientDataField> changedByOthers = {};

  String? value(ClientDataField field) => _values[field];

  String? original(ClientDataField field) => _original[field];

  void set(ClientDataField field, String? value) {
    final text = value?.trim();
    _values[field] = text == null || text.isEmpty ? null : text;
  }

  void revert(ClientDataField field) => _values[field] = _original[field];

  bool isChanged(ClientDataField field) =>
      _normalized(field, _values[field]) !=
      _normalized(field, _original[field]);

  List<ClientDataField> get changedFields => [
        for (final field in ClientDataField.values)
          if (isChanged(field)) field,
      ];

  int get changeCount => changedFields.length;

  /// Lo que no se puede guardar así, por dato.
  ///
  /// Sólo se juzga lo que esta edición cambió: un correo o un RUT inválido
  /// que ya venía guardado (hay uno en producción, 2026-10-03) no impide
  /// guardar el teléfono; se corrige cuando alguien lo edite.
  Map<ClientDataField, String> get problems {
    final problems = <ClientDataField, String>{};
    if (isChanged(ClientDataField.name) &&
        (_values[ClientDataField.name] ?? '').isEmpty) {
      problems[ClientDataField.name] = 'Escribe el nombre del cliente.';
    }
    final email = _values[ClientDataField.email];
    if (isChanged(ClientDataField.email) &&
        email != null &&
        !ChileanUtils.isValidEmail(email)) {
      problems[ClientDataField.email] =
          'Revisa el correo: debe ser como nombre@correo.cl.';
    }
    final rut = _values[ClientDataField.rut];
    if (isChanged(ClientDataField.rut) &&
        rut != null &&
        !ChileanUtils.isValidRut(rut)) {
      problems[ClientDataField.rut] =
          'Este RUT no es válido: revisa el número y el dígito verificador.';
    }
    return problems;
  }

  /// Las columnas que cambian y su valor tal como se guarda.
  ///
  /// El RUT y el teléfono chileno se guardan con su forma de siempre
  /// («12.345.678-9», «+56 9 8121 0019»); las notas conservan la línea de
  /// Zoho, que la hoja no muestra.
  Map<String, Object?> get changes => {
        for (final field in changedFields)
          field.column: _stored(field, _values[field]),
      };

  Object? _stored(ClientDataField field, String? value) {
    switch (field) {
      case ClientDataField.rut:
        return value == null ? null : ChileanUtils.formatRut(value);
      case ClientDataField.phone:
        return value == null ? null : ChileanUtils.formatPhone(value);
      case ClientDataField.notes:
        final zoho = record.zohoLine;
        if (zoho == null) return value;
        return value == null ? zoho : '$zoho\n$value';
      case ClientDataField.name:
      case ClientDataField.email:
      case ClientDataField.address:
      case ClientDataField.city:
      case ClientDataField.region:
        return value;
    }
  }

  /// Si escribir de otra forma lo mismo es un cambio: «12345678-5» y
  /// «12.345.678-5» son el mismo RUT.
  String? _normalized(ClientDataField field, String? value) {
    if (value == null) return null;
    return switch (field) {
      ClientDataField.rut => ChileanUtils.formatRut(value).toLowerCase(),
      ClientDataField.phone => ChileanUtils.formatPhone(value),
      ClientDataField.email => value.toLowerCase(),
      _ => value,
    };
  }

  /// Esta edición encima de [newer], la versión que guardó otro: los datos
  /// que esta edición no tocó toman lo nuevo; los que sí, quedan como se
  /// escribieron, y si otro también los cambió se marcan en
  /// [changedByOthers].
  ClientDataDraft rebasedOn(ClientRecord newer) {
    final next = ClientDataDraft(newer);
    for (final field in changedFields) {
      next._values[field] = _values[field];
      final theirs = _normalized(field, newer.valueOf(field));
      if (theirs != _normalized(field, _original[field]) &&
          theirs != _normalized(field, _values[field])) {
        next.changedByOthers.add(field);
      }
    }
    return next;
  }
}
