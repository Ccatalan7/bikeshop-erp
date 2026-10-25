import 'dart:async';

import 'package:flutter/material.dart';

import '../../../shared/themes/vinabike_theme_roles.dart';
import '../../../shared/widgets/vb_button.dart';
import '../../../shared/widgets/vb_segmented.dart';
import '../../../shared/widgets/vb_status_badge.dart';
import 'catalog_search_controller.dart';
import 'catalog_search_models.dart';
import 'catalog_ui_parts.dart';

/// «Búsquedas» (2026-10-24, owner: «has la 2 nomás»): what visitors search
/// in vinabike.cl and do not find, beside the words the search understands.
/// A search without results is answered with «Es una palabra de…» (its words
/// join a group: whoever writes one finds what the others find) or
/// «Ignorar» (not sold here, or written wrong). The groups are the shared
/// vocabulary of every store and the store's own words, which are the only
/// ones that can be taken out.
class CatalogSearchView extends StatefulWidget {
  const CatalogSearchView({super.key, required this.controller});

  final CatalogSearchController controller;

  @override
  State<CatalogSearchView> createState() => _CatalogSearchViewState();
}

enum _Pane { misses, words }

class _CatalogSearchViewState extends State<CatalogSearchView> {
  CatalogSearchMissState _state = CatalogSearchMissState.open;
  _Pane _pane = _Pane.misses;
  final _filter = TextEditingController();

  CatalogSearchController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    _filter.addListener(() => setState(() {}));
    if (!_c.loaded && !_c.loading) unawaited(_c.load());
  }

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  Future<void> _answer(CatalogSearchMiss miss) async {
    final choice = await showCatalogSearchWordPicker(
      context,
      controller: _c,
      miss: miss,
    );
    if (choice == null || !mounted) return;
    try {
      final result = await _c.addWords(
        concept: choice.concept,
        words: choice.words,
        miss: miss,
        label: choice.label,
      );
      if (mounted) {
        showCatalogMessage(context, result.describe(search: miss.typed));
      }
    } catch (error) {
      if (mounted) showCatalogMessage(context, catalogErrorMessage(error));
    }
  }

  Future<void> _ignore(CatalogSearchMiss miss, {required bool ignored}) async {
    try {
      await _c.setIgnored(miss, ignored: ignored);
      if (!mounted) return;
      showCatalogMessage(
        context,
        ignored
            ? '«${miss.typed}» quedó en Ignoradas.'
            : '«${miss.typed}» volvió a Por revisar.',
        action: ignored
            ? SnackBarAction(
                label: 'Deshacer',
                onPressed: () => _ignore(miss, ignored: false),
              )
            : null,
      );
    } catch (error) {
      if (mounted) showCatalogMessage(context, catalogErrorMessage(error));
    }
  }

  Future<void> _addTo(CatalogSearchConcept? concept) async {
    final words = await showCatalogSearchWordsEditor(context, concept: concept);
    if (words == null || !mounted) return;
    try {
      final result = await _c.addWords(
        concept: words.concept,
        words: words.words,
        label: words.label,
      );
      if (mounted) showCatalogMessage(context, result.describe());
    } catch (error) {
      if (mounted) showCatalogMessage(context, catalogErrorMessage(error));
    }
  }

  Future<void> _remove(CatalogSearchConcept concept, String word) async {
    try {
      final removed = await _c.removeWord(concept: concept.concept, word: word);
      if (!mounted) return;
      showCatalogMessage(
        context,
        removed
            ? '«$word» salió de ${concept.label}.'
            : '«$word» no es una palabra propia de la tienda.',
        action: removed
            ? SnackBarAction(
                label: 'Deshacer',
                onPressed: () => unawaited(
                  _c.addWords(concept: concept.concept, words: [word]),
                ),
              )
            : null,
      );
    } catch (error) {
      if (mounted) showCatalogMessage(context, catalogErrorMessage(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _c,
      builder: (context, _) => LayoutBuilder(
        builder: (context, constraints) {
          final theme = Theme.of(context);
          final scheme = theme.colorScheme;
          final wide = constraints.maxWidth >= 1080;
          final compact = constraints.maxWidth < 700;
          final side = compact ? 12.0 : 20.0;

          if (!_c.loaded) {
            return Center(
              child: _c.error == null
                  ? const CircularProgressIndicator()
                  : Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'No se pudieron leer las búsquedas.',
                            style: theme.textTheme.titleSmall,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _c.error!,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 12),
                          VbButton(
                            label: 'Reintentar',
                            variant: VbButtonVariant.secondary,
                            onPressed: _c.load,
                          ),
                        ],
                      ),
                    ),
            );
          }

          final header = Padding(
            padding: EdgeInsets.fromLTRB(side, 16, side, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Búsquedas de la tienda',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: Text(
                    'Lo que la gente busca en vinabike.cl y no encuentra, y '
                    'las palabras que entiende el buscador. Agrega la palabra '
                    'que falta a su grupo y la búsqueda encuentra lo mismo '
                    'que las otras.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                if (!wide) ...[
                  const SizedBox(height: 14),
                  VbSegmented<_Pane>(
                    groupLabel: 'Ver',
                    value: _pane,
                    options: [
                      VbSegmentedOption(
                        value: _Pane.misses,
                        label: 'Sin resultados (${_c.openCount})',
                      ),
                      VbSegmentedOption(
                        value: _Pane.words,
                        label: 'Palabras (${_c.vocabulary.length})',
                      ),
                    ],
                    onChanged: (pane) => setState(() => _pane = pane),
                  ),
                ],
              ],
            ),
          );

          final misses = _MissesPanel(
            controller: _c,
            state: _state,
            onState: (state) => setState(() => _state = state),
            onAnswer: _answer,
            onIgnore: _ignore,
          );
          final words = _WordsPanel(
            controller: _c,
            filter: _filter,
            onAdd: _addTo,
            onRemove: _remove,
          );

          if (wide) {
            return ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                header,
                Padding(
                  padding: EdgeInsets.fromLTRB(side, 16, side, 0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 5, child: misses),
                      const SizedBox(width: 20),
                      Expanded(flex: 6, child: words),
                    ],
                  ),
                ),
              ],
            );
          }
          return ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              header,
              Padding(
                padding: EdgeInsets.fromLTRB(side, 14, side, 0),
                child: _pane == _Pane.misses ? misses : words,
              ),
            ],
          );
        },
      ),
    );
  }
}

