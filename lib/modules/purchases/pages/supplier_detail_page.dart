import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/services/current_user_profile_service.dart';
import '../../../shared/services/return_navigation.dart';
import '../../../shared/themes/vinabike_theme_roles.dart';
import '../../../shared/widgets/branded_loading.dart';
import '../../../shared/widgets/main_layout.dart';
import '../../../shared/widgets/vb_notice.dart';
import '../../../shared/widgets/vb_short_select.dart';
import '../../../shared/widgets/vb_status_badge.dart';
import '../models/supplier_foundation.dart';
import '../services/supplier_credential_reveal_controller.dart';
import '../services/supplier_credential_service.dart';
import '../services/supplier_relationship_service.dart';

/// Read boundary for the routed supplier profile.
///
/// Production uses only the canonical relationship/economic projections and
/// the protected, secret-free credential status RPC. The interface is public
/// so the routed surface can be exercised without booting the whole workspace
/// shell; it is not an alternate persistence owner.
abstract interface class SupplierDetailDataSource {
  Future<SupplierProfile?> getProfile(String supplierId);

  Future<List<SupplierEconomicSummaryReadModel>> getEconomicSummary(
    String supplierId,
  );

  Future<SupplierEconomicTimelinePage> getEconomicTimeline(
    String supplierId,
  );

  Future<SupplierCredentialStatus> getCredentialStatus(String supplierId);

  bool get canReadCredentialMetadata;

  String get authorityFingerprint;

  Listenable? get profileAuthorityChanges;

  Stream<Object?>? get authAuthorityChanges;
}

class CanonicalSupplierDetailDataSource implements SupplierDetailDataSource {
  CanonicalSupplierDetailDataSource({
    required SupplierRelationshipService relationshipService,
    required CurrentUserProfileService profileService,
    SupplierCredentialService? credentialService,
  })  : _relationshipService = relationshipService,
        _profileService = profileService,
        _credentialService = credentialService ??
            SupplierCredentialService(profileService: profileService);

  final SupplierRelationshipService _relationshipService;
  final CurrentUserProfileService _profileService;
  final SupplierCredentialService _credentialService;

  @override
  Future<SupplierProfile?> getProfile(String supplierId) =>
      _relationshipService.getSupplierProfile(supplierId);

  @override
  Future<List<SupplierEconomicSummaryReadModel>> getEconomicSummary(
    String supplierId,
  ) =>
      _relationshipService.getEconomicSummary(supplierId);

  @override
  Future<SupplierEconomicTimelinePage> getEconomicTimeline(
    String supplierId,
  ) =>
      _relationshipService.getEconomicTimelinePage(supplierId, limit: 50);

  @override
  Future<SupplierCredentialStatus> getCredentialStatus(String supplierId) =>
      _credentialService.getStatus(supplierId: supplierId);

  @override
  bool get canReadCredentialMetadata =>
      _profileService.profile?.canManageSupplierCredentials == true;

  @override
  String get authorityFingerprint {
    final profile = _profileService.profile;
    return '${_credentialService.currentAuthUserId ?? ''}|'
        '${profile?.userId ?? ''}|${profile?.tenantId ?? ''}|'
        '${profile?.canManageSupplierCredentials ?? false}';
  }

  @override
  Listenable get profileAuthorityChanges => _profileService;

  @override
  Stream<Object?>? get authAuthorityChanges =>
      _credentialService.authorityEvents;
}

/// Routed supplier profile frozen in supplier Design turn T18.2.
///
/// Route contract: `/purchases/suppliers/:id`. The only record action is the
/// header's `Editar`, which pushes `/purchases/suppliers/:id/edit`. Closing
/// always follows [ReturnNavigation].
class SupplierDetailPage extends StatefulWidget {
  const SupplierDetailPage({
    super.key,
    required this.supplierId,
    this.dataSource,
    this.credentialRevealController,
    this.includeWorkspaceShell = true,
  });

  final String supplierId;
  final SupplierDetailDataSource? dataSource;

  /// Test seam for exercising the audited, short-lived reveal interaction.
  /// Production callers leave this null so this page creates the controller
  /// from the same credential service used by its metadata data source.
  @visibleForTesting
  final SupplierCredentialRevealController? credentialRevealController;

  /// Test seam for the record surface. Routed production callers leave this
  /// true; it does not create a second product surface.
  @visibleForTesting
  final bool includeWorkspaceShell;

  @override
  State<SupplierDetailPage> createState() => _SupplierDetailPageState();
}

enum _SupplierDetailSection {
  summary('Resumen'),
  identity('Identidad'),
  classification('Para qué lo usamos'),
  relationships('Relaciones'),
  accounting('Criterios contables'),
  access('Accesos'),
  movements('Movimientos');

  const _SupplierDetailSection(this.label);

  final String label;
}

class _SupplierDetailPageState extends State<SupplierDetailPage> {
  SupplierDetailDataSource? _dataSource;
  SupplierCredentialRevealController? _credentialRevealController;
  bool _ownsCredentialRevealController = false;
  Listenable? _profileAuthorityChanges;
  StreamSubscription<Object?>? _authAuthoritySubscription;
  String? _authorityFingerprint;
  SupplierProfile? _profile;
  List<SupplierEconomicSummaryReadModel> _economicSummaries = const [];
  SupplierEconomicTimelinePage? _economicTimeline;
  SupplierCredentialStatus? _credentialStatus;
  Object? _credentialStatusError;
  String? _credentialRevealErrorTarget;
  String? _credentialRevealErrorMessage;
  bool _credentialAccessDenied = false;
  Object? _loadError;
  bool _loading = true;
  int _loadGeneration = 0;
  _SupplierDetailSection _selectedSection = _SupplierDetailSection.summary;

