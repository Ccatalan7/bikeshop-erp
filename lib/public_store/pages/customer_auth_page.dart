import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../services/customer_account_service.dart';
import '../providers/public_store_tenant_provider.dart';
import '../theme/public_store_theme.dart';

class CustomerAuthPage extends StatefulWidget {
  const CustomerAuthPage({super.key});

  @override
  State<CustomerAuthPage> createState() => _CustomerAuthPageState();
}

class _CustomerAuthPageState extends State<CustomerAuthPage>
    with AutomaticKeepAliveClientMixin {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _phoneController = TextEditingController();

  bool _isLogin = true;
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _showVerificationNotice = false;
  String? _verificationEmail;

  // Keep this page alive in memory to prevent reloading on navigation
  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final accountService = context.read<CustomerAccountService>();

      // CRITICAL: Set tenant_id before any auth operations
      final tenantProvider = context.read<PublicStoreTenantProvider>();
      accountService.setTenantId(tenantProvider.tenantId);

      if (_isLogin) {
        await accountService.signIn(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
        _showVerificationNotice = false;
        _verificationEmail = null;
      } else {
        final result = await accountService.signUp(
          email: _emailController.text.trim(),
          password: _passwordController.text,
          name: _nameController.text.trim(),
          phone: _phoneController.text.trim().isNotEmpty
              ? _phoneController.text.trim()
              : null,
        );

        if (result == CustomerAuthResult.emailVerificationRequired) {
          _verificationEmail = accountService.pendingVerificationEmail;
          _showVerificationNotice = true;
          _isLogin = true;
          _passwordController.clear();
          setState(() {});
          if (!mounted) return;

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Te enviamos un correo a ${_verificationEmail ?? _emailController.text.trim()} para confirmar tu cuenta.',
              ),
            ),
          );

          return;
        } else {
          _showVerificationNotice = false;
          _verificationEmail = null;
        }
      }

      if (!mounted) return;

      // Navigate to account page or back
      context.go('/cuenta');
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isLogin
              ? 'Error al iniciar sesión: $e'
              : 'Error al crear cuenta: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _signInWithGoogle() async {
    try {
      final accountService = context.read<CustomerAccountService>();
      await accountService.signInWithGoogle();

      if (!mounted) return;
      context.go('/cuenta');
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error con Google: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    return Container(
      width: double.infinity,
      color: Colors.white,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 900;

          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(24, isWide ? 44 : 28, 24, 56),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1040),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: PublicStoreTheme.border.withValues(alpha: 0.9),
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x12000000),
                        blurRadius: 28,
                        offset: Offset(0, 14),
                      ),
                    ],
                  ),
                  child: isWide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: _buildIntroPanel(context)),
                            Expanded(child: _buildFormPanel(context)),
                          ],
                        )
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildIntroPanel(context, compact: true),
                            _buildFormPanel(context),
                          ],
                        ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildIntroPanel(BuildContext context, {bool compact = false}) {
    final theme = Theme.of(context);

    return Container(
      padding:
          EdgeInsets.fromLTRB(28, compact ? 28 : 36, 28, compact ? 24 : 36),
      decoration: BoxDecoration(
        color: compact ? Colors.white : PublicStoreTheme.surface,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(24),
          bottomLeft: compact ? Radius.zero : const Radius.circular(24),
          topRight: compact ? const Radius.circular(24) : Radius.zero,
        ),
        border: compact
            ? Border(
                bottom: BorderSide(
                  color: PublicStoreTheme.border.withValues(alpha: 0.75),
                ),
              )
            : Border(
                right: BorderSide(
                  color: PublicStoreTheme.border.withValues(alpha: 0.75),
                ),
              ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'CUENTA VINABIKE',
            style: theme.textTheme.labelMedium?.copyWith(
              color: PublicStoreTheme.textSecondary,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            _isLogin
                ? 'Ingresa para revisar pedidos, bicicletas y soporte desde un solo lugar.'
                : 'Crea tu cuenta para guardar tus datos, seguir tus pedidos y acceder a tu historial.',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontSize: compact ? 28 : 32,
              height: 1.15,
              color: PublicStoreTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            _isLogin
                ? 'Una experiencia más ordenada, rápida y clara que el checkout improvisado de invitado.'
                : 'Todo queda asociado a tu cuenta para futuras compras, seguimiento y atención postventa.',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: PublicStoreTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 28),
          _buildBenefitRow(
            icon: Icons.shopping_bag_outlined,
            title: 'Pedidos y seguimiento',
            subtitle:
                'Consulta compras, estados y confirmaciones en un solo panel.',
          ),
          const SizedBox(height: 16),
          _buildBenefitRow(
            icon: Icons.pedal_bike_outlined,
            title: 'Historial de bicicletas',
            subtitle:
                'Accede a tus bicicletas registradas y próximos servicios.',
          ),
          const SizedBox(height: 16),
          _buildBenefitRow(
            icon: Icons.support_agent_outlined,
            title: 'Atención más rápida',
            subtitle:
                'Mantén tus datos listos para soporte, mensajes y futuras compras.',
          ),
          if (!compact) ...[
            const SizedBox(height: 28),
            TextButton.icon(
              onPressed: () => context.go('/'),
              icon: const Icon(Icons.arrow_back, size: 18),
              label: const Text('Volver al inicio'),
              style: TextButton.styleFrom(
                foregroundColor: PublicStoreTheme.textPrimary,
                padding: EdgeInsets.zero,
                textStyle: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBenefitRow({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: PublicStoreTheme.border.withValues(alpha: 0.85),
            ),
          ),
          child: Icon(
            icon,
            size: 20,
            color: PublicStoreTheme.textPrimary,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: PublicStoreTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.45,
                  color: PublicStoreTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFormPanel(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 30, 28, 30),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _isLogin ? 'Iniciar sesión' : 'Crear cuenta',
              style: theme.textTheme.headlineSmall?.copyWith(
                color: PublicStoreTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _isLogin
                  ? 'Usa tu correo y contraseña para continuar.'
                  : 'Completa tus datos para guardar tus compras e historial.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: PublicStoreTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 24),
            if (_showVerificationNotice && _verificationEmail != null) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 20),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: PublicStoreTheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: PublicStoreTheme.border.withValues(alpha: 0.85),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Confirma tu correo',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: PublicStoreTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Enviamos un correo a $_verificationEmail. Revisa tu bandeja de entrada y activa tu cuenta desde el enlace recibido.',
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.45,
                        color: PublicStoreTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 14),
                    OutlinedButton.icon(
                      onPressed: _isLoading
                          ? null
                          : () async {
                              final messenger = ScaffoldMessenger.of(context);
                              final accountService =
                                  context.read<CustomerAccountService>();
                              try {
                                setState(() => _isLoading = true);
                                await accountService.resendVerificationEmail();
                                if (mounted) {
                                  messenger.showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Hemos reenviado el correo de verificación.',
                                      ),
                                    ),
                                  );
                                }
                              } catch (error) {
                                if (mounted) {
                                  messenger.showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'No pudimos reenviar el correo: $error',
                                      ),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                }
                              } finally {
                                if (mounted) {
                                  setState(() => _isLoading = false);
                                }
                              }
                            },
                      icon: const Icon(Icons.mark_email_unread_outlined),
                      label: const Text('Reenviar correo'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: PublicStoreTheme.textPrimary,
                        side: BorderSide(
                          color: PublicStoreTheme.border.withValues(alpha: 0.9),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 14,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (!_isLogin) ...[
              _buildFieldLabel('Nombre completo'),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  hintText: 'Tu nombre y apellido',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'El nombre es requerido';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
            ],
            _buildFieldLabel('Correo electrónico'),
            TextFormField(
              controller: _emailController,
              decoration: const InputDecoration(
                hintText: 'nombre@correo.com',
                prefixIcon: Icon(Icons.email_outlined),
              ),
              keyboardType: TextInputType.emailAddress,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'El correo es requerido';
                }
                if (!value.contains('@')) {
                  return 'Ingresa un correo válido';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            if (!_isLogin) ...[
              _buildFieldLabel('Teléfono'),
              TextFormField(
                controller: _phoneController,
                decoration: const InputDecoration(
                  hintText: '+56 9 1234 5678',
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 16),
            ],
            _buildFieldLabel('Contraseña'),
            TextFormField(
              controller: _passwordController,
              decoration: InputDecoration(
                hintText: _isLogin ? 'Tu contraseña' : 'Mínimo 6 caracteres',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                  onPressed: () {
                    setState(() => _obscurePassword = !_obscurePassword);
                  },
                ),
              ),
              obscureText: _obscurePassword,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'La contraseña es requerida';
                }
                if (!_isLogin && value.length < 6) {
                  return 'Mínimo 6 caracteres';
                }
                return null;
              },
            ),
            const SizedBox(height: 22),
            FilledButton(
              onPressed: _isLoading ? null : _submit,
              style: FilledButton.styleFrom(
                backgroundColor: PublicStoreTheme.textPrimary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                textStyle: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.15,
                ),
              ),
              child: _isLoading
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(_isLogin ? 'INICIAR SESIÓN' : 'CREAR CUENTA'),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: Container(
                    height: 1,
                    color: PublicStoreTheme.border.withValues(alpha: 0.9),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Text(
                    'o continúa con',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: PublicStoreTheme.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Expanded(
                  child: Container(
                    height: 1,
                    color: PublicStoreTheme.border.withValues(alpha: 0.9),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: _isLoading ? null : _signInWithGoogle,
              icon: const FaIcon(
                FontAwesomeIcons.google,
                size: 16,
                color: PublicStoreTheme.textPrimary,
              ),
              label: Text(
                _isLogin ? 'Continuar con Google' : 'Registrarse con Google',
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: PublicStoreTheme.textPrimary,
                backgroundColor: Colors.white,
                side: BorderSide(
                  color: PublicStoreTheme.border.withValues(alpha: 0.9),
                ),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                textStyle: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 22),
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 4,
              runSpacing: 4,
              children: [
                Text(
                  _isLogin ? '¿No tienes cuenta?' : '¿Ya tienes cuenta?',
                  style: const TextStyle(
                    color: PublicStoreTheme.textSecondary,
                    fontSize: 13,
                  ),
                ),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _isLogin = !_isLogin;
                      _formKey.currentState?.reset();
                    });
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: PublicStoreTheme.textPrimary,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  child: Text(_isLogin ? 'Regístrate' : 'Inicia sesión'),
                ),
              ],
            ),
            if (_isLogin)
              Align(
                alignment: Alignment.center,
                child: TextButton(
                  onPressed: _showPasswordResetDialog,
                  style: TextButton.styleFrom(
                    foregroundColor: PublicStoreTheme.textSecondary,
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  child: const Text('¿Olvidaste tu contraseña?'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFieldLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: PublicStoreTheme.textPrimary,
        ),
      ),
    );
  }

  Future<void> _showPasswordResetDialog() async {
    final emailController = TextEditingController(
      text: _emailController.text.trim(),
    );
    final formKey = GlobalKey<FormState>();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Recuperar contraseña'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Ingresa tu correo y enviaremos un enlace seguro para restablecer el acceso.',
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Correo electrónico',
                  prefixIcon: Icon(Icons.email_outlined),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'El correo es requerido';
                  }
                  if (!value.contains('@')) {
                    return 'Ingresa un correo válido';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              final messenger = ScaffoldMessenger.of(context);
              try {
                await context
                    .read<CustomerAccountService>()
                    .resetPassword(emailController.text.trim());
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Revisa tu correo para continuar con la recuperación.',
                    ),
                  ),
                );
              } catch (error) {
                messenger.showSnackBar(
                  SnackBar(
                    content: Text('No pudimos enviar el correo: $error'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text('Enviar enlace'),
          ),
        ],
      ),
    );

    emailController.dispose();
  }
}
