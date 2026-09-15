import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../../shared/services/current_user_profile_service.dart';
import '../../../shared/services/tenant_service.dart';
import '../../../shared/services/user_management_navigation.dart';
import '../../../shared/services/user_management_service.dart';
import '../../../shared/utils/auth_input_validation.dart';
import '../../../shared/widgets/branded_loading.dart';
import '../../../shared/widgets/vb_notice.dart';

enum _IdentityAudience { staff, customers, invitations }

class UserManagementPage extends StatefulWidget {
  const UserManagementPage({
    super.key,
    this.initialOpenRequest,
  });

  final String? initialOpenRequest;

  @override
  State<UserManagementPage> createState() => _UserManagementPageState();
}

class _UserManagementPageState extends State<UserManagementPage> {
  static const _noEmployeeSelection = '__no_employee__';

  late final UserManagementService _userService;
  late final TenantService _tenantService;
  CurrentUserProfileService? _profileService;
  final _searchController = TextEditingController();
  final _listScrollController = ScrollController();
  final _detailScrollController = ScrollController();

  Map<String, dynamic>? _currentTenant;
  List<Map<String, dynamic>> _staffUsers = [];
  List<Map<String, dynamic>> _customerAccounts = [];
  List<Map<String, dynamic>> _invitations = [];
  List<EmployeeAccessState> _employeeAccessStates = [];
  Map<String, dynamic>? _selectedItem;
  _IdentityAudience _audience = _IdentityAudience.staff;
  Timer? _searchDebounce;
  bool _compactShowingDetail = false;
  bool _compactSelectionWasExplicit = false;
  bool _dependenciesInitialized = false;
  bool _dataLoadStarted = false;
  bool _isLoading = true;
  bool _isActionRunning = false;
  String? _errorMessage;
  String? _accessBlockTitle;
  String? _accessBlockMessage;
  UserManagementOpenRequest? _openRequest;
  bool _requestedTargetUnavailable = false;

  static const _roleOptions = <String, String>{
    'admin': 'Administrador',
    'manager': 'Gerente',
    'cashier': 'Cajero',
    'mechanic': 'Mecánico',
    'accountant': 'Contador',
  };

  static const _permissionOptions = <_PermissionOption>[
    _PermissionOption('access_pos', 'Acceso a POS', Icons.point_of_sale),
    _PermissionOption('create_invoices', 'Crear facturas', Icons.receipt_long),
    _PermissionOption('edit_prices', 'Editar precios', Icons.sell_outlined),
    _PermissionOption(
        'delete_invoices', 'Eliminar facturas', Icons.delete_outline),
    _PermissionOption(
        'access_accounting', 'Acceso contable', Icons.account_balance),
    _PermissionOption(
        'manage_users', 'Gestionar usuarios', Icons.manage_accounts),
    _PermissionOption(
      'can_manage_supplier_credentials',
      'Credenciales de proveedores',
      Icons.key_outlined,
    ),
    _PermissionOption('edit_settings', 'Editar configuración', Icons.tune),
  ];

  @override
  void initState() {
    super.initState();
    _userService = Provider.of<UserManagementService>(context, listen: false);
    _tenantService = Provider.of<TenantService>(context, listen: false);
    _stageOpenRequest(widget.initialOpenRequest);
    _searchController.addListener(_scheduleSearch);
  }

  @override
  void didUpdateWidget(covariant UserManagementPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialOpenRequest == widget.initialOpenRequest) return;
    final request =
        UserManagementOpenRequest.tryParse(widget.initialOpenRequest);
    if (request == null) return;
    _searchDebounce?.cancel();
    _clearSearchWithoutNotification();
    setState(() => _stageOpenRequest(widget.initialOpenRequest));
    if (_dataLoadStarted && _hasManagementAccess) {
      unawaited(_loadData(silent: true));
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextProfileService =
        Provider.of<CurrentUserProfileService?>(context, listen: false);
    if (_dependenciesInitialized &&
        identical(nextProfileService, _profileService)) {
      return;
    }
    _dependenciesInitialized = true;
    _profileService?.removeListener(_evaluateAccess);
    _profileService = nextProfileService;
    _profileService?.addListener(_evaluateAccess);
    _evaluateAccess();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _profileService?.removeListener(_evaluateAccess);
    _searchController.dispose();
    _listScrollController.dispose();
    _detailScrollController.dispose();
    super.dispose();
  }

  bool get _hasManagementAccess =>
      _profileService == null ||
      _profileService?.profile?.canManageUsers == true;

