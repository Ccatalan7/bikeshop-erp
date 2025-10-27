# 🏗️ Multi-Tenant SaaS Implementation Plan - Approach 3 (Hybrid)

**Project**: Vinabike ERP - Multi-Tenant Bike Shop Management Platform  
**Architecture**: Hybrid (Centralized ERP + Dynamic Public Storefronts)  
**Database**: Single Supabase PostgreSQL (multi-tenant with RLS)  
**Deployment**: Vercel (for wildcard subdomain support)  
**Timeline**: ~15-20 hours for MVP, 30-40 hours for full implementation  
**Status**: 🟡 In Planning Phase

---

## 📊 CURRENT STATE ASSESSMENT

### ✅ What's Already Built (80% Complete)

#### 1. **Multi-Tenant Database Schema** ✅ DONE
- **File**: `supabase/sql/core_schema.sql`
- **Status**: Fully implemented
- **Features**:
  - `tenants` table with `id`, `shop_name`, `subdomain`, `owner_email`, `logo_url`, etc.
  - ALL tables have `tenant_id uuid references tenants(id) on delete cascade not null`
  - RLS (Row Level Security) enabled on all tenant-scoped tables
  - `user_tenant_id()` helper function for RLS policies
  - Proper indexes on `tenant_id` columns
  - Unique constraints scoped per-tenant (e.g., `unique(tenant_id, sku)`)

**Evidence**:
```sql
-- Line 14-26 in core_schema.sql
create table if not exists tenants (
  id uuid primary key default gen_random_uuid(),
  shop_name text not null,
  subdomain text unique, -- For multi-domain support
  owner_email text,
  plan text default 'free' check (plan in ('free', 'pro', 'enterprise')),
  is_active boolean default true,
  logo_url text,
  currency text default 'CLP',
  timezone text default 'America/Santiago',
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);
```

#### 2. **Public Store UI Module** ✅ EXISTS (needs tenant detection)
- **Directory**: `lib/public_store/`
- **Status**: UI built, needs tenant context integration
- **Pages**:
  - ✅ `public_home_page.dart` - Homepage with hero banners
  - ✅ `product_catalog_page.dart` - Product listing with filters
  - ✅ `product_detail_page.dart` - Individual product pages
  - ✅ `cart_page.dart` - Shopping cart
  - ✅ `checkout_page.dart` - Checkout flow
  - ✅ `order_confirmation_page.dart` - Order success
  - ✅ `contact_page.dart` - Contact form
  - ✅ `customer_auth_page.dart` - Customer login/signup
  - ✅ `customer_account_page.dart` - Customer dashboard
  - ✅ `customer_orders_page.dart` - Order history
- **Widgets**:
  - ✅ `public_store_layout.dart` - Consistent layout wrapper
  - ✅ `floating_whatsapp_button.dart` - WhatsApp integration
  - ✅ `customer_account_menu.dart` - Customer navigation
- **Services**:
  - ✅ `customer_account_service.dart` - Customer auth management
  - ✅ `address_autocomplete_service.dart` - Address lookup
- **Providers**:
  - ✅ `cart_provider.dart` - Shopping cart state management

**Current Limitation**: Services use authenticated user's `tenant_id` instead of detecting from subdomain.

#### 3. **Domain Detection Logic** ✅ PARTIAL
- **File**: `lib/main.dart` (lines 258-268)
- **Status**: Detects public store domains, routes to `/tienda`
- **Current Implementation**:

```dart
bool _detectPublicStoreHost() {
  if (!kIsWeb) return false;
  final host = Uri.base.host.toLowerCase();
  return host == 'vinabike-store.web.app' ||
         host == 'vinabike-store.firebaseapp.com' ||
         host == 'vinabike.cl' ||
         host == 'www.vinabike.cl';
}
```

**Gap**: Hardcoded domains, doesn't extract subdomain dynamically.

#### 4. **Routing System** ✅ DONE
- **File**: `lib/shared/routes/app_router.dart`
- **Status**: Public store routes configured
- **Features**:
  - `/tienda/*` routes for public store
  - No authentication required for public routes
  - `PublicStoreWrapper` for consistent layout
  - Redirect logic for authenticated vs public access

**Evidence**:
```dart
// Line 107-117
final publicRoutes = [
  '/tienda',
  '/tienda/productos',
  '/tienda/producto',
  '/tienda/carrito',
  '/tienda/checkout',
  '/tienda/pedido',
  '/tienda/contacto',
  '/tienda/cuenta',
];
```

#### 5. **Business Logic Services** ✅ DONE (need public access mode)
- **Inventory Service**: `lib/shared/services/inventory_service.dart`
  - Products already filter by `tenant_id`
  - Uses RLS policies
  - **Gap**: Assumes authenticated user context
  
- **Category Service**: `lib/modules/inventory/services/category_service.dart`
  - Categories scoped to tenant
  - **Gap**: Needs public read access

