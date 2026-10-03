import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../themes/vinabike_theme_roles.dart';
import '../utils/responsive_breakpoints.dart';
import 'vb_anchored_popover.dart';
import 'vb_segmented.dart' show VbDensity;
import 'vb_short_select.dart';

/// **S-06 · `VbSearchableSelect<T>`** — the searchable selector of the shared
/// kit, and the canonical owner of «elegir uno entre muchos».
///
/// `VbShortSelect` (S-05) publishes the ceiling and names its successor: *«Hasta
/// ~7 opciones… El menú **no** es scrollable: si necesita scroll, era el otro
/// componente.»* A tenant category tree of 133 nodes and a brand table of 146
/// rows are that other component. Until now every screen wrote its own, and the
/// OCR review's local copy is what put a four-level slash path inside a 150 px
/// closed field, where it rendered as `Componentes / Dirección / …`.
///
/// ### The closed field says the short name
///
/// The operator picked `Tee`. The field says `Tee`. A path is how the catalog
/// is *organised*, not what the thing is called, and it only earns space where
/// two options genuinely share a name — so the breadcrumb appears in the result
/// row and in the helper line under an ambiguous choice, never in the closed
/// field. This is the correction the owner asked for by name.
///
/// ### Geometry
///
/// Field, popover and option anatomy are S-05's, reused rather than re-read:
/// `height 34` (48 touch target), `padding 0 9 0 11`, `radius 8`, popover
/// `padding 5 · radius 10`, option `height 30 · padding 0 9`. Values are bound
/// to theme roles; no literal hex enters this file.
///
/// ### Compact hosts get a sheet
///
/// Below `ResponsiveBreakpoints.desktopMin` the list is a bottom sheet with its
/// own search field, per `O-05`. A 200 px popover on a phone is the
/// anti-pattern the guide names.
class VbSearchableSelectOption<T> {
  const VbSearchableSelectOption({
    required this.value,
    required this.label,
    this.context,
    this.searchText,
  });

  final T value;

  /// What the operator calls it. Shown in the closed field and as the first
  /// line of a result.
  final String label;

  /// Where it lives, when that disambiguates. Shown only inside results.
  final String? context;

  /// Extra words that should match a query without being displayed.
  final String? searchText;

  String get _haystack => <String?>[label, context, searchText]
      .whereType<String>()
      .join(' ')
      .toLowerCase();
}

class VbSearchableSelect<T> extends StatefulWidget {
  const VbSearchableSelect({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    required this.sheetTitle,
    this.label,
    this.placeholder,
    this.semanticLabel,
    this.helperText,
    this.errorText,
    this.searchHint = 'Buscar…',
    this.emptyLabel = 'Nada coincide',
    this.showLabel = true,
    this.allowClear = false,
    this.clearLabel = 'Sin especificar',
    this.useTouchLayout,
    this.density,
    this.showSearch = true,
    this.onCreate,
    this.createLabel,
  });

  final T? value;
  final List<VbSearchableSelectOption<T>> options;
  final ValueChanged<T?>? onChanged;

  /// Title of the compact bottom sheet. Required for the same reason S-05
  /// requires it: a title written «cuando toque» is empty on the first phone.
  final String sheetTitle;

  final String? label;
  final String? placeholder;
  final String? semanticLabel;
  final String? helperText;
  final String? errorText;
  final String searchHint;
  final String emptyLabel;
  final bool showLabel;

  /// Offers a context-aware empty choice at the top of the list.
  final bool allowClear;

  /// Visible wording for the empty choice. The default preserves the generic
  /// S-06 vocabulary; domain selectors should name what is being omitted.
  final String clearLabel;

  /// An embedded host may be narrower than the application MediaQuery.
  /// Null preserves the ordinary full-route responsive behavior.
  final bool? useTouchLayout;

  /// [VbDensity.comfortable] draws the closed field at the comfortable
  /// control height (38) with body-size text, for a page that reads at that
  /// size — the bike's technical sheet edited in place (2026-10-02). Null
  /// keeps the compact field every other screen uses.
  final VbDensity? density;

