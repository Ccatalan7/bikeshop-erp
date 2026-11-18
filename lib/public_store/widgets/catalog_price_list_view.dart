import 'package:flutter/material.dart';
import 'package:vinabike_public_core/modules/website/models/website_action.dart';
import 'package:vinabike_public_core/modules/website/models/website_catalog_presentation.dart';
import 'package:vinabike_public_core/modules/website/models/website_catalog_price_list.dart';

import '../theme/public_store_theme.dart';
import 'public_link_semantics.dart';

/// The sections the editor makes selectable on the canvas.
enum CatalogPriceListSection { hero, plans, list, closing }

/// The presentation's own texts, which the editor writes on the page.
enum CatalogPriceListField { eyebrow, title, intro, closingTitle, closingText }

/// What the editor adds to the price list on its canvas; the store and the
/// preview draw it without one.
class CatalogPriceListEditing {
  const CatalogPriceListEditing({
    required this.section,
    required this.text,
    required this.showsEmpty,
  });

  /// Wraps one section in its selectable chrome.
  final Widget Function(CatalogPriceListSection section, Widget child) section;

  /// One of the presentation's texts, written where it is read.
  final Widget Function(
    CatalogPriceListField field, {
    required String text,
    required TextStyle style,
    required TextAlign textAlign,
    required String placeholder,
    required bool uppercase,
  }) text;

  /// Whether an empty optional text is offered to write (its section is
  /// selected); otherwise it takes no room, as on the store.
  final bool Function(CatalogPriceListField field) showsEmpty;
}

/// A catalog root laid out as a price list ([WebsiteCatalogLayout.priceList]),
/// as the HTML storefront draws it (`catalog_price_list_view.dart`): the hero
/// with its button and the Google rating, the plan category's items as cards,
/// every other item by its category with its price and a search that filters
/// them, and the closing band. The store catalog, its Edit and Preview, and
/// the «Catálogo web» workspace preview draw this one widget.
///
/// Colors and fonts come from the website theme above it (`WebsiteThemeBuilder`):
/// the primary darkened for the bands, the accent for the buttons.
class CatalogPriceListView extends StatefulWidget {
  const CatalogPriceListView({
    super.key,
    required this.presentation,
    required this.list,
    required this.title,
    required this.intro,
    required this.heroImageUrl,
    required this.rootLabel,
    required this.plansTitle,
    required this.plansIntro,
    this.rating,
    this.initialQuery = '',
    this.noun = 'servicios',
    this.singular = 'servicio',
    this.onOpenItem,
    this.itemHref,
    this.onAction,
    this.isActionShown,
    this.onHome,
    this.editing,
  });

  final WebsiteCatalogPresentation presentation;
  final CatalogPriceList list;

  /// The hero's title and intro, already resolved against the root's name.
  final String title;
  final String intro;
  final String heroImageUrl;

  /// «Servicios»: the last step of the hero's trail.
  final String rootLabel;

  /// The plan category's own name and description.
  final String plansTitle;
  final String plansIntro;

  /// The store's Google rating, when the hero shows it and there is one.
  final CatalogPriceListRating? rating;

  /// The search the page opens with (`?q=`).
  final String initialQuery;

  /// What it lists, in plural and singular («servicios», «servicio»).
  final String noun;
  final String singular;

  /// Opens an item's page; null where the surface does not navigate.
  final ValueChanged<String>? onOpenItem;
  final String? Function(String id)? itemHref;

  /// Follows one of the editor's actions; null where the surface does not
  /// navigate.
  final ValueChanged<WebsiteActionValue>? onAction;

  /// Whether a visitor may follow an action's destination; one it may not
  /// follow is not drawn, as the HTML hides it (`publicHref`).
  final bool Function(String href)? isActionShown;
  final VoidCallback? onHome;

  /// Present on the editor's canvas only.
  final CatalogPriceListEditing? editing;

  @override
  State<CatalogPriceListView> createState() => _CatalogPriceListViewState();
}

class _CatalogPriceListViewState extends State<CatalogPriceListView> {
  final _search = TextEditingController();
  final _groupKeys = <String, GlobalKey>{};

  /// The groups a phone shows open: the first, until one is opened or
  /// searched.
  Set<String>? _open;

  @override
  void initState() {
    super.initState();
    _search.text = widget.initialQuery;
    _search.addListener(() => setState(() {}));
  }

