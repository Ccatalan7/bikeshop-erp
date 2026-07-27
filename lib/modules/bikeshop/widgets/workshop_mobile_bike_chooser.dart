import 'package:flutter/material.dart';

import '../models/bikeshop_models.dart';

class WorkshopMobileBikeChooser extends StatelessWidget {
  const WorkshopMobileBikeChooser({
    super.key,
    required this.jobLabel,
    required this.linkedBikeCount,
    required this.bikes,
    required this.onSelected,
    required this.onClose,
  });

  final String jobLabel;
  final int linkedBikeCount;
  final List<Bike> bikes;
  final ValueChanged<Bike> onSelected;
  final VoidCallback onClose;

  String _bikeSubtitle(Bike bike, int index) {
    final details = <String>['Bicicleta ${index + 1}'];
    final serialNumber = bike.serialNumber?.trim();
    final color = bike.color?.trim();
    if (serialNumber != null && serialNumber.isNotEmpty) {
      details.add('Serie $serialNumber');
    }
    if (color != null && color.isNotEmpty) {
      details.add(color);
    }
    return details.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: theme.colorScheme.surface,
      child: ConstrainedBox(
        key: const ValueKey('workshop-mobile-bike-chooser'),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.78,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 8, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Seleccionar bicicleta',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '$jobLabel tiene $linkedBikeCount bicicletas vinculadas. Elige la ficha que quieres abrir.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Semantics(
                    button: true,
                    excludeSemantics: true,
                    label: 'Cerrar selector de bicicletas',
                    child: SizedBox(
                      width: 48,
                      height: 48,
                      child: IconButton(
                        key: const ValueKey(
                          'workshop-mobile-bike-chooser-close',
                        ),
                        tooltip: 'Cerrar selector de bicicletas',
                        onPressed: onClose,
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Divider(
              height: 1,
              color: theme.colorScheme.outlineVariant,
            ),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: bikes.length,
                separatorBuilder: (context, index) => Divider(
                  height: 1,
                  indent: 20,
                  color:
                      theme.colorScheme.outlineVariant.withValues(alpha: 0.55),
                ),
                itemBuilder: (context, index) {
                  final bike = bikes[index];
                  final bikeId = bike.id ?? 'index-$index';
                  final subtitle = _bikeSubtitle(bike, index);
                  return Semantics(
                    button: true,
                    excludeSemantics: true,
                    label: 'Abrir bicicleta ${bike.displayName}, $subtitle',
                    child: ListTile(
                      key: ValueKey('workshop-mobile-bike-choice-$bikeId'),
                      minTileHeight: 56,
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 20),
                      title: Text(
                        bike.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing:
                          const Icon(Icons.chevron_right_rounded, size: 20),
                      onTap: () => onSelected(bike),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