  /// False drops the search field for a short, known list, where typing is
  /// slower than looking (two to seven values). Arrow keys and Enter still
  /// pick from the list.
  final bool showSearch;

  /// Offers «Agregar "…"» when the search text names nothing in the list (a
  /// bike brand or model the catalog does not have yet, 2026-10-02). It
  /// receives the typed text, trimmed; the host creates the value and then
  /// selects it. Null keeps the list closed to new values.
  final ValueChanged<String>? onCreate;

  /// Wording of that row. By default «Agregar "…"».
  final String Function(String query)? createLabel;

  /// Height of one result row on desktop.
  static const double optionHeight = 34;

  /// Tallest the desktop popover may grow before it scrolls.
  static const double maxPopoverHeight = 320;

  @override
  State<VbSearchableSelect<T>> createState() => _VbSearchableSelectState<T>();
}

class _VbSearchableSelectState<T> extends State<VbSearchableSelect<T>> {
  final GlobalKey _anchor = GlobalKey();
  bool _open = false;

  static const double _fieldRadius = 8;

  bool get _enabled => widget.onChanged != null;

  VbSearchableSelectOption<T>? get _selected {
    for (final option in widget.options) {
      if (option.value == widget.value) return option;
    }
    return null;
  }

  bool _isTouchHost(BuildContext context) =>
      widget.useTouchLayout ??
      (MediaQuery.sizeOf(context).width < ResponsiveBreakpoints.desktopMin);

  bool get _comfortable => widget.density == VbDensity.comfortable;

  Future<void> _open_() async {
    // Un catálogo vacío se abre igual si se puede agregar: es la única forma
    // de escribir su primera opción (revisión de Codex, 2026-10-02).
    if (!_enabled || (widget.options.isEmpty && widget.onCreate == null)) {
      return;
    }
    final useSheet = _isTouchHost(context);
    final pending = useSheet ? _showSheet() : _showPopover();
    setState(() => _open = true);
    final result = await pending;
    if (!mounted) return;
    setState(() => _open = false);
    // A cancelled popover and a deliberate empty choice must stay
    // distinguishable, so the answer travels wrapped.
    if (result == null) return;
    final created = result.created;
    if (created != null) {
      widget.onCreate?.call(created);
    } else {
      widget.onChanged?.call(result.value);
    }
  }

  String Function(String)? get _createLabel => widget.onCreate == null
      ? null
      : (widget.createLabel ?? (query) => 'Agregar «$query»');

  Future<_VbSearchableChoice<T>?> _showPopover() {
    return showVbAnchoredPopover<_VbSearchableChoice<T>>(
      anchorContext: _anchor.currentContext ?? context,
      minWidth: 260,
      builder: (_) => _VbSearchableMenu<T>(
        options: widget.options,
        value: widget.value,
        searchHint: widget.searchHint,
        emptyLabel: widget.emptyLabel,
        allowClear: widget.allowClear,
        clearLabel: widget.clearLabel,
        showSearch: widget.showSearch,
        comfortable: _comfortable,
        createLabel: _createLabel,
      ),
    );
  }

