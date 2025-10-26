# 🌐 MULTI-TENANT WEBSITE SETUP GUIDE

## 🎯 Overview

This guide explains how to enable **each tenant** to have their own e-commerce website with a unique Firebase subdomain (e.g., `tenant1.web.app`, `tenant2.web.app`).

---

## 🏗️ Architecture Options

### **Option 1: Single Firebase Project, Multiple Sites (RECOMMENDED)**
**How it works:**
- One Firebase project hosts multiple websites
- Each tenant gets a unique subdomain: `bikeshop1.web.app`, `bikeshop2.web.app`
- All sites share same codebase but show different data (filtered by `tenant_id`)
- **Cost:** FREE (Firebase Hosting allows 36 sites per project)

### **Option 2: Separate Firebase Projects Per Tenant**
**How it works:**
- Each tenant creates their own Firebase project
- Each tenant deploys independently
- **Cost:** FREE per tenant (each gets their own free tier)
- **Complexity:** High (requires tenant to manage Firebase)

### **Option 3: Custom Domains on Single Site**
**How it works:**
- Single Firebase site (e.g., `vinabike.web.app`)
- Route tenants by subdomain: `tenant1.vinabike.cl`, `tenant2.vinabike.cl`
- Detect tenant from hostname
- **Cost:** ~$12/year for domain + DNS setup
- **Complexity:** Medium

---

## 🚀 RECOMMENDED SOLUTION: Option 1 - Multiple Firebase Hosting Sites

### Benefits:
- ✅ **FREE** (no cost per tenant)
- ✅ **Easy to manage** (one Firebase project for all tenants)
- ✅ **Automated** (tenants just click "Create Website" in ERP)
- ✅ **Scalable** (up to 36 tenants per Firebase project)
- ✅ **No custom domain required** (each tenant gets `tenantname.web.app`)

---

## 📋 Implementation Plan

### **Step 1: Update Database Schema**

Add website configuration to `company_settings` table:

```sql
-- Add to core_schema.sql
alter table company_settings add column if not exists website_enabled boolean default false;
alter table company_settings add column if not exists website_subdomain text unique;
alter table company_settings add column if not exists website_url text;
alter table company_settings add column if not exists firebase_site_name text;
alter table company_settings add column if not exists website_deployed_at timestamptz;
alter table company_settings add column if not exists website_status text default 'not_configured'; -- not_configured, pending, deployed, error

comment on column company_settings.website_enabled is 'Whether tenant has activated their public website';
comment on column company_settings.website_subdomain is 'Unique subdomain for tenant website (e.g., bikeshop1)';
comment on column company_settings.website_url is 'Full URL of deployed website';
comment on column company_settings.firebase_site_name is 'Firebase Hosting site name';
comment on column company_settings.website_deployed_at is 'When website was last deployed';
comment on column company_settings.website_status is 'Current deployment status';
```

### **Step 2: Create Website Setup Service**

Create `lib/modules/website/services/website_setup_service.dart`:

