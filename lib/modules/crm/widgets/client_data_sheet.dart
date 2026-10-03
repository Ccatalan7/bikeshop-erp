import 'package:flutter/material.dart';

import '../../../shared/themes/vinabike_theme_roles.dart';
import '../../../shared/utils/chilean_utils.dart';
import '../../../shared/widgets/vb_searchable_select.dart';
import '../../../shared/widgets/vb_segmented.dart' show VbDensity;
import '../../bikeshop/widgets/bike_module_style.dart';
import '../services/client_data_draft.dart';

/// La hoja «Datos» del cliente: todos sus datos a la vista por sección, los
/// vacíos como «+ Agregar …», y la misma hoja se edita en su lugar (dueño,
/// 2026-10-03: «la primera cara visible del cliente deberían ser sus datos»).
///
/// No guarda nada: la página tiene el borrador, los campos y la barra de
/// guardar. En un ancho de escritorio es una hoja con una fila por sección;
/// en teléfono, una tarjeta por sección.
class ClientDataSheet extends StatelessWidget {
  const ClientDataSheet({
    super.key,
    required this.record,
    required this.draft,
    required this.controllers,
    required this.focusNodes,
    required this.problems,
    required this.busy,
    required this.onAdd,
    required this.onChanged,
    required this.onRegionChanged,
    required this.onUndo,
    this.onManageAccess,
  });

  final ClientRecord record;

  /// Nulo mientras se lee.
  final ClientDataDraft? draft;
  final Map<ClientDataField, TextEditingController> controllers;
  final Map<ClientDataField, FocusNode> focusNodes;

  /// Lo que no se puede guardar, junto a su dato.
  final Map<ClientDataField, String> problems;
  final bool busy;

  /// «+ Agregar teléfono»: edita la hoja con ese dato listo para escribir.
  final ValueChanged<ClientDataField> onAdd;
  final void Function(ClientDataField field, String value) onChanged;
  final ValueChanged<String?> onRegionChanged;
  final ValueChanged<ClientDataField> onUndo;

  /// «Gestionar acceso web», para quien puede administrar usuarios.
  final VoidCallback? onManageAccess;

  bool get _editing => draft != null;

