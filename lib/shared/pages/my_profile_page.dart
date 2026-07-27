import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;

import '../models/current_user_profile.dart';
import '../services/auth_service.dart';
import '../services/current_user_profile_service.dart';
import '../services/self_password_service.dart';
import '../services/tenant_service.dart';
import '../services/workspace_manager.dart';
import '../utils/auth_input_validation.dart';
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

  Future<void> _refresh({bool force = true}) {
    final authService = context.read<AuthService>();
    final user = authService.currentUser;
    return context.read<CurrentUserProfileService>().synchronize(
          identity: user == null ? null : CurrentUserIdentity.fromUser(user),
          resolveTenantId: context.read<TenantService>().getTenantId,
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
          title: Text(
            'Mi perfil',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
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

  final _sectionKeys = List<GlobalKey>.generate(
    _ProfileSectionId.values.length,
    (index) => GlobalKey(debugLabel: 'profile-section-$index'),
  );

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
  _ProfileSectionId _selectedSection = _ProfileSectionId.summary;

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

  Future<void> _goToSection(_ProfileSectionId section) async {
    setState(() => _selectedSection = section);
    final targetContext = _sectionKeys[section.index].currentContext;
    if (targetContext == null) return;
    await Scrollable.ensureVisible(
      targetContext,
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      alignment: 0.02,
    );
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
          final showSectionRail =
              constraints.maxWidth >= ResponsiveBreakpoints.desktopMin;
          final pagePadding =
              constraints.maxWidth >= ResponsiveBreakpoints.phoneMaxExclusive
                  ? 28.0
                  : 16.0;

          final scrollable = RefreshIndicator(
            onRefresh: _refreshSafely,
            child: SingleChildScrollView(
              key: const ValueKey('erp-profile-scroll'),
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                pagePadding,
                showSectionRail ? 28 : 20,
                pagePadding,
                56 + MediaQuery.paddingOf(context).bottom,
              ),
              child: _ProfileDetailsWorkspace(
                profile: profile,
                service: service,
                sectionKeys: _sectionKeys,
                showPageTitle: !ResponsiveViewport.usesCompactShell(context),
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
          );

          return Stack(
            children: [
              if (showSectionRail)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: 224,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 28, 12, 28),
                        child: _ProfileSectionNavigator(
                          selected: _selectedSection,
                          profile: profile,
                          onSelected: _goToSection,
                        ),
                      ),
                    ),
                    VerticalDivider(
                      width: 1,
                      thickness: 1,
                      color: Theme.of(context).dividerColor,
                    ),
                    Expanded(child: scrollable),
                  ],
                )
              else
                scrollable,
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
  summary,
  personal,
  employment,
  access,
  security,
}

extension on _ProfileSectionId {
  String get label => switch (this) {
        _ProfileSectionId.summary => 'Resumen',
        _ProfileSectionId.personal => 'Datos personales',
        _ProfileSectionId.employment => 'Vínculo laboral',
        _ProfileSectionId.access => 'Acceso',
        _ProfileSectionId.security => 'Seguridad',
      };
}

class _ProfileSectionNavigator extends StatelessWidget {
  const _ProfileSectionNavigator({
    required this.selected,
    required this.profile,
    required this.onSelected,
  });

  final _ProfileSectionId selected;
  final CurrentUserProfile profile;
  final ValueChanged<_ProfileSectionId> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final background = Color.alphaBlend(
      colors.primary.withValues(alpha: 0.055),
      colors.surface,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'MI PERFIL',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: colors.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    profile.displayName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ],
              ),
            ),
            for (final section in _ProfileSectionId.values)
              _SectionNavigationRow(
                label: section.label,
                selected: section == selected,
                onTap: () => onSelected(section),
              ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
              child: _LinkStateSummary(profile: profile),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionNavigationRow extends StatelessWidget {
  const _SectionNavigationRow({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                width: 3,
                height: selected ? 28 : 0,
                decoration: BoxDecoration(
                  color: colors.primary,
                  borderRadius: const BorderRadius.horizontal(
                    right: Radius.circular(3),
                  ),
                ),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color:
                            selected ? colors.primary : colors.onSurfaceVariant,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w500,
                      ),
                ),
              ),
              const SizedBox(width: 12),
            ],
          ),
        ),
      ),
    );
  }
}

class _LinkStateSummary extends StatelessWidget {
  const _LinkStateSummary({required this.profile});

  final CurrentUserProfile profile;

