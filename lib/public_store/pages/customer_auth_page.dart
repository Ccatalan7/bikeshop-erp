import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;
import 'package:vinabike_public_core/public_store/models/customer_auth_forms.dart';
import '../services/customer_account_service.dart';
import '../providers/public_store_tenant_provider.dart';
import '../theme/public_store_theme.dart';
import '../widgets/public_store_layout.dart';
import '../../shared/utils/auth_input_validation.dart';

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
  final _confirmPasswordController = TextEditingController();
  final _phoneController = TextEditingController();

  bool _isLogin = true;
  bool _isInvitationMode = false;
  bool _invitationTenantPending = false;
  bool _invitationSessionInvalid = false;
  bool _didInitializeAuthLinkMode = false;
  bool _invitationReconciliationScheduled = false;
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _showVerificationNotice = false;
  bool _showAccountConfirmedNotice = false;
  String? _verificationEmail;

  // Keep this page alive in memory to prevent reloading on navigation
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _isInvitationMode =
        CustomerAccountService.isFirstPasswordInvitationUri(Uri.base);
    _invitationTenantPending = _isInvitationMode;
    _showAccountConfirmedNotice =
        !_isInvitationMode && Uri.base.queryParameters['confirmed'] == 'true';
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final accountService = context.watch<CustomerAccountService>();
    final tenantProvider = context.watch<PublicStoreTenantProvider>();

    if (!_didInitializeAuthLinkMode) {
      _didInitializeAuthLinkMode = true;
      _isInvitationMode =
          CustomerAccountService.isFirstPasswordInvitationUri(Uri.base) ||
              accountService.isFirstPasswordInvitationVerificationPending ||
              accountService.hasFirstPasswordInvitationIntent;
      _invitationTenantPending = _isInvitationMode;
      _showAccountConfirmedNotice =
          !_isInvitationMode && Uri.base.queryParameters['confirmed'] == 'true';
    }

    if (_isInvitationMode ||
        accountService.isFirstPasswordInvitationVerificationPending ||
        accountService.hasFirstPasswordInvitationIntent) {
      _scheduleInvitationReconciliation(accountService, tenantProvider);
      return;
    }

    // `confirmed=true` is display-only. Session mutations require the Auth
    // token/event itself; a bare query parameter must never log out whichever
    // user happens to have this browser open.
  }

  void _scheduleInvitationReconciliation(
    CustomerAccountService accountService,
    PublicStoreTenantProvider tenantProvider,
  ) {
    if (_invitationReconciliationScheduled) return;
    _invitationReconciliationScheduled = true;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _invitationReconciliationScheduled = false;
      if (!mounted ||
          !(_isInvitationMode ||
              accountService.isFirstPasswordInvitationVerificationPending ||
              accountService.hasFirstPasswordInvitationIntent)) {
        return;
      }

      var tenantState =
          CustomerAccountService.firstPasswordInvitationTenantState(
        tenantId: tenantProvider.tenantId,
        isLoading: tenantProvider.isLoading,
        hasError: tenantProvider.hasError,
      );

      if (tenantState == FirstPasswordInvitationTenantState.waiting &&
          !tenantProvider.isLoading &&
          !tenantProvider.hasError) {
        await tenantProvider.detectTenant();
        if (!mounted) return;
        tenantState = CustomerAccountService.firstPasswordInvitationTenantState(
          tenantId: tenantProvider.tenantId,
          isLoading: tenantProvider.isLoading,
          hasError: tenantProvider.hasError,
        );
      }

      final tenantId = tenantProvider.tenantId?.trim();
      if (tenantState == FirstPasswordInvitationTenantState.ready) {
        // Only the tenant detected from the current storefront host can scope
        // invitation provisioning. Never fall back to an ERP session tenant.
        accountService.setTenantId(tenantId);
      }

      final invitationVerificationPending =
          accountService.isFirstPasswordInvitationVerificationPending;
      final tenantPending = invitationVerificationPending ||
          tenantState == FirstPasswordInvitationTenantState.waiting;
      final invitationInvalid = !invitationVerificationPending &&
          (!accountService.hasFirstPasswordInvitationIntent ||
              tenantState == FirstPasswordInvitationTenantState.unavailable ||
              (tenantState == FirstPasswordInvitationTenantState.ready &&
                  !accountService.hasAuthSession));
      if (_invitationTenantPending != tenantPending ||
          _invitationSessionInvalid != invitationInvalid) {
        setState(() {
          _invitationTenantPending = tenantPending;
          _invitationSessionInvalid = invitationInvalid;
        });
      }
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
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
                customerAuthVerificationSent(
                  _verificationEmail ?? _emailController.text.trim(),
                ),
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
      if (!accountService.isAuthenticated) {
        throw const AuthException(
          'No pudimos preparar la cuenta para esta tienda.',
        );
      }

      await PublicStoreLayout.navigateToHref(context, '/cuenta');
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isLogin ? customerAuthSignInFailed : customerAuthSignUpFailed,
          ),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _submitRecoveryPassword() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final accountService = context.read<CustomerAccountService>();
      await accountService.completePasswordRecovery(
        _passwordController.text,
      );
      await accountService.signOut();

      if (!mounted) return;
      setState(() {
        _isLogin = true;
        _passwordController.clear();
        _confirmPasswordController.clear();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(customerAuthPasswordRecovered),
        ),
      );
      // On the public store the login is the HTML store's page (a full load
      // that drops this bar): `?clave=` makes it say the same.
      await PublicStoreLayout.navigateToHref(
        context,
        '/cuenta/login?$customerAuthPasswordNoticeParameter=actualizada',
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_recoveryPasswordErrorMessage(error)),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _submitInvitationPassword() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      final accountService = context.read<CustomerAccountService>();
      final tenantProvider = context.read<PublicStoreTenantProvider>();
      final tenantState =
          CustomerAccountService.firstPasswordInvitationTenantState(
        tenantId: tenantProvider.tenantId,
        isLoading: tenantProvider.isLoading,
        hasError: tenantProvider.hasError,
      );
      final tenantId = tenantProvider.tenantId?.trim();

      if (!accountService.hasAuthSession ||
          !accountService.hasFirstPasswordInvitationIntent ||
          tenantState != FirstPasswordInvitationTenantState.ready ||
          tenantId == null ||
          tenantId.isEmpty) {
        if (mounted) {
          setState(() {
            _invitationTenantPending =
                tenantState == FirstPasswordInvitationTenantState.waiting;
            _invitationSessionInvalid =
                tenantState != FirstPasswordInvitationTenantState.waiting;
          });
        }
        return;
      }

      accountService.setTenantId(tenantId);
      await accountService.completeInvitedFirstPassword(
        _passwordController.text,
      );
      // updatePassword already revoked every other refresh session. This
      // closes only the current invitation session before a clean login.
      await accountService.signOut();

      if (!mounted) return;
      setState(() {
        _isInvitationMode = false;
        _invitationTenantPending = false;
        _invitationSessionInvalid = false;
        _isLogin = true;
        _passwordController.clear();
        _confirmPasswordController.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(customerAuthPasswordCreated),
        ),
      );
      await PublicStoreLayout.navigateToHref(
        context,
        '/cuenta/login?$customerAuthPasswordNoticeParameter=creada',
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(customerInvitationPrepareFailed),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _leaveInvitationMode() async {
    final accountService = context.read<CustomerAccountService>();
    setState(() => _isLoading = true);
    try {
      if (accountService.hasFirstPasswordInvitationIntent &&
          accountService.hasAuthSession) {
        await accountService.signOut();
      } else {
        accountService.clearFirstPasswordInvitationIntent();
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            customerAuthLinkCloseFailed,
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }

    if (!mounted) return;
    setState(() {
      _isInvitationMode = false;
      _invitationTenantPending = false;
      _invitationSessionInvalid = false;
      _passwordController.clear();
      _confirmPasswordController.clear();
    });
    await PublicStoreLayout.navigateToHref(context, '/cuenta/login');
  }

  Future<void> _leaveRecoveryMode() async {
    final accountService = context.read<CustomerAccountService>();
    setState(() => _isLoading = true);
    try {
      if (accountService.hasAuthSession) {
        await accountService.signOut();
      } else {
        accountService.clearPasswordRecoverySession();
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No pudimos cerrar esta sesión. Recarga la página e inténtalo nuevamente.',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }

    if (!mounted) return;
    _passwordController.clear();
    _confirmPasswordController.clear();
    await PublicStoreLayout.navigateToHref(context, '/cuenta/login');
  }

  String _recoveryPasswordErrorMessage(Object error) {
    final normalized =
        error is AuthException ? error.message.toLowerCase() : '';

    if (normalized.contains('same_password')) {
      return 'La nueva contraseña debe ser distinta a la contraseña actual.';
    }
    if (normalized.contains('otp_expired') ||
        normalized.contains('invalid or has expired')) {
      return 'El enlace de recuperación venció o ya fue usado. Genera un nuevo vínculo e inténtalo otra vez.';
    }
    if (normalized.contains('auth session missing') ||
        normalized.contains('authsessionmissingexception')) {
      return 'No pudimos confirmar la sesión de recuperación. Abre un vínculo nuevo en una pestaña privada.';
    }

    return 'No pudimos actualizar la contraseña. Inténtalo nuevamente con una contraseña nueva.';
  }

  Future<void> _signInWithGoogle() async {
    try {
      final accountService = context.read<CustomerAccountService>();
      final tenantProvider = context.read<PublicStoreTenantProvider>();
      accountService.setTenantId(tenantProvider.tenantId);
      await accountService.signInWithGoogle();
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(customerAuthGoogleFailed),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    final accountService = context.watch<CustomerAccountService>();
    final isRecoveryPending =
        accountService.isPasswordRecoveryVerificationPending;
    final isRecoveryMode =
        accountService.isPasswordRecoverySession || isRecoveryPending;
    final isInvitationMode = _isInvitationMode ||
        accountService.isFirstPasswordInvitationVerificationPending ||
        accountService.hasFirstPasswordInvitationIntent;

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
                      ? IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                  child: _buildIntroPanel(context,
                                      isRecoveryMode: isRecoveryMode,
                                      isInvitationMode: isInvitationMode)),
                              Expanded(
                                  child: _buildFormPanel(context,
                                      isRecoveryMode: isRecoveryMode,
                                      isInvitationMode: isInvitationMode,
                                      isRecoveryPending: isRecoveryPending)),
                            ],
                          ),
                        )
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildIntroPanel(context,
                                compact: true,
                                isRecoveryMode: isRecoveryMode,
                                isInvitationMode: isInvitationMode),
                            _buildFormPanel(context,
                                isRecoveryMode: isRecoveryMode,
                                isInvitationMode: isInvitationMode,
                                isRecoveryPending: isRecoveryPending),
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

  Widget _buildIntroPanel(
    BuildContext context, {
    bool compact = false,
    bool isRecoveryMode = false,
    bool isInvitationMode = false,
  }) {
    final theme = Theme.of(context);
    final mode = _mode(
      isRecoveryMode: isRecoveryMode,
      isInvitationMode: isInvitationMode,
    );

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
            customerAuthEyebrow,
            style: theme.textTheme.labelMedium?.copyWith(
              color: PublicStoreTheme.textSecondary,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            customerAuthHeadline(mode),
            style: theme.textTheme.headlineMedium?.copyWith(
              fontSize: compact ? 28 : 32,
              height: 1.15,
              color: PublicStoreTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            customerAuthLead(mode),
            style: theme.textTheme.bodyLarge?.copyWith(
              color: PublicStoreTheme.textSecondary,
            ),
          ),
          for (final (index, (icon, title, subtitle))
              in customerAuthBenefits.indexed) ...[
            SizedBox(height: index == 0 ? 28 : 16),
            _buildBenefitRow(
              icon: _benefitIcons[icon] ?? Icons.check_circle_outline,
              title: title,
              subtitle: subtitle,
            ),
          ],
          if (!compact) ...[
            const SizedBox(height: 28),
            // return-contract: explicit-destination — this is a labelled link
            // to the storefront home, not a promise to return to the origin.
            TextButton.icon(
              onPressed: () => PublicStoreLayout.navigateToHref(context, '/'),
              icon: const Icon(Icons.arrow_back, size: 18),
              label: const Text(customerAuthBackHome),
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

  CustomerAuthMode _mode({
    required bool isRecoveryMode,
    required bool isInvitationMode,
  }) =>
      isInvitationMode
          ? CustomerAuthMode.invitation
          : isRecoveryMode
              ? CustomerAuthMode.recovery
              : _isLogin
                  ? CustomerAuthMode.login
                  : CustomerAuthMode.register;

  static const _benefitIcons = <String, IconData>{
    'shopping_bag': Icons.shopping_bag_outlined,
    'pedal_bike': Icons.pedal_bike_outlined,
    'support_agent': Icons.support_agent_outlined,
  };

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

  Widget _buildFormPanel(
    BuildContext context, {
    bool isRecoveryMode = false,
    bool isInvitationMode = false,
    bool isRecoveryPending = false,
  }) {
    final theme = Theme.of(context);
    final isPasswordSetupMode = isRecoveryMode || isInvitationMode;
    final mode = _mode(
      isRecoveryMode: isRecoveryMode,
      isInvitationMode: isInvitationMode,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 30, 28, 30),
      child: isRecoveryPending
          ? _buildRecoveryVerificationLoadingView(context)
          : isInvitationMode && _invitationTenantPending
              ? _buildInvitationTenantLoadingView(context)
              : isInvitationMode && _invitationSessionInvalid
                  ? _buildInvalidInvitationView(context)
                  : Form(
                      key: _formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            customerAuthFormTitle(mode),
                            style: theme.textTheme.headlineSmall?.copyWith(
                              color: PublicStoreTheme.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            customerAuthFormLead(mode),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: PublicStoreTheme.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 24),
                          if (isPasswordSetupMode) ...[
                            _buildFieldLabel(customerAuthNewPasswordLabel),
                            TextFormField(
                              key: ValueKey(
                                isInvitationMode
                                    ? 'invited-customer-new-password'
                                    : 'customer-recovery-new-password',
                              ),
                              controller: _passwordController,
                              decoration: InputDecoration(
                                hintText:
                                    AuthInputValidation.strongPasswordHelper,
                                prefixIcon: const Icon(Icons.lock_outline),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscurePassword
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined,
                                  ),
                                  onPressed: () {
                                    setState(
                                      () =>
                                          _obscurePassword = !_obscurePassword,
                                    );
                                  },
                                ),
                              ),
                              obscureText: _obscurePassword,
                              validator: (value) =>
                                  AuthInputValidation.validatePassword(
                                value,
                                isNewPassword: true,
                              ),
                            ),
                            const SizedBox(height: 16),
                            _buildFieldLabel(customerAuthConfirmLabel),
                            TextFormField(
                              controller: _confirmPasswordController,
                              decoration: const InputDecoration(
                                hintText: customerAuthConfirmHint,
                                prefixIcon: Icon(Icons.lock_reset_outlined),
                              ),
                              obscureText: _obscurePassword,
                              validator: (value) => AuthInputValidation
                                  .validatePasswordConfirmation(
                                value,
                                password: _passwordController.text,
                              ),
                            ),
                            const SizedBox(height: 22),
                            FilledButton(
                              key: ValueKey(
                                isInvitationMode
                                    ? 'complete-customer-invitation-password'
                                    : 'complete-customer-recovery-password',
                              ),
                              onPressed: _isLoading
                                  ? null
                                  : isInvitationMode
                                      ? _submitInvitationPassword
                                      : _submitRecoveryPassword,
                              style: FilledButton.styleFrom(
                                backgroundColor: PublicStoreTheme.textPrimary,
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 15),
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
                                  : Text(customerAuthSubmit(mode)),
                            ),
                            const SizedBox(height: 14),
                            TextButton(
                              onPressed: _isLoading
                                  ? null
                                  : () {
                                      if (isInvitationMode) {
                                        _leaveInvitationMode();
                                        return;
                                      }
                                      _leaveRecoveryMode();
                                    },
                              child: const Text(customerAuthBackToLogin),
                            ),
                          ] else ...[
                            if (_showAccountConfirmedNotice) ...[
                              Container(
                                margin: const EdgeInsets.only(bottom: 20),
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEFF8F2),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                      color: const Color(0xFFB7E2C3)),
                                ),
                                child: const Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(Icons.check_circle_outline,
                                        color: Color(0xFF2E7D4F)),
                                    SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        customerAuthConfirmedNotice,
                                        style: TextStyle(
                                          color: Color(0xFF1F5D3B),
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            if (_showVerificationNotice &&
                                _verificationEmail != null) ...[
                              Container(
                                margin: const EdgeInsets.only(bottom: 20),
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: PublicStoreTheme.surface,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: PublicStoreTheme.border
                                        .withValues(alpha: 0.85),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      customerAuthVerifyTitle,
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                        color: PublicStoreTheme.textPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      customerAuthVerifyBody(
                                        _verificationEmail!,
                                      ),
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
                                              final messenger =
                                                  ScaffoldMessenger.of(context);
                                              final accountService =
                                                  context.read<
                                                      CustomerAccountService>();
                                              try {
                                                setState(
                                                    () => _isLoading = true);
                                                await accountService
                                                    .resendVerificationEmail();
                                                if (mounted) {
                                                  messenger.showSnackBar(
                                                    const SnackBar(
                                                      content: Text(
                                                        customerAuthResent,
                                                      ),
                                                    ),
                                                  );
                                                }
                                              } catch (_) {
                                                if (mounted) {
                                                  messenger.showSnackBar(
                                                    const SnackBar(
                                                      content: Text(
                                                        customerAuthResendFailed,
                                                      ),
                                                      backgroundColor:
                                                          Colors.red,
                                                    ),
                                                  );
                                                }
                                              } finally {
                                                if (mounted) {
                                                  setState(
                                                      () => _isLoading = false);
                                                }
                                              }
                                            },
                                      icon: const Icon(
                                          Icons.mark_email_unread_outlined),
                                      label: const Text(customerAuthResend),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor:
                                            PublicStoreTheme.textPrimary,
                                        side: BorderSide(
                                          color: PublicStoreTheme.border
                                              .withValues(alpha: 0.9),
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 18,
                                          vertical: 14,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            if (!_isLogin) ...[
                              _buildFieldLabel(customerAuthNameLabel),
                              TextFormField(
                                controller: _nameController,
                                decoration: const InputDecoration(
                                  hintText: customerAuthNameHint,
                                  prefixIcon: Icon(Icons.person_outline),
                                ),
                                validator: customerAuthNameError,
                              ),
                              const SizedBox(height: 16),
                            ],
                            _buildFieldLabel(customerAuthEmailLabel),
                            TextFormField(
                              controller: _emailController,
                              decoration: const InputDecoration(
                                hintText: customerAuthEmailHint,
                                prefixIcon: Icon(Icons.email_outlined),
                              ),
                              keyboardType: TextInputType.emailAddress,
                              validator: customerAuthEmailError,
                            ),
                            const SizedBox(height: 16),
                            if (!_isLogin) ...[
                              _buildFieldLabel(customerAuthPhoneLabel),
                              TextFormField(
                                controller: _phoneController,
                                decoration: const InputDecoration(
                                  hintText: customerAuthPhoneHint,
                                  prefixIcon: Icon(Icons.phone_outlined),
                                ),
                                keyboardType: TextInputType.phone,
                              ),
                              const SizedBox(height: 16),
                            ],
                            _buildFieldLabel(customerAuthPasswordLabel),
                            TextFormField(
                              controller: _passwordController,
                              decoration: InputDecoration(
                                hintText: customerAuthPasswordHint(mode),
                                prefixIcon: const Icon(Icons.lock_outline),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscurePassword
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined,
                                  ),
                                  onPressed: () {
                                    setState(() =>
                                        _obscurePassword = !_obscurePassword);
                                  },
                                ),
                              ),
                              obscureText: _obscurePassword,
                              validator: (value) =>
                                  customerAuthPasswordError(value, mode),
                            ),
                            const SizedBox(height: 22),
                            FilledButton(
                              onPressed: _isLoading ? null : _submit,
                              style: FilledButton.styleFrom(
                                backgroundColor: PublicStoreTheme.textPrimary,
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 15),
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
                                  : Text(customerAuthSubmit(mode)),
                            ),
                            const SizedBox(height: 18),
                            Row(
                              children: [
                                Expanded(
                                  child: Container(
                                    height: 1,
                                    color: PublicStoreTheme.border
                                        .withValues(alpha: 0.9),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14),
                                  child: Text(
                                    customerAuthOr,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: PublicStoreTheme.textSecondary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Container(
                                    height: 1,
                                    color: PublicStoreTheme.border
                                        .withValues(alpha: 0.9),
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
                              label: Text(customerAuthGoogle(mode)),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: PublicStoreTheme.textPrimary,
                                backgroundColor: Colors.white,
                                side: BorderSide(
                                  color: PublicStoreTheme.border
                                      .withValues(alpha: 0.9),
                                ),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
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
                                  customerAuthSwitchQuestion(mode),
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
                                    foregroundColor:
                                        PublicStoreTheme.textPrimary,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    textStyle: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  child: Text(customerAuthSwitchAction(mode)),
                                ),
                              ],
                            ),
                            if (_isLogin)
                              Align(
                                alignment: Alignment.center,
                                child: TextButton(
                                  onPressed: _showPasswordResetDialog,
                                  style: TextButton.styleFrom(
                                    foregroundColor:
                                        PublicStoreTheme.textSecondary,
                                    textStyle: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  child: const Text(customerAuthForgot),
                                ),
                              ),
                          ],
                        ],
                      ),
                    ),
    );
  }

  Widget _buildInvalidInvitationView(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(
          Icons.mark_email_unread_outlined,
          size: 44,
          color: theme.colorScheme.error,
        ),
        const SizedBox(height: 16),
        Text(
          customerInvitationInvalidTitle,
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall?.copyWith(
            color: PublicStoreTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          customerInvitationInvalidBody,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: PublicStoreTheme.textSecondary,
          ),
        ),
        const SizedBox(height: 24),
        FilledButton(
          key: const ValueKey('invalid-customer-invitation-login'),
          onPressed: _isLoading ? null : _leaveInvitationMode,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
          ),
          child: _isLoading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(customerAuthBackToLogin.toUpperCase()),
        ),
      ],
    );
  }

  Widget _buildInvitationTenantLoadingView(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      key: const ValueKey('customer-invitation-tenant-loading'),
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 18),
        Text(
          'Validando la tienda de esta invitación…',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: PublicStoreTheme.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildRecoveryVerificationLoadingView(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      key: const ValueKey('customer-recovery-verification-loading'),
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 18),
        Text(
          customerAuthLinkChecking(CustomerAuthMode.recovery),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: PublicStoreTheme.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
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
        title: const Text(customerResetTitle),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(customerResetBody),
              const SizedBox(height: 16),
              TextFormField(
                controller: emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: customerAuthEmailLabel,
                  prefixIcon: Icon(Icons.email_outlined),
                ),
                validator: customerAuthEmailError,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text(customerResetCancel),
          ),
          FilledButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              final messenger = ScaffoldMessenger.of(context);
              final email = emailController.text.trim();
              try {
                await context
                    .read<CustomerAccountService>()
                    .resetPassword(email);
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text(customerResetSent),
                  ),
                );
              } on AuthException catch (error) {
                final isRateLimited = customerResetIsRateLimited(
                  code: error.code,
                  message: error.message,
                );
                if (!isRateLimited) {
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text(customerResetSent),
                    ),
                  );
                  return;
                }
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text(customerResetRateLimited),
                    backgroundColor: Colors.red,
                  ),
                );
              } catch (_) {
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text(customerResetOffline),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text(customerResetSend),
          ),
        ],
      ),
    );

    emailController.dispose();
  }
}
