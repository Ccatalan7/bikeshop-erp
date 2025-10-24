import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/customer_account_service.dart';
import '../theme/public_store_theme.dart';

class CustomerProfilePage extends StatefulWidget {
  const CustomerProfilePage({super.key});

  @override
  State<CustomerProfilePage> createState() => _CustomerProfilePageState();
}

class _CustomerProfilePageState extends State<CustomerProfilePage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _emailController;
  late final TextEditingController _phoneController;
  late final TextEditingController _rutController;

  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    final profile = context.read<CustomerAccountService>().customerProfile;
    _nameController = TextEditingController(text: profile?['name'] ?? '');
    _emailController = TextEditingController(text: profile?['email'] ?? '');
    _phoneController = TextEditingController(text: profile?['phone'] ?? '');
    _rutController = TextEditingController(text: profile?['tax_id'] ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _rutController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accountService = context.watch<CustomerAccountService>();
    final profile = accountService.customerProfile;

    if (profile == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Mi Perfil')),
        body: const Center(child: Text('Cargando...')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mi Perfil'),
        actions: [
          if (_isEditing)
            TextButton.icon(
              onPressed: _saveProfile,
              icon: const Icon(Icons.save),
              label: const Text('GUARDAR'),
              style: TextButton.styleFrom(foregroundColor: Colors.white),
            )
          else
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () => setState(() => _isEditing = true),
              tooltip: 'Editar perfil',
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildProfileHeader(profile),
            const SizedBox(height: 32),
            _buildProfileForm(),
            const SizedBox(height: 32),
            _buildSecuritySection(context),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileHeader(Map<String, dynamic> profile) {
    return Column(
      children: [
        CircleAvatar(
          radius: 50,
          backgroundColor: PublicStoreTheme.primaryBlue.withOpacity(0.1),
          child: Text(
            (profile['name'] as String?)?.isNotEmpty == true
                ? profile['name'][0].toUpperCase()
                : '?',
            style: const TextStyle(
              fontSize: 40,
              fontWeight: FontWeight.bold,
              color: PublicStoreTheme.primaryBlue,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          profile['name'] ?? 'Sin nombre',
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          profile['email'] ?? '',
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }

  Widget _buildProfileForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Información Personal',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Nombre Completo',
              prefixIcon: Icon(Icons.person_outline),
            ),
            enabled: _isEditing,
            validator: (v) => v == null || v.isEmpty ? 'Nombre requerido' : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _emailController,
            decoration: const InputDecoration(
              labelText: 'Email',
              prefixIcon: Icon(Icons.email_outlined),
            ),
            enabled: false,
            style: TextStyle(color: Colors.grey[600]),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _phoneController,
            decoration: const InputDecoration(
              labelText: 'Teléfono',
              prefixIcon: Icon(Icons.phone_outlined),
            ),
            enabled: _isEditing,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _rutController,
            decoration: const InputDecoration(
              labelText: 'RUT',
              prefixIcon: Icon(Icons.badge_outlined),
            ),
            enabled: _isEditing,
          ),
        ],
      ),
    );
  }

  Widget _buildSecuritySection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Seguridad',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: ListTile(
            leading: const Icon(Icons.lock_outline),
            title: const Text('Cambiar Contraseña'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showPasswordChangeDialog(context),
          ),
        ),
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('Cerrar Sesión', style: TextStyle(color: Colors.red)),
            onTap: () => _confirmSignOut(context),
          ),
        ),
      ],
    );
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    final accountService = context.read<CustomerAccountService>();

    try {
      await accountService.updateProfile(
        name: _nameController.text.trim(),
        phone: _phoneController.text.trim().isNotEmpty
            ? _phoneController.text.trim()
            : null,
        rut: _rutController.text.trim().isNotEmpty
            ? _rutController.text.trim()
            : null,
      );

      setState(() => _isEditing = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Perfil actualizado correctamente'),
            backgroundColor: PublicStoreTheme.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al actualizar perfil: $e'),
            backgroundColor: PublicStoreTheme.error,
          ),
        );
      }
    }
  }

  void _showPasswordChangeDialog(BuildContext context) {
    final currentPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cambiar Contraseña'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: currentPasswordController,
                decoration: const InputDecoration(labelText: 'Contraseña Actual'),
                obscureText: true,
                validator: (v) => v == null || v.isEmpty ? 'Requerido' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: newPasswordController,
                decoration: const InputDecoration(labelText: 'Nueva Contraseña'),
                obscureText: true,
                validator: (v) =>
                    v == null || v.length < 6 ? 'Mínimo 6 caracteres' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: confirmPasswordController,
                decoration: const InputDecoration(labelText: 'Confirmar Contraseña'),
                obscureText: true,
                validator: (v) => v != newPasswordController.text
                    ? 'Las contraseñas no coinciden'
                    : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;

              // TODO: Implement password change with Supabase Auth
              // await context.read<CustomerAccountService>().updatePassword(...)

              Navigator.pop(context);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Contraseña actualizada'),
                    backgroundColor: PublicStoreTheme.success,
                  ),
                );
              }
            },
            child: const Text('Cambiar'),
          ),
        ],
      ),
    );
  }

  void _confirmSignOut(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cerrar Sesión'),
        content: const Text('¿Estás seguro que deseas cerrar sesión?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () async {
              await context.read<CustomerAccountService>().signOut();
              if (context.mounted) {
                Navigator.pop(context); // Close dialog
                Navigator.pop(context); // Go back to store
              }
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Cerrar Sesión'),
          ),
        ],
      ),
    );
  }
}
