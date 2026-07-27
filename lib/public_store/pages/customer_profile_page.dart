import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;
import '../services/customer_account_service.dart';
import '../theme/public_store_theme.dart';
import '../widgets/customer_portal_layout.dart';
import '../../shared/services/self_password_service.dart';
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
          _buildSecuritySection(
            context,
            hasPendingOtherSessionsRevocation:
                accountService.hasPendingOtherSessionsRevocation,
          ),
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

  Widget _buildSecuritySection(
    BuildContext context, {
    required bool hasPendingOtherSessionsRevocation,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return _ProfileSection(
      title: 'Seguridad',
      description:
          'Mantén tu cuenta protegida. Los cambios de contraseña se aplican a tu acceso web.',
      child: Material(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
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
                      child: const Icon(
                        Icons.lock_outline,
                        color: Color(0xFF102A43),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Contraseña',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            hasPendingOtherSessionsRevocation
                                ? 'Tu nueva contraseña ya está activa'
                                : 'Cambiar tu contraseña de acceso',
                            style: const TextStyle(
                              color: Color(0xFF667085),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right,
                      color: Color(0xFF667085),
                    ),
                  ],
                ),
              ),
            ),
            if (hasPendingOtherSessionsRevocation) ...[
              const Divider(height: 1),
              Container(
                key: const ValueKey(
                  'customer-password-session-revocation-pending',
                ),
                color: colorScheme.errorContainer.withValues(alpha: 0.45),
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Quedó pendiente cerrar las demás sesiones.',
                      style: TextStyle(
                        color: colorScheme.onErrorContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'No vuelvas a cambiar la contraseña: puedes reintentar solamente el cierre de sesiones.',
                      style: TextStyle(color: colorScheme.onErrorContainer),
                    ),
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: TextButton(
                        onPressed: () => _showPasswordChangeDialog(
                          context,
                          startWithRevocationRetry: true,
                        ),
                        style: TextButton.styleFrom(
                          minimumSize: const Size(48, 48),
                        ),
                        child: const Text('Completar cierre'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
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

  void _showPasswordChangeDialog(
    BuildContext context, {
    bool startWithRevocationRetry = false,
  }) {
    final accountService = context.read<CustomerAccountService>();
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CustomerPasswordChangeDialog(
        initialRevocationPending: startWithRevocationRetry ||
            accountService.hasPendingOtherSessionsRevocation,
      ),
    );
  }
}

enum _CustomerPasswordChangeStep {
  password,
  verification,
  sessionRevocation,
}

class _CustomerPasswordChangeDialog extends StatefulWidget {
  const _CustomerPasswordChangeDialog({
    required this.initialRevocationPending,
  });

  final bool initialRevocationPending;

  @override
  State<_CustomerPasswordChangeDialog> createState() =>
      _CustomerPasswordChangeDialogState();
}

class _CustomerPasswordChangeDialogState
    extends State<_CustomerPasswordChangeDialog> {
  final _passwordFormKey = GlobalKey<FormState>();
  final _verificationFormKey = GlobalKey<FormState>();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _verificationCodeController = TextEditingController();

  late _CustomerPasswordChangeStep _step;
  bool _isBusy = false;
  String? _passwordError;
  String? _verificationError;
  String? _verificationNotice;
  String? _revocationError;

  @override
  void initState() {
    super.initState();
    _step = widget.initialRevocationPending
        ? _CustomerPasswordChangeStep.sessionRevocation
        : _CustomerPasswordChangeStep.password;
  }

  @override
  void dispose() {
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    _verificationCodeController.dispose();
    super.dispose();
  }

  Future<void> _submitPassword() async {
    if (_isBusy || !_passwordFormKey.currentState!.validate()) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _isBusy = true;
      _passwordError = null;
    });

    SelfPasswordUpdateResult? result;
    var needsReauthentication = false;
    try {
      result = await context.read<CustomerAccountService>().updatePassword(
            _newPasswordController.text,
          );
    } on AuthException catch (error) {
      final issue = CustomerAccountService.classifyPasswordUpdateError(error);
      if (issue == CustomerPasswordUpdateIssue.reauthenticationRequired) {
        needsReauthentication = true;
      } else if (mounted) {
        setState(() => _passwordError = _passwordIssueMessage(issue));
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _passwordError =
              'No pudimos actualizar la contraseña. Inténtalo nuevamente.';
        });
      }
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }

    if (result != null && mounted) {
      _handlePasswordUpdateResult(result);
    } else if (needsReauthentication && mounted) {
      await _requestVerificationCode();
    }
  }

  Future<void> _requestVerificationCode({bool isResend = false}) async {
    if (_isBusy) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _step = _CustomerPasswordChangeStep.verification;
      _isBusy = true;
      _verificationError = null;
      _verificationNotice = null;
    });

    try {
      await context
          .read<CustomerAccountService>()
          .requestPasswordReauthentication();
      if (!mounted) return;
      _verificationCodeController.clear();
      setState(() {
        _verificationNotice = isResend
            ? 'Enviamos un código nuevo. Usa solamente el último recibido.'
            : 'Enviamos un código de verificación a tu correo asociado.';
      });
    } on AuthException catch (error) {
      if (!mounted) return;
      setState(() {
        _verificationError = _reauthenticationRequestMessage(error);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _verificationError =
            'No pudimos enviar el código. Revisa tu conexión e inténtalo nuevamente.';
      });
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _submitVerificationCode() async {
    if (_isBusy || !_verificationFormKey.currentState!.validate()) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _isBusy = true;
      _verificationError = null;
    });

    SelfPasswordUpdateResult? result;
    try {
      result = await context.read<CustomerAccountService>().updatePassword(
            _newPasswordController.text,
            reauthenticationNonce: _verificationCodeController.text,
          );
    } on AuthException catch (error) {
      if (!mounted) return;
      final issue = CustomerAccountService.classifyPasswordUpdateError(error);
      setState(() {
        _verificationError = _verificationIssueMessage(issue);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _verificationError =
            'No pudimos verificar el código. Inténtalo nuevamente.';
      });
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }

    if (result != null && mounted) {
      _handlePasswordUpdateResult(result);
    }
  }

  void _handlePasswordUpdateResult(SelfPasswordUpdateResult result) {
    if (result.otherSessionsRevoked) {
      _finishSuccessfully();
      return;
    }

    _newPasswordController.clear();
    _confirmPasswordController.clear();
    _verificationCodeController.clear();
    setState(() {
      _step = _CustomerPasswordChangeStep.sessionRevocation;
      _revocationError = null;
    });
  }

  Future<void> _retryOtherSessionRevocation() async {
    if (_isBusy) return;

    setState(() {
      _isBusy = true;
      _revocationError = null;
    });

    var completed = false;
    try {
      final outcome = await context
          .read<CustomerAccountService>()
          .retryOtherSessionRevocation();
      if (!mounted) return;
      if (outcome == SelfPasswordOtherSessionsRevocationOutcome.revoked) {
        completed = true;
      } else {
        setState(() {
          _revocationError =
              'La contraseña sigue actualizada, pero no pudimos cerrar las demás sesiones. Revisa tu conexión y reintenta.';
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _revocationError =
            'La contraseña sigue actualizada, pero no pudimos cerrar las demás sesiones. Reintenta desde Seguridad.';
      });
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }

    if (completed && mounted) {
      _finishSuccessfully();
    }
  }

  void _finishSuccessfully() {
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    messenger.showSnackBar(
      const SnackBar(
        content: Text(
          'Contraseña actualizada y demás sesiones cerradas.',
        ),
      ),
    );
  }

  String _passwordIssueMessage(CustomerPasswordUpdateIssue issue) {
    if (issue == CustomerPasswordUpdateIssue.samePassword) {
      return 'La nueva contraseña debe ser distinta a la contraseña actual.';
    }
    return 'No pudimos actualizar la contraseña. Inténtalo nuevamente.';
  }

  String _verificationIssueMessage(CustomerPasswordUpdateIssue issue) {
    switch (issue) {
      case CustomerPasswordUpdateIssue.invalidVerificationCode:
        return 'El código no es válido. Revísalo e inténtalo nuevamente.';
      case CustomerPasswordUpdateIssue.expiredVerificationCode:
        return 'El código venció. Solicita uno nuevo para continuar.';
      case CustomerPasswordUpdateIssue.reauthenticationRequired:
        return 'El código venció o ya no es válido. Solicita uno nuevo.';
      case CustomerPasswordUpdateIssue.samePassword:
        return 'La nueva contraseña debe ser distinta a la contraseña actual.';
      case CustomerPasswordUpdateIssue.unknown:
        return 'No pudimos verificar el código. Inténtalo nuevamente.';
    }
  }

  String _reauthenticationRequestMessage(AuthException error) {
    final code = error.code?.toLowerCase();
    if (code == 'over_email_send_rate_limit' ||
        code == 'over_request_rate_limit') {
      return 'Espera un momento antes de solicitar otro código.';
    }
    return 'No pudimos enviar el código. Inténtalo nuevamente.';
  }

  @override
  Widget build(BuildContext context) {
    final isVerification = _step == _CustomerPasswordChangeStep.verification;
    final isSessionRevocation =
        _step == _CustomerPasswordChangeStep.sessionRevocation;

    return PopScope(
      canPop: !_isBusy,
      child: AlertDialog(
        scrollable: true,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        title: Text(
          isSessionRevocation
              ? 'Completar seguridad'
              : isVerification
                  ? 'Verifica que eres tú'
                  : 'Cambiar contraseña',
        ),
        content: SizedBox(
          width: 420,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: isSessionRevocation
                ? _buildSessionRevocationStep()
                : isVerification
                    ? _buildVerificationStep()
                    : _buildPasswordStep(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _isBusy ? null : () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(
              minimumSize: const Size(48, 48),
            ),
            child: Text(
              isSessionRevocation ? 'Cerrar por ahora' : 'Cancelar',
            ),
          ),
          if (isVerification)
            TextButton(
              onPressed: _isBusy
                  ? null
                  : () => _requestVerificationCode(isResend: true),
              style: TextButton.styleFrom(
                minimumSize: const Size(48, 48),
              ),
              child: const Text('Reenviar código'),
            ),
          FilledButton(
            onPressed: _isBusy
                ? null
                : isSessionRevocation
                    ? _retryOtherSessionRevocation
                    : isVerification
                        ? _submitVerificationCode
                        : _submitPassword,
            style: FilledButton.styleFrom(
              minimumSize: const Size(48, 48),
            ),
            child: _isBusy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    isSessionRevocation
                        ? 'Reintentar cierre'
                        : isVerification
                            ? 'Verificar y cambiar'
                            : 'Cambiar',
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSessionRevocationStep() {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      key: const ValueKey('customer-password-session-revocation-step'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Tu contraseña ya quedó actualizada.',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 8),
        const Text(
          'No pudimos cerrar las demás sesiones. Puedes reintentar solamente ese cierre; no necesitas volver a ingresar ni cambiar tu contraseña.',
        ),
        if (_revocationError != null) ...[
          const SizedBox(height: 12),
          Text(
            _revocationError!,
            key: const ValueKey(
              'customer-password-session-revocation-error',
            ),
            style: TextStyle(color: colorScheme.error),
          ),
        ],
      ],
    );
  }

  Widget _buildPasswordStep() {
    return Form(
      key: _passwordFormKey,
      child: AutofillGroup(
        child: Column(
          key: const ValueKey('customer-password-change-step'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Elige una contraseña nueva. Si tu sesión requiere una verificación adicional, te enviaremos un código.',
            ),
            const SizedBox(height: 16),
            TextFormField(
              key: const ValueKey('customer-new-password'),
              controller: _newPasswordController,
              decoration: const InputDecoration(
                labelText: 'Nueva contraseña',
                helperText: AuthInputValidation.strongPasswordHelper,
              ),
              obscureText: true,
              autofillHints: const [AutofillHints.newPassword],
              textInputAction: TextInputAction.next,
              validator: (value) => AuthInputValidation.validatePassword(
                value,
                isNewPassword: true,
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const ValueKey('customer-confirm-new-password'),
              controller: _confirmPasswordController,
              decoration:
                  const InputDecoration(labelText: 'Confirmar contraseña'),
              obscureText: true,
              autofillHints: const [AutofillHints.newPassword],
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _submitPassword(),
              validator: (value) =>
                  AuthInputValidation.validatePasswordConfirmation(
                value,
                password: _newPasswordController.text,
              ),
            ),
            if (_passwordError != null) ...[
              const SizedBox(height: 12),
              Text(
                _passwordError!,
                key: const ValueKey('customer-password-change-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildVerificationStep() {
    final email =
        context.read<CustomerAccountService>().currentUser?.email?.trim();
    return Form(
      key: _verificationFormKey,
      child: Column(
        key: const ValueKey('customer-password-verification-step'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            email?.isNotEmpty == true
                ? 'Ingresa el código de 6 dígitos enviado a $email.'
                : 'Ingresa el código de 6 dígitos enviado a tu correo asociado.',
          ),
          const SizedBox(height: 16),
          TextFormField(
            key: const ValueKey('customer-password-verification-code'),
            controller: _verificationCodeController,
            autofocus: true,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.oneTimeCode],
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
            maxLength: 6,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              letterSpacing: 5,
            ),
            decoration: const InputDecoration(
              labelText: 'Código de verificación',
              counterText: '',
            ),
            onChanged: (_) {
              if (_verificationError != null) {
                setState(() => _verificationError = null);
              }
            },
            onFieldSubmitted: (_) => _submitVerificationCode(),
            validator: (value) {
              final code = value?.trim() ?? '';
              if (!RegExp(r'^\d{6}$').hasMatch(code)) {
                return 'Ingresa los 6 dígitos del código.';
              }
              return null;
            },
          ),
          if (_verificationError != null) ...[
            const SizedBox(height: 8),
            Text(
              _verificationError!,
              key: const ValueKey('customer-password-verification-error'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          if (_verificationNotice != null) ...[
            const SizedBox(height: 10),
            Text(
              _verificationNotice!,
              key: const ValueKey('customer-password-verification-notice'),
              style: TextStyle(color: Theme.of(context).colorScheme.primary),
            ),
          ],
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
