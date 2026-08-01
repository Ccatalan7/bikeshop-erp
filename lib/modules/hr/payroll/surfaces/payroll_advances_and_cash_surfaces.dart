import 'package:flutter/material.dart';

import '../theme/payroll_tokens.dart';
import 'payroll_accent_action.dart';

// ═════════════════════════════════════════════════════════════════════════════
// 2d — Anticipos: superficie hermana de Nóminas, employee-first.
// Resumen por persona primero; ledger y reglas SOLO de la persona seleccionada.
// ═════════════════════════════════════════════════════════════════════════════
class AdvancePersonVM {
  const AdvancePersonVM({
    required this.id,
    required this.name,
    required this.initials,
    required this.avatarColor,
    required this.balanceLabel,
    required this.caption,
    required this.selected,
    required this.onTap,
  });
  final String id;
  final String name;
  final String initials;
  final Color avatarColor;
  final String balanceLabel; // "$27.500"
  final String caption; // "aplicable ahora" | "todo aplicado"
  final bool selected;
  final VoidCallback onTap;
}

class AdvanceLedgerRowVM {
  const AdvanceLedgerRowVM({
    required this.date,
    required this.reason,
    required this.amount,
    required this.applied,
    required this.balance,
    required this.statusLabel,
    required this.tone,
    this.detail,
  });
  final String date;
  final String reason;
  final String? detail;
  final String amount;
  final String applied;
  final String balance;
  final String statusLabel;
  final PayrollStateTone tone;
}

class PayrollAdvancesSurface extends StatelessWidget {
  const PayrollAdvancesSurface({
    super.key,
    required this.people,
    required this.selectedName,
    required this.selectedInitials,
    required this.selectedAvatar,
    required this.selectedBalance,
    required this.selectedCount,
    required this.ledger,
    required this.onNewAdvanceForSelectedPerson,
    this.selectedPersonActionUnavailableReason,
    this.hasMore = false,
    this.isLoadingMore = false,
    this.paginationError,
    this.onLoadMore,
  });

