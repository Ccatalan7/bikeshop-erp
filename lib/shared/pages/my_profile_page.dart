import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;

import '../models/current_user_profile.dart';
import '../models/employee_self_service.dart';
import '../services/auth_service.dart';
import '../services/current_user_profile_service.dart';
import '../services/employee_self_service_service.dart';
import '../services/self_password_service.dart';
import '../services/tenant_service.dart';
import '../services/user_management_navigation.dart';
import '../services/workspace_manager.dart';
import '../utils/auth_input_validation.dart';
import '../utils/chilean_utils.dart';
import '../utils/responsive_breakpoints.dart';
import '../utils/responsive_viewport.dart';
import '../widgets/branded_loading.dart';
import '../widgets/main_layout.dart';

class MyProfilePage extends StatefulWidget {
  const MyProfilePage({super.key});

  @override
  State<MyProfilePage> createState() => _MyProfilePageState();
}

class _MyProfilePageState extends State<MyProfilePage> {
  final _contentKey = GlobalKey<MyProfileContentState>();
  final Object _workspaceCloseGuardOwner = Object();
  WorkspaceManager? _workspaceManager;
  String? _workspaceId;
  bool _navigationBlocked = false;
  bool _allowNextPop = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refresh(force: true);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bindWorkspaceCloseGuard();
  }

  void _bindWorkspaceCloseGuard() {
    WorkspaceManager? manager;
    Workspace? workspace;
    try {
      manager = context.read<WorkspaceManager>();
      workspace = context.read<Workspace>();
    } on ProviderNotFoundException {
      _unbindWorkspaceCloseGuard();
      return;
    }

    if (identical(_workspaceManager, manager) && _workspaceId == workspace.id) {
      return;
    }
    _unbindWorkspaceCloseGuard();
    if (manager.registerWorkspaceCloseGuard(
      workspaceId: workspace.id,
      owner: _workspaceCloseGuardOwner,
      guard: _confirmCanLeave,
    )) {
      _workspaceManager = manager;
      _workspaceId = workspace.id;
    }
  }

  void _unbindWorkspaceCloseGuard() {
    final manager = _workspaceManager;
    final workspaceId = _workspaceId;
    _workspaceManager = null;
    _workspaceId = null;
    if (manager == null || workspaceId == null) return;
    manager.unregisterWorkspaceCloseGuard(
      workspaceId: workspaceId,
      owner: _workspaceCloseGuardOwner,
    );
  }

  Future<void> _refresh({bool force = true}) async {
    final authService = context.read<AuthService>();
    final profileService = context.read<CurrentUserProfileService>();
    final user = authService.currentUser;
    await profileService.synchronize(
      identity: user == null ? null : CurrentUserIdentity.fromUser(user),
      resolveTenantId: context.read<TenantService>().getTenantId,
      force: force,
    );
    if (!mounted) return;
    // The labor read model is a separate scope; an explicit refresh of the
    // profile must refresh it too rather than leave a stale week behind.
    await context.read<EmployeeSelfServiceService>().synchronize(
          profile: profileService.profile,
          force: force,
        );
  }

  void _handleNavigationStateChanged(bool blocked) {
    if (!mounted || blocked == _navigationBlocked) return;
    setState(() => _navigationBlocked = blocked);
  }

  Future<bool> _confirmCanLeave() async {
    final contentState = _contentKey.currentState;
    if (contentState?.isSaving == true) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Espera a que termine el guardado antes de salir.'),
          ),
        );
      }
      return false;
    }
    return await contentState?.confirmDiscardIfNeeded() ?? !_navigationBlocked;
  }

  Future<void> _attemptBack() async {
    if (_allowNextPop) {
      if (mounted && context.canPop()) context.pop();
      return;
    }

    final canLeave = await _confirmCanLeave();
    if (!canLeave || !mounted || !context.canPop()) return;

    setState(() => _allowNextPop = true);
    await Future<void>.delayed(Duration.zero);
    if (mounted && context.canPop()) context.pop();
  }

  @override
  void dispose() {
    _unbindWorkspaceCloseGuard();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canPop = context.canPop();
    return PopScope(
      canPop: _allowNextPop || !_navigationBlocked,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_attemptBack());
      },
      child: MainLayout(
        title: 'Mi perfil',
        onBackPressed: canPop ? _attemptBack : null,
        compactHeader: MainLayoutCompactHeader(
          title: 'Mi perfil',
          actions: [
            IconButton(
              key: const ValueKey('erp-profile-refresh-compact'),
              tooltip: 'Actualizar perfil',
              onPressed: _navigationBlocked ? null : _refresh,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        child: MyProfileContent(
          key: _contentKey,
          onRefresh: _refresh,
          onNavigationStateChanged: _handleNavigationStateChanged,
        ),
      ),
    );
  }
}

@visibleForTesting
class MyProfileContent extends StatefulWidget {
  const MyProfileContent({
    required this.onRefresh,
    this.onNavigationStateChanged,
    super.key,
  });

  final Future<void> Function() onRefresh;
  final ValueChanged<bool>? onNavigationStateChanged;

  @override
  State<MyProfileContent> createState() => MyProfileContentState();
}

@visibleForTesting
class MyProfileContentState extends State<MyProfileContent> {
  final _scrollController = ScrollController();
  final _displayNameFormKey = GlobalKey<FormState>();
  final _contactFormKey = GlobalKey<FormState>();
  final _displayNameFocus = FocusNode();

  final _displayName = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _city = TextEditingController();
  final _emergencyName = TextEditingController();
  final _emergencyPhone = TextEditingController();

  CurrentUserProfileService? _service;
  String? _boundUserId;
  String? _boundEmployeeVersion;
  String _baselineDisplayName = '';
  String _baselinePhone = '';
  String _baselineAddress = '';
  String _baselineCity = '';
  String _baselineEmergencyName = '';
  String _baselineEmergencyPhone = '';
  bool _editingDisplayName = false;
  bool _editingContact = false;
  bool _dirty = false;
  bool _synchronizingControllers = false;
  String? _displayNameSaveError;
  String? _contactSaveError;
  _ProfileSectionId _selectedSection = _ProfileSectionId.personal;

  bool get isSaving => _service?.isSaving ?? false;

  @override
  void initState() {
    super.initState();
    for (final controller in _controllers) {
      controller.addListener(_recalculateDirty);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextService = context.read<CurrentUserProfileService>();
    if (identical(nextService, _service)) return;
    _service?.removeListener(_handleServiceChange);
    _service = nextService..addListener(_handleServiceChange);
    _synchronizeFromProfile(nextService.profile, force: true);
  }

  @override
  void didUpdateWidget(covariant MyProfileContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.onNavigationStateChanged != widget.onNavigationStateChanged) {
      _publishNavigationState();
    }
  }

  Iterable<TextEditingController> get _controllers sync* {
    yield _displayName;
    yield _phone;
    yield _address;
    yield _city;
    yield _emergencyName;
    yield _emergencyPhone;
  }

  void _handleServiceChange() {
    if (!mounted) return;
    final service = _service!;
    _synchronizeFromProfile(service.profile);
    _publishNavigationState();
  }

  void _synchronizeFromProfile(
    CurrentUserProfile? profile, {
    bool force = false,
  }) {
    if (profile == null) return;
    final employeeVersion = profile.employee?.updatedAt.toIso8601String();
    final identityChanged = _boundUserId != profile.userId;
    final authoritativeChanged = _boundEmployeeVersion != employeeVersion ||
        _baselineDisplayName != profile.displayName;

    if (!force &&
        !identityChanged &&
        (!authoritativeChanged || _dirty || _editingContact)) {
      return;
    }

    _synchronizingControllers = true;
    _displayName.text = profile.displayName;
    _phone.text = profile.employee?.phone ?? '';
    _address.text = profile.employee?.address ?? '';
    _city.text = profile.employee?.city ?? '';
    _emergencyName.text = profile.employee?.emergencyContactName ?? '';
    _emergencyPhone.text = profile.employee?.emergencyContactPhone ?? '';
    _baselineDisplayName = _normalize(_displayName.text);
    _baselinePhone = _normalize(_phone.text);
    _baselineAddress = _normalize(_address.text);
    _baselineCity = _normalize(_city.text);
    _baselineEmergencyName = _normalize(_emergencyName.text);
    _baselineEmergencyPhone = _normalize(_emergencyPhone.text);
    _boundUserId = profile.userId;
    _boundEmployeeVersion = employeeVersion;
    _synchronizingControllers = false;

    if (force || identityChanged) {
      _editingDisplayName = false;
      _editingContact = false;
      _displayNameSaveError = null;
      _contactSaveError = null;
    }
    _setDirty(false, rebuild: mounted);
  }

  String _normalize(String value) =>
      value.trim().replaceAll(RegExp(r'\s+'), ' ');

  void _recalculateDirty() {
    if (_synchronizingControllers || !mounted) return;
    final displayNameDirty = _editingDisplayName &&
        _normalize(_displayName.text) != _baselineDisplayName;
    final contactDirty = _editingContact &&
        (_normalize(_phone.text) != _baselinePhone ||
            _normalize(_address.text) != _baselineAddress ||
            _normalize(_city.text) != _baselineCity ||
            _normalize(_emergencyName.text) != _baselineEmergencyName ||
            _normalize(_emergencyPhone.text) != _baselineEmergencyPhone);
    _setDirty(displayNameDirty || contactDirty);
  }

  void _setDirty(bool value, {bool rebuild = true}) {
    if (_dirty == value) {
      _publishNavigationState();
      return;
    }
    if (rebuild) {
      setState(() => _dirty = value);
    } else {
      _dirty = value;
    }
    _publishNavigationState();
  }