  @override
  void didUpdateWidget(CatalogPriceListView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A new `?q=` replaces the search; the visitor's own typing stays while
    // the address does not change.
    if (widget.initialQuery != oldWidget.initialQuery) {
      _search.text = widget.initialQuery;
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// The editor's action when it can be followed here.
  WebsiteActionValue? _shown(WebsiteActionValue? action) =>
      action != null && (widget.isActionShown?.call(action.href) ?? true)
          ? action
          : null;

  GlobalKey _keyFor(String categoryId) =>
      _groupKeys.putIfAbsent(categoryId, GlobalKey.new);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final look = _PriceListLook.of(context, width);
        return Material(
          type: MaterialType.transparency,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _section(CatalogPriceListSection.hero, _hero(look)),
              if (widget.list.plans.isNotEmpty)
                _section(CatalogPriceListSection.plans, _plans(look)),
              _section(CatalogPriceListSection.list, _listSection(look)),
              if (widget.presentation.hasClosing)
                _section(CatalogPriceListSection.closing, _closing(look)),
            ],
          ),
        );
      },
    );
  }

  Widget _section(CatalogPriceListSection section, Widget child) =>
      widget.editing?.section(section, child) ?? child;

  /// One of the presentation's texts: written in place on the canvas, a plain
  /// text elsewhere. Null when it is empty and not offered.
  Widget? _text(
    CatalogPriceListField field, {
    required String text,
    required TextStyle style,
    TextAlign textAlign = TextAlign.start,
    String placeholder = '',
    bool uppercase = false,
  }) {
    final editing = widget.editing;
    if (editing == null) {
      if (text.isEmpty) return null;
      return Text(
        uppercase ? text.toUpperCase() : text,
        textAlign: textAlign,
        style: style,
      );
    }
    if (text.isEmpty && !editing.showsEmpty(field)) return null;
    return editing.text(
      field,
      text: text,
      style: style,
      textAlign: textAlign,
      placeholder: placeholder,
      uppercase: uppercase,
    );
  }

  Widget _frame(_PriceListLook look, Widget child) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: look.phone ? 20 : 32),
            child: child,
          ),
        ),
      );

  Widget _hero(_PriceListLook look) {
    final presentation = widget.presentation;
    final centered =
        presentation.heroAlignment == WebsiteCatalogHeroAlignment.center;
    final align = centered ? TextAlign.center : TextAlign.start;
    final rating = widget.rating;
    final text = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: look.phone ? double.infinity : 720),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment:
            centered ? CrossAxisAlignment.center : CrossAxisAlignment.start,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _link(
                onTap: widget.onHome,
                href: '/',
                child: Text('Inicio', style: look.crumb),
              ),
              Text(' / ', style: look.crumb),
              Text(widget.rootLabel, style: look.crumb),
            ],
          ),
          const SizedBox(height: 20),
          if (_text(
            CatalogPriceListField.eyebrow,
            text: presentation.heroEyebrow,
            textAlign: align,
            style: look.eyebrow,
            placeholder: 'Etiqueta sobre el título',
            uppercase: true,
          )
              case final eyebrow?) ...[
            eyebrow,
            const SizedBox(height: 14),
          ],
          _text(
                CatalogPriceListField.title,
                // The canvas writes the saved title; empty, the store shows
                // the root's name, which the canvas shows as its placeholder.
                text: widget.editing == null
                    ? widget.title
                    : presentation.heroTitle,
                textAlign: align,
                style: look.heroTitle,
                placeholder: widget.title.toUpperCase(),
                uppercase: true,
              ) ??
              const SizedBox.shrink(),
          if (_text(
            CatalogPriceListField.intro,
            text: widget.intro,
            textAlign: align,
            style: look.heroIntro,
            placeholder: 'Una o dos líneas bajo el título',
          )
              case final intro?) ...[
            const SizedBox(height: 22),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: intro,
            ),
          ],
          if (_shown(presentation.heroAction) case final action?) ...[
            const SizedBox(height: 32),
            SizedBox(
              width: look.phone ? double.infinity : null,
              child: _button(look, action, onDark: true, whatsappIcon: true),
            ),
          ],
        ],
      ),
    );
    final ratingCard = rating == null ? null : _ratingCard(look, rating);
    return Material(
      color: look.navy,
      child: Stack(
        children: [
          if (widget.heroImageUrl.isNotEmpty) ...[
            Positioned.fill(
              child: Image.network(
                widget.heroImageUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black.withValues(alpha: presentation.heroOverlay),
              ),
            ),
          ],
          _frame(
            look,
            Padding(
              padding: look.phone
                  ? const EdgeInsets.fromLTRB(0, 40, 0, 44)
                  : const EdgeInsets.fromLTRB(0, 64, 0, 72),
              child: look.phone || ratingCard == null
                  ? Column(
                      crossAxisAlignment: centered
                          ? CrossAxisAlignment.center
                          : CrossAxisAlignment.stretch,
                      children: [
                        text,
                        if (ratingCard != null) ...[
                          const SizedBox(height: 24),
                          ratingCard,
                        ],
                      ],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisAlignment: centered
                          ? MainAxisAlignment.center
                          : MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(child: text),
                        const SizedBox(width: 40),
                        SizedBox(width: 300, child: ratingCard),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _ratingCard(_PriceListLook look, CatalogPriceListRating rating) {
    return Semantics(
      container: true,
      label: [
        'Calificación en Google: ${rating.label} de 5',
        if (rating.totalLabel.isNotEmpty) rating.totalLabel,
      ].join(', '),
      excludeSemantics: true,
      child: Container(
        padding: look.phone
            ? const EdgeInsets.symmetric(horizontal: 20, vertical: 18)
            : const EdgeInsets.symmetric(horizontal: 26, vertical: 24),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(rating.label, style: look.ratingNumber),
                const SizedBox(width: 12),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: _Stars(
                      fraction: rating.rating / 5,
                      color: look.accent,
                      size: 22,
                    ),
                  ),
                ),
              ],
            ),
            if (rating.totalLabel.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(rating.totalLabel, style: look.ratingNote),
            ],
          ],
        ),
      ),
    );
  }

  /// The plans side by side ([CatalogPlanTable]), as the HTML lays them out:
  /// columns whose head, price and button share their lines, then the
  /// presentation's rows (a plan without one says so) and what each plan
  /// includes that no row holds. Four columns from 1024 px, two by two below
  /// (three stay in one line), and on a phone one band per plan, edge to
  /// edge, with only what it includes.
  Widget _plans(_PriceListLook look) {
    final list = widget.list;
    final fullest = list.fullestPlan;
    final table = list.planTable(widget.presentation.planRows);
    final count = table.plans.length;
    final head = _head(
      look,
      title: widget.plansTitle.isEmpty ? 'Planes' : widget.plansTitle,
      intro: widget.plansIntro,
    );
    if (look.phone) {
      return ColoredBox(
        color: look.paper,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 48),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _frame(look, head),
              const SizedBox(height: 34),
              DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.symmetric(
                    horizontal: BorderSide(color: look.line),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var index = 0; index < count; index++)
                      _planBand(
                        look,
                        table,
                        index,
                        highlighted: identical(table.plans[index], fullest),
                        first: index == 0,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }
    final columns = look.width >= 1024
        ? (count < 4 ? count : 4)
        : (count == 3 ? 3 : (count < 2 ? count : 2));
    return ColoredBox(
      color: look.paper,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 80),
        child: _frame(
          look,
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              head,
              const SizedBox(height: 34),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: look.background,
                  border: Border.all(color: look.line),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var start = 0; start < count; start += columns) ...[
                      if (start > 0) Container(height: 1, color: look.line),
                      ..._planLines(
                        look,
                        table,
                        [
                          for (var index = start;
                              index < start + columns;
                              index++)
                            index < count ? index : null,
                        ],
                        fullest: fullest,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// One line of plans on the table, line by line: heads, prices, buttons,
  /// then each row and the extras; [slots] holds each column's plan, or null
  /// for an empty column of the last line.
  List<Widget> _planLines(
    _PriceListLook look,
    CatalogPlanTable table,
    List<int?> slots, {
    required CatalogPricePlan? fullest,
  }) {
    bool lit(int index) => identical(table.plans[index], fullest);
    Widget line(Widget Function(int index, bool highlighted) cell) =>
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (column, index) in slots.indexed)
                Expanded(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: index != null && lit(index)
                          ? look.navy
                          : look.background,
                      border: Border(
                        left: column > 0
                            ? BorderSide(color: look.line)
                            : BorderSide.none,
                      ),
                    ),
                    child: index == null
                        ? const SizedBox.shrink()
                        : cell(index, lit(index)),
                  ),
                ),
            ],
          ),
        );
    return [
      line((index, lit) => _planTop(look, table, index, highlighted: lit)),
      line((index, lit) => _planPrice(look, table, index, highlighted: lit)),
      line((index, lit) => _planCta(look, highlighted: lit)),
      for (final row in table.rows)
        line(
          (index, lit) => _planCell(
            look,
            row.cells[index],
            row.label,
            highlighted: lit,
          ),
        ),
      for (var extra = 0; extra < table.extraLines; extra++)
        line(
          (index, lit) => extra < table.extras[index].length
              ? _planCell(
                  look,
                  [table.extras[index][extra]],
                  '',
                  highlighted: lit,
                )
              : const SizedBox.shrink(),
        ),
    ];
  }

  /// A plan on a phone: its head, price and button, then only what it
  /// includes, one band after another.
  Widget _planBand(
    _PriceListLook look,
    CatalogPlanTable table,
    int index, {
    required bool highlighted,
    required bool first,
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: highlighted ? look.navy : look.background,
        border: first
            ? null
            : Border(top: BorderSide(color: look.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _planTop(look, table, index, highlighted: highlighted),
          _planPrice(look, table, index, highlighted: highlighted),
          _planCta(look, highlighted: highlighted),
          for (final row in table.rows)
            if (row.cells[index].isNotEmpty)
              _planCell(look, row.cells[index], row.label,
                  highlighted: highlighted),
          for (final include in table.extras[index])
            _planCell(look, [include], '', highlighted: highlighted),
        ],
      ),
    );
  }

  Widget _planTop(
    _PriceListLook look,
    CatalogPlanTable table,
    int index, {
    required bool highlighted,
  }) {
    final plan = table.plans[index];
    final head = table.heads[index];
    final ink = highlighted ? Colors.white : look.ink;
    final mute = highlighted ? Colors.white.withValues(alpha: 0.74) : look.mute;
    return Padding(
      padding: look.phone
          ? const EdgeInsets.fromLTRB(20, 24, 20, 0)
          : const EdgeInsets.fromLTRB(26, 28, 26, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (head.kicker.isNotEmpty || highlighted) ...[
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 24),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 8,
                children: [
                  if (head.kicker.isNotEmpty)
                    Text(
                      head.kicker.toUpperCase(),
                      style: look.planKicker.copyWith(
                        color: highlighted
                            ? Colors.white.withValues(alpha: 0.72)
                            : look.mute,
                      ),
                    ),
                  if (highlighted)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: look.accent,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text('LA MÁS COMPLETA', style: look.pill),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
          _link(
            onTap: widget.onOpenItem == null
                ? null
                : () => widget.onOpenItem!(plan.item.id),
            href: widget.itemHref?.call(plan.item.id),
            child: Text(
              head.name.toUpperCase(),
              semanticsLabel: plan.item.name,
              style: look.planName.copyWith(color: ink),
            ),
          ),
          if (head.note.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(head.note, style: look.planNote.copyWith(color: mute)),
          ],
        ],
      ),
    );
  }

  Widget _planPrice(
    _PriceListLook look,
    CatalogPlanTable table,
    int index, {
    required bool highlighted,
  }) {
    return Padding(
      padding: look.phone
          ? const EdgeInsets.fromLTRB(20, 14, 20, 0)
          : const EdgeInsets.fromLTRB(26, 20, 26, 0),
      child: Text(
        table.plans[index].item.priceLabel,
        style: look.planPrice.copyWith(
          color: highlighted ? Colors.white : look.ink,
        ),
      ),
    );
  }

  /// The button's line, kept without a button so the rows keep theirs.
  Widget _planCta(_PriceListLook look, {required bool highlighted}) {
    final action = _shown(widget.presentation.heroAction);
    return Padding(
      padding: look.phone
          ? const EdgeInsets.fromLTRB(20, 18, 20, 22)
          : const EdgeInsets.fromLTRB(26, 24, 26, 28),
      child: action == null
          ? const SizedBox.shrink()
          : SizedBox(
              width: double.infinity,
              child: _button(look, action, onDark: highlighted, compact: true),
            ),
    );
  }

  /// A cell of a plan's column: the lines of its «qué incluye» on that row,
  /// or, when it has none, the row's subject after a cross.
  Widget _planCell(
    _PriceListLook look,
    List<CatalogPlanInclude> includes,
    String label, {
    required bool highlighted,
  }) {
    final ink = highlighted ? Colors.white : look.ink;
    final mute = highlighted ? Colors.white.withValues(alpha: 0.7) : look.mute;
    final included = includes.isNotEmpty;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: highlighted
                ? Colors.white.withValues(alpha: 0.16)
                : look.line,
          ),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: look.phone ? 20 : 26,
          vertical: look.phone ? 12 : 13,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.only(top: included ? 2 : 3),
              child: included
                  ? Icon(
                      Icons.check_rounded,
                      size: 18,
                      color: highlighted ? look.accent : look.primary,
                    )
                  : Icon(
                      Icons.close_rounded,
                      size: 16,
                      color: mute.withValues(alpha: mute.a * 0.7),
                    ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: included
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final (position, include) in includes.indexed) ...[
                          if (position > 0) const SizedBox(height: 8),
                          Text(
                            include.title,
                            style: look.include.copyWith(color: ink),
                          ),
                          if (include.detail.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              include.detail,
                              style: look.includeDetail.copyWith(color: mute),
                            ),
                          ],
                        ],
                      ],
                    )
                  : Text(
                      label,
                      semanticsLabel: 'No incluye: $label',
                      style: look.include.copyWith(color: mute),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _head(
    _PriceListLook look, {
    required String title,
    String intro = '',
    Widget? trailing,
  }) {
    final heading = Text(title.toUpperCase(), style: look.sectionTitle);
    final side = trailing ??
        (intro.isEmpty
            ? null
            : ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Text(intro, style: look.sectionIntro),
              ));
    if (side == null) return heading;
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.end,
      spacing: 32,
      runSpacing: 16,
      children: [heading, side],
    );
  }

  Widget _listSection(_PriceListLook look) {
    final query = catalogPriceSearchKey(_search.text);
    final groups = [
      for (final group in widget.list.groups)
        if (_matching(group, query) case final items when items.isNotEmpty)
          (group: group, items: items),
    ];
    if (look.phone) {
      _open ??= {widget.list.groups.firstOrNull?.categoryId ?? ''};
    }
    final searchField = SizedBox(
      width: look.phone ? double.infinity : 340,
      child: TextField(
        controller: _search,
        style: look.searchText,
        decoration: InputDecoration(
          hintText: 'Buscar un ${widget.singular}',
          isDense: true,
          prefixIcon: Icon(Icons.search_rounded, size: 20, color: look.mute),
          filled: true,
          fillColor: look.background,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(color: look.line),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(color: look.primary),
          ),
        ),
      ),
    );
    return ColoredBox(
      color: look.background,
      child: Padding(
        padding: look.phone
            ? const EdgeInsets.fromLTRB(0, 48, 0, 56)
            : const EdgeInsets.fromLTRB(0, 84, 0, 96),
        child: _frame(
          look,
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (look.phone) ...[
                _head(look, title: 'Todos los ${widget.noun}'),
                const SizedBox(height: 16),
                searchField,
              ] else
                DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: look.ink, width: 2),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 26),
                    child: _head(
                      look,
                      title: 'Todos los ${widget.noun}',
                      trailing: searchField,
                    ),
                  ),
                ),
              if (!look.phone && widget.list.groups.length > 1) ...[
                const SizedBox(height: 22),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final entry in groups)
                      _chip(look, entry.group, entry.items.length),
                  ],
                ),
              ],
              if (groups.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 40),
                  child: Text(
                    widget.list.groups.isEmpty
                        ? 'Todavía no hay ${widget.noun} publicados.'
                        : 'No hay ${widget.noun} con ese nombre.',
                    style: look.empty,
                  ),
                )
              else
                for (var index = 0; index < groups.length; index++)
                  look.phone
                      ? _phoneGroup(
                          look,
                          groups[index].group,
                          groups[index].items,
                          first: index == 0,
                          searching: query.isNotEmpty,
                        )
                      : _group(look, groups[index].group, groups[index].items),
            ],
          ),
        ),
      ),
    );
  }

  List<CatalogPriceItem> _matching(CatalogPriceGroup group, String query) => [
        for (final item in group.items)
          if (item.matches(query)) item,
      ];

  Widget _chip(_PriceListLook look, CatalogPriceGroup group, int count) {
    return Material(
      color: Colors.transparent,
      shape: StadiumBorder(side: BorderSide(color: look.line)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          final context = _keyFor(group.categoryId).currentContext;
          if (context != null) {
            Scrollable.ensureVisible(
              context,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
            );
          }
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 40),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(group.label, style: look.chip),
                const SizedBox(width: 8),
                Text('$count', style: look.chipCount),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _count(int count) =>
      '$count ${count == 1 ? widget.singular : widget.noun}';

  Widget _group(
    _PriceListLook look,
    CatalogPriceGroup group,
    List<CatalogPriceItem> items,
  ) {
    final label = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(group.label.toUpperCase(), style: look.groupTitle),
        const SizedBox(height: 8),
        Text(_count(items.length), style: look.groupCount),
      ],
    );
    final rows = LayoutBuilder(
      builder: (context, constraints) {
        final columnWidth = (constraints.maxWidth - 40) / 2;
        return DecoratedBox(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: look.ink)),
          ),
          child: Wrap(
            spacing: 40,
            children: [
              for (final item in items)
                SizedBox(width: columnWidth, child: _row(look, item)),
            ],
          ),
        );
      },
    );
    return Padding(
      key: _keyFor(group.categoryId),
      padding: const EdgeInsets.only(top: 48),
      child: look.wide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 260, child: label),
                const SizedBox(width: 40),
                Expanded(child: rows),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [label, const SizedBox(height: 14), rows],
            ),
    );
  }

  Widget _phoneGroup(
    _PriceListLook look,
    CatalogPriceGroup group,
    List<CatalogPriceItem> items, {
    required bool first,
    required bool searching,
  }) {
    final open = searching || (_open?.contains(group.categoryId) ?? false);
    return Container(
      key: _keyFor(group.categoryId),
      margin: EdgeInsets.only(top: first ? 18 : 0),
      decoration: BoxDecoration(
        border: Border(
          top: first ? BorderSide(color: look.ink, width: 2) : BorderSide.none,
          bottom: BorderSide(color: look.line),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            expanded: open,
            child: InkWell(
              onTap: searching
                  ? null
                  : () => setState(() {
                        final current = _open ??= <String>{};
                        if (!current.remove(group.categoryId)) {
                          current.add(group.categoryId);
                        }
                      }),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 60),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        group.label.toUpperCase(),
                        style: look.groupTitle.copyWith(fontSize: 20),
                      ),
                    ),
                    Text(
                      _count(items.length),
                      style: look.groupCount.copyWith(fontSize: 14),
                    ),
                    const SizedBox(width: 12),
                    AnimatedRotation(
                      turns: open ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: look.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (open)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final item in items)
                    DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border(top: BorderSide(color: look.line)),
                      ),
                      child: _row(look, item, bordered: false),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _row(_PriceListLook look, CatalogPriceItem item,
      {bool bordered = true}) {
    final content = ConstrainedBox(
      constraints: BoxConstraints(minHeight: look.phone ? 48 : 52),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: look.phone ? 12 : 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(child: Text(item.name, style: look.rowName)),
            const SizedBox(width: 16),
            Text(item.priceLabel, style: look.rowPrice),
          ],
        ),
      ),
    );
    final onOpen = widget.onOpenItem;
    final row = _link(
      onTap: onOpen == null ? null : () => onOpen(item.id),
      href: widget.itemHref?.call(item.id),
      child: content,
    );
    if (!bordered) return row;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: look.line)),
      ),
      child: row,
    );
  }

  Widget _closing(_PriceListLook look) {
    final presentation = widget.presentation;
    final title = _text(
      CatalogPriceListField.closingTitle,
      text: presentation.closingTitle,
      style: look.closingTitle,
      placeholder: 'Título del cierre',
      uppercase: true,
    );
    final line = _text(
      CatalogPriceListField.closingText,
      text: presentation.closingText,
      style: look.closingText,
      placeholder: 'Una línea que invite a escribir',
    );
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (title != null) title,
        if (line != null) ...[
          if (title != null) const SizedBox(height: 18),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 540),
            child: line,
          ),
        ],
      ],
    );
    final action = _shown(presentation.closingAction);
    return ColoredBox(
      color: look.navy,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: look.phone ? 56 : 88),
        child: _frame(
          look,
          look.phone || action == null
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    text,
                    if (action != null) ...[
                      const SizedBox(height: 32),
                      _button(look, action, onDark: true, whatsappIcon: true),
                    ],
                  ],
                )
              : Row(
                  children: [
                    Expanded(child: text),
                    const SizedBox(width: 32),
                    _button(look, action, onDark: true, whatsappIcon: true),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _button(
    _PriceListLook look,
    WebsiteActionValue action, {
    required bool onDark,
    bool whatsappIcon = false,
    bool compact = false,
  }) {
    final href = action.href.trim();
    final isWhatsapp = href.contains('wa.me/') || href.contains('whatsapp.com');
    final onTap =
        widget.onAction == null ? null : () => widget.onAction!(action);
    final (Color fill, Color border, Color text) = switch (action.variant) {
      WebsiteActionVariant.filled => (
          look.accent,
          look.accent,
          look.onAccent,
        ),
      WebsiteActionVariant.outline => (
          Colors.transparent,
          onDark ? Colors.white.withValues(alpha: 0.75) : look.ink,
          onDark ? Colors.white : look.ink,
        ),
      WebsiteActionVariant.text => (
          Colors.transparent,
          Colors.transparent,
          onDark ? Colors.white : look.ink,
        ),
    };
    return PublicLinkSemantics(
      href: href,
      child: Material(
        color: fill,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: BorderSide(color: border, width: 1.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: compact ? 14 : 26),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (whatsappIcon && isWhatsapp) ...[
                    Icon(Icons.chat_bubble_outline_rounded,
                        size: 20, color: text),
                    const SizedBox(width: 10),
                  ],
                  Flexible(
                    child: Text(
                      action.label.toUpperCase(),
                      textAlign: TextAlign.center,
                      style: (compact ? look.planButton : look.button).copyWith(
                        color: text,
                        decoration: action.variant == WebsiteActionVariant.text
                            ? TextDecoration.underline
                            : null,
                        decorationColor: text,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _link({
    required VoidCallback? onTap,
    required String? href,
    required Widget child,
  }) {
    return PublicLinkSemantics(
      href: href,
      enabled: onTap != null,
      child: InkWell(onTap: onTap, child: child),
    );
  }
}

class _Stars extends StatelessWidget {
  const _Stars({
    required this.fraction,
    required this.color,
    required this.size,
  });

  final double fraction;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontSize: size, height: 1, letterSpacing: 2);
    return Stack(
      children: [
        Text(
          '★★★★★',
          style: style.copyWith(color: Colors.white.withValues(alpha: 0.28)),
        ),
        ClipRect(
          clipper: _FractionClipper(fraction.clamp(0, 1).toDouble()),
          child: Text('★★★★★', style: style.copyWith(color: color)),
        ),
      ],
    );
  }
}

class _FractionClipper extends CustomClipper<Rect> {
  const _FractionClipper(this.fraction);

  final double fraction;

  @override
  Rect getClip(Size size) =>
      Rect.fromLTWH(0, 0, size.width * fraction, size.height);

  @override
  bool shouldReclip(_FractionClipper oldClipper) =>
      oldClipper.fraction != fraction;
}

/// The price list's colors and type for one width: the theme's primary
/// darkened for the bands and its accent for the buttons, the heading font
/// in capitals for titles and prices (`catalogPriceListCss`).
class _PriceListLook {
  _PriceListLook._({
    required this.phone,
    required this.wide,
    required this.navy,
    required this.paper,
    required this.line,
    required this.background,
    required this.ink,
    required this.mute,
    required this.primary,
    required this.accent,
    required this.onAccent,
    required this.heading,
    required this.body,
    required this.width,
  });

  factory _PriceListLook.of(BuildContext context, double width) {
    final scheme = Theme.of(context).colorScheme;
    return _PriceListLook._(
      phone: width < 600,
      wide: width >= 900,
      navy: Color.lerp(scheme.primary, Colors.black, 0.25)!,
      paper: Color.lerp(scheme.surface, scheme.primary, 0.05)!,
      line: Color.lerp(scheme.surface, scheme.onSurface, 0.13)!,
      background: scheme.surface,
      ink: scheme.onSurface,
      mute: scheme.onSurfaceVariant,
      primary: scheme.primary,
      accent: scheme.secondary,
      onAccent: scheme.onSecondary,
      heading: PublicStoreTheme.headingFont(context),
      body: PublicStoreTheme.bodyFont(context),
      width: width,
    );
  }

  final bool phone;
  final bool wide;
  final Color navy;
  final Color paper;
  final Color line;
  final Color background;
  final Color ink;
  final Color mute;
  final Color primary;
  final Color accent;
  final Color onAccent;
  final String heading;
  final String body;
  final double width;

  TextStyle _head(double size, {double height = 1.05, Color? color}) =>
      TextStyle(
        fontFamily: heading,
        fontWeight: FontWeight.w500,
        fontSize: size,
        height: height,
        color: color ?? ink,
      );

  TextStyle _body(
    double size, {
    double height = 1.5,
    FontWeight weight = FontWeight.w400,
    Color? color,
  }) =>
      TextStyle(
        fontFamily: body,
        fontWeight: weight,
        fontSize: size,
        height: height,
        color: color ?? ink,
      );

  TextStyle get crumb =>
      _body(14, height: 20 / 14, color: Colors.white.withValues(alpha: 0.66));
  TextStyle get eyebrow => _body(
        13,
        height: 1,
        weight: FontWeight.w600,
        color: Colors.white.withValues(alpha: 0.78),
      ).copyWith(letterSpacing: 13 * 0.16);
  TextStyle get heroTitle => _head(
        (width * 0.06).clamp(46, 76).toDouble(),
        height: 0.98,
        color: Colors.white,
      );
  TextStyle get heroIntro =>
      _body(phone ? 17 : 19, color: Colors.white.withValues(alpha: 0.82));
  TextStyle get ratingNumber =>
      _head(phone ? 40 : 58, height: 1, color: Colors.white).copyWith(
        fontFeatures: const [FontFeature.tabularFigures()],
      );
  TextStyle get ratingNote =>
      _body(15, height: 1.4, color: Colors.white.withValues(alpha: 0.74));
  TextStyle get sectionTitle => _head((width * 0.04).clamp(32, 44).toDouble());
  TextStyle get sectionIntro => _body(16, color: mute);
  TextStyle get planKicker => _body(
        12,
        height: 1.2,
        weight: FontWeight.w600,
        color: mute,
      ).copyWith(letterSpacing: 12 * 0.14);
  TextStyle get planName => _head(phone ? 28 : 32, height: 1.05);
  TextStyle get planNote => _body(15, height: 1.4, color: mute);
  TextStyle get planPrice => _head(phone ? 34 : 44, height: 1).copyWith(
        fontFeatures: const [FontFeature.tabularFigures()],
      );
  TextStyle get pill => _body(
        11,
        height: 1.2,
        weight: FontWeight.w700,
        color: onAccent,
      ).copyWith(letterSpacing: 1.1);
  TextStyle get include => _body(15, height: 1.45);
  TextStyle get includeDetail => _body(14, height: 1.45, color: mute);
  TextStyle get searchText => _body(16, height: 1.2);
  TextStyle get chip => _body(14, height: 1, weight: FontWeight.w600);
  TextStyle get chipCount => _body(
        14,
        height: 1,
        weight: FontWeight.w500,
        color: mute,
      ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
  TextStyle get groupTitle => _head(24, height: 1.15);
  TextStyle get groupCount => _body(15, height: 1.3, color: mute);
  TextStyle get rowName =>
      _body(phone ? 16 : 17, height: 1.35, weight: FontWeight.w500);
  TextStyle get rowPrice => _head(phone ? 18 : 20, height: 1).copyWith(
        fontFeatures: const [FontFeature.tabularFigures()],
      );
  TextStyle get empty => _body(17, color: mute);
  TextStyle get closingTitle => _head(
        (width * 0.046).clamp(36, 58).toDouble(),
        height: 1,
        color: Colors.white,
      );
  TextStyle get closingText =>
      _body(18, color: Colors.white.withValues(alpha: 0.8));
  TextStyle get button => _body(
        15,
        height: 1.2,
        weight: FontWeight.w700,
      ).copyWith(letterSpacing: 15 * 0.06);
  TextStyle get planButton => _body(
        14,
        height: 1.2,
        weight: FontWeight.w700,
      ).copyWith(letterSpacing: 14 * 0.04);
}
