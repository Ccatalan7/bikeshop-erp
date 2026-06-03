import 'package:flutter/foundation.dart';
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

    final defaultRow = await _supabase
        .from('companies')
        .select()
        .eq('tenant_id', tenantId)
        .eq('is_default', true)
        .order('updated_at', ascending: false)
        .limit(1)
        .maybeSingle();

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

    return firstRow == null ? null : CompanyProfile.fromMap(firstRow);
  }

  Future<CompanyProfile> getOrCreateDefaultCompany() async {
    final existing = await loadDefaultCompany();
    if (existing != null) return existing;

    final tenantId = await _requireTenantId();
    final tenant = await _supabase
        .from('tenants')
        .select('shop_name, owner_email')
        .eq('id', tenantId)
        .maybeSingle();

    final fallbackEmail =
        (tenant?['owner_email'] as String?)?.trim().isNotEmpty == true
            ? (tenant!['owner_email'] as String).trim()
            : 'vinabikechile@gmail.com';

    final fallback = CompanyProfile.vinabikeDefault(
      tenantId: tenantId,
      email: fallbackEmail,
    ).copyWith(
      name: (tenant?['shop_name'] as String?)?.trim().isNotEmpty == true
          ? (tenant!['shop_name'] as String).trim()
          : 'Viñabike',
    );

    return saveCompany(fallback, syncPublicData: true);
  }

  Future<CompanyProfile> saveCompany(
    CompanyProfile profile, {
    bool syncPublicData = true,
  }) async {
    final tenantId = await _requireTenantId();
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

    if (savedRow == null) {
      throw Exception('No se pudo guardar la empresa.');
    }

    final saved = CompanyProfile.fromMap(savedRow);

    if (saved.isDefault && (saved.id ?? '').isNotEmpty) {
      await _supabase
          .from('companies')
          .update({'is_default': false})
          .eq('tenant_id', tenantId)
          .neq('id', saved.id!);
    }

    if (syncPublicData) {
      await syncPublicSettings(saved);
    }

    return saved;
  }

  Future<List<CompanyBankAccount>> loadBankAccounts(String companyId) async {
    final tenantId = await _requireTenantId();

    final rows = await _supabase
        .from('company_bank_accounts')
        .select()
        .eq('tenant_id', tenantId)
        .eq('company_id', companyId)
        .order('is_default', ascending: false)
        .order('created_at', ascending: true);

    return List<Map<String, dynamic>>.from(rows as List)
        .map(CompanyBankAccount.fromMap)
        .toList();
  }

  Future<List<CompanyBankAccount>> saveBankAccounts({
    required String companyId,
    required List<CompanyBankAccount> accounts,
  }) async {
    final tenantId = await _requireTenantId();
    final normalized = _normalizeDefaultBankAccount(accounts);

    final existingRows = await _supabase
        .from('company_bank_accounts')
        .select('id')
        .eq('tenant_id', tenantId)
        .eq('company_id', companyId);

    final retainedIds = normalized
        .map((account) => account.id)
        .where((id) => id != null && id.isNotEmpty)
        .cast<String>()
        .toSet();

    for (final row in List<Map<String, dynamic>>.from(existingRows as List)) {
      final id = row['id']?.toString();
      if (id != null && id.isNotEmpty && !retainedIds.contains(id)) {
        await _supabase
            .from('company_bank_accounts')
            .delete()
            .eq('tenant_id', tenantId)
            .eq('company_id', companyId)
            .eq('id', id);
      }
    }

    final savedAccounts = <CompanyBankAccount>[];
    for (final account in normalized) {
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

      if (savedRow != null) {
        savedAccounts.add(CompanyBankAccount.fromMap(savedRow));
      }
    }

    return savedAccounts;
  }

  Future<void> syncPublicSettings(
    CompanyProfile profile, {
    CompanyBankAccount? defaultBankAccount,
  }) async {
    final tenantId = await _requireTenantId();
    final values = _buildWebsiteSettings(
      profile,
      defaultBankAccount: defaultBankAccount,
    );
    if (values.isEmpty) return;

    final timestamp = DateTime.now().toUtc().toIso8601String();

    for (final entry in values.entries) {
      final updateResult = await _supabase
          .from('website_settings')
          .update({
            'value': entry.value,
            'updated_at': timestamp,
          })
          .eq('tenant_id', tenantId)
          .eq('key', entry.key)
          .select();

      if (updateResult.isEmpty) {
        try {
          await _supabase.from('website_settings').insert({
            'tenant_id': tenantId,
            'key': entry.key,
            'value': entry.value,
            'description': 'Sincronizado desde datos de empresa',
            'updated_at': timestamp,
          });
        } catch (error) {
          if (kDebugMode) {
            debugPrint('Error syncing website setting ${entry.key}: $error');
          }
          rethrow;
        }
      }
    }
  }

  Map<String, String> _buildWebsiteSettings(
    CompanyProfile profile, {
    CompanyBankAccount? defaultBankAccount,
  }) {
    final values = <String, String>{};

    void put(String key, String value) {
      final trimmed = value.trim();
      if (trimmed.isNotEmpty) values[key] = trimmed;
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
}
