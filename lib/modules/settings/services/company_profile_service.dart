import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/services/tenant_service.dart';
import '../models/company_profile.dart';

class CompanyProfileService {
  CompanyProfileService({
    SupabaseClient? client,
    TenantService? tenantService,
  })  : _supabase = client ?? Supabase.instance.client,
        _tenantService = tenantService ?? TenantService();

  final SupabaseClient _supabase;
  final TenantService _tenantService;

  Future<CompanyProfile?> loadDefaultCompany() async {
    final tenantId = await _requireTenantId();
    return _loadDefaultCompanyForTenant(tenantId);
  }

  Future<CompanyProfile?> _loadDefaultCompanyForTenant(String tenantId) async {
    final defaultRow = await _supabase
        .from('companies')
        .select()
        .eq('tenant_id', tenantId)
        .eq('is_default', true)
        .order('updated_at', ascending: false)
        .limit(1)
        .maybeSingle();
    await _assertTenantLease(tenantId);

    if (defaultRow != null) {
      return CompanyProfile.fromMap(defaultRow);
    }

    final firstRow = await _supabase
        .from('companies')
        .select()
        .eq('tenant_id', tenantId)
        .order('created_at', ascending: true)
        .limit(1)
        .maybeSingle();
    await _assertTenantLease(tenantId);

    return firstRow == null ? null : CompanyProfile.fromMap(firstRow);
  }

  /// Loads the persisted company or returns an unsaved, tenant-derived draft.
  ///
  /// This read path deliberately performs no insert and no public projection.
  /// Persistence only happens after the operator explicitly saves the form.
  Future<CompanyProfile> loadInitialCompanyProfile() async {
    final tenantId = await _requireTenantId();
    final existing = await _loadDefaultCompanyForTenant(tenantId);
    if (existing != null) return existing;

    final tenant = await _supabase
        .from('tenants')
        .select('shop_name, owner_email')
        .eq('id', tenantId)
        .maybeSingle();
    await _assertTenantLease(tenantId);

    return CompanyProfile.neutralDraft(
      tenantId: tenantId,
      shopName: tenant?['shop_name']?.toString() ?? '',
      ownerEmail: tenant?['owner_email']?.toString() ?? '',
    );
  }

  Future<CompanyProfile> saveCompany(
    CompanyProfile profile, {
    bool syncPublicData = true,
  }) async {
    final tenantId = _requireProfileTenantId(profile);
    await _assertTenantLease(tenantId);
    final payload = profile.toDatabaseMap(tenantId: tenantId);
    Map<String, dynamic>? savedRow;

    if ((profile.id ?? '').isNotEmpty) {
      savedRow = await _supabase
          .from('companies')
          .update(payload)
          .eq('id', profile.id!)
          .eq('tenant_id', tenantId)
          .select()
          .maybeSingle();
    } else {
      savedRow = await _supabase
          .from('companies')
          .insert({
            ...payload,
            'created_at': DateTime.now().toUtc().toIso8601String(),
          })
          .select()
          .maybeSingle();
    }
    await _assertTenantLease(tenantId);

    if (savedRow == null) {
      throw Exception('No se pudo guardar la empresa.');
    }

    final saved = CompanyProfile.fromMap(savedRow);
    if (saved.tenantId != tenantId) {
      throw StateError(
        'La empresa guardada no pertenece al tenant que inició la operación.',
      );
    }

    if (saved.isDefault && (saved.id ?? '').isNotEmpty) {
      await _assertTenantLease(tenantId);
      await _supabase
          .from('companies')
          .update({'is_default': false})
          .eq('tenant_id', tenantId)
          .neq('id', saved.id!);
      await _assertTenantLease(tenantId);
    }

    if (syncPublicData) {
      await syncPublicSettings(saved);
    }

    return saved;
  }

  Future<List<CompanyBankAccount>> loadBankAccounts(
    String companyId, {
    required String expectedTenantId,
  }) async {
    final tenantId = _normalizeExpectedTenantId(expectedTenantId);
    await _assertTenantLease(tenantId);

    final rows = await _supabase
        .from('company_bank_accounts')
        .select()
        .eq('tenant_id', tenantId)
        .eq('company_id', companyId)
        .order('is_default', ascending: false)
        .order('created_at', ascending: true);
    await _assertTenantLease(tenantId);

    return List<Map<String, dynamic>>.from(rows as List)
        .map(CompanyBankAccount.fromMap)
        .toList();
  }