  void _publishNavigationState() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onNavigationStateChanged?.call(_dirty || isSaving);
    });
  }

  Future<bool> confirmDiscardIfNeeded() async {
    if (isSaving) return false;
    if (!_dirty) return true;

    final discard = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        key: const ValueKey('erp-profile-discard-dialog'),
        title: const Text('¿Descartar cambios?'),
        content: const Text(
          'Los datos que editaste todavía no se han guardado.',
        ),
        actions: [
          TextButton(
            key: const ValueKey('erp-profile-discard-cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            style: TextButton.styleFrom(
              minimumSize: const Size(48, 48),
            ),
            child: const Text('Continuar editando'),
          ),
          FilledButton(
            key: const ValueKey('erp-profile-discard-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              minimumSize: const Size(48, 48),
            ),
            child: const Text('Descartar'),
          ),
        ],
      ),
    );
    if (discard == true && mounted) {
      _cancelEditing();
      return true;
    }
    return false;
  }

  void _beginDisplayNameEdit() {
    if (isSaving) return;
    setState(() {
      _editingDisplayName = true;
      _editingContact = false;
      _displayNameSaveError = null;
      _contactSaveError = null;
      _displayName.text = _baselineDisplayName;
      _dirty = false;
    });
    _publishNavigationState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _displayNameFocus.requestFocus();
    });
  }

  void _beginContactEdit() {
    if (isSaving) return;
    setState(() {
      _editingContact = true;
      _editingDisplayName = false;
      _contactSaveError = null;
      _displayNameSaveError = null;
      _dirty = false;
    });
    _publishNavigationState();
  }

  void _cancelEditing() {
    final profile = _service?.profile;
    _synchronizingControllers = true;
    _displayName.text = profile?.displayName ?? _baselineDisplayName;
    _phone.text = profile?.employee?.phone ?? _baselinePhone;
    _address.text = profile?.employee?.address ?? _baselineAddress;
    _city.text = profile?.employee?.city ?? _baselineCity;
    _emergencyName.text =
        profile?.employee?.emergencyContactName ?? _baselineEmergencyName;
    _emergencyPhone.text =
        profile?.employee?.emergencyContactPhone ?? _baselineEmergencyPhone;
    _synchronizingControllers = false;
    setState(() {
      _editingDisplayName = false;
      _editingContact = false;
      _displayNameSaveError = null;
      _contactSaveError = null;
      _dirty = false;
    });
    FocusManager.instance.primaryFocus?.unfocus();
    _publishNavigationState();
  }

  Future<void> _saveDisplayName() async {
    if (isSaving || _displayNameFormKey.currentState?.validate() != true) {
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _displayNameSaveError = null);
    _publishNavigationState();

    try {
      await _service!.updateDisplayName(_displayName.text);
      if (!mounted) return;
      _synchronizeFromProfile(_service!.profile, force: true);
      setState(() {
        _editingDisplayName = false;
        _dirty = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nombre visible actualizado')),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _displayNameSaveError =
            'No pudimos guardar el nombre. Tus cambios siguen aquí; revisa tu conexión e inténtalo nuevamente.';
      });
    } finally {
      _publishNavigationState();
    }
  }

  Future<void> _saveContact() async {
    if (isSaving || _contactFormKey.currentState?.validate() != true) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _contactSaveError = null);
    _publishNavigationState();

    try {
      await _service!.updateEmployeePersonalContact(
        EmployeePersonalContactUpdate(
          phone: _phone.text,
          address: _address.text,
          city: _city.text,
          emergencyContactName: _emergencyName.text,
          emergencyContactPhone: _emergencyPhone.text,
        ),
      );
      if (!mounted) return;
      _synchronizeFromProfile(_service!.profile, force: true);
      setState(() {
        _editingContact = false;
        _dirty = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Datos de contacto actualizados')),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _contactSaveError =
            'No pudimos guardar los datos. Tus cambios siguen aquí; revisa tu conexión e inténtalo nuevamente.';
      });
    } finally {
      _publishNavigationState();
    }
  }

  Future<void> _refreshSafely() async {
    if (_dirty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Guarda o cancela tus cambios antes de actualizar.'),
        ),
      );
      return;
    }
    await widget.onRefresh();
  }

  void _goToSection(_ProfileSectionId section) {
    if (section == _selectedSection) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _selectedSection = section);
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<CurrentUserProfileService>();
    final profile = service.profile;

    if (profile == null && service.isLoading) {
      return _ProfileLoadingWorkspace(
        showPageTitle: !ResponsiveViewport.usesCompactShell(context),
      );
    }
    if (profile == null) {
      return _ProfileLoadFailure(
        issue: service.loadIssue,
        onRetry: widget.onRefresh,
        showPageTitle: !ResponsiveViewport.usesCompactShell(context),
      );
    }

    final stale = service.loadIssue == CurrentUserProfileLoadIssue.unavailable;
    return SafeArea(
      top: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final desktop =
              constraints.maxWidth >= ResponsiveBreakpoints.desktopMin;
          final pagePadding = desktop
              ? 28.0
              : constraints.maxWidth >= ResponsiveBreakpoints.phoneMaxExclusive
                  ? 22.0
                  : 14.0;

          return Stack(
            children: [
              RefreshIndicator(
                onRefresh: _refreshSafely,
                child: SingleChildScrollView(
                  key: const ValueKey('erp-profile-scroll'),
                  controller: _scrollController,
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(
                    pagePadding,
                    constraints.maxWidth >= ResponsiveBreakpoints.desktopMin
                        ? 24
                        : 16,
                    pagePadding,
                    48 + MediaQuery.paddingOf(context).bottom,
                  ),
                  child: _ProfileDetailsWorkspace(
                    profile: profile,
                    service: service,
                    desktopLayout: desktop,
                    selectedSection: _selectedSection,
                    onSectionSelected: _goToSection,
                    showPageTitle:
                        !ResponsiveViewport.usesCompactShell(context),
                    showStaleNotice: stale,
                    onRefresh: _refreshSafely,
                    editingDisplayName: _editingDisplayName,
                    editingContact: _editingContact,
                    dirty: _dirty,
                    displayNameController: _displayName,
                    displayNameFocus: _displayNameFocus,
                    displayNameFormKey: _displayNameFormKey,
                    displayNameSaveError: _displayNameSaveError,
                    contactFormKey: _contactFormKey,
                    phoneController: _phone,
                    addressController: _address,
                    cityController: _city,
                    emergencyNameController: _emergencyName,
                    emergencyPhoneController: _emergencyPhone,
                    contactSaveError: _contactSaveError,
                    onBeginDisplayNameEdit: _beginDisplayNameEdit,
                    onBeginContactEdit: _beginContactEdit,
                    onCancelEditing: _cancelEditing,
                    onSaveDisplayName: _saveDisplayName,
                    onSaveContact: _saveContact,
                  ),
                ),
              ),
              if (service.isLoading)
                const Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: LinearProgressIndicator(minHeight: 2),
                ),
            ],
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _service?.removeListener(_handleServiceChange);
    _scrollController.dispose();
    _displayNameFocus.dispose();
    for (final controller in _controllers) {
      controller
        ..removeListener(_recalculateDirty)
        ..dispose();
    }
    super.dispose();
  }
}

enum _ProfileSectionId {
  shifts,
  attendance,
  payroll,
  personal,
  employment,
  access,
  security,
}

enum _ProfileSectionGroup { work, account }

extension on _ProfileSectionGroup {
  String get label => switch (this) {
        _ProfileSectionGroup.work => 'Mi trabajo',
        _ProfileSectionGroup.account => 'Mi cuenta',
      };
}

extension on _ProfileSectionId {
  String get label => switch (this) {
        _ProfileSectionId.shifts => 'Turnos',
        _ProfileSectionId.attendance => 'Asistencia',
        _ProfileSectionId.payroll => 'Horas y nómina',
        _ProfileSectionId.personal => 'Datos personales',
        _ProfileSectionId.employment => 'Vínculo laboral',
        _ProfileSectionId.access => 'Acceso',
        _ProfileSectionId.security => 'Seguridad',
      };

  IconData get icon => switch (this) {
        _ProfileSectionId.shifts => Icons.calendar_month_outlined,
        _ProfileSectionId.attendance => Icons.schedule_outlined,
        _ProfileSectionId.payroll => Icons.payments_outlined,
        _ProfileSectionId.personal => Icons.person_outline,
        _ProfileSectionId.employment => Icons.badge_outlined,
        _ProfileSectionId.access => Icons.key_outlined,
        _ProfileSectionId.security => Icons.lock_outline,
      };

  _ProfileSectionGroup get group => switch (this) {
        _ProfileSectionId.shifts ||
        _ProfileSectionId.attendance ||
        _ProfileSectionId.payroll =>
          _ProfileSectionGroup.work,
        _ => _ProfileSectionGroup.account,
      };

  /// Labor sections exist only for an identity with a linked employee record.
  bool get requiresEmployee => group == _ProfileSectionGroup.work;
}

/// Sections available to [profile], in navigation order.
List<_ProfileSectionId> _visibleSections(CurrentUserProfile profile) {
  final linked = profile.employee != null;
  return [
    for (final section in _ProfileSectionId.values)
      if (linked || !section.requiresEmployee) section,
  ];
}

/// Persistent grouped rail used once the workspace has desktop width.
class _ProfileSectionRail extends StatelessWidget {
  const _ProfileSectionRail({
    required this.sections,
    required this.selected,
    required this.onSelected,
  });

  final List<_ProfileSectionId> sections;
  final _ProfileSectionId selected;
  final ValueChanged<_ProfileSectionId> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final groups = <_ProfileSectionGroup, List<_ProfileSectionId>>{};
    for (final section in sections) {
      groups.putIfAbsent(section.group, () => []).add(section);
    }

    return Semantics(
      container: true,
      label: 'Secciones de Mi perfil',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final group in groups.entries) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Text(
                group.key.label.toUpperCase(),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colors.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
              ),
            ),
            for (final section in group.value)
              _ProfileRailItem(
                section: section,
                selected: section == selected,
                onTap: () => onSelected(section),
              ),
            if (group.key != groups.keys.last) const SizedBox(height: 22),
          ],
        ],
      ),
    );
  }
}

class _ProfileRailItem extends StatelessWidget {
  const _ProfileRailItem({
    required this.section,
    required this.selected,
    required this.onTap,
  });