  SupplierDetailDataSource get _source => _dataSource!;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_dataSource != null) return;
    late final SupplierDetailDataSource source;
    if (widget.dataSource case final injectedSource?) {
      source = injectedSource;
      _credentialRevealController = widget.credentialRevealController;
    } else {
      final profileService = context.read<CurrentUserProfileService>();
      final credentialService = SupplierCredentialService(
        profileService: profileService,
      );
      source = CanonicalSupplierDetailDataSource(
        relationshipService: context.read<SupplierRelationshipService>(),
        profileService: profileService,
        credentialService: credentialService,
      );
      _credentialRevealController = widget.credentialRevealController ??
          SupplierCredentialRevealController(
            credentialService: credentialService,
            profileService: profileService,
          );
      _ownsCredentialRevealController =
          widget.credentialRevealController == null;
    }
    _dataSource = source;
    _credentialRevealController?.addListener(_handleCredentialRevealChange);
    _authorityFingerprint = source.authorityFingerprint;
    _profileAuthorityChanges = source.profileAuthorityChanges
      ?..addListener(_handleAuthorityChange);
    _authAuthoritySubscription = source.authAuthorityChanges?.listen(
      (_) => _handleAuthorityChange(clearCredentialMetadataImmediately: true),
    );
    unawaited(_load());
  }

  @override
  void dispose() {
    _profileAuthorityChanges?.removeListener(_handleAuthorityChange);
    unawaited(_authAuthoritySubscription?.cancel());
    final revealController = _credentialRevealController;
    revealController?.removeListener(_handleCredentialRevealChange);
    revealController?.clear();
    if (_ownsCredentialRevealController) revealController?.dispose();
    super.dispose();
  }

  void _handleCredentialRevealChange() {
    if (mounted) setState(() {});
  }

  void _handleAuthorityChange({
    bool clearCredentialMetadataImmediately = false,
  }) {
    if (!mounted) return;
    _credentialRevealController?.clear();
    final fingerprint = _source.authorityFingerprint;
    if (!clearCredentialMetadataImmediately &&
        fingerprint == _authorityFingerprint) {
      return;
    }
    _authorityFingerprint = fingerprint;
    setState(() {
      _credentialStatus = null;
      _credentialStatusError = null;
      _credentialRevealErrorTarget = null;
      _credentialRevealErrorMessage = null;
      _credentialAccessDenied = false;
    });
    unawaited(_load());
  }

  Future<void> _load({bool preserveProfile = false}) async {
    _credentialRevealController?.clear();
    final generation = ++_loadGeneration;
    if (!preserveProfile || _profile == null) {
      setState(() {
        _loading = true;
        _loadError = null;
        _credentialStatus = null;
        _credentialStatusError = null;
        _credentialRevealErrorTarget = null;
        _credentialRevealErrorMessage = null;
        _credentialAccessDenied = false;
      });
    } else {
      setState(() {
        _credentialRevealErrorTarget = null;
        _credentialRevealErrorMessage = null;
      });
    }

    try {
      final base = await Future.wait<Object?>([
        _source.getProfile(widget.supplierId),
        _source.getEconomicSummary(widget.supplierId),
        _source.getEconomicTimeline(widget.supplierId),
      ]);
      if (!mounted || generation != _loadGeneration) return;
      final profile = base[0] as SupplierProfile?;
      final summaries = base[1] as List<SupplierEconomicSummaryReadModel>;
      final timeline = base[2] as SupplierEconomicTimelinePage;

      SupplierCredentialStatus? credentialStatus;
      Object? credentialStatusError;
      var credentialAccessDenied = false;
      if (profile != null && _source.canReadCredentialMetadata) {
        try {
          credentialStatus =
              await _source.getCredentialStatus(widget.supplierId);
        } catch (error) {
          if (_isCredentialPermissionError(error)) {
            credentialAccessDenied = true;
          } else {
            credentialStatusError = error;
          }
        }
      } else if (profile?.relationship.hasCredentialReference == true) {
        credentialAccessDenied = true;
      }
      if (!mounted || generation != _loadGeneration) return;

      final recognizedActivities = timeline.timeline.activities
          .where((activity) => activity.isRecognized)
          .toList(growable: false);
      final safeTimeline = SupplierEconomicTimelinePage(
        timeline: SupplierEconomicReadModel(
          tenantId: timeline.timeline.tenantId,
          supplierId: timeline.timeline.supplierId,
          activities: recognizedActivities,
        ),
        offset: timeline.offset,
        limit: timeline.limit,
        hasMore: timeline.hasMore,
      );

      setState(() {
        _profile = profile;
        _economicSummaries = summaries;
        _economicTimeline = safeTimeline;
        _credentialStatus = credentialStatus;
        _credentialStatusError = credentialStatusError;
        _credentialAccessDenied = credentialAccessDenied;
        _loadError = null;
        _loading = false;
        _coerceSelectedSection();
      });
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _loadError = error;
        _loading = false;
      });
    }
  }

  void _coerceSelectedSection() {
    final sections = _sections;
    if (!sections.contains(_selectedSection)) {
      _selectedSection = _SupplierDetailSection.summary;
    }
  }

  bool get _hasRecognizedEconomicActivity {
    final profileCount = _profile?.attentionSignals?.recognizedDocumentCount;
    return (profileCount != null && profileCount > 0) ||
        _economicSummaries.any((summary) => summary.totalDocumentCount > 0) ||
        (_economicTimeline?.timeline.activities.isNotEmpty ?? false);
  }

  bool get _hasAccountingSection {
    final status = _profile?.attentionSignals?.accountingPolicyStatus;
    if (status == SupplierProfileAccountingPolicyStatus.notApplicable) {
      return false;
    }
    if (status == SupplierProfileAccountingPolicyStatus.configured ||
        status == SupplierProfileAccountingPolicyStatus.missingPolicy) {
      return true;
    }
    return _profile?.accounting.policies.isNotEmpty == true;
  }

  bool get _hasAccessSection {
    if (_credentialAccessDenied) {
      return _profile?.relationship.hasCredentialReference == true;
    }
    final status = _credentialStatus;
    if (status != null) {
      return status.hasPortalCredential || status.credentials.isNotEmpty;
    }
    return _profile?.relationship.hasCredentialReference == true;
  }

  List<_SupplierDetailSection> get _sections => [
        _SupplierDetailSection.summary,
        _SupplierDetailSection.identity,
        _SupplierDetailSection.classification,
        if ((_profile?.engagements.isNotEmpty ?? false) ||
            (_profile?.activeEngagementCount ?? 0) > 0 ||
            _profile?.serviceRelationshipSummary != null)
          _SupplierDetailSection.relationships,
        if (_hasAccountingSection) _SupplierDetailSection.accounting,
        if (_hasAccessSection) _SupplierDetailSection.access,
        if (_hasRecognizedEconomicActivity) _SupplierDetailSection.movements,
      ];

  Future<void> _openEditor() async {
    _credentialRevealController?.clear();
    final changed = await context.push<bool>(
      '/purchases/suppliers/${widget.supplierId}/edit',
    );
    if (changed == true && mounted) await _load(preserveProfile: true);
  }

  void _close() {
    _credentialRevealController?.clear();
    ReturnNavigation.close(
      context,
      fallbackRoute: '/purchases/suppliers',
    );
  }

  void _selectSection(_SupplierDetailSection section) {
    if (section != _SupplierDetailSection.access) {
      _credentialRevealController?.clear();
    }
    setState(() {
      _credentialRevealErrorTarget = null;
      _credentialRevealErrorMessage = null;
      _selectedSection = section;
    });
  }

  Future<void> _revealCredential(SupplierCredentialMetadata metadata) async {
    final controller = _credentialRevealController;
    if (controller == null ||
        !_source.canReadCredentialMetadata ||
        !metadata.secretAvailable) {
      return;
    }
    final target = SupplierCredentialRevealTarget(
      supplierId: metadata.supplierId,
      kind: metadata.kind,
      credentialKey: metadata.credentialKey,
    );
    final targetKey = _credentialTargetKey(target);
    setState(() {
      _credentialRevealErrorTarget = null;
      _credentialRevealErrorMessage = null;
    });
    try {
      final revealed = await controller.reveal(target);
      if (!mounted) return;
      if (!revealed) {
        setState(() {
          _credentialRevealErrorTarget = targetKey;
          _credentialRevealErrorMessage =
              'La clave ya no está disponible. Recarga los accesos e inténtalo de nuevo.';
        });
        return;
      }
      if (!_sameCredentialMetadataBinding(controller.metadata, metadata)) {
        controller.hide();
        setState(() {
          _credentialRevealErrorTarget = targetKey;
          _credentialRevealErrorMessage =
              'Este acceso cambió mientras lo abrías. Recarga antes de volver a intentarlo.';
        });
      }
    } catch (error) {
      if (!mounted) return;
      controller.hide();
      if (error is SupplierCredentialAccessDenied ||
          _isCredentialPermissionError(error)) {
        setState(() {
          _credentialStatus = null;
          _credentialAccessDenied = true;
          _credentialRevealErrorTarget = null;
          _credentialRevealErrorMessage = null;
        });
      } else {
        setState(() {
          _credentialRevealErrorTarget = targetKey;
          _credentialRevealErrorMessage =
              'No pudimos abrir esta clave. El resto del perfil sigue disponible.';
        });
      }
    }
  }

  void _hideCredential() {
    _credentialRevealController?.hide();
    if (!mounted) return;
    setState(() {
      _credentialRevealErrorTarget = null;
      _credentialRevealErrorMessage = null;
    });
  }

  Future<void> _copyCredential(
    SupplierCredentialMetadata metadata,
  ) async {
    final controller = _credentialRevealController;
    if (controller == null ||
        !controller.isVisible ||
        !_sameCredentialMetadataBinding(controller.metadata, metadata)) {
      return;
    }
    final secret = controller.revealedSecret;
    if (secret == null || secret.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: secret));
  }

  @override
  Widget build(BuildContext context) {
    final surface = _buildSurface(context);
    if (!widget.includeWorkspaceShell) {
      return Material(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: surface,
      );
    }
    return MainLayout(
      title: 'Proveedores',
      child: surface,
    );
  }

  Widget _buildSurface(BuildContext context) {
    final theme = Theme.of(context);
    final compact = MediaQuery.sizeOf(context).width < 900;
    return ColoredBox(
      color: theme.scaffoldBackgroundColor,
      child: Column(
        children: [
          const _SupplierDetailModuleHeader(),
          Expanded(
            child: switch ((_loading, _loadError, _profile)) {
              (true, _, null) => const Center(
                  child: BrandedLoading(
                    size: 64,
                    message: 'Cargando proveedor…',
                  ),
                ),
              (false, final Object error, null) => _SupplierDetailError(
                  error: error,
                  onRetry: _load,
                  onClose: _close,
                ),
              (false, null, null) => _SupplierDetailNotFound(
                  onClose: _close,
                ),
              _ => _buildProfile(context, compact),
            },
          ),
        ],
      ),
    );
  }

  Widget _buildProfile(BuildContext context, bool compact) {
    final profile = _profile!;
    final sections = _sections;
    final selectedIndex = sections.indexOf(_selectedSection);
    return SingleChildScrollView(
      key: const PageStorageKey('supplier-detail-scroll'),
      padding: EdgeInsets.fromLTRB(
        compact ? 12 : 16,
        compact ? 12 : 16,
        compact ? 12 : 16,
        24,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SupplierDetailBack(onPressed: _close, compact: compact),
          const SizedBox(height: 13),
          _SupplierRecordHeader(
            profile: profile,
            compact: compact,
            onEdit: _openEditor,
          ),
          SizedBox(height: compact ? 13 : 15),
          if (compact) ...[
            VbShortSelect<_SupplierDetailSection>(
              key: const ValueKey('supplier-detail-section-select'),
              value: _selectedSection,
              options: sections
                  .map(
                    (section) => VbShortSelectOption(
                      value: section,
                      label: section.label,
                    ),
                  )
                  .toList(growable: false),
              label: 'Sección · ${selectedIndex + 1} de ${sections.length}',
              semanticLabel:
                  'Sección ${selectedIndex + 1} de ${sections.length}',
              sheetTitle: 'Ir a una sección',
              onChanged: _selectSection,
            ),
            const SizedBox(height: 13),
            _buildSelectedSection(context),
          ] else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 196,
                  child: _SupplierSectionRail(
                    sections: sections,
                    selected: _selectedSection,
                    onSelected: _selectSection,
                  ),
                ),
                const SizedBox(width: 22),
                Expanded(child: _buildSelectedSection(context)),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildSelectedSection(BuildContext context) {
    return KeyedSubtree(
      key: ValueKey('supplier-section-${_selectedSection.name}'),
      child: switch (_selectedSection) {
        _SupplierDetailSection.summary => _SupplierSummarySection(
            profile: _profile!,
            summaries: _economicSummaries,
            credentialStatus: _credentialStatus,
            showEconomicActivity: _hasRecognizedEconomicActivity,
          ),
        _SupplierDetailSection.identity =>
          _SupplierIdentitySection(profile: _profile!),
        _SupplierDetailSection.classification =>
          _SupplierClassificationSection(profile: _profile!),
        _SupplierDetailSection.relationships =>
          _SupplierRelationshipsSection(profile: _profile!),
        _SupplierDetailSection.accounting =>
          _SupplierAccountingSection(profile: _profile!),
        _SupplierDetailSection.access => _SupplierAccessSection(
            profile: _profile!,
            status: _credentialStatus,
            accessDenied: _credentialAccessDenied,
            loadError: _credentialStatusError,
            revealController: _credentialRevealController,
            canReveal: _source.canReadCredentialMetadata &&
                !_credentialAccessDenied &&
                _credentialStatusError == null,
            revealErrorTarget: _credentialRevealErrorTarget,
            revealErrorMessage: _credentialRevealErrorMessage,
            onReveal: _revealCredential,
            onCopy: _copyCredential,
            onHide: _hideCredential,
            onRetry: () => _load(preserveProfile: true),
          ),
        _SupplierDetailSection.movements => _SupplierMovementsSection(
            summaries: _economicSummaries,
            timeline: _economicTimeline!,
          ),
      },
    );
  }
}

bool _isCredentialPermissionError(Object error) {
  return error is SupplierCredentialAccessDenied ||
      (error is PostgrestException && error.code == '42501');
}

String _credentialTargetKey(SupplierCredentialRevealTarget target) =>
    '${target.supplierId}|${target.kind.dbValue}|${target.credentialKey}';

bool _sameCredentialMetadataBinding(
  SupplierCredentialMetadata? current,
  SupplierCredentialMetadata expected,
) {
  final currentVersion = current?.updatedAt?.toUtc();
  final expectedVersion = expected.updatedAt?.toUtc();
  return current != null &&
      current.tenantId == expected.tenantId &&
      current.supplierId == expected.supplierId &&
      current.kind == expected.kind &&
      current.credentialKey == expected.credentialKey &&
      current.engagementId == expected.engagementId &&
      current.originUrl == expected.originUrl &&
      current.secretAvailable == expected.secretAvailable &&
      currentVersion != null &&
      expectedVersion != null &&
      currentVersion.isAtSameMomentAs(expectedVersion);
}

class _SupplierDetailModuleHeader extends StatelessWidget {
  const _SupplierDetailModuleHeader();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    return Container(
      color: roles.shell.canvas,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
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
    );
  }
}

