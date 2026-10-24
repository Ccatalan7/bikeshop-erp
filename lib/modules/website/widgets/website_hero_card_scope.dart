import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vinabike_public_core/modules/website/models/website_hero_content.dart';

import '../../../public_store/providers/public_store_tenant_provider.dart';
import '../../../public_store/services/public_inventory_service.dart';
import '../../../shared/models/product.dart';
import '../../../shared/services/tenant_service.dart';

/// Reads the product or service the split hero's card names
/// ([websiteHeroCardReference]: a SKU or an id) from the public catalog, in
/// or out of stock, as the HTML storefront reads it (`PagePicks.cards`), and
/// builds the hero with it: `null` while it loads, or when there is none.
class WebsiteHeroCardScope extends StatefulWidget {
  const WebsiteHeroCardScope({
    super.key,
    required this.reference,
    required this.tenantId,
    required this.builder,
  });

  final String? reference;
  final String? tenantId;
  final Widget Function(BuildContext context, Product? product) builder;

  @override
  State<WebsiteHeroCardScope> createState() => _WebsiteHeroCardScopeState();
}

class _WebsiteHeroCardScopeState extends State<WebsiteHeroCardScope> {
  /// The last cards read, so a rebuild of the canvas does not blink.
  static final _read = <String, Product?>{};

  Product? _product;
  int _token = 0;

  @override
  void initState() {
    super.initState();
    final key = _key();
    _product = key == null ? null : _read[key];
    _load();
  }

  @override
  void didUpdateWidget(covariant WebsiteHeroCardScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reference != widget.reference ||
        oldWidget.tenantId != widget.tenantId) {
      _load();
    }
  }

  String? _tenant() {
    final given = widget.tenantId?.trim() ?? '';
    if (given.isNotEmpty) return given;
    try {
      final store = context.read<PublicStoreTenantProvider>().tenantId;
      if (store != null && store.isNotEmpty) return store;
    } catch (_) {}
    try {
      return context.read<TenantService>().currentTenantId;
    } catch (_) {
      return null;
    }
  }

  /// `<tenant>|<reference>`, or `null` without one of them.
  String? _key() {
    final reference = widget.reference?.trim() ?? '';
    final tenantId = _tenant();
    if (reference.isEmpty || tenantId == null || tenantId.isEmpty) return null;
    return '$tenantId|$reference';
  }

  Future<void> _load() async {
    final token = ++_token;
    final key = _key();
    if (key == null) {
      if (_product != null) setState(() => _product = null);
      return;
    }
    if (_read.containsKey(key)) {
      final cached = _read[key];
      if (!identical(cached, _product)) setState(() => _product = cached);
      return;
    }
    final reference = widget.reference!.trim();
    final tenantId = key.substring(0, key.indexOf('|'));
    PublicInventoryService inventory;
    try {
      inventory = context.read<PublicInventoryService>();
    } catch (_) {
      inventory = PublicInventoryService();
    }
    final product = websiteHeroCardReferenceIsId(reference)
        ? await inventory.getProductById(
            productId: reference,
            tenantId: tenantId,
          )
        : await inventory.getProductBySku(sku: reference, tenantId: tenantId);
    if (_read.length >= 16) _read.remove(_read.keys.first);
    _read[key] = product;
    if (!mounted || token != _token) return;
    setState(() => _product = product);
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _product);
}