/// A titled surface the two halves share.
class _Panel extends StatelessWidget {
  const _Panel({
    required this.title,
    required this.subtitle,
    required this.child,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (trailing != null) ...[const SizedBox(width: 12), trailing!],
              ],
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _MissesPanel extends StatelessWidget {
  const _MissesPanel({
    required this.controller,
    required this.state,
    required this.onState,
    required this.onAnswer,
    required this.onIgnore,
  });

  final CatalogSearchController controller;
  final CatalogSearchMissState state;
  final ValueChanged<CatalogSearchMissState> onState;
  final ValueChanged<CatalogSearchMiss> onAnswer;
  final Future<void> Function(CatalogSearchMiss, {required bool ignored})
      onIgnore;

  @override
  Widget build(BuildContext context) {
    final roles = VinabikeThemeRoles.of(context);
    final shown = controller.missesIn(state);
    final count = {
      for (final value in CatalogSearchMissState.values)
        value: controller.missesIn(value).length,
    };
    return _Panel(
      title: 'Sin resultados',
      subtitle: 'Cada búsqueda que no encontró nada en toda la tienda, con las '
          'veces que se buscó. Sin correos, teléfonos ni RUT.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: VbSegmented<CatalogSearchMissState>(
              groupLabel: 'Búsquedas',
              value: state,
              options: [
                VbSegmentedOption(
                  value: CatalogSearchMissState.open,
                  label: 'Por revisar (${count[CatalogSearchMissState.open]})',
                ),
                VbSegmentedOption(
                  value: CatalogSearchMissState.word,
                  label: 'Resueltas (${count[CatalogSearchMissState.word]})',
                ),
                VbSegmentedOption(
                  value: CatalogSearchMissState.ignored,
                  label: 'Ignoradas (${count[CatalogSearchMissState.ignored]})',
                ),
              ],
              onChanged: onState,
            ),
          ),
          Divider(height: 1, color: roles.hairline),
          if (shown.isEmpty)
            CatalogEmpty(
              title: switch (state) {
                CatalogSearchMissState.open => 'Nada por revisar',
                CatalogSearchMissState.word => 'Todavía no hay resueltas',
                CatalogSearchMissState.ignored => 'No hay ignoradas',
              },
              body: state == CatalogSearchMissState.open
                  ? 'Cuando alguien busque en vinabike.cl algo que la tienda '
                      'no encuentra, aparece aquí con cuántas veces se buscó.'
                  : null,
            )
          else
            for (final (index, miss) in shown.indexed) ...[
              if (index > 0) Divider(height: 1, color: roles.hairline),
              _MissRow(
                miss: miss,
                group: miss.concept == null
                    ? null
                    : controller.concept(miss.concept!)?.label ??
                        _label(miss.concept!),
                busy: controller.busy,
                onAnswer: () => onAnswer(miss),
                onIgnore: () => onIgnore(miss, ignored: true),
                onReopen: () => onIgnore(miss, ignored: false),
              ),
            ],
        ],
      ),
    );
  }
}