class _SupplierDetailBack extends StatelessWidget {
  const _SupplierDetailBack({
    required this.onPressed,
    required this.compact,
  });

  final VoidCallback onPressed;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        key: const ValueKey('supplier-detail-back'),
        onPressed: onPressed,
        icon: const Icon(Icons.chevron_left, size: 18),
        label: const Text('Volver al directorio'),
        style: TextButton.styleFrom(
          minimumSize: Size(0, compact ? 48 : 38),
          padding: const EdgeInsets.symmetric(horizontal: 4),
          foregroundColor: theme.colorScheme.onSurfaceVariant,
          textStyle: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _SupplierRecordHeader extends StatelessWidget {
  const _SupplierRecordHeader({
    required this.profile,
    required this.compact,
    required this.onEdit,
  });

  final SupplierProfile profile;
  final bool compact;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final identifier = _primaryIdentifier(profile.party);
    final subtitleParts = <String>[
      _partyKindLabel(profile.party.kind),
      if (identifier?.value.trim().isNotEmpty == true) identifier!.value,
    ];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'PROVEEDOR',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  letterSpacing: .8,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                profile.displayName,
                style: (compact
                        ? theme.textTheme.titleLarge
                        : theme.textTheme.headlineSmall)
                    ?.copyWith(fontWeight: FontWeight.w600, height: 1.2),
              ),
              const SizedBox(height: 6),
              Text(
                subtitleParts.join(' · '),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 14),
        OutlinedButton(
          key: const ValueKey('supplier-detail-edit'),
          onPressed: onEdit,
          style: OutlinedButton.styleFrom(
            minimumSize: Size(0, compact ? 48 : 38),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            foregroundColor: theme.colorScheme.onSurface,
            side: BorderSide(color: theme.colorScheme.outline),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
            textStyle: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          child: const Text('Editar'),
        ),
      ],
    );
  }
}

class _SupplierSectionRail extends StatelessWidget {
  const _SupplierSectionRail({
    required this.sections,
    required this.selected,
    required this.onSelected,
  });

