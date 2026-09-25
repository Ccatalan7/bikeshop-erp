import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;
import '../models/customer_portal_presentation.dart';
import '../services/customer_account_service.dart';
import '../widgets/customer_portal_layout.dart';
import '../widgets/customer_portal_style.dart';
import '../../shared/services/self_password_service.dart';
import '../../shared/utils/auth_input_validation.dart';

/// «Perfil y seguridad» (`/cuenta/perfil`): los datos con que la tienda
/// prepara pedidos y boletas, y la contraseña. El nombre y el correo ya están
/// en el menú de la cuenta; aquí no se repiten en una tarjeta.
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
    _nameController = TextEditingController();
    _emailController = TextEditingController();
    _phoneController = TextEditingController();
    _rutController = TextEditingController();
    _fillFrom(profile);
  }

  /// «Usuario» y «Cliente» son relleno guardado, no un nombre: el campo
  /// empieza vacío para que el cliente escriba el suyo.
  void _fillFrom(Map<String, dynamic>? profile) {
    _nameController.text =
        customerFirstName(profile) == null ? '' : '${profile?['name'] ?? ''}';
    _emailController.text = profile?['email'] ?? '';
    _phoneController.text = profile?['phone'] ?? '';
    _rutController.text = profile?['rut'] ?? '';
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
        title: 'Perfil y seguridad',
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 48),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    return CustomerPortalLayout(
      title: 'Perfil y seguridad',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PortalSection(
            label: 'Datos personales',
            actionLabel: _isEditing ? null : 'Editar',
            onAction: _isEditing ? null : _startEditing,
            child:
                _isEditing ? _buildProfileForm() : _buildProfileFacts(profile),
          ),
          const SizedBox(height: 32),
          _buildSecuritySection(
            context,
            hasPendingOtherSessionsRevocation:
                accountService.hasPendingOtherSessionsRevocation,
          ),
        ],
      ),
    );
  }

  void _startEditing() {
    _fillFrom(context.read<CustomerAccountService>().customerProfile);
    setState(() => _isEditing = true);
  }

  void _cancelEditing() {
    _fillFrom(context.read<CustomerAccountService>().customerProfile);
    setState(() => _isEditing = false);
  }

  Widget _buildProfileFacts(Map<String, dynamic> profile) {
    final style = PortalStyle.of(context);
    Widget fact(String label, String? value, {String? note}) {
      final text = (value ?? '').trim();
      return PortalRow(
        title: label,
        meta: note,
        trailing: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 280),
          child: text.isEmpty
              ? Text('Agregar', style: style.link)
              : Text(
                  text,
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: style.rowMeta.copyWith(color: style.ink),
                ),
        ),
        onTap: text.isEmpty ? _startEditing : null,
      );
    }

    return PortalPanel(
      children: [
        fact(
          'Nombre',
          customerFirstName(profile) == null
              ? null
              : profile['name']?.toString(),
        ),
        fact('RUT', profile['rut']?.toString(), note: 'Para tus boletas'),
        fact('Teléfono', profile['phone']?.toString()),
        PortalRow(
          title: 'Correo',
          meta: 'Es tu acceso a la cuenta; no se cambia desde aquí.',
          trailing: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 280),
            child: Text(
              (profile['email'] ?? '').toString(),
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style.rowMeta.copyWith(color: style.ink),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProfileForm() {
    final style = PortalStyle.of(context);
    return Form(
      key: _formKey,
      child: PortalPanel(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 560;
                final fields = [
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Nombre completo',
                      border: OutlineInputBorder(),
                    ),
                    textCapitalization: TextCapitalization.words,
                    autofillHints: const [AutofillHints.name],
                    validator: (v) => v == null || v.trim().isEmpty
                        ? 'Escribe tu nombre'
                        : null,
                  ),
                  TextFormField(
                    controller: _rutController,
                    decoration: const InputDecoration(
                      labelText: 'RUT',
                      hintText: '12.345.678-9',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  TextFormField(
                    controller: _phoneController,
                    decoration: const InputDecoration(
                      labelText: 'Teléfono',
                      hintText: '+56 9 1234 5678',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.phone,
                    autofillHints: const [AutofillHints.telephoneNumber],
                  ),
                  TextFormField(
                    controller: _emailController,
                    decoration: const InputDecoration(
                      labelText: 'Correo de acceso',
                      border: OutlineInputBorder(),
                    ),
                    enabled: false,
                    style: TextStyle(color: style.inkSecondary),
                  ),
                ];

                final grid = compact
                    ? Column(
                        children: [
                          for (final field in fields)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 14),
                              child: field,
                            ),
                        ],
                      )
                    : Column(
                        children: [
                          Row(children: [
                            Expanded(child: fields[0]),
                            const SizedBox(width: 14),
                            Expanded(child: fields[1]),
                          ]),
                          const SizedBox(height: 14),
                          Row(children: [
                            Expanded(child: fields[2]),
                            const SizedBox(width: 14),
                            Expanded(child: fields[3]),
                          ]),
                          const SizedBox(height: 14),
                        ],
                      );

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    grid,
                    Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        TextButton(
                          onPressed: _isLoading ? null : _cancelEditing,
                          style: TextButton.styleFrom(
                            foregroundColor: style.inkSecondary,
                            minimumSize: const Size(0, 44),
                          ),
                          child: const Text('Cancelar'),
                        ),
                        FilledButton(
                          onPressed: _isLoading ? null : _saveProfile,
                          style: portalPrimaryButton(context),
                          child: Text(
                            _isLoading ? 'Guardando…' : 'Guardar cambios',
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSecuritySection(
    BuildContext context, {
    required bool hasPendingOtherSessionsRevocation,
  }) {
    final style = PortalStyle.of(context);
    final warning = style.tone(PortalTone.warning);
    return PortalSection(
      label: 'Seguridad',
      child: PortalPanel(
        children: [
          PortalRow(
            leading: const PortalThumb(fallbackIcon: Icons.lock_outline),
            title: 'Contraseña',
            meta: hasPendingOtherSessionsRevocation
                ? 'Tu nueva contraseña ya está activa'
                : 'Cambia la contraseña con que entras a la tienda',
            onTap: () => _showPasswordChangeDialog(context),
          ),
          if (hasPendingOtherSessionsRevocation)
            ColoredBox(
              key: const ValueKey(
                'customer-password-session-revocation-pending',
              ),
              color: warning.background,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Quedó pendiente cerrar las demás sesiones.',
                      style: style.rowTitle.copyWith(
                        color: warning.foreground,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Text(
                        'No vuelvas a cambiar la contraseña: puedes reintentar solamente el cierre de sesiones.',
                        style: style.rowMeta.copyWith(
                          color: warning.foreground,
                        ),
                      ),
                    ),
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: TextButton(
                        onPressed: () => _showPasswordChangeDialog(
                          context,
                          startWithRevocationRetry: true,
                        ),
                        style: TextButton.styleFrom(
                          foregroundColor: warning.foreground,
                          minimumSize: const Size(48, 48),
                          textStyle: style.link,
                        ),
                        child: const Text('Completar cierre'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
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
          const SnackBar(content: Text('Guardamos tus datos.')),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No pudimos guardar tus datos. Inténtalo nuevamente.',
            ),
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

    final style = PortalStyle.of(context);
    return PopScope(
      canPop: !_isBusy,
      child: AlertDialog(
        scrollable: true,
        backgroundColor: style.panel,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PortalStyle.panelRadius),
        ),
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        title: Semantics(
          header: true,
          child: Text(
            (isSessionRevocation
                    ? 'Completar seguridad'
                    : isVerification
                        ? 'Verifica que eres tú'
                        : 'Cambiar contraseña')
                .toUpperCase(),
            style: style.pageTitle(compact: true).copyWith(fontSize: 22),
          ),
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
              foregroundColor: style.inkSecondary,
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
                foregroundColor: style.accent,
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
            style: portalPrimaryButton(context).copyWith(
              minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
            ),
            child: _isBusy
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: style.onAccent,
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
              style: TextStyle(color: PortalStyle.of(context).accent),
            ),
          ],
        ],
      ),
    );
  }
}