  @override
  Widget build(BuildContext context) {
    final linked = profile.employeeLinkState == EmployeeLinkState.linked;
    final colors = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          linked ? Icons.link : Icons.info_outline,
          size: 18,
          color: linked ? colors.primary : colors.onSurfaceVariant,
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            linked
                ? 'Cuenta vinculada a una ficha laboral.'
                : 'Cuenta aún sin ficha laboral vinculada.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                  height: 1.35,
                ),
          ),
        ),
      ],
    );
  }
}

class _ProfileDetailsWorkspace extends StatelessWidget {
  const _ProfileDetailsWorkspace({
    required this.profile,
    required this.service,
    required this.sectionKeys,
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
  final List<GlobalKey> sectionKeys;
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showPageTitle) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Mi perfil',
                      style: Theme.of(context)
                          .textTheme
                          .headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'Tu identidad, datos personales, acceso y seguridad en un solo lugar.',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
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
          const SizedBox(height: 24),
        ],
        if (showStaleNotice) ...[
          _StaleProfileNotice(onRetry: onRefresh),
          const SizedBox(height: 18),
        ],
        KeyedSubtree(
          key: sectionKeys[_ProfileSectionId.summary.index],
          child: _ProfileHero(profile: profile),
        ),
        const SizedBox(height: 34),
        KeyedSubtree(
          key: sectionKeys[_ProfileSectionId.personal.index],
          child: _ProfileSection(
            title: 'Datos personales',
            description: profile.employee == null
                ? 'Administra el nombre visible de tu cuenta. El correo de acceso se mantiene como identidad de inicio de sesión.'
                : 'Actualiza únicamente la información personal que te corresponde. Los datos legales siguen bajo control de RR.HH.',
            child: _PersonalDetails(
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
            ),
          ),
        ),
        KeyedSubtree(
          key: sectionKeys[_ProfileSectionId.employment.index],
          child: _ProfileSection(
            title: 'Vínculo laboral',
            description:
                'Explica cómo tu usuario ERP se relaciona con la ficha de trabajador y quién puede modificar cada dato.',
            child: _EmploymentDetails(profile: profile),
          ),
        ),
        KeyedSubtree(
          key: sectionKeys[_ProfileSectionId.access.index],
          child: _ProfileSection(
            title: 'Acceso al ERP',
            description:
                'El negocio, el rol y los permisos son de solo lectura y los administra un responsable autorizado.',
            child: _AccessDetails(profile: profile),
          ),
        ),
        KeyedSubtree(
          key: sectionKeys[_ProfileSectionId.security.index],
          child: _ProfileSection(
            title: 'Seguridad',
            description:
                'Protege tu cuenta y revisa la consecuencia de cada acción antes de continuar.',
            showDivider: false,
            child: _SecurityDetails(profile: profile, service: service),
          ),
        ),
      ],
    );
  }
}

class _ProfileHero extends StatelessWidget {
  const _ProfileHero({required this.profile});

  final CurrentUserProfile profile;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final background = Color.alphaBlend(
      colors.primary.withValues(alpha: 0.075),
      colors.surface,
    );
    return Semantics(
      container: true,
      label:
          '${profile.displayName}, ${_roleLabel(profile.role)}, ${profile.tenantName}',
      child: Container(
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(22),
        ),
        padding: const EdgeInsets.all(24),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final roomy =
                constraints.maxWidth >= ResponsiveBreakpoints.phoneMaxExclusive;
            final identity = Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _ProfileAvatar(profile: profile, radius: roomy ? 35 : 30),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profile.displayName,
                        key: const ValueKey('erp-profile-display-name'),
                        style:
                            Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  height: 1.12,
                                ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        profile.email,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                      ),
                      const SizedBox(height: 9),
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
                ),
              ],
            );
            final contextSummary = _HeroContextSummary(profile: profile);

            if (!roomy) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  identity,
                  const SizedBox(height: 20),
                  Divider(color: Theme.of(context).dividerColor),
                  const SizedBox(height: 10),
                  contextSummary,
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(flex: 3, child: identity),
                const SizedBox(width: 28),
                SizedBox(
                  height: 76,
                  child: VerticalDivider(
                    color: Theme.of(context).dividerColor,
                  ),
                ),
                const SizedBox(width: 28),
                Expanded(flex: 2, child: contextSummary),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _HeroContextSummary extends StatelessWidget {
  const _HeroContextSummary({required this.profile});

  final CurrentUserProfile profile;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          profile.tenantName,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          _roleLabel(profile.role),
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 10),
        Text(
          profile.employee == null
              ? 'Cuenta ERP sin ficha laboral vinculada'
              : '${profile.employee!.jobTitle} · ${profile.employee!.departmentName ?? 'Sin departamento'}',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
                height: 1.35,
              ),
        ),
      ],
    );
  }
}

