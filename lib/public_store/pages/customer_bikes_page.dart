import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/customer_portal_presentation.dart';
import '../services/customer_account_service.dart';
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
      child: CustomerBikesBody(
        bikes: accountService.bikes,
        isLoading: accountService.isLoading && accountService.bikes.isEmpty,
        onOpenBike: (bike) => _showBike(context, bike, navigate),
        onNavigate: navigate,
      ),
    );
  }

  void _showBike(
    BuildContext context,
    Map<String, dynamic> bike,
    ValueChanged<String> navigate,
  ) {
    final warranty = portalParseDate(bike['warranty_until']);
    final purchased = portalParseDate(bike['purchase_date']);
    final count = (bike['service_count'] as num?)?.toInt() ?? 0;
    String? text(String key) {
      final value = (bike[key] ?? '').toString().trim();
      return value.isEmpty ? null : value;
    }

    final warrantyActive = warranty != null &&
        !warranty.isBefore(DateUtils.dateOnly(DateTime.now()));

    showPortalDetail(
      context,
      title: CustomerWorkshopPresentation.bikeTitle(bike),
      subtitle:
          customerBikeDetails(bike).isEmpty ? null : customerBikeDetails(bike),
      status: warranty == null
          ? null
          : PortalStatusPill(
              label: warrantyActive
                  ? 'Garantía hasta el ${portalDate(warranty)}'
                  : 'Garantía vencida el ${portalDate(warranty)}',
              tone: warrantyActive ? PortalTone.success : PortalTone.neutral,
            ),
      body: PortalFacts(
        facts: [
          ('Taller', customerBikeServiceSummary(bike)),
          ('Talla de cuadro', text('frame_size')),
          ('Número de serie', text('serial_number')),
          ('Comprada', purchased == null ? null : portalDate(purchased)),
          ('Notas', text('notes')),
        ],
      ),
      actions: [
        if (count > 0)
          Builder(
            builder: (buttonContext) => FilledButton(
              style: portalPrimaryButton(buttonContext),
              onPressed: () {
                Navigator.of(buttonContext).pop();
                navigate('/cuenta/servicios?bike_id=${bike['id']}');
              },
              child: const Text('Ver sus trabajos de taller'),
            ),
          ),
      ],
    );
  }
}

/// La lista de bicis, sin el marco ni el servicio.
///
/// No muestra el tipo de bici: el ERP lo trae marcado en `mountain_hardtail`
/// y casi todas quedaron así (ver [customerBikeDetails]).
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
        final compact = constraints.maxWidth < 560;
        final style = PortalStyle.of(context);
        return PortalPanel(
          children: [
            for (final bike in bikes)
              _BikeRow(
                bike: bike,
                compact: compact,
                style: style,
                onTap: () => onOpenBike(bike),
              ),
          ],
        );
      },
    );
  }
}

class _BikeRow extends StatelessWidget {
  const _BikeRow({
    required this.bike,
    required this.compact,
    required this.style,
    required this.onTap,
  });

  final Map<String, dynamic> bike;
  final bool compact;
  final PortalStyle style;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final details = customerBikeDetails(bike);
    final services = customerBikeServiceSummary(bike);
    return PortalRow(
      leading: PortalThumb(
        fallbackIcon: Icons.pedal_bike_outlined,
        imageUrl: customerBikeImage(bike),
      ),
      title: CustomerWorkshopPresentation.bikeTitle(bike),
      meta: compact
          ? [if (details.isNotEmpty) details, services].join(' · ')
          : (details.isEmpty ? null : details),
      trailing: compact
          ? null
          : ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 240),
              child: Text(
                services,
                textAlign: TextAlign.right,
                style: style.rowMeta,
              ),
            ),
      onTap: onTap,
    );
  }
}
