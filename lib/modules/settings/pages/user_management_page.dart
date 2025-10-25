import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

import '../../../shared/services/user_management_service.dart';
import '../../../shared/services/tenant_service.dart';
import '../../../shared/widgets/app_button.dart';
import '../widgets/user_invite_dialog.dart';
import '../widgets/user_edit_dialog.dart';

class UserManagementPage extends StatefulWidget {
  const UserManagementPage({super.key});

  @override
  State<UserManagementPage> createState() => _UserManagementPageState();
}

class _UserManagementPageState extends State<UserManagementPage> {
  late UserManagementService _userService;
  late TenantService _tenantService;
  
  List<Map<String, dynamic>> _users = [];
  Map<String, dynamic>? _currentTenant;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _userService = Provider.of<UserManagementService>(context, listen: false);
    _tenantService = Provider.of<TenantService>(context, listen: false);
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final users = await _userService.getTenantUsers();
      final tenant = await _tenantService.getCurrentTenant();
      
      setState(() {
        _users = users;
        _currentTenant = tenant;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _showInviteDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => const UserInviteDialog(),
    );

    if (result == true) {
      _loadData();
    }
  }

  Future<void> _showEditDialog(Map<String, dynamic> user) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => UserEditDialog(user: user),
    );

    if (result == true) {
      _loadData();
    }
  }

  Future<void> _toggleUserStatus(String userId, bool isCurrentlyActive) async {
    try {
      await _userService.toggleUserStatus(userId, !isCurrentlyActive);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isCurrentlyActive ? 'Usuario suspendido' : 'Usuario activado'),
          backgroundColor: Colors.green,
        ),
      );
      _loadData();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _deleteUser(String userId, String email) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar Usuario'),
        content: Text('¿Estás seguro de eliminar a $email?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          AppButton(
            text: 'Eliminar',
            onPressed: () => Navigator.pop(context, true),
            type: ButtonType.danger,
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _userService.deleteUser(userId);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Usuario eliminado'),
            backgroundColor: Colors.green,
          ),
        );
        _loadData();
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestión de Usuarios'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
            tooltip: 'Actualizar',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error, size: 64, color: Colors.red),
                      const SizedBox(height: 16),
                      Text('Error: $_errorMessage'),
                      const SizedBox(height: 16),
                      AppButton(
                        text: 'Reintentar',
                        onPressed: _loadData,
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    // Header with tenant info
                    if (_currentTenant != null)
                      Container(
                        padding: const EdgeInsets.all(16),
                        color: Theme.of(context).colorScheme.primaryContainer,
                        child: Row(
                          children: [
                            Icon(
                              Icons.business,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _currentTenant!['shop_name'] ?? 'Empresa',
                                    style: Theme.of(context).textTheme.titleMedium,
                                  ),
                                  Text(
                                    'Plan: ${_currentTenant!['plan'] ?? 'free'}',
                                    style: Theme.of(context).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            AppButton(
                              text: 'Invitar Usuario',
                              icon: Icons.person_add,
                              onPressed: _showInviteDialog,
                            ),
                          ],
                        ),
                      ),
                    
                    // User count
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Text(
                            'Usuarios Activos (${_users.length})',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ],
                      ),
                    ),

                    // User list
                    Expanded(
                      child: _users.isEmpty
                          ? const Center(
                              child: Text('No hay usuarios en este tenant'),
                            )
                          : ListView.builder(
                              itemCount: _users.length,
                              itemBuilder: (context, index) {
                                final user = _users[index];
                                return _buildUserCard(user);
                              },
                            ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildUserCard(Map<String, dynamic> user) {
    final email = user['email'] as String?;
    final role = user['role'] as String? ?? 'viewer';
    final isActive = user['is_active'] as bool? ?? true;
    final lastSignIn = user['last_sign_in'] as String?;
    final employeeName = user['employee_name'] as String?;
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    final isSelf = user['id'] == currentUserId;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isActive ? Colors.green : Colors.grey,
          child: Icon(
            _getRoleIcon(role),
            color: Colors.white,
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                email ?? 'Sin email',
                style: TextStyle(
                  decoration: isActive ? null : TextDecoration.lineThrough,
                ),
              ),
            ),
            if (isSelf)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.blue,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Tú',
                  style: TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Rol: ${_getRoleLabel(role)}'),
            if (employeeName != null)
              Text('Empleado: $employeeName', style: const TextStyle(fontSize: 12)),
            if (lastSignIn != null)
              Text(
                'Último acceso: ${_formatDate(lastSignIn)}',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            if (!isActive)
              const Text(
                'SUSPENDIDO',
                style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
              ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          onSelected: (value) async {
            switch (value) {
              case 'edit':
                _showEditDialog(user);
                break;
              case 'toggle_status':
                _toggleUserStatus(user['id'], isActive);
                break;
              case 'reset_password':
                await _userService.sendPasswordReset(email!);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Email de recuperación enviado'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
                break;
              case 'delete':
                _deleteUser(user['id'], email!);
                break;
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'edit',
              child: Row(
                children: [
                  Icon(Icons.edit, size: 20),
                  SizedBox(width: 8),
                  Text('Editar'),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'toggle_status',
              child: Row(
                children: [
                  Icon(
                    isActive ? Icons.block : Icons.check_circle,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(isActive ? 'Suspender' : 'Activar'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'reset_password',
              child: Row(
                children: [
                  Icon(Icons.lock_reset, size: 20),
                  SizedBox(width: 8),
                  Text('Resetear contraseña'),
                ],
              ),
            ),
            if (!isSelf)
              const PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete, size: 20, color: Colors.red),
                    SizedBox(width: 8),
                    Text('Eliminar', style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  IconData _getRoleIcon(String role) {
    switch (role) {
      case 'manager':
        return Icons.admin_panel_settings;
      case 'cashier':
        return Icons.point_of_sale;
      case 'mechanic':
        return Icons.build;
      case 'accountant':
        return Icons.account_balance;
      default:
        return Icons.person;
    }
  }

  String _getRoleLabel(String role) {
    switch (role) {
      case 'manager':
        return 'Gerente';
      case 'cashier':
        return 'Cajero';
      case 'mechanic':
        return 'Mecánico';
      case 'accountant':
        return 'Contador';
      default:
        return role;
    }
  }

  String _formatDate(String isoDate) {
    try {
      final date = DateTime.parse(isoDate);
      return DateFormat('dd/MM/yyyy HH:mm').format(date);
    } catch (e) {
      return isoDate;
    }
  }
}
