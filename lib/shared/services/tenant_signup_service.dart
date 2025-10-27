import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/tenant.dart';
import './tenant_detection_service.dart';

/// Service to handle tenant creation during signup
/// 
/// When a new user signs up, this service:
/// 1. Creates a tenant record with auto-generated subdomain
/// 2. Links the user to the tenant as admin (in user_profiles table)
/// 3. Initializes default data (payment methods, categories, accounts)
class TenantSignupService {
  final SupabaseClient _supabase = Supabase.instance.client;
  final TenantDetectionService _tenantDetectionService = TenantDetectionService();

  /// Create tenant for newly signed up user
  /// 
  /// Parameters:
  /// - [userId]: The authenticated user's ID
  /// - [email]: User's email address
  /// - [shopName]: Name of the bike shop (e.g., "Vinabike")
  /// - [phoneNumber]: Optional shop phone number
  /// 
  /// Returns: Tenant object or null on error
  Future<Tenant?> createTenantForUser({
    required String userId,
    required String email,
    required String shopName,
    String? phoneNumber,
  }) async {
    try {
      debugPrint('🏗️ TenantSignupService: Creating tenant for user $userId');

      // Step 1: Generate unique subdomain
      final subdomain = await _tenantDetectionService.generateUniqueSubdomain(shopName);
      if (subdomain == null) {
        debugPrint('❌ TenantSignupService: Failed to generate unique subdomain');
        throw Exception('No se pudo generar un subdominio único. Por favor intente con otro nombre.');
      }

      debugPrint('✅ TenantSignupService: Generated subdomain: $subdomain');

      // Step 2: Create tenant record
      final tenantData = {
        'shop_name': shopName,
        'subdomain': subdomain,
        'owner_email': email,
        'plan': 'free', // Start with free plan
        'is_active': true,
        'phone_number': phoneNumber,
        'currency': 'CLP', // Default to Chilean Peso
        'timezone': 'America/Santiago', // Default to Chile timezone
      };

      final tenantResponse = await _supabase
          .from('tenants')
          .insert(tenantData)
          .select()
          .single();

      final tenant = Tenant.fromJson(tenantResponse);
      debugPrint('✅ TenantSignupService: Created tenant: ${tenant.id}');

      // Step 3: Create user_profiles entry (link user to tenant as admin)
      final profileData = {
        'user_id': userId,
        'tenant_id': tenant.id,
        'role': 'admin', // Owner has admin role
        'is_active': true,
        'permissions': ['all'], // Admin has all permissions
      };

      await _supabase
          .from('user_profiles')
          .insert(profileData);

      debugPrint('✅ TenantSignupService: Created user_profile for admin');

      // Step 4: Initialize default data
      await _initializeDefaultData(tenant.id);

      debugPrint('🎉 TenantSignupService: Tenant setup complete!');
      debugPrint('   Shop Name: ${tenant.shopName}');
      debugPrint('   Subdomain: ${tenant.subdomain}');
      debugPrint('   Store URL: https://${tenant.subdomain}.bikeshop-erp.app');

      return tenant;
    } catch (e) {
      debugPrint('❌ TenantSignupService: Error creating tenant: $e');
      
      // Try to clean up if tenant was created but later steps failed
      // This is best-effort cleanup
      try {
        await _supabase
            .from('user_profiles')
            .delete()
            .eq('user_id', userId);
      } catch (_) {
        // Ignore cleanup errors
      }
      
      return null;
    }
  }

  /// Initialize default data for new tenant
  /// 
  /// Creates:
  /// - Default payment methods (Efectivo, Transferencia, Mercado Pago)
  /// - Default product categories (Bicicletas, Repuestos, Accesorios)
  /// - Default chart of accounts (basic accounting structure)
  Future<void> _initializeDefaultData(String tenantId) async {
    try {
      debugPrint('📦 TenantSignupService: Initializing default data for tenant $tenantId');

      // 1. Create default payment methods
      await _createDefaultPaymentMethods(tenantId);

      // 2. Create default categories
      await _createDefaultCategories(tenantId);

      // 3. Create default chart of accounts
      await _createDefaultAccounts(tenantId);

      debugPrint('✅ TenantSignupService: Default data initialized');
    } catch (e) {
      debugPrint('⚠️ TenantSignupService: Error initializing default data: $e');
      // Don't throw - tenant was created successfully, just log the error
    }
  }

  /// Create default payment methods
  Future<void> _createDefaultPaymentMethods(String tenantId) async {
    final paymentMethods = [
      {
        'tenant_id': tenantId,
        'name': 'Efectivo',
        'type': 'cash',
        'is_active': true,
        'description': 'Pago en efectivo',
      },
      {
        'tenant_id': tenantId,
        'name': 'Transferencia Bancaria',
        'type': 'bank_transfer',
        'is_active': true,
        'description': 'Transferencia electrónica',
      },
      {
        'tenant_id': tenantId,
        'name': 'Mercado Pago',
        'type': 'mercadopago',
        'is_active': false, // Disabled by default (requires configuration)
        'description': 'Pagos online con Mercado Pago',
      },
      {
        'tenant_id': tenantId,
        'name': 'Tarjeta de Débito',
        'type': 'debit_card',
        'is_active': true,
        'description': 'Tarjeta de débito',
      },
      {
        'tenant_id': tenantId,
        'name': 'Tarjeta de Crédito',
        'type': 'credit_card',
        'is_active': true,
        'description': 'Tarjeta de crédito',
      },
    ];

    await _supabase.from('payment_methods').insert(paymentMethods);
    debugPrint('✅ Created ${paymentMethods.length} default payment methods');
  }

