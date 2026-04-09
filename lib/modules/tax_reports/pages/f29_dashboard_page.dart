import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../shared/widgets/branded_loading.dart';
import '../../../shared/widgets/main_layout.dart';
import '../services/f29_service.dart';
import '../models/f29_declaration.dart';
import 'f29_detail_page.dart';

class F29DashboardPage extends StatefulWidget {
  const F29DashboardPage({super.key});

  @override
  State<F29DashboardPage> createState() => _F29DashboardPageState();
}

class _F29DashboardPageState extends State<F29DashboardPage> {
  final _currencyFormat = NumberFormat.currency(locale: 'es_CL', symbol: '\$');
  int? _selectedYear;
  int? _selectedMonth;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedYear = now.year;
    _selectedMonth = now.month;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<F29Service>().loadDeclarations();
    });
  }

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      title: 'Declaraciones F29',
      child: Column(
        children: [
          // Action bar
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              border: Border(
                bottom: BorderSide(
                  color: Theme.of(context).dividerColor,
                  width: 1,
                ),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.refresh),
                  label: const Text('Actualizar'),
                  onPressed: () =>
                      context.read<F29Service>().loadDeclarations(),
                ),
              ],
            ),
          ),
          // Content
          Expanded(
            child: Consumer<F29Service>(
              builder: (context, service, child) {
                if (service.isLoading) {
                  return const Center(child: BrandedLoading());
                }

                if (service.error != null) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline,
                            size: 64, color: Colors.red),
                        const SizedBox(height: 16),
                        Text('Error: ${service.error}'),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () => service.loadDeclarations(),
                          child: const Text('Reintentar'),
                        ),
                      ],
                    ),
                  );
                }

                return SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSummaryCards(service),
                      const SizedBox(height: 24),
                      _buildGenerateSection(service),
                      const SizedBox(height: 24),
                      _buildDeclarationsList(service),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCards(F29Service service) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 900) {
          // Mobile/Tablet: Stack vertically
          return Column(
            children: [
              _buildSummaryCard(
                'Declaraciones Pendientes',
                service.pendingDeclarations.length.toString(),
                Icons.pending_actions,
                Colors.orange,
              ),
              const SizedBox(height: 8),
              _buildSummaryCard(
                'Deuda Total',
                _currencyFormat.format(service.totalDebt),
                Icons.account_balance_wallet,
                Colors.red,
              ),
              const SizedBox(height: 8),
              _buildSummaryCard(
                'Crédito IVA',
                _currencyFormat.format(service.totalCredits),
                Icons.savings,
                Colors.green,
              ),
              const SizedBox(height: 8),
              _buildSummaryCard(
                'Atrasadas',
                service.overdueDeclarations.length.toString(),
                Icons.warning,
                Colors.red,
              ),
            ],
          );
        }

        // Desktop: Row
        return Row(
          children: [
            Expanded(
              child: _buildSummaryCard(
                'Declaraciones Pendientes',
                service.pendingDeclarations.length.toString(),
                Icons.pending_actions,
                Colors.orange,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildSummaryCard(
                'Deuda Total',
                _currencyFormat.format(service.totalDebt),
                Icons.account_balance_wallet,
                Colors.red,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildSummaryCard(
                'Crédito IVA',
                _currencyFormat.format(service.totalCredits),
                Icons.savings,
                Colors.green,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildSummaryCard(
                'Atrasadas',
                service.overdueDeclarations.length.toString(),
                Icons.warning,
                Colors.red,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSummaryCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 24),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGenerateSection(F29Service service) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Generar Nueva Declaración',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            const Text(
              'Selecciona el período para generar automáticamente el F29 desde los datos contables.',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < 600) {
                  // Mobile
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      DropdownButtonFormField<int>(
                        initialValue: _selectedMonth,
                        decoration: const InputDecoration(
                          labelText: 'Mes',
                          border: OutlineInputBorder(),
                        ),
                        items: List.generate(12, (index) {
                          final month = index + 1;
                          final monthName = DateFormat.MMMM('es').format(
                            DateTime(2000, month),
                          );
                          return DropdownMenuItem(
                            value: month,
                            child: Text(monthName),
                          );
                        }),
                        onChanged: (value) =>
                            setState(() => _selectedMonth = value),
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<int>(
                        initialValue: _selectedYear,
                        decoration: const InputDecoration(
                          labelText: 'Año',
                          border: OutlineInputBorder(),
                        ),
                        items: List.generate(5, (index) {
                          final year = DateTime.now().year - index;
                          return DropdownMenuItem(
                            value: year,
                            child: Text(year.toString()),
                          );
                        }),
                        onChanged: (value) =>
                            setState(() => _selectedYear = value),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: service.isLoading
                            ? null
                            : () => _generateF29(service),
                        icon: const Icon(Icons.auto_awesome),
                        label: const Text('Generar F29'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            vertical: 16,
                          ),
                        ),
                      ),
                    ],
                  );
                }

                // Desktop
                return Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: _selectedMonth,
                        decoration: const InputDecoration(
                          labelText: 'Mes',
                          border: OutlineInputBorder(),
                        ),
                        items: List.generate(12, (index) {
                          final month = index + 1;
                          final monthName = DateFormat.MMMM('es').format(
                            DateTime(2000, month),
                          );
                          return DropdownMenuItem(
                            value: month,
                            child: Text(monthName),
                          );
                        }),
                        onChanged: (value) =>
                            setState(() => _selectedMonth = value),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: _selectedYear,
                        decoration: const InputDecoration(
                          labelText: 'Año',
                          border: OutlineInputBorder(),
                        ),
                        items: List.generate(5, (index) {
                          final year = DateTime.now().year - index;
                          return DropdownMenuItem(
                            value: year,
                            child: Text(year.toString()),
                          );
                        }),
                        onChanged: (value) =>
                            setState(() => _selectedYear = value),
                      ),
                    ),
                    const SizedBox(width: 16),
                    ElevatedButton.icon(
                      onPressed: service.isLoading
                          ? null
                          : () => _generateF29(service),
                      icon: const Icon(Icons.auto_awesome),
                      label: const Text('Generar F29'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 16,
                        ),
                      ),
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

  Future<void> _generateF29(F29Service service) async {
    if (_selectedYear == null || _selectedMonth == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona mes y año')),
      );
      return;
    }

    // Check if F29 already exists
    final existing = await service.getDeclarationForPeriod(
      _selectedYear!,
      _selectedMonth!,
    );

    if (existing != null && !existing.isDraft) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('F29 ya existe'),
          content: Text(
            'Ya existe un F29 para ${existing.monthName} ${existing.periodYear} con estado: ${existing.statusDisplay}\n\n'
            '¿Deseas regenerarlo? Los datos anteriores se sobrescribirán.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Regenerar'),
            ),
          ],
        ),
      );

      if (confirm != true) return;
    }

    final f29 = await service.generateFromAccounting(
      _selectedYear!,
      _selectedMonth!,
    );

    if (!mounted) return;

    if (f29 != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'F29 generado: ${f29.monthName} ${f29.periodYear}\n'
            'Total a pagar: ${_currencyFormat.format(f29.totalAPagar)}',
          ),
          backgroundColor: Colors.green,
        ),
      );

      // Navigate to detail page
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => F29DetailPage(f29: f29),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error al generar F29'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildDeclarationsList(F29Service service) {
    if (service.declarations.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Center(
            child: Column(
              children: [
                Icon(Icons.description_outlined,
                    size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  'No hay declaraciones F29',
                  style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                ),
                const SizedBox(height: 8),
                Text(
                  'Genera tu primera declaración seleccionando el período arriba.',
                  style: TextStyle(color: Colors.grey[500]),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Historial de Declaraciones',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          const Divider(height: 1),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: service.declarations.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final f29 = service.declarations[index];
              return _buildDeclarationTile(f29);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDeclarationTile(F29Declaration f29) {
    Color statusColor;
    IconData statusIcon;

    switch (f29.status) {
      case 'draft':
        statusColor = Colors.orange;
        statusIcon = Icons.edit;
        break;
      case 'submitted':
        statusColor = Colors.blue;
        statusIcon = Icons.check_circle;
        break;
      case 'paid':
        statusColor = Colors.green;
        statusIcon = Icons.check_circle_outline;
        break;
      default:
        statusColor = Colors.grey;
        statusIcon = Icons.help_outline;
    }

    return ListTile(
      leading: Icon(statusIcon, color: statusColor, size: 32),
      title: Text(
        '${f29.monthName} ${f29.periodYear}',
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Estado: ${f29.statusDisplay}'),
          if (f29.hasDebt)
            Text(
              'Total a pagar: ${_currencyFormat.format(f29.totalAPagar)}',
              style: const TextStyle(color: Colors.red),
            ),
          if (f29.hasCredit)
            Text(
              'Crédito a favor: ${_currencyFormat.format(f29.totalAFavor)}',
              style: const TextStyle(color: Colors.green),
            ),
          if (f29.dueDate != null)
            Text(
              'Vencimiento: ${DateFormat('dd/MM/yyyy').format(f29.dueDate!)}',
              style: TextStyle(
                color: f29.dueDate!.isBefore(DateTime.now()) && !f29.isPaid
                    ? Colors.red
                    : Colors.grey,
              ),
            ),
        ],
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () {
        // Navigate to detail page
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => F29DetailPage(f29: f29),
          ),
        );
      },
    );
  }
}
