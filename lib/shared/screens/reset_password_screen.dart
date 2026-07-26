import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auth_service.dart';
import '../utils/auth_input_validation.dart';
import '../widgets/app_button.dart';

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isSuccess = false;
  bool _hasValidSession = false;
  bool _checkingSession = true;
  String? _errorMessage;
  AuthService? _authService;
  Timer? _recoveryTimeout;

  @override
  void initState() {
    super.initState();
    _recoveryTimeout = Timer(const Duration(seconds: 4), () {
      if (!mounted || _hasValidSession) return;
      setState(() {
        _checkingSession = false;
        _errorMessage =
            'El enlace de restablecimiento ha expirado o es inválido. Por favor solicita uno nuevo.';
      });
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final authService = context.read<AuthService>();
    if (identical(authService, _authService)) return;
    _authService?.removeListener(_handleAuthStateChanged);
    _authService = authService;
    _authService!.addListener(_handleAuthStateChanged);
    _handleAuthStateChanged();
  }

  void _handleAuthStateChanged() {
    if (!mounted || _authService?.isPasswordRecovery != true) return;
    _recoveryTimeout?.cancel();
    if (_checkingSession || !_hasValidSession || _errorMessage != null) {
      setState(() {
        _hasValidSession = true;
        _checkingSession = false;
        _errorMessage = null;
      });
    }
  }

  @override
  void dispose() {
    _recoveryTimeout?.cancel();
    _authService?.removeListener(_handleAuthStateChanged);
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _resetPassword() async {
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
      await authService.updatePassword(_passwordController.text);

      if (mounted) {
        setState(() {
          _isSuccess = true;
          _isLoading = false;
        });

        // Auto-redirect to dashboard after 2 seconds
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) {
            context.go('/dashboard');
          }
        });
      }
    } on AuthException catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_mapSupabaseError(e)),
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
              'No pudimos actualizar la contraseña. Solicita un enlace nuevo e inténtalo nuevamente.',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _mapSupabaseError(AuthException e) {
    final message = e.message.toLowerCase();
    if (message.contains('same password')) {
      return 'La nueva contraseña debe ser diferente a la anterior.';
    }
    if (message.contains('weak password') || message.contains('password')) {
      return AuthInputValidation.strongPasswordHelper;
    }
    return 'No pudimos actualizar la contraseña. Solicita un enlace nuevo e inténtalo nuevamente.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: _checkingSession
                    ? _buildLoadingView()
                    : !_hasValidSession
                        ? _buildErrorView()
                        : _isSuccess
                            ? _buildSuccessView()
                            : _buildResetForm(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingView() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 24),
        Text(
          'Verificando enlace...',
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ],
    );
  }

  Widget _buildErrorView() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(
          Icons.error_outline,
          size: 64,
          color: Colors.red,
        ),
        const SizedBox(height: 24),
        Text(
          'Enlace Inválido',
          style: Theme.of(context).textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        Text(
          _errorMessage ??
              'El enlace de restablecimiento ha expirado o es inválido.',
          style: Theme.of(context).textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        AppButton(
          text: 'Volver al inicio de sesión',
          onPressed: () => context.go('/login'),
        ),
      ],
    );
  }

  Widget _buildResetForm() {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Logo
          const Icon(
            Icons.two_wheeler,
            size: 64,
            color: Colors.blue,
          ),
          const SizedBox(height: 16),

          // Title
          const Text(
            'Restablecer contraseña',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Ingresa tu nueva contraseña',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 32),

          // New Password Field
          TextFormField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            decoration: InputDecoration(
              labelText: 'Nueva contraseña',
              helperText: AuthInputValidation.strongPasswordHelper,
              prefixIcon: const Icon(Icons.lock),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword ? Icons.visibility : Icons.visibility_off,
                ),
                onPressed: () {
                  setState(() => _obscurePassword = !_obscurePassword);
                },
              ),
              border: const OutlineInputBorder(),
            ),
            validator: (value) => AuthInputValidation.validatePassword(
              value,
              isNewPassword: true,
            ),
          ),
          const SizedBox(height: 16),

          // Confirm Password Field
          TextFormField(
            controller: _confirmPasswordController,
            obscureText: _obscureConfirmPassword,
            decoration: InputDecoration(
              labelText: 'Confirmar contraseña',
              hintText: 'Repite la contraseña',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureConfirmPassword
                      ? Icons.visibility
                      : Icons.visibility_off,
                ),
                onPressed: () {
                  setState(
                      () => _obscureConfirmPassword = !_obscureConfirmPassword);
                },
              ),
              border: const OutlineInputBorder(),
            ),
            validator: (value) =>
                AuthInputValidation.validatePasswordConfirmation(
              value,
              password: _passwordController.text,
            ),
            onFieldSubmitted: (_) => _resetPassword(),
          ),
          const SizedBox(height: 24),

          // Reset Button
          AppButton(
            text: 'Restablecer contraseña',
            onPressed: _isLoading ? null : _resetPassword,
            isLoading: _isLoading,
            icon: Icons.check,
          ),
          const SizedBox(height: 16),

          // Back to Login
          TextButton(
            onPressed: () => context.go('/'),
            child: const Text('Volver al inicio de sesión'),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccessView() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Success Icon
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.green.shade50,
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.check_circle,
            size: 80,
            color: Colors.green.shade600,
          ),
        ),
        const SizedBox(height: 24),

        // Success Title
        const Text(
          '¡Contraseña actualizada!',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),

        // Success Message
        Text(
          'Tu contraseña ha sido restablecida exitosamente.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 16,
            color: Colors.grey.shade700,
          ),
        ),
        const SizedBox(height: 24),

        // Auto-redirect message
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
              Text(
                'Redirigiendo al dashboard...',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.blue.shade900,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Manual redirect button
        TextButton(
          onPressed: () => context.go('/dashboard'),
          child: const Text('Ir al dashboard ahora →'),
        ),
      ],
    );
  }
}