  void _evaluateAccess() {
    final service = _profileService;
    if (service == null) {
      _startInitialLoad();
      return;
    }
    if (service.isLoading && service.profile == null) {
      if (!mounted) return;
      setState(() {
        _isLoading = true;
        _accessBlockTitle = null;
        _accessBlockMessage = null;
      });
      return;
    }
    if (service.profile?.canManageUsers == true) {
      if (mounted &&
          (_accessBlockTitle != null || _accessBlockMessage != null)) {
        setState(() {
          _accessBlockTitle = null;
          _accessBlockMessage = null;
        });
      }
      _startInitialLoad();
      return;
    }

    _dataLoadStarted = false;
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _accessBlockTitle = service.profile == null
          ? 'No pudimos verificar tu acceso'
          : 'Acceso restringido';
      _accessBlockMessage = service.profile == null
          ? 'Tu perfil de acceso no está disponible. Vuelve a intentarlo antes de administrar identidades.'
          : 'Tu cuenta no tiene permiso para administrar usuarios, roles ni invitaciones.';
    });
  }

  void _startInitialLoad() {
    if (_dataLoadStarted || !_hasManagementAccess) return;
    _dataLoadStarted = true;
    unawaited(_loadData());
  }

  void _scheduleSearch() {
    _searchDebounce?.cancel();
    _openRequest = null;
    _requestedTargetUnavailable = false;
    if (_audience != _IdentityAudience.customers) {
      setState(() {
        _selectedItem = _resolveSelection();
      });
      return;
    }
    _searchDebounce = Timer(
      const Duration(milliseconds: 350),
      () => _loadData(silent: true),
    );
  }

  Future<void> _loadData({bool silent = false}) async {
    if (!_hasManagementAccess) return;
    if (!silent) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final overviewFuture = _userService.getIdentityOverview(
        search: _searchController.text.trim(),
        customerId: _openRequest?.target == UserManagementTarget.customer
            ? _openRequest?.targetId
            : null,
      );
      final tenantFuture = _tenantService.getCurrentTenant();
      final overview = await overviewFuture;
      final tenant = await tenantFuture;

      if (!mounted || !_hasManagementAccess) return;
      String? inviteEmployeeId;
      setState(() {
        _staffUsers = _listFrom(overview['staffUsers']);
        _customerAccounts = _listFrom(overview['customerAccounts']);
        _invitations = _listFrom(overview['invitations']);
        _employeeAccessStates =
            parseEmployeeAccessStates(overview['employeeAccessStates']);
        _currentTenant = tenant;
        final requestedSelection = _resolveRequestedSelection();
        final requestedEmployee =
            _openRequest?.target == UserManagementTarget.employee &&
                    _openRequest?.targetId != null
                ? _employeeAccessById(_openRequest!.targetId)
                : null;
        final shouldOpenEmployeeInvitation = requestedSelection == null &&
            requestedEmployee != null &&
            _canSelectEmployee(requestedEmployee);
        if (shouldOpenEmployeeInvitation) {
          inviteEmployeeId = requestedEmployee.employeeId;
        }
        _selectedItem =
            _openRequest == null ? _resolveSelection() : requestedSelection;
        _requestedTargetUnavailable = _openRequest?.target != null &&
            requestedSelection == null &&
            !shouldOpenEmployeeInvitation;
        _compactShowingDetail =
            _openRequest?.target != null && requestedSelection != null;
        if (_openRequest?.target != null) {
          _compactSelectionWasExplicit = requestedSelection != null;
        }
        if (shouldOpenEmployeeInvitation) {
          _openRequest = null;
        }
        _isLoading = false;
      });
      if (inviteEmployeeId != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          unawaited(
            _showInviteStaffDialog(initialEmployeeId: inviteEmployeeId),
          );
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage =
            'No pudimos cargar las identidades. Inténtalo nuevamente.';
        _isLoading = false;
      });
    }
  }

  List<Map<String, dynamic>> _listFrom(dynamic value) {
    return List<Map<String, dynamic>>.from(value as List? ?? const []);
  }

  Map<String, dynamic>? _resolveSelection() {
    final currentList = _visibleItemsForAudience(_audience);
    if (currentList.isEmpty) return null;
    final selected = _selectedItem;
    if (selected == null) return currentList.first;
    final selectedId = _identityId(selected);
    return currentList.firstWhere(
      (item) => _identityId(item) == selectedId,
      orElse: () => currentList.first,
    );
  }

  void _stageOpenRequest(String? encodedRequest) {
    final request = UserManagementOpenRequest.tryParse(encodedRequest);
    if (request == null) return;
    _openRequest = request;
    _audience = switch (request.audience) {
      UserManagementAudience.staff => _IdentityAudience.staff,
      UserManagementAudience.customers => _IdentityAudience.customers,
      UserManagementAudience.invitations => _IdentityAudience.invitations,
    };
    _selectedItem = null;
    _compactShowingDetail = false;
    _compactSelectionWasExplicit = false;
    _requestedTargetUnavailable = false;
  }

  void _clearSearchWithoutNotification() {
    if (_searchController.text.isEmpty) return;
    _searchController.removeListener(_scheduleSearch);
    _searchController.clear();
    _searchController.addListener(_scheduleSearch);
  }

  Map<String, dynamic>? _resolveRequestedSelection() {
    final request = _openRequest;
    final targetId = request?.targetId?.trim();
    if (request == null || request.target == null || targetId == null) {
      return _resolveSelection();
    }

    for (final item in _itemsForAudience(_audience)) {
      final matches = switch (request.target!) {
        UserManagementTarget.user => _normalizedId(item['id']) == targetId,
        UserManagementTarget.customer =>
          _normalizedId(item['customerId']) == targetId ||
              _normalizedId(item['id']) == targetId,
        UserManagementTarget.invitation =>
          _normalizedId(item['invitationId'] ?? item['id']) == targetId,
        UserManagementTarget.employee =>
          _employeeStateForStaff(item)?.employeeId == targetId ||
              _invitationEmployeeId(item) == targetId,
      };
      if (matches) return item;
    }
    return null;
  }

  List<Map<String, dynamic>> _itemsForAudience(_IdentityAudience audience) {
    switch (audience) {
      case _IdentityAudience.staff:
        return _staffUsers;
      case _IdentityAudience.customers:
        return _customerAccounts;
      case _IdentityAudience.invitations:
        return _invitations;
    }
  }

  List<Map<String, dynamic>> _visibleItemsForAudience(
    _IdentityAudience audience,
  ) {
    final items = _itemsForAudience(audience);
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty || audience == _IdentityAudience.customers) {
      return items;
    }
    return items.where((item) {
      final employee = audience == _IdentityAudience.invitations
          ? _employeeAccessById(_invitationEmployeeId(item))
          : _employeeStateForStaff(item);
      final searchable = <String>[
        item['displayName']?.toString() ?? '',
        item['email']?.toString() ?? '',
        _roleLabel(item['role']),
        employee?.employeeName ?? '',
        employee?.email ?? '',
      ].join(' ').toLowerCase();
      return searchable.contains(query);
    }).toList(growable: false);
  }

  String _identityId(Map<String, dynamic> item) {
    return (item['id'] ?? item['customerId'] ?? item['invitationId'] ?? '')
        .toString();
  }

  String? _normalizedId(dynamic value) {
    final normalized = value?.toString().trim() ?? '';
    return normalized.isEmpty ? null : normalized;
  }

  String? _invitationEmployeeId(Map<String, dynamic> invitation) {
    return _normalizedId(
      invitation['employee_id'] ?? invitation['employeeId'],
    );
  }

  EmployeeAccessState? _employeeAccessById(String? employeeId) {
    if (employeeId == null) return null;
    for (final employee in _employeeAccessStates) {
      if (employee.employeeId == employeeId) return employee;
    }
    return null;
  }

  /// Correo actual de la ficha cuando **no** coincide con el de la invitación;
  /// `null` cuando coinciden o cuando no hay con qué comparar.
  ///
  /// Una invitación es una credencial dirigida a un buzón concreto: su token
  /// ya viaja dentro de un correo enviado. Que editar la ficha del trabajador
  /// no la redirija es correcto y es lo que hacen Workspace, Microsoft 365,
  /// Slack y Okta —redirigirla dejaría vivo el mensaje anterior hacia la
  /// dirección antigua, y aquí el rol invitado puede ser administrador—. El
  /// defecto era otro: esa divergencia no se veía en ninguna parte. El
  /// administrador cambiaba el correo, no pasaba nada visible, y la invitación
  /// seguía apuntando al buzón que acababa de descartar.
  String? _invitationEmailDrift(Map<String, dynamic> invitation) {
    final invitationEmail = invitation['email']?.toString().trim() ?? '';
    if (invitationEmail.isEmpty) return null;
    final employee = _employeeAccessById(_invitationEmployeeId(invitation));
    final employeeEmail = employee?.email?.trim() ?? '';
    if (employeeEmail.isEmpty) return null;
    return employeeEmail.toLowerCase() == invitationEmail.toLowerCase()
        ? null
        : employeeEmail;
  }

  EmployeeAccessState? _employeeStateForStaff(Map<String, dynamic> user) {
    final declaredEmployee =
        _employeeAccessById(_normalizedId(user['employeeId']));
    if (declaredEmployee != null) return declaredEmployee;

    final userId = _normalizedId(user['id']);
    if (userId == null) return null;
    for (final employee in _employeeAccessStates) {
      if (employee.erpUserId == userId) return employee;
    }
    return null;
  }

  Map<String, dynamic>? _pendingInvitationForEmployee(String employeeId) {
    for (final invitation in _invitations) {
      if (_invitationEmployeeId(invitation) == employeeId) return invitation;
    }
    return null;
  }

  String _staffIdentityLabel(String? userId) {
    if (userId == null) return 'otra cuenta ERP';
    for (final user in _staffUsers) {
      if (_normalizedId(user['id']) != userId) continue;
      return _normalizedId(user['displayName']) ??
          _normalizedId(user['email']) ??
          'otra cuenta ERP';
    }
    return 'otra cuenta ERP';
  }

  bool _canSelectEmployee(EmployeeAccessState employee) {
    return employee.canReceiveErpLink &&
        !employee.pendingInvitation &&
        _pendingInvitationForEmployee(employee.employeeId) == null;
  }

  String _employeeStateLabel(EmployeeAccessState employee) {
    if (!employee.isActiveEmployee) return 'Trabajador inactivo';
    if (employee.linkState != EmployeeErpLinkState.workerToErpPending &&
        (employee.pendingInvitation ||
            _pendingInvitationForEmployee(employee.employeeId) != null)) {
      return 'Invitación pendiente';
    }
    return switch (employee.linkState) {
      EmployeeErpLinkState.available => 'Disponible para vincular',
      EmployeeErpLinkState.pendingInvitation => 'Invitación pendiente',
      EmployeeErpLinkState.workerToErpPending =>
        'Worker activo · migración a ERP pendiente',
      EmployeeErpLinkState.erpLinked =>
        'Vinculado a ${_staffIdentityLabel(employee.erpUserId)}',
      EmployeeErpLinkState.workerActive =>
        'Worker Space activo · puede migrarse',
      EmployeeErpLinkState.workerSuspended =>
        'App de trabajadores suspendida · puede migrarse',
      EmployeeErpLinkState.inconsistent => 'Requiere revisión',
    };
  }

  String _employeeStateGuidance(EmployeeAccessState? employee) {
    if (employee == null) {
      return 'El vínculo es opcional. Si seleccionas un trabajador, la invitación quedará reservada para esa ficha y no se escogerá ninguna automáticamente.';
    }
    if (!employee.isActiveEmployee) {
      return 'Este trabajador está inactivo y no puede recibir un nuevo acceso ERP.';
    }
    final pending = _pendingInvitationForEmployee(employee.employeeId);
    if (employee.linkState != EmployeeErpLinkState.workerToErpPending &&
        (employee.pendingInvitation || pending != null)) {
      return 'Ya hay una invitación pendiente para este trabajador (${pending?['email'] ?? 'sin email visible'}). Reenvíala o cancélala desde Invitaciones.';
    }
    return switch (employee.linkState) {
      EmployeeErpLinkState.available =>
        'Disponible. Al aceptar la invitación, esta cuenta ERP quedará vinculada a ${employee.employeeName}.',
      EmployeeErpLinkState.pendingInvitation =>
        'Ya existe una invitación pendiente para este trabajador.',
      EmployeeErpLinkState.workerToErpPending =>
        'Worker Space sigue activo hasta que se acepte la invitación ERP. Puedes reenviarla o cancelarla sin dejar a la persona sin acceso.',
      EmployeeErpLinkState.erpLinked =>
        'Ya está vinculado a ${_staffIdentityLabel(employee.erpUserId)}. Desvincula esa cuenta antes de reasignarlo.',
      EmployeeErpLinkState.workerActive =>
        'Tiene Worker Space activo${employee.workerUsername == null ? '' : ' como ${employee.workerUsername}'}. La invitación no lo cerrará: al aceptarla, el sistema moverá su acceso y sus tareas abiertas a ERP en una sola operación.',
      EmployeeErpLinkState.workerSuspended =>
        'Su acceso independiente a la app de trabajadores está suspendido. Puedes migrarlo explícitamente a una cuenta ERP; el acceso anterior seguirá suspendido.',
      EmployeeErpLinkState.inconsistent =>
        'Los datos de acceso no coinciden. Revisa la ficha antes de crear o cambiar vínculos.',
    };
  }

  String _directEmployeeLinkGuidance(EmployeeAccessState? employee) {
    if (employee == null) {
      return 'Selecciona explícitamente la ficha correcta. El sistema no elegirá un trabajador por nombre o email.';
    }
    if (!employee.isActiveEmployee) {
      return 'Este trabajador está inactivo y no puede recibir un nuevo acceso ERP.';
    }
    final pending = _pendingInvitationForEmployee(employee.employeeId);
    if (employee.linkState != EmployeeErpLinkState.workerToErpPending &&
        (employee.pendingInvitation || pending != null)) {
      return 'Ya existe una invitación pendiente para este trabajador. Reenvíala o cancélala antes de vincular otra cuenta.';
    }
    return switch (employee.linkState) {
      EmployeeErpLinkState.available =>
        'Disponible. Esta cuenta ERP quedará vinculada inmediatamente a ${employee.employeeName}.',
      EmployeeErpLinkState.pendingInvitation =>
        'Ya existe una invitación pendiente para este trabajador.',
      EmployeeErpLinkState.workerToErpPending =>
        'Ya existe una migración a ERP pendiente. Reenvía o cancela esa invitación antes de elegir otra cuenta.',
      EmployeeErpLinkState.erpLinked =>
        'Ya está vinculado a ${_staffIdentityLabel(employee.erpUserId)}.',
      EmployeeErpLinkState.workerActive =>
        'Worker Space está activo. Al confirmar, se cerrarán sus sesiones Worker, se activará esta cuenta ERP y sus tareas abiertas seguirán con la misma persona.',
      EmployeeErpLinkState.workerSuspended =>
        'El acceso independiente de la app está suspendido. Puedes migrarlo explícitamente; ese acceso anterior seguirá suspendido.',
      EmployeeErpLinkState.inconsistent =>
        'Los datos de acceso no coinciden y deben revisarse antes de vincular.',
    };
  }

  void _applyEmployeePrefill({
    required EmployeeAccessState? employee,
    required TextEditingController emailController,
    required TextEditingController nameController,
    required String? previousEmailPrefill,
    required String? previousNamePrefill,
  }) {
    final currentEmail = emailController.text.trim();
    final currentName = nameController.text.trim();
    final canReplaceEmail = currentEmail.isEmpty ||
        (previousEmailPrefill != null &&
            currentEmail == previousEmailPrefill.trim());
    final canReplaceName = currentName.isEmpty ||
        (previousNamePrefill != null &&
            currentName == previousNamePrefill.trim());

    if (canReplaceEmail) {
      emailController.text = employee?.email ?? '';
    }
    if (canReplaceName) {
      nameController.text = employee?.employeeName ?? '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (_accessBlockTitle != null) {
      return Material(
        key: const ValueKey('user-management-access-blocked'),
        color: colorScheme.surfaceContainerLowest,
        child: _buildAccessBlockState(context),
      );
    }
    if (_isLoading) {
      return Material(
        color: colorScheme.surfaceContainerLowest,
        child: const Center(child: BrandedLoading()),
      );
    }
    if (_errorMessage != null) {
      return Material(
        color: colorScheme.surfaceContainerLowest,
        child: _buildErrorState(context),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 900;
        final showingCompactDetail =
            !isDesktop && _compactShowingDetail && _selectedItem != null;
        final horizontalPadding = isDesktop ? 24.0 : 14.0;

        return PopScope(
          canPop: !showingCompactDetail,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && showingCompactDetail) {
              _leaveCompactDetail();
            }
          },
          child: Material(
            color: colorScheme.surfaceContainerLowest,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                isDesktop ? 20 : 12,
                horizontalPadding,
                isDesktop ? 20 : 12,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!showingCompactDetail) ...[
                    _buildHeader(context, isCompact: !isDesktop),
                    const SizedBox(height: 14),
                    _buildNavigationAndSearch(context, isDesktop: isDesktop),
                    const SizedBox(height: 12),
                  ],
                  Expanded(
                    child: _buildWorkspace(
                      context,
                      isDesktop: isDesktop,
                      showingCompactDetail: showingCompactDetail,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildAccessBlockState(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.lock_outline,
                size: 38,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 14),
              Text(
                _accessBlockTitle ?? 'Acceso restringido',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                _accessBlockMessage ?? '',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 18),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Volver'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(48, 48),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, {required bool isCompact}) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final tenantName = _currentTenant?['shop_name']?.toString() ?? 'Empresa';
    final actionLabel = _audience == _IdentityAudience.customers
        ? 'Crear cliente web'
        : 'Invitar equipo';
    final actionIcon = _audience == _IdentityAudience.customers
        ? Icons.person_add_alt_1
        : Icons.outgoing_mail;
    final VoidCallback? action = _isActionRunning
        ? null
        : _audience == _IdentityAudience.customers
            ? () => _showCustomerAccountDialog()
            : _showInviteStaffDialog;

    final heading = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Usuarios y roles',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          '$tenantName · Administra identidades, acceso y vínculos sin salir de esta vista.',
          maxLines: isCompact ? 2 : 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
    final primaryAction = FilledButton.icon(
      key: const ValueKey('user-management-primary-action'),
      onPressed: action,
      icon: Icon(actionIcon, size: 18),
      label: Text(
        actionLabel,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 48),
      ),
    );
    final refreshAction = IconButton(
      tooltip: 'Actualizar usuarios',
      onPressed: _isActionRunning ? null : _loadData,
      icon: const Icon(Icons.refresh),
      constraints: const BoxConstraints.tightFor(width: 48, height: 48),
    );
    final actions = isCompact
        ? Row(
            children: [
              Expanded(child: primaryAction),
              const SizedBox(width: 6),
              refreshAction,
            ],
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              primaryAction,
              const SizedBox(width: 6),
              refreshAction,
            ],
          );

    if (isCompact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          heading,
          const SizedBox(height: 10),
          actions,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: heading),
        const SizedBox(width: 20),
        actions,
      ],
    );
  }

  Widget _buildNavigationAndSearch(
    BuildContext context, {
    required bool isDesktop,
  }) {
    final navigation = _audienceSelector(context);
    final search = _searchField();
    return isDesktop
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(child: navigation),
              const SizedBox(width: 18),
              SizedBox(width: 360, child: search),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              navigation,
              const SizedBox(height: 10),
              search,
            ],
          );
  }

  Widget _buildWorkspace(
    BuildContext context, {
    required bool isDesktop,
    required bool showingCompactDetail,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(isDesktop ? 18 : 14),
        border: isDesktop
            ? Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.55),
              )
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(isDesktop ? 17 : 13),
        child: isDesktop
            ? Row(
                children: [
                  Expanded(
                    flex: 5,
                    child: _buildListPanel(context, compact: false),
                  ),
                  VerticalDivider(
                    width: 1,
                    thickness: 1,
                    color: colorScheme.outlineVariant,
                  ),
                  Expanded(
                    flex: 6,
                    child: _buildDetailPanel(context, compact: false),
                  ),
                ],
              )
            : AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                child: showingCompactDetail
                    ? KeyedSubtree(
                        key: const ValueKey('user-management-compact-detail'),
                        child: _buildDetailPanel(context, compact: true),
                      )
                    : KeyedSubtree(
                        key: const ValueKey('user-management-compact-list'),
                        child: _buildListPanel(context, compact: true),
                      ),
              ),
      ),
    );
  }

  void _showCompactList() {
    setState(() => _compactShowingDetail = false);
  }

  void _leaveCompactDetail() {
    if (_openRequest?.target == null) {
      _showCompactList();
      return;
    }
    setState(() => _compactShowingDetail = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).maybePop();
    });
  }

  Widget _audienceSelector(BuildContext context) {
    return Row(
      children: [
        for (final audience in _IdentityAudience.values)
          Expanded(
            child: _audienceButton(
              context,
              audience: audience,
              label: switch (audience) {
                _IdentityAudience.staff => 'Equipo',
                _IdentityAudience.customers => 'Clientes web',
                _IdentityAudience.invitations => 'Invitaciones',
              },
              count: _itemsForAudience(audience).length,
            ),
          ),
      ],
    );
  }

  Widget _audienceButton(
    BuildContext context, {
    required _IdentityAudience audience,
    required String label,
    required int count,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final selected = _audience == audience;
    return Semantics(
      button: true,
      selected: selected,
      label: '$label, $count',
      child: InkWell(
        key: ValueKey('user-audience-${audience.name}'),
        onTap: () => _selectAudience(audience),
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 9),
          decoration: BoxDecoration(
            color: selected
                ? colorScheme.secondaryContainer.withValues(alpha: 0.34)
                : null,
            border: Border(
              bottom: BorderSide(
                color: selected
                    ? colorScheme.primary
                    : colorScheme.outlineVariant.withValues(alpha: 0.38),
                width: selected ? 2 : 1,
              ),
            ),
          ),
          child: Text(
            '$label ($count)',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: selected
                      ? colorScheme.onSecondaryContainer
                      : colorScheme.onSurfaceVariant,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                ),
          ),
        ),
      ),
    );
  }

  void _selectAudience(_IdentityAudience audience) {
    if (_audience == audience) return;
    _searchDebounce?.cancel();
    setState(() {
      _openRequest = null;
      _requestedTargetUnavailable = false;
      _audience = audience;
      _compactShowingDetail = false;
      _compactSelectionWasExplicit = false;
      _selectedItem = _resolveSelection();
    });
    if (audience == _IdentityAudience.customers) {
      _loadData(silent: true);
    }
  }

  Widget _searchField() {
    return TextField(
      key: const ValueKey('user-management-search'),
      controller: _searchController,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        isDense: true,
        prefixIcon: const Icon(Icons.search),
        suffixIcon: _searchController.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Limpiar búsqueda',
                onPressed: _searchController.clear,
                icon: const Icon(Icons.close),
              ),
        hintText: switch (_audience) {
          _IdentityAudience.staff => 'Buscar persona, email o rol',
          _IdentityAudience.customers =>
            'Buscar cliente por nombre, email o teléfono',
          _IdentityAudience.invitations => 'Buscar invitación, email o rol',
        },
        border: const OutlineInputBorder(),
      ),
    );
  }

  Widget _buildListPanel(BuildContext context, {required bool compact}) {
    final items = _visibleItemsForAudience(_audience);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final hasQuery = _searchController.text.trim().isNotEmpty;
    final title = switch (_audience) {
      _IdentityAudience.staff => 'Cuentas internas',
      _IdentityAudience.customers => 'Clientes CRM y cuentas web',
      _IdentityAudience.invitations => 'Invitaciones pendientes',
    };
    final subtitle = switch (_audience) {
      _IdentityAudience.staff => 'Usuarios que pueden entrar al ERP.',
      _IdentityAudience.customers => _searchController.text.trim().isEmpty
          ? 'Se muestran clientes CRM con login web y cuentas web sin ficha CRM. Busca para incluir clientes CRM sin login.'
          : 'Resultados de clientes CRM con login web, solo CRM y solo web sin ficha.',
      _IdentityAudience.invitations =>
        'Invitaciones de equipo todavía no aceptadas.',
    };

    return Column(
      key: const ValueKey('user-management-list-pane'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            compact ? 14 : 18,
            compact ? 14 : 18,
            compact ? 14 : 18,
            12,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    hasQuery
                        ? '${items.length} resultado${items.length == 1 ? '' : 's'}'
                        : '${items.length}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        Divider(
          height: 1,
          color: colorScheme.outlineVariant.withValues(alpha: 0.38),
        ),
        if (_requestedTargetUnavailable) ...[
          _requestedTargetUnavailableNotice(context),
          Divider(
            height: 1,
            color: colorScheme.outlineVariant.withValues(alpha: 0.38),
          ),
        ],
        Expanded(
          child: items.isEmpty
              ? _emptyState(
                  context,
                  filtered: hasQuery,
                  message: hasQuery
                      ? 'No hay resultados para esta búsqueda.'
                      : 'No hay registros para esta vista.',
                )
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: Scrollbar(
                    controller: _listScrollController,
                    thumbVisibility: !compact,
                    child: ListView.separated(
                      key: const PageStorageKey('user-management-list'),
                      controller: _listScrollController,
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: EdgeInsets.zero,
                      itemCount: items.length,
                      separatorBuilder: (_, __) => Divider(
                        height: 1,
                        indent: compact ? 14 : 18,
                        endIndent: compact ? 14 : 18,
                        color:
                            colorScheme.outlineVariant.withValues(alpha: 0.38),
                      ),
                      itemBuilder: (context, index) => _identityRow(
                        context,
                        items[index],
                        compact: compact,
                      ),
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _identityRow(
    BuildContext context,
    Map<String, dynamic> item, {
    required bool compact,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isSelected = _selectedItem != null &&
        (!compact || _compactSelectionWasExplicit) &&
        _identityId(_selectedItem!) == _identityId(item);
    final copy = _identityRowCopy(item);

    return Semantics(
      selected: isSelected,
      button: true,
      label: '${copy.title}, ${copy.subtitle}, ${copy.meta}',
      child: Material(
        color: isSelected
            ? colorScheme.secondaryContainer.withValues(alpha: 0.28)
            : colorScheme.surface,
        child: InkWell(
          key: ValueKey('user-row-${_identityId(item)}'),
          onTap: () => _selectIdentity(item, compact: compact),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 68),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 14 : 18,
                vertical: 11,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 3,
                    height: 42,
                    decoration: BoxDecoration(
                      color: isSelected ? colorScheme.primary : null,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          copy.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          copy.subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          copy.meta,
                          maxLines: copy.exception == null ? 1 : 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: copy.exception == null
                                ? colorScheme.onSurfaceVariant
                                : colorScheme.error,
                            fontWeight: copy.exception == null
                                ? FontWeight.w600
                                : FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  _IdentityRowCopy _identityRowCopy(Map<String, dynamic> item) {
    if (_audience == _IdentityAudience.invitations) {
      final employee = _employeeAccessById(_invitationEmployeeId(item));
      final role = _roleLabel(item['role']);
      final expiry = _formatDate(item['expires_at']);
      final exception = _invitationEmailDrift(item) == null
          ? null
          : 'Destino distinto al de la ficha';
      return _IdentityRowCopy(
        title: item['email']?.toString() ?? 'Invitación',
        subtitle: employee?.employeeName ?? 'Sin trabajador vinculado',
        meta: exception ??
            (employee == null
                ? '$role · vence $expiry'
                : '$role · invitación pendiente'),
        exception: exception,
      );
    }

    final title = item['displayName']?.toString() ??
        item['email']?.toString() ??
        'Usuario';
    final email = item['email']?.toString() ?? 'Sin email';
    final isActive = item['isActive'] != false;
    final emailConfirmed = item['emailConfirmed'] == true;
    if (_audience == _IdentityAudience.customers) {
      final relationship = _customerRelationshipLabel(item);
      final exception = item['isWebsiteOnlyAuth'] == true
          ? 'Cuenta web sin ficha CRM'
          : !emailConfirmed && item['hasAuth'] == true
              ? 'Correo pendiente de verificar'
              : !isActive
                  ? 'Acceso restringido'
                  : null;
      return _IdentityRowCopy(
        title: title,
        subtitle: email,
        meta: exception ??
            '$relationship · ${isActive ? 'Activo' : 'Restringido'}',
        exception: exception,
      );
    }

    final employee = _employeeStateForStaff(item);
    final isPrincipalOwner = item['isPrincipalOwner'] == true;
    final userId = _normalizedId(item['id']);
    final declaredEmployeeId = _normalizedId(item['employeeId']);
    final linkNeedsReview = declaredEmployeeId != null
        ? employee == null ||
            employee.linkState != EmployeeErpLinkState.erpLinked ||
            employee.erpUserId != userId
        : employee?.erpUserId == userId;
    final exception = linkNeedsReview
        ? 'Vínculo laboral requiere revisión'
        : !isActive
            ? 'Acceso restringido'
            : !emailConfirmed
                ? 'Correo pendiente de verificar'
                : null;
    return _IdentityRowCopy(
      title: title,
      subtitle: email,
      meta: isPrincipalOwner
          ? 'Identidad de Viñabike · no representa a un trabajador'
          : exception ??
              '${_roleLabel(item['role'])} · ${employee?.employeeName ?? 'Sin ficha laboral'}',
      exception: exception,
    );
  }

  void _selectIdentity(
    Map<String, dynamic> item, {
    required bool compact,
  }) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _openRequest = null;
      _requestedTargetUnavailable = false;
      _selectedItem = item;
      if (compact) {
        _compactSelectionWasExplicit = true;
        _compactShowingDetail = true;
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_detailScrollController.hasClients) {
        _detailScrollController.jumpTo(0);
      }
    });
  }

  String _customerRelationshipLabel(Map<String, dynamic> item) {
    if (item['isStaffAuthUser'] == true) return 'CRM + login ERP';
    if (item['isWebsiteOnlyAuth'] == true) return 'Solo web, sin ficha CRM';
    if (item['hasAuth'] == true) return 'CRM + cuenta web';
    return 'Solo CRM';
  }

  Widget _buildDetailPanel(
    BuildContext context, {
    required bool compact,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final item = _selectedItem;
    if (item == null) {
      return _emptyState(
        context,
        message: _requestedTargetUnavailable
            ? 'La cuenta solicitada ya no está disponible en esta empresa.'
            : 'Selecciona una cuenta para revisar su acceso.',
      );
    }

    final content = switch (_audience) {
      _IdentityAudience.customers => _customerDetail(context, item),
      _IdentityAudience.invitations => _invitationDetail(context, item),
      _IdentityAudience.staff => _staffDetail(context, item),
    };
    return Column(
      key: const ValueKey('user-management-detail-pane'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (compact) ...[
          Material(
            color: colorScheme.surfaceContainerLow,
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const ValueKey('user-management-compact-back'),
                onPressed: _leaveCompactDetail,
                icon: const Icon(Icons.arrow_back),
                label: Text(
                  _openRequest?.target == null ? 'Volver a usuarios' : 'Volver',
                ),
                style: TextButton.styleFrom(
                  minimumSize: const Size(48, 48),
                ),
              ),
            ),
          ),
          Divider(
            height: 1,
            color: colorScheme.outlineVariant.withValues(alpha: 0.38),
          ),
        ],
        Expanded(
          child: Scrollbar(
            controller: _detailScrollController,
            thumbVisibility: !compact,
            child: SingleChildScrollView(
              controller: _detailScrollController,
              padding: EdgeInsets.all(compact ? 14 : 20),
              child: content,
            ),
          ),
        ),
      ],
    );
  }

  Widget _staffDetail(BuildContext context, Map<String, dynamic> user) {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    final isSelf = user['id'] == currentUserId;
    final isPrincipalOwner = user['isPrincipalOwner'] == true;
    final isActive = user['isActive'] != false;
    final profileActive = user['profileActive'] == true;
    final email = user['email']?.toString() ?? '';
    final displayName = user['displayName']?.toString() ?? email;
    final userId = user['id']?.toString() ?? '';
    final declaredEmployeeId = user['employeeId']?.toString();
    final employeeState = _employeeStateForStaff(user);
    final hasHealthyEmployeeLink = employeeState != null &&
        employeeState.linkState == EmployeeErpLinkState.erpLinked &&
        employeeState.erpUserId == userId &&
        declaredEmployeeId == employeeState.employeeId;
    final hasDeclaredEmployeeLink =
        declaredEmployeeId != null && declaredEmployeeId.isNotEmpty;
    final employeeLinkNeedsReview = !isPrincipalOwner && hasDeclaredEmployeeLink
        ? !hasHealthyEmployeeLink
        : !isPrincipalOwner && employeeState?.erpUserId == userId;

    final hasWorkerTransitionCandidate = _employeeAccessStates.any(
      (employee) =>
          employee.isActiveEmployee &&
          employee.linkState == EmployeeErpLinkState.workerActive &&
          _canSelectEmployee(employee),
    );
    final canChangeEmployee = !isPrincipalOwner &&
        (canChangeEmployeeLink(
              actionRunning: _isActionRunning,
              employeeLinkNeedsReview: employeeLinkNeedsReview,
              profileActive: profileActive,
              hasHealthyEmployeeLink: hasHealthyEmployeeLink,
            ) ||
            (!_isActionRunning &&
                !employeeLinkNeedsReview &&
                !profileActive &&
                hasWorkerTransitionCandidate));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _detailHeader(
          context,
          title: displayName,
          subtitle: isPrincipalOwner
              ? 'Identidad de la empresa · Owner'
              : 'Usuario interno · ${_roleLabel(user['role'])}',
          status: isActive ? 'Acceso activo' : 'Acceso restringido',
          statusIsException: !isActive,
        ),
        const SizedBox(height: 22),
        _detailSection(
          context,
          title: 'Identidad',
          description:
              'Datos usados para reconocer esta cuenta dentro del ERP.',
          children: [
            _detailLine('Nombre visible', displayName),
            _detailLine('Email', email),
            _detailLine(
              'Email verificado',
              user['emailConfirmed'] == true ? 'Sí' : 'No',
            ),
            _detailLine('Último acceso', _formatDate(user['lastSignInAt'])),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _isActionRunning
                    ? null
                    : () => _showEditStaffIdentityDialog(user),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Editar nombre visible'),
                style: TextButton.styleFrom(
                  minimumSize: const Size(48, 48),
                ),
              ),
            ),
          ],
        ),
        _detailSection(
          context,
          title: 'Vínculo laboral',
          description: isPrincipalOwner
              ? 'Esta identidad representa a Viñabike completa, no a una persona de la nómina.'
              : 'Relaciona esta cuenta con la ficha correcta del trabajador.',
          children: [
            _detailLine(
              isPrincipalOwner ? 'Tipo de identidad' : 'Trabajador',
              isPrincipalOwner
                  ? 'Empresa (owner)'
                  : employeeLinkNeedsReview
                      ? 'Requiere revisión'
                      : hasHealthyEmployeeLink
                          ? employeeState.employeeName
                          : 'No vinculado',
            ),
            if (isPrincipalOwner) ...[
              const SizedBox(height: 10),
              _noteBox(
                context,
                icon: Icons.business_outlined,
                text:
                    'No se puede vincular a un trabajador ni mover a Worker Space. Los trabajadores usan identidades separadas para que los cambios de acceso nunca alteren la cuenta principal de la empresa.',
              ),
            ] else ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: !canChangeEmployee
                      ? null
                      : hasHealthyEmployeeLink
                          ? () => _confirmUnlinkEmployee(
                                user: user,
                                employee: employeeState,
                              )
                          : () => _showLinkEmployeeDialog(user),
                  icon: Icon(
                    hasHealthyEmployeeLink
                        ? Icons.link_off_outlined
                        : Icons.add_link_outlined,
                    size: 18,
                  ),
                  label: Text(
                    hasHealthyEmployeeLink
                        ? 'Desvincular trabajador'
                        : 'Vincular trabajador',
                  ),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(48, 48),
                  ),
                ),
              ),
            ],
            if (!isPrincipalOwner && hasHealthyEmployeeLink && !isSelf) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.tonalIcon(
                  key: const ValueKey('staff-switch-to-worker-action'),
                  onPressed: _isActionRunning
                      ? null
                      : () => _showSwitchToWorkerDialog(
                            user: user,
                            employee: employeeState,
                          ),
                  icon: const Icon(Icons.phone_iphone_outlined, size: 18),
                  label: const Text('Mover a Worker Space'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(48, 48),
                  ),
                ),
              ),
            ],
            if (employeeLinkNeedsReview) ...[
              const SizedBox(height: 10),
              _noteBox(
                context,
                icon: Icons.warning_amber_rounded,
                text:
                    'El perfil ERP y la ficha laboral no describen el mismo vínculo. Los cambios quedan bloqueados hasta revisar esa inconsistencia.',
              ),
            ] else if (!profileActive) ...[
              const SizedBox(height: 10),
              _noteBox(
                context,
                icon: Icons.link_off_outlined,
                text: hasHealthyEmployeeLink
                    ? 'La cuenta está suspendida, pero el vínculo exacto se conserva para auditoría y puede desvincularse explícitamente.'
                    : hasWorkerTransitionCandidate
                        ? 'Esta cuenta ERP está suspendida. Puedes elegir un trabajador con Worker Space activo para mover su acceso y sus tareas a esta cuenta en una sola operación.'
                        : 'Restaura primero el acceso si necesitas vincular esta cuenta a un trabajador.',
              ),
            ],
          ],
        ),
        _detailSection(
          context,
          title: 'Acceso al ERP',
          description:
              'Rol, permisos y acciones de recuperación de esta cuenta.',
          children: [
            _detailLine('Estado', isActive ? 'Activo' : 'Restringido'),
            const SizedBox(height: 10),
            _primaryDetailAction(
              context,
              icon: isActive ? Icons.tune : Icons.check_circle_outline,
              label: isActive ? 'Editar rol y permisos' : 'Restaurar acceso',
              onPressed: _isActionRunning || isSelf || isPrincipalOwner
                  ? null
                  : isActive
                      ? () => _showEditStaffDialog(user)
                      : () => _runAction(
                            'Usuario activado',
                            () => _userService.toggleUserStatus(
                              user['id'].toString(),
                              true,
                            ),
                          ),
            ),
            if (isSelf) ...[
              const SizedBox(height: 10),
              _noteBox(
                context,
                icon: Icons.shield_outlined,
                text:
                    'Tu propio rol, permisos y estado son de solo lectura. Otro administrador autorizado debe cambiarlos.',
              ),
            ],
            const SizedBox(height: 8),
            _actionDisclosure(
              context,
              title: 'Más acciones de acceso',
              children: [
                if (!isActive && !isSelf && !isPrincipalOwner)
                  _secondaryAction(
                    context,
                    icon: Icons.tune,
                    label: 'Editar rol y permisos',
                    onTap: _isActionRunning
                        ? null
                        : () => _showEditStaffDialog(user),
                  ),
                _secondaryAction(
                  context,
                  icon: Icons.lock_reset,
                  label: 'Enviar acceso seguro',
                  supportingText:
                      'Envía un correo para recuperar la contraseña.',
                  onTap: _isActionRunning || email.isEmpty
                      ? null
                      : () => _sendPasswordReset(email),
                ),
                if (user['emailConfirmed'] != true)
                  _secondaryAction(
                    context,
                    icon: Icons.outgoing_mail,
                    label: 'Reenviar acceso',
                    supportingText:
                        'Reenvía el correo de activación pendiente.',
                    onTap: _isActionRunning || email.isEmpty
                        ? null
                        : () => _runAction(
                              'Correo de acceso seguro enviado',
                              () => _userService.sendPasswordReset(email),
                            ),
                  ),
                if (isActive && !isSelf && !isPrincipalOwner)
                  _secondaryAction(
                    context,
                    icon: Icons.block_outlined,
                    label: 'Restringir acceso',
                    supportingText:
                        'Impide el ingreso sin eliminar la identidad.',
                    onTap: _isActionRunning
                        ? null
                        : () => _runAction(
                              'Usuario restringido',
                              () => _userService.toggleUserStatus(
                                user['id'].toString(),
                                false,
                              ),
                            ),
                  ),
              ],
            ),
            _permissionsPreview(context, user['permissions']),
          ],
        ),
        if (!isSelf && !isPrincipalOwner)
          _dangerAction(
            context,
            label: 'Dar de baja cuenta interna',
            onPressed: _isActionRunning
                ? null
                : () => _confirmAccountRemoval(
                      title: 'Dar de baja cuenta interna',
                      message:
                          'Se retirará el acceso ERP de $email. Si existe trazabilidad de mensajería, la identidad y su autoría se conservarán desactivadas para auditoría.',
                      confirmLabel: 'Procesar baja',
                      action: () =>
                          _userService.deleteUser(user['id'].toString()),
                    ),
          ),
      ],
    );
  }

  Widget _customerDetail(BuildContext context, Map<String, dynamic> customer) {
    final hasAuth = customer['hasAuth'] == true;
    final hasCustomerProfile = customer['hasCustomerProfile'] != false;
    final isWebsiteOnlyAuth = customer['isWebsiteOnlyAuth'] == true;
    final isSharedStaffAccount = customer['isStaffAuthUser'] == true;
    final isActive = customer['isActive'] != false;
    final email = customer['email']?.toString() ?? '';
    final customerId = customer['customerId']?.toString() ?? '';
    final authUserId = customer['authUserId']?.toString();

    final title = customer['displayName']?.toString() ?? email;
    final relationshipDescription = isWebsiteOnlyAuth
        ? 'Cuenta web sin ficha cliente CRM'
        : isSharedStaffAccount
            ? 'Cliente CRM vinculado a un usuario interno ERP'
            : hasAuth
                ? 'Cliente CRM con cuenta web'
                : 'Cliente CRM sin cuenta web';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _detailHeader(
          context,
          title: title,
          subtitle: relationshipDescription,
          status: !hasAuth
              ? 'Sin cuenta web'
              : isActive
                  ? _customerRelationshipLabel(customer)
                  : 'Acceso restringido',
          statusIsException: (hasAuth && !isActive) || isWebsiteOnlyAuth,
        ),
        const SizedBox(height: 22),
        _detailSection(
          context,
          title: 'Identidad del cliente',
          description:
              'La ficha CRM y el login web se conservan como recursos distintos.',
          children: [
            _detailLine('Email', email.isEmpty ? 'Sin email' : email),
            _detailLine(
              'Teléfono',
              customer['phone']?.toString() ?? 'No registrado',
            ),
            _detailLine('Relación', _customerRelationshipLabel(customer)),
            _detailLine('Ficha CRM', hasCustomerProfile ? 'Sí' : 'No'),
            _detailLine('Cuenta web', hasAuth ? 'Sí' : 'No'),
            if (isSharedStaffAccount)
              _detailLine('Tipo de login', 'Compartido con equipo ERP'),
          ],
        ),
        _detailSection(
          context,
          title: 'Acceso al sitio',
          description:
              'Verificación, recuperación y estado del acceso del cliente.',
          children: [
            _detailLine(
              'Estado',
              !hasAuth
                  ? 'Sin cuenta web'
                  : isActive
                      ? 'Activo'
                      : 'Restringido',
            ),
            _detailLine(
              'Email verificado',
              hasAuth
                  ? (customer['emailConfirmed'] == true ? 'Sí' : 'No')
                  : 'No aplica',
            ),
            _detailLine(
              'Último acceso',
              hasAuth ? _formatDate(customer['lastSignInAt']) : 'No aplica',
            ),
            const SizedBox(height: 10),
            _primaryDetailAction(
              context,
              icon: isWebsiteOnlyAuth
                  ? Icons.add_link_outlined
                  : hasAuth
                      ? Icons.manage_accounts_outlined
                      : Icons.person_add_alt_1_outlined,
              label: isWebsiteOnlyAuth
                  ? 'Crear ficha CRM'
                  : hasAuth
                      ? 'Revisar vínculo'
                      : 'Crear cuenta web',
              onPressed: _isActionRunning || isSharedStaffAccount
                  ? null
                  : () => _showCustomerAccountDialog(customer: customer),
            ),
            if (hasAuth) ...[
              const SizedBox(height: 8),
              _actionDisclosure(
                context,
                title: 'Más acciones de acceso',
                children: [
                  if (hasAuth)
                    _secondaryAction(
                      context,
                      icon: Icons.outgoing_mail,
                      label: 'Reenviar verificación',
                      onTap: _isActionRunning ||
                              !hasCustomerProfile ||
                              email.isEmpty ||
                              isSharedStaffAccount
                          ? null
                          : () => _runAction(
                                'Verificación reenviada',
                                () => _userService.resendCustomerVerification(
                                  customerId: customerId,
                                  email: email,
                                ),
                              ),
                    ),
                  _secondaryAction(
                    context,
                    icon: Icons.lock_reset,
                    label: 'Enviar acceso seguro',
                    supportingText:
                        'Envía un correo para recuperar la contraseña.',
                    onTap: _isActionRunning ||
                            email.isEmpty ||
                            isSharedStaffAccount
                        ? null
                        : () => _sendPasswordReset(email),
                  ),
                  if (hasCustomerProfile)
                    _secondaryAction(
                      context,
                      icon: isActive
                          ? Icons.block_outlined
                          : Icons.check_circle_outline,
                      label: isActive ? 'Limitar acceso' : 'Restaurar acceso',
                      supportingText: isActive
                          ? 'Restringe el portal sin borrar historial.'
                          : 'Habilita nuevamente el acceso del cliente.',
                      onTap: _isActionRunning || isSharedStaffAccount
                          ? null
                          : () => _runAction(
                                isActive
                                    ? 'Cliente restringido'
                                    : 'Cliente activado',
                                () => _userService.setCustomerAccess(
                                  customerId: customerId,
                                  isActive: !isActive,
                                ),
                              ),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 10),
            _noteBox(
              context,
              icon: Icons.info_outline,
              text: isSharedStaffAccount
                  ? 'Este cliente usa un login interno ERP. Gestiona contraseña, verificación y restricciones desde Equipo para no bloquear al personal.'
                  : isWebsiteOnlyAuth
                      ? 'Crea la ficha CRM para vincular historial, bicicletas, pedidos y soporte a este login.'
                      : hasAuth
                          ? 'Este acceso queda limitado al portal público y a los datos del propio cliente.'
                          : 'Crea una cuenta web solo cuando el cliente necesite ingresar al portal.',
            ),
          ],
        ),
        if (hasAuth && authUserId != null)
          _dangerAction(
            context,
            label: 'Dar de baja cuenta web',
            onPressed: _isActionRunning
                ? null
                : () => _confirmAccountRemoval(
                      title: 'Dar de baja cuenta web',
                      message: isWebsiteOnlyAuth
                          ? 'Se retirará el acceso web. Si existe trazabilidad de mensajería, la identidad se conservará desactivada para auditoría.'
                          : isSharedStaffAccount
                              ? 'Esto solo desvincula este cliente del login interno ERP. No elimina ni restringe el usuario del equipo.'
                              : 'Se retirará el acceso web de esta tienda y se conservarán la identidad global, la ficha CRM y su historial.',
                      confirmLabel: 'Procesar baja',
                      action: () => isWebsiteOnlyAuth
                          ? _userService.deleteWebsiteAuthAccount(
                              authUserId: authUserId,
                            )
                          : _userService.deleteCustomerAccount(
                              customerId: customerId,
                            ),
                    ),
          ),
      ],
    );
  }

  Widget _invitationDetail(
      BuildContext context, Map<String, dynamic> invitation) {
    final email = invitation['email']?.toString() ?? '';
    final invitationId = invitation['id']?.toString() ?? '';
    final invitationEmployeeId = _invitationEmployeeId(invitation);
    final invitationEmployee = _employeeAccessById(invitationEmployeeId);
    final driftEmail = _invitationEmailDrift(invitation);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _detailHeader(
          context,
          title: email,
          subtitle: 'Invitación de equipo · ${_roleLabel(invitation['role'])}',
          status: 'Pendiente',
        ),
        // E-04 `VbNotice`. La guía lo quiere anclado al contenido que explica:
        // la dirección vive en el encabezado, así que el aviso va justo debajo.
        // Un solo banner por superficie y con los datos reales dentro.
        if (driftEmail != null) ...[
          const SizedBox(height: 14),
          VbNotice(
            key: const ValueKey('invitation-email-drift-notice'),
            tone: VbNoticeTone.warning,
            title: 'Destino distinto al de la ficha',
            // El correo de la invitación ya está en el encabezado: repetirlo
            // acá sólo alarga el aviso. Falta el otro dato y la salida.
            body: 'La ficha de '
                '${invitationEmployee?.employeeName ?? 'este trabajador'} '
                'usa $driftEmail. Una invitación enviada no cambia de '
                'destino: cancela y vuelve a invitar.',
          ),
        ],
        if (invitationEmployee?.linkState ==
            EmployeeErpLinkState.workerToErpPending) ...[
          const SizedBox(height: 14),
          const VbNotice(
            key: ValueKey('worker-to-erp-pending-notice'),
            tone: VbNoticeTone.info,
            title: 'Cambio a ERP pendiente',
            body:
                'Worker Space sigue activo hasta que la persona acepte este correo. Al aceptar, sus sesiones Worker se cerrarán y sus tareas abiertas pasarán a la cuenta ERP.',
          ),
        ],
        const SizedBox(height: 22),
        _detailSection(
          context,
          title: 'Destino y vigencia',
          children: [
            _detailLine(
              'Trabajador',
              invitationEmployee?.employeeName ??
                  (invitationEmployeeId == null
                      ? 'Sin vínculo'
                      : 'Vínculo requiere revisión'),
            ),
            _detailLine('Expira', _formatDate(invitation['expires_at'])),
            _detailLine('Creada', _formatDate(invitation['created_at'])),
          ],
        ),
        _detailSection(
          context,
          title: 'Acceso propuesto',
          description:
              'La persona recibirá este rol y estos permisos al aceptar.',
          children: [
            _detailLine('Rol', _roleLabel(invitation['role'])),
            const SizedBox(height: 10),
            _primaryDetailAction(
              context,
              icon: Icons.outgoing_mail,
              label: 'Reenviar invitación',
              onPressed: _isActionRunning
                  ? null
                  : () => _runAction(
                        'Invitación reenviada',
                        () =>
                            _userService.resendInternalInvitation(invitationId),
                      ),
            ),
            _permissionsPreview(context, invitation['permissions']),
          ],
        ),
        _dangerAction(
          context,
          label: 'Cancelar invitación',
          onPressed: _isActionRunning
              ? null
              : () => _confirmDanger(
                    title: 'Cancelar invitación',
                    message: 'La invitación a $email dejará de ser válida.',
                    confirmLabel: 'Cancelar invitación',
                    action: () =>
                        _userService.cancelInternalInvitation(invitationId),
                  ),
        ),
      ],
    );
  }

  Widget _detailHeader(
    BuildContext context, {
    required String title,
    required String subtitle,
    required String status,
    bool statusIsException = false,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final accent = statusIsException ? colorScheme.error : colorScheme.primary;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 16, 14),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          accent.withValues(alpha: 0.055),
          colorScheme.surfaceContainerLow,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 3,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        statusIsException
                            ? Icons.warning_amber_rounded
                            : Icons.check_circle_outline,
                        size: 16,
                        color: accent,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          status,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailSection(
    BuildContext context, {
    required String title,
    String? description,
    required List<Widget> children,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.55),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          if (description != null) ...[
            const SizedBox(height: 3),
            Text(
              description,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _detailLine(String label, String value) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final labelWidget = Text(
      label,
      style: theme.textTheme.labelMedium?.copyWith(
        color: colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w700,
      ),
    );
    final valueWidget = SelectableText(
      value,
      style: theme.textTheme.bodyMedium?.copyWith(
        fontWeight: FontWeight.w600,
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final stack = constraints.maxWidth < 480;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: stack
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    labelWidget,
                    const SizedBox(height: 3),
                    valueWidget,
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 150, child: labelWidget),
                    const SizedBox(width: 12),
                    Expanded(child: valueWidget),
                  ],
                ),
        );
      },
    );
  }

  Widget _primaryDetailAction(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) => Align(
        alignment: Alignment.centerLeft,
        child: SizedBox(
          width: constraints.maxWidth < 480 ? double.infinity : null,
          child: FilledButton.icon(
            onPressed: onPressed,
            icon: Icon(icon, size: 18),
            label: Text(label),
            style: FilledButton.styleFrom(
              minimumSize: const Size(48, 48),
            ),
          ),
        ),
      ),
    );
  }

  Widget _actionDisclosure(
    BuildContext context, {
    required String title,
    required List<Widget> children,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Theme(
      data: Theme.of(context).copyWith(
        dividerColor: colorScheme.outlineVariant,
      ),
      child: ExpansionTile(
        key: ValueKey('user-management-disclosure-$title'),
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 4),
        minTileHeight: 48,
        title: Text(
          title,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        children: children,
      ),
    );
  }

  Widget _secondaryAction(
    BuildContext context, {
    required IconData icon,
    required String label,
    String? supportingText,
    required VoidCallback? onTap,
  }) {
    return ListTile(
      minTileHeight: 48,
      contentPadding: EdgeInsets.zero,
      enabled: onTap != null,
      leading: Icon(icon, size: 20),
      title: Text(label),
      subtitle: supportingText == null ? null : Text(supportingText),
      trailing: const Icon(Icons.chevron_right, size: 20),
      onTap: onTap,
    );
  }

  Widget _dangerAction(
    BuildContext context, {
    required String label,
    required VoidCallback? onPressed,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.only(top: 14),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.45),
          ),
        ),
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: onPressed,
          icon: const Icon(Icons.delete_outline, size: 18),
          label: Text(label),
          style: TextButton.styleFrom(
            foregroundColor: colorScheme.error,
            minimumSize: const Size(48, 48),
          ),
        ),
      ),
    );
  }

  Widget _permissionsPreview(BuildContext context, dynamic permissionsData) {
    final permissions =
        Map<String, dynamic>.from(permissionsData as Map? ?? {});
    final enabledCount = _permissionOptions
        .where((option) => permissions[option.key] == true)
        .length;
    final colorScheme = Theme.of(context).colorScheme;
    return Theme(
      data: Theme.of(context).copyWith(
        dividerColor: colorScheme.outlineVariant,
      ),
      child: ExpansionTile(
        key: const ValueKey('user-management-permissions-disclosure'),
        tilePadding: EdgeInsets.zero,
        minTileHeight: 48,
        title: const Text('Permisos operativos'),
        subtitle: Text(
          '$enabledCount de ${_permissionOptions.length} habilitados',
        ),
        children: [
          for (final option in _permissionOptions)
            Builder(
              builder: (context) {
                final enabled = permissions[option.key] == true;
                return ListTile(
                  minTileHeight: 48,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    enabled
                        ? Icons.check_circle_outline
                        : Icons.remove_circle_outline,
                    color: enabled
                        ? colorScheme.primary
                        : colorScheme.onSurfaceVariant,
                    size: 20,
                  ),
                  title: Text(option.label),
                  trailing: Text(enabled ? 'Permitido' : 'Sin acceso'),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _noteBox(
    BuildContext context, {
    required IconData icon,
    required String text,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  Widget _requestedTargetUnavailableNotice(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      key: const ValueKey('user-management-request-unavailable'),
      color: colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.only(left: 14),
        child: Row(
          children: [
            Icon(
              Icons.info_outline,
              size: 18,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'La cuenta solicitada ya no está disponible. Puedes elegir otra.',
              ),
            ),
            IconButton(
              tooltip: 'Cerrar aviso',
              onPressed: () {
                setState(() {
                  _openRequest = null;
                  _requestedTargetUnavailable = false;
                  _selectedItem = _resolveSelection();
                });
              },
              constraints: const BoxConstraints.tightFor(width: 48, height: 48),
              icon: const Icon(Icons.close),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState(
    BuildContext context, {
    String? message,
    bool filtered = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.manage_search,
              size: 36,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 10),
            Text(
              message ?? 'No hay registros para esta vista.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
            ),
            if (filtered) ...[
              const SizedBox(height: 8),
              TextButton(
                key: const ValueKey('user-management-clear-search'),
                onPressed: _searchController.clear,
                child: const Text('Limpiar búsqueda'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 520),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                color: colorScheme.error,
                size: 38,
              ),
              const SizedBox(height: 12),
              Text(
                'No se pudo cargar la consola de usuarios',
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(_errorMessage ?? '', textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _loadData,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(48, 48),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showInviteStaffDialog({String? initialEmployeeId}) async {
    final formKey = GlobalKey<FormState>();
    final emailController = TextEditingController();
    final nameController = TextEditingController();
    final emailFocusNode = FocusNode();
    var selectedRole = 'cashier';
    var permissions = _permissionsForRole(selectedRole);
    var selectedEmployeeKey = _noEmployeeSelection;
    EmployeeAccessState? selectedEmployee;
    String? previousEmailPrefill;
    String? previousNamePrefill;
    InvitationIdentityCheck? identityCheck;
    String? identityError;
    String? invitationError;
    var identityCheckVersion = 0;
    String? identityCheckKey;
    Future<InvitationIdentityCheck?>? identityCheckFuture;
    Timer? identityBlurTimer;
    var isCheckingIdentity = false;
    var isSubmitting = false;
    var dialogOpen = true;
    StateSetter? updateDialog;
    final activeEmployees = _employeeAccessStates
        .where((employee) => employee.isActiveEmployee)
        .toList(growable: false);
    final initialEmployee = _employeeAccessById(initialEmployeeId);
    if (initialEmployee != null &&
        initialEmployee.isActiveEmployee &&
        _canSelectEmployee(initialEmployee)) {
      selectedEmployeeKey = initialEmployee.employeeId;
      selectedEmployee = initialEmployee;
      previousEmailPrefill = initialEmployee.email;
      previousNamePrefill = initialEmployee.employeeName;
      emailController.text = initialEmployee.email ?? '';
      nameController.text = initialEmployee.employeeName;
    }

    void clearIdentityCheck() {
      identityCheckVersion += 1;
      identityCheckKey = null;
      identityCheckFuture = null;
      identityBlurTimer?.cancel();
      if (!dialogOpen) return;
      updateDialog?.call(() {
        identityCheck = null;
        identityError = null;
        invitationError = null;
        isCheckingIdentity = false;
      });
    }

    Future<InvitationIdentityCheck?> verifyIdentity({bool force = false}) {
      final email = emailController.text.trim();
      if (AuthInputValidation.validateEmail(email) != null) {
        clearIdentityCheck();
        return Future.value();
      }
      final requestKey =
          '${email.toLowerCase()}|${selectedEmployee?.employeeId ?? ''}|'
          '${selectedEmployee?.linkState == EmployeeErpLinkState.workerActive}';
      final pendingCheck = identityCheckFuture;
      if (pendingCheck != null && identityCheckKey == requestKey) {
        return pendingCheck;
      }
      if (!force && identityCheck != null && identityCheckKey == requestKey) {
        return Future.value(identityCheck);
      }

      final checkVersion = ++identityCheckVersion;
      identityCheckKey = requestKey;
      updateDialog?.call(() {
        isCheckingIdentity = true;
        identityError = null;
        invitationError = null;
      });

      late final Future<InvitationIdentityCheck?> request;
      request = (() async {
        try {
          final result = await _userService.checkInternalInvitationIdentity(
            email: email,
            employeeId: selectedEmployee?.employeeId,
            transitionFromWorker: selectedEmployee?.linkState ==
                EmployeeErpLinkState.workerActive,
          );
          if (!dialogOpen || checkVersion != identityCheckVersion) return null;
          updateDialog?.call(() {
            identityCheck = result;
            identityError = result.eligible
                ? null
                : localizedUserManagementError(result.code);
            isCheckingIdentity = false;
          });
          return result;
        } on UserManagementException catch (error) {
          if (!dialogOpen || checkVersion != identityCheckVersion) return null;
          updateDialog?.call(() {
            identityCheck = null;
            identityError = error.message;
            isCheckingIdentity = false;
          });
          return null;
        } catch (_) {
          if (!dialogOpen || checkVersion != identityCheckVersion) return null;
          updateDialog?.call(() {
            identityCheck = null;
            identityError = localizedUserManagementError(
              'staff_identity_lookup_failed',
            );
            isCheckingIdentity = false;
          });
          return null;
        } finally {
          if (identical(identityCheckFuture, request)) {
            identityCheckFuture = null;
          }
        }
      })();
      identityCheckFuture = request;
      return request;
    }

    void handleEmailFocus() {
      if (emailFocusNode.hasFocus) return;
      identityBlurTimer?.cancel();
      identityBlurTimer = Timer(Duration.zero, () {
        identityBlurTimer = null;
        if (dialogOpen && !emailFocusNode.hasFocus) {
          unawaited(verifyIdentity());
        }
      });
    }

    emailFocusNode.addListener(handleEmailFocus);

    try {
      final invitationSent = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) {
            updateDialog = setDialogState;
            return AlertDialog(
              title: const Text('Invitar usuario interno'),
              content: SizedBox(
                width: 560,
                child: Form(
                  key: formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        DropdownButtonFormField<String>(
                          key: const ValueKey('user-invite-employee-field'),
                          initialValue: selectedEmployeeKey,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Trabajador opcional',
                            prefixIcon: Icon(Icons.badge_outlined),
                          ),
                          items: [
                            const DropdownMenuItem(
                              value: _noEmployeeSelection,
                              child: Text('Sin vincular a trabajador'),
                            ),
                            for (final employee in activeEmployees)
                              DropdownMenuItem(
                                value: employee.employeeId,
                                enabled: _canSelectEmployee(employee),
                                child: Text(
                                  '${employee.employeeName} — ${_employeeStateLabel(employee)}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: (value) {
                            if (value == null) return;
                            final nextEmployee = value == _noEmployeeSelection
                                ? null
                                : _employeeAccessById(value);
                            _applyEmployeePrefill(
                              employee: nextEmployee,
                              emailController: emailController,
                              nameController: nameController,
                              previousEmailPrefill: previousEmailPrefill,
                              previousNamePrefill: previousNamePrefill,
                            );
                            setDialogState(() {
                              selectedEmployeeKey = value;
                              selectedEmployee = nextEmployee;
                              previousEmailPrefill = nextEmployee?.email;
                              previousNamePrefill = nextEmployee?.employeeName;
                            });
                            clearIdentityCheck();
                            unawaited(verifyIdentity());
                          },
                        ),
                        const SizedBox(height: 10),
                        _noteBox(
                          dialogContext,
                          icon: selectedEmployee == null
                              ? Icons.info_outline
                              : selectedEmployee!.linkState ==
                                          EmployeeErpLinkState.workerActive ||
                                      selectedEmployee!.linkState ==
                                          EmployeeErpLinkState.workerSuspended
                                  ? Icons.swap_horiz
                                  : Icons.link_outlined,
                          text: _employeeStateGuidance(selectedEmployee),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          key: const ValueKey('user-invite-email-field'),
                          controller: emailController,
                          focusNode: emailFocusNode,
                          decoration: const InputDecoration(
                            labelText: 'Email',
                            prefixIcon: Icon(Icons.email_outlined),
                          ),
                          keyboardType: TextInputType.emailAddress,
                          validator: AuthInputValidation.validateEmail,
                          onChanged: (_) => clearIdentityCheck(),
                        ),
                        if (isCheckingIdentity) ...[
                          const SizedBox(height: 8),
                          const LinearProgressIndicator(
                            key: ValueKey('user-invite-identity-checking'),
                          ),
                        ],
                        if (identityError != null) ...[
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              identityError!,
                              key: const ValueKey(
                                'user-invite-identity-error',
                              ),
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                            ),
                          ),
                        ] else if (identityCheck?.isExistingCustomer ==
                            true) ...[
                          const SizedBox(height: 8),
                          _noteBox(
                            dialogContext,
                            icon: Icons.verified_user_outlined,
                            text:
                                'Este correo ya usa una cuenta de cliente de Viñabike. La invitación conservará sus compras y añadirá el acceso ERP a la misma cuenta.',
                          ),
                        ],
                        const SizedBox(height: 12),
                        TextFormField(
                          key: const ValueKey('user-invite-name-field'),
                          controller: nameController,
                          decoration: const InputDecoration(
                            labelText: 'Nombre opcional',
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                          textCapitalization: TextCapitalization.words,
                          validator: (value) {
                            if ((value?.trim().length ?? 0) > 120) {
                              return 'El nombre no puede superar 120 caracteres';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          isExpanded: true,
                          initialValue: selectedRole,
                          decoration: const InputDecoration(
                            labelText: 'Rol',
                            prefixIcon:
                                Icon(Icons.admin_panel_settings_outlined),
                          ),
                          items: _roleOptions.entries
                              .map(
                                (entry) => DropdownMenuItem(
                                  value: entry.key,
                                  child: Text(entry.value),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            if (value == null) return;
                            setDialogState(() {
                              selectedRole = value;
                              permissions = _permissionsForRole(value);
                            });
                          },
                        ),
                        const SizedBox(height: 18),
                        _permissionEditor(permissions, setDialogState),
                        if (invitationError != null) ...[
                          const SizedBox(height: 12),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              invitationError!,
                              key: const ValueKey(
                                'user-invite-submission-error',
                              ),
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                    onPressed: isSubmitting
                        ? null
                        : () => Navigator.pop(dialogContext, false),
                    child: const Text('Cancelar')),
                FilledButton.icon(
                  onPressed: _isActionRunning ||
                          isSubmitting ||
                          isCheckingIdentity
                      ? null
                      : () async {
                          if (!formKey.currentState!.validate()) return;
                          emailFocusNode.unfocus();
                          identityBlurTimer?.cancel();
                          final eligibility = await verifyIdentity(force: true);
                          if (eligibility == null || !eligibility.eligible) {
                            return;
                          }
                          final employeeId = selectedEmployee?.employeeId;
                          setDialogState(() {
                            isSubmitting = true;
                            invitationError = null;
                          });
                          try {
                            await _userService.inviteInternalUser(
                              email: emailController.text.trim(),
                              role: selectedRole,
                              permissions: permissions,
                              name: nameController.text.trim().isEmpty
                                  ? null
                                  : nameController.text.trim(),
                              employeeId: employeeId,
                              transitionFromWorker:
                                  selectedEmployee?.linkState ==
                                      EmployeeErpLinkState.workerActive,
                            );
                            if (dialogContext.mounted) {
                              Navigator.pop(dialogContext, true);
                            }
                          } on UserManagementException catch (error) {
                            if (!dialogOpen) return;
                            setDialogState(() {
                              invitationError = error.message;
                              isSubmitting = false;
                            });
                          } catch (_) {
                            if (!dialogOpen) return;
                            setDialogState(() {
                              invitationError =
                                  'No pudimos enviar la invitación. Revisa los datos e inténtalo nuevamente.';
                              isSubmitting = false;
                            });
                          }
                        },
                  icon: isSubmitting
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_outlined, size: 18),
                  label: Text(
                    isSubmitting ? 'Enviando…' : 'Enviar invitación',
                  ),
                ),
              ],
            );
          },
        ),
      );
      dialogOpen = false;
      if (invitationSent == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invitación enviada por correo')),
        );
        await _loadData(silent: true);
      }
    } finally {
      dialogOpen = false;
      identityBlurTimer?.cancel();
      emailFocusNode.removeListener(handleEmailFocus);
      emailFocusNode.dispose();
      emailController.dispose();
      nameController.dispose();
    }
  }

  Future<void> _showLinkEmployeeDialog(Map<String, dynamic> user) async {
    final formKey = GlobalKey<FormState>();
    String? selectedEmployeeId;
    EmployeeAccessState? selectedEmployee;
    final profileActive = user['profileActive'] == true;
    final activeEmployees = _employeeAccessStates
        .where(
          (employee) =>
              employee.isActiveEmployee &&
              (profileActive ||
                  employee.linkState == EmployeeErpLinkState.workerActive),
        )
        .toList(growable: false);

    final employee = await showDialog<EmployeeAccessState>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Vincular trabajador'),
          content: SizedBox(
            width: 560,
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Cuenta ERP: ${user['email'] ?? user['displayName'] ?? 'usuario'}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: selectedEmployeeId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Trabajador',
                      prefixIcon: Icon(Icons.badge_outlined),
                    ),
                    hint: const Text('Selecciona una ficha'),
                    items: [
                      for (final option in activeEmployees)
                        DropdownMenuItem(
                          value: option.employeeId,
                          enabled: _canSelectEmployee(option),
                          child: Text(
                            '${option.employeeName} — ${_employeeStateLabel(option)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    validator: (value) =>
                        value == null ? 'Selecciona un trabajador' : null,
                    onChanged: (value) {
                      if (value == null) return;
                      setDialogState(() {
                        selectedEmployeeId = value;
                        selectedEmployee = _employeeAccessById(value);
                      });
                    },
                  ),
                  const SizedBox(height: 10),
                  _noteBox(
                    dialogContext,
                    icon: selectedEmployee?.linkState ==
                                EmployeeErpLinkState.workerActive ||
                            selectedEmployee?.linkState ==
                                EmployeeErpLinkState.workerSuspended
                        ? Icons.swap_horiz
                        : Icons.info_outline,
                    text: _directEmployeeLinkGuidance(selectedEmployee),
                  ),
                  if (activeEmployees.isEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      'No hay trabajadores activos disponibles.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.error,
                          ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            FilledButton.icon(
              onPressed: _isActionRunning
                  ? null
                  : () {
                      if (!formKey.currentState!.validate()) return;
                      final chosen = selectedEmployee;
                      if (chosen == null || !_canSelectEmployee(chosen)) {
                        setDialogState(() {
                          selectedEmployeeId = null;
                          selectedEmployee = null;
                        });
                        return;
                      }
                      Navigator.pop(dialogContext, chosen);
                    },
              icon: const Icon(Icons.add_link_outlined, size: 18),
              label: const Text('Continuar'),
            ),
          ],
        ),
      ),
    );

    if (employee == null || !mounted) return;
    await _confirmLinkEmployee(user: user, employee: employee);
  }

  Future<void> _confirmLinkEmployee({
    required Map<String, dynamic> user,
    required EmployeeAccessState employee,
  }) async {
    final userId = _normalizedId(user['id']);
    if (userId == null) return;
    final accountLabel = _normalizedId(user['email']) ??
        _normalizedId(user['displayName']) ??
        'esta cuenta ERP';
    final migrationNote = switch (employee.linkState) {
      EmployeeErpLinkState.workerActive =>
        '\n\nWorker Space seguirá disponible hasta confirmar. Al hacerlo, se cerrarán esas sesiones, se activará esta cuenta ERP y se moverán sus tareas abiertas.',
      EmployeeErpLinkState.workerSuspended =>
        '\n\nEl acceso histórico de Worker Space permanecerá suspendido.',
      _ => '',
    };
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Confirmar vínculo'),
        content: Text(
          'Vincularás la cuenta ERP $accountLabel con la ficha de ${employee.employeeName}.'
          '$migrationNote\n\nConfirma que ambas identidades pertenecen a la misma persona.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Volver'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.verified_user_outlined, size: 18),
            label: const Text('Confirmar vínculo'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await _runAction(
      'Trabajador vinculado a la cuenta ERP',
      () => _userService.linkInternalUserEmployee(
        userId: userId,
        employeeId: employee.employeeId,
      ),
    );
  }

  Future<void> _confirmUnlinkEmployee({
    required Map<String, dynamic> user,
    required EmployeeAccessState employee,
  }) async {
    final userId = _normalizedId(user['id']);
    if (userId == null) return;
    final accountLabel = _normalizedId(user['email']) ??
        _normalizedId(user['displayName']) ??
        'esta cuenta ERP';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Desvincular trabajador'),
        content: Text(
          'Quitarás el vínculo entre $accountLabel y ${employee.employeeName}. '
          'La cuenta ERP conservará su acceso y la ficha del trabajador conservará su historial; solo se elimina esta relación.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton.tonalIcon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.link_off_outlined, size: 18),
            label: const Text('Desvincular'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await _runAction(
      'Trabajador desvinculado de la cuenta ERP',
      () => _userService.unlinkInternalUserEmployee(
        userId: userId,
        employeeId: employee.employeeId,
      ),
    );
  }

  Future<void> _showSwitchToWorkerDialog({
    required Map<String, dynamic> user,
    required EmployeeAccessState employee,
  }) async {
    final userId = _normalizedId(user['id']);
    if (userId == null) return;
    final formKey = GlobalKey<FormState>();
    final suggested = employee.workerUsername ??
        employee.employeeName
            .toLowerCase()
            .replaceAll(RegExp(r'[^a-z0-9._-]+'), '.')
            .replaceAll(RegExp(r'^\.+|\.+$'), '');
    final usernameController = TextEditingController(
      text: suggested.length >= 3 ? suggested : 'trabajador',
    );
    final passwordController = TextEditingController();
    try {
      final input = await showDialog<({String username, String password})>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Mover a Worker Space'),
          content: Form(
            key: formKey,
            child: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${employee.employeeName} dejará de ingresar al ERP. Sus sesiones ERP se cerrarán y sus tareas abiertas pasarán a Worker Space; el historial y los mensajes se conservarán.',
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    key: const ValueKey('switch-worker-username'),
                    controller: usernameController,
                    decoration: const InputDecoration(
                      labelText: 'Usuario Worker Space',
                      prefixIcon: Icon(Icons.badge_outlined),
                    ),
                    validator: (value) {
                      final normalized = value?.trim().toLowerCase() ?? '';
                      return RegExp(r'^[a-z0-9][a-z0-9._-]{2,31}$')
                              .hasMatch(normalized)
                          ? null
                          : 'Usa 3 a 32 caracteres válidos';
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const ValueKey('switch-worker-password'),
                    controller: passwordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Contraseña temporal',
                      helperText:
                          AuthInputValidation.adminManagedPasswordHelper,
                      prefixIcon: Icon(Icons.lock_reset_outlined),
                    ),
                    validator: AuthInputValidation.validateAdminManagedPassword,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            FilledButton.icon(
              onPressed: () {
                if (!formKey.currentState!.validate()) return;
                Navigator.pop(
                  dialogContext,
                  (
                    username: usernameController.text.trim().toLowerCase(),
                    password: passwordController.text,
                  ),
                );
              },
              icon: const Icon(Icons.swap_horiz),
              label: const Text('Confirmar cambio'),
            ),
          ],
        ),
      );
      if (input == null || !mounted) return;
      await _runAction(
        'Acceso movido a Worker Space',
        () async {
          await _userService.switchErpUserToWorker(
            userId: userId,
            employeeId: employee.employeeId,
            username: input.username,
            password: input.password,
          );
        },
      );
    } finally {
      usernameController.dispose();
      passwordController.dispose();
    }
  }

  Future<void> _showEditStaffDialog(Map<String, dynamic> user) async {
    if (_normalizedId(user['id']) ==
        Supabase.instance.client.auth.currentUser?.id) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Otro administrador autorizado debe cambiar tu rol o permisos.',
          ),
        ),
      );
      return;
    }
    var selectedRole = user['role']?.toString() ?? 'cashier';
    var permissions = Map<String, bool>.from(
        user['permissions'] as Map? ?? _permissionsForRole(selectedRole));

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text('Permisos de ${user['email'] ?? 'usuario'}'),
            content: SizedBox(
              width: 560,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: selectedRole,
                      decoration: const InputDecoration(
                          labelText: 'Rol',
                          prefixIcon: Icon(Icons.badge_outlined)),
                      items: _roleOptions.entries
                          .map((entry) => DropdownMenuItem(
                              value: entry.key, child: Text(entry.value)))
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setDialogState(() {
                          selectedRole = value;
                          permissions = _permissionsForRole(value);
                        });
                      },
                    ),
                    const SizedBox(height: 18),
                    _permissionEditor(permissions, setDialogState),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancelar')),
              FilledButton.icon(
                onPressed: _isActionRunning
                    ? null
                    : () {
                        Navigator.pop(dialogContext);
                        _runAction(
                          'Usuario actualizado',
                          () => _userService.updateUserRole(
                            userId: user['id'].toString(),
                            newRole: selectedRole,
                            newPermissions: permissions,
                          ),
                        );
                      },
                icon: const Icon(Icons.save_outlined, size: 18),
                label: const Text('Guardar'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showEditStaffIdentityDialog(Map<String, dynamic> user) async {
    final nameController = TextEditingController(
      text: user['displayName']?.toString() ?? '',
    );

    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Editar nombre visible'),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameController,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Nombre visible',
                    prefixIcon: Icon(Icons.badge_outlined),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Este nombre se usa para identificar al usuario dentro del ERP sin cambiar su email de acceso.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            FilledButton.icon(
              onPressed: _isActionRunning
                  ? null
                  : () {
                      final name = nameController.text.trim();
                      if (name.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Ingresa un nombre visible.')),
                        );
                        return;
                      }
                      Navigator.pop(dialogContext);
                      _runAction(
                        'Nombre actualizado',
                        () => _userService.updateInternalIdentity(
                          userId: user['id'].toString(),
                          name: name,
                        ),
                      );
                    },
              icon: const Icon(Icons.save_outlined, size: 18),
              label: const Text('Guardar'),
            ),
          ],
        ),
      );
    } finally {
      nameController.dispose();
    }
  }

  Future<void> _showCustomerAccountDialog(
      {Map<String, dynamic>? customer}) async {
    final formKey = GlobalKey<FormState>();
    final isWebsiteOnlyAuth = customer?['isWebsiteOnlyAuth'] == true;
    final hasExistingAuth = customer?['hasAuth'] == true;
    final emailController =
        TextEditingController(text: customer?['email']?.toString() ?? '');
    final nameController =
        TextEditingController(text: customer?['displayName']?.toString() ?? '');
    final phoneController =
        TextEditingController(text: customer?['phone']?.toString() ?? '');

    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(isWebsiteOnlyAuth
              ? 'Crear ficha CRM y vincular'
              : customer == null
                  ? 'Crear cuenta cliente web'
                  : 'Crear o reparar cuenta web'),
          content: SizedBox(
            width: 560,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isWebsiteOnlyAuth) ...[
                      _noteBox(
                        dialogContext,
                        icon: Icons.link_outlined,
                        text:
                            'Esta cuenta web ya existe. Al guardar, se creará o reutilizará la ficha cliente CRM con este email y quedará vinculada al login del sitio.',
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextFormField(
                      controller: emailController,
                      decoration: const InputDecoration(
                          labelText: 'Email',
                          prefixIcon: Icon(Icons.email_outlined)),
                      keyboardType: TextInputType.emailAddress,
                      validator: AuthInputValidation.validateEmail,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: nameController,
                      decoration: const InputDecoration(
                          labelText: 'Nombre cliente',
                          prefixIcon: Icon(Icons.person_outline)),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                              ? 'Ingrese el nombre del cliente'
                              : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: phoneController,
                      decoration: const InputDecoration(
                          labelText: 'Teléfono opcional',
                          prefixIcon: Icon(Icons.phone_outlined)),
                    ),
                    const SizedBox(height: 10),
                    _noteBox(
                      dialogContext,
                      icon: hasExistingAuth
                          ? Icons.lock_reset
                          : Icons.outgoing_mail,
                      text: hasExistingAuth
                          ? 'Se enviará un correo seguro para recuperar el acceso. El ERP nunca ve ni define la contraseña del cliente.'
                          : 'Se enviará una invitación por email para que el cliente defina su propia contraseña.',
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancelar')),
            FilledButton.icon(
              onPressed: _isActionRunning
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) return;

                      final pageContext = context;
                      final email = emailController.text.trim();
                      final name = nameController.text.trim();
                      final phone = phoneController.text.trim();
                      Navigator.pop(dialogContext);
                      setState(() => _isActionRunning = true);
                      try {
                        final actionResult =
                            await _userService.createCustomerAccount(
                          customerId: customer?['customerId']?.toString(),
                          email: email,
                          name: name,
                          phone: phone.isEmpty ? null : phone,
                        );
                        if (!pageContext.mounted) return;
                        ScaffoldMessenger.of(pageContext).showSnackBar(
                          SnackBar(
                            content: Text(
                              _customerAccountSuccessMessage(actionResult),
                            ),
                          ),
                        );
                        await _loadData(silent: true);
                      } catch (_) {
                        if (!pageContext.mounted) return;
                        ScaffoldMessenger.of(pageContext).showSnackBar(
                          SnackBar(
                            content: const Text(
                              'No pudimos crear o vincular la cuenta. Inténtalo nuevamente.',
                            ),
                            backgroundColor:
                                Theme.of(pageContext).colorScheme.error,
                          ),
                        );
                      } finally {
                        if (mounted) {
                          setState(() => _isActionRunning = false);
                        }
                      }
                    },
              icon: const Icon(Icons.person_add_alt_1, size: 18),
              label:
                  Text(isWebsiteOnlyAuth ? 'Vincular ficha' : 'Crear cuenta'),
            ),
          ],
        ),
      );
    } finally {
      emailController.dispose();
      nameController.dispose();
      phoneController.dispose();
    }
  }

  Widget _permissionEditor(
    Map<String, bool> permissions,
    void Function(void Function()) setDialogState,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Permisos',
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        for (final option in _permissionOptions)
          CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            value: permissions[option.key] ?? false,
            onChanged: (value) =>
                setDialogState(() => permissions[option.key] = value ?? false),
            title: Row(
              children: [
                Icon(option.icon, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(option.label)),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _confirmDanger({
    required String title,
    required String message,
    required String confirmLabel,
    required Future<void> Function() action,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton.tonalIcon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.warning_amber, size: 18),
            label: Text(confirmLabel),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _runAction('Acción completada', action);
    }
  }

  Future<void> _confirmAccountRemoval({
    required String title,
    required String message,
    required String confirmLabel,
    required Future<Map<String, dynamic>> Function() action,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton.tonalIcon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.person_off_outlined, size: 18),
            label: Text(confirmLabel),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    setState(() => _isActionRunning = true);
    try {
      final result = await action();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_accountRemovalResultMessage(result))),
      );
      await _loadData(silent: true);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'No pudimos procesar la baja. Inténtalo nuevamente.',
          ),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isActionRunning = false);
    }
  }

  String _accountRemovalResultMessage(Map<String, dynamic> result) {
    if (result['outcome'] == 'deactivated_preserved_messaging_history') {
      if (result['authBanned'] == true) {
        return 'Acceso desactivado. La identidad y el historial de mensajería se conservaron para auditoría.';
      }
      return 'Membresía desactivada. La identidad sigue activa por otro acceso vigente y su historial quedó preservado.';
    }
    if (result['outcome'] == 'tenant_access_detached' ||
        result['authDetachedOnly'] == true) {
      return 'Acceso a esta tienda desactivado. La identidad global y la ficha histórica se conservaron.';
    }
    return 'Baja procesada correctamente.';
  }

  Future<void> _runAction(
      String successMessage, Future<void> Function() action) async {
    setState(() => _isActionRunning = true);
    try {
      await action();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(successMessage)));
      await _loadData(silent: true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_actionErrorMessage(error)),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      if (error is UserManagementException &&
          (error.status == 404 || error.status == 409)) {
        await _loadData(silent: true);
      }
    } finally {
      if (mounted) setState(() => _isActionRunning = false);
    }
  }

  String _actionErrorMessage(Object error) {
    if (error is UserManagementException) return error.message;
    return 'No pudimos completar la acción. Inténtalo nuevamente.';
  }

  Future<void> _sendPasswordReset(String email) async {
    await _runAction(
      'Correo de acceso seguro enviado',
      () => _userService.sendPasswordReset(email),
    );
  }

  String _customerAccountSuccessMessage(
    Map<String, dynamic> result,
  ) {
    if (result['passwordResetSent'] == true) {
      return 'Cuenta vinculada. Se envió un email para crear o recuperar la contraseña.';
    }
    if (result['inviteSent'] == true) {
      return 'Cuenta creada. Se envió la invitación de acceso al cliente.';
    }
    if (result['sharedStaffAccount'] == true) {
      return 'Este cliente ya usa un login interno ERP; no se cambió el acceso.';
    }
    return 'Cuenta cliente actualizada. Revisa el correo enviado para completar el acceso.';
  }

  Map<String, bool> _permissionsForRole(String role) {
    switch (role) {
      case 'admin':
      case 'manager':
        return {
          'access_pos': true,
          'create_invoices': true,
          'edit_prices': true,
          'delete_invoices': true,
          'access_accounting': true,
          'manage_users': true,
          'can_manage_supplier_credentials': true,
          'edit_settings': true,
        };
      case 'cashier':
        return {
          'access_pos': true,
          'create_invoices': true,
          'edit_prices': false,
          'delete_invoices': false,
          'access_accounting': false,
          'manage_users': false,
          'can_manage_supplier_credentials': false,
          'edit_settings': false,
        };
      case 'accountant':
        return {
          'access_pos': false,
          'create_invoices': false,
          'edit_prices': false,
          'delete_invoices': false,
          'access_accounting': true,
          'manage_users': false,
          'can_manage_supplier_credentials': false,
          'edit_settings': false,
        };
      case 'mechanic':
      default:
        return {
          'access_pos': false,
          'create_invoices': false,
          'edit_prices': false,
          'delete_invoices': false,
          'access_accounting': false,
          'manage_users': false,
          'can_manage_supplier_credentials': false,
          'edit_settings': false,
        };
    }
  }

  String _roleLabel(dynamic role) {
    return _roleOptions[role?.toString()] ?? role?.toString() ?? 'Sin rol';
  }

  /// Estas fechas son plazos del negocio —cuándo vence una invitación, cuándo
  /// entró alguien por última vez—, así que se leen en la hora del taller y no
  /// en la del equipo que abre la pantalla. `.toLocal()` mostraba la zona del
  /// dispositivo: en un Mac configurado en horario del Pacífico, un
  /// vencimiento de las 12:19 de Chile aparecía como 09:19, tres horas antes,
  /// en la misma pantalla donde el panel de al lado ya rotula «HORA CHILE».
  String _formatDate(dynamic value) {
    if (value == null || value.toString().isEmpty) return 'Sin registro';
    try {
      final parsed = DateTime.parse(value.toString()).toUtc();
      return DateFormat('dd/MM/yyyy HH:mm').format(
        tz.TZDateTime.from(parsed, _shopLocation()),
      );
    } catch (_) {
      return value.toString();
    }
  }
}

tz.Location? _shopLocationCache;

tz.Location _shopLocation() {
  final existing = _shopLocationCache;
  if (existing != null) return existing;
  tzdata.initializeTimeZones();
  return _shopLocationCache = tz.getLocation('America/Santiago');
}

class _PermissionOption {
  const _PermissionOption(this.key, this.label, this.icon);

  final String key;
  final String label;
  final IconData icon;
}

class _IdentityRowCopy {
  const _IdentityRowCopy({
    required this.title,
    required this.subtitle,
    required this.meta,
    this.exception,
  });

  final String title;
  final String subtitle;
  final String meta;
  final String? exception;
}
