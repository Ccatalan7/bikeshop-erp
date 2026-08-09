import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../shared/themes/vinabike_theme_roles.dart';
import '../../../shared/widgets/branded_loading.dart';
import '../../../shared/widgets/main_layout.dart';
import '../../../shared/widgets/vb_notice.dart';
import '../../../shared/widgets/vb_status_badge.dart';
import '../../../shared/widgets/vb_sub_tabs.dart';
import '../models/supplier_foundation.dart';
import '../services/supplier_relationship_service.dart';

enum SupplierHubTab { explore, directory }

enum _SupplierDirectoryState { all, active, inactive }

enum _SupplierAttentionScope {
  unclassified,
  missingAccountingPolicy,
  validationIncident,
}

abstract interface class SupplierHubDataSource {
  Future<List<SupplierProfile>> listSupplierProfiles();

  Future<SupplierClassificationCatalog> getClassificationCatalog();
}

class SupplierRelationshipHubDataSource implements SupplierHubDataSource {
  const SupplierRelationshipHubDataSource(this.service);

  final SupplierRelationshipService service;

  @override
  Future<List<SupplierProfile>> listSupplierProfiles() =>
      service.listSupplierProfiles();

  @override
  Future<SupplierClassificationCatalog> getClassificationCatalog() =>
      service.getClassificationCatalog();
}

/// Canonical supplier entry surface.
///
/// Design source: `ERP Bikeshop UI Mockups`, supplier turns T17/T17.1. The
/// surface deliberately has two modes: a visual operational entry and the
/// complete directory. Categories are role-backed and may overlap; they are
/// not mutually exclusive supplier types.
class SupplierListPage extends StatefulWidget {
  const SupplierListPage({
    super.key,
    this.dataSource,
    this.includeWorkspaceShell = true,
  });

  final SupplierHubDataSource? dataSource;
  final bool includeWorkspaceShell;

  @override
  State<SupplierListPage> createState() => _SupplierListPageState();
}

class _SupplierListPageState extends State<SupplierListPage> {
  static const _featuredCategories = <_SupplierCategoryPresentation>[
    _SupplierCategoryPresentation(
      code: 'goods_vendor',
      fallbackLabel: 'Proveedor de bienes',
      description: 'Repuestos, bicicletas y todo lo que entra al inventario',
      asset: 'assets/images/supplier_categories/goods-inventory.webp',
      icon: Icons.inventory_2_outlined,
    ),
    _SupplierCategoryPresentation(
      code: 'digital_platform',
      fallbackLabel: 'Plataforma digital',
      description: 'Dominios, hosting y cuentas en línea',
      asset: 'assets/images/supplier_categories/digital-services.webp',
      icon: Icons.language_outlined,
    ),
    _SupplierCategoryPresentation(
      code: 'utility_provider',
      fallbackLabel: 'Servicios básicos',
      description: 'Luz, agua y otros suministros del local',
      asset: 'assets/images/supplier_categories/utilities.webp',
      icon: Icons.electric_bolt_outlined,
    ),
    _SupplierCategoryPresentation(
      code: 'logistics_provider',
      fallbackLabel: 'Transporte y logística',
      description: 'Fletes, despachos y encomiendas',
      asset: 'assets/images/supplier_categories/logistics.webp',
      icon: Icons.local_shipping_outlined,
    ),
    _SupplierCategoryPresentation(
      code: 'landlord',
      fallbackLabel: 'Arrendador',
      description: 'Quien arrienda el local',
      asset: 'assets/images/supplier_categories/lease-landlord.webp',
      icon: Icons.home_work_outlined,
    ),
    _SupplierCategoryPresentation(
      code: 'government_authority',
      fallbackLabel: 'Organismo público',
      description: 'Impuestos y trámites con el Estado',
      asset: 'assets/images/supplier_categories/government-tax.webp',
      icon: Icons.account_balance_outlined,
    ),
  ];

  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  final _exploreScrollController = ScrollController();
  final _directoryScrollController = ScrollController();

  SupplierHubTab _tab = SupplierHubTab.explore;
  _SupplierDirectoryState _directoryState = _SupplierDirectoryState.all;
  _SupplierAttentionScope? _attentionScope;
  String? _categoryScope;
  String _query = '';
  List<SupplierProfile> _profiles = const [];
  SupplierClassificationCatalog _catalog = SupplierClassificationCatalog();
  bool? _classificationAvailable;
  bool _loading = true;
  Object? _loadError;

