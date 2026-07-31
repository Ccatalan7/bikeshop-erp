part of '../website_editor_panel.dart';

class _SyncTab extends StatefulWidget {
  const _SyncTab();

  @override
  State<_SyncTab> createState() => _SyncTabState();
}

class _SyncTabState extends State<_SyncTab> {
  bool _attemptedProviderTokenEnsure = false;

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
                    onPressed: () => googleService.connect(
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
                    onPressed: () => googleService.connect(
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
            onTap: () async {
              try {
                final hasAccess = await _ensureGoogleApiAccess(
                  context,
                  googleService,
                );
                if (!hasAccess || !context.mounted) return;

                final locations = await googleService.fetchLocations();
                if (!context.mounted) return;

                if (locations.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('No se encontraron ubicaciones')),
                  );
                } else {
                  _showLocationSelectionDialog(
                      context, locations, websiteService);
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text('Error: $e'),
                        backgroundColor: Colors.red),
                  );
                }
              }
            },
          ),
          const SizedBox(height: 12),
          _ActionCard(
            title: 'Sincronizar Reseñas',
            description: hasProviderToken
                ? 'Descargar últimas reseñas de Google.'
                : 'Renovar permiso para descargar reseñas.',
            icon: Icons.reviews,
            onTap: () async {
              try {
                final hasAccess = await _ensureGoogleApiAccess(
                  context,
                  googleService,
                );
                if (!hasAccess) return;
                if (!context.mounted) return;

                // 1. Get location name from settings (saved in previous step)
                final locationName =
                    websiteService.getSetting('business_google_location_id');

                if (locationName.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text(
                            'Primero debes sincronizar los datos del negocio para obtener la ubicación.')),
                  );
                  return;
                }

                // 2. Fetch reviews
                final reviews = await googleService.fetchReviews(locationName);
                if (!context.mounted) return;

                // 3. Save to settings
                if (reviews.isNotEmpty) {
                  await websiteService.saveSetting(
                      'google_reviews_data', jsonEncode(reviews));
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                          'Se descargaron ${reviews.length} reseñas correctamente!'),
                      backgroundColor: const Color(0xFF00A09D),
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text(
                            'No se encontraron reseñas para esta ubicación.')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text('Error: $e'),
                        backgroundColor: Colors.red),
                  );
                }
              }
            },
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
    BuildContext context,
    GoogleBusinessService googleService,
  ) async {
    if (googleService.hasProviderToken) return true;

    if (googleService.isLinked) {
      final restored = await googleService.ensureProviderToken(
        timeout: const Duration(seconds: 3),
      );
      if (restored) return true;
    }

    if (!context.mounted) return false;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Los datos guardados siguen conectados. Para refrescarlos desde Google, renueva el permiso.',
        ),
      ),
    );
    await googleService.connect(
                editorCapability: context
                    .read<WebsiteEditModeProvider>()
                    .editorEntryLease,
              );
    return false;
  }

  void _showLocationSelectionDialog(BuildContext context,
      List<GoogleLocation> locations, WebsiteService websiteService) {
    showDialog(
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
                onTap: () async {
                  final settings = <String, String>{
                    'business_name': loc.title,
                    'business_google_location_id': loc.name,
                  };

                  if (loc.phone != null) {
                    settings['business_phone'] = loc.phone!;
                    settings['contact_phone'] = loc.phone!;
                    settings['seo_phone'] = loc.phone!;
                  }

                  if (loc.addressLine != null) {
                    settings['contact_address'] = loc.addressLine!;
                  }
                  if (loc.addressStreet != null) {
                    settings['seo_address_street'] = loc.addressStreet!;
                  }
                  if (loc.addressCity != null) {
                    settings['seo_address_city'] = loc.addressCity!;
                  }
                  if (loc.addressRegion != null) {
                    settings['seo_address_region'] = loc.addressRegion!;
                  }
                  if (loc.addressPostalCode != null) {
                    settings['seo_address_postal'] = loc.addressPostalCode!;
                  }
                  if (loc.addressCountry != null) {
                    settings['seo_address_country'] = loc.addressCountry!;
                  }

                  if (loc.hours != null && loc.hours!.isNotEmpty) {
                    settings['google_business_regular_hours'] =
                        jsonEncode(loc.hours);
                  }

                  final mapsUrl = loc.mapsUri;
                  if (mapsUrl != null && mapsUrl.trim().isNotEmpty) {
                    settings['business_google_maps_url'] = mapsUrl.trim();
                    settings['seo_google_maps_url'] = mapsUrl.trim();
                  }

                  final reviewUrl = loc.newReviewUri;
                  if (reviewUrl != null && reviewUrl.trim().isNotEmpty) {
                    settings['business_google_review_url'] = reviewUrl.trim();
                  }

                  await websiteService.saveSettings(settings);
                  if (!ctx.mounted || !context.mounted) return;

                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Datos sincronizados correctamente!'),
                      backgroundColor: Color(0xFF00A09D),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}
