import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/customer_portal_presentation.dart';
import '../services/customer_account_service.dart';
import '../widgets/customer_job_row.dart';
import '../widgets/customer_portal_layout.dart';
import '../widgets/customer_portal_style.dart';
import '../widgets/public_store_layout.dart';

/// «Taller» (`/cuenta/servicios`): los trabajos del cliente, lo que está en
/// el taller arriba y el historial abajo. `?bike_id=` llega desde una bici.
class CustomerServiceHistoryPage extends StatefulWidget {
  final String? bikeId;

  const CustomerServiceHistoryPage({super.key, this.bikeId});

  @override
  State<CustomerServiceHistoryPage> createState() =>
      _CustomerServiceHistoryPageState();
}

class _CustomerServiceHistoryPageState extends State<CustomerServiceHistoryPage>
    with AutomaticKeepAliveClientMixin {
  String? _selectedBikeId;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _selectedBikeId = widget.bikeId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CustomerAccountService>().loadServiceHistory();
    });
  }

  @override
  void didUpdateWidget(CustomerServiceHistoryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bikeId != widget.bikeId) {
      _selectedBikeId = widget.bikeId;
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final accountService = context.watch<CustomerAccountService>();
    void navigate(String href) =>
        PublicStoreLayout.navigateToHref(context, href);

    return CustomerPortalLayout(
      title: 'Taller',
      subtitle: 'Tus bicis en el taller y lo que les hicimos.',
      headerAction: PortalButton(
        label: 'Hablar con el taller',
        kind: PortalButtonKind.onPhoto,
        arrow: true,
        onPressed: () => navigate('/cuenta/chats'),
      ),
      child: CustomerServiceHistoryBody(
        jobs: accountService.serviceHistory,
        isLoading:
            accountService.isLoading && accountService.serviceHistory.isEmpty,
        selectedBikeId: _selectedBikeId,
        onBikeChanged: (bikeId) => setState(() => _selectedBikeId = bikeId),
        onOpenJob: (job) => showCustomerJobDetail(
          context,
          job: job,
          onNavigate: navigate,
        ),
        onNavigate: navigate,
      ),
    );
  }
}

/// La lista de trabajos, sin el marco ni el servicio.
///
/// El filtro es por bici, y sólo aparece si hay más de una: el estado ya
/// separa lo que está en el taller del historial, y los códigos del taller
/// (`ESPERANDO_REPUESTOS`…) nunca llegan al cliente.
class CustomerServiceHistoryBody extends StatelessWidget {
  const CustomerServiceHistoryBody({
    super.key,
    required this.jobs,
    required this.selectedBikeId,
    required this.onBikeChanged,
    required this.onOpenJob,
    required this.onNavigate,
    this.isLoading = false,
  });

  final List<Map<String, dynamic>> jobs;
  final bool isLoading;
  final String? selectedBikeId;
  final ValueChanged<String?> onBikeChanged;
  final ValueChanged<Map<String, dynamic>> onOpenJob;
  final ValueChanged<String> onNavigate;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (jobs.isEmpty) {
      return PortalEmptyState(
        title: 'Todavía no tienes trabajos de taller.',
        message: 'Cuando dejes tu bici con nosotros vas a ver aquí en qué va, '
            'el presupuesto y cuándo está lista.',
        actions: [
          PortalLink(
            label: 'Ver servicios y precios',
            onTap: () => onNavigate('/servicios'),
          ),
          PortalLink(
            label: 'Hablar con el taller',
            onTap: () => onNavigate('/cuenta/chats'),
          ),
        ],
      );
    }

    // Las bicis salen de los trabajos: así el filtro sólo ofrece bicis con
    // algo que mostrar.
    final bikes = <String, String>{};
    final counts = <String, int>{};
    for (final job in jobs) {
      final id = job['bike_id']?.toString();
      if (id == null || id.isEmpty) continue;
      bikes.putIfAbsent(id, () => CustomerWorkshopPresentation.bikeTitle(job));
      counts[id] = (counts[id] ?? 0) + 1;
    }
    final filterId = selectedBikeId != null && selectedBikeId!.isNotEmpty
        ? selectedBikeId
        : null;
    final visible = filterId == null
        ? jobs
        : jobs
            .where((job) => job['bike_id']?.toString() == filterId)
            .toList(growable: false);
    final active = [
      for (final job in visible)
        if (CustomerWorkshopPresentation.of(job).isActive) job,
    ]..sort((a, b) {
        final needsA = CustomerWorkshopPresentation.of(a).needsCustomer;
        final needsB = CustomerWorkshopPresentation.of(b).needsCustomer;
        if (needsA != needsB) return needsA ? -1 : 1;
        return 0;
      });
    final historyJobs = [
      for (final job in visible)
        if (!CustomerWorkshopPresentation.of(job).isActive) job,
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final compact = width < PortalStyle.compactBreakpoint;
        final history = PortalPanel(
          header: width >= customerJobTableBreakpoint
              ? const CustomerJobTableHeader()
              : null,
          children: [
            for (final job in historyJobs)
              CustomerJobRow(
                job: job,
                showTotal: true,
                onTap: () => onOpenJob(job),
              ),
          ],
        );
        final tiles = [
          for (final job in active)
            (PortalTileLayout layout) => CustomerJobTile(
                  job: job,
                  compact: compact,
                  layout: layout,
                  onOpen: () => onOpenJob(job),
                  onNavigate: onNavigate,
                ),
        ];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (bikes.length > 1 || (filterId != null && bikes.isNotEmpty)) ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  PortalFilterChip(
                    label: 'Todas',
                    count: jobs.length,
                    selected: filterId == null,
                    onTap: () => onBikeChanged(null),
                  ),
                  for (final entry in bikes.entries)
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 260),
                      child: PortalFilterChip(
                        label: entry.value,
                        count: counts[entry.key],
                        selected: filterId == entry.key,
                        onTap: () => onBikeChanged(entry.key),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 40),
            ],
            if (visible.isEmpty)
              PortalEmptyState(
                title: 'Esta bicicleta no tiene trabajos registrados.',
                actions: [
                  PortalLink(
                    label: 'Ver todos los trabajos',
                    onTap: () => onBikeChanged(null),
                  ),
                ],
              ),
            if (active.isNotEmpty)
              PortalSection(
                label: 'En el taller',
                count: active
                    .where((job) =>
                        CustomerWorkshopPresentation.of(job).needsCustomer)
                    .length,
                child: PortalTileGrid(width: width, tiles: tiles),
              ),
            if (active.isNotEmpty && historyJobs.isNotEmpty)
              const SizedBox(height: 72),
            if (historyJobs.isNotEmpty)
              PortalSection(label: 'Historial', child: history),
          ],
        );
      },
    );
  }
}