class _MissRow extends StatelessWidget {
  const _MissRow({
    required this.miss,
    required this.group,
    required this.busy,
    required this.onAnswer,
    required this.onIgnore,
    required this.onReopen,
  });

  final CatalogSearchMiss miss;

  /// The name of the group a word was added to.
  final String? group;
  final bool busy;
  final VoidCallback onAnswer;
  final VoidCallback onIgnore;
  final VoidCallback onReopen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final roles = VinabikeThemeRoles.of(context);
    final searches = miss.searches == 1 ? '1 vez' : '${miss.searches} veces';
    final meta = [
      'Buscada $searches',
      'la última ${_ago(miss.lastSeenAt)}',
    ].join(' · ');
    final open = miss.state == CatalogSearchMissState.open;
    final store = '/productos?q=${Uri.encodeQueryComponent(miss.typed)}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: miss.searches > 2
                      ? roles.warning.container
                      : scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${miss.searches}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: miss.searches > 2
                        ? roles.warning.onContainer
                        : scheme.onSurfaceVariant,
                  ),
                  semanticsLabel: 'Buscada $searches',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '«${miss.typed}»',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      meta,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    if (miss.onlyOutOfStock ||
                        miss.state == CatalogSearchMissState.word) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          if (miss.state == CatalogSearchMissState.word &&
                              group != null)
                            VbStatusBadge(
                              label: 'En el grupo $group',
                              tone: VbStatusTone.success,
                            ),
                          if (miss.onlyOutOfStock)
                            VbStatusBadge(
                              label: miss.outOfStock == 1
                                  ? 'Existe, agotado'
                                  : 'Existen ${miss.outOfStock}, agotados',
                              tone: VbStatusTone.info,
                            ),
                        ],
                      ),
                    ],
                    if (miss.onlyOutOfStock && open) ...[
                      const SizedBox(height: 4),
                      Text(
                        'El buscador lo entiende: lo que falta es stock.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: roles.faintForeground,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Ver la búsqueda en vinabike.cl',
                onPressed: () => openCatalogStorePath(context, store),
                icon: const Icon(Icons.open_in_new_rounded, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 56),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (open) ...[
                  VbButton(
                    label: 'Es una palabra de…',
                    icon: Icons.playlist_add_rounded,
                    variant: VbButtonVariant.secondary,
                    busy: busy,
                    onPressed: onAnswer,
                  ),
                  VbButton(
                    label: 'Ignorar',
                    variant: VbButtonVariant.text,
                    onPressed: busy ? null : onIgnore,
                    disabledReason: busy ? 'Guardando…' : null,
                  ),
                ] else if (miss.state == CatalogSearchMissState.ignored)
                  VbButton(
                    label: 'Volver a revisar',
                    variant: VbButtonVariant.text,
                    onPressed: busy ? null : onReopen,
                    disabledReason: busy ? 'Guardando…' : null,
                  )
                else
                  VbButton(
                    label: 'Agregar otra palabra',
                    icon: Icons.playlist_add_rounded,
                    variant: VbButtonVariant.text,
                    onPressed: busy ? null : onAnswer,
                    disabledReason: busy ? 'Guardando…' : null,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _ago(DateTime when) {
    final days = DateTime.now().difference(when).inDays;
    if (days <= 0) return 'hoy';
    if (days == 1) return 'ayer';
    if (days < 30) return 'hace $days días';
    final months = days ~/ 30;
    return months == 1 ? 'hace un mes' : 'hace $months meses';
  }
}

/// A name as a group's: its first letter in capital.
String _label(String text) {
  final name = text.replaceAll('_', ' ').trim();
  return name.isEmpty ? name : '${name[0].toUpperCase()}${name.substring(1)}';
}

class _WordsPanel extends StatelessWidget {
  const _WordsPanel({
    required this.controller,
    required this.filter,
    required this.onAdd,
    required this.onRemove,
  });

  final CatalogSearchController controller;
  final TextEditingController filter;
  final ValueChanged<CatalogSearchConcept?> onAdd;
  final void Function(CatalogSearchConcept, String) onRemove;

  @override
  Widget build(BuildContext context) {
    final roles = VinabikeThemeRoles.of(context);
    final query = filter.text;
    final concepts = [
      for (final concept in controller.vocabulary)
        if (concept.matches(query)) concept,
    ];
    final own = controller.ownWordCount;
    return _Panel(
      title: 'Palabras del buscador',
      subtitle:
          '${controller.vocabulary.length} grupos. Una palabra encuentra lo '
          'que encuentran las otras de su grupo: quien busca «motor» ve los '
          'pedaleros. Van sin tildes: el buscador no las distingue. ${own == 0 ? 'La tienda todavía no agrega palabras propias.' : own == 1 ? '1 palabra es propia de la tienda.' : '$own palabras son propias de la tienda.'}',
      trailing: VbButton(
        label: 'Grupo nuevo',
        icon: Icons.add_rounded,
        variant: VbButtonVariant.secondary,
        busy: controller.busy,
        onPressed: () => onAdd(null),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: TextField(
              key: const ValueKey('catalog-search-filter'),
              controller: filter,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                hintText: 'Buscar una palabra o un grupo',
                border: const OutlineInputBorder(),
                suffixIcon: query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Borrar',
                        onPressed: filter.clear,
                        icon: const Icon(Icons.close_rounded, size: 18),
                      ),
              ),
            ),
          ),
          Divider(height: 1, color: roles.hairline),
          if (concepts.isEmpty)
            CatalogEmpty(
              title: 'Ningún grupo dice «${query.trim()}»',
              body: 'Créalo con «Grupo nuevo», o agrégala a un grupo que '
                  'signifique lo mismo.',
            )
          else
            for (final (index, concept) in concepts.indexed) ...[
              if (index > 0) Divider(height: 1, color: roles.hairline),
              _ConceptRow(
                concept: concept,
                busy: controller.busy,
                onAdd: () => onAdd(concept),
                onRemove: (word) => onRemove(concept, word),
              ),
            ],
        ],
      ),
    );
  }
}

