import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/services/auth_service.dart';
import '../../../shared/utils/auth_input_validation.dart';

enum _InvitationAccountMode { create, existing }

/// Invitation Acceptance Page
/// Handles employee invitation acceptance and account setup
/// Route: /accept-invitation#token=xxx (query-string fallback for old emails)
class AcceptInvitationPage extends StatefulWidget {
  final String token;

  const AcceptInvitationPage({
    super.key,
    required this.token,
  });

  @override
  State<AcceptInvitationPage> createState() => _AcceptInvitationPageState();
}

class _AcceptInvitationPageState extends State<AcceptInvitationPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isLoading = true;
  bool _isSubmitting = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _hasMatchingSession = false;
  bool _hasMismatchedSession = false;
  _InvitationAccountMode _accountMode = _InvitationAccountMode.create;
  String? _loadErrorMessage;
  String? _formErrorMessage;
  Map<String, dynamic>? _invitationData;

  @override
  void initState() {
    super.initState();
    _loadInvitation();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _loadInvitation() async {
    try {
      setState(() {
        _isLoading = true;
        _loadErrorMessage = null;
        _formErrorMessage = null;
      });

      final token = widget.token.trim();
      if (token.isEmpty) {
        _setInvitationLoadError('Invitación no encontrada o ya fue utilizada.');
        return;
      }

      final response = await Supabase.instance.client.rpc(
        'lookup_user_invitation',
        params: {'p_token': token},
      ).maybeSingle();

      if (response == null) {
        _setInvitationLoadError('Invitación no encontrada o ya fue utilizada.');
        return;
      }

      final invitation = Map<String, dynamic>.from(response as Map);
      final email = invitation['email']?.toString().trim() ?? '';
      if (email.isEmpty) {
        _setInvitationLoadError('La invitación no contiene un correo válido.');
        return;
      }

      if (!mounted) return;
      final signedInEmail = Supabase.instance.client.auth.currentUser?.email;
      final hasSession =
          signedInEmail != null && signedInEmail.trim().isNotEmpty;
      final sessionMatchesInvitation = hasSession &&
          signedInEmail.trim().toLowerCase() == email.toLowerCase();
      setState(() {
        _invitationData = invitation;
        _emailController.text = email;
        _hasMatchingSession = sessionMatchesInvitation;
        _hasMismatchedSession = hasSession && !sessionMatchesInvitation;
        if (sessionMatchesInvitation) {
          _accountMode = _InvitationAccountMode.existing;
        }
        _isLoading = false;
      });
    } catch (_) {
      _setInvitationLoadError(
        'No pudimos validar la invitación. Inténtalo nuevamente.',
      );
    }
  }

  void _setInvitationLoadError(String message) {
    if (!mounted) return;
    setState(() {
      _loadErrorMessage = message;
      _isLoading = false;
    });
  }

  Future<void> _acceptInvitation() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
      _formErrorMessage = null;
    });

    try {
      final email = _emailController.text.trim();
      final password = _passwordController.text;
      final authService = context.read<AuthService>();

      if (_hasMatchingSession) {
        await _claimInvitation(authService);
        return;
      }

      if (_hasMismatchedSession) {
        throw const AuthException(
          'Cierra la sesión actual antes de aceptar esta invitación.',
        );
      }

      if (_accountMode == _InvitationAccountMode.existing) {
        final user =
            await authService.signInWithEmailAndPassword(email, password);
        if (user.email?.trim().toLowerCase() != email.toLowerCase()) {
          await authService.signOut();
          throw const AuthException(
            'No pudimos verificar la cuenta para esta invitación.',
          );
        }
        await _claimInvitation(authService);
        return;
      }

      final authResponse = await authService.signUpStaffInvitation(
        email: email,
        password: password,
        invitationToken: widget.token.trim(),
      );
      if (authResponse.user == null) {
        throw const AuthException(
          'No pudimos completar el registro con esta invitación.',
        );
      }

      final needsEmailConfirmation = authResponse.session == null;
      // With email confirmation enabled, server-side assignment occurs when
      // the user confirms the mailbox link, not necessarily during signup.
      // If signup issued a session immediately, close it and require a clean
      // login after the invitation flow.
      if (authResponse.session != null) {
        await authService.signOut();
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            needsEmailConfirmation
                ? 'Cuenta creada. Revisa tu email para confirmar el acceso.'
                : 'Cuenta creada. Ya puedes iniciar sesión.',
          ),
          backgroundColor:
              needsEmailConfirmation ? Colors.orange : Colors.green,
          duration: const Duration(seconds: 6),
        ),
      );
      context.go('/login');
    } on AuthException {
      if (!mounted) return;
      setState(() {
        _formErrorMessage =
            'No pudimos verificar las credenciales o completar la invitación. Revisa los datos e inténtalo nuevamente.';
        _isSubmitting = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _formErrorMessage =
            'No pudimos completar la invitación. Verifica el enlace e inténtalo nuevamente.';
        _isSubmitting = false;
      });
    }
  }

  Future<void> _claimInvitation(AuthService authService) async {
    final accepted = await Supabase.instance.client.rpc(
      'accept_user_invitation',
      params: {'p_token': widget.token.trim()},
    );
    if (accepted != true) {
      throw const AuthException('No pudimos completar la invitación.');
    }

    await authService.refreshSession();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Invitación aceptada. Ya tienes acceso al equipo.'),
        backgroundColor: Colors.green,
      ),
    );
    context.go('/dashboard');
  }

  Future<void> _switchSignedInAccount() async {
    setState(() {
      _isSubmitting = true;
      _formErrorMessage = null;
    });
    try {
      await context.read<AuthService>().signOut();
      if (!mounted) return;
      setState(() {
        _hasMatchingSession = false;
        _hasMismatchedSession = false;
        _accountMode = _InvitationAccountMode.existing;
        _isSubmitting = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _formErrorMessage =
            'No pudimos cambiar la sesión. Inténtalo nuevamente.';
        _isSubmitting = false;
      });
    }
  }

  void _changeAccountMode(_InvitationAccountMode mode) {
    if (_accountMode == mode) return;
    _formKey.currentState?.reset();
    _passwordController.clear();
    _confirmPasswordController.clear();
    setState(() {
      _accountMode = mode;
      _formErrorMessage = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.blue.shade400,
              Colors.blue.shade700,
            ],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Card(
              elevation: 8,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 500),
                padding: const EdgeInsets.all(32.0),
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(),
                      )
                    : _loadErrorMessage != null
                        ? _buildErrorView()
                        : _buildInvitationForm(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorView() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.error_outline,
          size: 64,
          color: Colors.red.shade400,
        ),
        const SizedBox(height: 16),
        Text(
          'Error',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(
          _loadErrorMessage!,
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.red.shade700),
        ),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: () => context.go('/login'),
          child: const Text('Ir al Login'),
        ),
      ],
    );
  }

  Widget _buildInvitationForm() {
    final shopName =
        _invitationData!['shop_name']?.toString().trim() ?? 'tu empresa';
    final role = _invitationData!['role']?.toString() ?? '';

    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Icon(
            Icons.person_add,
            size: 64,
            color: Theme.of(context).primaryColor,
          ),
          const SizedBox(height: 16),
          Text(
            '¡Bienvenido!',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            'Te invitaron al equipo de $shopName. Elige cómo quieres vincular tu acceso.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 24),

          // Role badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.badge, size: 20, color: Colors.blue.shade700),
                const SizedBox(width: 8),
                Text(
                  'Rol: ${_getRoleDisplayName(role)}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.blue.shade700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Email field (read-only)
          TextFormField(
            controller: _emailController,
            readOnly: true,
            decoration: const InputDecoration(
              labelText: 'Email',
              prefixIcon: Icon(Icons.email),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),

          if (_hasMismatchedSession) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Hay otra cuenta iniciada en este dispositivo. Cámbiala antes de continuar con la invitación.',
                style: TextStyle(color: Colors.orange.shade900),
                textAlign: TextAlign.center,
              ),
            ),
          ] else if (_hasMatchingSession) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'La cuenta correcta ya está iniciada. Puedes aceptar la invitación sin volver a ingresar tu contraseña.',
                style: TextStyle(color: Colors.green.shade900),
                textAlign: TextAlign.center,
              ),
            ),
          ] else ...[
            SegmentedButton<_InvitationAccountMode>(
              selected: {_accountMode},
              showSelectedIcon: false,
              onSelectionChanged: (selection) =>
                  _changeAccountMode(selection.first),
              segments: const [
                ButtonSegment(
                  value: _InvitationAccountMode.create,
                  icon: Icon(Icons.person_add_outlined),
                  label: Text('Crear cuenta'),
                ),
                ButtonSegment(
                  value: _InvitationAccountMode.existing,
                  icon: Icon(Icons.login),
                  label: Text('Ya tengo cuenta'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              key: ValueKey('invitation-password-${_accountMode.name}'),
              controller: _passwordController,
              obscureText: _obscurePassword,
              decoration: InputDecoration(
                labelText: _accountMode == _InvitationAccountMode.create
                    ? 'Crear contraseña'
                    : 'Contraseña actual',
                prefixIcon: const Icon(Icons.lock),
                suffixIcon: IconButton(
                  icon: Icon(_obscurePassword
                      ? Icons.visibility
                      : Icons.visibility_off),
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
                border: const OutlineInputBorder(),
                helperText: _accountMode == _InvitationAccountMode.create
                    ? AuthInputValidation.strongPasswordHelper
                    : null,
              ),
              validator: (value) => AuthInputValidation.validatePassword(
                value,
                isNewPassword: _accountMode == _InvitationAccountMode.create,
              ),
            ),
            if (_accountMode == _InvitationAccountMode.create) ...[
              const SizedBox(height: 16),
              TextFormField(
                controller: _confirmPasswordController,
                obscureText: _obscureConfirmPassword,
                decoration: InputDecoration(
                  labelText: 'Confirmar contraseña',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(_obscureConfirmPassword
                        ? Icons.visibility
                        : Icons.visibility_off),
                    onPressed: () => setState(() =>
                        _obscureConfirmPassword = !_obscureConfirmPassword),
                  ),
                  border: const OutlineInputBorder(),
                ),
                validator: (value) =>
                    AuthInputValidation.validatePasswordConfirmation(
                  value,
                  password: _passwordController.text,
                ),
              ),
            ],
          ],
          const SizedBox(height: 24),

          // Error message
          if (_formErrorMessage != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _formErrorMessage!,
                style: TextStyle(color: Colors.red.shade700),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Submit button
          ElevatedButton(
            onPressed: _isSubmitting
                ? null
                : _hasMismatchedSession
                    ? _switchSignedInAccount
                    : _acceptInvitation,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: _isSubmitting
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    _hasMismatchedSession
                        ? 'Cambiar cuenta'
                        : _hasMatchingSession
                            ? 'Aceptar invitación'
                            : _accountMode == _InvitationAccountMode.create
                                ? 'Crear cuenta'
                                : 'Ingresar y aceptar',
                  ),
          ),
        ],
      ),
    );
  }

  String _getRoleDisplayName(String role) {
    const roleMap = {
      'admin': 'Administrador',
      'manager': 'Gerente',
      'cashier': 'Cajero',
      'mechanic': 'Mecánico',
      'accountant': 'Contador',
    };
    return roleMap[role] ?? role;
  }
}