  SupplierHubDataSource get _dataSource =>
      widget.dataSource ??
      SupplierRelationshipHubDataSource(
        context.read<SupplierRelationshipService>(),
      );

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _exploreScrollController.dispose();
    _directoryScrollController.dispose();
    super.dispose();
  }

  Future<void> _load({bool preserveContent = false}) async {
    if (!preserveContent || _profiles.isEmpty) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    }
    try {
      final result = await Future.wait<Object>([
        _dataSource.listSupplierProfiles(),
        _dataSource.getClassificationCatalog(),
      ]);
      if (!mounted) return;
      final profiles = result[0] as List<SupplierProfile>;
      final catalog = result[1] as SupplierClassificationCatalog;
      final classificationAvailable = catalog.roles.isNotEmpty &&
          profiles.every((profile) => profile.classificationWritesAvailable);
      setState(() {
        _profiles = profiles;
        _catalog = catalog;
        _classificationAvailable = classificationAvailable;
        if (!classificationAvailable) {
          _tab = SupplierHubTab.directory;
          _categoryScope = null;
          _attentionScope = null;
        }
        _loading = false;
        _loadError = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = error;
      });
    }
  }

  Future<void> _openNewSupplier() async {
    final created = await context.push<bool>('/purchases/suppliers/new');
    if (created == true) await _load(preserveContent: true);
  }

  Future<void> _openProfile(SupplierProfile profile) async {
    final changed = await context.push<bool>(
      '/purchases/suppliers/${profile.relationship.id}',
    );
    if (changed == true) await _load(preserveContent: true);
  }

  void _showDirectory({
    String? categoryCode,
    _SupplierAttentionScope? attentionScope,
  }) {
    if (_classificationAvailable == false &&
        (categoryCode != null || attentionScope != null)) {
      _selectTab(SupplierHubTab.directory);
      return;
    }
    if (categoryCode != null && _categoryCount(categoryCode) == 0) {
      final categoryLabel = _roleDefinition(categoryCode)?.label ??
          _featuredCategories
              .where((item) => item.code == categoryCode)
              .map((item) => item.fallbackLabel)
              .firstOrNull ??
          categoryCode;
      _selectTab(SupplierHubTab.directory);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Aún no hay proveedores confirmados en $categoryLabel. '
            'Se muestra el directorio completo.',
          ),
        ),
      );
      return;
    }
    setState(() {
      _tab = SupplierHubTab.directory;
      _categoryScope = categoryCode;
      _attentionScope = attentionScope;
    });
  }

  void _selectTab(SupplierHubTab tab) {
    setState(() {
      _tab = tab;
      if (tab == SupplierHubTab.directory) {
        _categoryScope = null;
        _attentionScope = null;
      }
    });
  }

  void _clearScope() {
    setState(() {
      _categoryScope = null;
      _attentionScope = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final compact = MediaQuery.sizeOf(context).width < 900;
    final effectiveTab =
        _classificationAvailable == false ? SupplierHubTab.directory : _tab;

    final content = ColoredBox(
      color: theme.scaffoldBackgroundColor,
      child: Column(
        children: [
          _SupplierModuleHeader(
            compact: compact,
            onCreate: _openNewSupplier,
          ),
          ColoredBox(
            color: theme.colorScheme.surface,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: VbSubTabs<SupplierHubTab>(
                tabs: [
                  if (_classificationAvailable != false)
                    const VbSubTab(
                      value: SupplierHubTab.explore,
                      label: 'Explorar',
                    ),
                  VbSubTab(
                    value: SupplierHubTab.directory,
                    label: 'Directorio  ${_profiles.length}',
                  ),
                ],
                value: effectiveTab,
                density: compact
                    ? VbSubTabsDensity.comfortable
                    : VbSubTabsDensity.compact,
                onChanged: _selectTab,
              ),
            ),
          ),
          Divider(height: 1, color: theme.colorScheme.outlineVariant),
          Expanded(
            child: _loading && _profiles.isEmpty
                ? const Center(child: BrandedLoading())
                : _loadError != null && _profiles.isEmpty
                    ? _SupplierLoadError(onRetry: _load)
                    : switch (effectiveTab) {
                        SupplierHubTab.explore =>
                          _buildExplore(context, roles, compact),
                        SupplierHubTab.directory =>
                          _buildDirectory(context, roles, compact),
                      },
          ),
        ],
      ),
    );
    return widget.includeWorkspaceShell ? MainLayout(child: content) : content;
  }

  Widget _buildExplore(
    BuildContext context,
    VinabikeThemeRoles roles,
    bool compact,
  ) {
    final theme = Theme.of(context);
    return CustomScrollView(
      key: const PageStorageKey('supplier-explore-scroll'),
      controller: _exploreScrollController,
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            compact ? 12 : 16,
            16,
            compact ? 12 : 16,
            24,
          ),
          sliver: SliverList.list(
            children: [
              _SupplierSearch(
                controller: _searchController,
                focusNode: _searchFocusNode,
                profiles: _profiles,
                catalog: _catalog,
                onQueryChanged: (value) => setState(() => _query = value),
                onSelected: _openProfile,
                onShowAll: () => _showDirectory(),
              ),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns = compact ? 2 : 3;
                  final gap = compact ? 12.0 : 14.0;
                  final cardWidth =
                      (constraints.maxWidth - gap * (columns - 1)) / columns;
                  final cardHeight = compact ? 245.0 : 318.0;
                  return Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: [
                      for (final item in _featuredCategories)
                        SizedBox(
                          width: cardWidth,
                          height: cardHeight,
                          child: _SupplierCategoryCard(
                            presentation: item,
                            label: _roleDefinition(item.code)?.label ??
                                item.fallbackLabel,
                            count: _categoryCount(item.code),
                            compact: compact,
                            onTap: () =>
                                _showDirectory(categoryCode: item.code),
                          ),
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
              _SupplierAllCategoriesRow(
                featuredCount: _featuredCategories.length,
                totalCount: _visibleRoleDefinitions.length,
                onTap: _openAllCategories,
              ),
              if (_attentionRows.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text(
                  'REQUIERE ATENCIÓN',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    letterSpacing: .9,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                _SupplierAttentionList(
                  rows: _attentionRows,
                  onTap: (scope) => _showDirectory(attentionScope: scope),
                ),
              ],
              if (_loadError != null) ...[
                const SizedBox(height: 16),
                VbNotice(
                  tone: VbNoticeTone.warning,
                  title: 'No se pudo actualizar el directorio',
                  body:
                      'Se mantienen los datos que ya estaban cargados. Puedes reintentar sin perder la vista actual.',
                  action: TextButton(
                    onPressed: () => _load(preserveContent: true),
                    child: const Text('Reintentar'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDirectory(
    BuildContext context,
    VinabikeThemeRoles roles,
    bool compact,
  ) {
    final profiles = _directoryProfiles;
    final scopeLabel = _currentScopeLabel;
    return CustomScrollView(
      key: const PageStorageKey('supplier-directory-scroll'),
      controller: _directoryScrollController,
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            compact ? 12 : 16,
            16,
            compact ? 12 : 16,
            24,
          ),
          sliver: SliverList.list(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _SupplierSearch(
                      controller: _searchController,
                      focusNode: _searchFocusNode,
                      profiles: _profiles,
                      catalog: _catalog,
                      resultCount: profiles.length,
                      onQueryChanged: (value) => setState(() => _query = value),
                      onSelected: _openProfile,
                      onShowAll: null,
                    ),
                  ),
                  const SizedBox(width: 10),
                  _SupplierFilterMenu(
                    compact: compact,
                    state: _directoryState,
                    onStateChanged: (value) {
                      setState(() => _directoryState = value);
                    },
                    onCategories: _classificationAvailable == true
                        ? _openAllCategories
                        : null,
                  ),
                ],
              ),
              if (scopeLabel != null) ...[
                const SizedBox(height: 10),
                _SupplierScopeBar(
                  label: scopeLabel,
                  count: profiles.length,
                  onClear: _clearScope,
                ),
              ],
              const SizedBox(height: 16),
              if (profiles.isEmpty)
                _SupplierEmptyDirectory(
                  hasScope: scopeLabel != null || _query.trim().isNotEmpty,
                  onClear: () {
                    _searchController.clear();
                    setState(() {
                      _query = '';
                      _directoryState = _SupplierDirectoryState.all;
                      _categoryScope = null;
                      _attentionScope = null;
                    });
                  },
                )
              else if (compact)
                _SupplierCompactDirectory(
                  profiles: profiles,
                  roleLabel: _roleLabel,
                  showReason: _attentionScope != null,
                  reasonFor: _attentionReason,
                  onTap: _openProfile,
                )
              else
                _SupplierDirectoryTable(
                  profiles: profiles,
                  roleLabel: _roleLabel,
                  showReason: _attentionScope != null,
                  reasonFor: _attentionReason,
                  onTap: _openProfile,
                ),
            ],
          ),
        ),
      ],
    );
  }

  SupplierClassificationDefinition? _roleDefinition(String code) {
    for (final definition in _catalog.roles) {
      if (definition.code == code) return definition;
    }
    return null;
  }

  List<SupplierClassificationDefinition> get _visibleRoleDefinitions =>
      _catalog.roles
          .where(
            (item) => item.isActive && !item.code.startsWith('free_service'),
          )
          .toList(growable: false);

  String _roleLabel(SupplierRole role) =>
      role.label ?? _roleDefinition(role.code)?.label ?? role.code;

  int _categoryCount(String code) => _profiles.where((profile) {
        return _hasConfirmedRole(profile, code);
      }).length;

  bool _hasConfirmedRole(SupplierProfile profile, String code) {
    return profile.relationship.roles.any(
      (role) => role.code == code && role.assignmentSource != 'observed',
    );
  }

  List<SupplierProfile> get _directoryProfiles {
    final normalizedQuery = _normalize(_query);
    final matches = <({
      SupplierProfile profile,
      _SupplierSearchReason? reason,
    })>[];
    for (final profile in _profiles) {
      if (_directoryState == _SupplierDirectoryState.active &&
          !profile.relationship.isActive) {
        continue;
      }
      if (_directoryState == _SupplierDirectoryState.inactive &&
          profile.relationship.isActive) {
        continue;
      }
      if (_categoryScope != null &&
          !_hasConfirmedRole(profile, _categoryScope!)) {
        continue;
      }
      if (_attentionScope != null &&
          !_matchesAttention(profile, _attentionScope!)) {
        continue;
      }
      final reason = normalizedQuery.isEmpty
          ? null
          : _SupplierSearch._matchReason(
              profile,
              _catalog,
              normalizedQuery,
            );
      if (normalizedQuery.isNotEmpty && reason == null) continue;
      matches.add((profile: profile, reason: reason));
    }
    matches.sort((left, right) {
      final leftRank = left.reason?.rank ?? 0;
      final rightRank = right.reason?.rank ?? 0;
      final byRank = leftRank.compareTo(rightRank);
      if (byRank != 0) return byRank;
      final byName = left.profile.displayName
          .toLowerCase()
          .compareTo(right.profile.displayName.toLowerCase());
      if (byName != 0) return byName;
      return left.profile.relationship.id.compareTo(
        right.profile.relationship.id,
      );
    });
    return matches.map((item) => item.profile).toList(growable: false);
  }

  List<_SupplierAttentionRow> get _attentionRows {
    final rows = <_SupplierAttentionRow>[];
    final unclassified = _profiles
        .where(
          (profile) =>
              profile.attentionSignals?.classificationStatus ==
              SupplierProfileClassificationStatus.unclassified,
        )
        .length;
    if (unclassified > 0) {
      rows.add(
        _SupplierAttentionRow(
          scope: _SupplierAttentionScope.unclassified,
          label: 'Sin categoría confirmada',
          description: 'todavía no sabemos en qué categoría va',
          count: unclassified,
        ),
      );
    }
    final missingPolicy = _profiles
        .where(
          (profile) =>
              profile.attentionSignals?.accountingPolicyStatus ==
              SupplierProfileAccountingPolicyStatus.missingPolicy,
        )
        .length;
    if (missingPolicy > 0) {
      rows.add(
        _SupplierAttentionRow(
          scope: _SupplierAttentionScope.missingAccountingPolicy,
          label: 'Sin regla contable',
          description: 'su relación pide una regla y aún no la tiene',
          count: missingPolicy,
        ),
      );
    }
    final pendingReview = _profiles
        .where(
          (profile) =>
              profile.attentionSignals?.validationIncidents.any(
                (incident) =>
                    incident.status == SupplierValidationIncidentStatus.pending,
              ) ==
              true,
        )
        .length;
    if (pendingReview > 0) {
      rows.add(
        _SupplierAttentionRow(
          scope: _SupplierAttentionScope.validationIncident,
          label: 'Requiere revisión',
          description: 'hay información que necesita confirmación',
          count: pendingReview,
        ),
      );
    }
    return rows;
  }

  bool _matchesAttention(
    SupplierProfile profile,
    _SupplierAttentionScope scope,
  ) {
    final signals = profile.attentionSignals;
    if (signals == null) return false;
    return switch (scope) {
      _SupplierAttentionScope.unclassified => signals.classificationStatus ==
          SupplierProfileClassificationStatus.unclassified,
      _SupplierAttentionScope.missingAccountingPolicy =>
        signals.accountingPolicyStatus ==
            SupplierProfileAccountingPolicyStatus.missingPolicy,
      _SupplierAttentionScope.validationIncident =>
        signals.validationIncidents.any(
          (incident) =>
              incident.status == SupplierValidationIncidentStatus.pending,
        ),
    };
  }

  String? _attentionReason(SupplierProfile profile) {
    final scope = _attentionScope;
    final signals = profile.attentionSignals;
    if (scope == null || signals == null) return null;
    return switch (scope) {
      _SupplierAttentionScope.unclassified =>
        'Todavía no tiene una categoría confirmada',
      _SupplierAttentionScope.missingAccountingPolicy =>
        'Su relación requiere una regla contable vigente',
      _SupplierAttentionScope.validationIncident => signals.validationIncidents
          .where(
            (incident) =>
                incident.status == SupplierValidationIncidentStatus.pending,
          )
          .map((incident) => incident.displayReason)
          .firstOrNull,
    };
  }

  String? get _currentScopeLabel {
    if (_categoryScope != null) {
      return _roleDefinition(_categoryScope!)?.label ??
          _featuredCategories
              .where((item) => item.code == _categoryScope)
              .map((item) => item.fallbackLabel)
              .firstOrNull;
    }
    return switch (_attentionScope) {
      _SupplierAttentionScope.unclassified => 'Sin categoría confirmada',
      _SupplierAttentionScope.missingAccountingPolicy => 'Sin regla contable',
      _SupplierAttentionScope.validationIncident => 'Requiere revisión',
      null => null,
    };
  }

  Future<void> _openAllCategories() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            Text('Todas las categorías',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final definition in _visibleRoleDefinitions)
              ListTile(
                minTileHeight: 48,
                title: Text(definition.label),
                subtitle: definition.description == null
                    ? null
                    : Text(definition.description!),
                trailing: Text('${_categoryCount(definition.code)}'),
                onTap: () => Navigator.of(context).pop(definition.code),
              ),
          ],
        ),
      ),
    );
    if (!mounted || selected == null) return;
    _showDirectory(categoryCode: selected);
  }
}

