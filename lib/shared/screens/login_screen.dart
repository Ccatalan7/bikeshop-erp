import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auth_service.dart';
import '../utils/auth_input_validation.dart';
import '../widgets/app_button.dart';
import '../widgets/forgot_password_dialog.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _shopNameController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _isRegisterMode = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handleAccessDeniedSession();
    });
  }

  Future<void> _handleAccessDeniedSession() async {
    if (Uri.base.queryParameters['error'] != 'access_denied' || !mounted) {
      return;
    }

    final authService = context.read<AuthService>();
    final hasUnassignedSession = authService.currentSession != null &&
        authService.isAccessProfileLoaded &&
        !authService.isStaff &&
        !authService.isWorker;

    if (hasUnassignedSession) {
      setState(() => _isLoading = true);
      var sessionCleared = false;
      try {
        // Google may authenticate an identity that has no active ERP/worker
        // membership. Clear it before allowing another login or owner signup.
        await authService.signOut();
        sessionCleared = true;
      } catch (_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No pudimos cerrar la sesión sin acceso. Recarga la aplicación antes de intentarlo nuevamente.',
            ),
            backgroundColor: Colors.red,
          ),
        );
        return;
      } finally {
        if (mounted && sessionCleared) {
          setState(() => _isLoading = false);
        }
      }
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Acceso denegado. Usa una cuenta que tenga acceso activo al ERP.',
        ),
        backgroundColor: Colors.red,
        duration: Duration(seconds: 5),
      ),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _shopNameController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      await authService.signInWithEmailAndPassword(
        _emailController.text.trim(),
        _passwordController.text,
      );

      if (mounted) {
        context.go('/dashboard');
      }
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_mapSupabaseError(e)),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No pudimos iniciar sesión. Revisa tus datos e inténtalo nuevamente.',
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
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    if (_passwordController.text != _confirmPasswordController.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Las contraseñas no coinciden'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final authService = context.read<AuthService>();
      final shopName = _shopNameController.text.trim();

      // Auth signup is the only client write. The database trigger owns the
      // tenant, staff profile, role metadata, and initial tenant data.
      final response = await authService.signUpTenantOwner(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        shopName: shopName,
        subdomain: AuthInputValidation.tenantSubdomain(shopName),
      );

      final user = response.user;
      if (user == null) {
        throw Exception(
            'Error al crear la cuenta. Por favor intente con otro correo.');
      }

      final session = response.session;
      if (session == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '📧 Confirma tu correo electrónico',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  Text('Te enviamos un correo a: ${_emailController.text}'),
                  const SizedBox(height: 4),
                  const Text(
                      'Por favor, haz clic en el enlace de confirmación.'),
                  const SizedBox(height: 4),
                  const Text(
                    'Tu tienda se preparará cuando confirmes el correo. Después podrás iniciar sesión.',
                  ),
                ],
              ),
              backgroundColor: Colors.blue,
              duration: const Duration(seconds: 8),
            ),
          );

          // Return to login mode
          setState(() {
            _isRegisterMode = false;
            _emailController.clear();
            _passwordController.clear();
            _confirmPasswordController.clear();
            _shopNameController.clear();
          });
        }
        return;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '🎉 ¡Cuenta creada exitosamente!',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 8),
                Text('🏪 Tu tienda: $shopName'),
              ],
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 6),
          ),
        );

        // Navigate to dashboard
        context.go('/dashboard');
      }
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_mapSupabaseError(e)),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No pudimos crear la cuenta con estos datos. Inténtalo nuevamente.',
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
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _isLoading = true);

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      await authService.signInWithGoogle();

      // For web, OAuth opens in new tab/window and redirects back
      // For desktop, OAuth opens in browser
      // The auth state listener will handle navigation automatically
      // No need to manually navigate here - just show loading state

      if (kIsWeb) {
        // On web, show message that redirect is happening
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Redirigiendo a Google...'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    } on AuthException {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No pudimos iniciar sesión con Google. Inténtalo nuevamente.',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No pudimos iniciar sesión con Google. Inténtalo nuevamente.',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
    // Don't set _isLoading to false here - let the auth state listener handle it
  }

  String _mapSupabaseError(AuthException e) {
    final code = e.message.toLowerCase();
    if (code.contains('invalid login credentials')) {
      return 'Credenciales inválidas. Verifica tu correo y contraseña.';
    }
    if (code.contains('email rate limit exceeded')) {
      return 'Has intentado demasiadas veces. Espera un momento e inténtalo nuevamente.';
    }
    if (code.contains('password should be at least')) {
      return 'La contraseña debe cumplir los requisitos mínimos de seguridad.';
    }
    return 'No pudimos completar la autenticación. Revisa los datos e inténtalo nuevamente.';
  }

  void _toggleAuthMode() {
    FocusScope.of(context).unfocus();
    _formKey.currentState?.reset();
    setState(() {
      _isRegisterMode = !_isRegisterMode;
      _passwordController.clear();
      _confirmPasswordController.clear();
      if (!_isRegisterMode) {
        _shopNameController.clear();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Logo
                  const Icon(
                    Icons.pedal_bike,
                    size: 80,
                    color: Colors.blue,
                  ),
                  const SizedBox(height: 16),

                  // Title
                  const Text(
                    'Vinabike ERP',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Sistema de Gestión Integral',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 48),

                  // Shop Name Field (only in register mode)
                  if (_isRegisterMode) ...[
                    TextFormField(
                      key: const ValueKey('signup-shop-name'),
                      controller: _shopNameController,
                      decoration: const InputDecoration(
                        labelText: 'Nombre de tu Tienda',
                        prefixIcon: Icon(Icons.store),
                        hintText: 'Ej: Vinabike',
                        helperText: 'Se usará para preparar tu nueva tienda',
                      ),
                      validator: (value) => _isRegisterMode
                          ? AuthInputValidation.validateShopName(value)
                          : null,
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Email Field
                  TextFormField(
                    key: const ValueKey('auth-email'),
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Correo Electrónico',
                      prefixIcon: Icon(Icons.email),
                    ),
                    validator: AuthInputValidation.validateEmail,
                  ),
                  const SizedBox(height: 16),

                  // Password Field
                  TextFormField(
                    key: ValueKey(
                      _isRegisterMode ? 'signup-password' : 'login-password',
                    ),
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    decoration: InputDecoration(
                      labelText: 'Contraseña',
                      prefixIcon: const Icon(Icons.lock),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility
                              : Icons.visibility_off,
                        ),
                        onPressed: () {
                          setState(() => _obscurePassword = !_obscurePassword);
                        },
                      ),
                      helperText: _isRegisterMode
                          ? AuthInputValidation.strongPasswordHelper
                          : null,
                    ),
                    validator: (value) => AuthInputValidation.validatePassword(
                      value,
                      isNewPassword: _isRegisterMode,
                    ),
                  ),

                  // Forgot Password Link (only in login mode)
                  if (!_isRegisterMode) ...[
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (context) => const ForgotPasswordDialog(),
                          );
                        },
                        child: const Text('¿Olvidaste tu contraseña?'),
                      ),
                    ),
                  ],

                  const SizedBox(height: 24),

                  if (_isRegisterMode) ...[
                    TextFormField(
                      key: const ValueKey('signup-password-confirmation'),
                      controller: _confirmPasswordController,
                      obscureText: _obscurePassword,
                      decoration: const InputDecoration(
                        labelText: 'Confirmar Contraseña',
                        prefixIcon: Icon(Icons.lock_outline),
                      ),
                      validator: (value) => !_isRegisterMode
                          ? null
                          : AuthInputValidation.validatePasswordConfirmation(
                              value,
                              password: _passwordController.text,
                            ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // Sign In Button
                  AppButton(
                    text: _isRegisterMode ? 'Crear Cuenta' : 'Iniciar Sesión',
                    onPressed: _isLoading
                        ? null
                        : _isRegisterMode
                            ? _register
                            : _signIn,
                    isLoading: _isLoading,
                    width: double.infinity,
                  ),
                  const SizedBox(height: 16),

                  // OAuth is an access path for identities already assigned to
                  // this ERP. New tenant owners must use the explicit signup
                  // form so the server receives the required shop metadata.
                  if (!_isRegisterMode) ...[
                    Row(
                      children: [
                        const Expanded(child: Divider()),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            'o continuar con',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 14,
                            ),
                          ),
                        ),
                        const Expanded(child: Divider()),
                      ],
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      key: const ValueKey('existing-account-google-login'),
                      onPressed: _isLoading ? null : _signInWithGoogle,
                      icon: Image.network(
                        'https://www.gstatic.com/firebasejs/ui/2.0.0/images/auth/google.svg',
                        height: 20,
                        width: 20,
                        errorBuilder: (context, error, stackTrace) =>
                            const Icon(Icons.g_mobiledata, size: 20),
                      ),
                      label:
                          const Text('Ingresar con Google (cuenta existente)'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        minimumSize: const Size(double.infinity, 48),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _isLoading ? null : _toggleAuthMode,
                      child: Text(
                        _isRegisterMode
                            ? '¿Ya tienes cuenta? Inicia sesión'
                            : '¿No tienes cuenta? Regístrate',
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