- **Customer Service**: `lib/modules/crm/services/customer_service.dart`
  - Customer management per tenant
  - **Gap**: Public store needs guest checkout

#### 6. **Authentication System** ✅ DONE
- **File**: `lib/shared/services/auth_service.dart`
- **Status**: Supabase Auth fully integrated
- **Features**:
  - Email/password signup/login
  - OAuth2 support (Google, GitHub)
  - Token refresh
  - Role-based access control
  - **Gap**: No tenant assignment on signup

#### 7. **Website Builder Module** ⚠️ REMOVED IN CURRENT BRANCH
- **Status**: Existed in newer commits, not in commit 5714571
- **Note**: Was causing GrapeJS persistence issues, user reverted
- **Future**: Will need to rebuild for tenant customization

#### 8. **Firebase Hosting Configuration** ✅ DONE
- **File**: `firebase.json`
- **Status**: Dual hosting targets configured
- **Targets**:
  - `erp`: project-vinabike.web.app (admin interface)
  - `store`: vinabike-store.web.app (public store)
- **Limitation**: Firebase doesn't support wildcard subdomains on free tier

---

### ❌ What's Missing (20% to Build)

#### 1. **Tenant Detection from Subdomain** ❌
- Extract subdomain from URL
- Query `tenants` table by subdomain
- Handle custom domains (CNAME)
- Fallback for invalid subdomains

#### 2. **Public Store Tenant Context** ❌
- Provider to hold detected tenant
- Initialize on app start for public store
- Make available to all public store pages/services

#### 3. **Public RLS Policies** ❌
- Allow anonymous users to read products
- Allow anonymous users to read categories
- Allow anonymous users to read website settings
- Still filtered by tenant_id

#### 4. **Tenant Signup Flow** ❌
- Create tenant record on user signup
- Auto-generate unique subdomain
- Assign user to tenant as owner
- Initialize default settings

#### 5. **Public Store Service Refactor** ❌
- Services need "public mode" that uses detected tenant
- Services need "admin mode" that uses authenticated user's tenant
- Inventory service: load products for detected tenant
- Category service: load categories for detected tenant

#### 6. **Subdomain Validation** ❌
- Check subdomain availability during signup
- Prevent reserved words (admin, www, api, etc.)
- Character restrictions (alphanumeric, hyphens)

#### 7. **Deployment to Vercel** ❌
- Migrate from Firebase to Vercel for store
- Configure wildcard subdomain DNS
- Set up custom domain

---

## 🎯 IMPLEMENTATION PLAN

### **PHASE 1: Foundation & Tenant Detection** (4-6 hours)

#### **Task 1.1: Update Tenants Table** (30 min)
**File**: `supabase/sql/core_schema.sql`

**Changes**:
```sql
-- Add custom_domain field if not exists
alter table tenants add column if not exists custom_domain text;

-- Add index on custom_domain
create index if not exists idx_tenants_custom_domain on tenants(custom_domain);

-- Add constraint: subdomain is required and URL-safe
alter table tenants add constraint subdomain_format 
  check (subdomain ~ '^[a-z0-9][a-z0-9-]*[a-z0-9]$');

-- Reserved subdomains
create table if not exists reserved_subdomains (
  subdomain text primary key,
  reason text
);

insert into reserved_subdomains (subdomain, reason) values
  ('www', 'Reserved'),
  ('api', 'Reserved'),
  ('admin', 'Reserved'),
  ('app', 'Reserved'),
  ('mail', 'Reserved'),
  ('ftp', 'Reserved'),
  ('store', 'Reserved'),
  ('shop', 'Reserved')
on conflict do nothing;
```

**Deploy**:
```bash
psql -h xzdvtzdqjeyqxnkqprtf.supabase.co -U postgres -d postgres -f supabase/sql/core_schema.sql
```

---

#### **Task 1.2: Create Tenant Detection Service** (2 hours)
**New File**: `lib/shared/services/tenant_detection_service.dart`

