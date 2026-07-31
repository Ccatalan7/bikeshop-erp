import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../shared/utils/chilean_utils.dart';
import '../../../shared/widgets/branded_loading.dart';
import '../models/company_profile.dart';
import '../services/company_profile_service.dart';

class CompanySettingsPage extends StatefulWidget {
  const CompanySettingsPage({super.key});

  @override
  State<CompanySettingsPage> createState() => _CompanySettingsPageState();
}

class _CompanySettingsPageState extends State<CompanySettingsPage> {
  final _formKey = GlobalKey<FormState>();
  final _service = CompanyProfileService();

  final _nameController = TextEditingController();
  final _legalNameController = TextEditingController();
  final _fantasyNameController = TextEditingController();
  final _taxIdController = TextEditingController();
  final _businessActivityController = TextEditingController();
  final _addressController = TextEditingController();
  final _comunaController = TextEditingController();
  final _cityController = TextEditingController();
  final _regionController = TextEditingController();
  final _postalCodeController = TextEditingController();
  final _countryController = TextEditingController(text: 'Chile');
  final _phoneController = TextEditingController();
  final _whatsappPhoneController = TextEditingController();
  final _whatsappApiPhoneController = TextEditingController();
  final _supportPhoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _billingEmailController = TextEditingController();
  final _publicEmailController = TextEditingController();
  final _websiteUrlController = TextEditingController();
  final _bankLabelController = TextEditingController();
  final _bankNameController = TextEditingController();
  final _bankAccountTypeController = TextEditingController();
  final _bankAccountNumberController = TextEditingController();
  final _bankHolderNameController = TextEditingController();
  final _bankHolderRutController = TextEditingController();
  final _bankContactEmailController = TextEditingController();
  final _bankNotesController = TextEditingController();

  CompanyProfile? _profile;
  List<CompanyBankAccount> _bankAccounts = [];
  int _selectedBankIndex = -1;
  bool _selectedBankIsDefault = false;
  bool _selectedBankIsActive = true;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _syncPublicData = true;

  @override
  void initState() {
    super.initState();
    _loadCompany();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _legalNameController.dispose();
    _fantasyNameController.dispose();
    _taxIdController.dispose();
    _businessActivityController.dispose();
    _addressController.dispose();
    _comunaController.dispose();
    _cityController.dispose();
    _regionController.dispose();
    _postalCodeController.dispose();
    _countryController.dispose();
    _phoneController.dispose();
    _whatsappPhoneController.dispose();
    _whatsappApiPhoneController.dispose();
    _supportPhoneController.dispose();
    _emailController.dispose();
    _billingEmailController.dispose();
    _publicEmailController.dispose();
    _websiteUrlController.dispose();
    _bankLabelController.dispose();
    _bankNameController.dispose();
    _bankAccountTypeController.dispose();
    _bankAccountNumberController.dispose();
    _bankHolderNameController.dispose();
    _bankHolderRutController.dispose();
    _bankContactEmailController.dispose();
    _bankNotesController.dispose();
    super.dispose();
  }