  Future<_VbSearchableChoice<T>?> _showSheet() {
    final media = MediaQuery.of(context);
    return showModalBottomSheet<_VbSearchableChoice<T>>(
      context: context,
      backgroundColor: Colors.transparent,
      elevation: 0,
      isScrollControlled: true,
      constraints: BoxConstraints(maxHeight: media.size.height * 0.75),
      builder: (_) => _VbSearchableSheet<T>(
        title: widget.sheetTitle,
        options: widget.options,
        value: widget.value,
        searchHint: widget.searchHint,
        emptyLabel: widget.emptyLabel,
        allowClear: widget.allowClear,
        clearLabel: widget.clearLabel,
        showSearch: widget.showSearch,
        createLabel: _createLabel,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final roles = VinabikeThemeRoles.of(context);
    final selected = _selected;
    final hasError = (widget.errorText ?? '').trim().isNotEmpty;

    final Color background =
        _enabled ? scheme.surface : scheme.surfaceContainerLow;
    final Color border = hasError
        ? roles.danger.border
        : _open
            ? roles.focusRing
            : (_enabled ? scheme.outline : scheme.outlineVariant);
    final Color foreground = !_enabled
        ? roles.disabledForeground
        : (selected == null ? scheme.onSurfaceVariant : scheme.onSurface);

    final double box = _comfortable
        ? VbDensity.comfortable.controlHeight
        : VbShortSelect.fieldHeight;
    final double target =
        _isTouchHost(context) ? VbShortSelect.touchTargetHeight : box;
    final valueStyle =
        _comfortable ? theme.textTheme.bodyMedium : theme.textTheme.bodySmall;

    final field = Semantics(
      button: true,
      enabled: _enabled,
      expanded: _open,
      label: widget.semanticLabel ?? widget.label,
      // The accessible value carries the disambiguating branch even though the
      // visible field deliberately shows only the short name.
      value: <String?>[
        selected?.label ?? widget.placeholder ?? '',
        selected?.context,
      ].whereType<String>().where((part) => part.isNotEmpty).join(', '),
      excludeSemantics: true,
      child: _OpenIntentShortcuts(
        enabled: _enabled,
        onOpen: _open_,
        child: InkWell(
          key: _anchor,
          onTap: _enabled ? _open_ : null,
          borderRadius: BorderRadius.circular(_fieldRadius),
          child: SizedBox(
            height: target,
            child: Center(
              child: Container(
                height: box,
                padding:
                    EdgeInsets.only(left: _comfortable ? 12 : 11, right: 9),
                decoration: BoxDecoration(
                  color: background,
                  borderRadius: BorderRadius.circular(_fieldRadius),
                  border: Border.all(color: border),
                  boxShadow: _open
                      ? <BoxShadow>[
                          BoxShadow(
                            color: roles.focusRing.withValues(alpha: 0.12),
                            spreadRadius: 3,
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        // The short name, never the path. A closed selector is
                        // an answer, not a map.
                        selected?.label ?? widget.placeholder ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: valueStyle?.copyWith(
                          color: foreground,
                          fontWeight: selected == null
                              ? FontWeight.w400
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.unfold_more,
                      size: _comfortable ? 16 : 14,
                      color: _enabled
                          ? scheme.onSurfaceVariant
                          : roles.disabledForeground,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final helper = widget.errorText ?? widget.helperText;
    if (!widget.showLabel && helper == null) return field;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.showLabel && (widget.label ?? '').isNotEmpty) ...[
          Text(
            widget.label!,
            style: (_comfortable
                    ? theme.textTheme.labelMedium
                    : theme.textTheme.labelSmall)
                ?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(height: _comfortable ? 6 : 5),
        ],
        field,
        if (helper != null) ...[
          const SizedBox(height: 4),
          Text(
            helper,
            style: theme.textTheme.labelSmall?.copyWith(
              color: hasError ? roles.danger.accent : scheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

class _VbSearchableChoice<T> {
  const _VbSearchableChoice(this.value, {this.created});

  final T? value;

  /// The typed text when the operator chose «Agregar».
  final String? created;
}

/// The text «Agregar» would create: what was typed, unless it is empty or
/// already names an option.
String? _creatable<T>(
  List<VbSearchableSelectOption<T>> options,
  String query,
) {
  final text = query.trim();
  if (text.isEmpty) return null;
  final lower = text.toLowerCase();
  if (options.any((option) => option.label.trim().toLowerCase() == lower)) {
    return null;
  }
  return text;
}

/// Shared filtering so the popover and the sheet cannot drift apart.
List<VbSearchableSelectOption<T>> _filter<T>(
  List<VbSearchableSelectOption<T>> options,
  String query,
) {
  final terms = query
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((term) => term.isNotEmpty)
      .toList(growable: false);
  if (terms.isEmpty) return options;
  return options
      .where((option) => terms.every(option._haystack.contains))
      .toList(growable: false);
}

class _VbSearchableMenu<T> extends StatefulWidget {
  const _VbSearchableMenu({
    required this.options,
    required this.value,
    required this.searchHint,
    required this.emptyLabel,
    required this.allowClear,
    this.clearLabel = 'Sin especificar',
    this.showSearch = true,
    this.comfortable = false,
    this.createLabel,
  });

  final List<VbSearchableSelectOption<T>> options;
  final T? value;
  final String searchHint;
  final String emptyLabel;
  final bool allowClear;
  final String clearLabel;
  final bool showSearch;
  final bool comfortable;
  final String Function(String query)? createLabel;

  @override
  State<_VbSearchableMenu<T>> createState() => _VbSearchableMenuState<T>();
}

class _VbSearchableMenuState<T> extends State<_VbSearchableMenu<T>> {
  final TextEditingController _query = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  final ScrollController _scroll = ScrollController();
  late int _highlighted = _initialHighlight();

  /// Without a search field the list opens on the current value, so the
  /// arrows move from what is chosen.
  int _initialHighlight() {
    if (widget.showSearch) return 0;
    final index =
        widget.options.indexWhere((option) => option.value == widget.value);
    return index < 0 ? 0 : index;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _query.dispose();
    _searchFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  List<VbSearchableSelectOption<T>> get _results =>
      _filter(widget.options, _query.text);

  String? get _creatableText => widget.createLabel == null
      ? null
      : _creatable(widget.options, _query.text);

  void _move(int delta) {
    final count = _results.length + (_creatableText == null ? 0 : 1);
    if (count == 0) return;
    setState(() {
      _highlighted = (_highlighted + delta).clamp(0, count - 1);
    });
    final target = _highlighted * VbSearchableSelect.optionHeight;
    if (_scroll.hasClients) {
      _scroll.animateTo(
        target.clamp(0, _scroll.position.maxScrollExtent).toDouble(),
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOut,
      );
    }
  }

  void _commit() {
    final results = _results;
    if (_highlighted < results.length) {
      Navigator.of(context)
          .pop(_VbSearchableChoice<T>(results[_highlighted].value));
      return;
    }
    final created = _creatableText;
    if (created != null) {
      Navigator.of(context).pop(_VbSearchableChoice<T>(null, created: created));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final results = _results;
    final created = _creatableText;
    final clearRows = widget.allowClear ? 1 : 0;

    return VbPopoverSurface(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxHeight: VbSearchableSelect.maxPopoverHeight,
          maxWidth: 420,
        ),
        child: CallbackShortcuts(
          bindings: <ShortcutActivator, VoidCallback>{
            const SingleActivator(LogicalKeyboardKey.arrowDown): () => _move(1),
            const SingleActivator(LogicalKeyboardKey.arrowUp): () => _move(-1),
            const SingleActivator(LogicalKeyboardKey.enter): _commit,
            const SingleActivator(LogicalKeyboardKey.numpadEnter): _commit,
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Sin campo de búsqueda el foco va a la lista, para que las
              // flechas y Enter sigan eligiendo.
              if (!widget.showSearch)
                Focus(focusNode: _searchFocus, child: const SizedBox.shrink())
              else
                Padding(
                  padding: const EdgeInsets.fromLTRB(5, 5, 5, 0),
                  child: TextField(
                    controller: _query,
                    focusNode: _searchFocus,
                    autofocus: true,
                    style: theme.textTheme.bodySmall,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: widget.searchHint,
                      prefixIcon: const Icon(Icons.search, size: 15),
                      prefixIconConstraints:
                          const BoxConstraints(minWidth: 30, minHeight: 30),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 8),
                    ),
                    onChanged: (_) => setState(() => _highlighted = 0),
                  ),
                ),
              Flexible(
                child: results.isEmpty && created == null
                    ? Padding(
                        padding: const EdgeInsets.all(14),
                        child: Text(
                          widget.emptyLabel,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.all(5),
                        shrinkWrap: true,
                        itemCount: results.length +
                            clearRows +
                            (created == null ? 0 : 1),
                        itemBuilder: (context, index) {
                          if (created != null &&
                              index == results.length + clearRows) {
                            return _OptionRow(
                              label: widget.createLabel!(created),
                              context: null,
                              icon: Icons.add,
                              selected: false,
                              highlighted: _highlighted == results.length,
                              comfortable: widget.comfortable,
                              onTap: () => Navigator.of(context).pop(
                                  _VbSearchableChoice<T>(null,
                                      created: created)),
                            );
                          }
                          if (widget.allowClear && index == 0) {
                            return _OptionRow(
                              label: widget.clearLabel,
                              context: null,
                              selected: widget.value == null,
                              highlighted: false,
                              comfortable: widget.comfortable,
                              onTap: () => Navigator.of(context)
                                  .pop(const _VbSearchableChoice<Never>(null)),
                            );
                          }
                          final option =
                              results[index - (widget.allowClear ? 1 : 0)];
                          return _OptionRow(
                            label: option.label,
                            context: option.context,
                            selected: option.value == widget.value,
                            highlighted: index - (widget.allowClear ? 1 : 0) ==
                                _highlighted,
                            comfortable: widget.comfortable,
                            onTap: () => Navigator.of(context)
                                .pop(_VbSearchableChoice<T>(option.value)),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VbSearchableSheet<T> extends StatefulWidget {
  const _VbSearchableSheet({
    required this.title,
    required this.options,
    required this.value,
    required this.searchHint,
    required this.emptyLabel,
    required this.allowClear,
    this.clearLabel = 'Sin especificar',
    this.showSearch = true,
    this.createLabel,
  });

  final String title;
  final List<VbSearchableSelectOption<T>> options;
  final T? value;
  final String searchHint;
  final String emptyLabel;
  final bool allowClear;
  final String clearLabel;
  final bool showSearch;
  final String Function(String query)? createLabel;

  @override
  State<_VbSearchableSheet<T>> createState() => _VbSearchableSheetState<T>();
}

class _VbSearchableSheetState<T> extends State<_VbSearchableSheet<T>> {
  final TextEditingController _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final results = _filter(widget.options, _query.text);
    final created = widget.createLabel == null
        ? null
        : _creatable(widget.options, _query.text);
    final clearRows = widget.allowClear ? 1 : 0;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Material(
        color: scheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 34,
                height: 4,
                decoration: BoxDecoration(
                  color: scheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.title,
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Cerrar',
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              if (widget.showSearch)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    controller: _query,
                    decoration: InputDecoration(
                      hintText: widget.searchHint,
                      prefixIcon: const Icon(Icons.search),
                      isDense: true,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              const SizedBox(height: 8),
              Flexible(
                child: results.isEmpty && created == null
                    ? Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          widget.emptyLabel,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: results.length +
                            clearRows +
                            (created == null ? 0 : 1),
                        separatorBuilder: (_, __) => Divider(
                          height: 1,
                          color: theme.dividerColor,
                        ),
                        itemBuilder: (context, index) {
                          if (created != null &&
                              index == results.length + clearRows) {
                            return ListTile(
                              minTileHeight: 48,
                              leading: const Icon(Icons.add),
                              title: Text(widget.createLabel!(created)),
                              onTap: () => Navigator.of(context).pop(
                                  _VbSearchableChoice<T>(null,
                                      created: created)),
                            );
                          }
                          if (widget.allowClear && index == 0) {
                            return ListTile(
                              minTileHeight: 48,
                              title: Text(widget.clearLabel),
                              selected: widget.value == null,
                              onTap: () => Navigator.of(context)
                                  .pop(const _VbSearchableChoice<Never>(null)),
                            );
                          }
                          final option =
                              results[index - (widget.allowClear ? 1 : 0)];
                          return ListTile(
                            minTileHeight: 48,
                            title: Text(option.label),
                            subtitle: option.context == null
                                ? null
                                : Text(option.context!),
                            selected: option.value == widget.value,
                            trailing: option.value == widget.value
                                ? const Icon(Icons.check, size: 18)
                                : null,
                            onTap: () => Navigator.of(context)
                                .pop(_VbSearchableChoice<T>(option.value)),
                          );
                        },
                      ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.label,
    required this.context,
    required this.selected,
    required this.highlighted,
    required this.onTap,
    this.comfortable = false,
    this.icon,
  });

  final String label;
  // ignore: avoid_field_initializers_in_const_classes
  final String? context;
  final bool selected;
  final bool highlighted;
  final VoidCallback onTap;
  final bool comfortable;

  /// Leads the row: «Agregar» carries a plus.
  final IconData? icon;

  @override
  Widget build(BuildContext buildContext) {
    final theme = Theme.of(buildContext);
    final scheme = theme.colorScheme;
    final roles = VinabikeThemeRoles.of(buildContext);
    final active = selected || highlighted;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        constraints: const BoxConstraints(
          minHeight: VbSearchableSelect.optionHeight,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: active ? roles.selectionContainer : null,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected ? roles.info.border : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: comfortable ? 18 : 15, color: roles.focusRing),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: (comfortable
                            ? theme.textTheme.bodyMedium
                            : theme.textTheme.bodySmall)
                        ?.copyWith(
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                  // The path earns its space here, where two options can share
                  // a name — and only here.
                  if (context != null && context!.isNotEmpty)
                    Text(
                      context!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            if (selected) Icon(Icons.check, size: 14, color: roles.focusRing),
          ],
        ),
      ),
    );
  }
}

class _OpenIntentShortcuts extends StatelessWidget {
  const _OpenIntentShortcuts({
    required this.enabled,
    required this.onOpen,
    required this.child,
  });

  final bool enabled;
  final VoidCallback onOpen;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.enter): onOpen,
        const SingleActivator(LogicalKeyboardKey.space): onOpen,
        const SingleActivator(LogicalKeyboardKey.arrowDown): onOpen,
      },
      child: Focus(child: child),
    );
  }
}

/// Elección directa de UNA opción con la misma anatomía S-06 del campo:
/// reutiliza el menú O-02 de escritorio y la hoja O-05 táctil del propio
/// owner, sin campo persistente. Para comandos del tipo «Reasignar a…».
Future<T?> showVbSearchableOptionPicker<T>({
  required BuildContext anchorContext,
  required String title,
  required List<VbSearchableSelectOption<T>> options,
  String searchHint = 'Buscar…',
  String emptyLabel = 'Nada coincide',
}) async {
  final touch =
      MediaQuery.sizeOf(anchorContext).width < ResponsiveBreakpoints.desktopMin;
  final _VbSearchableChoice<T>? choice;
  if (touch) {
    final media = MediaQuery.of(anchorContext);
    choice = await showModalBottomSheet<_VbSearchableChoice<T>>(
      context: anchorContext,
      backgroundColor: Colors.transparent,
      elevation: 0,
      isScrollControlled: true,
      constraints: BoxConstraints(maxHeight: media.size.height * 0.75),
      builder: (_) => _VbSearchableSheet<T>(
        title: title,
        options: options,
        value: null,
        searchHint: searchHint,
        emptyLabel: emptyLabel,
        allowClear: false,
      ),
    );
  } else {
    choice = await showVbAnchoredPopover<_VbSearchableChoice<T>>(
      anchorContext: anchorContext,
      minWidth: 260,
      barrierLabel: 'Cerrar $title',
      builder: (_) => _VbSearchableMenu<T>(
        options: options,
        value: null,
        searchHint: searchHint,
        emptyLabel: emptyLabel,
        allowClear: false,
      ),
    );
  }
  return choice?.value;
}