```dart
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/tenant.dart';

class TenantDetectionService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Extract subdomain from current URL
  /// Examples:
  ///   vinabike.bikeshop-erp.app → "vinabike"
  ///   www.vinabike.cl → "vinabike" (via custom_domain lookup)
  ///   bikeshop-erp.app → null (main domain, no subdomain)
  String? extractSubdomain(String host) {
    if (!kIsWeb) return null;
    
    // Remove port if present
    final cleanHost = host.split(':').first.toLowerCase();
    
    // Main domain patterns (adjust based on your domain)
    const mainDomains = [
      'bikeshop-erp.app',
      'bikeshop-erp.vercel.app',
      'localhost',
    ];
    
    for (final mainDomain in mainDomains) {
      if (cleanHost == mainDomain) {
        return null; // No subdomain, main domain
      }
      
      if (cleanHost.endsWith('.$mainDomain')) {
        // Extract subdomain: vinabike.bikeshop-erp.app → vinabike
        final subdomain = cleanHost.substring(0, cleanHost.length - mainDomain.length - 1);
        return subdomain;
      }
    }
    
    // Not a subdomain pattern, might be custom domain
    return null;
  }

  /// Get tenant by subdomain
  Future<Tenant?> getTenantBySubdomain(String subdomain) async {
    try {
      final response = await _supabase
          .from('tenants')
          .select()
          .eq('subdomain', subdomain)
          .eq('is_active', true)
          .maybeSingle();

      if (response == null) return null;
      return Tenant.fromJson(response);
    } catch (e) {
      debugPrint('[TenantDetection] Error fetching tenant by subdomain: $e');
      return null;
    }
  }

  /// Get tenant by custom domain
  Future<Tenant?> getTenantByCustomDomain(String domain) async {
    try {
      final response = await _supabase
          .from('tenants')
          .select()
          .eq('custom_domain', domain)
          .eq('is_active', true)
          .maybeSingle();

      if (response == null) return null;
      return Tenant.fromJson(response);
    } catch (e) {
      debugPrint('[TenantDetection] Error fetching tenant by domain: $e');
      return null;
    }
  }

  /// Detect tenant from current URL
  Future<Tenant?> detectTenant() async {
    if (!kIsWeb) return null;

    final host = Uri.base.host;
    debugPrint('[TenantDetection] Detecting tenant for host: $host');

    // Try subdomain extraction
    final subdomain = extractSubdomain(host);
    if (subdomain != null) {
      debugPrint('[TenantDetection] Extracted subdomain: $subdomain');
      final tenant = await getTenantBySubdomain(subdomain);
      if (tenant != null) {
        debugPrint('[TenantDetection] Found tenant: ${tenant.shopName}');
        return tenant;
      }
    }

    // Try custom domain lookup
    final tenant = await getTenantByCustomDomain(host);
    if (tenant != null) {
      debugPrint('[TenantDetection] Found tenant by custom domain: ${tenant.shopName}');
      return tenant;
    }

    debugPrint('[TenantDetection] No tenant found for host: $host');
    return null;
  }

  /// Check if subdomain is available
  Future<bool> isSubdomainAvailable(String subdomain) async {
    try {
      // Check reserved subdomains
      final reserved = await _supabase
          .from('reserved_subdomains')
          .select()
          .eq('subdomain', subdomain)
          .maybeSingle();

      if (reserved != null) return false;

      // Check existing tenants
      final existing = await _supabase
          .from('tenants')
          .select('id')
          .eq('subdomain', subdomain)
          .maybeSingle();

      return existing == null;
    } catch (e) {
      debugPrint('[TenantDetection] Error checking subdomain availability: $e');
      return false;
    }
  }

  /// Generate subdomain from shop name
  String generateSubdomain(String shopName) {
    return shopName
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-') // Replace non-alphanumeric with dash
        .replaceAll(RegExp(r'^-+|-+$'), '')     // Remove leading/trailing dashes
        .replaceAll(RegExp(r'-+'), '-');        // Replace multiple dashes with single
  }
}
```

---

#### **Task 1.3: Create Tenant Model** (30 min)
**New File**: `lib/shared/models/tenant.dart`

```dart
class Tenant {
  final String id;
  final String shopName;
  final String? subdomain;
  final String? ownerEmail;
  final String plan; // 'free', 'pro', 'enterprise'
  final bool isActive;
  final String? logoUrl;
  final String? customDomain;
  final String currency;
  final String timezone;
  final DateTime createdAt;
  final DateTime updatedAt;

  Tenant({
    required this.id,
    required this.shopName,
    this.subdomain,
    this.ownerEmail,
    this.plan = 'free',
    this.isActive = true,
    this.logoUrl,
    this.customDomain,
    this.currency = 'CLP',
    this.timezone = 'America/Santiago',
    required this.createdAt,
    required this.updatedAt,
  });

  factory Tenant.fromJson(Map<String, dynamic> json) {
    return Tenant(
      id: json['id'],
      shopName: json['shop_name'],
      subdomain: json['subdomain'],
      ownerEmail: json['owner_email'],
      plan: json['plan'] ?? 'free',
      isActive: json['is_active'] ?? true,
      logoUrl: json['logo_url'],
      customDomain: json['custom_domain'],
      currency: json['currency'] ?? 'CLP',
      timezone: json['timezone'] ?? 'America/Santiago',
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'shop_name': shopName,
      'subdomain': subdomain,
      'owner_email': ownerEmail,
      'plan': plan,
      'is_active': isActive,
      'logo_url': logoUrl,
      'custom_domain': customDomain,
      'currency': currency,
      'timezone': timezone,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  Tenant copyWith({
    String? id,
    String? shopName,
    String? subdomain,
    String? ownerEmail,
    String? plan,
    bool? isActive,
    String? logoUrl,
    String? customDomain,
    String? currency,
    String? timezone,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Tenant(
      id: id ?? this.id,
      shopName: shopName ?? this.shopName,
      subdomain: subdomain ?? this.subdomain,
      ownerEmail: ownerEmail ?? this.ownerEmail,
      plan: plan ?? this.plan,
      isActive: isActive ?? this.isActive,
      logoUrl: logoUrl ?? this.logoUrl,
      customDomain: customDomain ?? this.customDomain,
      currency: currency ?? this.currency,
      timezone: timezone ?? this.timezone,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
```

