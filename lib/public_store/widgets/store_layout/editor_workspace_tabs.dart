part of '../public_store_layout.dart';

enum _EditorCatalogTab { products, categories, featured }

enum _EditorCategoryTab { publication, structure, presentation }

enum _EditorConfigHubTab {
  // Site
  siteHub,
  sitePages,
  siteNavigation,
  siteDestinations,
  siteSettings,

  // E-commerce
  ecomCatalog,
  ecomOrders,

  // Reports
  reportsAnalytics,

  // Config
  domain,
  seo,
  integrations,
  paymentMethods,
}

extension on _EditorConfigHubTab {
  String get title {
    switch (this) {
      case _EditorConfigHubTab.siteHub:
        return 'Sitio web';
      case _EditorConfigHubTab.sitePages:
        return 'Páginas';
      case _EditorConfigHubTab.siteNavigation:
        return 'Navegación';
      case _EditorConfigHubTab.siteDestinations:
        return 'Destinos y enlaces';
      case _EditorConfigHubTab.siteSettings:
        return 'Ajustes del sitio';
      case _EditorConfigHubTab.ecomCatalog:
        return 'Catálogo web';
      case _EditorConfigHubTab.ecomOrders:
        return 'Pedidos online';
      case _EditorConfigHubTab.reportsAnalytics:
        return 'Analytics (Google)';
      case _EditorConfigHubTab.domain:
        return 'Dominio y URL';
      case _EditorConfigHubTab.seo:
        return 'Ajustes del sitio (SEO / contacto)';
      case _EditorConfigHubTab.integrations:
        return 'Integraciones (Google Merchant)';
      case _EditorConfigHubTab.paymentMethods:
        return 'Métodos de pago';
    }
  }
}
