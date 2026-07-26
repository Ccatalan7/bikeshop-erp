import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../shared/services/auth_service.dart';
import '../../../shared/utils/auth_input_validation.dart';

class WorkerPasswordResetPage extends StatefulWidget {
  const WorkerPasswordResetPage({super.key});

  @override
  State<WorkerPasswordResetPage> createState() =>
      _WorkerPasswordResetPageState();
}

class _WorkerPasswordResetPageState extends State<WorkerPasswordResetPage> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmationController = TextEditingController();
  bool _isSubmitting = false;
  bool _obscurePassword = true;
  bool _obscureConfirmation = true;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmationController.dispose();
    super.dispose();
  }

  Future<void> _completeReset() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);
    try {
      final authService = context.read<AuthService>();
      await authService.completeWorkerPasswordReset(
        _passwordController.text,
      );
      await authService.signOut();

      if (mounted) {
        context.go('/worker/login?password_reset=complete');
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'No pudimos completar el cambio de contraseña. Inténtalo nuevamente.',
          ),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _signOut() async {
    setState(() => _isSubmitting = true);
    try {
      await context.read<AuthService>().signOut();
      if (mounted) context.go('/worker/login');
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'No pudimos cerrar la sesión. Inténtalo nuevamente.',
          ),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
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
              constraints: const BoxConstraints(maxWidth: 460),
              child: Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  side: BorderSide(color: Colors.grey.shade200),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Icon(
                          Icons.password_outlined,
                          size: 42,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Crea tu contraseña personal',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'La contraseña inicial era temporal. Debes reemplazarla antes de acceder al portal.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 24),
                        TextFormField(
                          key: const ValueKey('worker-new-password'),
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          autofillHints: const [AutofillHints.newPassword],
                          maxLength: 128,
                          decoration: InputDecoration(
                            labelText: 'Nueva contraseña',
                            helperText:
                                AuthInputValidation.adminManagedPasswordHelper,
                            counterText: '',
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              tooltip: _obscurePassword
                                  ? 'Mostrar contraseña'
                                  : 'Ocultar contraseña',
                              onPressed: () => setState(
                                () => _obscurePassword = !_obscurePassword,
                              ),
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                            ),
                          ),
                          validator:
                              AuthInputValidation.validateAdminManagedPassword,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          key: const ValueKey(
                            'worker-new-password-confirmation',
                          ),
                          controller: _confirmationController,
                          obscureText: _obscureConfirmation,
                          autofillHints: const [AutofillHints.newPassword],
                          maxLength: 128,
                          decoration: InputDecoration(
                            labelText: 'Confirmar contraseña',
                            counterText: '',
                            prefixIcon: const Icon(Icons.lock_reset_outlined),
                            suffixIcon: IconButton(
                              tooltip: _obscureConfirmation
                                  ? 'Mostrar confirmación'
                                  : 'Ocultar confirmación',
                              onPressed: () => setState(
                                () => _obscureConfirmation =
                                    !_obscureConfirmation,
                              ),
                              icon: Icon(
                                _obscureConfirmation
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                            ),
                          ),
                          validator: (value) {
                            final strengthError = AuthInputValidation
                                .validateAdminManagedPassword(value);
                            if (strengthError != null) return strengthError;
                            return AuthInputValidation
                                .validatePasswordConfirmation(
                              value,
                              password: _passwordController.text,
                            );
                          },
                          onFieldSubmitted: (_) {
                            if (!_isSubmitting) _completeReset();
                          },
                        ),
                        const SizedBox(height: 24),
                        FilledButton.icon(
                          key: const ValueKey(
                            'complete-worker-password-reset',
                          ),
                          onPressed: _isSubmitting ? null : _completeReset,
                          icon: _isSubmitting
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.check_circle_outline),
                          label: const Text('Guardar y volver a ingresar'),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: _isSubmitting ? null : _signOut,
                          style: TextButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                          ),
                          child: const Text('Cerrar sesión'),
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