---

#### **Task 1.4: Create Public Store Tenant Provider** (1 hour)
**New File**: `lib/public_store/providers/public_store_tenant_provider.dart`

```dart
import 'package:flutter/foundation.dart';
import '../../shared/models/tenant.dart';
import '../../shared/services/tenant_detection_service.dart';

/// Manages the detected tenant for the public store
/// This is separate from the authenticated user's tenant (for admin/ERP)
class PublicStoreTenantProvider extends ChangeNotifier {
  final TenantDetectionService _detectionService;

  Tenant? _currentTenant;
  bool _isLoading = false;
  String? _error;

  PublicStoreTenantProvider(this._detectionService);

  Tenant? get currentTenant => _currentTenant;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get hasTenant => _currentTenant != null;

  /// Detect tenant from current URL
  Future<void> detectTenant() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _currentTenant = await _detectionService.detectTenant();
      
      if (_currentTenant == null) {
        _error = 'No se encontró la tienda. Verifica la URL.';
      }
    } catch (e) {
      _error = 'Error cargando la tienda: $e';
      debugPrint('[PublicStoreTenantProvider] Error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Set tenant manually (for testing)
  void setTenant(Tenant tenant) {
    _currentTenant = tenant;
    _error = null;
    notifyListeners();
  }

  /// Clear tenant
  void clearTenant() {
    _currentTenant = null;
    _error = null;
    notifyListeners();
  }

  /// Get tenant ID (convenience method)
  String? get tenantId => _currentTenant?.id;
}
```

---

#### **Task 1.5: Integrate Provider into App** (1 hour)
**File**: `lib/main.dart`

**Changes**:
```dart
// Add imports
import 'shared/services/tenant_detection_service.dart';
import 'shared/models/tenant.dart';
import 'public_store/providers/public_store_tenant_provider.dart';

// Inside VinabikeApp widget build method
@override
Widget build(BuildContext context) {
  return MultiProvider(
    providers: [
      // ... existing providers ...
      
      // Add tenant detection
      Provider(create: (_) => TenantDetectionService()),
      ChangeNotifierProvider(
        create: (context) => PublicStoreTenantProvider(
          context.read<TenantDetectionService>(),
        ),
      ),
    ],
    child: Builder(
      builder: (context) {
        // Detect tenant on app start if on public store domain
        final isPublicStoreHost = _detectPublicStoreHost();
        if (isPublicStoreHost) {
          // Trigger tenant detection
          WidgetsBinding.instance.addPostFrameCallback((_) {
            context.read<PublicStoreTenantProvider>().detectTenant();
          });
        }

        // ... rest of app ...
      },
    ),
  );
}
```

---

### **PHASE 2: Public RLS Policies** (2-3 hours)

#### **Task 2.1: Create Public Read Policies** (2 hours)
**File**: `supabase/sql/core_schema.sql`

**Add at end of RLS policies section**:

```sql
-- ========================================
-- PUBLIC STORE RLS POLICIES
-- Allow anonymous users to read tenant-scoped data
-- ========================================

-- Products: Public read access
create policy "Public can view active products"
  on products for select
  to anon
  using (
    is_active = true 
    and inventory_qty > 0  -- Only show in-stock products
  );

-- Categories: Public read access
create policy "Public can view categories"
  on categories for select
  to anon
  using (true);  -- All categories visible

-- Website banners: Public read access
create policy "Public can view active banners"
  on website_banners for select
  to anon
  using (is_active = true);

-- Website content: Public read access
create policy "Public can view published content"
  on website_content for select
  to anon
  using (status = 'published');

-- Website settings: Public read access
create policy "Public can view website settings"
  on website_settings for select
  to anon
  using (true);

-- Orders: Anonymous users can create orders (guest checkout)
create policy "Anonymous users can create orders"
  on orders for insert
  to anon
  with check (true);

-- Order items: Anonymous users can create order items
create policy "Anonymous users can create order items"
  on order_items for insert
  to anon
  with check (true);

-- Note: RLS still enforces tenant_id filtering through the application
-- The app must explicitly set tenant_id when querying as anon user
```

**Deploy**:
```bash
psql -h xzdvtzdqjeyqxnkqprtf.supabase.co -U postgres -d postgres -f supabase/sql/core_schema.sql
```

---

#### **Task 2.2: Test RLS Policies** (1 hour)

**Create test script**: `test_public_rls.sql`