class _SupplierModuleHeader extends StatelessWidget {
  const _SupplierModuleHeader({required this.compact, required this.onCreate});

  final bool compact;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final roles = VinabikeThemeRoles.of(context);
    final theme = Theme.of(context);
    return Container(
      color: roles.shell.canvas,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'COMPRAS',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: roles.shell.accent,
                    letterSpacing: 1.1,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Proveedores',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: roles.shell.foreground,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          FilledButton.icon(
            onPressed: onCreate,
            icon: const Icon(Icons.add, size: 17),
            label: const Text('Nuevo proveedor'),
            style: FilledButton.styleFrom(
              minimumSize: Size(0, compact ? 48 : 38),
              backgroundColor: roles.shell.accent,
              foregroundColor: roles.shell.onAccent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
              textStyle: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SupplierSearch extends StatelessWidget {
  const _SupplierSearch({
    required this.controller,
    required this.focusNode,
    required this.profiles,
    required this.catalog,
    required this.onQueryChanged,
    required this.onSelected,
    this.onShowAll,
    this.resultCount,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final List<SupplierProfile> profiles;
  final SupplierClassificationCatalog catalog;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<SupplierProfile> onSelected;
  final VoidCallback? onShowAll;
  final int? resultCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return RawAutocomplete<_SupplierSearchResult>(
      textEditingController: controller,
      focusNode: focusNode,
      displayStringForOption: (option) => option.profile.displayName,
      optionsBuilder: (value) {
        final query = _normalize(value.text);
        if (query.isEmpty) return const Iterable.empty();
        final matches = <_SupplierSearchResult>[];
        for (final profile in profiles) {
          final reason = _matchReason(profile, catalog, query);
          if (reason != null) {
            matches.add(_SupplierSearchResult(profile, reason));
          }
        }
        matches.sort((left, right) {
          final byRank = left.reason.rank.compareTo(right.reason.rank);
          if (byRank != 0) return byRank;
          return left.profile.displayName.toLowerCase().compareTo(
                right.profile.displayName.toLowerCase(),
              );
        });
        return matches.take(6);
      },
      onSelected: (option) => onSelected(option.profile),
      fieldViewBuilder: (context, textController, focusNode, onSubmitted) {
        return TextField(
          controller: textController,
          focusNode: focusNode,
          onChanged: onQueryChanged,
          onSubmitted: (_) {
            onSubmitted();
            if (textController.text.trim().isNotEmpty) onShowAll?.call();
          },
          decoration: InputDecoration(
            hintText: 'Buscar proveedor por nombre, alias o RUT',
            prefixIcon: const Icon(Icons.search, size: 17),
            suffixIcon: resultCount == null
                ? null
                : Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '$resultCount de ${profiles.length}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        if (textController.text.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          IconButton(
                            tooltip: 'Limpiar búsqueda',
                            onPressed: () {
                              textController.clear();
                              onQueryChanged('');
                            },
                            icon: const Icon(Icons.close, size: 16),
                          ),
                        ],
                      ],
                    ),
                  ),
            isDense: true,
            filled: true,
            fillColor: theme.colorScheme.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
          ),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        final rows = options.toList(growable: false);
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 6,
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(8),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620, maxHeight: 430),
              child: ListView(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                children: [
                  if (rows.isEmpty)
                    const ListTile(
                      minTileHeight: 48,
                      title: Text('Sin coincidencias'),
                    )
                  else
                    for (final result in rows)
                      ListTile(
                        minTileHeight: 48,
                        title: Text(result.profile.displayName),
                        subtitle: Text(result.reason.label),
                        onTap: () => onSelected(result),
                      ),
                  if (onShowAll != null)
                    ListTile(
                      minTileHeight: 48,
                      title:
                          const Text('Ver todos los resultados en Directorio'),
                      trailing: const Icon(Icons.arrow_forward, size: 16),
                      onTap: onShowAll,
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  static _SupplierSearchReason? _matchReason(
    SupplierProfile profile,
    SupplierClassificationCatalog catalog,
    String query,
  ) {
    final name = _normalize(profile.displayName);
    if (name.split(RegExp(r'\s+')).any((word) => word.startsWith(query))) {
      return const _SupplierSearchReason(1, 'Coincide con el nombre');
    }
    if (name.contains(query)) {
      return const _SupplierSearchReason(2, 'Coincide con el nombre');
    }
    for (final candidate in <(String?, String)>[
      (profile.party.legalName, 'nombre legal'),
      (profile.party.tradeName, 'nombre comercial'),
    ]) {
      final value = candidate.$1;
      if (value != null && _normalize(value).contains(query)) {
        return _SupplierSearchReason(2, 'Coincide con el ${candidate.$2}');
      }
    }
    if (profile.party.aliases.any(
      (value) => _normalize(value).contains(query),
    )) {
      return const _SupplierSearchReason(3, 'Coincide con un alias');
    }
    if (profile.party.identifiers.any(
      (value) => _normalize(value.value).contains(query),
    )) {
      return const _SupplierSearchReason(4, 'Coincide con el RUT');
    }
    final relationshipSummary = profile.serviceRelationshipSummary;
    if (relationshipSummary != null &&
        _normalize(relationshipSummary).contains(query)) {
      return _SupplierSearchReason(
        5,
        'Coincide con “$relationshipSummary”',
      );
    }
    final roleLabels = {
      for (final definition in catalog.roles) definition.code: definition.label,
    };
    for (final role in profile.relationship.roles) {
      final label = role.label ?? roleLabels[role.code] ?? role.code;
      if (_normalize(label).contains(query)) {
        return _SupplierSearchReason(5, 'Coincide con “$label”');
      }
    }
    return null;
  }
}

class _SupplierCategoryCard extends StatelessWidget {
  const _SupplierCategoryCard({
    required this.presentation,
    required this.label,
    required this.count,
    required this.compact,
    required this.onTap,
  });

  final _SupplierCategoryPresentation presentation;
  final String label;
  final int count;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    return Semantics(
      button: true,
      label: 'Abrir $label en el directorio, $count proveedores',
      child: Material(
        color: theme.colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          focusColor: roles.selectionContainer,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Image.asset(
                  presentation.asset,
                  fit: BoxFit.cover,
                  alignment: Alignment.center,
                  excludeFromSemantics: true,
                ),
              ),
              ConstrainedBox(
                constraints: BoxConstraints(minHeight: compact ? 69 : 58),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    compact ? 10 : 14,
                    10,
                    compact ? 8 : 12,
                    10,
                  ),
                  child: compact
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  presentation.icon,
                                  size: 13,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    label,
                                    maxLines: 2,
                                    style:
                                        theme.textTheme.labelMedium?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                const Icon(Icons.chevron_right, size: 15),
                              ],
                            ),
                            const SizedBox(height: 7),
                            Text('$count', style: theme.textTheme.labelMedium),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  presentation.icon,
                                  size: 13,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 7),
                                Expanded(
                                  child: Text(
                                    label,
                                    style:
                                        theme.textTheme.labelMedium?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                Text('$count',
                                    style: theme.textTheme.labelSmall),
                                const SizedBox(width: 3),
                                const Icon(Icons.chevron_right, size: 15),
                              ],
                            ),
                            const SizedBox(height: 5),
                            Text(
                              presentation.description,
                              maxLines: 2,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SupplierAllCategoriesRow extends StatelessWidget {
  const _SupplierAllCategoriesRow({
    required this.featuredCount,
    required this.totalCount,
    required this.onTap,
  });

  final int featuredCount;
  final int totalCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Destacadas $featuredCount de $totalCount. Un proveedor puede estar en más de una categoría.',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'Todas las categorías',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Icon(Icons.chevron_right, size: 15),
            ],
          ),
        ),
      ),
    );
  }
}