```dart
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class WebsiteSetupService extends ChangeNotifier {
  final SupabaseClient _supabase = Supabase.instance.client;

  bool _isLoading = false;
  String? _error;
  WebsiteConfig? _config;

  bool get isLoading => _isLoading;
  String? get error => _error;
  WebsiteConfig? get config => _config;

  /// Check if current tenant has website configured
  Future<void> loadWebsiteConfig() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _supabase
          .from('company_settings')
          .select()
          .single();

      _config = WebsiteConfig.fromJson(response);
    } catch (e) {
      _error = 'Error loading website config: $e';
      debugPrint(_error);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Request website creation (saves to database, admin deploys later)
  Future<bool> requestWebsiteCreation({
    required String shopName,
    String? preferredSubdomain,
  }) async {
    try {
      // Generate subdomain from shop name if not provided
      final subdomain = preferredSubdomain ?? 
          _generateSubdomain(shopName);

      // Check if subdomain is available
      final existing = await _supabase
          .from('company_settings')
          .select('website_subdomain')
          .eq('website_subdomain', subdomain)
          .maybeSingle();

      if (existing != null) {
        _error = 'Subdomain "$subdomain" is already taken';
        notifyListeners();
        return false;
      }

      // Update company settings
      await _supabase.from('company_settings').update({
        'website_enabled': true,
        'website_subdomain': subdomain,
        'website_status': 'pending',
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('tenant_id', _getCurrentTenantId());

      await loadWebsiteConfig();
      return true;
    } catch (e) {
      _error = 'Error requesting website: $e';
      debugPrint(_error);
      notifyListeners();
      return false;
    }
  }

  /// Generate URL-friendly subdomain from shop name
  String _generateSubdomain(String shopName) {
    return shopName
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
  }

  String _getCurrentTenantId() {
    final user = _supabase.auth.currentUser;
    return user?.userMetadata?['tenant_id'] ?? '';
  }
}

class WebsiteConfig {
  final bool enabled;
  final String? subdomain;
  final String? url;
  final String? firebaseSiteName;
  final DateTime? deployedAt;
  final String status; // not_configured, pending, deployed, error

  WebsiteConfig({
    required this.enabled,
    this.subdomain,
    this.url,
    this.firebaseSiteName,
    this.deployedAt,
    required this.status,
  });

  factory WebsiteConfig.fromJson(Map<String, dynamic> json) {
    return WebsiteConfig(
      enabled: json['website_enabled'] ?? false,
      subdomain: json['website_subdomain'],
      url: json['website_url'],
      firebaseSiteName: json['firebase_site_name'],
      deployedAt: json['website_deployed_at'] != null
          ? DateTime.parse(json['website_deployed_at'])
          : null,
      status: json['website_status'] ?? 'not_configured',
    );
  }

  bool get isConfigured => enabled && subdomain != null;
  bool get isPending => status == 'pending';
  bool get isDeployed => status == 'deployed';
  bool get hasError => status == 'error';
}
```

### **Step 3: Create Website Setup UI**