```sql
-- Switch to anonymous role
set role anon;

-- Test 1: Can read products? (should work)
select id, name, price from products limit 5;

-- Test 2: Can read categories? (should work)
select id, name from categories limit 5;

-- Test 3: Can insert products? (should FAIL)
insert into products (name, sku, price) values ('Test', 'TEST', 100);

-- Test 4: Can update products? (should FAIL)
update products set price = 999 where id = 'some-id';

-- Test 5: Can delete products? (should FAIL)
delete from products where id = 'some-id';

-- Reset role
reset role;
```

---

### **PHASE 3: Refactor Services for Public Access** (4-6 hours)

#### **Task 3.1: Create Public Inventory Service** (2 hours)
**New File**: `lib/public_store/services/public_inventory_service.dart`

```dart
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../shared/models/product.dart';
import '../../shared/models/category.dart';

/// Public-facing inventory service
/// Does NOT require authentication
/// Filters by provided tenant_id instead of authenticated user's tenant
class PublicInventoryService extends ChangeNotifier {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Get products for specific tenant (public access)
  Future<List<Product>> getProductsForTenant({
    required String tenantId,
    String? categoryId,
    String? searchQuery,
    bool onlyInStock = true,
  }) async {
    try {
      var query = _supabase
          .from('products')
          .select()
          .eq('tenant_id', tenantId)
          .eq('is_active', true);

      if (onlyInStock) {
        query = query.gt('inventory_qty', 0);
      }

      if (categoryId != null) {
        query = query.eq('category_id', categoryId);
      }

      if (searchQuery != null && searchQuery.isNotEmpty) {
        query = query.or('name.ilike.%$searchQuery%,sku.ilike.%$searchQuery%');
      }

      final response = await query.order('name');
      return (response as List).map((json) => Product.fromJson(json)).toList();
    } catch (e) {
      debugPrint('[PublicInventoryService] Error fetching products: $e');
      rethrow;
    }
  }

  /// Get single product by ID (public access)
  Future<Product?> getProductForTenant({
    required String tenantId,
    required String productId,
  }) async {
    try {
      final response = await _supabase
          .from('products')
          .select()
          .eq('tenant_id', tenantId)
          .eq('id', productId)
          .eq('is_active', true)
          .maybeSingle();

      if (response == null) return null;
      return Product.fromJson(response);
    } catch (e) {
      debugPrint('[PublicInventoryService] Error fetching product: $e');
      return null;
    }
  }

  /// Get categories for specific tenant (public access)
  Future<List<Category>> getCategoriesForTenant(String tenantId) async {
    try {
      final response = await _supabase
          .from('categories')
          .select()
          .eq('tenant_id', tenantId)
          .order('name');

      return (response as List).map((json) => Category.fromJson(json)).toList();
    } catch (e) {
      debugPrint('[PublicInventoryService] Error fetching categories: $e');
      rethrow;
    }
  }

  /// Search products (public access)
  Future<List<Product>> searchProductsForTenant({
    required String tenantId,
    required String query,
  }) async {
    try {
      final response = await _supabase
          .from('products')
          .select()
          .eq('tenant_id', tenantId)
          .eq('is_active', true)
          .gt('inventory_qty', 0)
          .or('name.ilike.%$query%,sku.ilike.%$query%,description.ilike.%$query%')
          .order('name')
          .limit(20);

      return (response as List).map((json) => Product.fromJson(json)).toList();
    } catch (e) {
      debugPrint('[PublicInventoryService] Error searching products: $e');
      rethrow;
    }
  }
}
```

---

#### **Task 3.2: Update Product Catalog Page** (1 hour)
**File**: `lib/public_store/pages/product_catalog_page.dart`

**Replace inventory service usage**:

```dart
import 'package:provider/provider.dart';
import '../services/public_inventory_service.dart';
import '../providers/public_store_tenant_provider.dart';

// Inside _loadProducts method
Future<void> _loadProducts() async {
  setState(() => _isLoading = true);

  try {
    final tenantProvider = context.read<PublicStoreTenantProvider>();
    final publicInventoryService = context.read<PublicInventoryService>();
    
    // Check if tenant is detected
    if (!tenantProvider.hasTenant) {
      debugPrint('[ProductCatalog] No tenant detected');
      setState(() {
        _allProducts = [];
        _isLoading = false;
      });
      return;
    }

    // Load products for detected tenant
    _allProducts = await publicInventoryService.getProductsForTenant(
      tenantId: tenantProvider.tenantId!,
      categoryId: _selectedCategoryId,
      searchQuery: _searchQuery,
      onlyInStock: true,
    );

    _applyFilters();
  } catch (e) {
    debugPrint('[ProductCatalog] Error loading products: $e');
  } finally {
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }
}
```

---

#### **Task 3.3: Add Public Service to Providers** (30 min)
**File**: `lib/main.dart`

```dart
// Add to MultiProvider
ChangeNotifierProvider(create: (_) => PublicInventoryService()),
```

---

### **PHASE 4: Tenant Signup Flow** (4-5 hours)

