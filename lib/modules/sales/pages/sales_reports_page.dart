import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../shared/widgets/main_layout.dart';

class SalesReportsPage extends StatelessWidget {
  const SalesReportsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      title: 'Informes de Ventas',
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Informes disponibles',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 24),
            Expanded(
              child: GridView.count(
                crossAxisCount: 3,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 1.5,
                children: [
                  _ReportCard(
                    title: 'Ventas por artículo',
                    description:
                        'Detalle de ventas agrupado por productos y servicios.',
                    icon: Icons.inventory_2_outlined,
                    onTap: () => context.push('/sales/reports/by-product'),
                  ),
                  _ReportCard(
                    title: 'Ventas por cliente',
                    description: 'Resumen de ventas por cliente.',
                    icon: Icons.people_outline,
                    onTap: () => context.push('/sales/reports/by-customer'),
                  ),
                  _ReportCard(
                    title: 'Ventas por vendedor',
                    description: 'Rendimiento de ventas por usuario.',
                    icon: Icons.badge_outlined,
                    onTap: () {
                      // TODO: Implement Sales by Salesperson
                    },
                    isComingSoon: true,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  final String title;
  final String description;
  final IconData icon;
  final VoidCallback onTap;
  final bool isComingSoon;

  const _ReportCard({
    required this.title,
    required this.description,
    required this.icon,
    required this.onTap,
    this.isComingSoon = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: isComingSoon ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 32, color: theme.colorScheme.primary),
                  const Spacer(),
                  if (isComingSoon)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceVariant,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'Próximamente',
                        style: theme.textTheme.labelSmall,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Text(
                  description,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