  String? _value(ClientDataField field) =>
      draft == null ? record.valueOf(field) : draft!.value(field);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final phone = constraints.maxWidth < 600;
        final sections = _sections(context);
        if (phone) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _phoneTitle(context),
              for (final section in sections) ...[
                const SizedBox(height: 12),
                _phoneCard(context, section),
              ],
            ],
          );
        }
        return _wideSheet(context, sections, constraints.maxWidth);
      },
    );
  }

  // ── Lo que dice cada sección ────────────────────────────────────────────

  List<_Section> _sections(BuildContext context) {
    final phone = _value(ClientDataField.phone);
    final email = _value(ClientDataField.email);
    final rut = _value(ClientDataField.rut);
    final address = _value(ClientDataField.address);
    final notes = _value(ClientDataField.notes);
    return [
      _Section(
        number: 1,
        title: 'Contacto',
        status: phone == null
            ? ('Falta el teléfono', SheetStatusTone.warning)
            : email == null
                ? ('Sin correo', SheetStatusTone.neutral)
                : ('Completo', SheetStatusTone.success),
        fields: const [
          _Field(ClientDataField.name, hint: 'Nombre y apellido'),
          _Field(ClientDataField.phone,
              add: 'Agregar teléfono',
              hint: 'Ej. +56 9 1234 5678',
              keyboard: TextInputType.phone),
          _Field(ClientDataField.email,
              add: 'Agregar correo',
              hint: 'Ej. nombre@correo.cl',
              keyboard: TextInputType.emailAddress),
        ],
        note: phone == null
            ? 'Sin teléfono no se le puede avisar por WhatsApp que su bici '
                'está lista.'
            : null,
      ),
      _Section(
        number: 2,
        title: 'Para facturar',
        status: rut != null && address != null
            ? ('Completo', SheetStatusTone.success)
            : ('Faltan datos', SheetStatusTone.warning),
        fields: const [
          _Field(ClientDataField.rut,
              add: 'Agregar RUT', hint: 'Ej. 12.345.678-9'),
          _Field(ClientDataField.address,
              add: 'Agregar dirección', hint: 'Calle y número', span: 2),
          _Field(ClientDataField.city,
              add: 'Agregar ciudad', hint: 'Ciudad o comuna'),
          _Field(ClientDataField.region,
              add: 'Agregar región', hint: 'Elegir región'),
        ],
        note: 'Una factura pide RUT y dirección; una boleta no.',
      ),
      _Section(
        number: 3,
        title: 'Portal web',
        status: record.hasPortalAccess
            ? ('Con acceso', SheetStatusTone.success)
            : ('Sin acceso', SheetStatusTone.neutral),
        fields: [
          _Field.fixed(
            'Cuenta web',
            record.hasPortalAccess ? 'Con acceso' : 'Sin acceso',
            caption: 'Con acceso sigue sus trabajos y aprueba presupuestos '
                'desde el portal.',
          ),
        ],
        action: onManageAccess == null
            ? null
            : TextButton.icon(
                onPressed: onManageAccess,
                icon: const Icon(Icons.manage_accounts_outlined, size: 18),
                label: const Text('Gestionar acceso web'),
                style: TextButton.styleFrom(minimumSize: const Size(48, 44)),
              ),
      ),
      _Section(
        number: 4,
        title: 'Notas',
        status: notes == null
            ? ('Sin notas', SheetStatusTone.neutral)
            : ('Con notas', SheetStatusTone.neutral),
        fields: const [
          _Field(ClientDataField.notes,
              add: 'Agregar nota',
              hint: 'Lo que el taller debe saber de este cliente',
              span: 3,
              multiline: true),
        ],
      ),
      _Section(
        number: 5,
        title: 'Registro',
        status: ('Lo pone el sistema', SheetStatusTone.neutral),
        fields: [
          _Field.fixed('Cliente desde', bikeFullDate(record.createdAt)),
          if (record.importedFromZoho)
            const _Field.fixed('Origen', 'Importado de Zoho'),
          _Field.fixed('Estado', record.isActive ? 'Activo' : 'Inactivo'),
        ],
      ),
    ];
  }

  /// «1 de 8 datos · faltan el contacto y los de facturación».
  String _summary() {
    final filled =
        ClientDataField.values.where((field) => _value(field) != null).length;
    final phone = _value(ClientDataField.phone);
    final email = _value(ClientDataField.email);
    final contact =
        phone == null ? (email == null ? 'el contacto' : 'el teléfono') : null;
    final billing = _value(ClientDataField.rut) == null ||
            _value(ClientDataField.address) == null
        ? 'los de facturación'
        : null;
    final total = ClientDataField.values.length;
    final missing = [contact, billing].whereType<String>().toList();
    if (missing.isEmpty) return '$filled de $total datos';
    final verb = missing.length == 1 && contact != null ? 'falta' : 'faltan';
    return '$filled de $total datos · $verb ${missing.join(' y ')}';
  }

  // ── Escritorio ──────────────────────────────────────────────────────────

  Widget _wideSheet(
      BuildContext context, List<_Section> sections, double width) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final labelWidth = width >= 860 ? 230.0 : 190.0;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _editing
              ? theme.colorScheme.primary
              : theme.colorScheme.outlineVariant,
          width: _editing ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: _title(context),
          ),
          for (final section in sections)
            Container(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: roles.hairline)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: labelWidth,
                    child: _sectionLabel(context, section, stacked: true),
                  ),
                  const SizedBox(width: 20),
                  Expanded(child: _sectionBody(context, section)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _title(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            if (_editing) ...[
              Icon(Icons.edit_outlined,
                  size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Semantics(
                header: true,
                child: Text(
                  _editing ? 'Editando los datos' : 'Datos del cliente',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: _editing
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurface,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          _editing
              ? 'Cambia lo que necesites y guarda abajo. Lo del sistema no se '
                  'edita.'
              : _summary(),
          style: TextStyle(
              fontSize: 13.5, color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _sectionLabel(BuildContext context, _Section section,
      {required bool stacked}) {
    final theme = Theme.of(context);
    final badge = Container(
      width: 26,
      height: 26,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: theme.colorScheme.primary,
        shape: BoxShape.circle,
      ),
      child: Text(
        '${section.number}',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: theme.colorScheme.onPrimary,
        ),
      ),
    );
    final title = Semantics(
      header: true,
      child: Text(
        section.title,
        style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
      ),
    );
    final chip =
        SheetStatusChip(label: section.status.$1, tone: section.status.$2);
    if (!stacked) {
      return Row(
        children: [
          badge,
          const SizedBox(width: 12),
          Expanded(child: title),
          const SizedBox(width: 8),
          chip,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        badge,
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: title,
              ),
              const SizedBox(height: 6),
              chip,
            ],
          ),
        ),
      ],
    );
  }

  Widget _sectionBody(BuildContext context, _Section section) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 24.0;
        final columns = (constraints.maxWidth / 190).floor().clamp(1, 3);
        final cell = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: gap,
              runSpacing: 16,
              children: [
                for (final field in section.fields)
                  SizedBox(
                    width: field.span >= columns
                        ? constraints.maxWidth
                        : cell * field.span + gap * (field.span - 1),
                    child: _fieldCell(context, field),
                  ),
              ],
            ),
            if (section.note != null) ...[
              const SizedBox(height: 12),
              _note(context, section.note!),
            ],
            if (section.action != null) ...[
              const SizedBox(height: 6),
              Align(alignment: Alignment.centerLeft, child: section.action),
            ],
          ],
        );
      },
    );
  }

  Widget _note(BuildContext context, String note) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(Icons.info_outline,
              size: 16, color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            note,
            style: TextStyle(
                fontSize: 13, color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }

  // ── Teléfono ────────────────────────────────────────────────────────────

  Widget _phoneTitle(BuildContext context) {
    final theme = Theme.of(context);
    if (!_editing) {
      return Text(
        _summary(),
        style: TextStyle(
            fontSize: 13.5, color: theme.colorScheme.onSurfaceVariant),
      );
    }
    return Row(
      children: [
        Icon(Icons.edit_outlined, size: 18, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Semantics(
            header: true,
            child: Text(
              'Editando los datos',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _phoneCard(BuildContext context, _Section section) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _editing && section.editable
              ? theme.colorScheme.primary
              : theme.colorScheme.outlineVariant,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _sectionLabel(context, section, stacked: false),
            const SizedBox(height: 14),
            for (final field in section.fields) ...[
              _fieldCell(context, field),
              const SizedBox(height: 14),
            ],
            if (section.note != null) _note(context, section.note!),
            if (section.action != null)
              Align(alignment: Alignment.centerLeft, child: section.action),
          ],
        ),
      ),
    );
  }

  // ── Un dato ─────────────────────────────────────────────────────────────

  Widget _fieldCell(BuildContext context, _Field field) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final label = Text(
      field.label,
      style: TextStyle(fontSize: 12.5, color: roles.faintForeground),
    );
    final data = field.field;
    if (data == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          label,
          const SizedBox(height: 5),
          Text(
            field.fixedValue ?? '—',
            style: TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (field.caption != null) ...[
            const SizedBox(height: 4),
            Text(
              field.caption!,
              style: TextStyle(fontSize: 12.5, color: roles.faintForeground),
            ),
          ],
        ],
      );
    }
    if (_editing) return _editCell(context, field, data);

    final value = record.valueOf(data);
    final shown = value == null
        ? null
        : data == ClientDataField.phone
            ? ChileanUtils.formatPhone(value)
            : value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        label,
        const SizedBox(height: 5),
        if (shown != null)
          SelectableText(
            shown,
            style: TextStyle(
              fontSize: 15.5,
              fontWeight: data == ClientDataField.notes
                  ? FontWeight.w500
                  : FontWeight.w600,
              height: 1.35,
              color: theme.colorScheme.onSurface,
            ),
          )
        else
          _AddChip(
            label: field.add ?? 'Agregar ${data.label.toLowerCase()}',
            onTap: busy ? null : () => onAdd(data),
          ),
      ],
    );
  }

  Widget _editCell(BuildContext context, _Field field, ClientDataField data) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final touch =
        MediaQuery.sizeOf(context).width < 900; // el teléfono y la tableta
    final draft = this.draft!;
    final problem = problems[data];
    final control = data == ClientDataField.region
        ? _regionSelect(context, draft, touch: touch)
        : Semantics(
            label: data.label,
            textField: true,
            child: TextField(
              key: ValueKey('client-data-${data.column}'),
              controller: controllers[data],
              focusNode: focusNodes[data],
              enabled: !busy,
              keyboardType:
                  field.multiline ? TextInputType.multiline : field.keyboard,
              textCapitalization: data == ClientDataField.name ||
                      data == ClientDataField.city ||
                      data == ClientDataField.address
                  ? TextCapitalization.words
                  : (field.multiline
                      ? TextCapitalization.sentences
                      : TextCapitalization.none),
              autocorrect: !(data == ClientDataField.email ||
                  data == ClientDataField.rut ||
                  data == ClientDataField.phone),
              minLines: field.multiline ? 3 : 1,
              maxLines: field.multiline ? 8 : 1,
              onChanged: (value) => onChanged(data, value),
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w500, height: 1.4),
              decoration: _decoration(context,
                  hint: field.hint, error: problem, touch: touch),
            ),
          );

    Widget? caption;
    if (draft.isChanged(data)) {
      final before = draft.original(data);
      final byOthers = draft.changedByOthers.contains(data);
      final color =
          byOthers ? roles.warning.onContainer : theme.colorScheme.primary;
      caption = Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              byOthers
                  ? 'Otro guardó: ${before ?? 'vacío'}'
                  : before == null
                      ? 'Nuevo'
                      : 'Antes: ${before.replaceAll('\n', ' ')}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w600, color: color),
            ),
          ),
          IconButton(
            tooltip: 'Deshacer cambio de ${data.label}',
            onPressed: busy ? null : () => onUndo(data),
            icon: const Icon(Icons.undo),
            iconSize: 16,
            padding: EdgeInsets.zero,
            constraints: BoxConstraints.tightFor(
              width: touch ? 44 : 24,
              height: touch ? 44 : 24,
            ),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          data.label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 6),
        control,
        // En escritorio la línea del cambio existe siempre: marcar un cambio
        // no mueve lo de abajo.
        if (!touch)
          SizedBox(height: 24, child: caption)
        else if (caption != null)
          SizedBox(height: 44, child: caption),
      ],
    );
  }

  Widget _regionSelect(BuildContext context, ClientDataDraft draft,
      {required bool touch}) {
    final current = draft.value(ClientDataField.region);
    final regions = ChileanUtils.getChileanRegions();
    return VbSearchableSelect<String>(
      value: current,
      options: [
        if (current != null && !regions.contains(current))
          VbSearchableSelectOption(value: current, label: current),
        for (final region in regions)
          VbSearchableSelectOption(value: region, label: region),
      ],
      onChanged: busy ? null : onRegionChanged,
      sheetTitle: 'Región',
      label: 'Región',
      showLabel: false,
      placeholder: 'Elegir región',
      semanticLabel: 'Región',
      searchHint: 'Buscar región…',
      allowClear: true,
      clearLabel: 'Sin región',
      errorText: problems[ClientDataField.region],
      density: VbDensity.comfortable,
    );
  }

  InputDecoration _decoration(
    BuildContext context, {
    String? hint,
    String? error,
    required bool touch,
  }) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    OutlineInputBorder border(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: color, width: width),
        );
    return InputDecoration(
      isDense: true,
      hintText: hint,
      // Un ejemplo, no un dato: más tenue que lo escrito.
      hintStyle:
          theme.textTheme.bodyMedium?.copyWith(color: roles.faintForeground),
      errorText: error,
      errorMaxLines: 3,
      filled: true,
      fillColor: theme.colorScheme.surface,
      contentPadding:
          EdgeInsets.symmetric(horizontal: 12, vertical: touch ? 18 : 13),
      border: border(theme.colorScheme.outline),
      enabledBorder: border(theme.colorScheme.outline),
      focusedBorder: border(roles.focusRing, 1.5),
      disabledBorder: border(theme.colorScheme.outlineVariant),
      errorBorder: border(theme.colorScheme.error),
      focusedErrorBorder: border(theme.colorScheme.error, 1.5),
    );
  }
}