  final _ProfileSectionId section;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final foreground =
        selected ? colors.onSecondaryContainer : colors.onSurface;
    return Semantics(
      button: true,
      selected: selected,
      label: 'Sección ${section.label}',
      child: Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Material(
          color: selected ? colors.secondaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: ValueKey('erp-profile-section-nav-${section.name}'),
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 11,
                ),
                child: ExcludeSemantics(
                  child: Row(
                    children: [
                      Icon(
                        section.icon,
                        size: 19,
                        color: selected ? foreground : colors.onSurfaceVariant,
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Text(
                          section.label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: foreground,
                                    fontWeight: selected
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    height: 1.2,
                                  ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact navigator: one scrollable row of labelled sections.
class _ProfileSectionStrip extends StatefulWidget {
  const _ProfileSectionStrip({
    required this.sections,
    required this.selected,
    required this.onSelected,
  });

  final List<_ProfileSectionId> sections;
  final _ProfileSectionId selected;
  final ValueChanged<_ProfileSectionId> onSelected;

  @override
  State<_ProfileSectionStrip> createState() => _ProfileSectionStripState();
}

class _ProfileSectionStripState extends State<_ProfileSectionStrip> {
  final _controller = ScrollController();
  final _itemKeys = <_ProfileSectionId, GlobalKey>{};

  @override
  void didUpdateWidget(covariant _ProfileSectionStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected != widget.selected) _revealSelected();
  }

  void _revealSelected() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final key = _itemKeys[widget.selected];
      final context = key?.currentContext;
      if (context == null || !mounted) return;
      Scrollable.ensureVisible(
        context,
        alignment: 0.5,
        duration: MediaQuery.disableAnimationsOf(this.context)
            ? Duration.zero
            : const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      label: 'Secciones de Mi perfil',
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: colors.outlineVariant),
          ),
        ),
        child: SingleChildScrollView(
          controller: _controller,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Row(
            children: [
              for (final section in widget.sections)
                _ProfileStripItem(
                  key: _itemKeys.putIfAbsent(section, GlobalKey.new),
                  section: section,
                  selected: section == widget.selected,
                  onTap: () => widget.onSelected(section),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

class _ProfileStripItem extends StatelessWidget {
  const _ProfileStripItem({
    required this.section,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final _ProfileSectionId section;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: 'Sección ${section.label}',
      child: InkWell(
        key: ValueKey('erp-profile-section-nav-${section.name}'),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: ExcludeSemantics(
              // Intrinsic width bounds the column inside the horizontal
              // scroller so the indicator can span exactly the label.
              child: IntrinsicWidth(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(0, 14, 0, 9),
                      child: Text(
                        section.label,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: selected
                                  ? colors.primary
                                  : colors.onSurfaceVariant,
                              fontWeight:
                                  selected ? FontWeight.w700 : FontWeight.w600,
                            ),
                      ),
                    ),
                    Container(
                      height: 2.5,
                      decoration: BoxDecoration(
                        color: selected ? colors.primary : Colors.transparent,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(2),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileDetailsWorkspace extends StatelessWidget {
  const _ProfileDetailsWorkspace({
    required this.profile,
    required this.service,
    required this.desktopLayout,
    required this.selectedSection,
    required this.onSectionSelected,
    required this.showPageTitle,
    required this.showStaleNotice,
    required this.onRefresh,
    required this.editingDisplayName,
    required this.editingContact,
    required this.dirty,
    required this.displayNameController,
    required this.displayNameFocus,
    required this.displayNameFormKey,
    required this.displayNameSaveError,
    required this.contactFormKey,
    required this.phoneController,
    required this.addressController,
    required this.cityController,
    required this.emergencyNameController,
    required this.emergencyPhoneController,
    required this.contactSaveError,
    required this.onBeginDisplayNameEdit,
    required this.onBeginContactEdit,
    required this.onCancelEditing,
    required this.onSaveDisplayName,
    required this.onSaveContact,
  });

  final CurrentUserProfile profile;
  final CurrentUserProfileService service;
  final bool desktopLayout;
  final _ProfileSectionId selectedSection;
  final ValueChanged<_ProfileSectionId> onSectionSelected;
  final bool showPageTitle;
  final bool showStaleNotice;
  final Future<void> Function() onRefresh;
  final bool editingDisplayName;
  final bool editingContact;
  final bool dirty;
  final TextEditingController displayNameController;
  final FocusNode displayNameFocus;
  final GlobalKey<FormState> displayNameFormKey;
  final String? displayNameSaveError;
  final GlobalKey<FormState> contactFormKey;
  final TextEditingController phoneController;
  final TextEditingController addressController;
  final TextEditingController cityController;
  final TextEditingController emergencyNameController;
  final TextEditingController emergencyPhoneController;
  final String? contactSaveError;
  final VoidCallback onBeginDisplayNameEdit;
  final VoidCallback onBeginContactEdit;
  final VoidCallback onCancelEditing;
  final Future<void> Function() onSaveDisplayName;
  final Future<void> Function() onSaveContact;

  @override
  Widget build(BuildContext context) {
    final sections = _visibleSections(profile);
    final activeSection =
        sections.contains(selectedSection) ? selectedSection : sections.first;
    final body = _ProfileSelectedSection(
      profile: profile,
      service: service,
      desktopLayout: desktopLayout,
      section: activeSection,
      trailing: desktopLayout
          ? IconButton(
              key: const ValueKey('erp-profile-refresh-desktop'),
              tooltip: 'Actualizar perfil',
              onPressed: dirty || service.isSaving ? null : onRefresh,
              icon: const Icon(Icons.refresh),
            )
          : null,
      editingDisplayName: editingDisplayName,
      editingContact: editingContact,
      displayNameController: displayNameController,
      displayNameFocus: displayNameFocus,
      displayNameFormKey: displayNameFormKey,
      displayNameSaveError: displayNameSaveError,
      contactFormKey: contactFormKey,
      phoneController: phoneController,
      addressController: addressController,
      cityController: cityController,
      emergencyNameController: emergencyNameController,
      emergencyPhoneController: emergencyPhoneController,
      contactSaveError: contactSaveError,
      onBeginDisplayNameEdit: onBeginDisplayNameEdit,
      onBeginContactEdit: onBeginContactEdit,
      onCancelEditing: onCancelEditing,
      onSaveDisplayName: onSaveDisplayName,
      onSaveContact: onSaveContact,
    );

    // Desktop pairs one persistent rail with a workspace that keeps the full
    // remaining width. The rail carries the identity summary, so no
    // full-width identity card competes with the section the operator opened.
    if (desktopLayout) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 248,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ProfileRailIdentity(profile: profile),
                const SizedBox(height: 22),
                _ProfileSectionRail(
                  sections: sections,
                  selected: activeSection,
                  onSelected: onSectionSelected,
                ),
              ],
            ),
          ),
          const SizedBox(width: 36),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (showStaleNotice) ...[
                  _StaleProfileNotice(onRetry: onRefresh),
                  const SizedBox(height: 16),
                ],
                body,
              ],
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showPageTitle) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  'Mi perfil',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                      ),
                ),
              ),
              IconButton(
                key: const ValueKey('erp-profile-refresh-desktop'),
                tooltip: 'Actualizar perfil',
                onPressed: dirty || service.isSaving ? null : onRefresh,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 14),
        ],
        if (showStaleNotice) ...[
          _StaleProfileNotice(onRetry: onRefresh),
          const SizedBox(height: 14),
        ],
        _ProfileIdentityHeader(profile: profile),
        const SizedBox(height: 18),
        _ProfileSectionStrip(
          sections: sections,
          selected: activeSection,
          onSelected: onSectionSelected,
        ),
        const SizedBox(height: 22),
        body,
      ],
    );
  }
}

/// Identity summary at the head of the desktop rail.
///
/// It replaces the former full-width identity card: the same facts, one
/// column narrower, and no band of chrome between the operator and the
/// section they opened.
class _ProfileRailIdentity extends StatelessWidget {
  const _ProfileRailIdentity({required this.profile});

  final CurrentUserProfile profile;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final employee = profile.employee;
    return Semantics(
      key: const ValueKey('erp-profile-identity-header'),
      container: true,
      label: '${profile.displayName}, ${profile.email}, '
          '${_roleLabel(profile.role)}, ${profile.tenantName}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _ProfileAvatar(profile: profile, radius: 23),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.displayName,
                      key: const ValueKey('erp-profile-display-name'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            height: 1.15,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      employee?.jobTitle ?? _roleLabel(profile.role),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          Text(
            profile.email,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 6),
          _InlineStatus(
            icon: profile.emailVerified
                ? Icons.verified_outlined
                : Icons.warning_amber_outlined,
            label: profile.emailVerified
                ? 'Correo verificado'
                : 'Correo sin verificar',
            isWarning: !profile.emailVerified,
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
            decoration: BoxDecoration(
              color: colors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: colors.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile.tenantName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 1),
                Text(
                  employee == null
                      ? '${_roleLabel(profile.role)} · sin ficha'
                      : '${_roleLabel(profile.role)} · ${employee.employeeNumber}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colors.onSurfaceVariant,
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

/// How much of the content column one panel claims.
enum _PanelSpan { full, main, aside, half }

class _PanelSlot {
  const _PanelSlot(this.child, {this.span = _PanelSpan.full});

  final Widget child;
  final _PanelSpan span;
}

/// Arranges a section's panels across the available width.
///
/// Below `1040px` of content width every panel is a full row, which is the
/// only readable option on tablet and phone. Above it, `main`/`aside` and
/// paired `half` panels share a row so a wide workspace carries related
/// panels side by side instead of one tall centred column.
class _SectionBody extends StatelessWidget {
  const _SectionBody({required this.slots});

  final List<_PanelSlot> slots;

  static const _gap = 18.0;
  static const _twoColumnMin = 1040.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final twoColumns = width >= _twoColumnMin;
        // A single readable measure for prose-shaped panels on any width.
        final singleWidth = width > 900 ? 900.0 : width;

        if (!twoColumns) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var index = 0; index < slots.length; index++) ...[
                if (index > 0) const SizedBox(height: _gap),
                SizedBox(
                  width: slots[index].span == _PanelSpan.full
                      ? width
                      : singleWidth,
                  child: slots[index].child,
                ),
              ],
            ],
          );
        }

        final mainWidth = (width - _gap) * 0.58;
        final asideWidth = width - _gap - mainWidth;
        final halfWidth = (width - _gap) / 2;

        return Wrap(
          spacing: _gap,
          runSpacing: _gap,
          children: [
            for (final slot in slots)
              SizedBox(
                width: switch (slot.span) {
                  _PanelSpan.full => width,
                  _PanelSpan.main => mainWidth,
                  _PanelSpan.aside => asideWidth,
                  _PanelSpan.half => halfWidth,
                },
                child: slot.child,
              ),
          ],
        );
      },
    );
  }
}

class _ProfileIdentityHeader extends StatelessWidget {
  const _ProfileIdentityHeader({required this.profile});

  final CurrentUserProfile profile;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      key: const ValueKey('erp-profile-identity-header'),
      container: true,
      label:
          '${profile.displayName}, ${profile.email}, ${_roleLabel(profile.role)}, ${profile.tenantName}',
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.alphaBlend(
                colors.primary.withValues(alpha: 0.06),
                colors.surfaceContainerLow,
              ),
              colors.surfaceContainerLow,
            ],
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: colors.outlineVariant),
        ),
        padding: const EdgeInsets.all(18),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final roomy = constraints.maxWidth >= 720;
            final identity = Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _ProfileAvatar(profile: profile, radius: 26),
                const SizedBox(width: 15),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profile.displayName,
                        key: const ValueKey('erp-profile-display-name'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style:
                            Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  height: 1.12,
                                  letterSpacing: -0.4,
                                ),
                      ),
                      const SizedBox(height: 5),
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 9,
                        runSpacing: 4,
                        children: [
                          Text(
                            profile.email,
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: colors.onSurfaceVariant,
                                    ),
                          ),
                          _InlineStatus(
                            icon: profile.emailVerified
                                ? Icons.verified_outlined
                                : Icons.warning_amber_outlined,
                            label: profile.emailVerified
                                ? 'Correo verificado'
                                : 'Correo sin verificar',
                            isWarning: !profile.emailVerified,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            );
            final accountContext = _IdentityAccountContext(profile: profile);

            if (!roomy) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  identity,
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.only(left: 57),
                    child: accountContext,
                  ),
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(flex: 5, child: identity),
                const SizedBox(width: 30),
                Flexible(
                  flex: 4,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: accountContext,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _IdentityAccountContext extends StatelessWidget {
  const _IdentityAccountContext({required this.profile});

  final CurrentUserProfile profile;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final employee = profile.employee;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${profile.tenantName} · ${_roleLabel(profile.role)}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          employee == null
              ? 'Sin ficha de trabajador vinculada'
              : 'Vinculada a ${employee.fullName} · ${employee.jobTitle}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
                height: 1.3,
              ),
        ),
      ],
    );
  }
}

class _ProfileSelectedSection extends StatelessWidget {
  const _ProfileSelectedSection({
    required this.profile,
    required this.service,
    required this.desktopLayout,
    required this.section,
    required this.editingDisplayName,
    required this.editingContact,
    required this.displayNameController,
    required this.displayNameFocus,
    required this.displayNameFormKey,
    required this.displayNameSaveError,
    required this.contactFormKey,
    required this.phoneController,
    required this.addressController,
    required this.cityController,
    required this.emergencyNameController,
    required this.emergencyPhoneController,
    required this.contactSaveError,
    required this.onBeginDisplayNameEdit,
    required this.onBeginContactEdit,
    required this.onCancelEditing,
    required this.onSaveDisplayName,
    required this.onSaveContact,
    this.trailing,
  });

  final Widget? trailing;
  final CurrentUserProfile profile;
  final CurrentUserProfileService service;
  final bool desktopLayout;
  final _ProfileSectionId section;
  final bool editingDisplayName;
  final bool editingContact;
  final TextEditingController displayNameController;
  final FocusNode displayNameFocus;
  final GlobalKey<FormState> displayNameFormKey;
  final String? displayNameSaveError;
  final GlobalKey<FormState> contactFormKey;
  final TextEditingController phoneController;
  final TextEditingController addressController;
  final TextEditingController cityController;
  final TextEditingController emergencyNameController;
  final TextEditingController emergencyPhoneController;
  final String? contactSaveError;
  final VoidCallback onBeginDisplayNameEdit;
  final VoidCallback onBeginContactEdit;
  final VoidCallback onCancelEditing;
  final Future<void> Function() onSaveDisplayName;
  final Future<void> Function() onSaveContact;

  @override
  Widget build(BuildContext context) {
    late final String description;
    late final String ownership;
    late final Widget content;

    switch (section) {
      case _ProfileSectionId.shifts:
        description =
            'Tus turnos planificados, tu horario base y tus solicitudes de cambio.';
        ownership =
            'La planificación la publica tu jefatura. Aquí ves lo asignado y el estado de lo que solicitaste.';
        content = const _WorkShiftsSection();
        break;
      case _ProfileSectionId.attendance:
        description =
            'Tus marcajes de la semana y la diferencia con lo planificado.';
        ownership =
            'Los marcajes provienen del control de asistencia. Su corrección la realiza RR.HH.';
        content = const _WorkAttendanceSection();
        break;
      case _ProfileSectionId.payroll:
        description =
            'Tus horas liquidadas y el estado de pago de cada período.';
        ownership =
            'Las liquidaciones las emite RR.HH. Esta vista muestra únicamente tus propias líneas.';
        content = const _WorkPayrollSection();
        break;
      case _ProfileSectionId.personal:
        description = profile.employee == null
            ? 'Qué nombre puedes mostrar en el ERP y cuál es tu identidad de acceso.'
            : 'Qué información de contacto puedes mantener directamente.';
        ownership = profile.employee == null
            ? 'Tu cuenta administra el nombre visible. El correo de acceso se mantiene sin cambios.'
            : 'Tú administras contacto y emergencia. RR.HH. conserva la identidad legal y laboral.';
        content = _PersonalDetails(
          profile: profile,
          service: service,
          editingDisplayName: editingDisplayName,
          editingContact: editingContact,
          displayNameController: displayNameController,
          displayNameFocus: displayNameFocus,
          displayNameFormKey: displayNameFormKey,
          displayNameSaveError: displayNameSaveError,
          contactFormKey: contactFormKey,
          phoneController: phoneController,
          addressController: addressController,
          cityController: cityController,
          emergencyNameController: emergencyNameController,
          emergencyPhoneController: emergencyPhoneController,
          contactSaveError: contactSaveError,
          onBeginDisplayNameEdit: onBeginDisplayNameEdit,
          onBeginContactEdit: onBeginContactEdit,
          onCancelEditing: onCancelEditing,
          onSaveDisplayName: onSaveDisplayName,
          onSaveContact: onSaveContact,
        );
        break;
      case _ProfileSectionId.employment:
        description = 'Qué ficha de trabajador está vinculada a tu usuario.';
        ownership =
            'RR.HH. o un responsable autorizado administra el vínculo y los datos laborales.';
        content = _EmploymentDetails(profile: profile);
        break;
      case _ProfileSectionId.access:
        description =
            'A qué negocio entras, con qué rol y qué operaciones puedes realizar.';
        ownership =
            'Esta información es de solo lectura. Un administrador gestiona roles y permisos.';
        content = _AccessDetails(profile: profile);
        break;
      case _ProfileSectionId.security:
        description = 'Cómo cambiar tu contraseña y cerrar las demás sesiones.';
        ownership =
            'La verificación y el cierre se ejecutan sobre tu identidad autenticada.';
        content = _SectionBody(
          slots: [
            _PanelSlot(
              _SecurityDetails(profile: profile, service: service),
              span: _PanelSpan.main,
            ),
          ],
        );
        break;
    }

    return _ProfileSectionWorkspace(
      key: ValueKey('erp-profile-section-body-${section.name}'),
      section: section,
      desktopLayout: desktopLayout,
      description: description,
      ownership: ownership,
      trailing: trailing,
      child: content,
    );
  }
}

class _ProfileSectionWorkspace extends StatelessWidget {
  const _ProfileSectionWorkspace({
    required this.section,
    required this.desktopLayout,
    required this.description,
    required this.ownership,
    required this.child,
    this.trailing,
    super.key,
  });

