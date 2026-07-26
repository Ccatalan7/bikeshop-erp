import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/services/auth_service.dart';

class WorkerLoginPage extends StatefulWidget {
  const WorkerLoginPage({super.key});

  @override
  State<WorkerLoginPage> createState() => _WorkerLoginPageState();
}

class _WorkerLoginPageState extends State<WorkerLoginPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _storeController;
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    final queryStore = Uri.base.queryParameters['store']?.trim();
    _storeController = TextEditingController(
      text: queryStore?.isNotEmpty == true ? queryStore! : 'vinabike',
    );
    if (Uri.base.queryParameters['password_reset'] == 'complete') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Contraseña actualizada. Ingresa nuevamente con tu nueva contraseña.',
            ),
          ),
        );
      });
    }
  }

  @override
  void dispose() {
    _storeController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final authService = context.read<AuthService>();
      await authService.signInWorkerWithUsername(
        tenant: _storeController.text,
        username: _usernameController.text,
        password: _passwordController.text,
      );

      if (!authService.isWorker) {
        await authService.signOut();
        throw const AuthException('Este usuario no tiene acceso trabajador.');
      }

      if (mounted) {
        context.go(
          authService.workerMustResetPassword
              ? '/worker/password-reset'
              : '/worker',
        );
      }
    } on AuthException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_mapAuthError(error.message)),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'No pudimos iniciar sesión. Revisa los datos e inténtalo nuevamente.',
          ),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _mapAuthError(String message) {
    final lower = message.toLowerCase();
    if (lower.contains('invalid login credentials')) {
      return 'Usuario o contraseña incorrectos.';
    }
    return 'No pudimos iniciar sesión. Revisa los datos e inténtalo nuevamente.';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: Colors.grey.shade200),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Acceso trabajadores',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: Colors.grey.shade900,
                          ),
                        ),
                        const SizedBox(height: 20),
                        TextFormField(
                          controller: _storeController,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Tienda',
                            prefixIcon: Icon(Icons.storefront_outlined),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Ingresa la tienda';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _usernameController,
                          textInputAction: TextInputAction.next,
                          autocorrect: false,
                          enableSuggestions: false,
                          decoration: const InputDecoration(
                            labelText: 'Usuario',
                            prefixIcon: Icon(Icons.badge_outlined),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Ingresa tu usuario';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          onFieldSubmitted: (_) {
                            if (!_isLoading) _signIn();
                          },
                          decoration: InputDecoration(
                            labelText: 'Contraseña',
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              tooltip: _obscurePassword
                                  ? 'Mostrar contraseña'
                                  : 'Ocultar contraseña',
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                              onPressed: () => setState(
                                () => _obscurePassword = !_obscurePassword,
                              ),
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Ingresa tu contraseña';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 20),
                        FilledButton(
                          onPressed: _isLoading ? null : _signIn,
                          child: _isLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('Entrar'),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed:
                              _isLoading ? null : () => context.go('/login'),
                          child: const Text('Acceso ERP'),
                        ),
                      ],
                    ),
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
