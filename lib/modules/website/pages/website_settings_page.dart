import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../shared/widgets/branded_loading.dart';
import '../models/website_seo_settings_aliases.dart';
import '../services/website_service.dart';
import '../widgets/website_admin_ui.dart';
import '../widgets/website_media_picker.dart';
import '../../../shared/services/tenant_service.dart';
import '../../../shared/models/tenant.dart';

/// Page for configuring website settings
class WebsiteSettingsPage extends StatefulWidget {
  const WebsiteSettingsPage({
    super.key,
    this.embedded = false,
  });

  final bool embedded;

  @override
  State<WebsiteSettingsPage> createState() => _WebsiteSettingsPageState();
}

class _WebsiteSettingsPageState extends State<WebsiteSettingsPage> {
  final _formKey = GlobalKey<FormState>();

  // Store info
  late final TextEditingController _storeNameController;
  late final TextEditingController _storeUrlController;
  late final TextEditingController _storeDescriptionController;

  // Contact info
  late final TextEditingController _contactEmailController;
  late final TextEditingController _contactPhoneController;
  late final TextEditingController _contactAddressController;
  late final TextEditingController _whatsappController;

  // Transfer payment info
  late final TextEditingController _paymentTransferBankNameController;
  late final TextEditingController _paymentTransferAccountTypeController;
  late final TextEditingController _paymentTransferAccountNumberController;
  late final TextEditingController _paymentTransferAccountHolderController;
  late final TextEditingController _paymentTransferRutController;
  late final TextEditingController _paymentTransferEmailController;
  late final TextEditingController _paymentTransferInstructionsController;

  // Social media
  late final TextEditingController _facebookController;
  late final TextEditingController _instagramController;
  late final TextEditingController _twitterController;
  late final TextEditingController _youtubeController;

  // Canonical site SEO owner
  late final TextEditingController _seoMetaTitleController;
  late final TextEditingController _seoMetaDescriptionController;
  late final TextEditingController _seoTopicsController;
  late final TextEditingController _seoProductTitleTemplateController;
  late final TextEditingController _seoProductDescriptionTemplateController;

  /// GA4 measurement id.
  ///
  /// This page is its only writer. `scripts/sync_seo_index.sh` requires
  /// `seo_ga_id` and validates the same `G-…` shape before it will build the
  /// indexable shell, so an operator with no control over it cannot publish.
  late final TextEditingController _seoAnalyticsIdController;

  String _seoOgImageUrl = '';
  final GlobalKey _seoSectionKey = GlobalKey();

  /// Read-only projection of the company profile.
  ///
  /// `CompanyProfileService` writes these keys into `website_settings` whenever
  /// the company record is saved. Editing them here would create a second
  /// writer whose empty values that projection silently resurrects, so this
  /// page shows the effective value and routes to the owner.
  static const List<({String key, String label})> _companyOwnedSeoFields = [
    (key: 'business_legal_name', label: 'Razón social'),
    (key: 'business_tax_id', label: 'RUT'),
    (key: 'seo_address_street', label: 'Calle'),
    (key: 'seo_address_city', label: 'Ciudad'),
    (key: 'seo_address_region', label: 'Región'),
    (key: 'seo_address_postal', label: 'Código postal'),
    (key: 'seo_address_country', label: 'País'),
  ];

  Map<String, String> _companyOwnedValues = const {};

  // Feature toggles
  bool _enableOrders = true;
  bool _showPrices = true;
  bool _requireLogin = false;
  bool _enableReviews = false;
  bool _showStock = true;

  bool _isLoading = false;
  bool _isSaving = false;
  Tenant? _currentTenant;