class _ConceptRow extends StatelessWidget {
  const _ConceptRow({
    required this.concept,
    required this.busy,
    required this.onAdd,
    required this.onRemove,
  });

  final CatalogSearchConcept concept;
  final bool busy;
  final VoidCallback onAdd;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final roles = VinabikeThemeRoles.of(context);
    final chipText = theme.textTheme.labelMedium;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                concept.label,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                [
                  if (!concept.shared) 'de la tienda',
                  if (concept.kind == 'attribute')
                    'también en la ficha técnica',
                  if (concept.broader.isNotEmpty)
                    'dentro de ${concept.broader.first}',
                ].join(' · '),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: roles.faintForeground,
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Agregar palabras a ${concept.label}',
                onPressed: busy ? null : onAdd,
                icon: const Icon(Icons.add_rounded, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final word in concept.sharedWords)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    word,
                    style: chipText?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
              for (final word in concept.ownWords)
                Semantics(
                  container: true,
                  label: 'Palabra de la tienda: $word',
                  child: Container(
                    padding: const EdgeInsets.only(left: 10),
                    decoration: BoxDecoration(
                      color: roles.selectionContainer,
                      border: Border.all(color: roles.accentBorder),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          word,
                          style: chipText?.copyWith(
                            color: roles.onSelectionContainer,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(
                          width: 36,
                          height: 30,
                          child: IconButton(
                            tooltip: 'Quitar «$word»',
                            padding: EdgeInsets.zero,
                            iconSize: 16,
                            onPressed: busy ? null : () => onRemove(word),
                            icon: Icon(
                              Icons.close_rounded,
                              color: roles.onSelectionContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// What the picker or the editor chose: the group and the words.
typedef CatalogSearchWordsChoice = ({
  String concept,
  List<String> words,
  String? label,
});

/// The words as written in one field, by commas or new lines.
List<String> _splitWords(String text) => [
      for (final part in text.split(RegExp(r'[,;\n]')))
        if (part.trim().isNotEmpty) part.trim(),
    ];

/// A sheet on a phone, a dialog on a wide screen.
Future<T?> _showPanel<T>(
  BuildContext context,
  WidgetBuilder builder, {
  bool tall = false,
}) {
  final wide = MediaQuery.sizeOf(context).width >= 640;
  if (wide) {
    return showDialog<T>(
      context: context,
      builder: (context) => Dialog(
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 680),
          child: builder(context),
        ),
      ),
    );
  }
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (context) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: tall
          ? FractionallySizedBox(heightFactor: 0.88, child: builder(context))
          : builder(context),
    ),
  );
}

/// «Es una palabra de…»: the group a search means, with its words.
Future<CatalogSearchWordsChoice?> showCatalogSearchWordPicker(
  BuildContext context, {
  required CatalogSearchController controller,
  required CatalogSearchMiss miss,
}) =>
    _showPanel(
      context,
      (context) => _WordPicker(controller: controller, miss: miss),
    );

class _WordPicker extends StatefulWidget {
  const _WordPicker({required this.controller, required this.miss});

  final CatalogSearchController controller;
  final CatalogSearchMiss miss;

  @override
  State<_WordPicker> createState() => _WordPickerState();
}

class _WordPickerState extends State<_WordPicker> {
  late final _words = TextEditingController(text: widget.miss.typed);
  late final _find = TextEditingController(text: _firstWord(widget.miss.typed));
  String? _picked;

  static String _firstWord(String text) {
    final words = foldCatalogSearchText(text).split(' ');
    return words.isEmpty ? '' : words.first;
  }

  @override
  void initState() {
    super.initState();
    _find.addListener(() => setState(() {}));
    _words.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _words.dispose();
    _find.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final roles = VinabikeThemeRoles.of(context);
    final query = _find.text;
    var concepts = [
      for (final concept in widget.controller.vocabulary)
        if (concept.matches(query)) concept,
    ];
    if (concepts.isEmpty && query.trim().isNotEmpty) {
      concepts = widget.controller.vocabulary;
    }
    final words = _splitWords(_words.text);
    final newName = foldCatalogSearchText(words.isEmpty ? '' : words.first);
    final newLabel = _label(words.isEmpty ? '' : words.first);
    final picked = _picked;
    final canSave = words.isNotEmpty && picked != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
          child: Text(
            '¿Qué buscaban con «${widget.miss.typed}»?',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Text(
            'Elige el grupo que significa lo mismo: la búsqueda va a '
            'encontrar lo que encuentran sus palabras.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
          child: TextField(
            key: const ValueKey('catalog-search-words'),
            controller: _words,
            decoration: const InputDecoration(
              labelText: 'Palabras que se agregan',
              helperMaxLines: 3,
              helperText: 'Separadas por coma. Agrega también el plural si '
                  'se busca así («buje, bujes»).',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: TextField(
            key: const ValueKey('catalog-search-find-group'),
            controller: _find,
            decoration: const InputDecoration(
              isDense: true,
              prefixIcon: Icon(Icons.search_rounded, size: 20),
              hintText: 'Buscar el grupo',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        Divider(height: 1, color: roles.hairline),
        Expanded(
          child: RadioGroup<String>(
            groupValue: picked,
            onChanged: (value) => setState(() => _picked = value),
            child: ListView(
              children: [
                if (newName.isNotEmpty &&
                    widget.controller.concept(newName) == null)
                  RadioListTile<String>(
                    value: newName,
                    title: Text('Grupo nuevo: $newLabel'),
                    subtitle: const Text(
                      'Ninguno significa lo mismo: un grupo propio de la '
                      'tienda con estas palabras.',
                    ),
                  ),
                for (final concept in concepts)
                  RadioListTile<String>(
                    value: concept.concept,
                    title: Text(concept.label),
                    subtitle: Text(
                      concept.allWords.take(8).join(', '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
          ),
        ),
        Divider(height: 1, color: roles.hairline),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          // A disabled button says why beside it: on a phone they wrap.
          child: Wrap(
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              VbButton(
                label: 'Cancelar',
                variant: VbButtonVariant.text,
                onPressed: () => Navigator.of(context).pop(),
              ),
              VbButton(
                label: picked == null
                    ? 'Agregar'
                    : 'Agregar a ${widget.controller.concept(picked)?.label ?? newLabel}',
                onPressed: canSave
                    ? () => Navigator.of(
                          context,
                        ).pop((
                          concept: picked,
                          words: words,
                          label: widget.controller.concept(picked) == null
                              ? newLabel
                              : null,
                        ))
                    : null,
                disabledReason: words.isEmpty
                    ? 'Escribe al menos una palabra.'
                    : 'Elige un grupo.',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Words for a group ([concept]), or a new group when it is null.
Future<CatalogSearchWordsChoice?> showCatalogSearchWordsEditor(
  BuildContext context, {
  CatalogSearchConcept? concept,
}) =>
    _showPanel(context, (context) => _WordsEditor(concept: concept));

class _WordsEditor extends StatefulWidget {
  const _WordsEditor({this.concept});

  final CatalogSearchConcept? concept;

  @override
  State<_WordsEditor> createState() => _WordsEditorState();
}

class _WordsEditorState extends State<_WordsEditor> {
  final _name = TextEditingController();
  final _words = TextEditingController();

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
    _words.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    _words.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final concept = widget.concept;
    final words = _splitWords(_words.text);
    final name = concept?.concept ?? foldCatalogSearchText(_name.text);
    final canSave = words.isNotEmpty && name.isNotEmpty;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            concept == null
                ? 'Grupo nuevo'
                : 'Agregar palabras a ${concept.label}',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            concept == null
                ? 'Palabras que nombran lo mismo. Un producto que diga una '
                    'de ellas en su nombre o su categoría aparece al buscar '
                    'cualquiera.'
                : 'Ya dice: ${concept.allWords.join(', ')}.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          if (concept == null) ...[
            TextField(
              key: const ValueKey('catalog-search-group-name'),
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Nombre del grupo',
                hintText: 'Por ejemplo: portabidón',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            key: const ValueKey('catalog-search-group-words'),
            controller: _words,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Palabras',
              hintText: 'caramagiola, caramagiolas, portacaramagiola',
              helperMaxLines: 3,
              helperText: 'Separadas por coma. Varias palabras juntas '
                  '(«pata de cambio») se buscan como frase.',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              VbButton(
                label: 'Cancelar',
                variant: VbButtonVariant.text,
                onPressed: () => Navigator.of(context).pop(),
              ),
              VbButton(
                label: concept == null ? 'Crear grupo' : 'Agregar',
                onPressed: canSave
                    ? () => Navigator.of(
                          context,
                        ).pop((
                          concept: name,
                          words: words,
                          label: concept == null ? _label(_name.text) : null,
                        ))
                    : null,
                disabledReason: name.isEmpty
                    ? 'Escribe el nombre del grupo.'
                    : 'Escribe al menos una palabra.',
              ),
            ],
          ),
        ],
      ),
    );
  }
}