#### **Task 4.1: Update Signup to Create Tenant** (3 hours)
**File**: `lib/shared/screens/login_screen.dart`

**Add to _handleSignup method**:

```dart
Future<void> _handleSignup() async {
  if (!_formKey.currentState!.validate()) return;

  setState(() => _isLoading = true);

  try {
    final authService = context.read<AuthService>();
    final tenantService = TenantDetectionService();

    // Step 1: Create auth user
    await authService.signUp(
      email: _emailController.text.trim(),
      password: _passwordController.text,
    );

    // Step 2: Generate subdomain from email
    final emailPrefix = _emailController.text.split('@').first;
    String subdomain = tenantService.generateSubdomain(emailPrefix);

    // Step 3: Ensure subdomain is unique
    bool isAvailable = await tenantService.isSubdomainAvailable(subdomain);
    int attempt = 1;
    while (!isAvailable && attempt < 10) {
      subdomain = '${tenantService.generateSubdomain(emailPrefix)}-$attempt';
      isAvailable = await tenantService.isSubdomainAvailable(subdomain);
      attempt++;
    }

    if (!isAvailable) {
      throw Exception('No se pudo generar un subdominio único');
    }

    // Step 4: Create tenant record
    final user = authService.currentUser;
    if (user == null) throw Exception('No se pudo obtener usuario autenticado');

    final response = await Supabase.instance.client
        .from('tenants')
        .insert({
          'shop_name': emailPrefix, // Can be updated later in settings
          'subdomain': subdomain,
          'owner_email': _emailController.text.trim(),
          'plan': 'free',
          'is_active': true,
        })
        .select()
        .single();

    final tenantId = response['id'];

    // Step 5: Link user to tenant
    await Supabase.instance.client
        .from('user_profiles')
        .insert({
          'user_id': user.id,
          'tenant_id': tenantId,
          'role': 'admin', // First user is admin
          'permissions': {
            'all': true, // Full permissions for owner
          },
        });

    // Step 6: Initialize default data (optional)
    await _initializeDefaultTenantData(tenantId);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Cuenta creada! Tu tienda: $subdomain.bikeshop-erp.app'),
          duration: const Duration(seconds: 5),
        ),
      );
      context.go('/dashboard');
    }
  } on AuthException catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_getAuthErrorMessage(e))),
      );
    }
  } catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  } finally {
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }
}

/// Initialize default data for new tenant
Future<void> _initializeDefaultTenantData(String tenantId) async {
  try {
    // Create default payment methods
    await Supabase.instance.client.from('payment_methods').insert([
      {'tenant_id': tenantId, 'name': 'Efectivo', 'is_active': true},
      {'tenant_id': tenantId, 'name': 'Transferencia', 'is_active': true},
      {'tenant_id': tenantId, 'name': 'Tarjeta de Crédito', 'is_active': true},
    ]);

    // Create default categories
    await Supabase.instance.client.from('categories').insert([
      {'tenant_id': tenantId, 'name': 'Bicicletas'},
      {'tenant_id': tenantId, 'name': 'Repuestos'},
      {'tenant_id': tenantId, 'name': 'Accesorios'},
    ]);

    // Create default accounts (simplified chart of accounts)
    await Supabase.instance.client.from('accounts').insert([
      {'tenant_id': tenantId, 'code': '1100', 'name': 'Caja', 'type': 'asset'},
      {'tenant_id': tenantId, 'code': '1200', 'name': 'Banco', 'type': 'asset'},
      {'tenant_id': tenantId, 'code': '4100', 'name': 'Ventas', 'type': 'income'},
      {'tenant_id': tenantId, 'code': '5100', 'name': 'Costo de Ventas', 'type': 'expense'},
    ]);
  } catch (e) {
    debugPrint('[Signup] Error initializing default data: $e');
    // Don't throw - let signup succeed even if defaults fail
  }
}
```

---

#### **Task 4.2: Add user_profiles Table** (1 hour)
**File**: `supabase/sql/core_schema.sql`

**Add after tenants table**:

```sql
-- User profiles: Link auth.users to tenants with roles
create table if not exists user_profiles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete cascade not null,
  tenant_id uuid references tenants(id) on delete cascade not null,
  role text not null check (role in ('admin', 'manager', 'cashier', 'mechanic', 'accountant')),
  permissions jsonb not null default '{}'::jsonb,
  is_active boolean default true,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  unique(user_id, tenant_id)
);

create index idx_user_profiles_user on user_profiles(user_id);
create index idx_user_profiles_tenant on user_profiles(tenant_id);

-- RLS for user_profiles
alter table user_profiles enable row level security;

create policy "Users can view their own profiles"
  on user_profiles for select
  using (auth.uid() = user_id);

create policy "Admins can manage profiles in their tenant"
  on user_profiles for all
  using (
    tenant_id = (
      select tenant_id from user_profiles 
      where user_id = auth.uid() and role = 'admin'
    )
  );

-- Helper function: Get user's tenant ID
create or replace function public.user_tenant_id()
returns uuid
language sql
security definer
stable
as $$
  select tenant_id from user_profiles where user_id = auth.uid() limit 1;
$$;
```

