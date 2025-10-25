import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../shared/services/user_management_service.dart';
import '../../../shared/widgets/app_button.dart';

class UserInviteDialog extends StatefulWidget {
  const UserInviteDialog({super.key});

  @override
  State<UserInviteDialog> createState() => _UserInviteDialogState();
}

class _UserInviteDialogState extends State<UserInviteDialog> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  
  String _selectedRole = 'cashier';
  bool _isLoading = false;
  
  final Map<String, bool> _permissions = {
    'access_pos': true,
    'create_invoices': true,
    'edit_prices': false,
    'delete_invoices': false,
    'access_accounting': false,
    'manage_users': false,
    'edit_settings': false,
  };

  @override
  void initState() {
    super.initState();
    _updatePermissionsForRole(_selectedRole);
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  void _updatePermissionsForRole(String role) {
    setState(() {
      switch (role) {
        case 'manager':
          _permissions['access_pos'] = true;
          _permissions['create_invoices'] = true;
          _permissions['edit_prices'] = true;
          _permissions['delete_invoices'] = true;
          _permissions['access_accounting'] = true;
          _permissions['manage_users'] = true;
          _permissions['edit_settings'] = true;
          break;
        case 'cashier':
          _permissions['access_pos'] = true;
          _permissions['create_invoices'] = true;
          _permissions['edit_prices'] = false;
          _permissions['delete_invoices'] = false;
          _permissions['access_accounting'] = false;
          _permissions['manage_users'] = false;
          _permissions['edit_settings'] = false;
          break;
        case 'mechanic':
          _permissions['access_pos'] = false;
          _permissions['create_invoices'] = false;
          _permissions['edit_prices'] = false;
          _permissions['delete_invoices'] = false;
          _permissions['access_accounting'] = false;
          _permissions['manage_users'] = false;
          _permissions['edit_settings'] = false;
          break;
        case 'accountant':
          _permissions['access_pos'] = false;
          _permissions['create_invoices'] = false;
          _permissions['edit_prices'] = false;
          _permissions['delete_invoices'] = false;
          _permissions['access_accounting'] = true;
          _permissions['manage_users'] = false;
          _permissions['edit_settings'] = false;
          break;
      }
    });
  }

  Future<void> _inviteUser() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final userService = context.read<UserManagementService>();
      
      await userService.inviteUser(
        email: _emailController.text.trim(),
        role: _selectedRole,
        permissions: _permissions,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Invitación enviada exitosamente'),
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
    return AlertDialog(
      title: const Text('Invitar Usuario'),
      content: SizedBox(
        width: 500,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Email field
                TextFormField(
                  controller: _emailController,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    hintText: 'usuario@ejemplo.com',
                    prefixIcon: Icon(Icons.email),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Por favor ingresa un email';
                    }
                    if (!value.contains('@')) {
                      return 'Email inválido';
                    }
                    return null;
                  },
                ),
                
                const SizedBox(height: 16),
                
                // Role selector
                DropdownButtonFormField<String>(
                  value: _selectedRole,
                  decoration: const InputDecoration(
                    labelText: 'Rol',
                    prefixIcon: Icon(Icons.person),
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
                
                // Permissions checkboxes
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
                
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.blue.shade700),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'El usuario recibirá un email con instrucciones para crear su cuenta.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.blue.shade900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        AppButton(
          text: 'Enviar Invitación',
          onPressed: _isLoading ? null : _inviteUser,
          isLoading: _isLoading,
        ),
      ],
    );
  }

  Widget _buildPermissionCheckbox(String key, String label, IconData icon) {
    return CheckboxListTile(
      dense: true,
      title: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey.shade600),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontSize: 14)),
        ],
      ),
      value: _permissions[key],
      onChanged: (value) {
        setState(() {
          _permissions[key] = value ?? false;
        });
      },
    );
  }
}