  final _ProfileSectionId section;
  final bool desktopLayout;
  final String description;
  final String ownership;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final header = KeyedSubtree(
      key: const ValueKey('erp-profile-section-context'),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  section.label,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                        height: 1.45,
                      ),
                ),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 16),
            trailing!,
          ],
        ],
      ),
    );

    return Semantics(
      container: true,
      label: 'Sección ${section.label} seleccionada',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          const SizedBox(height: 20),
          KeyedSubtree(
            key: const ValueKey('erp-profile-section-content'),
            child: child,
          ),
          const SizedBox(height: 16),
          // Ownership stays a closing footnote so it explains the section
          // without competing with the operator's actual work.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline,
                size: 15,
                color: colors.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  ownership,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                        height: 1.45,
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

/// The one panel primitive used by every profile section.
///
/// Grouping comes from tone, spacing and a single hairline boundary rather
/// than a card per field, so a section reads as one surface.
class _ProfilePanel extends StatelessWidget {
  const _ProfilePanel({
    required this.child,
    this.title,
    this.subtitle,
    this.trailing,
    this.padded = true,
    super.key,
  });

  static const padding = EdgeInsets.all(20);

  final Widget child;
  final String? title;
  final String? subtitle;
  final Widget? trailing;

  /// Set to `false` when the child paints its own insets, such as a tile that
  /// needs its tap target to reach the panel edges.
  final bool padded;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final heading = title;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outlineVariant),
      ),
      padding: padded ? padding : EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (heading != null) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        heading,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          subtitle!,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: colors.onSurfaceVariant,
                                    height: 1.4,
                                  ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: 12),
                  trailing!,
                ],
              ],
            ),
            const SizedBox(height: 16),
          ],
          child,
        ],
      ),
    );
  }
}

/// Resolves the labor read model and renders loading, unavailable, unlinked
/// and loaded states as first-class compositions.
class _SelfServiceScope extends StatelessWidget {
  const _SelfServiceScope({required this.builder});

  final Widget Function(
    BuildContext context,
    EmployeeSelfServiceService service,
    EmployeeSelfServiceSnapshot snapshot,
  ) builder;

  @override
  Widget build(BuildContext context) {
    final service = context.watch<EmployeeSelfServiceService>();
    final snapshot = service.snapshot;

    if (snapshot == null && service.isLoading) {
      return const _ProfilePanel(
        key: ValueKey('erp-profile-work-loading'),
        child: _WorkSkeleton(),
      );
    }
    if (snapshot == null) {
      final profile = context.read<CurrentUserProfileService>().profile;
      final notLinked = service.issue == EmployeeSelfServiceIssue.notLinked;
      return _ProfilePanel(
        key: const ValueKey('erp-profile-work-unavailable'),
        child: _WorkMessage(
          icon: notLinked ? Icons.link_off_outlined : Icons.cloud_off_outlined,
          title: notLinked
              ? 'Sin ficha de trabajador vinculada'
              : 'No pudimos cargar tu información laboral',
          message: notLinked
              ? 'Los turnos, la asistencia y la nómina requieren que un administrador vincule tu cuenta con una ficha existente.'
              : 'Revisa tu conexión y vuelve a intentarlo. No se muestra información parcial.',
          actionLabel: notLinked ? null : 'Reintentar',
          onAction: notLinked
              ? null
              : () => service.synchronize(profile: profile, force: true),
        ),
      );
    }

    return Stack(
      children: [
        builder(context, service, snapshot),
        if (service.isLoading)
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(minHeight: 2),
          ),
      ],
    );
  }
}

class _WorkShiftsSection extends StatelessWidget {
  const _WorkShiftsSection();