---

### **PHASE 5: Vercel Deployment** (2-3 hours)

#### **Task 5.1: Create Vercel Configuration** (1 hour)
**New File**: `vercel.json`

```json
{
  "buildCommand": "flutter build web --release",
  "outputDirectory": "build/web",
  "framework": null,
  "routes": [
    {
      "src": "/assets/(.*)",
      "dest": "/assets/$1"
    },
    {
      "src": "/(.*\\.(js|css|png|jpg|jpeg|gif|svg|ico|json|woff|woff2|ttf|eot))",
      "dest": "/$1"
    },
    {
      "src": "/(.*)",
      "dest": "/index.html"
    }
  ],
  "headers": [
    {
      "source": "/assets/(.*)",
      "headers": [
        {
          "key": "Cache-Control",
          "value": "public, max-age=31536000, immutable"
        }
      ]
    }
  ]
}
```

---

#### **Task 5.2: Deploy to Vercel** (1 hour)

**Steps**:

1. **Install Vercel CLI**:
```bash
npm install -g vercel
```

2. **Login to Vercel**:
```bash
vercel login
```

3. **Deploy**:
```bash
vercel --prod
```

4. **Add Custom Domain** (in Vercel dashboard):
   - Go to Project Settings → Domains
   - Add: `bikeshop-erp.app` (buy from Namecheap/GoDaddy ~$12/year)
   - Vercel provides DNS instructions
   - Configure DNS A records to point to Vercel

5. **Enable Wildcard Subdomain**:
   - Add domain: `*.bikeshop-erp.app`
   - Vercel automatically provisions SSL for all subdomains

---

#### **Task 5.3: Test Multi-Tenant Routing** (1 hour)

**Test scenarios**:

1. **Main domain** (`bikeshop-erp.app`):
   - Should show: Landing page or redirect to login
   - Tenant detected: None

2. **Vinabike subdomain** (`vinabike.bikeshop-erp.app`):
   - Should show: Vinabike's public store
   - Tenant detected: Vinabike (tenant_id: abc123)
   - Products shown: Vinabike's products only

3. **Second tenant** (`joesikes.bikeshop-erp.app`):
   - Should show: Joe's Bikes public store
   - Tenant detected: Joe's Bikes (tenant_id: xyz789)
   - Products shown: Joe's products only

4. **Invalid subdomain** (`nonexistent.bikeshop-erp.app`):
   - Should show: "Store not found" page
   - Tenant detected: None

---

### **PHASE 6: Website Customization** (8-10 hours - Future)

This phase is for allowing tenants to customize their storefront appearance.

#### **Task 6.1: Website Settings Table**
Already exists in `core_schema.sql` (line ~8559):
```sql
create table website_settings (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  -- colors, fonts, layouts, etc.
);
```

#### **Task 6.2: Simple Theme Editor**
- Color picker (primary, secondary, accent)
- Logo upload
- Banner images
- Footer text

#### **Task 6.3: Advanced Builder** (GrapeJS or similar)
- Drag-and-drop page builder
- Save layouts to database
- Render from JSON

**Note**: User previously had GrapeJS issues, so keep this simple initially.

---

### **PHASE 7: Custom Domains** (6-8 hours - Optional)

#### **Task 7.1: Domain Verification**
- Tenant enters custom domain
- System provides DNS verification TXT record
- Check DNS propagation
- Mark domain as verified

#### **Task 7.2: SSL Provisioning**
- Use Let's Encrypt via Vercel API
- Auto-renew certificates

#### **Task 7.3: Domain Mapping**
- CNAME: `www.vinabike.cl` → `vinabike.bikeshop-erp.app`
- Update tenant record with custom_domain
- Handle both www and non-www

---

## 📋 TESTING CHECKLIST

### **Multi-Tenant Isolation**
- [ ] Tenant A cannot see Tenant B's products
- [ ] Tenant A cannot modify Tenant B's data
- [ ] RLS policies enforce tenant_id filtering
- [ ] Anonymous users can read but not write
- [ ] Subdomain detection works correctly

### **Signup Flow**
- [ ] New user signup creates tenant record
- [ ] Subdomain is auto-generated and unique
- [ ] User is linked to tenant as admin
- [ ] Default data is initialized
- [ ] User can access their ERP dashboard

### **Public Store**
- [ ] Subdomain routes to correct tenant's store
- [ ] Products display correctly
- [ ] Cart works without authentication
- [ ] Guest checkout creates order
- [ ] Invalid subdomain shows error page

### **Performance**
- [ ] Page load time < 3 seconds
- [ ] Product queries optimized (indexed)
- [ ] Image loading lazy/cached
- [ ] No N+1 query problems