  Future<void> _loadCompany() async {
    try {
      final profile = await _service.loadInitialCompanyProfile();
      if (!mounted) return;
      _profile = profile;
      _fillControllers(profile);
      if ((profile.id ?? '').isNotEmpty) {
        _bankAccounts = await _service.loadBankAccounts(
          profile.id!,
          expectedTenantId: profile.tenantId!,
        );
        _selectedBankIndex = _bankAccounts.isEmpty ? -1 : 0;
        _fillBankControllers(_selectedBank);
      }
    } catch (error) {
      if (!mounted) return;
      _showSnackBar('No se pudieron cargar los datos de empresa: $error');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _fillControllers(CompanyProfile profile) {
    _nameController.text = profile.name;
    _legalNameController.text = profile.legalName;
    _fantasyNameController.text = profile.fantasyName;
    _taxIdController.text = profile.formattedTaxId.isNotEmpty
        ? profile.formattedTaxId
        : profile.taxId;
    _businessActivityController.text = profile.businessActivity;
    _addressController.text = profile.address;
    _comunaController.text = profile.comuna;
    _cityController.text = profile.city;
    _regionController.text = profile.region;
    _postalCodeController.text = profile.postalCode;
    _countryController.text =
        profile.country.isEmpty ? 'Chile' : profile.country;
    _phoneController.text = profile.phone;
    _whatsappPhoneController.text = profile.whatsappPhone;
    _whatsappApiPhoneController.text = profile.whatsappApiPhone;
    _supportPhoneController.text = profile.supportPhone;
    _emailController.text = profile.email;
    _billingEmailController.text = profile.billingEmail;
    _publicEmailController.text = profile.publicEmail;
    _websiteUrlController.text = profile.websiteUrl;
  }

  Future<void> _saveCompany() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;
    final loadedProfile = _profile;
    if (loadedProfile == null || (loadedProfile.tenantId ?? '').isEmpty) {
      _showSnackBar(
        'Los datos de empresa ya no pertenecen al tenant activo. '
        'Vuelve a abrir esta sección.',
      );
      return;
    }

    _commitBankDraft();
    if (!_bankAccountsAreValid()) {
      _showSnackBar('Revisa las cuentas bancarias antes de guardar');
      return;
    }
    setState(() => _isSaving = true);

    final taxId = ChileanUtils.formatRut(_taxIdController.text).toUpperCase();
    final profile = loadedProfile.copyWith(
      name: _text(_nameController),
      legalName: _text(_legalNameController),
      fantasyName: _text(_fantasyNameController),
      taxId: taxId,
      businessActivity: _text(_businessActivityController),
      address: _text(_addressController),
      comuna: _text(_comunaController),
      city: _text(_cityController),
      region: _text(_regionController),
      postalCode: _text(_postalCodeController),
      country: _text(_countryController).isEmpty
          ? 'Chile'
          : _text(_countryController),
      phone: _text(_phoneController),
      whatsappPhone: _text(_whatsappPhoneController),
      whatsappApiPhone: _text(_whatsappApiPhoneController),
      supportPhone: _text(_supportPhoneController),
      email: _text(_emailController),
      billingEmail: _text(_billingEmailController),
      publicEmail: _text(_publicEmailController),
      websiteUrl: _normalizeWebsiteUrl(_websiteUrlController.text),
      isDefault: true,
      metadata: {
        ...?_profile?.metadata,
        'public_sync_enabled': _syncPublicData,
      },
    );

    try {
      final saved = await _service.saveCompany(
        profile,
        syncPublicData: false,
      );
      final savedAccounts = (saved.id ?? '').isEmpty
          ? <CompanyBankAccount>[]
          : await _service.saveBankAccounts(
              companyId: saved.id!,
              accounts: _bankAccounts,
              expectedTenantId: saved.tenantId!,
            );
      final defaultBankAccount = _defaultBankAccount(savedAccounts);
      if (_syncPublicData) {
        await _service.syncPublicSettings(
          saved,
          defaultBankAccount: defaultBankAccount,
        );
      }
      if (!mounted) return;
      _profile = saved;
      _bankAccounts = savedAccounts;
      _selectedBankIndex = _clampBankIndex(_selectedBankIndex);
      _fillControllers(saved);
      _fillBankControllers(_selectedBank);
      _showSnackBar('Datos de empresa guardados');
    } catch (error) {
      if (!mounted) return;
      _showSnackBar('No se pudo guardar: $error');
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  CompanyBankAccount? get _selectedBank {
    if (_selectedBankIndex < 0 || _selectedBankIndex >= _bankAccounts.length) {
      return null;
    }
    return _bankAccounts[_selectedBankIndex];
  }

  void _fillBankControllers(CompanyBankAccount? account) {
    _bankLabelController.text = account?.label ?? '';
    _bankNameController.text = account?.bankName ?? 'Banco de Chile';
    _bankAccountTypeController.text =
        account?.accountType ?? 'Cuenta corriente';
    _bankAccountNumberController.text = account?.accountNumber ?? '';
    _bankHolderNameController.text = account?.holderName ?? '';
    _bankHolderRutController.text = account?.holderRut ?? '';
    _bankContactEmailController.text = account?.contactEmail ?? '';
    _bankNotesController.text = account?.notes ?? '';
    _selectedBankIsDefault = account?.isDefault ?? false;
    _selectedBankIsActive = account?.isActive ?? true;
  }

  void _commitBankDraft() {
    final selected = _selectedBank;
    if (selected == null) return;

    final updated = selected.copyWith(
      label: _text(_bankLabelController),
      bankName: _text(_bankNameController),
      accountType: _text(_bankAccountTypeController).isEmpty
          ? 'Cuenta corriente'
          : _text(_bankAccountTypeController),
      accountNumber: _text(_bankAccountNumberController),
      holderName: _text(_bankHolderNameController),
      holderRut: _bankHolderRutController.text.trim().isEmpty
          ? ''
          : ChileanUtils.formatRut(_bankHolderRutController.text).toUpperCase(),
      contactEmail: _text(_bankContactEmailController),
      notes: _text(_bankNotesController),
      isDefault: _selectedBankIsDefault,
      isActive: _selectedBankIsActive,
    );

    _bankAccounts = [
      for (var index = 0; index < _bankAccounts.length; index++)
        if (index == _selectedBankIndex)
          updated
        else if (_selectedBankIsDefault)
          _bankAccounts[index].copyWith(isDefault: false)
        else
          _bankAccounts[index],
    ];
  }

  void _selectBankAccount(int index) {
    _commitBankDraft();
    setState(() {
      _selectedBankIndex = index;
      _fillBankControllers(_selectedBank);
    });
  }

  void _addBankAccount() {
    final loadedProfile = _profile;
    if (loadedProfile == null || (loadedProfile.tenantId ?? '').isEmpty) {
      _showSnackBar(
        'Vuelve a abrir esta sección antes de agregar una cuenta.',
      );
      return;
    }
    _commitBankDraft();
    final company = loadedProfile.copyWith(
      legalName: _text(_legalNameController),
      name: _text(_nameController),
      taxId: _text(_taxIdController),
      billingEmail: _text(_billingEmailController),
      publicEmail: _text(_publicEmailController),
      email: _text(_emailController),
    );
    final nextIndex = _bankAccounts.length + 1;
    final account = CompanyBankAccount.empty(
      tenantId: loadedProfile.tenantId,
      companyId: loadedProfile.id,
      index: nextIndex,
      company: company,
      isDefault: _bankAccounts.isEmpty,
    );

    setState(() {
      _bankAccounts = [..._bankAccounts, account];
      _selectedBankIndex = _bankAccounts.length - 1;
      _fillBankControllers(account);
    });
  }

  void _removeSelectedBankAccount() {
    if (_selectedBank == null) return;

    final wasDefault = _selectedBank!.isDefault;
    final updated = [..._bankAccounts]..removeAt(_selectedBankIndex);
    if (wasDefault && updated.isNotEmpty) {
      updated[0] = updated[0].copyWith(isDefault: true);
    }

    setState(() {
      _bankAccounts = updated;
      _selectedBankIndex = _clampBankIndex(_selectedBankIndex);
      _fillBankControllers(_selectedBank);
    });
  }

  int _clampBankIndex(int index) {
    if (_bankAccounts.isEmpty) return -1;
    if (index < 0) return 0;
    if (index >= _bankAccounts.length) return _bankAccounts.length - 1;
    return index;
  }

  bool _bankAccountsAreValid() {
    for (final account in _bankAccounts) {
      if (account.label.trim().isEmpty ||
          account.bankName.trim().isEmpty ||
          account.accountType.trim().isEmpty ||
          account.accountNumber.trim().isEmpty ||
          account.holderName.trim().isEmpty ||
          account.holderRut.trim().isEmpty ||
          !ChileanUtils.isValidRut(account.holderRut)) {
        return false;
      }
      final email = account.contactEmail.trim();
      if (email.isNotEmpty && !ChileanUtils.isValidEmail(email)) {
        return false;
      }
    }
    return true;
  }

  CompanyBankAccount? _defaultBankAccount(List<CompanyBankAccount> accounts) {
    if (accounts.isEmpty) return null;
    for (final account in accounts) {
      if (account.isDefault) return account;
    }
    return accounts.first;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        title: const Text('Datos de empresa'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.icon(
              onPressed: _isSaving || _isLoading ? null : _saveCompany,
              icon: _isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined, size: 18),
              label: Text(_isSaving ? 'Guardando' : 'Guardar'),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: BrandedLoading())
          : LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 1060;
                final content = Form(
                  key: _formKey,
                  child: isWide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 330,
                              child: _buildSummaryPanel(context),
                            ),
                            const SizedBox(width: 20),
                            Expanded(
                                child: _buildFormSections(context, isWide)),
                          ],
                        )
                      : Column(
                          children: [
                            _buildSummaryPanel(context),
                            const SizedBox(height: 16),
                            _buildFormSections(context, isWide),
                          ],
                        ),
                );

                return SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    isWide ? 28 : 16,
                    18,
                    isWide ? 28 : 16,
                    32,
                  ),
                  child: content,
                );
              },
            ),
    );
  }

  Widget _buildSummaryPanel(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final displayName = _fantasyNameController.text.trim().isNotEmpty
        ? _fantasyNameController.text.trim()
        : _nameController.text.trim();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.apartment_rounded,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName.isEmpty ? 'Empresa principal' : displayName,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      _legalNameController.text.trim().isEmpty
                          ? 'Razon social pendiente'
                          : _legalNameController.text.trim(),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _SummaryLine(
            label: 'RUT',
            value: _taxIdController.text.trim().isEmpty
                ? 'No definido'
                : _taxIdController.text.trim(),
          ),
          _SummaryLine(
            label: 'Giro',
            value: _businessActivityController.text.trim().isEmpty
                ? 'No definido'
                : _businessActivityController.text.trim(),
          ),
          _SummaryLine(
            label: 'Contacto',
            value: _publicEmailController.text.trim().isNotEmpty
                ? _publicEmailController.text.trim()
                : (_emailController.text.trim().isEmpty
                    ? 'No definido'
                    : _emailController.text.trim()),
          ),
          _SummaryLine(
            label: 'WhatsApp tienda',
            value: _whatsappPhoneController.text.trim().isEmpty
                ? 'No definido'
                : _whatsappPhoneController.text.trim(),
          ),
          _SummaryLine(
            label: 'WhatsApp API',
            value: _whatsappApiPhoneController.text.trim().isEmpty
                ? 'No definido'
                : _whatsappApiPhoneController.text.trim(),
          ),
          const SizedBox(height: 12),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: _syncPublicData,
            onChanged: _isSaving
                ? null
                : (value) => setState(() => _syncPublicData = value),
            title: Text(
              'Sincronizar datos públicos',
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            subtitle: Text(
              'Actualiza tienda web, contacto y SEO al guardar.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormSections(BuildContext context, bool isWide) {
    return Column(
      children: [
        _SectionCard(
          icon: Icons.receipt_long_outlined,
          title: 'Identidad tributaria',
          children: [
            _ResponsiveFields(
              isWide: isWide,
              children: [
                _AppTextField(
                  controller: _fantasyNameController,
                  label: 'Nombre de fantasia *',
                  hint: 'Nombre comercial',
                  validator: _requiredValidator,
                  onChanged: (_) => setState(() {}),
                ),
                _AppTextField(
                  controller: _nameController,
                  label: 'Nombre interno *',
                  hint: 'Nombre de la empresa',
                  validator: _requiredValidator,
                  onChanged: (_) => setState(() {}),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _ResponsiveFields(
              isWide: isWide,
              children: [
                _AppTextField(
                  controller: _legalNameController,
                  label: 'Razon social *',
                  hint: 'Empresa Ejemplo SpA',
                  validator: _requiredValidator,
                  onChanged: (_) => setState(() {}),
                ),
                _AppTextField(
                  controller: _taxIdController,
                  label: 'RUT *',
                  hint: '12.345.678-5',
                  keyboardType: TextInputType.text,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9kK.\-]')),
                  ],
                  validator: _rutValidator,
                  onEditingComplete: () {
                    _taxIdController.text = ChileanUtils.formatRut(
                      _taxIdController.text,
                    ).toUpperCase();
                  },
                  onChanged: (_) => setState(() {}),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _AppTextField(
              controller: _businessActivityController,
              label: 'Giro *',
              hint: 'Actividad económica principal...',
              minLines: 2,
              maxLines: 3,
              validator: _requiredValidator,
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _SectionCard(
          icon: Icons.alternate_email_outlined,
          title: 'Contacto y canales',
          children: [
            _ResponsiveFields(
              isWide: isWide,
              children: [
                _AppTextField(
                  controller: _emailController,
                  label: 'Email interno',
                  hint: 'administracion@tuempresa.cl',
                  keyboardType: TextInputType.emailAddress,
                  validator: _optionalEmailValidator,
                ),
                _AppTextField(
                  controller: _publicEmailController,
                  label: 'Email publico',
                  hint: 'contacto@tuempresa.cl',
                  keyboardType: TextInputType.emailAddress,
                  validator: _optionalEmailValidator,
                ),
              ],
            ),
            const SizedBox(height: 12),
            _ResponsiveFields(
              isWide: isWide,
              children: [
                _AppTextField(
                  controller: _billingEmailController,
                  label: 'Email facturacion',
                  hint: 'facturacion@tuempresa.cl',
                  keyboardType: TextInputType.emailAddress,
                  validator: _optionalEmailValidator,
                ),
                _AppTextField(
                  controller: _websiteUrlController,
                  label: 'Sitio web',
                  hint: 'https://tuempresa.cl',
                  keyboardType: TextInputType.url,
                ),
              ],
            ),
            const SizedBox(height: 12),
            _ResponsiveFields(
              isWide: isWide,
              children: [
                _AppTextField(
                  controller: _phoneController,
                  label: 'Telefono principal',
                  hint: '+56 9 1234 5678',
                  keyboardType: TextInputType.phone,
                ),
                _AppTextField(
                  controller: _supportPhoneController,
                  label: 'Soporte',
                  hint: '+56 9 1234 5678',
                  keyboardType: TextInputType.phone,
                ),
              ],
            ),
            const SizedBox(height: 12),
            _ResponsiveFields(
              isWide: isWide,
              children: [
                _AppTextField(
                  controller: _whatsappPhoneController,
                  label: 'WhatsApp tienda / SIM',
                  hint: '+56 9 1234 5678',
                  keyboardType: TextInputType.phone,
                ),
                _AppTextField(
                  controller: _whatsappApiPhoneController,
                  label: 'WhatsApp API Meta',
                  hint: '+56 9 1234 5678',
                  keyboardType: TextInputType.phone,
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        _SectionCard(
          icon: Icons.account_balance_outlined,
          title: 'Cuentas bancarias',
          children: [
            _buildBankAccountNavigator(context),
            if (_selectedBank != null) ...[
              const SizedBox(height: 14),
              _buildBankAccountEditor(context, isWide),
            ],
          ],
        ),
        const SizedBox(height: 16),
        _SectionCard(
          icon: Icons.location_on_outlined,
          title: 'Direccion fisica',
          children: [
            _AppTextField(
              controller: _addressController,
              label: 'Direccion',
              hint: 'Calle, numero, local',
            ),
            const SizedBox(height: 12),
            _ResponsiveFields(
              isWide: isWide,
              children: [
                _AppTextField(
                  controller: _comunaController,
                  label: 'Comuna',
                  hint: 'Viña del Mar',
                ),
                _AppTextField(
                  controller: _cityController,
                  label: 'Ciudad',
                  hint: 'Viña del Mar',
                ),
              ],
            ),
            const SizedBox(height: 12),
            _ResponsiveFields(
              isWide: isWide,
              children: [
                _AppTextField(
                  controller: _regionController,
                  label: 'Region',
                  hint: 'Valparaiso',
                ),
                _AppTextField(
                  controller: _postalCodeController,
                  label: 'Codigo postal',
                  keyboardType: TextInputType.number,
                ),
                _AppTextField(
                  controller: _countryController,
                  label: 'Pais',
                  hint: 'Chile',
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildBankAccountNavigator(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (_bankAccounts.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.7),
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.account_balance_wallet_outlined,
              size: 20,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Sin cuentas bancarias',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            OutlinedButton.icon(
              onPressed: _addBankAccount,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Agregar'),
            ),
          ],
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var index = 0; index < _bankAccounts.length; index++) ...[
                  if (index > 0) const SizedBox(width: 8),
                  _BankAccountChip(
                    account: _bankAccounts[index],
                    selected: index == _selectedBankIndex,
                    onTap: () => _selectBankAccount(index),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        IconButton.filledTonal(
          tooltip: 'Agregar cuenta',
          onPressed: _addBankAccount,
          icon: const Icon(Icons.add, size: 19),
        ),
        const SizedBox(width: 6),
        IconButton(
          tooltip: 'Eliminar cuenta',
          onPressed: _removeSelectedBankAccount,
          icon: const Icon(Icons.delete_outline, size: 19),
        ),
      ],
    );
  }

  Widget _buildBankAccountEditor(BuildContext context, bool isWide) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _CompactSwitch(
                label: 'Predeterminada',
                value: _selectedBankIsDefault,
                onChanged: (value) => setState(() {
                  _selectedBankIsDefault = value;
                  if (value) {
                    _bankAccounts = [
                      for (var index = 0; index < _bankAccounts.length; index++)
                        _bankAccounts[index].copyWith(
                          isDefault: index == _selectedBankIndex,
                        ),
                    ];
                  }
                }),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _CompactSwitch(
                label: 'Activa',
                value: _selectedBankIsActive,
                onChanged: (value) => setState(() {
                  _selectedBankIsActive = value;
                }),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _ResponsiveFields(
          isWide: isWide,
          children: [
            _AppTextField(
              controller: _bankLabelController,
              label: 'Etiqueta *',
              hint: 'Cuenta principal',
              validator: _requiredValidator,
            ),
            _AppDropdownField(
              controller: _bankNameController,
              label: 'Banco *',
              values: CompanyBankAccount.chileanBanks,
              validator: _requiredValidator,
            ),
            _AppDropdownField(
              controller: _bankAccountTypeController,
              label: 'Tipo de cuenta *',
              values: CompanyBankAccount.accountTypes,
              validator: _requiredValidator,
            ),
          ],
        ),
        const SizedBox(height: 12),
        _ResponsiveFields(
          isWide: isWide,
          children: [
            _AppTextField(
              controller: _bankAccountNumberController,
              label: 'Numero de cuenta *',
              keyboardType: TextInputType.text,
              validator: _requiredValidator,
            ),
            _AppTextField(
              controller: _bankHolderNameController,
              label: 'Titular *',
              hint: 'Empresa Ejemplo SpA',
              validator: _requiredValidator,
            ),
            _AppTextField(
              controller: _bankHolderRutController,
              label: 'RUT titular *',
              hint: '12.345.678-5',
              keyboardType: TextInputType.text,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9kK.\-]')),
              ],
              validator: _rutValidator,
              onEditingComplete: () {
                _bankHolderRutController.text = ChileanUtils.formatRut(
                  _bankHolderRutController.text,
                ).toUpperCase();
              },
            ),
          ],
        ),
        const SizedBox(height: 12),
        _ResponsiveFields(
          isWide: isWide,
          children: [
            _AppTextField(
              controller: _bankContactEmailController,
              label: 'Email comprobantes',
              hint: 'comprobantes@tuempresa.cl',
              keyboardType: TextInputType.emailAddress,
              validator: _optionalEmailValidator,
            ),
            _AppTextField(
              controller: _bankNotesController,
              label: 'Instrucciones',
              hint: 'Enviar comprobante al correo indicado',
            ),
          ],
        ),
      ],
    );
  }

  String? _requiredValidator(String? value) {
    if ((value ?? '').trim().isEmpty) return 'Campo requerido';
    return null;
  }

  String? _rutValidator(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return 'Campo requerido';
    if (!ChileanUtils.isValidRut(text)) return 'RUT invalido';
    return null;
  }

  String? _optionalEmailValidator(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return null;
    if (!ChileanUtils.isValidEmail(text)) return 'Email invalido';
    return null;
  }

  String _normalizeWebsiteUrl(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '';
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    return 'https://$trimmed';
  }

  String _text(TextEditingController controller) => controller.text.trim();

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.icon,
    required this.title,
    required this.children,
  });

  final IconData icon;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: colorScheme.primary),
              const SizedBox(width: 10),
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }
}

class _ResponsiveFields extends StatelessWidget {
  const _ResponsiveFields({
    required this.isWide,
    required this.children,
  });

  final bool isWide;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (!isWide || children.length == 1) {
      return Column(
        children: [
          for (var index = 0; index < children.length; index++) ...[
            if (index > 0) const SizedBox(height: 12),
            children[index],
          ],
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < children.length; index++) ...[
          if (index > 0) const SizedBox(width: 12),
          Expanded(child: children[index]),
        ],
      ],
    );
  }
}

class _AppTextField extends StatelessWidget {
  const _AppTextField({
    required this.controller,
    required this.label,
    this.hint,
    this.keyboardType,
    this.inputFormatters,
    this.validator,
    this.onChanged,
    this.onEditingComplete,
    this.minLines = 1,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onEditingComplete;
  final int minLines;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          validator: validator,
          onChanged: onChanged,
          onEditingComplete: onEditingComplete,
          minLines: minLines,
          maxLines: maxLines,
          decoration: InputDecoration(
            hintText: hint,
            isDense: true,
            filled: true,
            fillColor: Theme.of(context).colorScheme.surfaceContainerLowest,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
          ),
        ),
      ],
    );
  }
}

class _AppDropdownField extends StatelessWidget {
  const _AppDropdownField({
    required this.controller,
    required this.label,
    required this.values,
    this.validator,
  });

  final TextEditingController controller;
  final String label;
  final List<String> values;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentValue = values.contains(controller.text)
        ? controller.text
        : (values.isEmpty ? null : values.first);

    if (currentValue != null && controller.text != currentValue) {
      controller.text = currentValue;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          key: ValueKey('$label-$currentValue'),
          initialValue: currentValue,
          validator: validator,
          isExpanded: true,
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: Theme.of(context).colorScheme.surfaceContainerLowest,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
          ),
          items: [
            for (final value in values)
              DropdownMenuItem(
                value: value,
                child: Text(value),
              ),
          ],
          onChanged: (value) {
            if (value != null) controller.text = value;
          },
        ),
      ],
    );
  }
}

class _CompactSwitch extends StatelessWidget {
  const _CompactSwitch({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.7),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _BankAccountChip extends StatelessWidget {
  const _BankAccountChip({
    required this.account,
    required this.selected,
    required this.onTap,
  });

  final CompanyBankAccount account;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final accent = selected ? colorScheme.primary : colorScheme.outlineVariant;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Ink(
          width: 210,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? colorScheme.primary.withValues(alpha: 0.08)
                : colorScheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: accent.withValues(alpha: 0.75)),
          ),
          child: Row(
            children: [
              Icon(
                Icons.account_balance_outlined,
                size: 18,
                color: selected
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            account.displayLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: selected
                                  ? colorScheme.primary
                                  : colorScheme.onSurface,
                            ),
                          ),
                        ),
                        if (account.isDefault)
                          Container(
                            margin: const EdgeInsets.only(left: 6),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: colorScheme.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              'Default',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: colorScheme.primary,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        account.bankName,
                        account.maskedAccountNumber,
                      ].where((value) => value.trim().isNotEmpty).join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryLine extends StatelessWidget {
  const _SummaryLine({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w600,
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }
}
