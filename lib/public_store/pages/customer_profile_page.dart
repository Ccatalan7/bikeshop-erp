import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/customer_account_service.dart';
import '../theme/public_store_theme.dart';
import '../widgets/customer_portal_layout.dart';
import '../../shared/utils/auth_input_validation.dart';

class CustomerProfilePage extends StatefulWidget {
  const CustomerProfilePage({super.key});

  @override
  State<CustomerProfilePage> createState() => _CustomerProfilePageState();
}

class _CustomerProfilePageState extends State<CustomerProfilePage>
    with AutomaticKeepAliveClientMixin {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _emailController;
  late final TextEditingController _phoneController;
  late final TextEditingController _rutController;

  bool _isEditing = false;
  bool _isLoading = false;

  // Keep this page alive in memory to prevent reloading on navigation
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    final profile = context.read<CustomerAccountService>().customerProfile;
    _nameController = TextEditingController(text: profile?['name'] ?? '');
    _emailController = TextEditingController(text: profile?['email'] ?? '');
    _phoneController = TextEditingController(text: profile?['phone'] ?? '');
    _rutController = TextEditingController(text: profile?['rut'] ?? '');
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
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    final accountService = context.watch<CustomerAccountService>();
    final profile = accountService.customerProfile;

    if (profile == null) {
      return const CustomerPortalLayout(
        title: 'Mi Perfil',
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return CustomerPortalLayout(
      title: 'Mi Perfil',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildIdentityCard(profile),
          const SizedBox(height: 20),
          _buildProfileForm(),
          const SizedBox(height: 20),
          _buildSecuritySection(context),
        ],
      ),
    );
  }

  Widget _buildIdentityCard(Map<String, dynamic> profile) {
    final name = (profile['name'] ?? 'Sin nombre').toString();
    final email = (profile['email'] ?? '').toString();
    final initial = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : 'C';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE0E4EA)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 560;
          final identity = Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor:
                    PublicStoreTheme.primaryBlue.withValues(alpha: 0.1),
                child: Text(
                  initial,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: PublicStoreTheme.primaryBlue,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF18212F),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF667085),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
          final action = _isEditing
              ? FilledButton.icon(
                  onPressed: _isLoading ? null : _saveProfile,
                  icon: _isLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.check, size: 18),
                  label: const Text('Guardar cambios'),
                )
              : FilledButton.icon(
                  onPressed: () => setState(() => _isEditing = true),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Editar datos'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF102A43),
                    foregroundColor: Colors.white,
                  ),
                );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [identity, const SizedBox(height: 14), action],
            );
          }
          return Row(
            children: [
              Expanded(child: identity),
              const SizedBox(width: 14),
              action,
            ],
          );
        },
      ),
    );
  }

  Widget _buildProfileForm() {
    return Form(
      key: _formKey,
      child: _ProfileSection(
        title: 'Datos personales',
        description:
            'Usamos esta información para preparar pedidos, boletas y soporte. Tu email queda bloqueado porque es tu acceso seguro.',
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 620;
            final fields = [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Nombre completo',
                  border: OutlineInputBorder(),
                ),
                enabled: _isEditing,
                validator: (v) =>
                    v == null || v.isEmpty ? 'Nombre requerido' : null,
              ),
              TextFormField(
                controller: _rutController,
                decoration: const InputDecoration(
                  labelText: 'RUT',
                  border: OutlineInputBorder(),
                ),
                enabled: _isEditing,
              ),
              TextFormField(
                controller: _emailController,
                decoration: const InputDecoration(
                  labelText: 'Email de acceso',
                  border: OutlineInputBorder(),
                  filled: true,
                ),
                enabled: false,
                style: const TextStyle(color: Color(0xFF667085)),
              ),
              TextFormField(
                controller: _phoneController,
                decoration: const InputDecoration(
                  labelText: 'Teléfono',
                  border: OutlineInputBorder(),
                ),
                enabled: _isEditing,
              ),
            ];

            if (compact) {
              return Column(
                children: fields
                    .map((field) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: field,
                        ))
                    .toList(),
              );
            }

            return Column(
              children: [
                Row(children: [
                  Expanded(child: fields[0]),
                  const SizedBox(width: 14),
                  Expanded(child: fields[1])
                ]),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(child: fields[2]),
                  const SizedBox(width: 14),
                  Expanded(child: fields[3])
                ]),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildSecuritySection(BuildContext context) {
    return _ProfileSection(
      title: 'Seguridad',
      description:
          'Mantén tu cuenta protegida. Los cambios de contraseña se aplican a tu acceso web.',
      child: Material(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => _showPasswordChangeDialog(context),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE0E4EA)),
                  ),
                  child:
                      const Icon(Icons.lock_outline, color: Color(0xFF102A43)),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Contraseña',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Cambiar tu contraseña de acceso',
                        style: TextStyle(
                          color: Color(0xFF667085),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: Color(0xFF667085)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

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

      setState(() {
        _isEditing = false;
        _isLoading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Perfil actualizado correctamente'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No pudimos actualizar el perfil. Inténtalo nuevamente.',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showPasswordChangeDialog(BuildContext context) {
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cambiar contraseña'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Actualizaremos la contraseña de tu cuenta de forma segura para futuros accesos.',
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: newPasswordController,
                decoration: const InputDecoration(
                  labelText: 'Nueva contraseña',
                  helperText: AuthInputValidation.strongPasswordHelper,
                ),
                obscureText: true,
                validator: (value) => AuthInputValidation.validatePassword(
                  value,
                  isNewPassword: true,
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: confirmPasswordController,
                decoration:
                    const InputDecoration(labelText: 'Confirmar contraseña'),
                obscureText: true,
                validator: (value) =>
                    AuthInputValidation.validatePasswordConfirmation(
                  value,
                  password: newPasswordController.text,
                ),
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
              if (formKey.currentState!.validate()) {
                final messenger = ScaffoldMessenger.of(context);
                try {
                  await context
                      .read<CustomerAccountService>()
                      .updatePassword(newPasswordController.text);
                  if (context.mounted) Navigator.pop(context);
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text('Contraseña actualizada correctamente'),
                      backgroundColor: Colors.green,
                    ),
                  );
                } catch (_) {
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text(
                        'No pudimos actualizar la contraseña. Inténtalo nuevamente.',
                      ),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: const Text('Cambiar'),
          ),
        ],
      ),
    );
  }
}

class _ProfileSection extends StatelessWidget {
  final String title;
  final String description;
  final Widget child;

  const _ProfileSection({
    required this.title,
    required this.description,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE0E4EA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF18212F),
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            description,
            style: const TextStyle(
              color: Color(0xFF667085),
              fontSize: 13,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}