### **Security**
- [ ] SQL injection protected (parameterized queries)
- [ ] XSS protected (sanitized inputs)
- [ ] RLS policies prevent data leaks
- [ ] Authentication works correctly
- [ ] Password requirements enforced

---

## 🚀 DEPLOYMENT SEQUENCE

### **Development**
1. Work on `ecommerce-module2.0` branch
2. Test locally with `flutter run -d chrome --web-hostname localhost --web-port 8080`
3. Test subdomain simulation: `vinabike.localhost:8080`

### **Staging**
1. Deploy to Vercel preview: `vercel`
2. Test with staging subdomain: `vinabike.staging.bikeshop-erp.app`
3. Verify all features work

### **Production**
1. Deploy to Vercel production: `vercel --prod`
2. Configure DNS for `bikeshop-erp.app`
3. Enable wildcard SSL
4. Monitor for errors
5. Announce to users

---

## 📊 SUCCESS METRICS

### **Technical**
- ✅ 100% tenant data isolation (0 cross-tenant queries)
- ✅ < 500ms average API response time
- ✅ 99.9% uptime (Vercel SLA)
- ✅ Zero SQL injection vulnerabilities
- ✅ Zero XSS vulnerabilities

### **Business**
- ✅ Tenant signup takes < 2 minutes
- ✅ Storefront creation is instant (no manual setup)
- ✅ Subdomain works immediately after signup
- ✅ Custom domain setup takes < 5 minutes (optional)

### **User Experience**
- ✅ Public store loads in < 3 seconds
- ✅ Product search works accurately
- ✅ Cart persists across sessions
- ✅ Checkout process is smooth (< 5 clicks)

---

## 🔧 TOOLS & RESOURCES

### **Development**
- Flutter SDK 3.35.6+
- Dart 3.0+
- VS Code with Flutter extension
- Chrome DevTools

### **Database**
- Supabase PostgreSQL
- pgAdmin (for schema management)
- SQL client (for RLS testing)

### **Deployment**
- Vercel CLI
- Git (version control)
- GitHub Actions (optional CI/CD)

### **Monitoring**
- Vercel Analytics
- Supabase Dashboard
- Sentry (error tracking, optional)

### **Testing**
- Flutter test framework
- Supabase RLS testing
- Manual QA checklist

---

## 📞 SUPPORT & DOCUMENTATION

### **For Development**
- Supabase docs: https://supabase.com/docs
- Flutter web docs: https://docs.flutter.dev/platform-integration/web
- Vercel docs: https://vercel.com/docs

### **For Tenant Onboarding**
- Create user guide: "How to set up your bike shop online"
- Video tutorial: Signup → Add products → Customize store
- FAQ: Common questions about subdomains, custom domains

---

## 🎯 IMMEDIATE NEXT STEPS

1. **Update `core_schema.sql`** with reserved_subdomains and user_profiles tables
2. **Create** `TenantDetectionService` class
3. **Create** `PublicStoreTenantProvider` class
4. **Update** signup flow to create tenant
5. **Test** locally with mock subdomains
6. **Deploy** to Vercel with wildcard DNS

---

## ⚠️ KNOWN LIMITATIONS

### **Current Branch (ecommerce-module2.0)**
- ❌ No website builder (was removed due to GrapeJS issues)
- ❌ No theme customization UI
- ❌ No custom domain support yet
- ❌ No tenant dashboard for managing subdomain

### **Vercel Free Tier**
- ✅ Unlimited subdomains
- ✅ Free SSL
- ⚠️ 100GB bandwidth/month (usually enough)
- ⚠️ 6000 build minutes/month

### **Supabase Free Tier**
- ✅ 500MB database
- ✅ 1GB file storage
- ⚠️ 50,000 monthly active users
- ⚠️ 2GB bandwidth

---

## 💰 COST ESTIMATE

### **MVP (Free Tier)**
- Vercel: $0/month
- Supabase: $0/month
- Domain (bikeshop-erp.app): $12/year
- **Total**: $12/year ($1/month)

### **Production (100 tenants)**
- Vercel Pro: $20/month
- Supabase Pro: $25/month
- Domain: $12/year
- **Total**: $45/month + $12/year = ~$46/month

### **Scale (1000 tenants)**
- Vercel Enterprise: $300/month (custom pricing)
- Supabase Team: $599/month
- Multiple domains: ~$100/year
- **Total**: ~$900/month

---

## 🎉 CONCLUSION

This implementation plan provides a **complete, production-ready architecture** for a multi-tenant SaaS bike shop platform. The approach balances:

- ✅ **Simplicity**: Single database, shared infrastructure
- ✅ **Scalability**: Can support thousands of tenants
- ✅ **Cost-effectiveness**: Free tier for MVP, affordable at scale
- ✅ **Security**: RLS policies, tenant isolation
- ✅ **User experience**: Instant subdomain setup, optional custom domains
- ✅ **Maintainability**: One codebase, one deployment

**Ready to start building Phase 1?** 🚀