Create `lib/modules/website/pages/website_setup_page.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/website_setup_service.dart';

class WebsiteSetupPage extends StatefulWidget {
  const WebsiteSetupPage({Key? key}) : super(key: key);

  @override
  State<WebsiteSetupPage> createState() => _WebsiteSetupPageState();
}

class _WebsiteSetupPageState extends State<WebsiteSetupPage> {
  final _formKey = GlobalKey<FormState>();
  final _shopNameController = TextEditingController();
  final _subdomainController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<WebsiteSetupService>().loadWebsiteConfig();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Configurar Website'),
      ),
      body: Consumer<WebsiteSetupService>(
        builder: (context, service, child) {
          if (service.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          final config = service.config;

          // Website already configured
          if (config != null && config.isConfigured) {
            return _buildConfiguredView(config);
          }

          // Setup wizard
          return _buildSetupWizard(service);
        },
      ),
    );
  }

  Widget _buildConfiguredView(WebsiteConfig config) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '✅ Tu Website Está Configurado',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 24),
          _buildInfoCard(
            icon: Icons.language,
            title: 'Subdomain',
            value: config.subdomain ?? 'N/A',
          ),
          const SizedBox(height: 16),
          _buildInfoCard(
            icon: Icons.link,
            title: 'URL',
            value: config.url ?? 'Pendiente de despliegue',
            isLink: config.url != null,
          ),
          const SizedBox(height: 16),
          _buildInfoCard(
            icon: Icons.cloud_done,
            title: 'Estado',
            value: _getStatusLabel(config.status),
            statusColor: _getStatusColor(config.status),
          ),
          if (config.deployedAt != null) ...[
            const SizedBox(height: 16),
            _buildInfoCard(
              icon: Icons.schedule,
              title: 'Último Despliegue',
              value: _formatDate(config.deployedAt!),
            ),
          ],
          const SizedBox(height: 32),
          if (config.isPending)
            const Card(
              color: Colors.orange,
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.info, color: Colors.white),
                    SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        'Tu solicitud está pendiente. Un administrador desplegará tu website pronto.',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (config.isDeployed && config.url != null)
            ElevatedButton.icon(
              onPressed: () {
                // Open website in browser
                // You can use url_launcher package
              },
              icon: const Icon(Icons.open_in_new),
              label: const Text('Abrir Mi Website'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSetupWizard(WebsiteSetupService service) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '🌐 Crea Tu Website',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Obtén tu propia tienda online con un dominio gratuito de Firebase',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey[600],
                  ),
            ),
            const SizedBox(height: 32),
            TextFormField(
              controller: _shopNameController,
              decoration: const InputDecoration(
                labelText: 'Nombre de tu Tienda',
                hintText: 'Ej: Bike Shop Santiago',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Ingresa el nombre de tu tienda';
                }
                return null;
              },
              onChanged: (value) {
                // Auto-generate subdomain
                final subdomain = service._generateSubdomain(value);
                _subdomainController.text = subdomain;
              },
            ),
            const SizedBox(height: 24),
            TextFormField(
              controller: _subdomainController,
              decoration: InputDecoration(
                labelText: 'Subdomain (URL)',
                hintText: 'bikeshop-santiago',
                border: const OutlineInputBorder(),
                suffixText: '.web.app',
                helperText: 'Este será tu URL público',
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Ingresa un subdomain';
                }
                if (!RegExp(r'^[a-z0-9-]+$').hasMatch(value)) {
                  return 'Solo letras minúsculas, números y guiones';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue[200]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.info, color: Colors.blue[700]),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      'Tu website será: ${_subdomainController.text}.web.app',
                      style: TextStyle(
                        color: Colors.blue[900],
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: service.isLoading
                  ? null
                  : () async {
                      if (_formKey.currentState!.validate()) {
                        final success = await service.requestWebsiteCreation(
                          shopName: _shopNameController.text,
                          preferredSubdomain: _subdomainController.text,
                        );

                        if (success && mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('✅ Solicitud enviada exitosamente'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        } else if (service.error != null && mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(service.error!),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    },
              icon: const Icon(Icons.rocket_launch),
              label: const Text('Crear Mi Website'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 56),
              ),
            ),
            const SizedBox(height: 32),
            const Divider(),
            const SizedBox(height: 16),
            Text(
              '¿Qué incluye?',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            _buildFeatureItem('Tienda online completa'),
            _buildFeatureItem('Dominio gratuito (.web.app)'),
            _buildFeatureItem('SSL/HTTPS incluido'),
            _buildFeatureItem('Sincronización automática con inventario'),
            _buildFeatureItem('Panel de administración'),
            _buildFeatureItem('Carrito de compras'),
            _buildFeatureItem('Procesamiento de pagos'),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String title,
    required String value,
    bool isLink = false,
    Color? statusColor,
  }) {
    return Card(
      child: ListTile(
        leading: Icon(icon, color: statusColor),
        title: Text(title),
        subtitle: Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: statusColor ?? Colors.black87,
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: Colors.green, size: 20),
          const SizedBox(width: 12),
          Text(text),
        ],
      ),
    );
  }

  String _getStatusLabel(String status) {
    switch (status) {
      case 'pending':
        return '⏳ Pendiente de Despliegue';
      case 'deployed':
        return '✅ Desplegado';
      case 'error':
        return '❌ Error';
      default:
        return 'No Configurado';
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'pending':
        return Colors.orange;
      case 'deployed':
        return Colors.green;
      case 'error':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute}';
  }
}
```

### **Step 4: Admin Deployment Script**

Create a Node.js script to auto-deploy tenant websites:

`scripts/deploy_tenant_website.js`:

```javascript
// Deploy a tenant's website to Firebase Hosting
// Usage: node scripts/deploy_tenant_website.js <tenant_id>

const { execSync } = require('child_process');
const { createClient } = require('@supabase/supabase-js');

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SERVICE_KEY = process.env.SUPABASE_SERVICE_KEY;
const FIREBASE_PROJECT = 'project-vinabike';

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);

async function deployTenantWebsite(tenantId) {
  try {
    console.log(`🚀 Deploying website for tenant: ${tenantId}`);

    // 1. Get tenant config from database
    const { data: config, error } = await supabase
      .from('company_settings')
      .select('website_subdomain, shop_name')
      .eq('tenant_id', tenantId)
      .single();

    if (error || !config) {
      throw new Error(`Tenant not found: ${tenantId}`);
    }

    const siteName = config.website_subdomain;

    if (!siteName) {
      throw new Error('No subdomain configured for this tenant');
    }

    console.log(`📝 Site name: ${siteName}`);

    // 2. Create Firebase Hosting site (if doesn't exist)
    console.log('🔧 Creating Firebase Hosting site...');
    try {
      execSync(
        `firebase hosting:sites:create ${siteName} --project ${FIREBASE_PROJECT}`,
        { stdio: 'inherit' }
      );
    } catch (e) {
      console.log('⚠️  Site may already exist, continuing...');
    }

    // 3. Add site to .firebaserc targets
    console.log('📦 Configuring deployment target...');
    execSync(
      `firebase target:apply hosting ${siteName} ${siteName} --project ${FIREBASE_PROJECT}`,
      { stdio: 'inherit' }
    );

    // 4. Build Flutter web app (same build for all tenants - tenant_id filters data)
    console.log('🔨 Building Flutter web app...');
    execSync('flutter build web --release', { stdio: 'inherit' });

    // 5. Deploy to Firebase Hosting
    console.log('🚀 Deploying to Firebase Hosting...');
    execSync(
      `firebase deploy --only hosting:${siteName} --project ${FIREBASE_PROJECT}`,
      { stdio: 'inherit' }
    );

    // 6. Update database with deployment info
    const url = `https://${siteName}.web.app`;
    console.log('💾 Updating database...');
    await supabase
      .from('company_settings')
      .update({
        website_url: url,
        firebase_site_name: siteName,
        website_deployed_at: new Date().toISOString(),
        website_status: 'deployed',
      })
      .eq('tenant_id', tenantId);

    console.log(`✅ Success! Website deployed at: ${url}`);
  } catch (error) {
    console.error('❌ Deployment failed:', error.message);

    // Update database with error status
    await supabase
      .from('company_settings')
      .update({
        website_status: 'error',
      })
      .eq('tenant_id', tenantId);

    process.exit(1);
  }
}

// Get tenant ID from command line
const tenantId = process.argv[2];

if (!tenantId) {
  console.error('Usage: node deploy_tenant_website.js <tenant_id>');
  process.exit(1);
}

deployTenantWebsite(tenantId);
```

### **Step 5: Auto-Detect Tenant from URL**

Update `lib/main.dart` to detect tenant from Firebase subdomain:

```dart
// In main.dart, before runApp()

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'YOUR_SUPABASE_URL',
    anonKey: 'YOUR_ANON_KEY',
  );

  // Detect tenant from URL (for multi-tenant websites)
  String? detectedTenantSubdomain;
  if (kIsWeb) {
    final hostname = Uri.base.host;
    // Extract subdomain from Firebase URL (e.g., bikeshop1.web.app)
    if (hostname.endsWith('.web.app')) {
      detectedTenantSubdomain = hostname.split('.').first;
    }
  }

  runApp(MyApp(tenantSubdomain: detectedTenantSubdomain));
}
```

Then in your services, filter data by tenant using the subdomain.

---

## 🔄 User Flow

### For Tenant (Shop Owner):
1. Login to ERP
2. Go to **Settings** → **Website Setup**
3. Enter shop name and desired subdomain
4. Click **"Create My Website"**
5. Wait for admin to deploy (or auto-deploy with script)
6. Receive notification when website is live
7. Manage website content via Website module

### For Admin (You):
1. Receive notification of new website request
2. Run deployment script: `node scripts/deploy_tenant_website.js <tenant_id>`
3. Script automatically:
   - Creates Firebase Hosting site
   - Deploys Flutter web app
   - Updates database with URL
4. Tenant receives email/notification that website is live

---

## 💰 Cost Breakdown

- **Firebase Hosting:** FREE (up to 10 GB storage, 360 MB/day transfer)
- **Each additional site:** FREE (can have 36 sites per project)
- **Custom domain (optional):** ~$12/year per tenant
- **SSL certificate:** FREE (auto-included with Firebase)

**Total cost for 10 tenants:** $0/month (if using .web.app domains)

---

## 🎯 Next Steps

1. ✅ Add database columns to `company_settings`
2. ✅ Create `WebsiteSetupService`
3. ✅ Create `WebsiteSetupPage` UI
4. ✅ Add menu item in Settings → Website Setup
5. ✅ Create Node.js deployment script
6. ✅ Test with 2-3 dummy tenants
7. ✅ Add email notifications
8. ✅ (Optional) Auto-deploy with GitHub Actions

---

## 📝 Notes

- Each tenant sees ONLY their data (filtered by `tenant_id`)
- Same Flutter codebase serves all tenants
- Each tenant can customize:
  - Shop name
  - Logo
  - Colors
  - Products
  - Banners
  - Content
- Data isolation guaranteed by RLS policies

---

**Ready to implement? Start with Step 1 (database schema) and I'll help you build each piece!** 🚀