  Future<List<CompanyBankAccount>> saveBankAccounts({
    required String companyId,
    required List<CompanyBankAccount> accounts,
    required String expectedTenantId,
  }) async {
    final tenantId = _normalizeExpectedTenantId(expectedTenantId);
    await _assertTenantLease(tenantId);
    for (final account in accounts) {
      final accountTenantId = account.tenantId?.trim() ?? '';
      if (accountTenantId.isNotEmpty && accountTenantId != tenantId) {
        throw StateError(
          'Una cuenta bancaria pertenece a otro tenant.',
        );
      }
      final accountCompanyId = account.companyId?.trim() ?? '';
      if (accountCompanyId.isNotEmpty && accountCompanyId != companyId) {
        throw StateError(
          'Una cuenta bancaria pertenece a otra empresa.',
        );
      }
    }
    final normalized = _normalizeDefaultBankAccount(accounts);

    final existingRows = await _supabase
        .from('company_bank_accounts')
        .select('id')
        .eq('tenant_id', tenantId)
        .eq('company_id', companyId);
    await _assertTenantLease(tenantId);

    final retainedIds = normalized
        .map((account) => account.id)
        .where((id) => id != null && id.isNotEmpty)
        .cast<String>()
        .toSet();

    for (final row in List<Map<String, dynamic>>.from(existingRows as List)) {
      final id = row['id']?.toString();
      if (id != null && id.isNotEmpty && !retainedIds.contains(id)) {
        await _assertTenantLease(tenantId);
        await _supabase
            .from('company_bank_accounts')
            .delete()
            .eq('tenant_id', tenantId)
            .eq('company_id', companyId)
            .eq('id', id);
        await _assertTenantLease(tenantId);
      }
    }

    final savedAccounts = <CompanyBankAccount>[];
    for (final account in normalized) {
      await _assertTenantLease(tenantId);
      final payload = account.toDatabaseMap(
        tenantId: tenantId,
        companyId: companyId,
      );

      final Map<String, dynamic>? savedRow;
      if ((account.id ?? '').isNotEmpty) {
        savedRow = await _supabase
            .from('company_bank_accounts')
            .update(payload)
            .eq('tenant_id', tenantId)
            .eq('company_id', companyId)
            .eq('id', account.id!)
            .select()
            .maybeSingle();
      } else {
        savedRow = await _supabase
            .from('company_bank_accounts')
            .insert({
              ...payload,
              'created_at': DateTime.now().toUtc().toIso8601String(),
            })
            .select()
            .maybeSingle();
      }
      await _assertTenantLease(tenantId);

      if (savedRow != null) {
        final savedAccount = CompanyBankAccount.fromMap(savedRow);
        if (savedAccount.tenantId != tenantId ||
            savedAccount.companyId != companyId) {
          throw StateError(
            'La cuenta guardada no pertenece a la operación activa.',
          );
        }
        savedAccounts.add(savedAccount);
      }
    }

    return savedAccounts;
  }

  Future<void> syncPublicSettings(
    CompanyProfile profile, {
    CompanyBankAccount? defaultBankAccount,
  }) async {
    final tenantId = _requireProfileTenantId(profile);
    await _assertTenantLease(tenantId);
    final bankTenantId = defaultBankAccount?.tenantId?.trim() ?? '';
    if (bankTenantId.isNotEmpty && bankTenantId != tenantId) {
      throw StateError(
        'La cuenta bancaria pública pertenece a otro tenant.',
      );
    }
    final values = _buildWebsiteSettings(
      profile,
      defaultBankAccount: defaultBankAccount,
    );
    if (values.isEmpty) return;

    final timestamp = DateTime.now().toUtc().toIso8601String();
    final rows = values.entries
        .map(
          (entry) => <String, dynamic>{
            'tenant_id': tenantId,
            'key': entry.key,
            'value': entry.value,
            'description': 'Sincronizado desde datos de empresa',
            'updated_at': timestamp,
          },
        )
        .toList(growable: false);

    // `website_settings_tenant_key_unique` owns (tenant_id, key), so this is
    // one PostgreSQL statement: the public projection cannot be left half old
    // and half new by a failure between individual keys.
    await _assertTenantLease(tenantId);
    await _supabase
        .from('website_settings')
        .upsert(rows, onConflict: 'tenant_id,key');
    await _assertTenantLease(tenantId);
  }

