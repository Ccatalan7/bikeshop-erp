import 'package:vinabike_public_core/modules/website/theme/website_theme_roles.dart';
import 'package:vinabike_public_core/public_store/models/public_business_hours.dart';
import 'package:vinabike_public_core/public_store/seo/public_page_structured_data.dart';
import 'package:vinabike_public_core/public_store/utils/social_url.dart';

import 'public_reads.dart';
import 'site_layout.dart';
import 'contact_page_css.dart';

/// `/contacto`, as Flutter's `ContactPage` decides it: the store's contact
/// settings (an unset one is left out, never another store's), its opening
/// hours, a link to Google Maps, WhatsApp and the social networks, and a
/// form that writes an email to the store. Not published: «Contacto no
/// disponible».
class ContactPageModel {
  ContactPageModel._({
    required this.page,
    required this.meta,
    required this.available,
    required this.email,
    required this.phone,
    required this.address,
    required this.whatsappDigits,
    required this.instagramUrl,
    required this.facebookUrl,
    required this.mapsUrl,
    required this.hours,
  });

  factory ContactPageModel.build({
    required PageContext page,
    required ContactPageReads reads,
  }) {
    final shell = page.shell;
    String setting(String key) => shell.setting(key).trim();
    String first(List<String> keys) => keys
        .map(setting)
        .firstWhere((value) => value.isNotEmpty, orElse: () => '');
    final storeName = setting('store_name');
    final address = setting('contact_address');
    final configuredMaps = first(const [
      'seo_google_maps_url',
      'business_google_maps_url',
      'google_maps_url',
    ]);
    // A search link only when there is something real to search for.
    final mapsQuery = [
      storeName,
      address.replaceAll('\n', ' '),
    ].map((value) => value.trim()).where((value) => value.isNotEmpty).join(' ');
    final mapsUrl = configuredMaps.isNotEmpty
        ? configuredMaps
        : mapsQuery.isEmpty
        ? ''
        : 'https://www.google.com/maps/search/?api=1&query='
              '${Uri.encodeComponent(mapsQuery)}';

    final row = reads.page;
    final available = row != null;
    final seoName = shell.setting('seo_business_name', storeName).trim();
    final configuredTitle = (row?['title'] ?? '').toString().trim();
    final title = configuredTitle.isNotEmpty ? configuredTitle : 'Contacto';
    final configuredSeoTitle = (row?['meta_title'] ?? '').toString().trim();
    final seoTitle = configuredSeoTitle.isNotEmpty
        ? configuredSeoTitle
        : seoName.isEmpty
        ? title
        : '$title | $seoName';
    final configuredDescription = (row?['meta_description'] ?? '')
        .toString()
        .trim();
    final description = configuredDescription.isNotEmpty
        ? configuredDescription
        : 'Dirección, teléfono, correo y horario de '
              '${seoName.isEmpty ? 'la tienda' : seoName}.';
    final canonicalUrl = '${page.storeUrl}/contacto';
    final configuredImage = (row?['og_image_url'] ?? '').toString().trim();
    final theme = WebsiteThemeRoles.resolve(shell.setting);

    return ContactPageModel._(
      page: page,
      meta: PageMeta(
        title: available
            ? seoTitle
            : 'Contacto no disponible${seoName.isEmpty ? '' : ' | $seoName'}',
        description: available
            ? description
            : 'Esta página todavía no está publicada.',
        canonicalUrl: canonicalUrl,
        indexable: available,
        imageUrl: configuredImage.isNotEmpty
            ? configuredImage
            : shell.setting('seo_og_image', shell.setting('logo_url')),
        structuredData: [
          if (available)
            buildPublicPageStructuredData(
              slug: 'contacto',
              title: title,
              description: description,
              pageUrl: canonicalUrl,
              storeUrl: page.storeUrl,
              storeName: seoName,
            ),
        ],
        styles: contactPageCss(theme),
      ),
      available: available,
      email: setting('contact_email'),
      phone: setting('contact_phone'),
      address: address,
      // The footer's number (WhatsApp takes it with or without the «+»
      // Flutter's contact page keeps).
      whatsappDigits: shell.whatsappDigits,
      instagramUrl: normalizeSocialUrl(
        setting('instagram'),
        'https://instagram.com/',
      ),
      facebookUrl: normalizeSocialUrl(
        setting('facebook'),
        'https://facebook.com/',
      ),
      mapsUrl: mapsUrl,
      hours: publicBusinessHourRows(
        first(const ['business_hours_json', 'google_business_regular_hours']),
      ),
    );
  }

  final PageContext page;
  final PageMeta meta;

  /// The `contacto` page is published.
  final bool available;
  final String email;
  final String phone;
  final String address;
  final String whatsappDigits;
  final String? instagramUrl;
  final String? facebookUrl;
  final String mapsUrl;
  final List<PublicBusinessHourRow> hours;

  /// The WhatsApp link with Flutter's greeting.
  String get whatsappHref =>
      'https://wa.me/$whatsappDigits?text='
      '${Uri.encodeComponent('¡Hola! Me gustaría obtener más información.')}';
}
