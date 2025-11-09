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
  /// - Default chart of accounts (MUST be created first - required by payment methods)
  /// - Default payment methods (linked to accounting accounts)
  /// - Default product categories (Bicicletas, Repuestos, Accesorios)
  Future<void> _initializeDefaultData(String tenantId) async {
    try {
      debugPrint('📦 TenantSignupService: Initializing default data for tenant $tenantId');

      // 1. Create default chart of accounts FIRST (required by payment methods)
      await _createDefaultAccounts(tenantId);

      // 2. Create default payment methods (requires account_id from accounts)
      await _createDefaultPaymentMethods(tenantId);

      // 3. Create default categories
      await _createDefaultCategories(tenantId);

      debugPrint('✅ TenantSignupService: Default data initialized');
    } catch (e) {
      debugPrint('⚠️ TenantSignupService: Error initializing default data: $e');
      // Don't throw - tenant was created successfully, just log the error
    }
  }

  /// Create default payment methods
  /// CRITICAL: Accounts must be created first, as payment methods reference account_id
  Future<void> _createDefaultPaymentMethods(String tenantId) async {
    // Fetch the cash and bank accounts created in _createDefaultAccounts
    final cashAccount = await _supabase
        .from('accounts')
        .select('id')
        .eq('tenant_id', tenantId)
        .eq('code', '1101') // Caja General
        .maybeSingle();

    final bankAccount = await _supabase
        .from('accounts')
        .select('id')
        .eq('tenant_id', tenantId)
        .eq('code', '1110') // Bancos - Cuenta Corriente
        .maybeSingle();

    if (cashAccount == null || bankAccount == null) {
      throw Exception('❌ Cash or Bank account not found. Accounts must be created before payment methods.');
    }

    final cashAccountId = cashAccount['id'] as String;
    final bankAccountId = bankAccount['id'] as String;

    final paymentMethods = [
      {
        'tenant_id': tenantId,
        'code': 'cash',
        'name': 'Efectivo',
        'account_id': cashAccountId,
        'requires_reference': false,
        'icon': 'payments',
        'sort_order': 1,
        'is_active': true,
      },
      {
        'tenant_id': tenantId,
        'code': 'bank_transfer',
        'name': 'Transferencia Bancaria',
        'account_id': bankAccountId,
        'requires_reference': true,
        'icon': 'account_balance',
        'sort_order': 2,
        'is_active': true,
      },
      {
        'tenant_id': tenantId,
        'code': 'debit_card',
        'name': 'Tarjeta de Débito',
        'account_id': bankAccountId,
        'requires_reference': false,
        'icon': 'credit_card',
        'sort_order': 3,
        'is_active': true,
      },
      {
        'tenant_id': tenantId,
        'code': 'credit_card',
        'name': 'Tarjeta de Crédito',
        'account_id': bankAccountId,
        'requires_reference': false,
        'icon': 'credit_card',
        'sort_order': 4,
        'is_active': true,
      },
      {
        'tenant_id': tenantId,
        'code': 'mercadopago',
        'name': 'Mercado Pago',
        'account_id': bankAccountId,
        'requires_reference': true,
        'icon': 'payment',
        'sort_order': 5,
        'is_active': false, // Disabled by default (requires configuration)
      },
    ];

    await _supabase.from('payment_methods').insert(paymentMethods);
    debugPrint('✅ Created ${paymentMethods.length} default payment methods');
    debugPrint('   💰 Linked to accounting accounts (Cash: $cashAccountId, Bank: $bankAccountId)');
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
  /// CRITICAL: Account codes must match those used in database functions (ensure_account calls)
  /// This chart follows Chilean accounting standards and integrates with all ERP modules
  Future<void> _createDefaultAccounts(String tenantId) async {
    final accounts = [
      // ============================================================================
      // ASSETS (1xxx) - Activos
      // ============================================================================
      
      // Current Assets - Activos Corrientes
      {
        'tenant_id': tenantId,
        'code': '1101',
        'name': 'Caja General',
        'type': 'asset',
        'category': 'currentAsset',
        'description': 'Efectivo disponible en caja y fondos inmediatos',
        'is_active': true,
      },
      {
        'tenant_id': tenantId,
        'code': '1110',
        'name': 'Bancos - Cuenta Corriente',
        'type': 'asset',
        'category': 'currentAsset',
        'description': 'Saldos disponibles en cuentas corrientes bancarias',
        'is_active': true,
      },
      {
        'tenant_id': tenantId,
        'code': '1130',
        'name': 'Cuentas por Cobrar Comerciales',
        'type': 'asset',
        'category': 'currentAsset',
        'description': 'Saldos pendientes de cobro a clientes por ventas a crédito',
        'is_active': true,
      },
      {
        'tenant_id': tenantId,
        'code': '1105',
        'name': 'Inventarios',
        'type': 'asset',
        'category': 'currentAsset',
        'description': 'Valor del inventario de productos y repuestos',
        'is_active': true,
      },
      {
        'tenant_id': tenantId,
        'code': '1190',
        'name': 'Otros Activos Corrientes',
        'type': 'asset',
        'category': 'currentAsset',
        'description': 'Activos circulantes no clasificados en otra cuenta específica',
        'is_active': true,
      },

      // ============================================================================
      // LIABILITIES (2xxx) - Pasivos
      // ============================================================================
      
      // Current Liabilities - Pasivos Corrientes
      {
        'tenant_id': tenantId,
        'code': '2101',
        'name': 'Cuentas por Pagar Proveedores',
        'type': 'liability',
        'category': 'currentLiability',
        'description': 'Obligaciones con proveedores',
        'is_active': true,
      },
      {
        'tenant_id': tenantId,
        'code': '2150',
        'name': 'IVA Débito Fiscal',
        'type': 'liability',
        'category': 'currentLiability',
        'description': 'IVA generado en ventas',
        'is_active': true,
      },
      {
        'tenant_id': tenantId,
        'code': '210200',
        'name': 'IVA por Pagar',
        'type': 'liability',
        'category': 'currentLiability',
        'description': 'IVA a pagar al SII',
        'is_active': true,
      },

      // ============================================================================
      // EQUITY (3xxx) - Patrimonio
      // ============================================================================
      {
        'tenant_id': tenantId,
        'code': '3101',
        'name': 'Capital',
        'type': 'equity',
        'category': 'capital',
        'description': 'Capital aportado por los socios',
        'is_active': true,
      },
      {
        'tenant_id': tenantId,
        'code': '3201',
        'name': 'Utilidades Retenidas',
        'type': 'equity',
        'category': 'retainedEarnings',
        'description': 'Utilidades acumuladas de ejercicios anteriores',
        'is_active': true,
      },

      // ============================================================================
      // REVENUE (4xxx) - Ingresos
      // ============================================================================
      {
        'tenant_id': tenantId,
        'code': '4100',
        'name': 'Ingresos Operacionales',
        'type': 'income',
        'category': 'operatingIncome',
        'description': 'Ingresos operacionales por ventas y servicios',
        'is_active': true,
      },

      // ============================================================================
      // EXPENSES (5xxx) - Gastos
      // ============================================================================
      
      // Cost of Goods Sold
      {
        'tenant_id': tenantId,
        'code': '5100',
        'name': 'Costo de Ventas',
        'type': 'expense',
        'category': 'costOfGoodsSold',
        'description': 'Costo de ventas de productos y servicios',
        'is_active': true,
      },

      // Operating Expenses - Gastos Operacionales
      {
        'tenant_id': tenantId,
        'code': '610100',
        'name': 'Sueldos y Salarios',
        'type': 'expense',
        'category': 'operatingExpense',
        'description': 'Remuneraciones del personal y pagos de nómina',
        'is_active': true,
      },
      {
        'tenant_id': tenantId,
        'code': '610200',
        'name': 'Cotizaciones Previsionales y Salud',
        'type': 'expense',
        'category': 'operatingExpense',
        'description': 'Aportes previsionales, salud y seguros obligatorios del personal',
        'is_active': true,
      },
      {
        'tenant_id': tenantId,
        'code': '610300',
        'name': 'Honorarios Profesionales',
        'type': 'expense',
        'category': 'operatingExpense',
        'description': 'Servicios profesionales externos y consultorías',
        'is_active': true,
      },
      {
        'tenant_id': tenantId,
        'code': '620100',
        'name': 'Arriendo de Locales',
        'type': 'expense',
        'category': 'operatingExpense',
        'description': 'Pagos de arriendo de oficinas, locales y bodegas',
        'is_active': true,
      },
      {
        'tenant_id': tenantId,
        'code': '620200',
        'name': 'Servicios Básicos',
        'type': 'expense',
        'category': 'operatingExpense',
        'description': 'Consumo de electricidad, agua, gas y otros servicios básicos',
        'is_active': true,
      },
      {
        'tenant_id': tenantId,
        'code': '620300',
        'name': 'Telefonía e Internet',
        'type': 'expense',
        'category': 'operatingExpense',
        'description': 'Planes de telefonía fija, móvil y servicios de internet',
        'is_active': true,
      },
      {
        'tenant_id': tenantId,
        'code': '620400',
        'name': 'Mantención y Reparaciones',
        'type': 'expense',
        'category': 'operatingExpense',
        'description': 'Gastos de mantenimiento preventivo y correctivo de infraestructura y equipos',
        'is_active': true,
      },
      {
        'tenant_id': tenantId,
        'code': '620500',
        'name': 'Suministros de Oficina',
        'type': 'expense',
        'category': 'operatingExpense',
        'description': 'Materiales de oficina, papelería e insumos administrativos',
        'is_active': true,
      },
      {
        'tenant_id': tenantId,
        'code': '630100',
        'name': 'Marketing y Publicidad',
        'type': 'expense',
        'category': 'operatingExpense',
        'description': 'Campañas de marketing, publicidad y promoción de la marca',
        'is_active': true,
      },
      {
        'tenant_id': tenantId,
        'code': '630200',
        'name': 'Comisiones y Servicios de Venta',
        'type': 'expense',
        'category': 'operatingExpense',
        'description': 'Comisiones pagadas a vendedores y servicios relacionados con ventas',
        'is_active': true,
      },
      {
        'tenant_id': tenantId,
        'code': '640100',
        'name': 'Gastos de Viaje y Viáticos',
        'type': 'expense',
        'category': 'operatingExpense',
        'description': 'Traslados, alojamiento y viáticos del personal',
        'is_active': true,
      },
      {
        'tenant_id': tenantId,
        'code': '640200',
        'name': 'Capacitación y Desarrollo',
        'type': 'expense',
        'category': 'operatingExpense',
        'description': 'Programas de formación, cursos y certificaciones del personal',
        'is_active': true,
      },
      {
        'tenant_id': tenantId,
        'code': '650100',
        'name': 'Seguros Generales',
        'type': 'expense',
        'category': 'operatingExpense',
        'description': 'Primas de seguros patrimoniales, de responsabilidad y otros',
        'is_active': true,
      },
      {
        'tenant_id': tenantId,
        'code': '650200',
        'name': 'Impuestos y Contribuciones Municipales',
        'type': 'expense',
        'category': 'taxExpense',
        'description': 'Patentes, contribuciones y otros impuestos municipales',
        'is_active': true,
      },
      {
        'tenant_id': tenantId,
        'code': '660100',
        'name': 'Intereses y Gastos Financieros',
        'type': 'expense',
        'category': 'financialExpense',
        'description': 'Intereses de créditos, comisiones bancarias y costos financieros',
        'is_active': true,
      },
      {
        'tenant_id': tenantId,
        'code': '670100',
        'name': 'Depreciación y Amortización',
        'type': 'expense',
        'category': 'operatingExpense',
        'description': 'Gastos por depreciación de activos fijos y amortización de intangibles',
        'is_active': true,
      },
      {
        'tenant_id': tenantId,
        'code': '680100',
        'name': 'Gastos Varios',
        'type': 'expense',
        'category': 'operatingExpense',
        'description': 'Gastos generales menores no clasificados en otras cuentas específicas',
        'is_active': true,
      },
    ];

    await _supabase.from('accounts').insert(accounts);
    debugPrint('✅ Created ${accounts.length} default accounts');
    debugPrint('   📊 Chart of accounts aligned with database functions');
    debugPrint('   ✅ All ensure_account() codes present');
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