class _Section {
  const _Section({
    required this.number,
    required this.title,
    required this.status,
    required this.fields,
    this.note,
    this.action,
  });

  final int number;
  final String title;
  final (String, SheetStatusTone) status;
  final List<_Field> fields;
  final String? note;
  final Widget? action;

  bool get editable => fields.any((field) => field.field != null);
}

class _Field {
  const _Field(
    this.field, {
    this.add,
    this.hint,
    this.span = 1,
    this.keyboard,
    this.multiline = false,
  })  : fixedLabel = null,
        fixedValue = null,
        caption = null;

  /// Un dato que pone el sistema: se lee, no se edita.
  const _Field.fixed(String label, String value, {this.caption})
      : field = null,
        fixedLabel = label,
        fixedValue = value,
        add = null,
        hint = null,
        span = 1,
        keyboard = null,
        multiline = false;

  final ClientDataField? field;
  final String? fixedLabel;
  final String? fixedValue;
  final String? caption;
  final String? add;
  final String? hint;
  final int span;
  final TextInputType? keyboard;
  final bool multiline;

  String get label => field?.label ?? fixedLabel ?? '';
}

/// «+ Agregar teléfono»: un dato vacío, que se completa ahí mismo.
class _AddChip extends StatelessWidget {
  const _AddChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final touch = MediaQuery.sizeOf(context).width < 900;
    return Material(
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: touch ? 44 : 32),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add, size: 16, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