  @override
  Widget build(BuildContext context) {
    return _SelfServiceScope(
      builder: (context, service, snapshot) {
        final shifts = snapshot.myShifts
            .where((shift) => !shift.isCancelled)
            .toList(growable: false);
        return KeyedSubtree(
          key: const ValueKey('erp-profile-work-shifts'),
          child: _SectionBody(
            slots: [
              _PanelSlot(_WeekNavigator(service: service)),
              _PanelSlot(
                _ProfilePanel(
                  title: 'Mis turnos',
                  subtitle: shifts.isEmpty
                      ? 'Sin turnos asignados en esta semana'
                      : '${shifts.length} ${shifts.length == 1 ? 'turno' : 'turnos'} · '
                          '${_formatDuration(snapshot.plannedDuration)} planificadas',
                  child: shifts.isEmpty
                      ? const _WorkMessage(
                          icon: Icons.event_available_outlined,
                          title: 'Semana sin turnos',
                          message:
                              'Cuando tu jefatura publique la planificación de esta semana, aparecerá aquí.',
                          compact: true,
                        )
                      : _ShiftList(shifts: shifts),
                ),
                span: _PanelSpan.main,
              ),
              _PanelSlot(
                _ProfilePanel(
                  title: 'Horario base',
                  subtitle: snapshot.defaultShiftBlocks.isEmpty
                      ? null
                      : 'Tu disponibilidad habitual.',
                  child: snapshot.defaultShiftBlocks.isEmpty
                      ? const _WorkMessage(
                          icon: Icons.event_repeat_outlined,
                          title: 'Sin horario base',
                          message:
                              'RR.HH. puede configurar tu disponibilidad habitual para generar la planificación.',
                          compact: true,
                        )
                      : _DefaultBlocksView(
                          blocks: snapshot.defaultShiftBlocks,
                        ),
                ),
                span: _PanelSpan.aside,
              ),
              if (snapshot.changeRequests.isNotEmpty)
                _PanelSlot(
                  _ProfilePanel(
                    title: 'Solicitudes de cambio',
                    subtitle: snapshot.pendingRequestCount == 0
                        ? 'Sin solicitudes pendientes de respuesta.'
                        : '${snapshot.pendingRequestCount} pendiente(s) de respuesta.',
                    child: _ChangeRequestList(
                      requests: snapshot.changeRequests,
                    ),
                  ),
                ),
              if (snapshot.teamShifts.isNotEmpty)
                _PanelSlot(
                  _WorkDisclosure(
                    label: 'Cobertura del equipo esta semana',
                    summary: '${snapshot.teamShifts.length} turnos publicados',
                    child: _ShiftList(
                      shifts: snapshot.teamShifts,
                      showEmployee: true,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _WorkAttendanceSection extends StatelessWidget {
  const _WorkAttendanceSection();

  @override
  Widget build(BuildContext context) {
    return _SelfServiceScope(
      builder: (context, service, snapshot) {
        final variance = snapshot.varianceDuration;
        return KeyedSubtree(
          key: const ValueKey('erp-profile-work-attendance'),
          child: _SectionBody(
            slots: [
              _PanelSlot(_WeekNavigator(service: service)),
              _PanelSlot(
                _ProfilePanel(
                  child: _FigureRow(
                    figures: [
                      _FigureData(
                        label: 'Planificado',
                        value: _formatDuration(snapshot.plannedDuration),
                      ),
                      _FigureData(
                        label: 'Trabajado',
                        value: _formatDuration(snapshot.workedDuration),
                      ),
                      _FigureData(
                        label: 'Diferencia',
                        value: _formatSignedDuration(variance),
                        tone: variance.inMinutes.abs() < 15
                            ? _FigureTone.neutral
                            : variance.isNegative
                                ? _FigureTone.warning
                                : _FigureTone.positive,
                      ),
                      _FigureData(
                        label: 'Marcajes',
                        value: '${snapshot.attendances.length}',
                      ),
                    ],
                  ),
                ),
              ),
              _PanelSlot(
                _ProfilePanel(
                  title: 'Marcajes de la semana',
                  subtitle: snapshot.ongoingAttendance == null
                      ? null
                      : 'Tienes una jornada en curso sin marcaje de salida.',
                  child: snapshot.attendances.isEmpty
                      ? const _WorkMessage(
                          icon: Icons.schedule_outlined,
                          title: 'Sin marcajes registrados',
                          message:
                              'Los marcajes de entrada y salida de esta semana aparecerán aquí.',
                          compact: true,
                        )
                      : _AttendanceList(attendances: snapshot.attendances),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _WorkPayrollSection extends StatelessWidget {
  const _WorkPayrollSection();

  @override
  Widget build(BuildContext context) {
    return _SelfServiceScope(
      builder: (context, service, snapshot) {
        final lines = snapshot.payrollLines;
        final latest = snapshot.latestPayrollLine;
        if (latest == null) {
          return const _ProfilePanel(
            key: ValueKey('erp-profile-work-payroll'),
            child: _WorkMessage(
              icon: Icons.payments_outlined,
              title: 'Sin liquidaciones emitidas',
              message:
                  'Cuando RR.HH. emita una liquidación que te incluya, verás aquí tus horas y el estado de pago.',
              compact: true,
            ),
          );
        }

        return KeyedSubtree(
          key: const ValueKey('erp-profile-work-payroll'),
          child: _SectionBody(
            slots: [
              _PanelSlot(
                _ProfilePanel(
                  title: 'Último período liquidado',
                  subtitle: _payrollPeriodLabel(latest),
                  trailing: _StatusMark(
                    label: _payrollStatusLabel(latest.status),
                    tone: latest.isSettled
                        ? _FigureTone.positive
                        : _FigureTone.neutral,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _FigureRow(
                        figures: [
                          _FigureData(
                            label: 'Horas',
                            value: _formatHours(latest.workedHours),
                          ),
                          _FigureData(
                            label: 'Extras',
                            value: _formatHours(latest.overtimeHours),
                          ),
                          _FigureData(
                            label: 'Total',
                            value:
                                ChileanUtils.formatCurrency(latest.totalAmount),
                            emphasized: true,
                          ),
                        ],
                      ),
                      if (latest.paidAt != null ||
                          latest.paymentMethodName != null) ...[
                        const SizedBox(height: 16),
                        _DefinitionGrid(
                          items: [
                            if (latest.paidAt != null)
                              _DefinitionData(
                                label: 'Fecha de pago',
                                value: ChileanUtils.formatDate(
                                  employeeSelfServiceLocalTime(
                                    latest.paidAt!,
                                    snapshot.timezone,
                                  ),
                                ),
                              ),
                            if (latest.paymentMethodName != null)
                              _DefinitionData(
                                label: 'Medio de pago',
                                value: _paymentMethodLabel(
                                  latest.paymentMethodName!,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                span: _PanelSpan.main,
              ),
              if (lines.length > 1)
                _PanelSlot(
                  _ProfilePanel(
                    title: 'Historial',
                    subtitle: 'Períodos de los últimos 12 meses.',
                    child: _PayrollList(lines: lines.skip(1).toList()),
                  ),
                  span: _PanelSpan.aside,
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Week stepper shared by the shift and attendance sections.
class _WeekNavigator extends StatelessWidget {
  const _WeekNavigator({required this.service});

  final EmployeeSelfServiceService service;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final profile = context.read<CurrentUserProfileService>().profile;
    final start = service.weekStart;
    final end = start.add(const Duration(days: 6));
    final busy = service.isLoading;

    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.outlineVariant),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Row(
        children: [
          IconButton(
            key: const ValueKey('erp-profile-week-previous'),
            tooltip: 'Semana anterior',
            onPressed:
                busy ? null : () => service.shiftWeek(-1, profile: profile),
            icon: const Icon(Icons.chevron_left),
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          ),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _weekRangeLabel(start, end),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                Text(
                  service.isCurrentWeek ? 'Semana actual' : 'Otra semana',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
          if (!service.isCurrentWeek)
            TextButton(
              key: const ValueKey('erp-profile-week-today'),
              onPressed: busy
                  ? null
                  : () => service.selectCurrentWeek(profile: profile),
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              child: const Text('Hoy'),
            ),
          IconButton(
            key: const ValueKey('erp-profile-week-next'),
            tooltip: 'Semana siguiente',
            onPressed:
                busy ? null : () => service.shiftWeek(1, profile: profile),
            icon: const Icon(Icons.chevron_right),
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          ),
        ],
      ),
    );
  }
}

class _ShiftList extends StatelessWidget {
  const _ShiftList({required this.shifts, this.showEmployee = false});

  final List<SelfPlannedShift> shifts;
  final bool showEmployee;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final sorted = [...shifts]..sort((a, b) => a.startAt.compareTo(b.startAt));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < sorted.length; index++)
          Builder(
            builder: (context) {
              final shift = sorted[index];
              final start = employeeSelfServiceLocalTime(
                shift.startAt,
                shift.timezone,
              );
              final end = employeeSelfServiceLocalTime(
                shift.endAt,
                shift.timezone,
              );
              final detail = [
                if (showEmployee && shift.employeeName != null)
                  shift.employeeName!,
                if (shift.roleName != null) shift.roleName!,
                if (shift.title != null) shift.title!,
              ].join(' · ');

              return _DayRow(
                first: index == 0,
                day: start,
                leading: _formatTimeRange(start, end),
                detail: detail.isEmpty ? null : detail,
                trailing: Text(
                  _formatDuration(shift.plannedDurationInWeek),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                badge:
                    shift.status == 'published' || shift.status == 'completed'
                        ? null
                        : _shiftStatusLabel(shift.status),
              );
            },
          ),
      ],
    );
  }
}

class _AttendanceList extends StatelessWidget {
  const _AttendanceList({required this.attendances});

  final List<SelfAttendance> attendances;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < attendances.length; index++)
          Builder(
            builder: (context) {
              final attendance = attendances[index];
              final checkIn = employeeSelfServiceLocalTime(
                attendance.checkIn,
                attendance.timezone,
              );
              final checkOut = attendance.checkOut == null
                  ? null
                  : employeeSelfServiceLocalTime(
                      attendance.checkOut!,
                      attendance.timezone,
                    );
              final range = checkOut == null
                  ? '${_formatTime(checkIn)} — en curso'
                  : _formatTimeRange(checkIn, checkOut);
              final detail = attendance.breakMinutes > 0
                  ? 'Colación ${attendance.breakMinutes} min'
                  : null;

              return _DayRow(
                first: index == 0,
                day: checkIn,
                leading: range,
                detail: detail,
                trailing: Text(
                  attendance.isOngoing
                      ? '—'
                      : _formatDuration(
                          attendance.contributesToWorkedDuration
                              ? attendance.workedDurationInWeek
                              : attendance.effectiveDuration,
                        ),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                badge: switch (attendance.status) {
                  'approved' => null,
                  'completed' => null,
                  'rejected' => 'Rechazado',
                  _ => 'En curso',
                },
              );
            },
          ),
      ],
    );
  }
}

class _PayrollList extends StatelessWidget {
  const _PayrollList({required this.lines});

  final List<SelfPayrollLine> lines;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < lines.length; index++)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 13),
            decoration: index == 0
                ? null
                : BoxDecoration(
                    border: Border(
                      top: BorderSide(color: colors.outlineVariant),
                    ),
                  ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _payrollPeriodLabel(lines[index]),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${_formatHours(lines[index].workedHours)} · '
                        '${_payrollStatusLabel(lines[index].status)}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  ChileanUtils.formatCurrency(lines[index].totalAmount),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _ChangeRequestList extends StatelessWidget {
  const _ChangeRequestList({required this.requests});

  final List<SelfShiftChangeRequest> requests;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < requests.length; index++)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 13),
            decoration: index == 0
                ? null
                : BoxDecoration(
                    border: Border(
                      top: BorderSide(color: colors.outlineVariant),
                    ),
                  ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _requestTypeLabel(requests[index].requestType),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _requestDetail(requests[index]),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                              height: 1.4,
                            ),
                      ),
                      if (requests[index].managerNote != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Respuesta: ${requests[index].managerNote}',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: colors.onSurfaceVariant,
                                    fontStyle: FontStyle.italic,
                                  ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _StatusMark(
                  label: _requestStatusLabel(requests[index].status),
                  tone: switch (requests[index].status) {
                    'approved' => _FigureTone.positive,
                    'rejected' => _FigureTone.warning,
                    _ => _FigureTone.neutral,
                  },
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _DefaultBlocksView extends StatelessWidget {
  const _DefaultBlocksView({required this.blocks});

  final List<SelfDefaultShiftBlock> blocks;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final byDay = <int, List<SelfDefaultShiftBlock>>{};
    for (final block in blocks) {
      byDay.putIfAbsent(block.dayOfWeek, () => []).add(block);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var day = 1; day <= 7; day++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 92,
                  child: Text(
                    _weekdayName(day),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: byDay.containsKey(day)
                              ? colors.onSurface
                              : colors.onSurfaceVariant,
                          fontWeight: byDay.containsKey(day)
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                  ),
                ),
                Expanded(
                  child: Text(
                    byDay[day] == null
                        ? 'Libre'
                        : byDay[day]!
                            .map(
                              (block) => '${_trimTime(block.startTime)} – '
                                  '${_trimTime(block.endTime)}',
                            )
                            .join('  ·  '),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: byDay.containsKey(day)
                          ? colors.onSurface
                          : colors.onSurfaceVariant,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// One dated row: the day is printed once per date, then each entry lines up
/// under a shared time column so a week can be scanned vertically.
class _DayRow extends StatelessWidget {
  const _DayRow({
    required this.first,
    required this.day,
    required this.leading,
    required this.trailing,
    this.detail,
    this.badge,
  });

  final bool first;
  final DateTime day;
  final String leading;
  final Widget trailing;
  final String? detail;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isToday = _isSameDate(day, DateTime.now());

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: first
          ? null
          : BoxDecoration(
              border: Border(top: BorderSide(color: colors.outlineVariant)),
            ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 62,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _shortWeekday(day),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color:
                            isToday ? colors.primary : colors.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                      ),
                ),
                Text(
                  '${day.day}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: isToday ? colors.primary : colors.onSurface,
                        fontWeight: FontWeight.w700,
                        height: 1.05,
                      ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        leading,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          fontFeatures: const [
                            FontFeature.tabularFigures(),
                          ],
                        ),
                      ),
                    ),
                    if (badge != null) ...[
                      const SizedBox(width: 8),
                      _StatusMark(label: badge!, tone: _FigureTone.neutral),
                    ],
                  ],
                ),
                if (detail != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    detail!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          trailing,
        ],
      ),
    );
  }
}

enum _FigureTone { neutral, positive, warning }

class _FigureData {
  const _FigureData({
    required this.label,
    required this.value,
    this.tone = _FigureTone.neutral,
    this.emphasized = false,
  });

  final String label;
  final String value;
  final _FigureTone tone;
  final bool emphasized;
}

/// Comparable figures in one aligned row, separated by hairlines instead of
/// one coloured card per metric.
class _FigureRow extends StatelessWidget {
  const _FigureRow({required this.figures});

  final List<_FigureData> figures;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth < 420 ? 2 : figures.length;
        const gap = 18.0;
        final width = (constraints.maxWidth - (columns - 1) * gap) / columns;

        return Wrap(
          spacing: gap,
          runSpacing: 18,
          children: [
            for (var index = 0; index < figures.length; index++)
              SizedBox(
                width: width,
                child: Container(
                  padding: EdgeInsets.only(left: index % columns == 0 ? 0 : 14),
                  decoration: index % columns == 0
                      ? null
                      : BoxDecoration(
                          border: Border(
                            left: BorderSide(color: colors.outlineVariant),
                          ),
                        ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        figures[index].label,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        figures[index].value,
                        style: (figures[index].emphasized
                                ? Theme.of(context).textTheme.titleLarge
                                : Theme.of(context).textTheme.titleMedium)
                            ?.copyWith(
                          fontWeight: FontWeight.w700,
                          height: 1.1,
                          color: switch (figures[index].tone) {
                            _FigureTone.positive => colors.tertiary,
                            _FigureTone.warning => colors.error,
                            _FigureTone.neutral => colors.onSurface,
                          },
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// A quiet state marker: text plus tone, never a coloured pill wall.
class _StatusMark extends StatelessWidget {
  const _StatusMark({required this.label, required this.tone});

  final String label;
  final _FigureTone tone;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = switch (tone) {
      _FigureTone.positive => colors.tertiary,
      _FigureTone.warning => colors.error,
      _FigureTone.neutral => colors.onSurfaceVariant,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _WorkDisclosure extends StatelessWidget {
  const _WorkDisclosure({
    required this.label,
    required this.summary,
    required this.child,
  });

  final String label;
  final String summary;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          controlAffinity: ListTileControlAffinity.trailing,
          title: Text(
            label,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          subtitle: Text(
            summary,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
          ),
          children: [child],
        ),
      ),
    );
  }
}

class _WorkMessage extends StatelessWidget {
  const _WorkMessage({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: compact ? 10 : 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 22, color: colors.onSurfaceVariant),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      message,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: colors.onSurfaceVariant,
                            height: 1.45,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(left: 35),
              child: TextButton(
                onPressed: onAction,
                style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                child: Text(actionLabel!),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _WorkSkeleton extends StatelessWidget {
  const _WorkSkeleton();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    Widget bar(double width, double height) => Container(
          width: width,
          height: height,
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: colors.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(6),
          ),
        );

    return Semantics(
      label: 'Cargando tu información laboral',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          bar(180, 16),
          bar(double.infinity, 42),
          bar(double.infinity, 42),
          bar(220, 42),
        ],
      ),
    );
  }
}

class _PersonalDetails extends StatelessWidget {
  const _PersonalDetails({
    required this.profile,
    required this.service,
    required this.editingDisplayName,
    required this.editingContact,
    required this.displayNameController,
    required this.displayNameFocus,
    required this.displayNameFormKey,
    required this.displayNameSaveError,
    required this.contactFormKey,
    required this.phoneController,
    required this.addressController,
    required this.cityController,
    required this.emergencyNameController,
    required this.emergencyPhoneController,
    required this.contactSaveError,
    required this.onBeginDisplayNameEdit,
    required this.onBeginContactEdit,
    required this.onCancelEditing,
    required this.onSaveDisplayName,
    required this.onSaveContact,
  });

  final CurrentUserProfile profile;
  final CurrentUserProfileService service;
  final bool editingDisplayName;
  final bool editingContact;
  final TextEditingController displayNameController;
  final FocusNode displayNameFocus;
  final GlobalKey<FormState> displayNameFormKey;
  final String? displayNameSaveError;
  final GlobalKey<FormState> contactFormKey;
  final TextEditingController phoneController;
  final TextEditingController addressController;
  final TextEditingController cityController;
  final TextEditingController emergencyNameController;
  final TextEditingController emergencyPhoneController;
  final String? contactSaveError;
  final VoidCallback onBeginDisplayNameEdit;
  final VoidCallback onBeginContactEdit;
  final VoidCallback onCancelEditing;
  final Future<void> Function() onSaveDisplayName;
  final Future<void> Function() onSaveContact;

  @override
  Widget build(BuildContext context) {
    if (profile.employee == null) {
      return _SectionBody(
        slots: [
          _PanelSlot(
            _ProfilePanel(
              title: 'Identidad de acceso',
              child: _DisplayNameEditor(
                profile: profile,
                service: service,
                editing: editingDisplayName,
                controller: displayNameController,
                focusNode: displayNameFocus,
                formKey: displayNameFormKey,
                saveError: displayNameSaveError,
                onEdit: onBeginDisplayNameEdit,
                onCancel: onCancelEditing,
                onSave: onSaveDisplayName,
              ),
            ),
            span: _PanelSpan.main,
          ),
        ],
      );
    }

    final employee = profile.employee!;
    final editor = _EmployeeContactEditor(
      profile: profile,
      service: service,
      editing: editingContact,
      formKey: contactFormKey,
      phone: phoneController,
      address: addressController,
      city: cityController,
      emergencyName: emergencyNameController,
      emergencyPhone: emergencyPhoneController,
      saveError: contactSaveError,
      onEdit: onBeginContactEdit,
      onCancel: onCancelEditing,
      onSave: onSaveContact,
    );

    // The active form is one uninterrupted task and stays a single column.
    // At rest the same data reads better as two purpose-owned panels.
    if (editingContact) {
      return _SectionBody(
        slots: [
          _PanelSlot(
            _ProfilePanel(title: 'Editar mis datos', child: editor),
            span: _PanelSpan.main,
          ),
        ],
      );
    }

    return _SectionBody(
      slots: [
        _PanelSlot(
          _ProfilePanel(
            title: 'Contacto',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _DefinitionGrid(
                  items: [
                    _DefinitionData(
                      label: 'Teléfono',
                      value: employee.phone ?? 'Sin informar',
                    ),
                    _DefinitionData(
                      label: 'Ciudad',
                      value: employee.city ?? 'Sin informar',
                    ),
                    _DefinitionData(
                      label: 'Dirección',
                      value: employee.address ?? 'Sin informar',
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                editor,
              ],
            ),
          ),
          span: _PanelSpan.main,
        ),
        _PanelSlot(
          _ProfilePanel(
            title: 'Contacto de emergencia',
            subtitle: 'A quién avisamos si ocurre algo durante tu jornada.',
            child: _DefinitionGrid(
              items: [
                _DefinitionData(
                  label: 'Nombre',
                  value: employee.emergencyContactName ?? 'Sin informar',
                ),
                _DefinitionData(
                  label: 'Teléfono',
                  value: employee.emergencyContactPhone ?? 'Sin informar',
                ),
              ],
            ),
          ),
          span: _PanelSpan.aside,
        ),
      ],
    );
  }
}

class _DisplayNameEditor extends StatelessWidget {
  const _DisplayNameEditor({
    required this.profile,
    required this.service,
    required this.editing,
    required this.controller,
    required this.focusNode,
    required this.formKey,
    required this.saveError,
    required this.onEdit,
    required this.onCancel,
    required this.onSave,
  });

  final CurrentUserProfile profile;
  final CurrentUserProfileService service;
  final bool editing;
  final TextEditingController controller;
  final FocusNode focusNode;
  final GlobalKey<FormState> formKey;
  final String? saveError;
  final VoidCallback onEdit;
  final VoidCallback onCancel;
  final Future<void> Function() onSave;

  @override
  Widget build(BuildContext context) {
    if (!editing) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _DefinitionGrid(
            items: [
              _DefinitionData(
                label: 'Nombre visible',
                value: profile.displayName,
              ),
              _DefinitionData(
                label: 'Correo de acceso',
                value: profile.email,
                supporting: profile.emailVerified
                    ? 'Verificado'
                    : 'Pendiente de verificación',
              ),
            ],
          ),
          if (profile.canEditDisplayName) ...[
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const ValueKey('erp-profile-edit-display-name'),
                onPressed: service.isSaving ? null : onEdit,
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Editar nombre visible'),
                style: TextButton.styleFrom(
                  minimumSize: const Size(48, 48),
                ),
              ),
            ),
          ],
        ],
      );
    }

    return Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            key: const ValueKey('erp-profile-display-name-field'),
            controller: controller,
            focusNode: focusNode,
            enabled: !service.isSaving,
            maxLength: 80,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              labelText: 'Nombre visible',
              helperText:
                  'Este nombre se muestra mientras no exista un vínculo laboral.',
            ),
            onFieldSubmitted: (_) => onSave(),
            validator: (value) {
              final normalized = value?.trim() ?? '';
              if (normalized.length < 2) {
                return 'Ingresa al menos 2 caracteres.';
              }
              if (normalized.contains(
                RegExp(r'[\u0000-\u001F\u007F]'),
              )) {
                return 'El nombre contiene caracteres no permitidos.';
              }
              return null;
            },
          ),
          if (saveError != null) ...[
            const SizedBox(height: 10),
            _InlineOperationError(
              key: const ValueKey('erp-profile-display-name-save-error'),
              message: saveError!,
            ),
          ],
          const SizedBox(height: 16),
          _EditActions(
            saving: service.isSaving,
            saveLabel: 'Guardar nombre',
            saveKey: const ValueKey('erp-profile-save-display-name'),
            cancelKey: const ValueKey('erp-profile-cancel-display-name'),
            onCancel: onCancel,
            onSave: onSave,
          ),
        ],
      ),
    );
  }
}

class _EmployeeContactEditor extends StatelessWidget {
  const _EmployeeContactEditor({
    required this.profile,
    required this.service,
    required this.editing,
    required this.formKey,
    required this.phone,
    required this.address,
    required this.city,
    required this.emergencyName,
    required this.emergencyPhone,
    required this.saveError,
    required this.onEdit,
    required this.onCancel,
    required this.onSave,
  });

  final CurrentUserProfile profile;
  final CurrentUserProfileService service;
  final bool editing;
  final GlobalKey<FormState> formKey;
  final TextEditingController phone;
  final TextEditingController address;
  final TextEditingController city;
  final TextEditingController emergencyName;
  final TextEditingController emergencyPhone;
  final String? saveError;
  final VoidCallback onEdit;
  final VoidCallback onCancel;
  final Future<void> Function() onSave;

  @override
  Widget build(BuildContext context) {
    if (!editing) {
      // The values themselves are rendered by the purpose-owned panels; this
      // editor contributes only the command that opens the form.
      if (!profile.canEditEmployeeContact) {
        return const _InlineNotice(
          message:
              'La edición está disponible únicamente para trabajadores activos.',
        );
      }
      return Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.tonalIcon(
          key: const ValueKey('erp-profile-edit-contact'),
          onPressed: service.isSaving ? null : onEdit,
          icon: const Icon(Icons.edit_outlined),
          label: const Text('Editar datos personales'),
          style: FilledButton.styleFrom(
            minimumSize: const Size(48, 48),
          ),
        ),
      );
    }

    return Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ContactFieldGrid(
            children: [
              _ContactFieldSpec(
                key: const ValueKey('erp-profile-contact-phone'),
                controller: phone,
                label: 'Teléfono',
                maxLength: 32,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
              ),
              _ContactFieldSpec(
                key: const ValueKey('erp-profile-contact-city'),
                controller: city,
                label: 'Ciudad',
                maxLength: 120,
                textInputAction: TextInputAction.next,
              ),
              _ContactFieldSpec(
                key: const ValueKey('erp-profile-contact-address'),
                controller: address,
                label: 'Dirección',
                maxLength: 240,
                textInputAction: TextInputAction.next,
                fullWidth: true,
              ),
            ],
          ),
          const SizedBox(height: 22),
          Text(
            'Contacto de emergencia',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 12),
          _ContactFieldGrid(
            children: [
              _ContactFieldSpec(
                key: const ValueKey('erp-profile-emergency-name'),
                controller: emergencyName,
                label: 'Nombre',
                maxLength: 160,
                textInputAction: TextInputAction.next,
              ),
              _ContactFieldSpec(
                key: const ValueKey('erp-profile-emergency-phone'),
                controller: emergencyPhone,
                label: 'Teléfono',
                maxLength: 32,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => onSave(),
              ),
            ],
          ),
          if (saveError != null) ...[
            const SizedBox(height: 12),
            _InlineOperationError(
              key: const ValueKey('erp-profile-contact-save-error'),
              message: saveError!,
            ),
          ],
          const SizedBox(height: 18),
          _EditActions(
            saving: service.isSaving,
            saveLabel: 'Guardar datos',
            saveKey: const ValueKey('erp-profile-save-contact'),
            cancelKey: const ValueKey('erp-profile-cancel-contact'),
            onCancel: onCancel,
            onSave: onSave,
          ),
        ],
      ),
    );
  }
}

class _ContactFieldSpec {
  const _ContactFieldSpec({
    required this.key,
    required this.controller,
    required this.label,
    required this.maxLength,
    required this.textInputAction,
    this.keyboardType,
    this.fullWidth = false,
    this.onSubmitted,
  });

  final Key key;
  final TextEditingController controller;
  final String label;
  final int maxLength;
  final TextInputAction textInputAction;
  final TextInputType? keyboardType;
  final bool fullWidth;
  final ValueChanged<String>? onSubmitted;
}

class _ContactFieldGrid extends StatelessWidget {
  const _ContactFieldGrid({required this.children});

  final List<_ContactFieldSpec> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumns =
            constraints.maxWidth >= ResponsiveBreakpoints.phoneMaxExclusive;
        const gap = 14.0;
        final halfWidth = (constraints.maxWidth - gap) / 2;

        return Wrap(
          spacing: gap,
          runSpacing: 14,
          children: [
            for (final field in children)
              SizedBox(
                width: !twoColumns || field.fullWidth
                    ? constraints.maxWidth
                    : halfWidth,
                child: TextFormField(
                  key: field.key,
                  controller: field.controller,
                  enabled: !context.watch<CurrentUserProfileService>().isSaving,
                  keyboardType: field.keyboardType,
                  textInputAction: field.textInputAction,
                  maxLength: field.maxLength,
                  decoration: InputDecoration(
                    labelText: field.label,
                    counterText: '',
                  ),
                  onFieldSubmitted: field.onSubmitted,
                  validator: (value) {
                    final normalized = (value ?? '').trim();
                    if (normalized.length > field.maxLength) {
                      return 'Máximo ${field.maxLength} caracteres.';
                    }
                    if (normalized.contains(
                      RegExp(r'[\u0000-\u001F\u007F]'),
                    )) {
                      return 'El valor contiene caracteres no permitidos.';
                    }
                    return null;
                  },
                ),
              ),
          ],
        );
      },
    );
  }
}

class _EditActions extends StatelessWidget {
  const _EditActions({
    required this.saving,
    required this.saveLabel,
    required this.saveKey,
    required this.cancelKey,
    required this.onCancel,
    required this.onSave,
  });

  final bool saving;
  final String saveLabel;
  final Key saveKey;
  final Key cancelKey;
  final VoidCallback onCancel;
  final Future<void> Function() onSave;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      alignment: WrapAlignment.end,
      children: [
        TextButton(
          key: cancelKey,
          onPressed: saving ? null : onCancel,
          style: TextButton.styleFrom(
            minimumSize: const Size(48, 48),
          ),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          key: saveKey,
          onPressed: saving ? null : onSave,
          icon: saving
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check),
          label: Text(saving ? 'Guardando…' : saveLabel),
          style: FilledButton.styleFrom(
            minimumSize: const Size(48, 48),
          ),
        ),
      ],
    );
  }
}

class _EmploymentDetails extends StatelessWidget {
  const _EmploymentDetails({required this.profile});

  final CurrentUserProfile profile;

  @override
  Widget build(BuildContext context) {
    final employee = profile.employee;
    if (employee == null) {
      return _SectionBody(
        slots: [
          _PanelSlot(
            _ProfilePanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _InlineNotice(
                    key: ValueKey('erp-profile-unlinked-employee'),
                    title: 'Cuenta sin ficha de trabajador',
                    message:
                        'Tu acceso al ERP funciona de forma independiente, pero los datos laborales requieren que un administrador vincule esta cuenta con una ficha existente.',
                  ),
                  if (profile.canManageUsers) ...[
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => UserManagementNavigation.open(
                          context,
                          audience: UserManagementAudience.staff,
                          target: UserManagementTarget.user,
                          targetId: profile.userId,
                        ),
                        icon: const Icon(Icons.manage_accounts_outlined),
                        label: const Text(
                          'Administrar vínculo en Usuarios y roles',
                        ),
                        style: TextButton.styleFrom(
                          minimumSize: const Size(48, 48),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            span: _PanelSpan.main,
          ),
        ],
      );
    }

    return _SectionBody(
      slots: [
        _PanelSlot(
          _ProfilePanel(
            title: 'Ficha de trabajador',
            subtitle: 'Tu identidad laboral dentro de ${profile.tenantName}.',
            child: _DefinitionGrid(
              items: [
                _DefinitionData(
                  label: 'Nombre legal',
                  value: employee.fullName,
                ),
                _DefinitionData(
                  label: 'N.º de trabajador',
                  value: employee.employeeNumber,
                ),
                _DefinitionData(
                  label: 'RUT',
                  value: employee.rut ?? 'Sin informar',
                ),
                _DefinitionData(
                  label: 'Correo laboral',
                  value: employee.email ?? 'Sin informar',
                ),
              ],
            ),
          ),
          span: _PanelSpan.main,
        ),
        _PanelSlot(
          _ProfilePanel(
            title: 'Puesto',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _DefinitionGrid(
                  items: [
                    _DefinitionData(label: 'Cargo', value: employee.jobTitle),
                    _DefinitionData(
                      label: 'Departamento',
                      value: employee.departmentName ?? 'Sin asignar',
                    ),
                    _DefinitionData(
                      label: 'Estado',
                      value: _employeeStatusLabel(employee.status),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const _InlineNotice(
                  key: ValueKey('erp-profile-linked-employee'),
                  title: 'Ficha laboral vinculada',
                  message:
                      'La identidad legal, el cargo, el estado y la remuneración los administra RR.HH.',
                  positive: true,
                ),
                if (profile.canManageUsers) ...[
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () =>
                          context.push('/hr/employees/${employee.id}'),
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('Abrir ficha en RR.HH.'),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(48, 48),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          span: _PanelSpan.aside,
        ),
      ],
    );
  }
}

class _AccessDetails extends StatelessWidget {
  const _AccessDetails({required this.profile});

  final CurrentUserProfile profile;

  static const _permissionLabels = <String, String>{
    'access_pos': 'Acceder al POS',
    'create_invoices': 'Crear facturas',
    'edit_prices': 'Editar precios',
    'delete_invoices': 'Eliminar facturas',
    'access_accounting': 'Acceder a contabilidad',
    'manage_users': 'Gestionar usuarios',
    'can_manage_supplier_credentials': 'Gestionar credenciales de proveedores',
    'edit_settings': 'Editar configuración',
  };

  @override
  Widget build(BuildContext context) {
    final granted = profile.permissions.entries
        .where((entry) => entry.value)
        .map(
          (entry) => MapEntry(
            entry.key,
            _permissionLabels[entry.key] ?? entry.key,
          ),
        )
        .toList(growable: false)
      ..sort((a, b) => a.value.compareTo(b.value));
    final groups = _groupPermissions(granted);

    return _SectionBody(
      slots: [
        _PanelSlot(
          _ProfilePanel(
            title: 'Contexto de acceso',
            child: _DefinitionGrid(
              items: [
                _DefinitionData(label: 'Negocio', value: profile.tenantName),
                _DefinitionData(
                  label: 'Subdominio',
                  value: profile.tenantSubdomain ?? 'Sin subdominio',
                ),
                _DefinitionData(label: 'Rol', value: _roleLabel(profile.role)),
              ],
            ),
          ),
          span: _PanelSpan.aside,
        ),
        _PanelSlot(
          _ProfilePanel(
            padded: false,
            child: Theme(
              data:
                  Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                key: const ValueKey('erp-profile-permissions-disclosure'),
                initiallyExpanded: granted.isNotEmpty,
                tilePadding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                controlAffinity: ListTileControlAffinity.trailing,
                title: Text(
                  granted.isEmpty
                      ? 'Permisos activos'
                      : 'Permisos activos (${granted.length})',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                subtitle: Text(
                  granted.isEmpty
                      ? 'No hay permisos adicionales asignados.'
                      : 'Qué acciones están habilitadas para tu rol.',
                ),
                children: [
                  if (granted.isEmpty)
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text('Sin permisos adicionales asignados.'),
                      ),
                    )
                  else
                    _PermissionGroups(groups: groups),
                ],
              ),
            ),
          ),
          span: _PanelSpan.main,
        ),
      ],
    );
  }

  Map<String, List<String>> _groupPermissions(
    List<MapEntry<String, String>> permissions,
  ) {
    final groups = <String, List<String>>{
      'Operación': [],
      'Administración': [],
      'Finanzas': [],
      'Otros': [],
    };
    for (final permission in permissions) {
      final group = switch (permission.key) {
        'access_pos' || 'create_invoices' => 'Operación',
        'access_accounting' => 'Finanzas',
        'edit_prices' ||
        'delete_invoices' ||
        'manage_users' ||
        'can_manage_supplier_credentials' ||
        'edit_settings' =>
          'Administración',
        _ => 'Otros',
      };
      groups[group]!.add(permission.value);
    }
    groups.removeWhere((_, values) => values.isEmpty);
    return groups;
  }
}

class _PermissionGroups extends StatelessWidget {
  const _PermissionGroups({required this.groups});

  final Map<String, List<String>> groups;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumns =
            constraints.maxWidth >= ResponsiveBreakpoints.phoneMaxExclusive;
        const gap = 28.0;
        final width = twoColumns
            ? (constraints.maxWidth - gap) / 2
            : constraints.maxWidth;

        return Wrap(
          spacing: gap,
          runSpacing: 18,
          children: [
            for (final group in groups.entries)
              SizedBox(
                width: width,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      group.key,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 8),
                    for (final permission in group.value)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 7),
                        child: Text(
                          '•  $permission',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _SecurityDetails extends StatelessWidget {
  const _SecurityDetails({
    required this.profile,
    required this.service,
  });

  final CurrentUserProfile profile;
  final CurrentUserProfileService service;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outlineVariant),
      ),
      padding: _ProfilePanel.padding,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact =
              constraints.maxWidth < ResponsiveBreakpoints.phoneMaxExclusive;
          final revocationPending = service.hasPendingOtherSessionsRevocation;
          final copy = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                revocationPending
                    ? 'Contraseña actualizada · cierre pendiente'
                    : 'Contraseña y sesiones',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                revocationPending
                    ? 'Tu nueva contraseña ya está activa. Falta cerrar las demás sesiones; reintenta únicamente esa operación.'
                    : 'El cambio puede solicitar un código de 6 dígitos enviado a ${profile.email}. Al completarlo, se intentará cerrar las demás sesiones.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: revocationPending
                          ? colors.error
                          : colors.onSurfaceVariant,
                      height: 1.45,
                    ),
              ),
            ],
          );
          final action = FilledButton.icon(
            key: const ValueKey('erp-profile-change-password'),
            onPressed: () => showDialog<void>(
              context: context,
              barrierDismissible: false,
              builder: (_) => _ErpPasswordChangeDialog(
                email: profile.email,
                initialRevocationPending: revocationPending,
              ),
            ),
            icon: Icon(
              revocationPending
                  ? Icons.logout_outlined
                  : Icons.password_outlined,
            ),
            label: Text(
              revocationPending
                  ? 'Completar cierre de sesiones'
                  : 'Cambiar contraseña',
            ),
            style: FilledButton.styleFrom(
              minimumSize: const Size(48, 48),
            ),
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                copy,
                const SizedBox(height: 18),
                action,
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: copy),
              const SizedBox(width: 28),
              action,
            ],
          );
        },
      ),
    );
  }
}

class _DefinitionData {
  const _DefinitionData({
    required this.label,
    required this.value,
    this.supporting,
  });

  final String label;
  final String value;
  final String? supporting;
}

class _DefinitionGrid extends StatelessWidget {
  const _DefinitionGrid({required this.items});

  final List<_DefinitionData> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < items.length; index++)
          _DefinitionItem(
            data: items[index],
            last: index == items.length - 1,
          ),
      ],
    );
  }
}