class _SupplierAttentionList extends StatelessWidget {
  const _SupplierAttentionList({required this.rows, required this.onTap});

  final List<_SupplierAttentionRow> rows;
  final ValueChanged<_SupplierAttentionScope> onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    return Material(
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var index = 0; index < rows.length; index++) ...[
            if (index > 0) Divider(height: 1, color: theme.dividerColor),
            InkWell(
              onTap: () => onTap(rows[index].scope),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: rows[index].scope ==
                                  _SupplierAttentionScope.validationIncident
                              ? roles.neutral.accent
                              : roles.warning.accent,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Wrap(
                          spacing: 10,
                          runSpacing: 3,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(rows[index].label),
                            Text(
                              rows[index].description,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text('${rows[index].count}'),
                      const SizedBox(width: 4),
                      const Icon(Icons.chevron_right, size: 16),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SupplierFilterMenu extends StatelessWidget {
  const _SupplierFilterMenu({
    required this.compact,
    required this.state,
    required this.onStateChanged,
    required this.onCategories,
  });

  final bool compact;
  final _SupplierDirectoryState state;
  final ValueChanged<_SupplierDirectoryState> onStateChanged;
  final VoidCallback? onCategories;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopupMenuButton<Object>(
      tooltip: 'Filtros del directorio',
      onSelected: (value) {
        if (value is _SupplierDirectoryState) onStateChanged(value);
        if (value == 'categories') onCategories?.call();
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          enabled: false,
          child: Text('Estado'),
        ),
        for (final value in _SupplierDirectoryState.values)
          CheckedPopupMenuItem(
            value: value,
            checked: state == value,
            child: Text(switch (value) {
              _SupplierDirectoryState.all => 'Todos',
              _SupplierDirectoryState.active => 'Activos',
              _SupplierDirectoryState.inactive => 'Inactivos',
            }),
          ),
        if (onCategories != null) ...[
          const PopupMenuDivider(),
          const PopupMenuItem(
            value: 'categories',
            child: Text('Elegir categoría…'),
          ),
        ],
      ],
      child: Container(
        constraints: BoxConstraints(minHeight: compact ? 48 : 40),
        padding: EdgeInsets.symmetric(horizontal: compact ? 13 : 14),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.tune, size: 16),
            if (!compact) ...[
              const SizedBox(width: 8),
              const Text('Filtros'),
            ],
            const SizedBox(width: 5),
            const Icon(Icons.arrow_drop_down, size: 16),
          ],
        ),
      ),
    );
  }
}