  Map<String, String> _buildWebsiteSettings(
    CompanyProfile profile, {
    CompanyBankAccount? defaultBankAccount,
  }) {
    final values = <String, String>{};

    void put(String key, String value) {
      // Empty values are intentional ownership too: clearing a company field
      // must clear its old public projection instead of resurrecting stale
      // identity/contact data.
      values[key] = value.trim();
    }

    put('site_title', profile.displayName);
    put('store_name', profile.displayName);
    put('business_name', profile.displayName);
    put('business_legal_name', profile.legalName);
    put('business_fantasy_name', profile.fantasyName);
    put('business_tax_id', profile.formattedTaxId);
    put('business_activity', profile.businessActivity);
    put('business_website_url', profile.websiteUrl);

    put('contact_email', profile.primaryEmail);
    put('seo_email', profile.primaryEmail);
    put('business_email', profile.email);
    put('billing_email', profile.billingEmail);

    put('contact_phone', profile.primaryPhone);
    put('seo_phone', profile.primaryPhone);
    put('business_phone', profile.phone);
    put('whatsapp_business_phone', profile.whatsappPhone);
    put('whatsapp_sim_phone', profile.whatsappPhone);
    put('whatsapp', profile.whatsappPhone);
    put('whatsapp_phone', profile.whatsappPhone);
    put('whatsapp_api_phone', profile.whatsappApiPhone);
    put('whatsapp_meta_api_phone', profile.whatsappApiPhone);
    put('messaging_whatsapp_phone', profile.whatsappApiPhone);
    put('support_phone', profile.supportPhone);

    if (defaultBankAccount != null) {
      put('payment_transfer_bank_name', defaultBankAccount.bankName);
      put('payment_transfer_account_type', defaultBankAccount.accountType);
      put(
        'payment_transfer_account_number',
        defaultBankAccount.accountNumber,
      );
      put('payment_transfer_account_holder', defaultBankAccount.holderName);
      put('payment_transfer_rut', defaultBankAccount.holderRut);
      put('payment_transfer_contact_email', defaultBankAccount.contactEmail);
      put('payment_transfer_instructions', defaultBankAccount.notes);
    }

    put('contact_address', profile.fullAddress);
    put('seo_address_street', profile.address);
    put('seo_address_city',
        profile.city.isNotEmpty ? profile.city : profile.comuna);
    put('seo_address_region', profile.region);
    put('seo_address_postal', profile.postalCode);
    put('seo_address_country', profile.country);

    return values;
  }

  List<CompanyBankAccount> _normalizeDefaultBankAccount(
    List<CompanyBankAccount> accounts,
  ) {
    if (accounts.isEmpty) return const [];

    final normalized = <CompanyBankAccount>[];
    var defaultWasAssigned = false;

    for (final account in accounts) {
      final shouldBeDefault = account.isDefault && !defaultWasAssigned;
      if (shouldBeDefault) defaultWasAssigned = true;
      normalized.add(account.copyWith(isDefault: shouldBeDefault));
    }

    if (!defaultWasAssigned) {
      normalized[0] = normalized[0].copyWith(isDefault: true);
    }

    return normalized;
  }

  Future<String> _requireTenantId() async {
    final tenantId = await _tenantService.getTenantId();
    if (tenantId == null || tenantId.isEmpty) {
      throw Exception('No hay tenant activo para guardar datos de empresa.');
    }
    return tenantId;
  }

  String _requireProfileTenantId(CompanyProfile profile) {
    return _normalizeExpectedTenantId(profile.tenantId);
  }

  String _normalizeExpectedTenantId(String? tenantId) {
    final normalized = tenantId?.trim() ?? '';
    if (normalized.isEmpty) {
      throw StateError(
        'La operación de empresa no tiene un tenant de origen.',
      );
    }
    return normalized;
  }

  Future<void> _assertTenantLease(String expectedTenantId) async {
    final activeTenantId = await _requireTenantId();
    if (activeTenantId != expectedTenantId) {
      throw StateError(
        'El tenant activo cambió durante la operación. '
        'No se guardaron pasos posteriores.',
      );
    }
  }
}