class _DefinitionItem extends StatelessWidget {
  const _DefinitionItem({required this.data, this.last = false});

  final _DefinitionData data;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontal =
            constraints.maxWidth >= ResponsiveBreakpoints.phoneMaxExclusive;
        final value = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              data.value,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            if (data.supporting != null && data.supporting!.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(
                data.supporting!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
              ),
            ],
          ],
        );
        return Container(
          constraints: BoxConstraints(minHeight: horizontal ? 54 : 62),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: last
              ? null
              : BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: colors.outlineVariant),
                  ),
                ),
          child: horizontal
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 158,
                      child: Text(
                        data.label,
                        style:
                            Theme.of(context).textTheme.labelMedium?.copyWith(
                                  color: colors.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                ),
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(child: value),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      data.label,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: colors.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 5),
                    value,
                  ],
                ),
        );
      },
    );
  }
}

class _InlineStatus extends StatelessWidget {
  const _InlineStatus({
    required this.icon,
    required this.label,
    this.isWarning = false,
  });

  final IconData icon;
  final String label;
  final bool isWarning;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = isWarning ? colors.error : colors.tertiary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 17, color: color),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
      ],
    );
  }
}

class _InlineNotice extends StatelessWidget {
  const _InlineNotice({
    required this.message,
    this.title,
    this.positive = false,
    super.key,
  });

