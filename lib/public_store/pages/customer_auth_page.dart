import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../services/customer_account_service.dart';
import '../theme/public_store_theme.dart';

class CustomerAuthPage extends StatefulWidget {
  const CustomerAuthPage({super.key});

  @override
  State<CustomerAuthPage> createState() => _CustomerAuthPageState();
}

class _CustomerAuthPageState extends State<CustomerAuthPage> {
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
      context.go('/tienda/cuenta');
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
      context.go('/tienda/cuenta');
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
    return Scaffold(
      appBar: AppBar(
        title: Text(_isLogin ? 'Iniciar Sesión' : 'Crear Cuenta'),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Center(
        child: SingleChildScrollView(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 450),
            padding: const EdgeInsets.all(24),
            child: Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                        if (_showVerificationNotice && _verificationEmail != null) ...[
                          Container(
                            margin: const EdgeInsets.only(bottom: 16),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: PublicStoreTheme.success.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Confirma tu correo',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Enviamos un correo a $_verificationEmail. Revisa tu bandeja de entrada y haz clic en el enlace para activar tu cuenta.',
                                  style: TextStyle(
                                    color: PublicStoreTheme.textSecondary,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                OutlinedButton.icon(
                                  onPressed: _isLoading
                                      ? null
                                      : () async {
                                          try {
                                            setState(() => _isLoading = true);
                                            await context
                                                .read<CustomerAccountService>()
                                                .resendVerificationEmail();
                                            if (mounted) {
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(
                                                const SnackBar(
                                                  content: Text(
                                                      'Hemos reenviado el correo de verificación.'),
                                                ),
                                              );
                                            }
                                          } catch (error) {
                                            if (mounted) {
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(
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
                                ),
                              ],
                            ),
                          ),
                        ],
                      // Logo/Title
                      Text(
                        _isLogin ? '¡Bienvenido!' : '¡Únete a Vinabike!',
                        style: Theme.of(context).textTheme.headlineSmall,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _isLogin
                            ? 'Ingresa a tu cuenta para continuar'
                            : 'Crea tu cuenta y disfruta de beneficios exclusivos',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: PublicStoreTheme.textSecondary,
                            ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 32),

                      // Name field (only for signup)
                      if (!_isLogin) ...[
                        TextFormField(
                          controller: _nameController,
                          decoration: const InputDecoration(
                            labelText: 'Nombre completo',
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

                      // Email field
                      TextFormField(
                        controller: _emailController,
                        decoration: const InputDecoration(
                          labelText: 'Correo electrónico',
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

                      // Phone field (only for signup)
                      if (!_isLogin) ...[
                        TextFormField(
                          controller: _phoneController,
                          decoration: const InputDecoration(
                            labelText: 'Teléfono (opcional)',
                            prefixIcon: Icon(Icons.phone_outlined),
                            hintText: '+56 9 1234 5678',
                          ),
                          keyboardType: TextInputType.phone,
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Password field
                      TextFormField(
                        controller: _passwordController,
                        decoration: InputDecoration(
                          labelText: 'Contraseña',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            icon: Icon(_obscurePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined),
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
                      const SizedBox(height: 24),

                      // Submit button
                      FilledButton(
                        onPressed: _isLoading ? null : _submit,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Text(
                                _isLogin ? 'INICIAR SESIÓN' : 'CREAR CUENTA',
                                style: const TextStyle(fontSize: 16),
                              ),
                      ),
                      const SizedBox(height: 16),

                      // Divider
                      Row(
                        children: [
                          const Expanded(child: Divider()),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Text(
                              'O',
                              style: TextStyle(color: PublicStoreTheme.textSecondary),
                            ),
                          ),
                          const Expanded(child: Divider()),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Google sign in button
                      OutlinedButton.icon(
                        onPressed: _isLoading ? null : _signInWithGoogle,
                        icon: Image.network(
                          'https://www.gstatic.com/firebasejs/ui/2.0.0/images/auth/google.svg',
                          height: 20,
                        ),
                        label: Text(_isLogin
                            ? 'Continuar con Google'
                            : 'Registrarse con Google'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Toggle login/signup
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _isLogin
                                ? '¿No tienes cuenta?'
                                : '¿Ya tienes cuenta?',
                            style: TextStyle(color: PublicStoreTheme.textSecondary),
                          ),
                          TextButton(
                            onPressed: () {
                              setState(() {
                                _isLogin = !_isLogin;
                                _formKey.currentState?.reset();
                              });
                            },
                            child: Text(_isLogin ? 'Regístrate' : 'Inicia sesión'),
                          ),
                        ],
                      ),

                      // Forgot password (only in login mode)
                      if (_isLogin)
                        TextButton(
                          onPressed: () {
                            // TODO: Implement forgot password dialog
                            showDialog(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('Recuperar Contraseña'),
                                content: const Text(
                                  'Funcionalidad próximamente disponible',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context),
                                    child: const Text('OK'),
                                  ),
                                ],
                              ),
                            );
                          },
                          child: const Text('¿Olvidaste tu contraseña?'),
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