class _ProfileSection extends StatelessWidget {
  const _ProfileSection({
    required this.title,
    required this.description,
    required this.child,
    this.showDivider = true,
  });

  final String title;
  final String description;
  final Widget child;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 6),
        Text(
          description,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
                height: 1.45,
              ),
        ),
        const SizedBox(height: 20),
        child,
        if (showDivider) ...[
          const SizedBox(height: 30),
          Divider(color: Theme.of(context).dividerColor),
          const SizedBox(height: 30),
        ] else
          const SizedBox(height: 12),
      ],
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
      return _DisplayNameEditor(
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
      );
    }

    return _EmployeeContactEditor(
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
    final employee = profile.employee!;
    if (!editing) {
      return Column(
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
              _DefinitionData(
                label: 'Contacto de emergencia',
                value: employee.emergencyContactName ?? 'Sin informar',
                supporting: employee.emergencyContactPhone,
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (profile.canEditEmployeeContact)
            Align(
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
            )
          else
            const _InlineNotice(
              message:
                  'La edición está disponible únicamente para trabajadores activos.',
            ),
        ],
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
      return Column(
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
                onPressed: () => context.push('/settings/users'),
                icon: const Icon(Icons.arrow_forward),
                label: const Text('Gestionar vínculos de usuarios'),
                style: TextButton.styleFrom(
                  minimumSize: const Size(48, 48),
                ),
              ),
            ),
          ],
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _InlineNotice(
          key: ValueKey('erp-profile-linked-employee'),
          title: 'Ficha laboral vinculada',
          message:
              'La identidad legal, el cargo, el departamento, el estado y la remuneración son administrados por RR.HH. o un responsable autorizado.',
          positive: true,
        ),
        const SizedBox(height: 18),
        _DefinitionGrid(
          items: [
            _DefinitionData(label: 'Nombre legal', value: employee.fullName),
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
        if (profile.canManageUsers) ...[
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => context.push('/hr/employees/${employee.id}'),
              icon: const Icon(Icons.open_in_new),
              label: const Text('Abrir ficha laboral'),
              style: TextButton.styleFrom(
                minimumSize: const Size(48, 48),
              ),
            ),
          ),
        ],
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DefinitionGrid(
          items: [
            _DefinitionData(label: 'Negocio', value: profile.tenantName),
            _DefinitionData(
              label: 'Subdominio',
              value: profile.tenantSubdomain ?? 'Sin subdominio',
            ),
            _DefinitionData(label: 'Rol', value: _roleLabel(profile.role)),
          ],
        ),
        const SizedBox(height: 18),
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            key: const ValueKey('erp-profile-permissions-disclosure'),
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 8),
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
                  : 'Abre el detalle para revisar qué acciones están habilitadas.',
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
        color: Color.alphaBlend(
          colors.primary.withValues(alpha: 0.045),
          colors.surface,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      padding: const EdgeInsets.all(20),
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
          runSpacing: 0,
          children: [
            for (final item in items)
              SizedBox(
                width: width,
                child: _DefinitionItem(data: item),
              ),
          ],
        );
      },
    );
  }
}

class _DefinitionItem extends StatelessWidget {
  const _DefinitionItem({required this.data});

  final _DefinitionData data;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minHeight: 70),
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.72),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            data.label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 4),
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
      ),
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
    final color = isWarning ? colors.error : colors.primary;
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
    final accent = positive ? colors.primary : colors.onSurfaceVariant;
    return Container(
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          accent.withValues(alpha: positive ? 0.065 : 0.04),
          colors.surface,
        ),
        borderRadius: BorderRadius.circular(14),
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
        color: Color.alphaBlend(
          colors.primary.withValues(alpha: 0.055),
          colors.surface,
        ),
        borderRadius: BorderRadius.circular(14),
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
      backgroundColor: colors.primary,
      foregroundColor: colors.onPrimary,
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
                constraints: const BoxConstraints(minHeight: 150),
                decoration: BoxDecoration(
                  color: Color.alphaBlend(
                    colors.primary.withValues(alpha: 0.065),
                    colors.surface,
                  ),
                  borderRadius: BorderRadius.circular(22),
                ),
                padding: const EdgeInsets.all(24),
                child: const Center(child: BrandedLoading()),
              ),
              const SizedBox(height: 30),
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