  final String? title;
  final String message;
  final bool positive;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final accent = positive ? colors.tertiary : colors.onSurfaceVariant;
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            positive ? Icons.link : Icons.info_outline,
            size: 20,
            color: accent,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null) ...[
                  Text(
                    title!,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 4),
                ],
                Text(
                  message,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                        height: 1.45,
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

class _InlineOperationError extends StatelessWidget {
  const _InlineOperationError({
    required this.message,
    super.key,
  });

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.error_outline, color: colors.error, size: 20),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            message,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colors.error,
                  height: 1.4,
                ),
          ),
        ),
      ],
    );
  }
}

class _StaleProfileNotice extends StatelessWidget {
  const _StaleProfileNotice({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return _InlineNoticeWithAction(
      key: const ValueKey('erp-profile-stale-notice'),
      title: 'Mostrando la última información disponible',
      message:
          'No pudimos actualizar el perfil. Revisa tu conexión y vuelve a intentarlo; no se ha descartado la información anterior.',
      actionLabel: 'Reintentar',
      onAction: onRetry,
    );
  }
}

class _InlineNoticeWithAction extends StatelessWidget {
  const _InlineNoticeWithAction({
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
    super.key,
  });

  final String title;
  final String message;
  final String actionLabel;
  final Future<void> Function() onAction;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 16,
        runSpacing: 12,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
              minimumSize: const Size(48, 48),
            ),
            child: Text(actionLabel),
          ),
        ],
      ),
    );
  }
}

