import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../shared/services/user_management_service.dart';
import '../../../shared/widgets/app_button.dart';

class UserEditDialog extends StatefulWidget {
  final Map<String, dynamic> user;

  const UserEditDialog({super.key, required this.user});

  @override
  State<UserEditDialog> createState() => _UserEditDialogState();
}

class _UserEditDialogState extends State<UserEditDialog> {
  late String _selectedRole;
  late Map<String, bool> _permissions;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _selectedRole = widget.user['role'] as String? ?? 'cashier';
    
    // Parse permissions from user data
    final permsData = widget.user['permissions'];
    if (permsData is Map) {
      _permissions = Map<String, bool>.from(permsData);
    } else {
      _permissions = _getDefaultPermissions(_selectedRole);
    }
  }

  Map<String, bool> _getDefaultPermissions(String role) {
    switch (role) {
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
      case 'mechanic':
        return {
          'access_pos': false,
          'create_invoices': false,
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
      default:
        return {};
    }
  }

  void _updatePermissionsForRole(String role) {
    setState(() {
      _permissions = _getDefaultPermissions(role);
    });
  }

  Future<void> _saveChanges() async {
    setState(() => _isLoading = true);

    try {
      final userService = context.read<UserManagementService>();
      
      await userService.updateUserRole(
        userId: widget.user['id'],
        newRole: _selectedRole,
        newPermissions: _permissions,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Usuario actualizado exitosamente'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = widget.user['email'] as String? ?? 'Sin email';
    final employeeName = widget.user['employee_name'] as String?;

    return AlertDialog(
      title: Text('Editar Usuario: $email'),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Email (read-only)
              TextField(
                controller: TextEditingController(text: email),
                decoration: const InputDecoration(
                  labelText: 'Email',
                  prefixIcon: Icon(Icons.email),
                  suffixIcon: Icon(Icons.verified, color: Colors.green),
                ),
                enabled: false,
              ),
              
              const SizedBox(height: 16),
              
              // Employee link (if any)
              if (employeeName != null) ...[
                TextField(
                  controller: TextEditingController(text: employeeName),
                  decoration: const InputDecoration(
                    labelText: 'Empleado Vinculado',
                    prefixIcon: Icon(Icons.person),
                  ),
                  enabled: false,
                ),
                const SizedBox(height: 16),
              ],
              
              // Role selector
              DropdownButtonFormField<String>(
                value: _selectedRole,
                decoration: const InputDecoration(
                  labelText: 'Rol',
                  prefixIcon: Icon(Icons.badge),
                ),
                items: const [
                  DropdownMenuItem(value: 'manager', child: Text('Gerente')),
                  DropdownMenuItem(value: 'cashier', child: Text('Cajero')),
                  DropdownMenuItem(value: 'mechanic', child: Text('Mecánico')),
                  DropdownMenuItem(value: 'accountant', child: Text('Contador')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _selectedRole = value);
                    _updatePermissionsForRole(value);
                  }
                },
              ),
              
              const SizedBox(height: 24),
              const Text(
                'Permisos',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const Divider(),
              
              // Permissions section
              _buildSection(
                'Ventas & POS',
                [
                  _buildPermissionCheckbox(
                    'access_pos',
                    'Acceso a POS',
                    Icons.point_of_sale,
                  ),
                  _buildPermissionCheckbox(
                    'create_invoices',
                    'Crear Facturas',
                    Icons.receipt,
                  ),
                  _buildPermissionCheckbox(
                    'edit_prices',
                    'Editar Precios',
                    Icons.attach_money,
                  ),
                  _buildPermissionCheckbox(
                    'delete_invoices',
                    'Eliminar Facturas',
                    Icons.delete,
                  ),
                ],
              ),
              
              const SizedBox(height: 16),
              
              _buildSection(
                'Administración',
                [
                  _buildPermissionCheckbox(
                    'access_accounting',
                    'Acceso a Contabilidad',
                    Icons.account_balance,
                  ),
                  _buildPermissionCheckbox(
                    'manage_users',
                    'Gestionar Usuarios',
                    Icons.people,
                  ),
                  _buildPermissionCheckbox(
                    'edit_settings',
                    'Editar Configuración',
                    Icons.settings,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        AppButton(
          text: 'Guardar Cambios',
          onPressed: _isLoading ? null : _saveChanges,
          isLoading: _isLoading,
        ),
      ],
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 4),
        ...children,
      ],
    );
  }

  Widget _buildPermissionCheckbox(String key, String label, IconData icon) {
    return CheckboxListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey.shade600),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontSize: 14)),
        ],
      ),
      value: _permissions[key] ?? false,
      onChanged: (value) {
        setState(() {
          _permissions[key] = value ?? false;
        });
      },
    );
  }
}
