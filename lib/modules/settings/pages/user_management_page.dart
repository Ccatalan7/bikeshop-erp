import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/services/tenant_service.dart';
import '../../../shared/services/user_management_service.dart';
import '../../../shared/utils/auth_input_validation.dart';
import '../../../shared/widgets/branded_loading.dart';

enum _IdentityAudience { staff, customers, invitations }

class UserManagementPage extends StatefulWidget {
  const UserManagementPage({super.key});

  @override
  State<UserManagementPage> createState() => _UserManagementPageState();
}

class _UserManagementPageState extends State<UserManagementPage> {
  static const _noEmployeeSelection = '__no_employee__';

  late final UserManagementService _userService;
  late final TenantService _tenantService;
  final _searchController = TextEditingController();

  Map<String, dynamic>? _currentTenant;
  List<Map<String, dynamic>> _staffUsers = [];
  List<Map<String, dynamic>> _customerAccounts = [];
  List<Map<String, dynamic>> _invitations = [];
  List<EmployeeAccessState> _employeeAccessStates = [];
  Map<String, dynamic> _summary = {};
  Map<String, dynamic>? _selectedItem;
  _IdentityAudience _audience = _IdentityAudience.staff;
  Timer? _searchDebounce;
  bool _isLoading = true;
  bool _isActionRunning = false;
  String? _errorMessage;

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
    _PermissionOption('edit_settings', 'Editar configuración', Icons.tune),
  ];

  @override
  void initState() {
    super.initState();
    _userService = Provider.of<UserManagementService>(context, listen: false);
    _tenantService = Provider.of<TenantService>(context, listen: false);
    _searchController.addListener(_scheduleSearch);
    _loadData();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _scheduleSearch() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      _loadData(silent: true);
    });
  }

  Future<void> _loadData({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final overviewFuture = _userService.getIdentityOverview(
          search: _searchController.text.trim());
      final tenantFuture = _tenantService.getCurrentTenant();
      final overview = await overviewFuture;
      final tenant = await tenantFuture;

      if (!mounted) return;
      setState(() {
        _staffUsers = _listFrom(overview['staffUsers']);
        _customerAccounts = _listFrom(overview['customerAccounts']);
        _invitations = _listFrom(overview['invitations']);
        _employeeAccessStates =
            parseEmployeeAccessStates(overview['employeeAccessStates']);
        _summary = Map<String, dynamic>.from(overview['summary'] as Map? ?? {});
        _currentTenant = tenant;
        _selectedItem = _resolveSelection();
        _isLoading = false;
      });
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
    final currentList = _itemsForAudience(_audience);
    if (currentList.isEmpty) return null;
    final selected = _selectedItem;
    if (selected == null) return currentList.first;
    final selectedId = _identityId(selected);
    return currentList.firstWhere(
      (item) => _identityId(item) == selectedId,
      orElse: () => currentList.first,
    );
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
    if (employee.pendingInvitation ||
        _pendingInvitationForEmployee(employee.employeeId) != null) {
      return 'Invitación pendiente';
    }
    return switch (employee.linkState) {
      EmployeeErpLinkState.available => 'Disponible para vincular',
      EmployeeErpLinkState.pendingInvitation => 'Invitación pendiente',
      EmployeeErpLinkState.erpLinked =>
        'Vinculado a ${_staffIdentityLabel(employee.erpUserId)}',
      EmployeeErpLinkState.workerActive => 'App de trabajadores activa',
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
    if (employee.pendingInvitation || pending != null) {
      return 'Ya hay una invitación pendiente para este trabajador (${pending?['email'] ?? 'sin email visible'}). Reenvíala o cancélala desde Invitaciones.';
    }
    return switch (employee.linkState) {
      EmployeeErpLinkState.available =>
        'Disponible. Al aceptar la invitación, esta cuenta ERP quedará vinculada a ${employee.employeeName}.',
      EmployeeErpLinkState.pendingInvitation =>
        'Ya existe una invitación pendiente para este trabajador.',
      EmployeeErpLinkState.erpLinked =>
        'Ya está vinculado a ${_staffIdentityLabel(employee.erpUserId)}. Desvincula esa cuenta antes de reasignarlo.',
      EmployeeErpLinkState.workerActive =>
        'Tiene acceso activo en la app de trabajadores${employee.workerUsername == null ? '' : ' como ${employee.workerUsername}'}. Suspéndelo antes de migrarlo a una cuenta ERP.',
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
    if (employee.pendingInvitation || pending != null) {
      return 'Ya existe una invitación pendiente para este trabajador. Reenvíala o cancélala antes de vincular otra cuenta.';
    }
    return switch (employee.linkState) {
      EmployeeErpLinkState.available =>
        'Disponible. Esta cuenta ERP quedará vinculada inmediatamente a ${employee.employeeName}.',
      EmployeeErpLinkState.pendingInvitation =>
        'Ya existe una invitación pendiente para este trabajador.',
      EmployeeErpLinkState.erpLinked =>
        'Ya está vinculado a ${_staffIdentityLabel(employee.erpUserId)}.',
      EmployeeErpLinkState.workerActive =>
        'Tiene acceso activo en la app de trabajadores. Suspéndelo antes de migrarlo a una cuenta ERP.',
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

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLowest,
      body: SafeArea(
        child: _isLoading
            ? const Center(child: BrandedLoading())
            : _errorMessage != null
                ? _buildErrorState(context)
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final isWide = constraints.maxWidth >= 1120;
                      return RefreshIndicator(
                        onRefresh: _loadData,
                        child: SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: EdgeInsets.fromLTRB(
                            isWide ? 28 : 18,
                            isWide ? 24 : 18,
                            isWide ? 28 : 18,
                            40,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildHeader(context),
                              const SizedBox(height: 18),
                              _buildSummaryStrip(context),
                              const SizedBox(height: 18),
                              _buildToolbar(context, isWide: isWide),
                              const SizedBox(height: 18),
                              if (isWide)
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      flex: 6,
                                      child: _buildListPanel(context),
                                    ),
                                    const SizedBox(width: 18),
                                    Expanded(
                                      flex: 4,
                                      child: _buildDetailPanel(context),
                                    ),
                                  ],
                                )
                              else ...[
                                _buildListPanel(context),
                                const SizedBox(height: 18),
                                _buildDetailPanel(context),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    final tenantName = _currentTenant?['shop_name']?.toString() ?? 'Empresa';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF123C69), Color(0xFF0F766E)],
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x220F766E),
            blurRadius: 30,
            offset: Offset(0, 16),
          ),
        ],
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        runSpacing: 18,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.18),
                    ),
                  ),
                  child: Text(
                    tenantName,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Usuarios y roles',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Administra cuentas internas del ERP, clientes del sitio web, verificación de correo, accesos restringidos e invitaciones pendientes desde una sola consola.',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: Colors.white.withValues(alpha: 0.86),
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _headerAction(
                context,
                icon: Icons.person_add_alt_1,
                label: 'Invitar equipo',
                onPressed: _isActionRunning ? null : _showInviteStaffDialog,
              ),
              _headerAction(
                context,
                icon: Icons.storefront,
                label: 'Crear cliente web',
                onPressed: _isActionRunning
                    ? null
                    : () => _showCustomerAccountDialog(),
              ),
              IconButton.filledTonal(
                tooltip: 'Actualizar',
                onPressed: _isActionRunning ? null : _loadData,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _headerAction(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
  }) {
    return FilledButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: FilledButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF123C69),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }

  Widget _buildSummaryStrip(BuildContext context) {
    final cards = [
      _SummaryCardData(
        label: 'Equipo ERP',
        value: _number(_summary['staffCount']),
        icon: Icons.badge_outlined,
        color: const Color(0xFF2563EB),
      ),
      _SummaryCardData(
        label: 'CRM + web',
        value: _number(_summary['linkedCustomerCount']),
        icon: Icons.public,
        color: const Color(0xFF0F766E),
      ),
      _SummaryCardData(
        label: 'Clientes CRM',
        value: _number(_summary['customerCount']),
        icon: Icons.groups_2_outlined,
        color: const Color(0xFF8B5CF6),
      ),
      _SummaryCardData(
        label: 'Solo web sin ficha',
        value: _number(_summary['orphanWebsiteAccountCount']),
        icon: Icons.person_search_outlined,
        color: const Color(0xFFB7791F),
      ),
      _SummaryCardData(
        label: 'Invitaciones',
        value: _number(_summary['pendingInvitationCount']),
        icon: Icons.mark_email_unread_outlined,
        color: const Color(0xFFB7791F),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1200 ? 5 : 2;
        const spacing = 12.0;
        final width =
            (constraints.maxWidth - (spacing * (columns - 1))) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final card in cards)
              SizedBox(width: width, child: _summaryCard(context, card)),
          ],
        );
      },
    );
  }

  Widget _summaryCard(BuildContext context, _SummaryCardData data) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Color.lerp(colorScheme.surface, data.color, 0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: data.color.withValues(alpha: 0.16)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: data.color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(data.icon, color: data.color, size: 21),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data.value,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  data.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar(BuildContext context, {required bool isWide}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Theme.of(context)
              .colorScheme
              .outlineVariant
              .withValues(alpha: 0.65),
        ),
      ),
      child: isWide
          ? Row(
              children: [
                Expanded(child: _audienceSelector(context)),
                const SizedBox(width: 12),
                SizedBox(width: 360, child: _searchField()),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _audienceSelector(context),
                const SizedBox(height: 12),
                _searchField(),
              ],
            ),
    );
  }

  Widget _audienceSelector(BuildContext context) {
    return SegmentedButton<_IdentityAudience>(
      selected: {_audience},
      showSelectedIcon: false,
      onSelectionChanged: (selection) {
        setState(() {
          _audience = selection.first;
          _selectedItem = _resolveSelection();
        });
      },
      segments: const [
        ButtonSegment(
          value: _IdentityAudience.staff,
          icon: Icon(Icons.badge_outlined, size: 18),
          label: Text('Equipo'),
        ),
        ButtonSegment(
          value: _IdentityAudience.customers,
          icon: Icon(Icons.storefront_outlined, size: 18),
          label: Text('Clientes'),
        ),
        ButtonSegment(
          value: _IdentityAudience.invitations,
          icon: Icon(Icons.mark_email_unread_outlined, size: 18),
          label: Text('Invitaciones'),
        ),
      ],
    );
  }

  Widget _searchField() {
    return TextField(
      controller: _searchController,
      decoration: InputDecoration(
        isDense: true,
        prefixIcon: const Icon(Icons.search),
        suffixIcon: _searchController.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Limpiar búsqueda',
                onPressed: () {
                  _searchController.clear();
                  _loadData(silent: true);
                },
                icon: const Icon(Icons.close),
              ),
        hintText: _audience == _IdentityAudience.customers
            ? 'Buscar cliente o cuenta web por nombre, email o teléfono'
            : 'Buscar email o nombre',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  Widget _buildListPanel(BuildContext context) {
    final items = _itemsForAudience(_audience);
    final theme = Theme.of(context);
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

    return _panel(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              _countPill(context, items.length),
            ],
          ),
          const SizedBox(height: 14),
          if (items.isEmpty)
            _emptyState(context)
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) =>
                  _identityRow(context, items[index]),
            ),
        ],
      ),
    );
  }

  Widget _identityRow(BuildContext context, Map<String, dynamic> item) {
    final isSelected = _selectedItem != null &&
        _identityId(_selectedItem!) == _identityId(item);
    final isCustomer =
        item['kind'] == 'customer' || _audience == _IdentityAudience.customers;
    final isInvitation = _audience == _IdentityAudience.invitations;
    final isWebsiteOnlyAuth = item['isWebsiteOnlyAuth'] == true;
    final accent = isCustomer
        ? (isWebsiteOnlyAuth
            ? const Color(0xFFB7791F)
            : const Color(0xFF0F766E))
        : isInvitation
            ? const Color(0xFFB7791F)
            : const Color(0xFF2563EB);
    final title = isInvitation
        ? item['email']?.toString() ?? 'Invitación'
        : item['displayName']?.toString() ??
            item['email']?.toString() ??
            'Usuario';
    final invitationEmployee =
        isInvitation ? _employeeAccessById(_invitationEmployeeId(item)) : null;
    final subtitle = isInvitation
        ? invitationEmployee == null
            ? 'Rol: ${_roleLabel(item['role'])} · expira ${_formatDate(item['expires_at'])}'
            : 'Rol: ${_roleLabel(item['role'])} · ${invitationEmployee.employeeName}'
        : item['email']?.toString() ?? 'Sin email';
    final isActive = item['isActive'] != false;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => setState(() => _selectedItem = item),
        child: Ink(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isSelected
                ? accent.withValues(alpha: 0.09)
                : Theme.of(context).colorScheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected
                  ? accent.withValues(alpha: 0.35)
                  : Theme.of(context)
                      .colorScheme
                      .outlineVariant
                      .withValues(alpha: 0.55),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  isCustomer
                      ? _customerRelationshipIcon(item)
                      : isInvitation
                          ? Icons.mail_outline
                          : _roleIcon(item['role']?.toString()),
                  color: accent,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        if (!isInvitation)
                          _miniChip(
                            context,
                            isActive ? 'Activo' : 'Restringido',
                            isActive
                                ? Colors.green.shade700
                                : Colors.red.shade700,
                          ),
                        if (!isInvitation)
                          _miniChip(
                            context,
                            item['emailConfirmed'] == true
                                ? 'Email verificado'
                                : 'Sin verificar',
                            item['emailConfirmed'] == true
                                ? Colors.blue.shade700
                                : Colors.orange.shade800,
                          ),
                        if (isCustomer)
                          _miniChip(
                            context,
                            _customerRelationshipLabel(item),
                            _customerRelationshipColor(item),
                          ),
                        if (!isCustomer && !isInvitation)
                          _miniChip(context, _roleLabel(item['role']), accent),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Icon(Icons.chevron_right, color: accent),
            ],
          ),
        ),
      ),
    );
  }

  String _customerRelationshipLabel(Map<String, dynamic> item) {
    if (item['isStaffAuthUser'] == true) return 'CRM + login ERP';
    if (item['isWebsiteOnlyAuth'] == true) return 'Solo web, sin ficha CRM';
    if (item['hasAuth'] == true) return 'CRM + cuenta web';
    return 'Solo CRM';
  }

  Color _customerRelationshipColor(Map<String, dynamic> item) {
    if (item['isWebsiteOnlyAuth'] == true) return const Color(0xFFB7791F);
    if (item['hasAuth'] == true) return const Color(0xFF0F766E);
    return Colors.grey.shade700;
  }

  IconData _customerRelationshipIcon(Map<String, dynamic> item) {
    if (item['isWebsiteOnlyAuth'] == true) return Icons.person_search_outlined;
    if (item['isStaffAuthUser'] == true) return Icons.badge_outlined;
    if (item['hasAuth'] == true) return Icons.storefront;
    return Icons.contact_page_outlined;
  }

  Widget _buildDetailPanel(BuildContext context) {
    final item = _selectedItem ?? _resolveSelection();
    if (item == null) {
      return _panel(
        context,
        child: _emptyState(context,
            message: 'Selecciona una cuenta para ver sus controles.'),
      );
    }

    if (_audience == _IdentityAudience.customers) {
      return _customerDetail(context, item);
    }
    if (_audience == _IdentityAudience.invitations) {
      return _invitationDetail(context, item);
    }
    return _staffDetail(context, item);
  }

  Widget _staffDetail(BuildContext context, Map<String, dynamic> user) {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    final isSelf = user['id'] == currentUserId;
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
    final employeeLinkNeedsReview = hasDeclaredEmployeeLink
        ? !hasHealthyEmployeeLink
        : employeeState?.erpUserId == userId;

    return _panel(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _detailHeader(
            context,
            icon: _roleIcon(user['role']?.toString()),
            color: const Color(0xFF2563EB),
            title: displayName,
            subtitle: 'Usuario interno · ${_roleLabel(user['role'])}',
          ),
          const SizedBox(height: 18),
          _detailLine('Nombre visible', displayName),
          _detailLine('Email', email),
          _detailLine('Estado', isActive ? 'Activo' : 'Acceso restringido'),
          _detailLine(
              'Email verificado', user['emailConfirmed'] == true ? 'Sí' : 'No'),
          _detailLine('Último acceso', _formatDate(user['lastSignInAt'])),
          _detailLine(
            'Trabajador vinculado',
            employeeLinkNeedsReview
                ? 'Requiere revisión'
                : hasHealthyEmployeeLink
                    ? employeeState.employeeName
                    : 'No vinculado',
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: _isActionRunning || isSelf
                    ? null
                    : () => _showEditStaffDialog(user),
                icon: const Icon(Icons.tune, size: 18),
                label: const Text('Rol y permisos'),
              ),
              OutlinedButton.icon(
                onPressed: _isActionRunning ||
                        employeeLinkNeedsReview ||
                        (!profileActive && !hasHealthyEmployeeLink)
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
              ),
              OutlinedButton.icon(
                onPressed: _isActionRunning
                    ? null
                    : () => _showEditStaffIdentityDialog(user),
                icon: const Icon(Icons.drive_file_rename_outline, size: 18),
                label: const Text('Editar nombre'),
              ),
              OutlinedButton.icon(
                onPressed: _isActionRunning || email.isEmpty
                    ? null
                    : () => _sendPasswordReset(email),
                icon: const Icon(Icons.lock_reset, size: 18),
                label: const Text('Enviar acceso seguro'),
              ),
              OutlinedButton.icon(
                onPressed: _isActionRunning || isSelf
                    ? null
                    : () => _runAction(
                          isActive ? 'Usuario restringido' : 'Usuario activado',
                          () => _userService.toggleUserStatus(
                              user['id'].toString(), !isActive),
                        ),
                icon:
                    Icon(isActive ? Icons.block : Icons.check_circle, size: 18),
                label:
                    Text(isActive ? 'Restringir acceso' : 'Restaurar acceso'),
              ),
              OutlinedButton.icon(
                onPressed: _isActionRunning || user['emailConfirmed'] == true
                    ? null
                    : () => _runAction(
                          'Correo de acceso seguro enviado',
                          () => _userService.sendPasswordReset(email),
                        ),
                icon: const Icon(Icons.outgoing_mail, size: 18),
                label: const Text('Reenviar acceso'),
              ),
              OutlinedButton.icon(
                onPressed: _isActionRunning || isSelf
                    ? null
                    : () => _confirmAccountRemoval(
                          title: 'Dar de baja cuenta interna',
                          message:
                              'Se retirará el acceso ERP de $email. Si existe trazabilidad de mensajería, la identidad y su autoría se conservarán desactivadas para auditoría.',
                          confirmLabel: 'Procesar baja',
                          action: () =>
                              _userService.deleteUser(user['id'].toString()),
                        ),
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Dar de baja'),
              ),
            ],
          ),
          if (isSelf) ...[
            const SizedBox(height: 12),
            _noteBox(
              context,
              icon: Icons.shield_outlined,
              text:
                  'Tu propio rol y tus permisos se muestran como referencia. Otro administrador autorizado debe cambiarlos.',
            ),
          ],
          if (employeeLinkNeedsReview) ...[
            const SizedBox(height: 12),
            _noteBox(
              context,
              icon: Icons.warning_amber_rounded,
              text:
                  'El perfil ERP y el registro del trabajador no describen el mismo vínculo. Se bloquearon los cambios para evitar asignar acceso a la persona incorrecta.',
            ),
          ],
          if (!profileActive) ...[
            const SizedBox(height: 12),
            _noteBox(
              context,
              icon: Icons.link_off_outlined,
              text: hasHealthyEmployeeLink
                  ? 'La cuenta interna está suspendida, pero su vínculo exacto se conserva para auditoría. Puedes desvincularla explícitamente si necesitas reasignar la ficha del trabajador.'
                  : 'Restaura primero el acceso de esta cuenta interna si necesitas vincularla a un trabajador.',
            ),
          ],
          const SizedBox(height: 18),
          _permissionsPreview(context, user['permissions']),
        ],
      ),
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

    return _panel(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _detailHeader(
            context,
            icon: _customerRelationshipIcon(customer),
            color: _customerRelationshipColor(customer),
            title: customer['displayName']?.toString() ?? email,
            subtitle: isWebsiteOnlyAuth
                ? 'Cuenta web sin ficha cliente CRM'
                : isSharedStaffAccount
                    ? 'Cliente CRM vinculado a un usuario interno ERP'
                    : hasAuth
                        ? 'Cliente CRM con cuenta web'
                        : 'Cliente CRM sin cuenta web',
          ),
          const SizedBox(height: 18),
          _detailLine('Email', email.isEmpty ? 'Sin email' : email),
          _detailLine(
              'Teléfono', customer['phone']?.toString() ?? 'No registrado'),
          _detailLine(
              'Relación ERP/sitio', _customerRelationshipLabel(customer)),
          _detailLine(
              'Ficha cliente ERP/CRM', hasCustomerProfile ? 'Sí' : 'No'),
          _detailLine('Cuenta sitio web', hasAuth ? 'Sí' : 'No'),
          _detailLine('Estado', isActive ? 'Activo' : 'Acceso restringido'),
          _detailLine(
              'Email verificado',
              hasAuth
                  ? (customer['emailConfirmed'] == true ? 'Sí' : 'No')
                  : 'No aplica'),
          if (isSharedStaffAccount)
            _detailLine('Tipo de acceso', 'Login compartido con equipo ERP'),
          _detailLine('Último acceso', _formatDate(customer['lastSignInAt'])),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: _isActionRunning || isSharedStaffAccount
                    ? null
                    : () => _showCustomerAccountDialog(customer: customer),
                icon: Icon(
                    isWebsiteOnlyAuth
                        ? Icons.add_link
                        : hasAuth
                            ? Icons.manage_accounts
                            : Icons.person_add_alt_1,
                    size: 18),
                label: Text(isWebsiteOnlyAuth
                    ? 'Crear ficha CRM'
                    : hasAuth
                        ? 'Reparar vínculo'
                        : 'Crear cuenta web'),
              ),
              OutlinedButton.icon(
                onPressed: _isActionRunning ||
                        !hasAuth ||
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
                icon: const Icon(Icons.outgoing_mail, size: 18),
                label: const Text('Reenviar verificación'),
              ),
              OutlinedButton.icon(
                onPressed:
                    _isActionRunning || email.isEmpty || isSharedStaffAccount
                        ? null
                        : () => _sendPasswordReset(email),
                icon: const Icon(Icons.lock_reset, size: 18),
                label: const Text('Enviar acceso seguro'),
              ),
              OutlinedButton.icon(
                onPressed: _isActionRunning ||
                        !hasCustomerProfile ||
                        isSharedStaffAccount
                    ? null
                    : () => _runAction(
                          isActive ? 'Cliente restringido' : 'Cliente activado',
                          () => _userService.setCustomerAccess(
                            customerId: customerId,
                            isActive: !isActive,
                          ),
                        ),
                icon:
                    Icon(isActive ? Icons.block : Icons.check_circle, size: 18),
                label: Text(isActive ? 'Limitar acceso' : 'Restaurar acceso'),
              ),
              OutlinedButton.icon(
                onPressed: _isActionRunning || !hasAuth || authUserId == null
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
                                  authUserId: authUserId)
                              : _userService.deleteCustomerAccount(
                                  customerId: customerId),
                        ),
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Dar de baja'),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _noteBox(
            context,
            icon: Icons.info_outline,
            text: isSharedStaffAccount
                ? 'Este cliente usa el mismo login que un usuario interno del ERP. Las acciones de contraseña, verificación y restricción se gestionan desde la pestaña Equipo para no bloquear accidentalmente el acceso del personal.'
                : isWebsiteOnlyAuth
                    ? 'Esta cuenta existe en Supabase Auth como cliente del sitio, pero no tiene ficha cliente CRM. Crea la ficha CRM para vincular historial, bicicletas, pedidos y soporte a ese login.'
                    : hasAuth
                        ? 'Los clientes web no tienen permisos de ERP. Su acceso queda limitado al portal público, pedidos, bicicletas y soporte vinculado a su propio cliente.'
                        : 'Busca un cliente y crea su cuenta desde aquí cuando tenga problemas con el registro del sitio web.',
          ),
        ],
      ),
    );
  }

  Widget _invitationDetail(
      BuildContext context, Map<String, dynamic> invitation) {
    final email = invitation['email']?.toString() ?? '';
    final invitationId = invitation['id']?.toString() ?? '';
    final invitationEmployeeId = _invitationEmployeeId(invitation);
    final invitationEmployee = _employeeAccessById(invitationEmployeeId);
    return _panel(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _detailHeader(
            context,
            icon: Icons.mark_email_unread_outlined,
            color: const Color(0xFFB7791F),
            title: email,
            subtitle:
                'Invitación pendiente · ${_roleLabel(invitation['role'])}',
          ),
          const SizedBox(height: 18),
          _detailLine('Estado', invitation['status']?.toString() ?? 'pending'),
          _detailLine(
            'Trabajador',
            invitationEmployee?.employeeName ??
                (invitationEmployeeId == null
                    ? 'Sin vínculo'
                    : 'Vínculo requiere revisión'),
          ),
          _detailLine('Expira', _formatDate(invitation['expires_at'])),
          _detailLine('Creada', _formatDate(invitation['created_at'])),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: _isActionRunning
                    ? null
                    : () => _runAction(
                          'Invitación reenviada',
                          () => _userService
                              .resendInternalInvitation(invitationId),
                        ),
                icon: const Icon(Icons.outgoing_mail, size: 18),
                label: const Text('Reenviar'),
              ),
              OutlinedButton.icon(
                onPressed: _isActionRunning
                    ? null
                    : () => _confirmDanger(
                          title: 'Cancelar invitación',
                          message:
                              'La invitación a $email dejará de ser válida.',
                          confirmLabel: 'Cancelar invitación',
                          action: () => _userService
                              .cancelInternalInvitation(invitationId),
                        ),
                icon: const Icon(Icons.cancel_outlined, size: 18),
                label: const Text('Cancelar'),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _permissionsPreview(context, invitation['permissions']),
        ],
      ),
    );
  }

  Widget _panel(BuildContext context, {required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: Theme.of(context)
              .colorScheme
              .outlineVariant
              .withValues(alpha: 0.65),
        ),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).colorScheme.shadow.withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _detailHeader(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.13),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(icon, color: color, size: 23),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _detailLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SelectableText(
              value,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _permissionsPreview(BuildContext context, dynamic permissionsData) {
    final permissions =
        Map<String, dynamic>.from(permissionsData as Map? ?? {});
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Permisos operativos',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in _permissionOptions)
              _permissionPill(
                context,
                option,
                permissions[option.key] == true,
              ),
          ],
        ),
      ],
    );
  }

  Widget _permissionPill(
    BuildContext context,
    _PermissionOption option,
    bool enabled,
  ) {
    final color = enabled ? const Color(0xFF0F766E) : Colors.grey.shade600;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: enabled ? 0.1 : 0.06),
        borderRadius: BorderRadius.circular(999),
        border:
            Border.all(color: color.withValues(alpha: enabled ? 0.22 : 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(option.icon, size: 15, color: color),
          const SizedBox(width: 6),
          Text(
            option.label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }

  Widget _miniChip(BuildContext context, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
            ),
      ),
    );
  }

  Widget _countPill(BuildContext context, int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$count',
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w800,
            ),
      ),
    );
  }

  Widget _noteBox(BuildContext context,
      {required IconData icon, required String text}) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
              child: Text(text, style: Theme.of(context).textTheme.bodySmall)),
        ],
      ),
    );
  }

  Widget _emptyState(BuildContext context, {String? message}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 42),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Icon(Icons.manage_search,
              size: 40, color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(height: 10),
          Text(
            message ?? 'No hay registros para esta vista.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: _panel(
          context,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline,
                  color: Theme.of(context).colorScheme.error, size: 42),
              const SizedBox(height: 12),
              Text('No se pudo cargar la consola de usuarios',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(_errorMessage ?? '', textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _loadData,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showInviteStaffDialog() async {
    final formKey = GlobalKey<FormState>();
    final emailController = TextEditingController();
    final nameController = TextEditingController();
    var selectedRole = 'cashier';
    var permissions = _permissionsForRole(selectedRole);
    var selectedEmployeeKey = _noEmployeeSelection;
    EmployeeAccessState? selectedEmployee;
    String? previousEmailPrefill;
    String? previousNamePrefill;
    final activeEmployees = _employeeAccessStates
        .where((employee) => employee.isActiveEmployee)
        .toList(growable: false);

    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) {
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
                          },
                        ),
                        const SizedBox(height: 10),
                        _noteBox(
                          dialogContext,
                          icon: selectedEmployee == null
                              ? Icons.info_outline
                              : selectedEmployee!.linkState ==
                                      EmployeeErpLinkState.workerSuspended
                                  ? Icons.swap_horiz
                                  : Icons.link_outlined,
                          text: _employeeStateGuidance(selectedEmployee),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          key: const ValueKey('user-invite-email-field'),
                          controller: emailController,
                          decoration: const InputDecoration(
                            labelText: 'Email',
                            prefixIcon: Icon(Icons.email_outlined),
                          ),
                          keyboardType: TextInputType.emailAddress,
                          validator: AuthInputValidation.validateEmail,
                        ),
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
                          final employeeId = selectedEmployee?.employeeId;
                          Navigator.pop(dialogContext);
                          await _runAction(
                            'Invitación enviada por correo',
                            () async {
                              await _userService.inviteInternalUser(
                                email: emailController.text.trim(),
                                role: selectedRole,
                                permissions: permissions,
                                name: nameController.text.trim().isEmpty
                                    ? null
                                    : nameController.text.trim(),
                                employeeId: employeeId,
                              );
                            },
                          );
                        },
                  icon: const Icon(Icons.send_outlined, size: 18),
                  label: const Text('Enviar invitación'),
                ),
              ],
            );
          },
        ),
      );
    } finally {
      emailController.dispose();
      nameController.dispose();
    }
  }

  Future<void> _showLinkEmployeeDialog(Map<String, dynamic> user) async {
    final formKey = GlobalKey<FormState>();
    String? selectedEmployeeId;
    EmployeeAccessState? selectedEmployee;
    final activeEmployees = _employeeAccessStates
        .where((employee) => employee.isActiveEmployee)
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
    final migrationNote = employee.linkState ==
            EmployeeErpLinkState.workerSuspended
        ? '\n\nEl acceso independiente de la app de trabajadores permanecerá suspendido.'
        : '';
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
          'edit_settings': false,
        };
    }
  }

  IconData _roleIcon(String? role) {
    switch (role) {
      case 'admin':
      case 'manager':
        return Icons.admin_panel_settings_outlined;
      case 'cashier':
        return Icons.point_of_sale;
      case 'mechanic':
        return Icons.build_outlined;
      case 'accountant':
        return Icons.account_balance_outlined;
      default:
        return Icons.person_outline;
    }
  }

  String _roleLabel(dynamic role) {
    return _roleOptions[role?.toString()] ?? role?.toString() ?? 'Sin rol';
  }

  String _formatDate(dynamic value) {
    if (value == null || value.toString().isEmpty) return 'Sin registro';
    try {
      return DateFormat('dd/MM/yyyy HH:mm')
          .format(DateTime.parse(value.toString()).toLocal());
    } catch (_) {
      return value.toString();
    }
  }

  String _number(dynamic value) {
    final number = int.tryParse(value?.toString() ?? '') ?? 0;
    return NumberFormat.decimalPattern('es_CL').format(number);
  }
}

class _PermissionOption {
  const _PermissionOption(this.key, this.label, this.icon);

  final String key;
  final String label;
  final IconData icon;
}

class _SummaryCardData {
  const _SummaryCardData({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
}