  final List<_SupplierDetailSection> sections;
  final _SupplierDetailSection selected;
  final ValueChanged<_SupplierDetailSection> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 7),
          child: Text(
            'SECCIONES',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              letterSpacing: .8,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        for (final section in sections)
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Material(
              color: section == selected
                  ? roles.selectionContainer
                  : Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
              child: InkWell(
                key: ValueKey('supplier-detail-nav-${section.name}'),
                onTap: () => onSelected(section),
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 36),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: section == selected
                      ? BoxDecoration(
                          border: Border(
                            left: BorderSide(
                              color: roles.info.accent,
                              width: 3,
                            ),
                          ),
                        )
                      : null,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    section.label,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: section == selected
                          ? theme.colorScheme.onSurface
                          : theme.colorScheme.onSurfaceVariant,
                      fontWeight: section == selected
                          ? FontWeight.w600
                          : FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _SupplierSectionHeading extends StatelessWidget {
  const _SupplierSectionHeading({
    required this.title,
    required this.description,
  });

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            description,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _SupplierBlockLabel extends StatelessWidget {
  const _SupplierBlockLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      label.toUpperCase(),
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        letterSpacing: .8,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _SupplierPanel extends StatelessWidget {
  const _SupplierPanel({
    required this.child,
    this.padding = EdgeInsets.zero,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: roles.shadow.withValues(alpha: .06),
            offset: const Offset(0, 1),
            blurRadius: 2,
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

class _SupplierDataRow extends StatelessWidget {
  const _SupplierDataRow({
    required this.label,
    required this.value,
    this.first = false,
  });

  final String label;
  final String value;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        border: first
            ? null
            : Border(
                top: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _partyKindLabel(ExternalPartyKind kind) => switch (kind) {
      ExternalPartyKind.organization => 'Organización',
      ExternalPartyKind.person => 'Persona',
      ExternalPartyKind.publicAuthority => 'Organismo público',
      ExternalPartyKind.other => 'Sin especificar',
    };

class _SupplierSummarySection extends StatelessWidget {
  const _SupplierSummarySection({
    required this.profile,
    required this.summaries,
    required this.credentialStatus,
    required this.showEconomicActivity,
  });

  final SupplierProfile profile;
  final List<SupplierEconomicSummaryReadModel> summaries;
  final SupplierCredentialStatus? credentialStatus;
  final bool showEconomicActivity;

  @override
  Widget build(BuildContext context) {
    final activeEngagements = profile.engagements
        .where((item) => item.status == SupplierEngagementStatus.active)
        .toList(growable: false);
    final pendingIncidents = profile.attentionSignals?.validationIncidents
            .where(
              (incident) =>
                  incident.status == SupplierValidationIncidentStatus.pending,
            )
            .toList(growable: false) ??
        const <SupplierValidationIncident>[];
    final credentials = credentialStatus?.credentials ?? const [];
    final hasStoredSecret = credentials.any(
      (credential) => credential.secretAvailable,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SupplierSectionHeading(
          title: 'Resumen',
          description: 'Lo que necesitas saber sin entrar a ninguna sección.',
        ),
        if (activeEngagements.isNotEmpty ||
            profile.serviceRelationshipSummary != null) ...[
          const _SupplierBlockLabel('Relaciones vigentes'),
          const SizedBox(height: 7),
          if (activeEngagements.isNotEmpty)
            _SupplierPanel(
              child: Column(
                children: [
                  for (var index = 0; index < activeEngagements.length; index++)
                    _SupplierDataRow(
                      first: index == 0,
                      label: activeEngagements[index].name,
                      value: _engagementCurrentTerms(activeEngagements[index]),
                    ),
                ],
              ),
            )
          else
            _SupplierPanel(
              child: _SupplierDataRow(
                first: true,
                label: 'Relaciones',
                value: profile.serviceRelationshipSummary!,
              ),
            ),
          const SizedBox(height: 6),
          Text(
            'Cada una tiene su propia historia y sus propios criterios.',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
          ),
          const SizedBox(height: 20),
        ],
        if (pendingIncidents.isNotEmpty) ...[
          const _SupplierBlockLabel('Incidencias'),
          const SizedBox(height: 7),
          for (var index = 0; index < pendingIncidents.length; index++) ...[
            _SupplierIncidentNotice(incident: pendingIncidents[index]),
            if (index != pendingIncidents.length - 1) const SizedBox(height: 8),
          ],
          const SizedBox(height: 20),
        ],
        if (credentials.isNotEmpty) ...[
          _SupplierBlockLabel('Accesos · ${credentials.length}'),
          const SizedBox(height: 7),
          _SupplierPanel(
            child: Column(
              children: [
                for (var index = 0; index < credentials.length; index++)
                  _SupplierDataRow(
                    first: index == 0,
                    label: credentials[index].label ?? 'Acceso',
                    value: credentials[index].originUrl ??
                        credentials[index].username ??
                        'Cuenta protegida',
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            hasStoredSecret
                ? 'Las claves disponibles se piden aparte, una por una.'
                : 'Estos accesos conservan la cuenta, pero no tienen una clave guardada.',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
          ),
          const SizedBox(height: 20),
        ],
        if (showEconomicActivity) ...[
          const _SupplierBlockLabel('Movimiento económico'),
          const SizedBox(height: 7),
          for (var index = 0; index < summaries.length; index++) ...[
            _SupplierEconomicSummaryPanel(summary: summaries[index]),
            if (index != summaries.length - 1) const SizedBox(height: 10),
          ],
        ] else if (_hasFreeCurrentEngagement(activeEngagements)) ...[
          const _SupplierBlockLabel('Estado'),
          const SizedBox(height: 7),
          const VbNotice(
            title: 'Relación vigente sin cobro',
            body:
                'El ciclo de cobro publicado para esta relación es Sin costo.',
            tone: VbNoticeTone.success,
          ),
        ],
      ],
    );
  }
}

class _SupplierEconomicSummaryPanel extends StatelessWidget {
  const _SupplierEconomicSummaryPanel({required this.summary});

  final SupplierEconomicSummaryReadModel summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final coverage = _provenanceLabel(summary);
    return _SupplierPanel(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _SupplierBlockLabel(
                'Movimiento económico · ${summary.currencyCode}',
              ),
              Text(
                'compras y gastos no se suman entre sí',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (summary.purchases.documentCount > 0)
            _EconomicUniverseLine(
              label: 'Compras',
              value: _economicBreakdownText(
                summary.purchases,
                summary.currencyCode,
              ),
            ),
          if (summary.expenses.documentCount > 0)
            _EconomicUniverseLine(
              label: 'Gastos',
              value: _economicBreakdownText(
                summary.expenses,
                summary.currencyCode,
              ),
            ),
          if (coverage != null) ...[
            const SizedBox(height: 9),
            Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: _economicStatusColor(context, summary),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    coverage,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _EconomicUniverseLine extends StatelessWidget {
  const _EconomicUniverseLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SupplierIncidentNotice extends StatelessWidget {
  const _SupplierIncidentNotice({required this.incident});

  final SupplierValidationIncident incident;

  @override
  Widget build(BuildContext context) {
    final tone = switch (incident.severity) {
      SupplierValidationIncidentSeverity.error => VbNoticeTone.danger,
      SupplierValidationIncidentSeverity.warning => VbNoticeTone.warning,
      SupplierValidationIncidentSeverity.info => VbNoticeTone.info,
      SupplierValidationIncidentSeverity.unknown => VbNoticeTone.neutral,
    };
    return VbNotice(
      title: incident.displayReason,
      tone: tone,
    );
  }
}

String _engagementCurrentTerms(SupplierEngagement engagement) {
  final version = engagement.currentVersion;
  if (version == null) return _engagementStatusLabel(engagement.status);
  final parts = <String>[_billingCadenceLabel(version.billingCadence)];
  if (version.dueDay != null) parts.add('vence el ${version.dueDay}');
  return parts.join(' · ');
}

bool _hasFreeCurrentEngagement(List<SupplierEngagement> engagements) =>
    engagements.any((engagement) => engagement.currentVersion?.isFree == true);

String _billingCadenceLabel(String value) => switch (value) {
      'free' => 'Sin costo',
      'monthly' => 'Mensual',
      'bimonthly' => 'Bimensual',
      'quarterly' => 'Trimestral',
      'semiannual' => 'Semestral',
      'annual' => 'Anual',
      'irregular' => 'Cobro irregular',
      _ => 'Condición vigente',
    };

String _engagementStatusLabel(SupplierEngagementStatus value) =>
    switch (value) {
      SupplierEngagementStatus.draft => 'Borrador',
      SupplierEngagementStatus.active => 'Rige hoy',
      SupplierEngagementStatus.suspended => 'Suspendida',
      SupplierEngagementStatus.ended => 'Finalizada',
    };

String _economicBreakdownText(
  SupplierEconomicAmountBreakdown breakdown,
  String currencyCode,
) {
  final parts = <String>[
    '${breakdown.documentCount} ${breakdown.documentCount == 1 ? 'documento' : 'documentos'}',
  ];
  if (breakdown.grossAmount != null) {
    parts.add(
        'registrado ${_formatMoney(breakdown.grossAmount!, currencyCode)}');
  }
  if (breakdown.paidAmount != null) {
    parts.add('pagado ${_formatMoney(breakdown.paidAmount!, currencyCode)}');
  }
  if (breakdown.balanceAmount != null) {
    parts.add(
        'pendiente ${_formatMoney(breakdown.balanceAmount!, currencyCode)}');
  }
  if (breakdown.paymentCount > 0) {
    parts.add(
      '${breakdown.paymentCount} ${breakdown.paymentCount == 1 ? 'pago' : 'pagos'}',
    );
  }
  return parts.join(' · ');
}

String? _provenanceLabel(SupplierEconomicSummaryReadModel summary) {
  return switch (summary.provenanceStatus) {
    'complete' =>
      'Cobertura completa · ${summary.tracedDocumentCount} movimientos trazables',
    'partial' =>
      'Cobertura parcial · ${summary.tracedDocumentCount} movimientos trazables',
    'none' => 'Cobertura pendiente de trazabilidad',
    'not_applicable' => null,
    _ => null,
  };
}

Color _economicStatusColor(
  BuildContext context,
  SupplierEconomicSummaryReadModel summary,
) {
  final roles = VinabikeThemeRoles.of(context);
  return switch (summary.provenanceStatus) {
    'complete' => roles.success.accent,
    'partial' => roles.warning.accent,
    _ => roles.neutral.accent,
  };
}

String _formatMoney(double amount, String currencyCode) {
  final format = NumberFormat.currency(
    locale: 'es_CL',
    symbol: currencyCode == 'CLP' ? r'$' : '$currencyCode ',
    decimalDigits: currencyCode == 'CLP' ? 0 : 2,
  );
  return format.format(amount);
}

class _SupplierIdentitySection extends StatelessWidget {
  const _SupplierIdentitySection({required this.profile});

  final SupplierProfile profile;

  @override
  Widget build(BuildContext context) {
    final party = profile.party;
    final relationship = profile.relationship;
    final legacy = profile.legacyDetails;
    final identifier = _primaryIdentifier(party);
    final address = [
      legacy.address,
      legacy.comuna,
      legacy.city,
      legacy.region,
    ].whereType<String>().where((value) => value.trim().isNotEmpty).join(', ');
    final values = <({String label, String value})>[
      (label: 'Nombre visible', value: party.displayName),
      if (_present(party.legalName))
        (label: 'Razón social', value: party.legalName!),
      if (_present(party.tradeName))
        (label: 'Nombre comercial', value: party.tradeName!),
      (label: 'Tipo de entidad', value: _partyKindLabel(party.kind)),
      if (identifier != null)
        (label: 'Identificador tributario', value: identifier.value),
      if (_present(party.countryCode))
        (label: 'País', value: party.countryCode!),
      if (_present(relationship.contactPerson))
        (label: 'Contacto', value: relationship.contactPerson!),
      if (_present(relationship.email))
        (label: 'Correo', value: relationship.email!),
      if (_present(relationship.phone))
        (label: 'Teléfono', value: relationship.phone!),
      if (_present(relationship.website))
        (label: 'Sitio web', value: relationship.website!),
      if (address.isNotEmpty) (label: 'Dirección', value: address),
      if (_present(relationship.notes))
        (label: 'Notas', value: relationship.notes!),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SupplierSectionHeading(
          title: 'Identidad',
          description: 'Datos legales y de contacto de este proveedor.',
        ),
        const _SupplierBlockLabel('Datos vigentes'),
        const SizedBox(height: 7),
        _SupplierPanel(
          child: Column(
            children: [
              for (var index = 0; index < values.length; index++)
                _SupplierDataRow(
                  first: index == 0,
                  label: values[index].label,
                  value: values[index].value,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SupplierClassificationSection extends StatelessWidget {
  const _SupplierClassificationSection({required this.profile});

  final SupplierProfile profile;

  @override
  Widget build(BuildContext context) {
    final relationship = profile.relationship;
    final signal = profile.attentionSignals?.classificationStatus;
    final purposes = relationship.roles
        .map(
          (role) => _relationshipPurposeLabel(
            role.code,
            _classificationLabel(role.label, 'Relación vigente'),
          ),
        )
        .toList(growable: false);
    final details = relationship.capabilities
        .map(
          (capability) => _relationshipDetailLabel(
            capability.code,
            _classificationLabel(capability.label, 'Detalle vigente'),
          ),
        )
        .toList(growable: false);
    final internalTags = relationship.tags
        .where((tag) => !_systemRelationshipTagCodes.contains(tag.code))
        .map((tag) => _classificationLabel(tag.label, 'Etiqueta interna'))
        .toList(growable: false);
    final hasValues = purposes.isNotEmpty || details.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SupplierSectionHeading(
          title: 'Para qué lo usamos',
          description:
              'Define dónde aparece y qué información se puede configurar. No contabiliza ni automatiza por sí sola.',
        ),
        if (signal == SupplierProfileClassificationStatus.unclassified) ...[
          const VbNotice(
            title: 'Clasificación pendiente',
            body:
                'El servidor publicó este proveedor como pendiente de clasificar.',
            tone: VbNoticeTone.warning,
          ),
          const SizedBox(height: 16),
        ] else if (!hasValues &&
            signal == SupplierProfileClassificationStatus.notApplicable) ...[
          const VbNotice(
            title: 'Clasificación no aplicable',
            tone: VbNoticeTone.neutral,
          ),
          const SizedBox(height: 16),
        ],
        if (purposes.isNotEmpty) ...[
          const _SupplierBlockLabel('Relaciones vigentes'),
          const SizedBox(height: 7),
          _SupplierPanel(
            child: Column(
              children: [
                for (var index = 0; index < purposes.length; index++)
                  _SupplierPlainValueRow(
                    first: index == 0,
                    value: purposes[index],
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (details.isNotEmpty || internalTags.isNotEmpty) ...[
          _SupplierPanel(
            child: Column(
              children: [
                if (details.isNotEmpty)
                  _SupplierDataRow(
                    first: true,
                    label: 'Detalles operativos',
                    value: details.join(' · '),
                  ),
                if (internalTags.isNotEmpty)
                  _SupplierDataRow(
                    first: details.isEmpty,
                    label: 'Organización interna',
                    value: internalTags.join(' · '),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
        const _SupplierBlockLabel('Naturaleza operacional'),
        const SizedBox(height: 7),
        const VbNotice(
          title: 'Se define en cada criterio contable',
          body:
              'No es una propiedad del proveedor: una misma contraparte puede facturar cosas de naturaleza distinta.',
          tone: VbNoticeTone.info,
        ),
      ],
    );
  }
}

const _systemRelationshipTagCodes = <String>{
  'digital',
  'transport',
  'government',
  'facility',
  'recurring',
  'essential_service',
};

String _relationshipPurposeLabel(String code, String fallback) =>
    switch (code) {
      'goods_vendor' => 'Bienes y repuestos',
      'service_provider' => 'Servicios',
      'digital_platform' => 'Servicios digitales',
      'logistics_provider' => 'Transporte y logística',
      'utility_provider' => 'Servicios básicos',
      'landlord' => 'Arrendamiento',
      'government_authority' => 'Impuestos y obligaciones públicas',
      'operational_resource' => 'Recurso o portal operativo',
      _ => fallback,
    };

String _relationshipDetailLabel(String code, String fallback) => switch (code) {
      'inventory_goods' => 'Inventario y reventa',
      'workshop_consumables' => 'Insumos de taller',
      'freight_transport' => 'Flete o despacho',
      'digital_services' => 'Software, dominio, red o publicidad',
      'utilities' => 'Luz, agua u otro suministro',
      'rent_lease' => 'Arriendo de local, inmueble o activo',
      'tax_payments' => 'Impuestos, tasas o permisos',
      'credential_portal' => 'Acceso, enlace o cuenta operativa',
      'purchase_invoices' => 'Documentos de compra',
      _ => fallback,
    };

class _SupplierPlainValueRow extends StatelessWidget {
  const _SupplierPlainValueRow({
    required this.value,
    required this.first,
  });

  final String value;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 48),
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        border: first
            ? null
            : Border(
                top: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
      ),
      child: Text(
        value,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

ExternalPartyIdentifier? _primaryIdentifier(ExternalParty party) {
  for (final identifier in party.identifiers) {
    if (identifier.isPrimary) return identifier;
  }
  return party.identifiers.isEmpty ? null : party.identifiers.first;
}

bool _present(String? value) => value?.trim().isNotEmpty == true;

String _classificationLabel(String? publishedLabel, String fallback) {
  final value = publishedLabel?.trim();
  return value == null || value.isEmpty ? fallback : value;
}

class _SupplierRelationshipsSection extends StatelessWidget {
  const _SupplierRelationshipsSection({required this.profile});

  final SupplierProfile profile;

  @override
  Widget build(BuildContext context) {
    final engagements = [...profile.engagements]..sort((left, right) {
        final activeOrder = _engagementStatusOrder(left.status)
            .compareTo(_engagementStatusOrder(right.status));
        if (activeOrder != 0) return activeOrder;
        return left.name.toLowerCase().compareTo(right.name.toLowerCase());
      });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SupplierSectionHeading(
          title: 'Relaciones',
          description:
              'Convenios, servicios y sedes. Qué rige hoy y desde cuándo.',
        ),
        for (var index = 0; index < engagements.length; index++) ...[
          _SupplierEngagementPanel(
            engagement: engagements[index],
            site: _siteFor(profile.sites, engagements[index].businessSiteId),
          ),
          if (index != engagements.length - 1) const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _SupplierEngagementPanel extends StatelessWidget {
  const _SupplierEngagementPanel({
    required this.engagement,
    required this.site,
  });

  final SupplierEngagement engagement;
  final BusinessSite? site;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final version = engagement.currentVersion;
    final details = <({String label, String value})>[
      (
        label: 'Tipo',
        value: _engagementKindLabel(engagement.kind),
      ),
      if (engagement.startsOn != null)
        (
          label: 'Desde',
          value: _formatMonthYear(engagement.startsOn!),
        ),
      if (version != null)
        (
          label: 'Versión vigente',
          value:
              'v${version.version} · ${_billingCadenceLabel(version.billingCadence)}',
        ),
      if (version?.dueDay != null)
        (label: 'Vencimiento', value: 'día ${version!.dueDay}'),
      if (site != null) (label: 'Sede', value: site!.name),
      if (_present(version?.serviceIdentifier))
        (label: 'Referencia', value: version!.serviceIdentifier!),
    ];
    return _SupplierPanel(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  engagement.name,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              VbStatusBadge(
                label: _engagementStatusLabel(engagement.status),
                tone: _engagementStatusTone(engagement.status),
              ),
            ],
          ),
          const SizedBox(height: 9),
          for (var index = 0; index < details.length; index++)
            _CompactFactRow(
              label: details[index].label,
              value: details[index].value,
              first: index == 0,
            ),
        ],
      ),
    );
  }
}

class _CompactFactRow extends StatelessWidget {
  const _CompactFactRow({
    required this.label,
    required this.value,
    this.first = false,
  });

  final String label;
  final String value;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 40),
      decoration: BoxDecoration(
        border: first
            ? null
            : Border(
                top: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SupplierAccountingSection extends StatelessWidget {
  const _SupplierAccountingSection({required this.profile});

  final SupplierProfile profile;

  @override
  Widget build(BuildContext context) {
    final signal = profile.attentionSignals?.accountingPolicyStatus;
    final policies = [...profile.accounting.policies]
      ..sort((left, right) => left.priority.compareTo(right.priority));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SupplierSectionHeading(
          title: 'Criterios contables',
          description:
              'Configuración versionada por contexto. Esta ficha no clasifica ni contabiliza operaciones.',
        ),
        if (signal == SupplierProfileAccountingPolicyStatus.missingPolicy) ...[
          const VbNotice(
            title: 'Falta configurar un criterio contable',
            body: 'Este estado fue publicado por la proyección del proveedor.',
            tone: VbNoticeTone.warning,
          ),
          if (policies.isNotEmpty) const SizedBox(height: 16),
        ],
        for (var index = 0; index < policies.length; index++) ...[
          _SupplierAccountingPolicyPanel(
            policy: policies[index],
            rules: profile.accounting.rules,
          ),
          if (index != policies.length - 1) const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _SupplierAccountingPolicyPanel extends StatelessWidget {
  const _SupplierAccountingPolicyPanel({
    required this.policy,
    required this.rules,
  });

  final SupplierAccountingPolicySummary policy;
  final List<SupplierAccountingRuleSummary> rules;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final version = policy.currentVersion;
    final activeRules = version == null
        ? const <SupplierAccountingRuleSummary>[]
        : rules
            .where(
              (rule) => rule.policyVersionId == version.id && rule.isActive,
            )
            .toList(growable: false);
    final details = <({String label, String value})>[
      if (version != null)
        (
          label: 'Versión vigente',
          value:
              'v${version.version} · desde ${_formatDate(version.effectiveFrom)}',
        ),
      if (_present(version?.operationalNatureLabel))
        (
          label: 'Naturaleza operacional',
          value: version!.operationalNatureLabel!,
        ),
      if (version != null)
        (
          label: 'Tratamiento tributario',
          value: _taxTreatmentLabel(version.taxTreatmentCode),
        ),
      if (version != null) (label: 'Moneda', value: version.currencyCode),
      if (_present(version?.expectedDocumentType))
        (
          label: 'Documento esperado',
          value: version!.expectedDocumentType!,
        ),
      (
        label: 'Reglas vigentes',
        value: activeRules.length.toString(),
      ),
    ];
    return _SupplierPanel(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  policy.name,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              VbStatusBadge(
                label: _accountingPolicyStatusLabel(policy.status),
                tone: _accountingPolicyStatusTone(policy.status),
              ),
            ],
          ),
          const SizedBox(height: 9),
          for (var index = 0; index < details.length; index++)
            _CompactFactRow(
              label: details[index].label,
              value: details[index].value,
              first: index == 0,
            ),
        ],
      ),
    );
  }
}

BusinessSite? _siteFor(List<BusinessSite> sites, String? siteId) {
  if (siteId == null) return null;
  for (final site in sites) {
    if (site.id == siteId) return site;
  }
  return null;
}

int _engagementStatusOrder(SupplierEngagementStatus status) => switch (status) {
      SupplierEngagementStatus.active => 0,
      SupplierEngagementStatus.draft => 1,
      SupplierEngagementStatus.suspended => 2,
      SupplierEngagementStatus.ended => 3,
    };

String _engagementKindLabel(SupplierEngagementKind kind) => switch (kind) {
      SupplierEngagementKind.contract => 'Contrato',
      SupplierEngagementKind.serviceAccount => 'Cuenta de servicio',
      SupplierEngagementKind.subscription => 'Suscripción',
      SupplierEngagementKind.lease => 'Arriendo',
      SupplierEngagementKind.utility => 'Servicio básico',
      SupplierEngagementKind.taxObligation => 'Obligación tributaria',
      SupplierEngagementKind.portal => 'Portal',
      SupplierEngagementKind.other => 'Otra relación',
    };

VbStatusTone _engagementStatusTone(SupplierEngagementStatus status) =>
    switch (status) {
      SupplierEngagementStatus.active => VbStatusTone.success,
      SupplierEngagementStatus.draft => VbStatusTone.info,
      SupplierEngagementStatus.suspended => VbStatusTone.warning,
      SupplierEngagementStatus.ended => VbStatusTone.neutral,
    };

String _accountingPolicyStatusLabel(SupplierAccountingPolicyStatus status) =>
    switch (status) {
      SupplierAccountingPolicyStatus.draft => 'Borrador',
      SupplierAccountingPolicyStatus.active => 'Rige hoy',
      SupplierAccountingPolicyStatus.retired => 'Retirado',
    };

VbStatusTone _accountingPolicyStatusTone(
        SupplierAccountingPolicyStatus status) =>
    switch (status) {
      SupplierAccountingPolicyStatus.draft => VbStatusTone.info,
      SupplierAccountingPolicyStatus.active => VbStatusTone.success,
      SupplierAccountingPolicyStatus.retired => VbStatusTone.neutral,
    };

String _taxTreatmentLabel(String value) => switch (value) {
      'no_tax' => 'Sin impuesto',
      'tax_included' => 'Impuesto incluido',
      'exempt' => 'Exento',
      'not_applicable' => 'No aplica',
      _ => 'Tratamiento publicado',
    };

String _formatDate(DateTime value) {
  String twoDigits(int number) => number.toString().padLeft(2, '0');
  return '${twoDigits(value.day)}-${twoDigits(value.month)}-${value.year}';
}

String _formatMonthYear(DateTime value) {
  final month = value.month.toString().padLeft(2, '0');
  return '$month-${value.year}';
}

class _SupplierAccessSection extends StatelessWidget {
  const _SupplierAccessSection({
    required this.profile,
    required this.status,
    required this.accessDenied,
    required this.loadError,
    required this.revealController,
    required this.canReveal,
    required this.revealErrorTarget,
    required this.revealErrorMessage,
    required this.onReveal,
    required this.onCopy,
    required this.onHide,
    required this.onRetry,
  });

  final SupplierProfile profile;
  final SupplierCredentialStatus? status;
  final bool accessDenied;
  final Object? loadError;
  final SupplierCredentialRevealController? revealController;
  final bool canReveal;
  final String? revealErrorTarget;
  final String? revealErrorMessage;
  final ValueChanged<SupplierCredentialMetadata> onReveal;
  final ValueChanged<SupplierCredentialMetadata> onCopy;
  final VoidCallback onHide;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final credentials = status?.credentials ?? const [];
    final hasOriginBoundSecret = credentials.any(
      (credential) =>
          credential.secretAvailable && credential.originUrl != null,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SupplierSectionHeading(
          title: 'Accesos',
          description: credentials.any(
            (credential) => credential.secretAvailable,
          )
              ? 'Dónde entra y con qué cuenta. Las claves disponibles se piden aparte.'
              : 'Dónde entra y con qué cuenta. Puedes completar una clave desde el editor.',
        ),
        if (accessDenied)
          const VbNotice(
            title: 'No tienes permiso para ver los accesos',
            body:
                'Esta sección no se cargó. Pídele el permiso a quien administra el taller.',
            tone: VbNoticeTone.warning,
          )
        else if (loadError != null)
          VbNotice(
            title: 'No pudimos cargar los accesos',
            body: 'El resto del perfil sigue disponible.',
            tone: VbNoticeTone.warning,
            action: TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                minimumSize: const Size(48, 48),
              ),
              child: const Text('Reintentar'),
            ),
          )
        else ...[
          for (var index = 0; index < credentials.length; index++) ...[
            _SupplierCredentialMetadataPanel(
              metadata: credentials[index],
              engagement: _engagementFor(
                profile.engagements,
                credentials[index].engagementId,
              ),
              revealController: revealController,
              canReveal: canReveal,
              revealError: revealErrorTarget ==
                      _credentialTargetKey(
                        SupplierCredentialRevealTarget(
                          supplierId: credentials[index].supplierId,
                          kind: credentials[index].kind,
                          credentialKey: credentials[index].credentialKey,
                        ),
                      )
                  ? revealErrorMessage
                  : null,
              onReveal: onReveal,
              onCopy: onCopy,
              onHide: onHide,
            ),
            if (index != credentials.length - 1) const SizedBox(height: 10),
          ],
          if (hasOriginBoundSecret) ...[
            const SizedBox(height: 12),
            const VbNotice(
              title: 'Origen HTTPS exacto',
              body:
                  'La clave se usa sólo en el origen autorizado. No se prueban variantes como www ni el sitio general del proveedor.',
              tone: VbNoticeTone.info,
            ),
          ],
        ],
      ],
    );
  }
}

class _SupplierCredentialMetadataPanel extends StatelessWidget {
  const _SupplierCredentialMetadataPanel({
    required this.metadata,
    required this.engagement,
    required this.revealController,
    required this.canReveal,
    required this.revealError,
    required this.onReveal,
    required this.onCopy,
    required this.onHide,
  });

  final SupplierCredentialMetadata metadata;
  final SupplierEngagement? engagement;
  final SupplierCredentialRevealController? revealController;
  final bool canReveal;
  final String? revealError;
  final ValueChanged<SupplierCredentialMetadata> onReveal;
  final ValueChanged<SupplierCredentialMetadata> onCopy;
  final VoidCallback onHide;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final target = SupplierCredentialRevealTarget(
      supplierId: metadata.supplierId,
      kind: metadata.kind,
      credentialKey: metadata.credentialKey,
    );
    final controller = revealController;
    final ownsTarget = controller != null &&
        controller.target != null &&
        _credentialTargetKey(controller.target!) ==
            _credentialTargetKey(target);
    final revealing = ownsTarget && controller.isRevealing;
    final visible = ownsTarget &&
        controller.isVisible &&
        _sameCredentialMetadataBinding(controller.metadata, metadata);
    final revealedSecret = visible ? controller.revealedSecret : null;
    final facts = <({String label, String value})>[
      if (_present(metadata.originUrl))
        (label: 'Entra en', value: metadata.originUrl!),
      if (_present(metadata.username))
        (label: 'Usuario', value: metadata.username!),
      if (engagement != null) (label: 'Relación', value: engagement!.name),
      if (metadata.updatedAt != null)
        (
          label: 'Actualizado',
          value: _formatDate(metadata.updatedAt!.toLocal()),
        ),
    ];
    return _SupplierPanel(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  metadata.label ?? 'Acceso protegido',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (!metadata.secretAvailable)
                Text(
                  'Sin clave guardada',
                  key: ValueKey(
                    'supplier-credential-no-secret-${metadata.kind.dbValue}-${metadata.credentialKey}',
                  ),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                )
              else if (visible)
                Text(
                  'Visible ahora',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                )
              else if (canReveal && controller != null)
                TextButton(
                  key: ValueKey(
                    'supplier-credential-reveal-${metadata.kind.dbValue}-${metadata.credentialKey}',
                  ),
                  onPressed: revealing ? null : () => onReveal(metadata),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(48, 48),
                  ),
                  child: Text(revealing ? 'Abriendo…' : 'Ver la clave'),
                ),
            ],
          ),
          if (facts.isNotEmpty) const SizedBox(height: 5),
          for (var index = 0; index < facts.length; index++)
            _CompactFactRow(
              label: facts[index].label,
              value: facts[index].value,
              first: index == 0,
            ),
          if (revealedSecret != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
              decoration: BoxDecoration(
                color: roles.warning.container,
                border: Border.all(color: roles.warning.border),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          revealedSecret,
                          key: ValueKey(
                            'supplier-credential-secret-${metadata.kind.dbValue}-${metadata.credentialKey}',
                          ),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: roles.warning.onContainer,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'se oculta sola',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: roles.warning.onContainer,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Wrap(
                    children: [
                      TextButton(
                        key: ValueKey(
                          'supplier-credential-copy-${metadata.kind.dbValue}-${metadata.credentialKey}',
                        ),
                        onPressed: () => onCopy(metadata),
                        style: TextButton.styleFrom(
                          minimumSize: const Size(48, 48),
                        ),
                        child: const Text('Copiar'),
                      ),
                      TextButton(
                        key: ValueKey(
                          'supplier-credential-hide-${metadata.kind.dbValue}-${metadata.credentialKey}',
                        ),
                        onPressed: onHide,
                        style: TextButton.styleFrom(
                          minimumSize: const Size(48, 48),
                        ),
                        child: const Text('Ocultar'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Queda registrado quién lo vio y cuándo.',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          if (revealError != null) ...[
            const SizedBox(height: 8),
            Text(
              revealError!,
              key: ValueKey(
                'supplier-credential-reveal-error-${metadata.kind.dbValue}-${metadata.credentialKey}',
              ),
              style: theme.textTheme.labelMedium?.copyWith(
                color: roles.warning.accent,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

SupplierEngagement? _engagementFor(
  List<SupplierEngagement> engagements,
  String? engagementId,
) {
  if (engagementId == null) return null;
  for (final engagement in engagements) {
    if (engagement.id == engagementId) return engagement;
  }
  return null;
}

class _SupplierMovementsSection extends StatelessWidget {
  const _SupplierMovementsSection({
    required this.summaries,
    required this.timeline,
  });

  final List<SupplierEconomicSummaryReadModel> summaries;
  final SupplierEconomicTimelinePage timeline;

  @override
  Widget build(BuildContext context) {
    final activities = timeline.timeline.activities;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SupplierSectionHeading(
          title: 'Movimientos',
          description:
              'Documentos y pagos reconocidos por la proyección económica.',
        ),
        for (var index = 0; index < summaries.length; index++) ...[
          _SupplierEconomicSummaryPanel(summary: summaries[index]),
          const SizedBox(height: 14),
        ],
        if (activities.isNotEmpty) ...[
          const _SupplierBlockLabel('Actividad reconocida'),
          const SizedBox(height: 7),
          _SupplierPanel(
            child: Column(
              children: [
                for (var index = 0; index < activities.length; index++)
                  _SupplierEconomicActivityRow(
                    activity: activities[index],
                    first: index == 0,
                  ),
              ],
            ),
          ),
          if (timeline.hasMore) ...[
            const SizedBox(height: 7),
            Text(
              'Hay más actividad disponible en la proyección.',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ],
        ],
      ],
    );
  }
}

class _SupplierEconomicActivityRow extends StatelessWidget {
  const _SupplierEconomicActivityRow({
    required this.activity,
    required this.first,
  });

  final SupplierEconomicActivity activity;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reference = _present(activity.documentNumber)
        ? activity.documentNumber!
        : _formatDate(activity.occurredAt);
    final amount =
        activity.grossAmount != 0 ? activity.grossAmount : activity.paidAmount;
    return Container(
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        border: first
            ? null
            : Border(
                top: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _economicActivityLabel(activity.kind),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$reference · ${_formatDate(activity.occurredAt)}',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _formatMoney(amount, activity.currencyCode),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              VbStatusBadge(
                label: _economicQualityLabel(activity.dataQualityStatus),
                tone: _economicQualityTone(activity.dataQualityStatus),
                dense: true,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String _economicActivityLabel(SupplierEconomicActivityKind kind) =>
    switch (kind) {
      SupplierEconomicActivityKind.purchaseInvoice => 'Documento de compra',
      SupplierEconomicActivityKind.expense => 'Gasto',
      SupplierEconomicActivityKind.purchasePayment => 'Pago de compra',
      SupplierEconomicActivityKind.expensePayment => 'Pago de gasto',
      SupplierEconomicActivityKind.purchaseCreditNote =>
        'Nota de crédito de compra',
      SupplierEconomicActivityKind.purchaseSupplierRefund =>
        'Devolución del proveedor',
      SupplierEconomicActivityKind.creditNote => 'Nota de crédito',
      SupplierEconomicActivityKind.suppliedProduct => 'Producto suministrado',
      SupplierEconomicActivityKind.other => 'Movimiento reconocido',
    };

String _economicQualityLabel(SupplierEconomicDataQualityStatus status) =>
    switch (status) {
      SupplierEconomicDataQualityStatus.complete => 'completo',
      SupplierEconomicDataQualityStatus.needsReview => 'revisar',
      SupplierEconomicDataQualityStatus.notRecognized => 'no reconocido',
      SupplierEconomicDataQualityStatus.notApplicable => 'no aplica',
      SupplierEconomicDataQualityStatus.lifecycleOnly => 'ciclo de vida',
      SupplierEconomicDataQualityStatus.unknown => 'estado publicado',
    };

VbStatusTone _economicQualityTone(SupplierEconomicDataQualityStatus status) =>
    switch (status) {
      SupplierEconomicDataQualityStatus.complete => VbStatusTone.success,
      SupplierEconomicDataQualityStatus.needsReview => VbStatusTone.warning,
      SupplierEconomicDataQualityStatus.notRecognized => VbStatusTone.danger,
      SupplierEconomicDataQualityStatus.notApplicable ||
      SupplierEconomicDataQualityStatus.lifecycleOnly ||
      SupplierEconomicDataQualityStatus.unknown =>
        VbStatusTone.neutral,
    };

class _SupplierDetailError extends StatelessWidget {
  const _SupplierDetailError({
    required this.error,
    required this.onRetry,
    required this.onClose,
  });

  final Object error;
  final VoidCallback onRetry;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const VbNotice(
                title: 'No pudimos cargar este proveedor',
                body: 'Puedes reintentar o volver al directorio.',
                tone: VbNoticeTone.danger,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: onClose,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(48, 48),
                    ),
                    child: const Text('Volver'),
                  ),
                  FilledButton(
                    onPressed: onRetry,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(48, 48),
                    ),
                    child: const Text('Reintentar'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SupplierDetailNotFound extends StatelessWidget {
  const _SupplierDetailNotFound({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const VbNotice(
                title: 'Proveedor no encontrado',
                body: 'El registro ya no está disponible en este taller.',
                tone: VbNoticeTone.neutral,
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton(
                  onPressed: onClose,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(48, 48),
                  ),
                  child: const Text('Volver al directorio'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
