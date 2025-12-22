import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../bikeshop/models/bikeshop_models.dart';
import '../../../bikeshop/services/bikeshop_service.dart';

class JobPreviewDialog extends StatelessWidget {
  final String jobNumber;

  const JobPreviewDialog({super.key, required this.jobNumber});

  @override
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<MechanicJob>>(
      future: context.read<BikeshopService>().getJobs(searchTerm: jobNumber),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const AlertDialog(content: LinearProgressIndicator());
        }

        final job = snapshot.data?.firstOrNull;

        if (job == null) {
          return AlertDialog(
            title: const Text('Job no encontrado'),
            content: Text('No se encontró el Job #$jobNumber'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cerrar'),
              ),
            ],
          );
        }

        return AlertDialog(
          title: Text('Job #${job.jobNumber ?? "..."}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildRow('Status:', job.status.displayName),
              _buildRow('Prioridad:', job.priority.displayName),
              _buildRow('Total:', '\$${job.totalCost.toStringAsFixed(0)}'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cerrar'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(context); // Close dialog
                // TODO: Navigate to job detail
                // context.push('/bikeshop/jobs/${job.id}');
              },
              child: const Text('Ver Detalles'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          Text(value),
        ],
      ),
    );
  }
}
