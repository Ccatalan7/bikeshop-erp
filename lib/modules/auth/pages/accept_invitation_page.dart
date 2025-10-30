import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';

/// Invitation Acceptance Page
/// Handles employee invitation acceptance and account setup
/// Route: /accept-invitation?token=xxx
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
  String? _errorMessage;
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
        _errorMessage = null;
      });

      debugPrint('🔍 Loading invitation with token: ${widget.token}');

      // Fetch invitation by token
      final response = await Supabase.instance.client
          .from('user_invitations')
          .select('id, email, role, tenant_id, status, expires_at, metadata, employee_id')
          .eq('metadata->>invitation_token', widget.token)
          .maybeSingle();

      debugPrint('📦 Invitation response: $response');

      if (response == null) {
        debugPrint('❌ No invitation found for token: ${widget.token}');
        setState(() {
          _errorMessage = 'Invitación no encontrada o ya fue utilizada.';
          _isLoading = false;
        });
        return;
      }

      // Check if invitation is expired
      final expiresAt = DateTime.parse(response['expires_at']);
      if (DateTime.now().isAfter(expiresAt)) {
        setState(() {
          _errorMessage = 'Esta invitación ha expirado.';
          _isLoading = false;
        });
        return;
      }

      // Check if already accepted
      if (response['status'] == 'accepted') {
        setState(() {
          _errorMessage = 'Esta invitación ya fue aceptada.';
          _isLoading = false;
        });
        return;
      }

      setState(() {
        _invitationData = response;
        _emailController.text = response['email'];
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error al cargar la invitación: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _acceptInvitation() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final email = _emailController.text.trim();
      final password = _passwordController.text;

      // IMPORTANT: The trigger handle_new_user() will automatically:
      // 1. Find the pending invitation
      // 2. Create user_profile with correct tenant_id and role
      // 3. Update auth.users metadata
      // 4. Mark invitation as accepted
      // 
      // We DON'T need to pass metadata in signUp() - the trigger handles everything!
      
      // Step 1: Sign up the user (trigger will handle the rest)
      // Note: emailRedirectTo skips the confirmation email for invited users
      AuthResponse authResponse;
      
      try {
        authResponse = await Supabase.instance.client.auth.signUp(
          email: email,
          password: password,
          emailRedirectTo: null, // Skip email confirmation redirect
          // Don't pass metadata - let the trigger handle it
        );
        
        debugPrint('✅ User signed up: ${authResponse.user?.id}');
        debugPrint('✅ Email confirmed: ${authResponse.user?.emailConfirmedAt}');
      } catch (signupError) {
        debugPrint('⚠️ Signup error: $signupError');
        
        // Check if user already exists
        if (signupError.toString().contains('already registered') ||
            signupError.toString().contains('User already registered')) {
          setState(() {
            _errorMessage = 'Este email ya está registrado. Si ya tienes una cuenta, inicia sesión normalmente.';
            _isSubmitting = false;
          });
          return;
        }
        
        throw signupError;
      }

      if (authResponse.user == null) {
        throw Exception('Error al crear la cuenta. Por favor intenta nuevamente.');
      }

      final userId = authResponse.user!.id;
      debugPrint('✅ User created with ID: $userId');

      // Step 2: Link user to employee if employee_id exists
      // (The trigger already marked invitation as accepted)
      if (_invitationData!['employee_id'] != null) {
        try {
          await Supabase.instance.client
              .from('employees')
              .update({'user_id': userId})
              .eq('id', _invitationData!['employee_id']);
          
          debugPrint('✅ Linked user to employee: ${_invitationData!['employee_id']}');
        } catch (employeeError) {
          debugPrint('⚠️ Failed to link employee (non-critical): $employeeError');
          // Non-critical error - continue anyway
        }
      }

      // Step 3: Sign out (force fresh login to load correct tenant context)
      await Supabase.instance.client.auth.signOut();

      // Step 4: Check if email confirmation is required
      final needsEmailConfirmation = authResponse.user?.emailConfirmedAt == null;

      // Step 5: Show success message and redirect
      if (mounted) {
        if (needsEmailConfirmation) {
          // Email confirmation required - show clear instructions
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                '✅ Cuenta creada exitosamente!\n'
                '📧 Revisa tu email para confirmar tu cuenta.\n'
                'Una vez confirmada, podrás iniciar sesión.',
              ),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 8),
            ),
          );
        } else {
          // Email auto-confirmed - can login immediately
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Cuenta creada exitosamente. Ya puedes iniciar sesión con tu contraseña.'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 5),
            ),
          );
        }

        // Redirect to login page
        context.go('/login');
      }
    } catch (e) {
      debugPrint('❌ Error accepting invitation: $e');
      setState(() {
        _errorMessage = 'Error al crear la cuenta: ${e.toString()}';
        _isSubmitting = false;
      });
    }
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
                    : _errorMessage != null
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
          _errorMessage!,
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
    final firstName = _invitationData!['metadata']['first_name'];
    final lastName = _invitationData!['metadata']['last_name'];
    final role = _invitationData!['role'];

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
            'Hola $firstName $lastName, configura tu contraseña para acceder al sistema.',
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
            enabled: false,
            decoration: const InputDecoration(
              labelText: 'Email',
              prefixIcon: Icon(Icons.email),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),

          // Password field
          TextFormField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            decoration: InputDecoration(
              labelText: 'Contraseña',
              prefixIcon: const Icon(Icons.lock),
              suffixIcon: IconButton(
                icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
              ),
              border: const OutlineInputBorder(),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Por favor ingresa una contraseña';
              }
              if (value.length < 8) {
                return 'La contraseña debe tener al menos 8 caracteres';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),

          // Confirm password field
          TextFormField(
            controller: _confirmPasswordController,
            obscureText: _obscureConfirmPassword,
            decoration: InputDecoration(
              labelText: 'Confirmar Contraseña',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                icon: Icon(_obscureConfirmPassword ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
              ),
              border: const OutlineInputBorder(),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Por favor confirma tu contraseña';
              }
              if (value != _passwordController.text) {
                return 'Las contraseñas no coinciden';
              }
              return null;
            },
          ),
          const SizedBox(height: 24),

          // Error message
          if (_errorMessage != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _errorMessage!,
                style: TextStyle(color: Colors.red.shade700),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Submit button
          ElevatedButton(
            onPressed: _isSubmitting ? null : _acceptInvitation,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: _isSubmitting
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Crear Cuenta'),
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