class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({
    required this.profile,
    required this.radius,
  });

  final CurrentUserProfile profile;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final photoUrl = profile.employee?.photoUrl;
    final colors = Theme.of(context).colorScheme;
    final fallback = CircleAvatar(
      radius: radius,
      backgroundColor: colors.surfaceContainerHighest,
      foregroundColor: colors.onSurfaceVariant,
      child: Text(
        profile.initials,
        style: TextStyle(
          fontSize: radius * 0.58,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
    if (photoUrl == null) return fallback;

    return ClipOval(
      child: Image.network(
        photoUrl,
        width: radius * 2,
        height: radius * 2,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback,
      ),
    );
  }
}

class _ProfileLoadingWorkspace extends StatelessWidget {
  const _ProfileLoadingWorkspace({required this.showPageTitle});

  final bool showPageTitle;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        key: const ValueKey('erp-profile-loading'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        child: Semantics(
          liveRegion: true,
          label: 'Cargando tu perfil',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (showPageTitle) ...[
                Text(
                  'Mi perfil',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 20),
              ],
              Container(
                constraints: const BoxConstraints(minHeight: 124),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(18),
                ),
                padding: const EdgeInsets.all(20),
                child: const Center(child: BrandedLoading()),
              ),
              const SizedBox(height: 22),
              Text(
                'Cargando identidad, vínculo laboral y permisos…',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 14),
              const LinearProgressIndicator(minHeight: 3),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileLoadFailure extends StatelessWidget {
  const _ProfileLoadFailure({
    required this.issue,
    required this.onRetry,
    required this.showPageTitle,
  });

  final CurrentUserProfileLoadIssue? issue;
  final Future<void> Function() onRetry;
  final bool showPageTitle;

  @override
  Widget build(BuildContext context) {
    final (title, message) = switch (issue) {
      CurrentUserProfileLoadIssue.inconsistentEmployeeLink => (
          'Vínculo laboral por revisar',
          'Tu cuenta y tu ficha de trabajador no coinciden. Por seguridad, no mostramos datos laborales hasta que un administrador corrija el vínculo.',
        ),
      CurrentUserProfileLoadIssue.invalidAccessContext => (
          'No pudimos validar tu acceso',
          'La sesión no coincide con un perfil activo del negocio. Cierra sesión y vuelve a ingresar o contacta a un administrador.',
        ),
      _ => (
          'No pudimos cargar tu perfil',
          'Revisa tu conexión e inténtalo nuevamente. No se realizó ningún cambio.',
        ),
    };
    final colors = Theme.of(context).colorScheme;

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showPageTitle) ...[
              Text(
                'Mi perfil',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 22),
            ],
            Container(
              key: const ValueKey('erp-profile-load-failure'),
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: Color.alphaBlend(
                  colors.error.withValues(alpha: 0.06),
                  colors.surface,
                ),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.shield_outlined, color: colors.error, size: 28),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style:
                              Theme.of(context).textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                        const SizedBox(height: 7),
                        Text(
                          message,
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: colors.onSurfaceVariant,
                                    height: 1.45,
                                  ),
                        ),
                        const SizedBox(height: 18),
                        FilledButton.icon(
                          onPressed: onRetry,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Reintentar'),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(48, 48),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _PasswordChangeStep {
  password,
  verification,
  sessionRevocation,
}

class _ErpPasswordChangeDialog extends StatefulWidget {
  const _ErpPasswordChangeDialog({
    required this.email,
    required this.initialRevocationPending,
  });

  final String email;
  final bool initialRevocationPending;

  @override
  State<_ErpPasswordChangeDialog> createState() =>
      _ErpPasswordChangeDialogState();
}

class _ErpPasswordChangeDialogState extends State<_ErpPasswordChangeDialog> {
  final _passwordFormKey = GlobalKey<FormState>();
  final _verificationFormKey = GlobalKey<FormState>();
  final _newPassword = TextEditingController();
  final _confirmPassword = TextEditingController();
  final _verificationCode = TextEditingController();
  late _PasswordChangeStep _step;
  bool _busy = false;
  String? _error;
  String? _notice;

  @override
  void initState() {
    super.initState();
    _step = widget.initialRevocationPending
        ? _PasswordChangeStep.sessionRevocation
        : _PasswordChangeStep.password;
  }

  @override
  void dispose() {
    _newPassword.dispose();
    _confirmPassword.dispose();
    _verificationCode.dispose();
    super.dispose();
  }

  Future<void> _submitPassword() async {
    if (_busy || _passwordFormKey.currentState?.validate() != true) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });

    SelfPasswordUpdateResult? result;
    var requiresCode = false;
    try {
      result = await context
          .read<CurrentUserProfileService>()
          .updatePassword(_newPassword.text);
    } on AuthException catch (error) {
      final issue =
          CurrentUserProfileService.classifyPasswordUpdateError(error);
      if (issue == SelfPasswordUpdateIssue.reauthenticationRequired) {
        requiresCode = true;
      } else if (mounted) {
        setState(() => _error = _passwordMessage(issue));
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'No pudimos actualizar la contraseña. Inténtalo nuevamente.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }

    if (result != null && mounted) {
      _handlePasswordUpdateResult(result);
    } else if (requiresCode && mounted) {
      await _requestCode();
    }
  }

  Future<void> _requestCode({bool resend = false}) async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _step = _PasswordChangeStep.verification;
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await context
          .read<CurrentUserProfileService>()
          .requestPasswordReauthentication();
      if (!mounted) return;
      _verificationCode.clear();
      setState(() {
        _notice = resend
            ? 'Enviamos un código nuevo. Usa solamente el último recibido.'
            : 'Enviamos un código de verificación a tu correo.';
      });
    } on AuthException catch (error) {
      if (!mounted) return;
      final code = error.code?.toLowerCase();
      setState(() {
        _error = code == 'over_email_send_rate_limit' ||
                code == 'over_request_rate_limit'
            ? 'Espera un momento antes de solicitar otro código.'
            : 'No pudimos enviar el código. Inténtalo nuevamente.';
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'No pudimos enviar el código. Inténtalo nuevamente.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verifyAndUpdate() async {
    if (_busy || _verificationFormKey.currentState?.validate() != true) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    SelfPasswordUpdateResult? result;
    try {
      result = await context.read<CurrentUserProfileService>().updatePassword(
            _newPassword.text,
            reauthenticationNonce: _verificationCode.text,
          );
    } on AuthException catch (error) {
      if (mounted) {
        final issue =
            CurrentUserProfileService.classifyPasswordUpdateError(error);
        setState(() => _error = _verificationMessage(issue));
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'No pudimos verificar el código. Inténtalo nuevamente.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (result != null && mounted) _handlePasswordUpdateResult(result);
  }

  void _handlePasswordUpdateResult(SelfPasswordUpdateResult result) {
    if (result.otherSessionsRevoked) {
      _finish();
      return;
    }

    _newPassword.clear();
    _confirmPassword.clear();
    _verificationCode.clear();
    setState(() {
      _step = _PasswordChangeStep.sessionRevocation;
      _error = null;
      _notice = null;
    });
  }

  Future<void> _retryOtherSessionRevocation() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    var completed = false;
    try {
      final outcome = await context
          .read<CurrentUserProfileService>()
          .retryOtherSessionRevocation();
      if (!mounted) return;
      if (outcome == SelfPasswordOtherSessionsRevocationOutcome.revoked) {
        completed = true;
      } else {
        setState(() {
          _error =
              'La contraseña sigue actualizada, pero no pudimos cerrar las demás sesiones. Revisa tu conexión y reintenta.';
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error =
            'La contraseña sigue actualizada, pero no pudimos cerrar las demás sesiones. Puedes reintentarlo desde Seguridad.';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }

    if (completed && mounted) _finish();
  }

  void _finish() {
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Contraseña actualizada y demás sesiones cerradas'),
      ),
    );
  }

  String _passwordMessage(SelfPasswordUpdateIssue issue) {
    if (issue == SelfPasswordUpdateIssue.samePassword) {
      return 'La nueva contraseña debe ser distinta a la actual.';
    }
    return 'No pudimos actualizar la contraseña. Inténtalo nuevamente.';
  }

  String _verificationMessage(SelfPasswordUpdateIssue issue) {
    return switch (issue) {
      SelfPasswordUpdateIssue.invalidVerificationCode =>
        'El código no es válido. Revísalo e inténtalo nuevamente.',
      SelfPasswordUpdateIssue.expiredVerificationCode =>
        'El código venció. Solicita uno nuevo para continuar.',
      SelfPasswordUpdateIssue.reauthenticationRequired =>
        'El código venció o ya no es válido. Solicita uno nuevo.',
      SelfPasswordUpdateIssue.samePassword =>
        'La nueva contraseña debe ser distinta a la actual.',
      SelfPasswordUpdateIssue.unknown =>
        'No pudimos verificar el código. Inténtalo nuevamente.',
    };
  }

  @override
  Widget build(BuildContext context) {
    final verification = _step == _PasswordChangeStep.verification;
    final sessionRevocation = _step == _PasswordChangeStep.sessionRevocation;
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        scrollable: true,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        title: Text(
          sessionRevocation
              ? 'Completar seguridad'
              : verification
                  ? 'Verifica que eres tú'
                  : 'Cambiar contraseña',
        ),
        content: SafeArea(
          top: false,
          bottom: false,
          child: SizedBox(
            width: 420,
            child: AnimatedSwitcher(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 180),
              child: sessionRevocation
                  ? _sessionRevocationStep()
                  : verification
                      ? _verificationStep()
                      : _passwordStep(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
            child: Text(sessionRevocation ? 'Cerrar por ahora' : 'Cancelar'),
          ),
          if (verification)
            TextButton(
              onPressed: _busy ? null : () => _requestCode(resend: true),
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              child: const Text('Reenviar código'),
            ),
          FilledButton(
            onPressed: _busy
                ? null
                : sessionRevocation
                    ? _retryOtherSessionRevocation
                    : verification
                        ? _verifyAndUpdate
                        : _submitPassword,
            style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
            child: _busy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    sessionRevocation
                        ? 'Reintentar cierre'
                        : verification
                            ? 'Verificar y cambiar'
                            : 'Cambiar',
                  ),
          ),
        ],
      ),
    );
  }

  Widget _sessionRevocationStep() {
    final colors = Theme.of(context).colorScheme;
    return Column(
      key: const ValueKey('erp-password-session-revocation-step'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Tu contraseña ya quedó actualizada.',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 8),
        const Text(
          'No pudimos cerrar las demás sesiones. Puedes reintentar solamente ese cierre; no necesitas volver a ingresar ni cambiar tu contraseña.',
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(
            _error!,
            key: const ValueKey('erp-password-session-revocation-error'),
            style: TextStyle(color: colors.error),
          ),
        ],
      ],
    );
  }

  Widget _passwordStep() {
    return Form(
      key: _passwordFormKey,
      child: AutofillGroup(
        child: Column(
          key: const ValueKey('erp-password-change-step'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Elige una contraseña nueva. Si hace falta una verificación reciente, te enviaremos un código.',
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _newPassword,
              decoration: const InputDecoration(
                labelText: 'Nueva contraseña',
                helperText: AuthInputValidation.strongPasswordHelper,
              ),
              obscureText: true,
              autofillHints: const [AutofillHints.newPassword],
              textInputAction: TextInputAction.next,
              validator: (value) => AuthInputValidation.validatePassword(
                value,
                isNewPassword: true,
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _confirmPassword,
              decoration: const InputDecoration(
                labelText: 'Confirmar contraseña',
              ),
              obscureText: true,
              autofillHints: const [AutofillHints.newPassword],
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _submitPassword(),
              validator: (value) =>
                  AuthInputValidation.validatePasswordConfirmation(
                value,
                password: _newPassword.text,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                key: const ValueKey('erp-password-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _verificationStep() {
    return Form(
      key: _verificationFormKey,
      child: Column(
        key: const ValueKey('erp-password-verification-step'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.email.isEmpty
                ? 'Ingresa el código de 6 dígitos enviado a tu correo.'
                : 'Ingresa el código de 6 dígitos enviado a ${widget.email}.',
          ),
          const SizedBox(height: 16),
          TextFormField(
            key: const ValueKey('erp-password-verification-field'),
            controller: _verificationCode,
            autofocus: true,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.oneTimeCode],
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
            maxLength: 6,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              letterSpacing: 5,
            ),
            decoration: const InputDecoration(
              labelText: 'Código de verificación',
              counterText: '',
            ),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            onFieldSubmitted: (_) => _verifyAndUpdate(),
            validator: (value) {
              if (!RegExp(r'^\d{6}$').hasMatch(value?.trim() ?? '')) {
                return 'Ingresa los 6 dígitos del código.';
              }
              return null;
            },
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              key: const ValueKey('erp-password-verification-error'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          if (_notice != null) ...[
            const SizedBox(height: 10),
            Text(
              _notice!,
              style: TextStyle(color: Theme.of(context).colorScheme.primary),
            ),
          ],
        ],
      ),
    );
  }
}

String _roleLabel(String role) {
  return switch (role) {
    'owner' => 'Propietario/a',
    'admin' => 'Administrador/a',
    'manager' => 'Gerente',
    'cashier' => 'Cajero/a',
    'mechanic' => 'Mecánico/a',
    'accountant' => 'Contador/a',
    'employee' => 'Trabajador/a',
    _ => role,
  };
}

String _employeeStatusLabel(String status) {
  return switch (status) {
    'active' => 'Activo/a',
    'inactive' => 'Inactivo/a',
    'terminated' => 'Desvinculado/a',
    'on_leave' => 'Con licencia',
    _ => status,
  };
}

const _weekdayNames = <String>[
  'Lunes',
  'Martes',
  'Miércoles',
  'Jueves',
  'Viernes',
  'Sábado',
  'Domingo',
];

const _shortWeekdayNames = <String>[
  'LUN',
  'MAR',
  'MIÉ',
  'JUE',
  'VIE',
  'SÁB',
  'DOM',
];

const _monthNames = <String>[
  'enero',
  'febrero',
  'marzo',
  'abril',
  'mayo',
  'junio',
  'julio',
  'agosto',
  'septiembre',
  'octubre',
  'noviembre',
  'diciembre',
];

/// ISO weekday name, `1` = Monday.
String _weekdayName(int dayOfWeek) => _weekdayNames[(dayOfWeek - 1) % 7];

String _shortWeekday(DateTime date) =>
    _shortWeekdayNames[(date.weekday - 1) % 7];

bool _isSameDate(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String _weekRangeLabel(DateTime start, DateTime end) {
  if (start.month == end.month) {
    return '${start.day} – ${end.day} de ${_monthNames[end.month - 1]}';
  }
  return '${start.day} de ${_monthNames[start.month - 1]} – '
      '${end.day} de ${_monthNames[end.month - 1]}';
}

String _two(int value) => value.toString().padLeft(2, '0');

String _formatTime(DateTime value) =>
    '${_two(value.hour)}:${_two(value.minute)}';

String _formatTimeRange(DateTime start, DateTime end) =>
    '${_formatTime(start)} – ${_formatTime(end)}';

/// `HH:MM` from a Postgres `time` value such as `09:00:00`.
String _trimTime(String value) {
  final parts = value.split(':');
  if (parts.length < 2) return value;
  return '${parts[0].padLeft(2, '0')}:${parts[1]}';
}

String _formatDuration(Duration value) {
  final minutes = value.inMinutes.abs();
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  if (hours == 0) return '$rest min';
  if (rest == 0) return '$hours h';
  return '$hours h $rest min';
}

String _formatSignedDuration(Duration value) {
  if (value.inMinutes == 0) return 'Sin diferencia';
  final sign = value.isNegative ? '−' : '+';
  return '$sign${_formatDuration(value)}';
}

String _formatHours(double hours) {
  return _formatDuration(Duration(minutes: (hours * 60).round()));
}

String _shiftStatusLabel(String status) {
  return switch (status) {
    'draft' => 'Borrador',
    'published' => 'Publicado',
    'completed' => 'Completado',
    'cancelled' => 'Cancelado',
    _ => status,
  };
}

String _payrollStatusLabel(String status) {
  return switch (status) {
    'draft' => 'Borrador',
    'confirmed' => 'Confirmada',
    'partial' => 'Pago parcial',
    'paid' => 'Pagada',
    _ => status,
  };
}

String _payrollPeriodLabel(SelfPayrollLine line) {
  final label = line.periodLabel;
  if (label != null && label.isNotEmpty) return label;
  return '${ChileanUtils.formatDate(line.periodStart)} – '
      '${ChileanUtils.formatDate(line.periodEnd)}';
}

String _paymentMethodLabel(String value) {
  return switch (value) {
    'transfer' => 'Transferencia',
    'cash' => 'Efectivo',
    'check' => 'Cheque',
    _ => value,
  };
}

String _requestTypeLabel(String value) {
  return switch (value) {
    'create' => 'Nuevo turno solicitado',
    'update' => 'Cambio de turno',
    'delete' => 'Liberar turno',
    'availability' => 'Cambio de disponibilidad',
    _ => value,
  };
}

String _requestStatusLabel(String value) {
  return switch (value) {
    'pending' => 'Pendiente',
    'approved' => 'Aprobada',
    'rejected' => 'Rechazada',
    'cancelled' => 'Cancelada',
    _ => value,
  };
}

String _requestDetail(SelfShiftChangeRequest request) {
  final start = request.requestedStartAt;
  final end = request.requestedEndAt;
  final created = 'Enviada el ${ChileanUtils.formatDate(
    employeeSelfServiceLocalTime(request.createdAt, request.timezone),
  )}';
  if (start == null || end == null) {
    return request.workerNote ?? created;
  }
  final localStart = employeeSelfServiceLocalTime(start, request.timezone);
  final localEnd = employeeSelfServiceLocalTime(end, request.timezone);
  return '${ChileanUtils.formatDate(localStart)} · '
      '${_formatTimeRange(localStart, localEnd)} — $created';
}