class _SupplierScopeBar extends StatelessWidget {
  const _SupplierScopeBar({
    required this.label,
    required this.count,
    required this.onClear,
  });

  final String label;
  final int count;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$label · $count ${count == 1 ? 'proveedor' : 'proveedores'}',
              style: theme.textTheme.labelMedium,
            ),
          ),
          TextButton.icon(
            onPressed: onClear,
            icon: const Icon(Icons.close, size: 15),
            label: const Text('Quitar alcance'),
          ),
        ],
      ),
    );
  }
}

class _SupplierDirectoryTable extends StatelessWidget {
  const _SupplierDirectoryTable({
    required this.profiles,
    required this.roleLabel,
    required this.showReason,
    required this.reasonFor,
    required this.onTap,
  });

  final List<SupplierProfile> profiles;
  final String Function(SupplierRole) roleLabel;
  final bool showReason;
  final String? Function(SupplierProfile) reasonFor;
  final ValueChanged<SupplierProfile> onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            color: theme.colorScheme.surfaceContainerLow,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: Row(
              children: [
                Expanded(
                  flex: 5,
                  child: _tableHeader(context, 'PROVEEDOR'),
                ),
                Expanded(
                  flex: 3,
                  child: _tableHeader(
                    context,
                    showReason ? 'MOTIVO' : 'SERVICIO O RELACIÓN',
                  ),
                ),
              ],
            ),
          ),
          for (var index = 0; index < profiles.length; index++) ...[
            if (index > 0) Divider(height: 1, color: theme.dividerColor),
            InkWell(
              onTap: () => onTap(profiles[index]),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 9,
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 5,
                      child: _SupplierIdentityCell(
                        profile: profiles[index],
                        roleLabel: roleLabel,
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(
                        showReason
                            ? reasonFor(profiles[index]) ?? ''
                            : _engagementSummary(profiles[index]),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _tableHeader(BuildContext context, String text) => Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              letterSpacing: .8,
              fontWeight: FontWeight.w600,
            ),
      );
}

class _SupplierCompactDirectory extends StatelessWidget {
  const _SupplierCompactDirectory({
    required this.profiles,
    required this.roleLabel,
    required this.showReason,
    required this.reasonFor,
    required this.onTap,
  });

  final List<SupplierProfile> profiles;
  final String Function(SupplierRole) roleLabel;
  final bool showReason;
  final String? Function(SupplierProfile) reasonFor;
  final ValueChanged<SupplierProfile> onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var index = 0; index < profiles.length; index++) ...[
            if (index > 0) Divider(height: 1, color: theme.dividerColor),
            InkWell(
              onTap: () => onTap(profiles[index]),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 64),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _SupplierIdentityCell(
                              profile: profiles[index],
                              roleLabel: roleLabel,
                            ),
                            if (showReason &&
                                reasonFor(profiles[index]) != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 5),
                                child: Text(
                                  reasonFor(profiles[index])!,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            if (!showReason &&
                                _engagementSummary(profiles[index]).isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 5),
                                child: Text(
                                  _engagementSummary(profiles[index]),
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right, size: 17),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SupplierIdentityCell extends StatelessWidget {
  const _SupplierIdentityCell({
    required this.profile,
    required this.roleLabel,
  });

  final SupplierProfile profile;
  final String Function(SupplierRole) roleLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = profile.relationship.roles
        .map(roleLabel)
        .where((value) => value.trim().isNotEmpty)
        .toList(growable: false);
    final taxId = profile.party.identifiers
        .where((item) => item.kind == 'tax_id' && item.isPrimary)
        .map((item) => item.value)
        .firstOrNull;
    final typeLabel = switch (profile.party.kind) {
      ExternalPartyKind.person => 'Persona',
      ExternalPartyKind.publicAuthority => 'Organismo público',
      ExternalPartyKind.organization => roles.isEmpty ? 'Organización' : null,
      ExternalPartyKind.other => roles.isEmpty ? 'Otra contraparte' : null,
    };
    final metadata = <String>[
      if (typeLabel != null && !roles.contains(typeLabel)) typeLabel,
      ...roles,
      if (taxId != null) taxId,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                profile.displayName,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (!profile.relationship.isActive) ...[
              const SizedBox(width: 8),
              const VbStatusBadge(
                label: 'Inactivo',
                tone: VbStatusTone.neutral,
              ),
            ],
          ],
        ),
        if (metadata.isNotEmpty) ...[
          const SizedBox(height: 3),
          Text(
            metadata.join(' · '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

class _SupplierEmptyDirectory extends StatelessWidget {
  const _SupplierEmptyDirectory({
    required this.hasScope,
    required this.onClear,
  });

  final bool hasScope;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 56),
      child: Column(
        children: [
          const Icon(Icons.storefront_outlined, size: 34),
          const SizedBox(height: 12),
          Text(
            hasScope
                ? 'No hay proveedores que coincidan'
                : 'Todavía no hay proveedores',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          if (hasScope) ...[
            const SizedBox(height: 8),
            TextButton(onPressed: onClear, child: const Text('Limpiar vista')),
          ],
        ],
      ),
    );
  }
}

class _SupplierLoadError extends StatelessWidget {
  const _SupplierLoadError({required this.onRetry});

  final Future<void> Function({bool preserveContent}) onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: VbNotice(
          tone: VbNoticeTone.danger,
          title: 'No pudimos abrir Proveedores',
          body: 'Revisa la conexión e inténtalo nuevamente.',
          action: TextButton(
            onPressed: () => onRetry(),
            child: const Text('Reintentar'),
          ),
        ),
      ),
    );
  }
}

@immutable
class _SupplierCategoryPresentation {
  const _SupplierCategoryPresentation({
    required this.code,
    required this.fallbackLabel,
    required this.description,
    required this.asset,
    required this.icon,
  });

  final String code;
  final String fallbackLabel;
  final String description;
  final String asset;
  final IconData icon;
}

@immutable
class _SupplierAttentionRow {
  const _SupplierAttentionRow({
    required this.scope,
    required this.label,
    required this.description,
    required this.count,
  });

  final _SupplierAttentionScope scope;
  final String label;
  final String description;
  final int count;
}

@immutable
class _SupplierSearchResult {
  const _SupplierSearchResult(this.profile, this.reason);

  final SupplierProfile profile;
  final _SupplierSearchReason reason;
}

@immutable
class _SupplierSearchReason {
  const _SupplierSearchReason(this.rank, this.label);

  final int rank;
  final String label;
}

String _normalize(String value) {
  const accents = 'áéíóúüñÁÉÍÓÚÜÑ';
  const ascii = 'aeiouunAEIOUUN';
  var normalized = value.trim().toLowerCase();
  for (var index = 0; index < accents.length; index++) {
    normalized = normalized.replaceAll(accents[index], ascii[index]);
  }
  return normalized.replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
}

String _engagementSummary(SupplierProfile profile) {
  final published = profile.serviceRelationshipSummary?.trim();
  return published == null || published.isEmpty ? '' : published;
}