  /// Create default product categories
  Future<void> _createDefaultCategories(String tenantId) async {
    final categories = [
      {
        'tenant_id': tenantId,
        'name': 'Bicicletas',
        'full_path': 'Bicicletas',
        'level': 0,
        'is_active': true,
        'sort_order': 1,
      },
      {
        'tenant_id': tenantId,
        'name': 'Repuestos',
        'full_path': 'Repuestos',
        'level': 0,
        'is_active': true,
        'sort_order': 2,
      },
      {
        'tenant_id': tenantId,
        'name': 'Accesorios',
        'full_path': 'Accesorios',
        'level': 0,
        'is_active': true,
        'sort_order': 3,
      },
      {
        'tenant_id': tenantId,
        'name': 'Indumentaria',
        'full_path': 'Indumentaria',
        'level': 0,
        'is_active': true,
        'sort_order': 4,
      },
      {
        'tenant_id': tenantId,
        'name': 'Servicios',
        'full_path': 'Servicios',
        'level': 0,
        'is_active': true,
        'sort_order': 5,
      },
    ];

    await _supabase.from('categories').insert(categories);
    debugPrint('✅ Created ${categories.length} default categories');
  }

  /// Create default chart of accounts
  Future<void> _createDefaultAccounts(String tenantId) async {
    final accounts = [
      // Assets (1.xxx)
      {
        'tenant_id': tenantId,
        'code': '1.1.001',
        'name': 'Caja',
        'type': 'asset',
        'is_active': true,
      },
      {
        'tenant_id': tenantId,
        'code': '1.1.002',
        'name': 'Banco',
        'type': 'asset',
        'is_active': true,
      },
      {
        'tenant_id': tenantId,
        'code': '1.2.001',
        'name': 'Cuentas por Cobrar',
        'type': 'asset',
        'is_active': true,
      },
      {
        'tenant_id': tenantId,
        'code': '1.3.001',
        'name': 'Inventario',
        'type': 'asset',
        'is_active': true,
      },

      // Liabilities (2.xxx)
      {
        'tenant_id': tenantId,
        'code': '2.1.001',
        'name': 'Cuentas por Pagar',
        'type': 'liability',
        'is_active': true,
      },
      {
        'tenant_id': tenantId,
        'code': '2.2.001',
        'name': 'IVA por Pagar',
        'type': 'liability',
        'is_active': true,
      },

      // Equity (3.xxx)
      {
        'tenant_id': tenantId,
        'code': '3.1.001',
        'name': 'Capital',
        'type': 'equity',
        'is_active': true,
      },
      {
        'tenant_id': tenantId,
        'code': '3.2.001',
        'name': 'Utilidades Retenidas',
        'type': 'equity',
        'is_active': true,
      },

      // Revenue (4.xxx)
      {
        'tenant_id': tenantId,
        'code': '4.1.001',
        'name': 'Ventas',
        'type': 'revenue',
        'is_active': true,
      },
      {
        'tenant_id': tenantId,
        'code': '4.1.002',
        'name': 'Servicios',
        'type': 'revenue',
        'is_active': true,
      },

      // Expenses (5.xxx)
      {
        'tenant_id': tenantId,
        'code': '5.1.001',
        'name': 'Costo de Ventas',
        'type': 'expense',
        'is_active': true,
      },
      {
        'tenant_id': tenantId,
        'code': '5.2.001',
        'name': 'Sueldos y Salarios',
        'type': 'expense',
        'is_active': true,
      },
      {
        'tenant_id': tenantId,
        'code': '5.2.002',
        'name': 'Arriendo',
        'type': 'expense',
        'is_active': true,
      },
      {
        'tenant_id': tenantId,
        'code': '5.2.003',
        'name': 'Servicios Básicos',
        'type': 'expense',
        'is_active': true,
      },
      {
        'tenant_id': tenantId,
        'code': '5.3.001',
        'name': 'Gastos Generales',
        'type': 'expense',
        'is_active': true,
      },
    ];

    await _supabase.from('accounts').insert(accounts);
    debugPrint('✅ Created ${accounts.length} default accounts');
  }

  /// Check if user already has a tenant
  Future<Tenant?> getUserTenant(String userId) async {
    try {
      final profileResponse = await _supabase
          .from('user_profiles')
          .select('tenant_id, tenants(*)')
          .eq('user_id', userId)
          .maybeSingle();

      if (profileResponse == null) {
        return null;
      }

      final tenantData = profileResponse['tenants'];
      if (tenantData == null) {
        return null;
      }

      return Tenant.fromJson(tenantData);
    } catch (e) {
      debugPrint('❌ TenantSignupService: Error getting user tenant: $e');
      return null;
    }
  }
}
