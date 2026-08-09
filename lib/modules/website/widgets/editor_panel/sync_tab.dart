part of '../website_editor_panel.dart';

class _SyncTab extends StatefulWidget {
  const _SyncTab();

  @override
  State<_SyncTab> createState() => _SyncTabState();
}

class _SyncTabState extends State<_SyncTab> {
  bool _attemptedProviderTokenEnsure = false;
  bool _locationsInFlight = false;
  bool _reviewsInFlight = false;

  // The host revision closes the provider/service A -> B -> A hole. Equal
  // lease fields on the remounted A instance do not erase that B owned this
  // State in between.
  WebsiteEditModeProvider? _remoteWriteProviderIdentity;
  GoogleBusinessService? _remoteWriteGoogleServiceIdentity;
  WebsiteService? _remoteWriteWebsiteServiceIdentity;
  int _remoteWriteHostRevision = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    WebsiteEditModeProvider? provider;
    GoogleBusinessService? googleService;
    WebsiteService? websiteService;
    try {
      provider = context.read<WebsiteEditModeProvider>();
      googleService = context.read<GoogleBusinessService>();
      websiteService = context.read<WebsiteService>();
    } catch (_) {
      // Without the complete owner set this tab cannot issue a remote write.
    }

    if ((_remoteWriteProviderIdentity != null &&
            !identical(_remoteWriteProviderIdentity, provider)) ||
        (_remoteWriteGoogleServiceIdentity != null &&
            !identical(_remoteWriteGoogleServiceIdentity, googleService)) ||
        (_remoteWriteWebsiteServiceIdentity != null &&
            !identical(_remoteWriteWebsiteServiceIdentity, websiteService))) {
      _remoteWriteHostRevision++;
    }
    _remoteWriteProviderIdentity = provider;
    _remoteWriteGoogleServiceIdentity = googleService;
    _remoteWriteWebsiteServiceIdentity = websiteService;
  }

  ({
    WebsiteEditorRemoteWriteAuthority authority,
    WebsiteEditModeProvider provider,
    GoogleBusinessService googleService,
    WebsiteService websiteService,
  })? _captureRemoteWrite({
    required String operation,
    required Iterable<String> sourceKeys,
  }) {
    WebsiteEditModeProvider provider;
    GoogleBusinessService googleService;
    WebsiteService websiteService;
    try {
      provider = context.read<WebsiteEditModeProvider>();
      googleService = context.read<GoogleBusinessService>();
      websiteService = context.read<WebsiteService>();
    } catch (_) {
      return null;
    }

    final intent = provider.captureSitewideAsyncIntent(
      bucket: WebsiteSitewideDraftBucket.siteSettings,
      sourceKeys: sourceKeys,
    );
    final tenantId = provider.sessionOwnerTenantId?.trim() ?? '';
    final fingerprint = provider.sessionOwnerLeaseFingerprint;
    if (intent == null || tenantId.isEmpty || fingerprint == null) return null;

    final hostRevision = _remoteWriteHostRevision;
    final entryLeaseGeneration = provider.editorEntryLeaseGeneration;
    final entryLeaseIdentityRevision =
        provider.editorEntryLeaseIdentityRevision;
    bool isCurrent() {
      if (!mounted || _remoteWriteHostRevision != hostRevision) return false;
      try {
        final liveProvider = context.read<WebsiteEditModeProvider>();
        final liveGoogleService = context.read<GoogleBusinessService>();
        final liveWebsiteService = context.read<WebsiteService>();
        return identical(liveProvider, provider) &&
            identical(liveGoogleService, googleService) &&
            identical(liveWebsiteService, websiteService) &&
            liveProvider.editorEntryLeaseGeneration == entryLeaseGeneration &&
            liveProvider.editorEntryLeaseIdentityRevision ==
                entryLeaseIdentityRevision &&
            liveProvider.sessionOwnerTenantId == tenantId &&
            liveProvider.sessionOwnerLeaseFingerprint == fingerprint;
      } catch (_) {
        return false;
      }
    }

    return (
      authority: WebsiteEditorRemoteWriteAuthority(
        tenantId: tenantId,
        operation: operation,
        isCurrent: isCurrent,
        claimOwner: () =>
            provider.commitSitewideAsyncIntent(
              intent,
              () => WebsiteInlineMutationResult.unchanged,
            ) !=
            WebsiteInlineMutationResult.rejected,
      ),
      provider: provider,
      googleService: googleService,
      websiteService: websiteService,
    );
  }

  Future<void> _syncLocations() async {
    if (_locationsInFlight || _reviewsInFlight) return;
    final scope = _captureRemoteWrite(
      operation: 'sincronizar los datos de Google',
      sourceKeys: const <String>{
        'business_name',
        'business_google_location_id',
        'business_phone',
        'contact_phone',
        'seo_phone',
        'contact_address',
        'seo_address_street',
        'seo_address_city',
        'seo_address_region',
        'seo_address_postal',
        'seo_address_country',
        'google_business_regular_hours',
        'business_google_maps_url',
        'seo_google_maps_url',
        'business_google_review_url',
      },
    );
    if (scope == null) return;
    setState(() => _locationsInFlight = true);

    try {
      final hasAccess = await _ensureGoogleApiAccess(scope);
      scope.authority.ensureCurrent();
      if (!hasAccess) return;

      final locations = await scope.googleService.fetchLocations();
      scope.authority.ensureCurrent();
      if (locations.isEmpty) {
        _showMessage('No se encontraron ubicaciones');
        return;
      }

      final selected = await _showLocationSelectionDialog(locations);
      scope.authority.ensureCurrent();
      if (selected == null) return;

      final writeGuard = scope.authority.claimForWrite();
      await scope.websiteService.saveSettingsForTenant(
        scope.authority.tenantId,
        _settingsForLocation(selected),
        writeGuard: writeGuard,
      );
      scope.authority.ensureCurrent();
      _showMessage(
        'Datos sincronizados correctamente!',
        backgroundColor: const Color(0xFF00A09D),
      );
    } on WebsiteEditorWriteSupersededException {
      _showMessage(
        'La sesión del editor cambió. No se guardaron los datos de Google.',
      );
    } catch (error) {
      _showMessage('Error: $error', backgroundColor: Colors.red);
    } finally {
      if (mounted) setState(() => _locationsInFlight = false);
    }
  }

  Future<void> _syncReviews() async {
    if (_locationsInFlight || _reviewsInFlight) return;
    final scope = _captureRemoteWrite(
      operation: 'sincronizar las reseñas de Google',
      sourceKeys: const <String>{
        'business_google_location_id',
        'google_reviews_data',
      },
    );
    if (scope == null) return;
    setState(() => _reviewsInFlight = true);

    try {
      final hasAccess = await _ensureGoogleApiAccess(scope);
      scope.authority.ensureCurrent();
      if (!hasAccess) return;

      final locationName =
          scope.websiteService.getSetting('business_google_location_id').trim();
      if (locationName.isEmpty) {
        _showMessage(
          'Primero debes sincronizar los datos del negocio para obtener la ubicación.',
        );
        return;
      }

      final reviews = await scope.googleService.fetchReviews(locationName);
      scope.authority.ensureCurrent();
      if (reviews.isEmpty) {
        _showMessage('No se encontraron reseñas para esta ubicación.');
        return;
      }

      final writeGuard = scope.authority.claimForWrite();
      await scope.websiteService.saveSettingsForTenant(
        scope.authority.tenantId,
        <String, String>{'google_reviews_data': jsonEncode(reviews)},
        writeGuard: writeGuard,
      );
      scope.authority.ensureCurrent();
      _showMessage(
        'Se descargaron ${reviews.length} reseñas correctamente!',
        backgroundColor: const Color(0xFF00A09D),
      );
    } on WebsiteEditorWriteSupersededException {
      _showMessage(
        'La sesión del editor cambió. No se guardaron las reseñas.',
      );
    } catch (error) {
      _showMessage('Error: $error', backgroundColor: Colors.red);
    } finally {
      if (mounted) setState(() => _reviewsInFlight = false);
    }
  }

  void _showMessage(String message, {Color? backgroundColor}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: backgroundColor),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Only verify context types, do not assume they are ready if generic
    final googleService = context.watch<GoogleBusinessService>();
    final websiteService = context.watch<WebsiteService>();
    final hasProviderToken = googleService.hasProviderToken;
    final hasSavedGoogleBusinessData =
        _hasSavedGoogleBusinessData(websiteService);

    if (!_attemptedProviderTokenEnsure &&
        googleService.isLinked &&
        !hasProviderToken) {
      _attemptedProviderTokenEnsure = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        googleService.ensureProviderToken(timeout: const Duration(seconds: 3));
      });
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'GOOGLE BUSINESS PROFILE',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Sincroniza tu información de negocio directamente desde Google para mejorar tu SEO y mostrar reseñas.',
            style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white12),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, color: Colors.white54, size: 18),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Si al conectar ves “Acceso bloqueado (403)”, no es un bug del editor: Google bloquea el acceso porque este sync usa el scope restringido business.manage.\n\nSolución rápida: en el proyecto de Google Cloud del OAuth configurado en Supabase → OAuth consent screen → Test users, agrega tu correo (ej: vinabikechile@gmail.com).\n\nPara uso público: debes completar la verificación de Google para ese scope.',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          if (googleService.error != null)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline,
                      color: Colors.amber, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      googleService.error!,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          if (hasProviderToken)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF4285F4).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: const Color(0xFF4285F4).withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle,
                      color: Color(0xFF4285F4), size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Conectado correctamente',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13),
                        ),
                        Text(
                          'Google Business Profile',
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.7),
                              fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh,
                        color: Colors.white54, size: 18),
                    tooltip: 'Reconectar',
                    onPressed: googleService.isLoading
                        ? null
                        : () => googleService.connect(
                              editorCapability: context
                                  .read<WebsiteEditModeProvider>()
                                  .editorEntryLease,
                            ),
                  ),
                ],
              ),
            )
          else if (hasSavedGoogleBusinessData)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF00A09D).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: const Color(0xFF00A09D).withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.check_circle,
                      color: Color(0xFF00A09D), size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Google conectado',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13),
                        ),
                        Text(
                          'Los datos del negocio siguen guardados. Para actualizar horarios, dirección o reseñas desde Google, renueva el permiso.',
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.7),
                              fontSize: 11,
                              height: 1.35),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh,
                        color: Colors.white54, size: 18),
                    tooltip: 'Renovar acceso',
                    onPressed: googleService.isLoading
                        ? null
                        : () => googleService.connect(
                              editorCapability: context
                                  .read<WebsiteEditModeProvider>()
                                  .editorEntryLease,
                            ),
                  ),
                ],
              ),
            )
          else if (googleService.isLinked)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Colors.orange.withValues(alpha: 0.3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.warning_amber_rounded,
                          color: Colors.orange, size: 20),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Falta un paso más',
                          style: TextStyle(
                              color: Colors.orange,
                              fontWeight: FontWeight.bold,
                              fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Tu cuenta Google está vinculada, pero necesitamos renovar el permiso para acceder a los datos del negocio.',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: googleService.isLoading
                          ? null
                          : () => googleService.connect(
                                editorCapability: context
                                    .read<WebsiteEditModeProvider>()
                                    .editorEntryLease,
                              ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.black,
                      ),
                      child: Text(googleService.isLoading
                          ? 'Conectando...'
                          : 'Autorizar Acceso Google'),
                    ),
                  ),
                ],
              ),
            )
          else
            Center(
              child: ElevatedButton.icon(
                onPressed: googleService.isLoading
                    ? null
                    : () => googleService.connect(
                          editorCapability: context
                              .read<WebsiteEditModeProvider>()
                              .editorEntryLease,
                        ),
                icon: googleService.isLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.add_link, size: 18),
                label: Text(googleService.isLoading
                    ? 'Conectando...'
                    : 'Conectar Cuenta Google'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4285F4),
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
              ),
            ),
          const SizedBox(height: 32),
          const Divider(color: Colors.white12),
          const SizedBox(height: 24),
          const Text(
            'ACCIONES',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 12),
          _ActionCard(
            title: 'Sincronizar Datos',
            description: hasProviderToken
                ? 'Importar dirección, horario y teléfono.'
                : 'Renovar permiso para actualizar desde Google.',
            icon: Icons.sync,
            enabled: !googleService.isLoading &&
                !_locationsInFlight &&
                !_reviewsInFlight,
            onTap: _syncLocations,
          ),
          const SizedBox(height: 12),
          _ActionCard(
            title: 'Sincronizar Reseñas',
            description: hasProviderToken
                ? 'Descargar últimas reseñas de Google.'
                : 'Renovar permiso para descargar reseñas.',
            icon: Icons.reviews,
            enabled: !googleService.isLoading &&
                !_locationsInFlight &&
                !_reviewsInFlight,
            onTap: _syncReviews,
          ),
        ],
      ),
    );
  }

  bool _hasSavedGoogleBusinessData(WebsiteService websiteService) {
    const keys = [
      'business_google_location_id',
      'google_maps_place_id',
      'google_business_regular_hours',
      'business_hours_json',
      'business_google_maps_url',
      'seo_google_maps_url',
      'business_google_review_url',
      'google_reviews_data',
    ];

    return keys.any((key) => websiteService.getSetting(key).trim().isNotEmpty);
  }

  Future<bool> _ensureGoogleApiAccess(
      ({
        WebsiteEditorRemoteWriteAuthority authority,
        WebsiteEditModeProvider provider,
        GoogleBusinessService googleService,
        WebsiteService websiteService,
      }) scope) async {
    final googleService = scope.googleService;
    scope.authority.ensureCurrent();
    if (googleService.hasProviderToken) return true;
    if (googleService.isLoading) return false;

    if (googleService.isLinked) {
      final restored = await googleService.ensureProviderToken(
        timeout: const Duration(seconds: 3),
      );
      scope.authority.ensureCurrent();
      if (restored) return true;
    }

    _showMessage(
      'Los datos guardados siguen conectados. Para refrescarlos desde Google, renueva el permiso.',
    );
    scope.authority.ensureCurrent();
    await googleService.connect(
      editorCapability: scope.provider.editorEntryLease,
    );
    scope.authority.ensureCurrent();
    return false;
  }

  Future<GoogleLocation?> _showLocationSelectionDialog(
    List<GoogleLocation> locations,
  ) {
    return showDialog<GoogleLocation>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Seleccionar Ubicación',
            style: TextStyle(color: Colors.white)),
        content: SizedBox(
          width: 300,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: locations.length,
            itemBuilder: (context, index) {
              final loc = locations[index];
              return ListTile(
                title: Text(loc.title,
                    style: const TextStyle(color: Colors.white)),
                subtitle: Text(loc.addressLine ?? '',
                    style: const TextStyle(color: Colors.white70)),
                onTap: () => Navigator.pop(ctx, loc),
              );
            },
          ),
        ),
      ),
    );
  }

  Map<String, String> _settingsForLocation(GoogleLocation location) {
    final settings = <String, String>{
      'business_name': location.title,
      'business_google_location_id': location.name,
    };

    final phone = location.phone;
    if (phone != null) {
      settings['business_phone'] = phone;
      settings['contact_phone'] = phone;
      settings['seo_phone'] = phone;
    }
    if (location.addressLine != null) {
      settings['contact_address'] = location.addressLine!;
    }
    if (location.addressStreet != null) {
      settings['seo_address_street'] = location.addressStreet!;
    }
    if (location.addressCity != null) {
      settings['seo_address_city'] = location.addressCity!;
    }
    if (location.addressRegion != null) {
      settings['seo_address_region'] = location.addressRegion!;
    }
    if (location.addressPostalCode != null) {
      settings['seo_address_postal'] = location.addressPostalCode!;
    }
    if (location.addressCountry != null) {
      settings['seo_address_country'] = location.addressCountry!;
    }
    if (location.hours != null && location.hours!.isNotEmpty) {
      settings['google_business_regular_hours'] = jsonEncode(location.hours);
    }

    final mapsUrl = location.mapsUri?.trim() ?? '';
    if (mapsUrl.isNotEmpty) {
      settings['business_google_maps_url'] = mapsUrl;
      settings['seo_google_maps_url'] = mapsUrl;
    }
    final reviewUrl = location.newReviewUri?.trim() ?? '';
    if (reviewUrl.isNotEmpty) {
      settings['business_google_review_url'] = reviewUrl;
    }
    return settings;
  }
}