  @override
  void initState() {
    super.initState();

    // Initialize controllers
    _storeNameController = TextEditingController();
    _storeUrlController = TextEditingController();
    _storeDescriptionController = TextEditingController();
    _contactEmailController = TextEditingController();
    _contactPhoneController = TextEditingController();
    _contactAddressController = TextEditingController();
    _whatsappController = TextEditingController();
    _paymentTransferBankNameController = TextEditingController();
    _paymentTransferAccountTypeController = TextEditingController();
    _paymentTransferAccountNumberController = TextEditingController();
    _paymentTransferAccountHolderController = TextEditingController();
    _paymentTransferRutController = TextEditingController();
    _paymentTransferEmailController = TextEditingController();
    _paymentTransferInstructionsController = TextEditingController();
    _facebookController = TextEditingController();
    _instagramController = TextEditingController();
    _twitterController = TextEditingController();
    _youtubeController = TextEditingController();
    _seoMetaTitleController = TextEditingController();
    _seoMetaDescriptionController = TextEditingController();
    _seoTopicsController = TextEditingController();
    _seoProductTitleTemplateController = TextEditingController();
    _seoProductDescriptionTemplateController = TextEditingController();
    _seoAnalyticsIdController = TextEditingController();
    // Load settings
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadSettings();
    });
  }

  @override
  void dispose() {
    _storeNameController.dispose();
    _storeUrlController.dispose();
    _storeDescriptionController.dispose();
    _contactEmailController.dispose();
    _contactPhoneController.dispose();
    _contactAddressController.dispose();
    _whatsappController.dispose();
    _paymentTransferBankNameController.dispose();
    _paymentTransferAccountTypeController.dispose();
    _paymentTransferAccountNumberController.dispose();
    _paymentTransferAccountHolderController.dispose();
    _paymentTransferRutController.dispose();
    _paymentTransferEmailController.dispose();
    _paymentTransferInstructionsController.dispose();
    _facebookController.dispose();
    _instagramController.dispose();
    _twitterController.dispose();
    _youtubeController.dispose();
    _seoMetaTitleController.dispose();
    _seoMetaDescriptionController.dispose();
    _seoTopicsController.dispose();
    _seoProductTitleTemplateController.dispose();
    _seoProductDescriptionTemplateController.dispose();
    _seoAnalyticsIdController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);

    try {
      final service = context.read<WebsiteService>();
      final tenantService = context.read<TenantService>();
      await service.loadSettings();

      // Load current tenant data
      final tenantData = await tenantService.getCurrentTenant();

      debugPrint('🔍 Tenant data loaded: $tenantData');

      if (tenantData != null && mounted) {
        _currentTenant = Tenant.fromJson(tenantData);
        debugPrint(
            '✅ Tenant object created: ${_currentTenant?.shopName} (${_currentTenant?.subdomain})');
      } else {
        debugPrint('❌ Tenant data is NULL!');
      }

      if (mounted) {
        final tenantName = _currentTenant?.shopName ?? 'Mi Tienda';
        final tenantSubdomain = _currentTenant?.subdomain ?? 'mitienda';
        final tenantEmail =
            _currentTenant?.ownerEmail ?? 'contacto@mitienda.cl';

        debugPrint(
            '📝 Using values: name=$tenantName, subdomain=$tenantSubdomain, email=$tenantEmail');

        setState(() {
          // Store info - Use tenant data as defaults
          _storeNameController.text =
              service.getSetting('store_name', tenantName);
          _storeUrlController.text = service.getSetting(
              'store_url', 'https://$tenantSubdomain.bikeshop-erp.app');
          _storeDescriptionController.text = service.getSetting(
              'store_description', 'Tienda de bicicletas y accesorios');

          // Contact - Use tenant data as defaults
          _contactEmailController.text =
              service.getSetting('contact_email', tenantEmail);
          _contactPhoneController.text =
              service.getSetting('contact_phone', '');
          _contactAddressController.text =
              service.getSetting('contact_address', '');
          _whatsappController.text = service.getSetting('whatsapp', '');
          _paymentTransferBankNameController.text =
              service.getSetting('payment_transfer_bank_name', '');
          _paymentTransferAccountTypeController.text =
              service.getSetting('payment_transfer_account_type', '');
          _paymentTransferAccountNumberController.text =
              service.getSetting('payment_transfer_account_number', '');
          _paymentTransferAccountHolderController.text =
              service.getSetting('payment_transfer_account_holder', '');
          _paymentTransferRutController.text =
              service.getSetting('payment_transfer_rut', '');
          _paymentTransferEmailController.text = service.getSetting(
              'payment_transfer_contact_email',
              service.getSetting('contact_email', tenantEmail));
          _paymentTransferInstructionsController.text =
              service.getSetting('payment_transfer_instructions', '');

          // Social media
          _facebookController.text = service.getSetting('facebook', '');
          _instagramController.text = service.getSetting('instagram', '');
          _twitterController.text = service.getSetting('twitter', '');
          _youtubeController.text = service.getSetting('youtube', '');

          _seoMetaTitleController.text = service.getSetting(
            'seo_meta_title',
            service.getSetting('meta_title', ''),
          );
          _seoMetaDescriptionController.text = service.getSetting(
            'seo_meta_description',
            service.getSetting('meta_description', ''),
          );
          _seoTopicsController.text = service.getSetting(
            'seo_meta_keywords',
            service.getSetting('meta_keywords', ''),
          );
          _seoAnalyticsIdController.text = service.getSetting('seo_ga_id', '');
          _companyOwnedValues = {
            for (final field in _companyOwnedSeoFields)
              field.key: field.key == 'seo_address_city'
                  ? service.getSetting(
                      'seo_address_city',
                      service.getSetting('seo_address_locality', ''),
                    )
                  : service.getSetting(field.key, ''),
          };
          _seoProductTitleTemplateController.text = service.getSetting(
            'seo_product_title_template',
            '{product_name} | {store_name}',
          );
          _seoProductDescriptionTemplateController.text = service.getSetting(
            'seo_product_description_template',
            '{product_description}',
          );
          _seoOgImageUrl = service.getSetting('seo_og_image', '');

          // Feature toggles
          _enableOrders = service.getSetting('enable_orders', 'true') == 'true';
          _showPrices = service.getSetting('show_prices', 'true') == 'true';
          _requireLogin =
              service.getSetting('require_login', 'false') == 'true';
          _enableReviews =
              service.getSetting('enable_reviews', 'false') == 'true';
          _showStock = service.getSetting('show_stock', 'true') == 'true';
        });

        if (GoRouterState.of(context).uri.queryParameters['section'] == 'seo') {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final targetContext = _seoSectionKey.currentContext;
            if (mounted && targetContext != null) {
              Scrollable.ensureVisible(
                targetContext,
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
                alignment: 0.05,
              );
            }
          });
        }
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return WebsiteAdminShell(
      embedded: widget.embedded,
      title: 'Configuración del sitio',
      description: 'Datos públicos, medios de contacto y reglas de compra.',
      actions: [
        IconButton.outlined(
          icon: const Icon(Icons.refresh_rounded, size: 19),
          onPressed: _loadSettings,
          tooltip: 'Recargar configuración',
        ),
        FilledButton.icon(
          onPressed: _isSaving ? null : _saveSettings,
          icon: _isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.save_outlined, size: 18),
          label: Text(_isSaving ? 'Guardando…' : 'Guardar'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _isLoading
                ? const Center(child: BrandedLoading())
                : Form(
                    key: _formKey,
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 920),
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
                          children: [
                            // Store Information Section
                            _buildSection(
                              icon: Icons.store,
                              title: 'Información de la Tienda',
                              color: Colors.blue,
                              children: [
                                TextFormField(
                                  controller: _storeNameController,
                                  onChanged: (_) => setState(() {}),
                                  decoration: const InputDecoration(
                                    labelText: 'Nombre de la Tienda',
                                    hintText: 'Ej: Vinabike',
                                    prefixIcon: Icon(Icons.storefront),
                                  ),
                                  validator: (value) => value?.isEmpty ?? true
                                      ? 'Campo requerido'
                                      : null,
                                ),
                                const SizedBox(height: 16),
                                TextFormField(
                                  controller: _storeUrlController,
                                  onChanged: (_) => setState(() {}),
                                  decoration: const InputDecoration(
                                    labelText: 'URL de la Tienda',
                                    hintText: 'https://tienda.ejemplo.cl',
                                    prefixIcon: Icon(Icons.link),
                                  ),
                                  validator: (value) {
                                    final raw = value?.trim() ?? '';
                                    if (raw.isEmpty) {
                                      return 'Campo requerido';
                                    }
                                    if (WebsiteSeoSettingsAliases
                                            .normalizeHttpsOrigin(raw)
                                        .isEmpty) {
                                      return 'Ingresa solo el dominio público con HTTPS, sin rutas ni parámetros';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 16),
                                TextFormField(
                                  controller: _storeDescriptionController,
                                  onChanged: (_) => setState(() {}),
                                  decoration: const InputDecoration(
                                    labelText: 'Descripción',
                                    hintText: 'Breve descripción de tu tienda',
                                    prefixIcon: Icon(Icons.description),
                                  ),
                                  maxLines: 3,
                                ),
                              ],
                            ),

                            const SizedBox(height: 32),

                            // Contact Information Section
                            _buildSection(
                              icon: Icons.contact_mail,
                              title: 'Información de Contacto',
                              color: Colors.green,
                              children: [
                                TextFormField(
                                  controller: _contactEmailController,
                                  decoration: const InputDecoration(
                                    labelText: 'Email de Contacto',
                                    hintText: 'contacto@ejemplo.cl',
                                    prefixIcon: Icon(Icons.email),
                                  ),
                                  keyboardType: TextInputType.emailAddress,
                                  validator: (value) {
                                    if (value?.isEmpty ?? true) {
                                      return 'Campo requerido';
                                    }
                                    if (!value!.contains('@')) {
                                      return 'Email inválido';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 16),
                                TextFormField(
                                  controller: _contactPhoneController,
                                  decoration: const InputDecoration(
                                    labelText: 'Teléfono',
                                    hintText: '+56 2 2345 6789',
                                    prefixIcon: Icon(Icons.phone),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                TextFormField(
                                  controller: _whatsappController,
                                  decoration: const InputDecoration(
                                    labelText: 'WhatsApp',
                                    hintText: '+56912345678',
                                    prefixIcon: Icon(Icons.chat),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                TextFormField(
                                  controller: _contactAddressController,
                                  decoration: const InputDecoration(
                                    labelText: 'Dirección',
                                    hintText: 'Calle, Ciudad',
                                    prefixIcon: Icon(Icons.location_on),
                                  ),
                                  maxLines: 2,
                                ),
                              ],
                            ),

                            const SizedBox(height: 32),

                            _buildSection(
                              icon: Icons.account_balance,
                              title: 'Datos para Transferencia',
                              color: Colors.amber,
                              children: [
                                TextFormField(
                                  controller:
                                      _paymentTransferBankNameController,
                                  decoration: const InputDecoration(
                                    labelText: 'Banco',
                                    hintText: 'Ej: Banco de Chile',
                                    prefixIcon: Icon(Icons.account_balance),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                TextFormField(
                                  controller:
                                      _paymentTransferAccountTypeController,
                                  decoration: const InputDecoration(
                                    labelText: 'Tipo de Cuenta',
                                    hintText: 'Ej: Cuenta Vista',
                                    prefixIcon: Icon(Icons.badge_outlined),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                TextFormField(
                                  controller:
                                      _paymentTransferAccountNumberController,
                                  decoration: const InputDecoration(
                                    labelText: 'Número de Cuenta',
                                    hintText: 'Ej: 81522258',
                                    prefixIcon: Icon(Icons.numbers),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                TextFormField(
                                  controller:
                                      _paymentTransferAccountHolderController,
                                  decoration: const InputDecoration(
                                    labelText: 'Titular',
                                    hintText: 'Ej: Newen SpA',
                                    prefixIcon: Icon(Icons.person_outline),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                TextFormField(
                                  controller: _paymentTransferRutController,
                                  decoration: const InputDecoration(
                                    labelText: 'RUT',
                                    hintText: 'Ej: 77541999-7',
                                    prefixIcon:
                                        Icon(Icons.credit_card_outlined),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                TextFormField(
                                  controller: _paymentTransferEmailController,
                                  decoration: const InputDecoration(
                                    labelText: 'Email para Comprobante',
                                    hintText: 'Ej: contacto@vinabike.cl',
                                    prefixIcon:
                                        Icon(Icons.mark_email_read_outlined),
                                  ),
                                  keyboardType: TextInputType.emailAddress,
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return null;
                                    }
                                    if (!value.contains('@')) {
                                      return 'Email inválido';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 16),
                                TextFormField(
                                  controller:
                                      _paymentTransferInstructionsController,
                                  decoration: const InputDecoration(
                                    labelText: 'Instrucciones Adicionales',
                                    hintText:
                                        'Ej: Envía el comprobante junto con tu número de pedido',
                                    prefixIcon: Icon(Icons.info_outline),
                                  ),
                                  maxLines: 3,
                                ),
                              ],
                            ),

                            const SizedBox(height: 32),

                            // Social Media Section
                            _buildSection(
                              icon: Icons.share,
                              title: 'Redes Sociales',
                              color: Colors.purple,
                              children: [
                                TextFormField(
                                  controller: _facebookController,
                                  decoration: InputDecoration(
                                    labelText: 'Facebook',
                                    hintText: 'usuario o URL',
                                    prefixIcon: Icon(Icons.facebook,
                                        color: Colors.blue[700]),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                TextFormField(
                                  controller: _instagramController,
                                  decoration: InputDecoration(
                                    labelText: 'Instagram',
                                    hintText: '@usuario',
                                    prefixIcon: Icon(Icons.camera_alt,
                                        color: Colors.pink[400]),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                TextFormField(
                                  controller: _twitterController,
                                  decoration: InputDecoration(
                                    labelText: 'Twitter / X',
                                    hintText: '@usuario',
                                    prefixIcon: Icon(Icons.alternate_email,
                                        color: Colors.blue[400]),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                TextFormField(
                                  controller: _youtubeController,
                                  decoration: InputDecoration(
                                    labelText: 'YouTube',
                                    hintText: '@canal',
                                    prefixIcon: Icon(Icons.video_library,
                                        color: Colors.red[600]),
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 32),

                            KeyedSubtree(
                              key: _seoSectionKey,
                              child: _buildSection(
                                icon: Icons.search,
                                title: 'Cómo aparece tu sitio en buscadores',
                                color: Theme.of(context).colorScheme.primary,
                                children: [
                                  Text(
                                    'Estos son los datos generales que heredan '
                                    'las páginas y productos cuando no tienen '
                                    'un texto propio.',
                                    style:
                                        Theme.of(context).textTheme.bodyMedium,
                                  ),
                                  const SizedBox(height: 16),
                                  TextFormField(
                                    controller: _seoMetaTitleController,
                                    maxLength: 60,
                                    onChanged: (_) => setState(() {}),
                                    decoration: const InputDecoration(
                                      labelText: 'Título del sitio',
                                      hintText:
                                          'Viñabike | Bicicletas y taller',
                                      helperText:
                                          'Es el título principal que puede mostrar Google.',
                                      prefixIcon: Icon(Icons.title_rounded),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  TextFormField(
                                    controller: _seoMetaDescriptionController,
                                    minLines: 3,
                                    maxLines: 4,
                                    maxLength: 165,
                                    onChanged: (_) => setState(() {}),
                                    decoration: const InputDecoration(
                                      labelText: 'Descripción del sitio',
                                      hintText:
                                          'Explica qué vendes, qué servicio ofreces y dónde.',
                                      helperText:
                                          'Texto breve y persuasivo para los resultados de búsqueda.',
                                      prefixIcon: Icon(Icons.notes_rounded),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  _buildSearchResultPreview(),
                                  const SizedBox(height: 20),
                                  TextFormField(
                                    controller: _seoTopicsController,
                                    minLines: 2,
                                    maxLines: 3,
                                    decoration: const InputDecoration(
                                      labelText: 'Temas principales del sitio',
                                      hintText:
                                          'bicicletas, repuestos, taller de bicicletas',
                                      helperText:
                                          'Orientación editorial separada por comas; no garantiza posicionamiento.',
                                      prefixIcon:
                                          Icon(Icons.label_outline_rounded),
                                    ),
                                  ),
                                  const SizedBox(height: 18),
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      'Imagen al compartir el sitio',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelLarge
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  WebsiteImagePickerField(
                                    currentUrl: _seoOgImageUrl.trim().isEmpty
                                        ? null
                                        : _seoOgImageUrl,
                                    enableBackgroundRemoval: false,
                                    onChanged: (url) => setState(
                                      () => _seoOgImageUrl = url.trim(),
                                    ),
                                  ),
                                  if (_seoOgImageUrl.trim().isNotEmpty)
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: TextButton.icon(
                                        onPressed: () => setState(
                                          () => _seoOgImageUrl = '',
                                        ),
                                        icon: const Icon(
                                          Icons.delete_outline_rounded,
                                          size: 18,
                                        ),
                                        label:
                                            const Text('Quitar imagen global'),
                                      ),
                                    ),
                                  const SizedBox(height: 8),
                                  ExpansionTile(
                                    tilePadding: EdgeInsets.zero,
                                    childrenPadding: EdgeInsets.zero,
                                    title: const Text(
                                      'Plantillas automáticas para productos',
                                    ),
                                    subtitle: const Text(
                                      'Se usan solo cuando un producto no tiene texto SEO propio.',
                                    ),
                                    children: [
                                      const SizedBox(height: 8),
                                      TextFormField(
                                        controller:
                                            _seoProductTitleTemplateController,
                                        decoration: const InputDecoration(
                                          labelText:
                                              'Plantilla de título de producto',
                                          helperText:
                                              'Variables: {product_name}, {store_name}, {product_brand}, {product_price}, {product_sku}',
                                        ),
                                      ),
                                      const SizedBox(height: 14),
                                      TextFormField(
                                        controller:
                                            _seoProductDescriptionTemplateController,
                                        minLines: 2,
                                        maxLines: 4,
                                        decoration: const InputDecoration(
                                          labelText:
                                              'Plantilla de descripción de producto',
                                          helperText:
                                              'También admite {product_description}.',
                                        ),
                                      ),
                                    ],
                                  ),
                                  _buildCompanyOwnedSeoTile(),
                                  _buildAnalyticsTile(),
                                  const SizedBox(height: 16),
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: OutlinedButton.icon(
                                      onPressed: () =>
                                          context.push('/website/seo'),
                                      icon: const Icon(
                                        Icons.travel_explore_rounded,
                                      ),
                                      label: const Text(
                                        'Ver diagnóstico y evidencia SEO',
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 32),

                            // Feature Toggles Section
                            _buildSection(
                              icon: Icons.tune,
                              title: 'Funcionalidades',
                              color: Colors.teal,
                              children: [
                                SwitchListTile(
                                  title: const Text('Habilitar Pedidos Online'),
                                  subtitle: const Text(
                                      'Los clientes pueden hacer compras'),
                                  value: _enableOrders,
                                  onChanged: (value) =>
                                      setState(() => _enableOrders = value),
                                  secondary: Icon(
                                    Icons.shopping_cart,
                                    color: _enableOrders
                                        ? Colors.green
                                        : Colors.grey,
                                  ),
                                ),
                                const Divider(),
                                SwitchListTile(
                                  title: const Text('Mostrar Precios'),
                                  subtitle: const Text(
                                      'Precios visibles para visitantes'),
                                  value: _showPrices,
                                  onChanged: (value) =>
                                      setState(() => _showPrices = value),
                                  secondary: Icon(
                                    Icons.attach_money,
                                    color: _showPrices
                                        ? Colors.green
                                        : Colors.grey,
                                  ),
                                ),
                                const Divider(),
                                SwitchListTile(
                                  title: const Text('Mostrar Stock'),
                                  subtitle:
                                      const Text('Cantidad disponible visible'),
                                  value: _showStock,
                                  onChanged: (value) =>
                                      setState(() => _showStock = value),
                                  secondary: Icon(
                                    Icons.inventory,
                                    color:
                                        _showStock ? Colors.green : Colors.grey,
                                  ),
                                ),
                                const Divider(),
                                SwitchListTile(
                                  title:
                                      const Text('Requiere Login para Comprar'),
                                  subtitle: const Text(
                                      'Los clientes deben crear cuenta'),
                                  value: _requireLogin,
                                  onChanged: (value) =>
                                      setState(() => _requireLogin = value),
                                  secondary: Icon(
                                    Icons.login,
                                    color: _requireLogin
                                        ? Colors.orange
                                        : Colors.grey,
                                  ),
                                ),
                                const Divider(),
                                SwitchListTile(
                                  title: const Text('Habilitar Reseñas'),
                                  subtitle: const Text(
                                      'Los clientes pueden dejar comentarios'),
                                  value: _enableReviews,
                                  onChanged: (value) =>
                                      setState(() => _enableReviews = value),
                                  secondary: Icon(
                                    Icons.star,
                                    color: _enableReviews
                                        ? Colors.amber
                                        : Colors.grey,
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 32),

                            Align(
                              alignment: Alignment.centerRight,
                              child: FilledButton.icon(
                                onPressed: _isSaving ? null : _saveSettings,
                                icon: const Icon(Icons.save_outlined, size: 18),
                                label: const Text('Guardar cambios'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  /// Read-only projection of the company-profile owner.
  ///
  /// These keys reach `website_settings` through
  /// `CompanyProfileService._buildWebsiteSettings`, and `sync_seo_index.sh`
  /// refuses to build the indexable shell while any of them is empty. Showing
  /// them here — with their real emptiness — makes that failure visible from
  /// the SEO surface without creating a competing writer.
  Widget _buildCompanyOwnedSeoTile() {
    final theme = Theme.of(context);
    final missing = _companyOwnedSeoFields
        .where((field) => (_companyOwnedValues[field.key] ?? '').trim().isEmpty)
        .length;

    return ExpansionTile(
      // `initiallyExpanded` is read once per State. Keying on the condition
      // makes the re-evaluation explicit instead of depending on the loading
      // placeholder happening to replace this subtree.
      key: ValueKey('company-owned-seo-${missing > 0}'),
      tilePadding: EdgeInsets.zero,
      childrenPadding: EdgeInsets.zero,
      // Opened by default only when something is actually missing, so the
      // normal case stays compact and the blocking case is not hidden.
      initiallyExpanded: missing > 0,
      title: const Text('Identidad legal y dirección del negocio'),
      subtitle: Text(
        missing == 0
            ? 'Se usan en los datos estructurados del sitio. Los edita la '
                'ficha de empresa.'
            : '$missing de ${_companyOwnedSeoFields.length} sin definir. La '
                'publicación indexable los exige.',
        style: missing == 0 ? null : TextStyle(color: theme.colorScheme.error),
      ),
      children: [
        const SizedBox(height: 4),
        for (final field in _companyOwnedSeoFields)
          _buildOwnedValueRow(
            label: field.label,
            value: (_companyOwnedValues[field.key] ?? '').trim(),
          ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: () => context.push('/settings/company'),
            icon: const Icon(Icons.badge_outlined, size: 18),
            label: const Text('Editar en la ficha de empresa'),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildOwnedValueRow({required String label, required String value}) {
    final theme = Theme.of(context);
    final isEmpty = value.isEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 132,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              isEmpty ? 'Sin definir' : value,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: isEmpty ? FontWeight.w400 : FontWeight.w600,
                color: isEmpty ? theme.colorScheme.error : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The only writer of `seo_ga_id` in the application.
  Widget _buildAnalyticsTile() {
    final isUnset = _seoAnalyticsIdController.text.trim().isEmpty;
    return ExpansionTile(
      key: ValueKey('seo-analytics-$isUnset'),
      tilePadding: EdgeInsets.zero,
      childrenPadding: EdgeInsets.zero,
      initiallyExpanded: isUnset,
      title: const Text('Medición de audiencia'),
      subtitle: const Text(
        'Identificador de Google Analytics 4 usado por el sitio publicado.',
      ),
      children: [
        const SizedBox(height: 8),
        TextFormField(
          controller: _seoAnalyticsIdController,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            labelText: 'ID de medición GA4',
            hintText: 'G-XXXXXXXXXX',
            helperText:
                'Empieza con «G-». Déjalo vacío solo si no vas a medir: la '
                'publicación indexable lo exige.',
            prefixIcon: Icon(Icons.insights_outlined),
          ),
          validator: (value) {
            final raw = value?.trim() ?? '';
            if (raw.isEmpty) return null;
            // Same shape the publish script enforces, so an invalid value is
            // rejected here instead of failing the build later.
            if (!RegExp(r'^G-[A-Z0-9]+$').hasMatch(raw)) {
              return 'Formato inválido. Debe ser como G-XXXXXXXXXX.';
            }
            return null;
          },
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildSearchResultPreview() {
    final theme = Theme.of(context);
    final title = _seoMetaTitleController.text.trim().isNotEmpty
        ? _seoMetaTitleController.text.trim()
        : _storeNameController.text.trim().isNotEmpty
            ? _storeNameController.text.trim()
            : 'Tu tienda';
    final description = _seoMetaDescriptionController.text.trim().isNotEmpty
        ? _seoMetaDescriptionController.text.trim()
        : _storeDescriptionController.text.trim().isNotEmpty
            ? _storeDescriptionController.text.trim()
            : 'Agrega una descripción breve de tu tienda.';
    final url = _storeUrlController.text.trim().isEmpty
        ? 'https://tu-dominio.cl'
        : _storeUrlController.text.trim();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Vista previa aproximada',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            url,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.tertiary,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            description,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(height: 1.35),
          ),
        ],
      ),
    );
  }

  Widget _buildSection({
    required IconData icon,
    required String title,
    required Color color,
    required List<Widget> children,
  }) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.11),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 19),
            ),
            const SizedBox(width: 11),
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        WebsiteAdminSurface(
          accent: color,
          child: Column(
            children: children,
          ),
        ),
      ],
    );
  }

  Future<void> _saveSettings() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final service = context.read<WebsiteService>();

      // Save all settings
      final settings = {
        // Store
        'store_name': _storeNameController.text,
        'store_url': _storeUrlController.text,
        'store_description': _storeDescriptionController.text,

        // Contact
        'contact_email': _contactEmailController.text,
        'contact_phone': _contactPhoneController.text,
        'contact_address': _contactAddressController.text,
        'whatsapp': _whatsappController.text,
        'payment_transfer_bank_name': _paymentTransferBankNameController.text,
        'payment_transfer_account_type':
            _paymentTransferAccountTypeController.text,
        'payment_transfer_account_number':
            _paymentTransferAccountNumberController.text,
        'payment_transfer_account_holder':
            _paymentTransferAccountHolderController.text,
        'payment_transfer_rut': _paymentTransferRutController.text,
        'payment_transfer_contact_email': _paymentTransferEmailController.text,
        'payment_transfer_instructions':
            _paymentTransferInstructionsController.text,

        // Social
        'facebook': _facebookController.text,
        'instagram': _instagramController.text,
        'twitter': _twitterController.text,
        'youtube': _youtubeController.text,

        // Canonical site SEO owner.
        //
        // `seo_address_*`, `business_legal_name` and `business_tax_id` are
        // deliberately absent: the company profile owns them and re-projects
        // them on every save, so writing them here would be a second writer
        // whose cleared values that projection silently restores.
        'seo_meta_title': _seoMetaTitleController.text,
        'seo_meta_description': _seoMetaDescriptionController.text,
        'seo_meta_keywords': _seoTopicsController.text,
        'seo_ga_id': _seoAnalyticsIdController.text.trim(),
        'seo_og_image': _seoOgImageUrl,
        'seo_product_title_template': _seoProductTitleTemplateController.text,
        'seo_product_description_template':
            _seoProductDescriptionTemplateController.text,

        // Features
        'enable_orders': _enableOrders.toString(),
        'show_prices': _showPrices.toString(),
        'require_login': _requireLogin.toString(),
        'enable_reviews': _enableReviews.toString(),
        'show_stock': _showStock.toString(),
      };

      // One operation. The previous per-key loop issued 33 sequential upserts,
      // so a failure midway left the site configured half old and half new
      // while still reporting a plain error.
      await service.saveSettings(settings);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Configuración guardada exitosamente'),
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
}
