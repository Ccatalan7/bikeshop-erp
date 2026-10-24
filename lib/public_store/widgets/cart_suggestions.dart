import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vinabike_public_core/public_store/models/cart_suggestions_copy.dart';

import '../../shared/models/product.dart';
import '../../shared/utils/chilean_utils.dart';
import '../models/public_commerce_product_projection.dart';
import '../providers/cart_provider.dart';
import '../providers/public_store_tenant_provider.dart';
import '../services/public_inventory_service.dart';
import '../theme/public_store_surface_theme.dart';
import '../utils/product_url.dart';
import 'public_store_layout.dart';

/// «Te puede faltar» under the cart's lines (2026-10-24), as the HTML cart
/// draws it (`_moreHtml`): what fits the first lines' tyres or tubes
/// (`get_public_product_fits_v1`), in stock and not in the cart, each one
/// added from its own button. Nothing while it loads or when there is none.
class CartSuggestions extends StatefulWidget {
  const CartSuggestions({super.key, required this.isMobile});

  final bool isMobile;

  @override
  State<CartSuggestions> createState() => _CartSuggestionsState();
}

class _CartSuggestionsState extends State<CartSuggestions> {
  List<Product> _fits = const [];
  String _kind = '';
  String _asked = '';
  int _token = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _maybeLoad();
  }

  @override
  void didUpdateWidget(covariant CartSuggestions oldWidget) {
    super.didUpdateWidget(oldWidget);
    _maybeLoad();
  }

  List<String> _askedIds(CartProvider cart) => [
        for (final item in cart.items.take(CartSuggestionsCopy.askedLines))
          item.product.id,
      ];

  void _maybeLoad() {
    final cart = context.read<CartProvider>();
    final ids = _askedIds(cart);
    final asked = ids.join(',');
    if (asked == _asked) return;
    _asked = asked;
    _load(ids, inCart: {for (final item in cart.items) item.product.id});
  }

  Future<void> _load(List<String> ids, {required Set<String> inCart}) async {
    final token = ++_token;
    String? tenantId;
    try {
      tenantId = context.read<PublicStoreTenantProvider>().tenantId?.trim();
    } catch (_) {}
    if (ids.isEmpty || tenantId == null || tenantId.isEmpty) {
      // Called before a build: no setState.
      _fits = const [];
      return;
    }
    PublicInventoryService inventory;
    try {
      inventory = context.read<PublicInventoryService>();
    } catch (_) {
      inventory = PublicInventoryService();
    }
    try {
      final client = Supabase.instance.client;
      final answers = await Future.wait([
        for (final id in ids)
          client.rpc(
            'get_public_product_fits_v1',
            params: {'p_tenant_id': tenantId, 'p_product_id': id, 'p_limit': 6},
          ),
      ]);
      // In the order they fit, each line's own first, as the HTML cart.
      final order = <String>[];
      var kind = '';
      for (final answer in answers) {
        final rows = [
          for (final row in (answer as List? ?? const []).whereType<Map>()) row,
        ]..sort(
            (a, b) => ((a['fit_position'] as num?) ?? 0)
                .compareTo((b['fit_position'] as num?) ?? 0),
          );
        for (final row in rows) {
          final id = '${row['product_id'] ?? ''}';
          final rowKind = '${row['kind'] ?? ''}';
          // One kind under one title: the first line with fits sets it.
          if (kind.isNotEmpty && rowKind != kind) continue;
          if (id.isEmpty || ids.contains(id) || order.contains(id)) continue;
          order.add(id);
          kind = rowKind;
        }
      }
      final fits = order.isEmpty
          ? const <Product>[]
          : ((await inventory.getProductPageForTenant(
              tenantId: tenantId,
              productIds: order,
              onlyInStock: true,
              limit: order.length,
            ))
              .products
              .where(
                (fit) =>
                    fit.price > 0 &&
                    (!fit.tracksInventory || fit.availableStockQuantity > 0),
              )
              .toList()
            ..sort(
              (a, b) => order.indexOf(a.id).compareTo(order.indexOf(b.id)),
            ));
      if (!mounted || token != _token) return;
      setState(() {
        _fits = fits;
        _kind = kind;
      });
    } catch (error) {
      debugPrint('[CartSuggestions] Fits failed: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Watching the cart calls didChangeDependencies on each change, which
    // asks again when its first lines change.
    final cart = context.watch<CartProvider>();
    final picks = [
      for (final fit in _fits)
        if (!cart.hasProduct(fit.id)) fit,
    ].take(CartSuggestionsCopy.limit).toList();
    if (picks.isEmpty) return const SizedBox.shrink();
    final store = PublicStoreSurfaceTheme.of(context);
    final mobile = widget.isMobile;
    return Semantics(
      container: true,
      label: CartSuggestionsCopy.title(_kind),
      child: Container(
        width: double.infinity,
        margin: EdgeInsets.only(top: mobile ? 28 : 36),
        padding: mobile
            ? const EdgeInsets.fromLTRB(16, 22, 16, 22)
            : const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: store.photoTile,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              CartSuggestionsCopy.eyebrow.toUpperCase(),
              style: store.text.labelSmall?.copyWith(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.4,
                color: store.primary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              CartSuggestionsCopy.title(_kind),
              style: store.text.headlineSmall?.copyWith(
                fontSize: mobile ? 21 : 24,
                fontWeight: FontWeight.w600,
                height: 1.25,
                color: store.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: Text(
                CartSuggestionsCopy.note(_kind),
                style: store.text.bodyMedium?.copyWith(
                  fontSize: 14,
                  height: 1.55,
                  color: store.textSecondary,
                ),
              ),
            ),
            const SizedBox(height: 20),
            if (mobile)
              SizedBox(
                height: 112,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: picks.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (context, index) => SizedBox(
                    width: 280,
                    child: _SuggestionCard(product: picks[index]),
                  ),
                ),
              )
            else
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns = (constraints.maxWidth / 262).floor().clamp(
                        1,
                        4,
                      );
                  final width =
                      (constraints.maxWidth - 12 * (columns - 1)) / columns;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final pick in picks)
                        SizedBox(
                          width: width,
                          child: _SuggestionCard(product: pick),
                        ),
                    ],
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _SuggestionCard extends StatelessWidget {
  const _SuggestionCard({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    final store = PublicStoreSurfaceTheme.of(context);
    final commerce = PublicCommerceProductProjection.fromProduct(product);
    final image = commerce.imageUrls.isEmpty ? null : commerce.imageUrls.first;
    void open() =>
        PublicStoreLayout.navigateToHref(context, publicProductPath(product));
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: store.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        children: [
          ExcludeSemantics(
            child: GestureDetector(
              onTap: open,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: 88,
                  height: 88,
                  color: store.photoTile,
                  padding: const EdgeInsets.all(8),
                  child: image == null
                      ? Icon(Icons.pedal_bike_outlined, color: store.textMuted)
                      : ColorFiltered(
                          colorFilter: ColorFilter.mode(
                            store.photoTile,
                            BlendMode.multiply,
                          ),
                          child: Image.network(
                            image,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => Icon(
                              Icons.pedal_bike_outlined,
                              color: store.textMuted,
                            ),
                          ),
                        ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (commerce.brand.isNotEmpty)
                  Text(
                    commerce.brand.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: store.text.labelSmall?.copyWith(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.9,
                      color: store.textSecondary,
                    ),
                  ),
                InkWell(
                  onTap: open,
                  child: Text(
                    commerce.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: store.text.bodyMedium?.copyWith(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      height: 1.35,
                      color: store.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        ChileanUtils.formatCurrency(commerce.price),
                        style: store.text.bodyMedium?.copyWith(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: store.textPrimary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: () => context
                          .read<CartProvider>()
                          .addProduct(product, quantity: 1),
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text(CartSuggestionsCopy.add),
                      style: FilledButton.styleFrom(
                        backgroundColor: store.primary,
                        foregroundColor: store.onPrimary,
                        minimumSize: const Size(0, 36),
                        padding: const EdgeInsets.fromLTRB(10, 0, 14, 0),
                        textStyle: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                        shape: const StadiumBorder(),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
