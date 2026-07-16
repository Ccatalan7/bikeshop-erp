import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../shared/widgets/branded_loading.dart';
import '../../../shared/widgets/main_layout.dart';
import '../../../shared/widgets/safe_layout_builder.dart';
import '../services/website_service.dart';

import '../models/website_page_models.dart';

/// Comprehensive SEO Settings Page
/// Manages all SEO-related settings for Google Merchant Center compliance
class SeoSettingsPage extends StatefulWidget {
  final bool embedded;

  const SeoSettingsPage({super.key, this.embedded = false});

  @override
  State<SeoSettingsPage> createState() => _SeoSettingsPageState();
}

class _SeoSettingsPageState extends State<SeoSettingsPage>
    with TickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _hasChanges = false;

  // Business Information
  final _businessNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _addressStreetController = TextEditingController();
  final _addressCityController = TextEditingController();
  final _addressRegionController = TextEditingController();
  final _addressPostalController = TextEditingController();
  final _addressCountryController = TextEditingController();
  final _googleMapsUrlController = TextEditingController();

  // Meta Tags
  final _metaTitleController = TextEditingController();
  final _metaDescriptionController = TextEditingController();
  final _metaKeywordsController = TextEditingController();
  final _canonicalUrlController = TextEditingController();

  // Open Graph
  final _ogTitleController = TextEditingController();
  final _ogDescriptionController = TextEditingController();
  final _ogImageController = TextEditingController();

  // Twitter Cards
  final _twitterTitleController = TextEditingController();
  final _twitterDescriptionController = TextEditingController();
  final _twitterImageController = TextEditingController();

  // Legal Pages
  final _refundPolicyUrlController = TextEditingController();
  final _termsUrlController = TextEditingController();
  final _shippingPolicyUrlController = TextEditingController();
  final _privacyPolicyUrlController = TextEditingController();

  // Structured Data Toggles
  bool _enableLocalBusinessSchema = true;
  bool _enableOrganizationSchema = true;

  // Analytics
  final _gaIdController = TextEditingController();
  final _fbPixelIdController = TextEditingController();
  final _gtmIdController = TextEditingController();

  // Pages for SEO audit
  List<WebsitePage> _allPages = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadSettings();
    _loadPages();
  }

  @override
  void dispose() {
    _businessNameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _addressStreetController.dispose();
    _addressCityController.dispose();
    _addressRegionController.dispose();
    _addressPostalController.dispose();
    _addressCountryController.dispose();
    _googleMapsUrlController.dispose();
    _metaTitleController.dispose();
    _metaDescriptionController.dispose();
    _metaKeywordsController.dispose();
    _canonicalUrlController.dispose();
    _ogTitleController.dispose();
    _ogDescriptionController.dispose();
    _ogImageController.dispose();
    _twitterTitleController.dispose();
    _twitterDescriptionController.dispose();
    _twitterImageController.dispose();
    _refundPolicyUrlController.dispose();
    _termsUrlController.dispose();
    _shippingPolicyUrlController.dispose();
    _privacyPolicyUrlController.dispose();
    _gaIdController.dispose();
    _fbPixelIdController.dispose();
    _gtmIdController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadPages() async {
    try {
      final service = context.read<WebsiteService>();
      // Load pages from website_pages table using existing method
      await service.loadPages();
      if (mounted) {
        setState(() => _allPages = service.pages);
      }
    } catch (e) {
      debugPrint('Error loading pages for SEO audit: $e');
    }
  }

  Future<void> _confirmDeletePage(WebsitePage page) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar página'),
        content: Text(
            '¿Eliminar "${page.title}" (/${page.slug})?\n\nEsta acción no se puede deshacer.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        final service = context.read<WebsiteService>();
        await service.deletePage(page.id);
        await _loadPages(); // Refresh list
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Página "${page.title}" eliminada'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);

    try {
      final service = context.read<WebsiteService>();
      await service.loadSettings();

      if (mounted) {
        setState(() {
          // Business Information
          _businessNameController.text = service.getSetting(
              'seo_business_name', service.getSetting('store_name', ''));
          _phoneController.text = service.getSetting(
              'seo_phone', service.getSetting('contact_phone', ''));
          _emailController.text = service.getSetting(
              'seo_email', service.getSetting('contact_email', ''));
          _addressStreetController.text = service.getSetting(
              'seo_address_street', service.getSetting('contact_address', ''));
          _addressCityController.text =
              service.getSetting('seo_address_city', '');
          _addressRegionController.text =
              service.getSetting('seo_address_region', '');
          _addressPostalController.text =
              service.getSetting('seo_address_postal', '');
          _addressCountryController.text =
              service.getSetting('seo_address_country', 'Chile');
          _googleMapsUrlController.text =
              service.getSetting('seo_google_maps_url', '');

          // Meta Tags
          _metaTitleController.text = service.getSetting(
              'seo_meta_title', service.getSetting('meta_title', ''));
          _metaDescriptionController.text = service.getSetting(
              'seo_meta_description',
              service.getSetting('meta_description', ''));
          _metaKeywordsController.text = service.getSetting(
              'seo_meta_keywords', service.getSetting('meta_keywords', ''));
          _canonicalUrlController.text = service.getSetting(
              'seo_canonical_url', service.getSetting('store_url', ''));

          // Open Graph
          _ogTitleController.text = service.getSetting('seo_og_title', '');
          _ogDescriptionController.text =
              service.getSetting('seo_og_description', '');
          _ogImageController.text = service.getSetting('seo_og_image', '');

          // Twitter Cards
          _twitterTitleController.text =
              service.getSetting('seo_twitter_title', '');
          _twitterDescriptionController.text =
              service.getSetting('seo_twitter_description', '');
          _twitterImageController.text =
              service.getSetting('seo_twitter_image', '');

          // Legal Pages
          _refundPolicyUrlController.text =
              service.getSetting('seo_refund_policy_url', '');
          _termsUrlController.text = service.getSetting('seo_terms_url', '');
          _shippingPolicyUrlController.text =
              service.getSetting('seo_shipping_policy_url', '');
          _privacyPolicyUrlController.text =
              service.getSetting('seo_privacy_policy_url', '');

          // Structured Data
          _enableLocalBusinessSchema =
              service.getSetting('seo_enable_localbusiness_schema', 'true') ==
                  'true';
          _enableOrganizationSchema =
              service.getSetting('seo_enable_organization_schema', 'true') ==
                  'true';

          // Analytics
          _gaIdController.text =
              service.getSetting('seo_ga_id', 'G-FR5Q37BW43');
          _fbPixelIdController.text = service.getSetting('seo_fb_pixel_id', '');
          _gtmIdController.text = service.getSetting('seo_gtm_id', '');
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _saveSettings() async {
    setState(() => _isSaving = true);

    try {
      final service = context.read<WebsiteService>();

      final settings = {
        // Business Information
        'seo_business_name': _businessNameController.text,
        'seo_phone': _phoneController.text,
        'seo_email': _emailController.text,
        'seo_address_street': _addressStreetController.text,
        'seo_address_city': _addressCityController.text,
        'seo_address_region': _addressRegionController.text,
        'seo_address_postal': _addressPostalController.text,
        'seo_address_country': _addressCountryController.text,
        'seo_google_maps_url': _googleMapsUrlController.text,

        // Also sync to legacy keys for footer
        'contact_phone': _phoneController.text,
        'contact_email': _emailController.text,
        'contact_address': _addressStreetController.text.isNotEmpty
            ? '${_addressStreetController.text}, ${_addressCityController.text}, ${_addressCountryController.text}'
            : '',

        // Meta Tags
        'seo_meta_title': _metaTitleController.text,
        'seo_meta_description': _metaDescriptionController.text,
        'seo_meta_keywords': _metaKeywordsController.text,
        'seo_canonical_url': _canonicalUrlController.text,
        'meta_title': _metaTitleController.text,
        'meta_description': _metaDescriptionController.text,
        'meta_keywords': _metaKeywordsController.text,

        // Open Graph
        'seo_og_title': _ogTitleController.text,
        'seo_og_description': _ogDescriptionController.text,
        'seo_og_image': _ogImageController.text,

        // Twitter Cards
        'seo_twitter_title': _twitterTitleController.text,
        'seo_twitter_description': _twitterDescriptionController.text,
        'seo_twitter_image': _twitterImageController.text,

        // Legal Pages
        'seo_refund_policy_url': _refundPolicyUrlController.text,
        'seo_terms_url': _termsUrlController.text,
        'seo_shipping_policy_url': _shippingPolicyUrlController.text,
        'seo_privacy_policy_url': _privacyPolicyUrlController.text,

        // Structured Data
        'seo_enable_localbusiness_schema':
            _enableLocalBusinessSchema.toString(),
        'seo_enable_organization_schema': _enableOrganizationSchema.toString(),

        // Analytics
        'seo_ga_id': _gaIdController.text,
        'seo_fb_pixel_id': _fbPixelIdController.text,
        'seo_gtm_id': _gtmIdController.text,
      };

      await service.saveSettings(settings);

      if (mounted) {
        setState(() => _hasChanges = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 12),
                Text('Configuración SEO guardada'),
              ],
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al guardar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  void _markChanged() {
    if (!_hasChanges) {
      setState(() => _hasChanges = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
          // Header
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: theme.dividerColor.withValues(alpha: 0.1),
                ),
              ),
            ),
            child: Row(
              children: [
                if (!widget.embedded) ...[
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => context.go('/website'),
                  ),
                  const SizedBox(width: 12),
                ],
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF4CAF50), Color(0xFF2E7D32)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                child: const Icon(Icons.search, color: Colors.white, size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'SEO y Datos Estructurados',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Optimización para buscadores y Google Merchant Center',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_hasChanges)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.edit, color: Colors.orange, size: 16),
                        SizedBox(width: 6),
                        Text('Cambios sin guardar',
                            style: TextStyle(
                                color: Colors.orange,
                                fontWeight: FontWeight.w500,
                                fontSize: 12)),
                      ],
                    ),
                  ),
                const SizedBox(width: 16),
                FilledButton.icon(
                  onPressed: _isSaving ? null : _saveSettings,
                  icon: _isSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.save),
                  label: Text(_isSaving ? 'Guardando...' : 'Guardar'),
                ),
              ],
            ),
          ),

          // Tab Bar
          Container(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: theme.dividerColor.withValues(alpha: 0.1),
                ),
              ),
            ),
            child: TabBar(
              controller: _tabController,
              tabs: const [
                Tab(
                  icon: Icon(Icons.settings),
                  text: 'Configuración',
                ),
                Tab(
                  icon: Icon(Icons.verified_user),
                  text: 'Verificación',
                ),
              ],
              indicatorColor: Colors.green,
              labelColor: Colors.green,
              unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
            ),
          ),

          // Tab Content
          Expanded(
            child: _isLoading
                ? const Center(child: BrandedLoading())
                : TabBarView(
                    controller: _tabController,
                    children: [
                      // Tab 1: Configuración (existing content)
                      SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Google Merchant Status Banner
                            _buildMerchantStatusBanner(theme),
                            const SizedBox(height: 24),

                            // Two column layout for larger screens
                            ConstraintLayoutBuilder(
                              builder: (context, constraints) {
                                if (constraints.maxWidth > 1200) {
                                  return Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Column(
                                          children: [
                                            _buildBusinessInfoSection(theme),
                                            const SizedBox(height: 24),
                                            _buildMetaTagsSection(theme),
                                            const SizedBox(height: 24),
                                            _buildLegalPagesSection(theme),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 24),
                                      Expanded(
                                        child: Column(
                                          children: [
                                            _buildSocialSection(theme),
                                            const SizedBox(height: 24),
                                            _buildStructuredDataSection(theme),
                                            const SizedBox(height: 24),
                                            _buildAnalyticsSection(theme),
                                          ],
                                        ),
                                      ),
                                    ],
                                  );
                                }
                                return Column(
                                  children: [
                                    _buildBusinessInfoSection(theme),
                                    const SizedBox(height: 24),
                                    _buildMetaTagsSection(theme),
                                    const SizedBox(height: 24),
                                    _buildLegalPagesSection(theme),
                                    const SizedBox(height: 24),
                                    _buildSocialSection(theme),
                                    const SizedBox(height: 24),
                                    _buildStructuredDataSection(theme),
                                    const SizedBox(height: 24),
                                    _buildAnalyticsSection(theme),
                                  ],
                                );
                              },
                            ),
                            const SizedBox(height: 32),
                          ],
                        ),
                      ),

                      // Tab 2: Verificación (SEO Audit)
                      _buildVerificationTab(theme),
                    ],
                  ),
          ),
      ],
    );

    if (widget.embedded) return content;
    return MainLayout(child: content);
  }

  /// Build the Verification/Audit tab content
  Widget _buildVerificationTab(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Site-wide sync status card
          _buildSiteSyncStatusCard(theme),
          const SizedBox(height: 24),

          // Per-page SEO audit table
          _buildPagesSeoAuditCard(theme),
        ],
      ),
    );
  }

  /// Card showing site-wide sync status
  Widget _buildSiteSyncStatusCard(ThemeData theme) {
    final hasPhone = _phoneController.text.isNotEmpty;
    final hasEmail = _emailController.text.isNotEmpty;
    final hasAddress = _addressStreetController.text.isNotEmpty;
    final hasRefund = _refundPolicyUrlController.text.isNotEmpty;
    final hasTerms = _termsUrlController.text.isNotEmpty;
    final hasShipping = _shippingPolicyUrlController.text.isNotEmpty;
    final hasPrivacy = _privacyPolicyUrlController.text.isNotEmpty;
    final hasAllLegal = hasRefund && hasTerms && hasShipping && hasPrivacy;
    final legalCount =
        [hasRefund, hasTerms, hasShipping, hasPrivacy].where((v) => v).length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.sync, color: Colors.blue, size: 22),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Estado de Sincronización',
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 2),
                      Text('Verifica que los datos estén correctos para Google',
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 32),
            _buildSyncStatusRow('Teléfono', hasPhone, _phoneController.text),
            const SizedBox(height: 8),
            _buildSyncStatusRow('Email', hasEmail, _emailController.text),
            const SizedBox(height: 8),
            _buildSyncStatusRow(
                'Dirección', hasAddress, _addressStreetController.text),
            const Divider(height: 24),
            _buildSyncStatusRow(
                'Páginas Legales', hasAllLegal, '$legalCount/4 configuradas'),
            const SizedBox(height: 16),
            if (!hasAllLegal)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border:
                      Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber,
                        color: Colors.orange, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Completa las páginas legales en la pestaña "Configuración" para aprobar Google Merchant Center',
                        style: TextStyle(
                            color: Colors.orange.shade800, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSyncStatusRow(String label, bool isOk, String value) {
    return Row(
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: isOk ? Colors.green : Colors.grey.shade300,
            shape: BoxShape.circle,
          ),
          child: Icon(
            isOk ? Icons.check : Icons.remove,
            color: Colors.white,
            size: 16,
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 140,
          child:
              Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
        ),
        Expanded(
          child: Text(
            value.isNotEmpty ? value : '—',
            style: TextStyle(
              color: isOk ? Colors.black87 : Colors.grey,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
    );
  }

  /// Card showing per-page SEO audit
  Widget _buildPagesSeoAuditCard(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.purple.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.description,
                      color: Colors.purple, size: 22),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('SEO por Página',
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 2),
                      Text(
                          'Cada página necesita su propio título y descripción',
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                TextButton.icon(
                  onPressed: _loadPages,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Actualizar'),
                ),
              ],
            ),
            const Divider(height: 32),
            if (_allPages.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    children: [
                      Icon(Icons.hourglass_empty,
                          size: 48, color: Colors.grey.shade400),
                      const SizedBox(height: 16),
                      Text('Cargando páginas...',
                          style: TextStyle(color: Colors.grey.shade600)),
                    ],
                  ),
                ),
              )
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columnSpacing: 24,
                  columns: const [
                    DataColumn(label: Text('Página')),
                    DataColumn(label: Text('Slug')),
                    DataColumn(label: Text('Meta Title')),
                    DataColumn(label: Text('Meta Desc')),
                    DataColumn(label: Text('OG Image')),
                    DataColumn(label: Text('Estado')),
                    DataColumn(label: Text('Acción')),
                  ],
                  rows: _allPages.map((page) {
                    final hasTitle = page.metaTitle?.isNotEmpty == true;
                    final hasDesc = page.metaDescription?.isNotEmpty == true;
                    final hasImage = page.ogImageUrl?.isNotEmpty == true;
                    final isComplete = hasTitle && hasDesc;
                    final isPartial = hasTitle || hasDesc;

                    return DataRow(cells: [
                      DataCell(Text(page.title,
                          style: const TextStyle(fontWeight: FontWeight.w500))),
                      DataCell(Text('/${page.slug}')),
                      DataCell(_buildStatusCell(hasTitle)),
                      DataCell(_buildStatusCell(hasDesc)),
                      DataCell(_buildStatusCell(hasImage)),
                      DataCell(_buildOverallStatusCell(isComplete, isPartial)),
                      DataCell(
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextButton(
                              onPressed: () {
                                context.go('/website/pagina/${page.slug}');
                              },
                              child: const Text('Editar'),
                            ),
                            if (!page.isHome && !page.isSystem)
                              IconButton(
                                icon: const Icon(Icons.delete_outline,
                                    size: 18, color: Colors.red),
                                tooltip: 'Eliminar página',
                                onPressed: () => _confirmDeletePage(page),
                              ),
                          ],
                        ),
                      ),
                    ]);
                  }).toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCell(bool isOk) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isOk
            ? Colors.green.withValues(alpha: 0.1)
            : Colors.grey.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isOk ? Icons.check_circle : Icons.remove_circle_outline,
            size: 16,
            color: isOk ? Colors.green : Colors.grey,
          ),
          const SizedBox(width: 4),
          Text(
            isOk ? 'OK' : '—',
            style: TextStyle(
              color: isOk ? Colors.green : Colors.grey,
              fontWeight: FontWeight.w500,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverallStatusCell(bool isComplete, bool isPartial) {
    if (isComplete) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.green.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, size: 16, color: Colors.green),
            SizedBox(width: 4),
            Text('Completo',
                style: TextStyle(
                    color: Colors.green,
                    fontWeight: FontWeight.w500,
                    fontSize: 12)),
          ],
        ),
      );
    } else if (isPartial) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.orange.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.warning_amber, size: 16, color: Colors.orange),
            SizedBox(width: 4),
            Text('Parcial',
                style: TextStyle(
                    color: Colors.orange,
                    fontWeight: FontWeight.w500,
                    fontSize: 12)),
          ],
        ),
      );
    } else {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 16, color: Colors.red),
            SizedBox(width: 4),
            Text('Falta',
                style: TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.w500,
                    fontSize: 12)),
          ],
        ),
      );
    }
  }

  Widget _buildMerchantStatusBanner(ThemeData theme) {
    // Check completion status
    final hasBusinessInfo = _businessNameController.text.isNotEmpty &&
        _phoneController.text.isNotEmpty &&
        _emailController.text.isNotEmpty;
    final hasLegalPages = _refundPolicyUrlController.text.isNotEmpty &&
        _termsUrlController.text.isNotEmpty &&
        _privacyPolicyUrlController.text.isNotEmpty;
    final hasMeta = _metaTitleController.text.isNotEmpty &&
        _metaDescriptionController.text.isNotEmpty;

    final isComplete = hasBusinessInfo && hasLegalPages && hasMeta;
    final completionPercent =
        [hasBusinessInfo, hasLegalPages, hasMeta].where((v) => v).length / 3;

    return Card(
      color: isComplete ? Colors.green.shade50 : Colors.orange.shade50,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isComplete ? Colors.green : Colors.orange,
                shape: BoxShape.circle,
              ),
              child: Icon(
                isComplete ? Icons.verified : Icons.warning_amber,
                color: Colors.white,
                size: 28,
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isComplete
                        ? '¡Listo para Google Merchant Center!'
                        : 'Configuración incompleta',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: isComplete
                          ? Colors.green.shade800
                          : Colors.orange.shade800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isComplete
                        ? 'Tu sitio cumple con los requisitos de Google Merchant Center'
                        : 'Completa los campos requeridos para aprobar la verificación',
                    style: TextStyle(
                      color: isComplete
                          ? Colors.green.shade700
                          : Colors.orange.shade700,
                    ),
                  ),
                  if (!isComplete) ...[
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: completionPercent,
                      backgroundColor: Colors.orange.shade200,
                      valueColor:
                          AlwaysStoppedAnimation(Colors.orange.shade600),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBusinessInfoSection(ThemeData theme) {
    return _buildSection(
      theme: theme,
      icon: Icons.business,
      iconColor: Colors.blue,
      title: 'Información del Negocio',
      subtitle: 'Datos de contacto para Google Merchant Center',
      isRequired: true,
      children: [
        _buildTextField(
          controller: _businessNameController,
          label: 'Nombre del Negocio',
          hint: 'Ej: Vinabike',
          icon: Icons.store,
          isRequired: true,
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildTextField(
                controller: _phoneController,
                label: 'Teléfono',
                hint: '+56998357797',
                icon: Icons.phone,
                isRequired: true,
                keyboardType: TextInputType.phone,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildTextField(
                controller: _emailController,
                label: 'Email',
                hint: 'contacto@tutienda.cl',
                icon: Icons.email,
                isRequired: true,
                keyboardType: TextInputType.emailAddress,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildTextField(
          controller: _addressStreetController,
          label: 'Dirección',
          hint: 'Álvarez 32, Local 17',
          icon: Icons.location_on,
          isRequired: true,
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildTextField(
                controller: _addressCityController,
                label: 'Ciudad',
                hint: 'Viña del Mar',
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildTextField(
                controller: _addressRegionController,
                label: 'Región',
                hint: 'Valparaíso',
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildTextField(
                controller: _addressPostalController,
                label: 'Código Postal',
                hint: '2520000',
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildTextField(
                controller: _addressCountryController,
                label: 'País',
                hint: 'Chile',
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildTextField(
          controller: _googleMapsUrlController,
          label: 'URL de Google Maps',
          hint: 'https://maps.google.com/...',
          icon: Icons.map,
        ),
      ],
    );
  }

  Widget _buildMetaTagsSection(ThemeData theme) {
    return _buildSection(
      theme: theme,
      icon: Icons.code,
      iconColor: Colors.orange,
      title: 'Meta Tags',
      subtitle: 'Cómo aparece tu sitio en Google',
      isRequired: true,
      children: [
        _buildTextField(
          controller: _metaTitleController,
          label: 'Título SEO',
          hint: 'Vinabike - Tienda de Bicicletas en Viña del Mar',
          icon: Icons.title,
          isRequired: true,
          maxLength: 60,
          helperText: 'Máximo 60 caracteres',
        ),
        const SizedBox(height: 16),
        _buildTextField(
          controller: _metaDescriptionController,
          label: 'Meta Descripción',
          hint:
              'Tu tienda especializada en ciclismo, repuestos y servicio técnico',
          icon: Icons.description,
          isRequired: true,
          maxLength: 160,
          maxLines: 3,
          helperText: 'Máximo 160 caracteres',
        ),
        const SizedBox(height: 16),
        _buildTextField(
          controller: _metaKeywordsController,
          label: 'Palabras Clave',
          hint: 'bicicletas, mtb, ruta, ciclismo, repuestos',
          icon: Icons.label,
          helperText: 'Separadas por comas',
        ),
        const SizedBox(height: 16),
        _buildTextField(
          controller: _canonicalUrlController,
          label: 'URL Canónica',
          hint: 'https://vinabike.cl',
          icon: Icons.link,
        ),
      ],
    );
  }

  Widget _buildLegalPagesSection(ThemeData theme) {
    return _buildSection(
      theme: theme,
      icon: Icons.gavel,
      iconColor: Colors.green,
      title: 'Páginas Legales',
      subtitle: 'Requeridas por Google Merchant Center',
      isRequired: true,
      children: [
        _buildLegalUrlField(
          controller: _refundPolicyUrlController,
          label: 'Política de Reembolso',
          isConfigured: _refundPolicyUrlController.text.isNotEmpty,
        ),
        const SizedBox(height: 12),
        _buildLegalUrlField(
          controller: _termsUrlController,
          label: 'Términos y Condiciones',
          isConfigured: _termsUrlController.text.isNotEmpty,
        ),
        const SizedBox(height: 12),
        _buildLegalUrlField(
          controller: _shippingPolicyUrlController,
          label: 'Política de Envíos',
          isConfigured: _shippingPolicyUrlController.text.isNotEmpty,
        ),
        const SizedBox(height: 12),
        _buildLegalUrlField(
          controller: _privacyPolicyUrlController,
          label: 'Política de Privacidad',
          isConfigured: _privacyPolicyUrlController.text.isNotEmpty,
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.blue.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              const Icon(Icons.lightbulb_outline, color: Colors.blue, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Tip: Crea estas páginas en el Editor de Páginas y copia las URLs aquí',
                  style: TextStyle(color: Colors.blue.shade700, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSocialSection(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader(
              theme: theme,
              icon: Icons.share,
              iconColor: Colors.purple,
              title: 'Redes Sociales',
              subtitle: 'Open Graph y Twitter Cards',
            ),
            const Divider(height: 32),

            // Open Graph subsection
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                children: [
                  Icon(Icons.facebook, color: Colors.blue.shade700, size: 20),
                  const SizedBox(width: 8),
                  Text('Open Graph (Facebook, LinkedIn)',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            _buildTextField(
              controller: _ogTitleController,
              label: 'og:title',
              hint: 'Título para compartir en redes',
            ),
            const SizedBox(height: 12),
            _buildTextField(
              controller: _ogDescriptionController,
              label: 'og:description',
              hint: 'Descripción para compartir',
              maxLines: 2,
            ),
            const SizedBox(height: 12),
            _buildTextField(
              controller: _ogImageController,
              label: 'og:image',
              hint: 'URL de imagen para compartir',
              icon: Icons.image,
            ),

            const SizedBox(height: 24),

            // Twitter Cards subsection
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                children: [
                  Icon(Icons.alternate_email,
                      color: Colors.lightBlue.shade600, size: 20),
                  const SizedBox(width: 8),
                  Text('Twitter Cards',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            _buildTextField(
              controller: _twitterTitleController,
              label: 'twitter:title',
              hint: 'Título para Twitter',
            ),
            const SizedBox(height: 12),
            _buildTextField(
              controller: _twitterDescriptionController,
              label: 'twitter:description',
              hint: 'Descripción para Twitter',
              maxLines: 2,
            ),
            const SizedBox(height: 12),
            _buildTextField(
              controller: _twitterImageController,
              label: 'twitter:image',
              hint: 'URL de imagen para Twitter',
              icon: Icons.image,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStructuredDataSection(ThemeData theme) {
    return _buildSection(
      theme: theme,
      icon: Icons.data_object,
      iconColor: Colors.teal,
      title: 'Datos Estructurados',
      subtitle: 'JSON-LD Schema para buscadores',
      children: [
        SwitchListTile(
          title: const Text('LocalBusiness Schema'),
          subtitle: const Text('Mejora visibilidad en búsquedas locales'),
          value: _enableLocalBusinessSchema,
          onChanged: (value) {
            setState(() => _enableLocalBusinessSchema = value);
            _markChanged();
          },
          secondary: Icon(
            Icons.location_city,
            color: _enableLocalBusinessSchema ? Colors.teal : Colors.grey,
          ),
        ),
        const Divider(),
        SwitchListTile(
          title: const Text('Organization Schema'),
          subtitle: const Text('Información de la empresa en Google'),
          value: _enableOrganizationSchema,
          onChanged: (value) {
            setState(() => _enableOrganizationSchema = value);
            _markChanged();
          },
          secondary: Icon(
            Icons.business,
            color: _enableOrganizationSchema ? Colors.teal : Colors.grey,
          ),
        ),
        const SizedBox(height: 16),
        ExpansionTile(
          title: const Text('Ver JSON-LD generado'),
          tilePadding: EdgeInsets.zero,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                _generateJsonLdPreview(),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAnalyticsSection(ThemeData theme) {
    return _buildSection(
      theme: theme,
      icon: Icons.analytics,
      iconColor: Colors.amber,
      title: 'Analytics y Tracking',
      subtitle: 'IDs de seguimiento',
      children: [
        _buildTextField(
          controller: _gaIdController,
          label: 'Google Analytics ID',
          hint: 'G-XXXXXXXXXX',
          icon: Icons.analytics,
        ),
        const SizedBox(height: 16),
        _buildTextField(
          controller: _fbPixelIdController,
          label: 'Facebook Pixel ID',
          hint: '123456789012345',
          icon: Icons.facebook,
        ),
        const SizedBox(height: 16),
        _buildTextField(
          controller: _gtmIdController,
          label: 'Google Tag Manager ID',
          hint: 'GTM-XXXXXXX',
          icon: Icons.code,
        ),
      ],
    );
  }

  Widget _buildSection({
    required ThemeData theme,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required List<Widget> children,
    bool isRequired = false,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader(
              theme: theme,
              icon: icon,
              iconColor: iconColor,
              title: title,
              subtitle: subtitle,
              isRequired: isRequired,
            ),
            const Divider(height: 32),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader({
    required ThemeData theme,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    bool isRequired = false,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: iconColor, size: 22),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(title,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  if (isRequired) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text('Requerido',
                          style: TextStyle(
                              color: Colors.red,
                              fontSize: 10,
                              fontWeight: FontWeight.w600)),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              Text(subtitle,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    String? hint,
    IconData? icon,
    bool isRequired = false,
    int? maxLength,
    int maxLines = 1,
    String? helperText,
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: controller,
      maxLength: maxLength,
      maxLines: maxLines,
      keyboardType: keyboardType,
      onChanged: (_) => _markChanged(),
      decoration: InputDecoration(
        labelText: isRequired ? '$label *' : label,
        hintText: hint,
        helperText: helperText,
        prefixIcon: icon != null ? Icon(icon) : null,
        border: const OutlineInputBorder(),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    );
  }

  Widget _buildLegalUrlField({
    required TextEditingController controller,
    required String label,
    required bool isConfigured,
  }) {
    return Row(
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: isConfigured ? Colors.green : Colors.grey.shade300,
            shape: BoxShape.circle,
          ),
          child: Icon(
            isConfigured ? Icons.check : Icons.remove,
            color: Colors.white,
            size: 16,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: TextField(
            controller: controller,
            onChanged: (_) {
              _markChanged();
              setState(() {}); // Update the status icon
            },
            decoration: InputDecoration(
              labelText: label,
              hintText: '/politica-de-reembolso',
              border: const OutlineInputBorder(),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              suffixIcon: controller.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.open_in_new, size: 18),
                      onPressed: () {
                        final url = controller.text.startsWith('http')
                            ? controller.text
                            : 'https://vinabike.cl${controller.text}';
                        Clipboard.setData(ClipboardData(text: url));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('URL copiada')),
                        );
                      },
                    )
                  : null,
            ),
          ),
        ),
      ],
    );
  }

  String _generateJsonLdPreview() {
    return '''{
  "@context": "https://schema.org",
  "@type": "LocalBusiness",
  "name": "${_businessNameController.text}",
  "telephone": "${_phoneController.text}",
  "email": "${_emailController.text}",
  "address": {
    "@type": "PostalAddress",
    "streetAddress": "${_addressStreetController.text}",
    "addressLocality": "${_addressCityController.text}",
    "addressRegion": "${_addressRegionController.text}",
    "postalCode": "${_addressPostalController.text}",
    "addressCountry": "${_addressCountryController.text}"
  },
  "url": "${_canonicalUrlController.text}"
}''';
  }
}
