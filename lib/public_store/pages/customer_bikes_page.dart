import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/customer_account_service.dart';
import '../widgets/customer_bike_card.dart';
import '../widgets/customer_portal_layout.dart';
import '../widgets/customer_portal_style.dart';
import '../widgets/public_store_layout.dart';

/// «Bicicletas» (`/cuenta/bicicletas`): las bicis que el taller registró a
/// nombre del cliente, con cuántas veces pasaron por el taller.
class CustomerBikesPage extends StatefulWidget {
  const CustomerBikesPage({super.key});

  @override
  State<CustomerBikesPage> createState() => _CustomerBikesPageState();
}

class _CustomerBikesPageState extends State<CustomerBikesPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CustomerAccountService>().loadBikes();
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final accountService = context.watch<CustomerAccountService>();
    void navigate(String href) =>
        PublicStoreLayout.navigateToHref(context, href);

    return CustomerPortalLayout(
      title: 'Bicicletas',
      subtitle: 'Las bicis que el taller registró a tu nombre.',
      child: CustomerBikesBody(
        bikes: accountService.bikes,
        isLoading: accountService.isLoading && accountService.bikes.isEmpty,
        onOpenBike: (bike) => showCustomerBikeDetail(
          context,
          bike: bike,
          onNavigate: navigate,
        ),
        onNavigate: navigate,
      ),
    );
  }
}

/// Las bicis en una grilla de tarjetas, sin el marco ni el servicio.
class CustomerBikesBody extends StatelessWidget {
  const CustomerBikesBody({
    super.key,
    required this.bikes,
    required this.onOpenBike,
    required this.onNavigate,
    this.isLoading = false,
  });

  final List<Map<String, dynamic>> bikes;
  final bool isLoading;
  final ValueChanged<Map<String, dynamic>> onOpenBike;
  final ValueChanged<String> onNavigate;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (bikes.isEmpty) {
      return PortalEmptyState(
        title: 'Todavía no hay bicicletas en tu cuenta.',
        message: 'El taller registra tu bici la primera vez que la traes, y '
            'desde ahí vas a ver aquí cada servicio que le hagamos.',
        actions: [
          PortalLink(
            label: 'Ver servicios y precios',
            onTap: () => onNavigate('/servicios'),
          ),
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 860
            ? 3
            : width >= PortalStyle.compactBreakpoint
                ? 2
                : 1;
        const gap = 32.0;
        final cardWidth = (width - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: 40,
          children: [
            for (final bike in bikes)
              SizedBox(
                width: cardWidth,
                child: CustomerBikeCard(
                  bike: bike,
                  compact: columns == 1,
                  onTap: () => onOpenBike(bike),
                ),
              ),
          ],
        );
      },
    );
  }
}
