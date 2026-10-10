part of '../public_store_layout.dart';

enum _EditorCatalogTab { products, resolve, services, categories, featured }


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
        return 'Resumen del sitio';
      case _EditorConfigHubTab.sitePages:
        return 'Páginas';
      case _EditorConfigHubTab.siteNavigation:
        return 'Menús';
      case _EditorConfigHubTab.siteDestinations:
        return 'Enlaces';
      case _EditorConfigHubTab.siteSettings:
        return 'Tienda y contacto';
      case _EditorConfigHubTab.ecomCatalog:
        return 'Catálogo';
      case _EditorConfigHubTab.ecomOrders:
        return 'Pedidos';
      case _EditorConfigHubTab.reportsAnalytics:
        return 'Visitas (Google Analytics)';
      case _EditorConfigHubTab.domain:
        return 'Dominio';
      case _EditorConfigHubTab.seo:
        return 'Buscadores';
      case _EditorConfigHubTab.integrations:
        return 'Integraciones';
      case _EditorConfigHubTab.paymentMethods:
        return 'Pagos';
    }
  }
}
