import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/widgets/main_layout.dart';
import '../../../shared/widgets/search_widget.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/responsive_data_view.dart';
import '../../../shared/themes/app_theme.dart';
import '../../../shared/services/database_service.dart';
import '../../../shared/services/image_service.dart';
import '../../../shared/utils/chilean_utils.dart';
import '../models/crm_models.dart';
import '../services/customer_service.dart';

class CustomerListPage extends StatefulWidget {
  const CustomerListPage({super.key});

  @override
  State<CustomerListPage> createState() => _CustomerListPageState();
}

class _CustomerListPageState extends State<CustomerListPage> {
  late CustomerService _customerService;
  List<Customer> _customers = [];
  List<Customer> _filteredCustomers = [];
  bool _isLoading = true;
  String _searchTerm = '';

  @override
  void initState() {
    super.initState();
    _customerService = CustomerService(
      Provider.of<DatabaseService>(context, listen: false),
    );
    _loadCustomers();
  }

  Future<void> _loadCustomers() async {
    setState(() => _isLoading = true);
    try {
      final customers = await _customerService.getCustomers();
      setState(() {
        _customers = customers;
        _filteredCustomers = customers;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error cargando clientes: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _onSearchChanged(String searchTerm) {
    setState(() {
      _searchTerm = searchTerm;
      if (searchTerm.isEmpty) {
        _filteredCustomers = _customers;
      } else {
        _filteredCustomers = _customers
            .where((customer) =>
                customer.name.toLowerCase().contains(searchTerm.toLowerCase()) ||
                customer.rut.toLowerCase().contains(searchTerm.toLowerCase()) ||
                (customer.email?.toLowerCase().contains(searchTerm.toLowerCase()) ?? false))
            .toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = AppTheme.isMobile(context);
    final theme = Theme.of(context);
    
    return MainLayout(
      title: 'Clientes',
      child: Column(
        children: [
          // Header
          Padding(
            padding: EdgeInsets.all(isMobile ? 12.0 : 16.0),
            child: isMobile
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Clientes',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      AppButton(
                        text: 'Nuevo Cliente',
                        icon: Icons.person_add,
                        fullWidth: true,
                        onPressed: () {
                          context.push('/crm/customers/new').then((_) {
                            _loadCustomers();
                          });
                        },
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Clientes',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      AppButton(
                        text: 'Nuevo Cliente',
                        icon: Icons.person_add,
                        onPressed: () {
                          context.push('/crm/customers/new').then((_) {
                            _loadCustomers();
                          });
                        },
                      ),
                    ],
                  ),
          ),
          
          // Search
          SearchWidget(
            hintText: 'Buscar por nombre, RUT o email...',
            onSearchChanged: _onSearchChanged,
          ),
          
          // Stats
          if (!_isLoading && _customers.isNotEmpty)
            Container(
              margin: EdgeInsets.symmetric(
                horizontal: isMobile ? 12 : 16,
                vertical: 8,
              ),
              padding: EdgeInsets.all(isMobile ? 12 : 16),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withOpacity(0.3),
                borderRadius: BorderRadius.circular(12),
              ),
              child: isMobile
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildStatItem(theme, 'Total', _customers.length.toString(), true),
                        _buildStatItem(
                          theme,
                          'Activos', 
                          _customers.where((c) => c.isActive).length.toString(),
                          true,
                        ),
                        _buildStatItem(
                          theme,
                          'Mostrando', 
                          _filteredCustomers.length.toString(),
                          true,
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        _buildStatItem(theme, 'Total', _customers.length.toString(), false),
                        const SizedBox(width: 24),
                        _buildStatItem(
                          theme,
                          'Activos', 
                          _customers.where((c) => c.isActive).length.toString(),
                          false,
                        ),
                        const SizedBox(width: 24),
                        _buildStatItem(
                          theme,
                          'Mostrando', 
                          _filteredCustomers.length.toString(),
                          false,
                        ),
                      ],
                    ),
            ),
          const SizedBox(height: 8),
          
          // Content
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _buildCustomersList(isMobile),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(ThemeData theme, String label, String value, bool isCompact) {
    return Column(
      children: [
        Text(
          value,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.primary,
            fontSize: isCompact ? 18 : 20,
          ),
        ),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontSize: isCompact ? 11 : 12,
          ),
        ),
      ],
    );
  }

  Widget _buildCustomersList(bool isMobile) {
    if (_filteredCustomers.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.people_outline,
              size: 80,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              _searchTerm.isEmpty 
                  ? 'No hay clientes registrados'
                  : 'No se encontraron clientes',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
            ),
            if (_searchTerm.isEmpty) ...[
              const SizedBox(height: 16),
              AppButton(
                text: 'Agregar Primer Cliente',
                fullWidth: isMobile,
                onPressed: () {
                  context.push('/crm/customers/new').then((_) {
                    _loadCustomers();
                  });
                },
              ),
            ],
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadCustomers,
      child: ListView.builder(
        padding: EdgeInsets.all(isMobile ? 12.0 : 16.0),
        itemCount: _filteredCustomers.length,
        itemBuilder: (context, index) {
          final customer = _filteredCustomers[index];
          return _buildCustomerCard(customer, isMobile);
        },
      ),
    );
  }

  Widget _buildCustomerCard(Customer customer, bool isMobile) {
    final theme = Theme.of(context);
    
    return Card(
      margin: EdgeInsets.only(bottom: isMobile ? 10 : 16),
      child: InkWell(
        onTap: () {
          context.push('/crm/customers/${customer.id}').then((_) {
            _loadCustomers();
          });
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: EdgeInsets.all(isMobile ? 12.0 : 16.0),
          child: Row(
            children: [
              // Avatar
              ImageService.buildAvatarImage(
                imageUrl: customer.imageUrl,
                radius: isMobile ? 28 : 30,
                initials: customer.initials,
              ),
              SizedBox(width: isMobile ? 12 : 16),
              
              // Customer info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            customer.name,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              fontSize: isMobile ? 15 : 16,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (!customer.isActive)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.errorContainer,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              'Inactivo',
                              style: TextStyle(
                                color: theme.colorScheme.error,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.badge_outlined,
                          size: 14,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          ChileanUtils.formatRut(customer.rut),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    if (customer.email != null && !isMobile) ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(
                            Icons.email_outlined,
                            size: 14,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              customer.email!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (customer.phone != null) ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(
                            Icons.phone_outlined,
                            size: 14,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            customer.phone!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              
              // Arrow icon
              Icon(
                Icons.chevron_right,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}