  final List<AdvancePersonVM> people;
  final String selectedName;
  final String selectedInitials;
  final Color selectedAvatar;
  final String selectedBalance;
  final String selectedCount; // "2 movimientos"
  final List<AdvanceLedgerRowVM> ledger;
  final VoidCallback? onNewAdvanceForSelectedPerson;
  final String? selectedPersonActionUnavailableReason;
  final bool hasMore;
  final bool isLoadingMore;
  final String? paginationError;
  final VoidCallback? onLoadMore;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < PayrollTokens.bpDesktop) {
          return _CompactAdvancesSurface(
            people: people,
            selectedName: selectedName,
            selectedInitials: selectedInitials,
            selectedAvatar: selectedAvatar,
            selectedBalance: selectedBalance,
            selectedCount: selectedCount,
            ledger: ledger,
            onNewAdvanceForSelectedPerson: onNewAdvanceForSelectedPerson,
            selectedPersonActionUnavailableReason:
                selectedPersonActionUnavailableReason,
            hasMore: hasMore,
            isLoadingMore: isLoadingMore,
            paginationError: paginationError,
            onLoadMore: onLoadMore,
          );
        }
        return _desktop(context, constraints);
      },
    );
  }

  Widget _desktop(BuildContext context, BoxConstraints constraints) {
    // 5h pone a las personas en **columna a la izquierda**, no en una tira
    // horizontal arriba. La tira funcionaba con tres personas de mock; con las
    // seis reales ya empujaba gente fuera de pantalla, y a nadie se le ocurre
    // scrollear en horizontal para buscar a alguien. La columna las muestra
    // todas y deja la cifra de cada una alineada con la de al lado, que es lo
    // que hace comparable «quién debe cuánto».
    const columnWidth = 250.0;
    final roomForRules = constraints.maxWidth >= 1180;

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SizedBox(
            width: columnWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.only(left: 2, bottom: 8),
                  child: Text(
                    'PERSONA',
                    style: PayrollVisualTokens.of(context).overline,
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    key: const PageStorageKey<String>(
                      'payroll-desktop-advance-people',
                    ),
                    primary: false,
                    itemCount: people.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) => _PersonCard(vm: people[i]),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(
                    child: _Ledger(
                  name: selectedName,
                  initials: selectedInitials,
                  avatar: selectedAvatar,
                  balance: selectedBalance,
                  count: selectedCount,
                  rows: ledger,
                  onNewAdvanceForSelectedPerson: onNewAdvanceForSelectedPerson,
                  actionUnavailableReason:
                      selectedPersonActionUnavailableReason,
                  hasMore: hasMore,
                  isLoadingMore: isLoadingMore,
                  paginationError: paginationError,
                  onLoadMore: onLoadMore,
                )),
                if (roomForRules) ...<Widget>[
                  const SizedBox(width: 14),
                  SizedBox(
                    width: 280,
                    child: SingleChildScrollView(
                      child: _RulesCard(initials: selectedInitials),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactAdvancesSurface extends StatelessWidget {
  const _CompactAdvancesSurface({
    required this.people,
    required this.selectedName,
    required this.selectedInitials,
    required this.selectedAvatar,
    required this.selectedBalance,
    required this.selectedCount,
    required this.ledger,
    required this.onNewAdvanceForSelectedPerson,
    this.selectedPersonActionUnavailableReason,
    required this.hasMore,
    required this.isLoadingMore,
    this.paginationError,
    this.onLoadMore,
  });

  final List<AdvancePersonVM> people;
  final String selectedName;
  final String selectedInitials;
  final Color selectedAvatar;
  final String selectedBalance;
  final String selectedCount;
  final List<AdvanceLedgerRowVM> ledger;
  final VoidCallback? onNewAdvanceForSelectedPerson;
  final String? selectedPersonActionUnavailableReason;
  final bool hasMore;
  final bool isLoadingMore;
  final String? paginationError;
  final VoidCallback? onLoadMore;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    return ListView(
      key: const PageStorageKey<String>('payroll-mobile-advances'),
      padding: const EdgeInsets.fromLTRB(13, 13, 13, 20),
      children: [
        Text('PERSONA', style: visual.overline),
        const SizedBox(height: 8),
        _CompactAdvancePersonChooser(people: people),
        const SizedBox(height: 13),
        Container(
          decoration: BoxDecoration(
            color: visual.surface,
            borderRadius: BorderRadius.circular(PayrollTokens.rPanel),
            border: Border.all(color: visual.borderStrong),
            boxShadow: visual.raised,
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(13, 12, 13, 11),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: selectedAvatar,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        selectedInitials,
                        style: visual.avatarInitials(11),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            selectedName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: visual.sectionTitle,
                          ),
                          Text(
                            selectedCount,
                            style: visual.bodyS.copyWith(
                              fontSize: 10.5,
                              color: visual.inkFaint,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('VIGENTE', style: visual.overline),
                        Text(
                          selectedBalance,
                          style: visual.numCard.copyWith(fontSize: 17),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: visual.border),
              for (var index = 0; index < ledger.length; index++)
                _CompactLedgerRow(
                  vm: ledger[index],
                  isLast: index == ledger.length - 1,
                ),
              if (hasMore || isLoadingMore || paginationError != null)
                _AdvanceLedgerPaginationControl(
                  compact: true,
                  loading: isLoadingMore,
                  error: paginationError,
                  onPressed:
                      hasMore || paginationError != null ? onLoadMore : null,
                ),
              if (selectedPersonActionUnavailableReason != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(13, 11, 13, 0),
                  child: Text(
                    selectedPersonActionUnavailableReason!,
                    key: const ValueKey<String>(
                      'payroll-advance-person-action-unavailable',
                    ),
                    style: visual.bodyS.copyWith(
                      fontSize: 11,
                      height: 1.4,
                      color: visual.inkFaint,
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(11),
                child: Semantics(
                  button: true,
                  enabled: onNewAdvanceForSelectedPerson != null,
                  label: 'Registrar anticipo para $selectedName',
                  excludeSemantics: true,
                  child: Material(
                    color: onNewAdvanceForSelectedPerson == null
                        ? visual.surfaceSunken
                        : visual.accentSoft,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(PayrollTokens.rField),
                      side: BorderSide(color: visual.accentBorder),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: onNewAdvanceForSelectedPerson,
                      mouseCursor: SystemMouseCursors.click,
                      hoverColor: visual.accent.withValues(alpha: 0.06),
                      focusColor: visual.accent.withValues(alpha: 0.12),
                      child: Container(
                        height: PayrollTokens.touchMobile,
                        alignment: Alignment.center,
                        child: Text(
                          'Registrar anticipo para $selectedName',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: visual.labelStrong.copyWith(
                            fontSize: 12,
                            color: onNewAdvanceForSelectedPerson == null
                                ? visual.inkFaint
                                : visual.accent,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _CompactAdvanceRules(initials: selectedInitials),
      ],
    );
  }
}

class _CompactAdvancePersonChooser extends StatelessWidget {
  const _CompactAdvancePersonChooser({required this.people});

  final List<AdvancePersonVM> people;

  @override
  Widget build(BuildContext context) {
    var selected = people.first;
    for (final person in people) {
      if (person.selected) {
        selected = person;
        break;
      }
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final searchable = people.length > 7;
        final menuHeight =
            (MediaQuery.sizeOf(context).height * 0.48).clamp(220.0, 340.0);
        return KeyedSubtree(
          key: const ValueKey<String>('payroll-advance-person-picker'),
          child: DropdownMenu<String>(
            key: ValueKey<String>(
              'payroll-advance-person-picker-${selected.id}',
            ),
            width: constraints.maxWidth,
            menuHeight: menuHeight,
            initialSelection: selected.id,
            label: const Text('Trabajador'),
            helperText:
                searchable ? 'Busca por nombre si la lista es larga.' : null,
            enableFilter: searchable,
            enableSearch: searchable,
            requestFocusOnTap: searchable,
            dropdownMenuEntries: <DropdownMenuEntry<String>>[
              for (final person in people)
                DropdownMenuEntry<String>(
                  value: person.id,
                  label:
                      '${person.name} · ${person.balanceLabel} ${person.caption}',
                ),
            ],
            onSelected: (id) {
              if (id == null || id == selected.id) return;
              for (final person in people) {
                if (person.id == id) {
                  person.onTap();
                  return;
                }
              }
            },
          ),
        );
      },
    );
  }
}

class _CompactLedgerRow extends StatelessWidget {
  const _CompactLedgerRow({required this.vm, required this.isLast});

  final AdvanceLedgerRowVM vm;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        border: Border(
          bottom: isLast ? BorderSide.none : BorderSide(color: visual.border),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(vm.date, style: visual.monoM.copyWith(fontSize: 11)),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      vm.reason,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: visual.bodyM.copyWith(fontSize: 12),
                    ),
                    if (vm.detail != null)
                      Text(
                        vm.detail!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: visual.bodyS.copyWith(
                          fontSize: 10,
                          color: visual.inkFaint,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: vm.tone.soft,
                  borderRadius: BorderRadius.circular(PayrollTokens.rPill),
                  border: Border.all(color: vm.tone.border),
                ),
                child: Text(
                  vm.statusLabel,
                  style: visual.labelStrong.copyWith(
                    fontSize: 9,
                    color: vm.tone.fg,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              Expanded(
                child: _CompactLedgerFigure(label: 'MONTO', value: vm.amount),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _CompactLedgerFigure(
                  label: 'APLICADO',
                  value: vm.applied,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _CompactLedgerFigure(
                  label: 'VIGENTE',
                  value: vm.balance,
                  emphasis: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CompactLedgerFigure extends StatelessWidget {
  const _CompactLedgerFigure({
    required this.label,
    required this.value,
    this.emphasis = false,
  });

  final String label;
  final String value;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: visual.overline.copyWith(fontSize: 8.5)),
        const SizedBox(height: 2),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: visual.monoM.copyWith(
            fontSize: 11.5,
            fontWeight: emphasis ? FontWeight.w700 : FontWeight.w500,
            color: emphasis ? visual.accent : visual.inkMuted,
          ),
        ),
      ],
    );
  }
}

class _CompactAdvanceRules extends StatelessWidget {
  const _CompactAdvanceRules({required this.initials});

  final String initials;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    return Container(
      decoration: BoxDecoration(
        color: visual.surface,
        borderRadius: BorderRadius.circular(PayrollTokens.rPanel),
        border: Border.all(color: visual.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 13),
        childrenPadding: const EdgeInsets.fromLTRB(13, 0, 13, 12),
        // Removes the ExpansionTile divider without mounting a Theme island.
        shape: const Border(),
        collapsedShape: const Border(),
        iconColor: visual.accent,
        collapsedIconColor: visual.inkFaint,
        title: Text(
          'Cómo funciona el saldo de $initials',
          style: visual.sectionTitle.copyWith(fontSize: 12.5),
        ),
        children: [
          for (var index = 0; index < _RulesCard._rules.length; index++) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${index + 1}',
                  style: visual.overline.copyWith(
                    fontSize: 10,
                    color: visual.accent,
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    _RulesCard._rules[index],
                    style: visual.bodyS.copyWith(
                      fontSize: 11.5,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
            if (index != _RulesCard._rules.length - 1)
              const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class _PersonCard extends StatelessWidget {
  const _PersonCard({required this.vm});
  final AdvancePersonVM vm;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    final borderRadius = BorderRadius.circular(PayrollTokens.rPanel);
    return Semantics(
      key: ValueKey<String>('payroll-advance-person-card-${vm.id}'),
      button: true,
      selected: vm.selected,
      label: '${vm.name}, saldo ${vm.balanceLabel}',
      excludeSemantics: true,
      child: Material(
        color: vm.selected ? visual.surface : visual.surfaceSunken,
        shape: RoundedRectangleBorder(
          borderRadius: borderRadius,
          side: BorderSide(
            color: vm.selected ? visual.accent : visual.border,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: vm.onTap,
          mouseCursor: SystemMouseCursors.click,
          borderRadius: borderRadius,
          hoverColor: visual.accent.withValues(alpha: 0.06),
          focusColor: visual.accent.withValues(alpha: 0.12),
          child: Container(
            constraints:
                const BoxConstraints(minHeight: PayrollTokens.touchMobile),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              boxShadow: vm.selected
                  ? <BoxShadow>[
                      BoxShadow(
                          color: visual.accent.withValues(alpha: 0.12),
                          spreadRadius: 3,
                          blurRadius: 0),
                    ]
                  : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                          color: vm.avatarColor, shape: BoxShape.circle),
                      alignment: Alignment.center,
                      child:
                          Text(vm.initials, style: visual.avatarInitials(10.5)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(vm.name,
                          style: visual.cardTitle.copyWith(
                              color:
                                  vm.selected ? visual.ink : visual.inkMuted),
                          overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
                const SizedBox(height: 9),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: <Widget>[
                    Text(vm.balanceLabel, style: visual.numCard),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        vm.caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: visual.bodyS.copyWith(
                          fontSize: 10,
                          color: visual.inkFaint,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Ledger extends StatelessWidget {
  const _Ledger({
    required this.name,
    required this.initials,
    required this.avatar,
    required this.balance,
    required this.count,
    required this.rows,
    required this.onNewAdvanceForSelectedPerson,
    this.actionUnavailableReason,
    required this.hasMore,
    required this.isLoadingMore,
    this.paginationError,
    this.onLoadMore,
  });
  final String name;
  final String initials;
  final Color avatar;
  final String balance;
  final String count;
  final List<AdvanceLedgerRowVM> rows;
  final VoidCallback? onNewAdvanceForSelectedPerson;
  final String? actionUnavailableReason;
  final bool hasMore;
  final bool isLoadingMore;
  final String? paginationError;
  final VoidCallback? onLoadMore;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    return Container(
      decoration: BoxDecoration(
        color: visual.surface,
        borderRadius: BorderRadius.circular(PayrollTokens.rPanel),
        border: Border.all(color: visual.borderStrong),
        boxShadow: visual.raised,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Container(
            height: 46,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: visual.border)),
            ),
            child: Row(
              children: <Widget>[
                Container(
                  width: 26,
                  height: 26,
                  decoration:
                      BoxDecoration(color: avatar, shape: BoxShape.circle),
                  alignment: Alignment.center,
                  child: Text(initials, style: visual.avatarInitials(10)),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Text(name,
                          style: visual.sectionTitle.copyWith(fontSize: 13),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      // 5h pone la cifra JUNTO a la persona, no en la otra
                      // punta de la fila: «saldo vigente $X» se lee como una
                      // frase sobre ella. El número grande ya vive en su
                      // tarjeta de la columna, así que repetirlo a la derecha
                      // sólo ocupaba el lugar donde va la acción.
                      Text(
                        'saldo vigente $balance · $count',
                        style: visual.bodyS
                            .copyWith(fontSize: 11, color: visual.inkFaint),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 200),
                  child: SizedBox(
                    height: 30,
                    // La etiqueta visible es la de 5h y no repite el nombre,
                    // que está 200 px a la izquierda. Quien no ve la pantalla
                    // no tiene ese contexto, así que la semántica sí lo dice.
                    child: Semantics(
                      button: true,
                      enabled: onNewAdvanceForSelectedPerson != null,
                      label: 'Registrar anticipo para $name',
                      excludeSemantics: true,
                      child: OutlinedButton.icon(
                        onPressed: onNewAdvanceForSelectedPerson,
                        icon: const Icon(Icons.add_rounded, size: 15),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: visual.inkMuted,
                          backgroundColor: visual.surface,
                          padding: const EdgeInsets.symmetric(horizontal: 11),
                          side: BorderSide(color: visual.borderStrong),
                          shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(PayrollTokens.rField),
                          ),
                        ),
                        label: Text(
                          'Nuevo para esta persona',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: visual.label.copyWith(fontSize: 11),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(
            height: PayrollTokens.tableColsH,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: visual.surfaceSunken,
              border: Border(bottom: BorderSide(color: visual.border)),
            ),
            child: Row(
              children: <Widget>[
                SizedBox(
                    width: 66, child: Text('FECHA', style: visual.overline)),
                const SizedBox(width: 10),
                Expanded(child: Text('MOTIVO', style: visual.overline)),
                const SizedBox(width: 10),
                SizedBox(
                    width: 84,
                    child: Text('MONTO',
                        textAlign: TextAlign.right, style: visual.overline)),
                const SizedBox(width: 10),
                SizedBox(
                    width: 84,
                    child: Text('APLICADO',
                        textAlign: TextAlign.right, style: visual.overline)),
                const SizedBox(width: 10),
                SizedBox(
                    width: 96,
                    child: Text('VIGENTE',
                        textAlign: TextAlign.right,
                        style: visual.overline.copyWith(color: visual.accent))),
                const SizedBox(width: 10),
                SizedBox(
                    width: 112, child: Text('ESTADO', style: visual.overline)),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              key: const ValueKey<String>('payroll-advance-ledger-scroll'),
              primary: false,
              itemCount: rows.length +
                  ((hasMore || isLoadingMore || paginationError != null)
                      ? 1
                      : 0),
              itemBuilder: (context, index) {
                if (index == rows.length) {
                  return _AdvanceLedgerPaginationControl(
                    compact: false,
                    loading: isLoadingMore,
                    error: paginationError,
                    onPressed:
                        hasMore || paginationError != null ? onLoadMore : null,
                  );
                }
                return _LedgerRow(vm: rows[index]);
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            decoration: BoxDecoration(
              color: visual.surfaceSunken,
              border: Border(top: BorderSide(color: visual.border)),
            ),
            // 5h reserva este pie para explicar **vigente**, que es la palabra
            // de la que cuelga todo el submódulo. Antes decía sólo dónde se
            // consume el saldo; lo que no decía —y es lo que la gente pregunta—
            // es que aplicarlo NO es automático y que se puede deshacer
            // mientras la semana siga abierta.
            child: actionUnavailableReason != null
                ? Text(
                    actionUnavailableReason!,
                    key: const ValueKey<String>(
                      'payroll-advance-person-action-unavailable',
                    ),
                    style: visual.bodyS.copyWith(
                      fontSize: 11,
                      color: visual.inkFaint,
                    ),
                  )
                : Text.rich(
                    TextSpan(
                      style: visual.bodyS
                          .copyWith(fontSize: 11, color: visual.inkMuted),
                      children: <InlineSpan>[
                        TextSpan(
                          text: 'Vigente',
                          style: visual.labelStrong.copyWith(
                            fontSize: 11,
                            color: visual.ink,
                          ),
                        ),
                        const TextSpan(
                          text: ' es la palabra que manda: un anticipo existe '
                              'como saldo a nombre de la persona hasta que un '
                              'pago lo aplica. Aplicarlo es una decisión del '
                              'pago, nunca automática, y se puede deshacer '
                              'mientras la semana no esté confirmada.',
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _AdvanceLedgerPaginationControl extends StatelessWidget {
  const _AdvanceLedgerPaginationControl({
    required this.compact,
    required this.loading,
    required this.error,
    required this.onPressed,
  });

  final bool compact;
  final bool loading;
  final String? error;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    final actionLabel = loading
        ? 'Cargando movimientos…'
        : error == null
            ? 'Cargar movimientos anteriores'
            : 'Reintentar cargar movimientos';

    return Container(
      key: ValueKey<String>(
        compact
            ? 'payroll-advance-load-more-compact'
            : 'payroll-advance-load-more',
      ),
      padding: EdgeInsets.fromLTRB(
        compact ? 13 : 16,
        compact ? 11 : 12,
        compact ? 13 : 16,
        compact ? 11 : 12,
      ),
      decoration: BoxDecoration(
        color: visual.surfaceSunken,
        border: Border(top: BorderSide(color: visual.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (error != null) ...[
            Semantics(
              container: true,
              liveRegion: true,
              label: 'Error al cargar movimientos anteriores: $error',
              child: ExcludeSemantics(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.error_outline_rounded,
                      size: 17,
                      color: visual.dangerFg,
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        error!,
                        key: const ValueKey<String>(
                          'payroll-advance-pagination-error',
                        ),
                        style: visual.bodyS.copyWith(
                          color: visual.dangerFg,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 9),
          ],
          Align(
            child: SizedBox(
              width: compact ? double.infinity : 320,
              height: compact ? PayrollTokens.touchMobile : 40,
              child: OutlinedButton.icon(
                key: const ValueKey<String>(
                  'payroll-advance-pagination-action',
                ),
                onPressed: loading ? null : onPressed,
                icon: loading
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: visual.accent,
                        ),
                      )
                    : Icon(
                        error == null
                            ? Icons.expand_more_rounded
                            : Icons.refresh_rounded,
                        size: 18,
                      ),
                label: Text(actionLabel),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LedgerRow extends StatelessWidget {
  const _LedgerRow({required this.vm});
  final AdvanceLedgerRowVM vm;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 50),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: visual.border)),
      ),
      child: Row(
        children: <Widget>[
          SizedBox(
              width: 66,
              child: Text(vm.date, style: visual.monoM.copyWith(fontSize: 11))),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  vm.reason,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: visual.bodyM.copyWith(fontSize: 12),
                ),
                if (vm.detail != null)
                  Text(
                    vm.detail!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: visual.bodyS.copyWith(
                      fontSize: 9.5,
                      color: visual.inkFaint,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
              width: 84,
              child: Text(vm.amount,
                  textAlign: TextAlign.right,
                  style:
                      visual.monoM.copyWith(fontSize: 12, color: visual.ink))),
          const SizedBox(width: 10),
          SizedBox(
              width: 84,
              child: Text(vm.applied,
                  textAlign: TextAlign.right,
                  style: visual.monoM
                      .copyWith(fontSize: 12, color: visual.inkFaint))),
          const SizedBox(width: 10),
          SizedBox(
              width: 96,
              child: Text(vm.balance,
                  textAlign: TextAlign.right,
                  style: visual.numRow.copyWith(fontSize: 13))),
          const SizedBox(width: 10),
          SizedBox(
            width: 112,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: vm.tone.soft,
                  borderRadius: BorderRadius.circular(PayrollTokens.rPill),
                  border: Border.all(color: vm.tone.border),
                ),
                child: Text(vm.statusLabel,
                    style: visual.labelStrong
                        .copyWith(fontSize: 9.5, color: vm.tone.fg)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RulesCard extends StatelessWidget {
  const _RulesCard({required this.initials});
  final String initials;

  static const List<String> _rules = <String>[
    'Nace sin semana: es plata entregada a la persona.',
    'Aparece como aplicable al pagar cualquier semana.',
    'No modifica horas ni total calculado: baja el dinero nuevo.',
    'Se puede aplicar parcial y en varias semanas.',
  ];

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
      decoration: BoxDecoration(
        color: visual.surface,
        borderRadius: BorderRadius.circular(PayrollTokens.rPanel),
        border: Border.all(color: visual.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Cómo funciona el saldo de $initials',
              style: visual.sectionTitle.copyWith(fontSize: 12.5)),
          const SizedBox(height: 10),
          for (int i = 0; i < _rules.length; i++) ...<Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text('${i + 1}',
                      style: visual.overline
                          .copyWith(fontSize: 10, color: visual.accent)),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(_rules[i],
                      style:
                          visual.bodyS.copyWith(fontSize: 11.5, height: 1.5)),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],
          Divider(height: 13, color: visual.border),
          Text.rich(
            TextSpan(
              style: visual.bodyS
                  .copyWith(fontSize: 11, height: 1.5, color: visual.inkFaint),
              children: <InlineSpan>[
                const TextSpan(
                    text:
                        'En la semana de nómina no se ve este ledger: solo el '),
                TextSpan(
                    text: 'saldo vigente',
                    style: TextStyle(
                        fontWeight: FontWeight.w600, color: visual.inkMuted)),
                const TextSpan(text: ' como línea aplicable.'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// 2e — Efectivo compacto (390/372 de ancho). Una persona, una ecuación, un CTA.
// Al confirmar NO autoavanza: ofrece siguiente o volver a la cola.
// ═════════════════════════════════════════════════════════════════════════════
class PayrollCashSurface extends StatelessWidget {
  const PayrollCashSurface({
    super.key,
    required this.weekLabel,
    required this.personName,
    required this.initials,
    required this.avatarColor,
    required this.hoursAndMethod,
    required this.earnedLabel,
    required this.advancesLabel,
    required this.deliverLabel,
    required this.availableAdvanceLabel,
    required this.dateLabel,
    required this.deliveredBy,
    required this.onClose,
    this.onApplyAdvance,
    required this.onConfirm,
    this.onPickDate,
    this.confirmed = false,
    this.weekRemainingLabel = '',
    this.weekBlockedReason = '',
    this.nextCashLabel = '',
    this.onNextCash,
    this.onBackToQueue,
  });

  final String weekLabel;
  final String personName;
  final String initials;
  final Color avatarColor;
  final String hoursAndMethod; // "33,0 h · efectivo"
  final String earnedLabel;
  final String advancesLabel;
  final String deliverLabel; // "$95.000"
  final String availableAdvanceLabel; // "$40.000"
  final String dateLabel;
  final String deliveredBy;
  final VoidCallback onClose;
  final VoidCallback? onApplyAdvance;
  final VoidCallback onConfirm;
  final VoidCallback? onPickDate;

  final bool confirmed;
  final String weekRemainingLabel;
  final String weekBlockedReason;
  final String nextCashLabel;
  final VoidCallback? onNextCash;
  final VoidCallback? onBackToQueue;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _CashHeader(
          title: confirmed ? 'Entrega registrada' : 'Confirmar efectivo',
          meta: '$weekLabel · $personName',
          onClose: onClose,
        ),
        Expanded(
          child: confirmed
              ? _confirmedState(visual)
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: <Widget>[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: visual.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: visual.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                    color: avatarColor, shape: BoxShape.circle),
                                alignment: Alignment.center,
                                child: Text(initials,
                                    style: visual.avatarInitials(15)),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Text(personName,
                                        style: visual.recordTitle.copyWith(
                                            fontSize: 15, color: visual.ink)),
                                    Text(hoursAndMethod,
                                        style: visual.monoS
                                            .copyWith(fontSize: 11)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 15),
                          // Ecuación siempre visible, incluso con anticipos en $0.
                          Container(
                            padding: const EdgeInsets.all(13),
                            decoration: BoxDecoration(
                              color: visual.surfaceSunken,
                              borderRadius:
                                  BorderRadius.circular(PayrollTokens.rPanel),
                              border: Border.all(color: visual.border),
                            ),
                            // 5f desglosa con rótulos en vez de dejar una
                            // ecuación cruda: el que entrega el billete tiene
                            // que poder leer de dónde sale la cifra sin
                            // reconstruir la resta.
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: <Widget>[
                                _CashBreakdownLine(
                                  label: 'Total de la semana',
                                  value: earnedLabel,
                                ),
                                const SizedBox(height: 3),
                                _CashBreakdownLine(
                                  label: 'Anticipo aplicado',
                                  value: advancesLabel,
                                  credit: true,
                                ),
                                const SizedBox(height: 7),
                                Divider(height: 1, color: visual.border),
                                const SizedBox(height: 7),
                                Row(
                                  children: <Widget>[
                                    Expanded(
                                      child: Text(
                                        'A entregar en mano',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: visual.bodyM
                                            .copyWith(fontSize: 12.5),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Text(deliverLabel,
                                        style: visual.numBar.copyWith(
                                            fontSize: 22,
                                            color: visual.accent)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          // Aplicar el anticipo es lo esperado, pero es una
                          // DECISIÓN: 5f insiste en decir qué pasa si se
                          // desmarca, porque el saldo no se pierde — vuelve a
                          // quedar disponible para otra semana.
                          Text.rich(
                            TextSpan(
                              style: visual.bodyS.copyWith(
                                  fontSize: 10.5, color: visual.inkFaint),
                              children: <InlineSpan>[
                                const TextSpan(
                                  text: 'Descontar el anticipo es lo esperado, '
                                      'pero es una ',
                                ),
                                TextSpan(
                                    text: 'decisión',
                                    style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: visual.inkMuted)),
                                TextSpan(
                                    text: ': desmarcarlo entrega $earnedLabel '
                                        'completos y el anticipo queda vigente '
                                        'para otra semana. Tiene '),
                                TextSpan(
                                    text: availableAdvanceLabel,
                                    style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: visual.inkMuted)),
                                const TextSpan(
                                    text: ' de anticipo vigente sin aplicar.'),
                              ],
                            ),
                          ),
                          const SizedBox(height: 11),
                          if (onApplyAdvance != null)
                            Material(
                              color: visual.accentSoft,
                              shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(PayrollTokens.rPanel),
                                side: BorderSide(
                                  color: visual.accentBorder,
                                ),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: InkWell(
                                onTap: onApplyAdvance,
                                mouseCursor: SystemMouseCursors.click,
                                child: Container(
                                  height: PayrollTokens.touchMobile - 4,
                                  alignment: Alignment.center,
                                  child: Text(
                                    'Aplicar anticipo de $availableAdvanceLabel',
                                    style: visual.labelStrong.copyWith(
                                      fontSize: 12.5,
                                      color: visual.accent,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 13),
                    Container(
                      padding: const EdgeInsets.all(15),
                      decoration: BoxDecoration(
                        color: visual.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: visual.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Text('CONFIRMACIÓN MANUAL', style: visual.overline),
                          const SizedBox(height: 11),
                          GestureDetector(
                            onTap: onPickDate,
                            child: _MobileField(
                                label: 'Fecha', value: dateLabel, mono: true),
                          ),
                          const SizedBox(height: 10),
                          // «Entregado por» y no «Registrado por»: sin cartola,
                          // el nombre de quien puso el billete en la mano es
                          // la única traza que queda.
                          _MobileField(
                              label: 'Entregado por', value: deliveredBy),
                        ],
                      ),
                    ),
                    const SizedBox(height: 13),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: visual.warningSoft,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: visual.warningBorder),
                      ),
                      child: Text.rich(
                        TextSpan(
                          style: visual.bodyS.copyWith(
                              fontSize: 11.5,
                              height: 1.5,
                              color: visual.warningFg),
                          // 5f: esto no es una advertencia, es la razón de
                          // existir de la pantalla. Explica por qué el
                          // efectivo se pregunta a mano y nunca lo resuelve el
                          // OCR — sin cartola, esta confirmación ES el
                          // comprobante.
                          children: const <InlineSpan>[
                            TextSpan(text: 'El efectivo no tiene cartola: '),
                            TextSpan(
                                text: 'esta confirmación es el comprobante',
                                style: TextStyle(fontWeight: FontWeight.w600)),
                            TextSpan(
                                text: '. Queda con tu nombre, fecha y hora en '
                                    'la bitácora, y por eso la conciliación '
                                    'nunca la genera sola — la pregunta de '
                                    'efectivo es siempre manual.'),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
        ),
        if (!confirmed)
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
            decoration: BoxDecoration(
              color: visual.surface,
              border: Border(top: BorderSide(color: visual.borderStrong)),
            ),
            child: PayrollAccentAction(
              label: 'Confirmar entrega $deliverLabel',
              onTap: onConfirm,
              height: 50,
              fontSize: 14,
              borderRadius: 11,
            ),
          ),
      ],
    );
  }

  Widget _confirmedState(PayrollVisualTokens visual) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          decoration: BoxDecoration(
            color: visual.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: visual.successBorder),
          ),
          child: Column(
            children: <Widget>[
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: visual.successSoft,
                  shape: BoxShape.circle,
                  border: Border.all(color: visual.successBorder),
                ),
                alignment: Alignment.center,
                child: Icon(Icons.check, size: 20, color: visual.successFg),
              ),
              const SizedBox(height: 11),
              Text(deliverLabel, style: visual.numBar.copyWith(fontSize: 22)),
              const SizedBox(height: 3),
              Text('entregados en efectivo · $dateLabel · $deliveredBy',
                  textAlign: TextAlign.center,
                  style: visual.bodyS
                      .copyWith(fontSize: 11.5, color: visual.inkFaint)),
            ],
          ),
        ),
        const SizedBox(height: 13),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
          decoration: BoxDecoration(
            color: visual.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: visual.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text('QUÉ PASÓ CON LA SEMANA', style: visual.overline),
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  Text('Falta pagar',
                      style: visual.bodyM.copyWith(fontSize: 12)),
                  const Spacer(),
                  Text(weekRemainingLabel,
                      style: visual.numCard.copyWith(fontSize: 15)),
                ],
              ),
              const SizedBox(height: 11),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
                decoration: BoxDecoration(
                  color: visual.warningSoft,
                  borderRadius: BorderRadius.circular(PayrollTokens.rField),
                  border: Border.all(color: visual.warningBorder),
                ),
                child: Text(weekBlockedReason,
                    style: visual.bodyS.copyWith(
                        fontSize: 11, height: 1.45, color: visual.warningFg)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 13),
        Text('¿QUÉ SIGUE?', style: visual.overline),
        const SizedBox(height: 9),
        if (onNextCash != null) ...[
          _NextChoice(
            label: nextCashLabel,
            actionLabel: 'Confirmar siguiente',
            onTap: onNextCash,
          ),
          const SizedBox(height: 9),
        ] else ...[
          _CompletionNote(label: nextCashLabel),
          const SizedBox(height: 9),
        ],
        _NextChoice(
          label: 'Volver a Nóminas',
          actionLabel: 'Volver',
          onTap: onBackToQueue,
        ),
        const SizedBox(height: 14),
        Text('Nada avanza solo: eliges tú el siguiente paso.',
            textAlign: TextAlign.center,
            style:
                visual.bodyS.copyWith(fontSize: 10.5, color: visual.inkFaint)),
      ],
    );
  }
}

class _CashHeader extends StatelessWidget {
  const _CashHeader({
    required this.title,
    required this.meta,
    required this.onClose,
  });

  final String title;
  final String meta;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    return Container(
      height: 62,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: visual.shell,
        border: Border(
          bottom: BorderSide(color: visual.tabHairline),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            key: const ValueKey<String>('payroll-cash-close'),
            onPressed: onClose,
            tooltip: 'Volver a Nóminas',
            style: IconButton.styleFrom(
              foregroundColor: visual.onShell,
              hoverColor: visual.onShell.withValues(alpha: 0.08),
              focusColor: visual.brand.withValues(alpha: 0.14),
            ),
            icon: const Icon(Icons.arrow_back_rounded, size: 19),
          ),
          const SizedBox(width: 2),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: visual.moduleTitle.copyWith(fontSize: 14),
                ),
                const SizedBox(height: 2),
                Text(
                  meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: visual.monoS.copyWith(
                    color: visual.onShellMuted,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Una línea `concepto … cifra` del desglose de efectivo (5f).
class _CashBreakdownLine extends StatelessWidget {
  const _CashBreakdownLine({
    required this.label,
    required this.value,
    this.credit = false,
  });

  final String label;
  final String value;

  /// Plata que ya salió antes: se lee en verde, como en el resto del módulo.
  final bool credit;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: visual.bodyS.copyWith(
              fontSize: 11.5,
              color: visual.inkMuted,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          value,
          maxLines: 1,
          style: visual.monoM.copyWith(
            fontSize: 12,
            color: credit ? visual.successFg : visual.ink,
          ),
        ),
      ],
    );
  }
}

class _MobileField extends StatelessWidget {
  const _MobileField({
    required this.label,
    required this.value,
    this.mono = false,
  });
  final String label;
  final String value;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    return Container(
      height: PayrollTokens.touchMobile,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(PayrollTokens.rPanel),
        border: Border.all(color: visual.border),
      ),
      child: Row(
        children: <Widget>[
          Text(label,
              style:
                  visual.bodyS.copyWith(fontSize: 11, color: visual.inkFaint)),
          const Spacer(),
          Flexible(
              child: Text(value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: mono
                      ? visual.monoM.copyWith(fontSize: 13, color: visual.ink)
                      : visual.bodyM.copyWith(fontSize: 13))),
        ],
      ),
    );
  }
}

class _CompletionNote extends StatelessWidget {
  const _CompletionNote({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 52),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
      decoration: BoxDecoration(
        color: visual.successSoft,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: visual.successBorder),
      ),
      child: Row(
        children: [
          Icon(
            Icons.check_circle_outline_rounded,
            size: 18,
            color: visual.successFg,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              label,
              style: visual.bodyM.copyWith(
                fontSize: 12.5,
                color: visual.successFg,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NextChoice extends StatelessWidget {
  const _NextChoice({
    required this.label,
    required this.actionLabel,
    this.onTap,
  });
  final String label;
  final String actionLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    return Semantics(
      button: true,
      label: '$actionLabel: $label',
      excludeSemantics: true,
      child: Material(
        color: visual.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(11),
          side: BorderSide(color: visual.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          mouseCursor: onTap == null
              ? SystemMouseCursors.basic
              : SystemMouseCursors.click,
          child: SizedBox(
            height: 52,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 13),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      label,
                      style: visual.bodyM.copyWith(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    actionLabel,
                    style: visual.label.copyWith(
                      fontSize: 12,
                      color: visual.accent,
                    ),
                  ),
                  const SizedBox(width: 3),
                  Icon(
                    Icons.arrow_forward_rounded,
                    size: 15,
                    color: visual.accent,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
