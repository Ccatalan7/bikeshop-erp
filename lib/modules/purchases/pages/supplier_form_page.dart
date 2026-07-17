import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../../../shared/models/supplier.dart';
import '../models/purchase_invoice.dart';
import '../../../shared/widgets/branded_loading.dart';
import '../../../shared/models/tax_treatment.dart';
import '../../../shared/utils/chilean_utils.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/main_layout.dart';
import '../../../shared/services/workspace_manager.dart';

import '../services/purchase_service.dart';

class SupplierFormPage extends StatefulWidget {
  final String? supplierId;

  const SupplierFormPage({super.key, this.supplierId});

  @override
  State<SupplierFormPage> createState() => _SupplierFormPageState();
}

class _SupplierFormPageState extends State<SupplierFormPage>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();

  // Controllers
  final _nameController = TextEditingController();
  final _legalNameController = TextEditingController();
  final _tradeNameController = TextEditingController();
  final _ownerNameController = TextEditingController();
  final _aliasesController = TextEditingController();
  final _rutController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _cityController = TextEditingController();
  final _regionController = TextEditingController();
  final _comunaController = TextEditingController();
  final _contactController = TextEditingController();
  final _websiteController = TextEditingController();
  final _notesController = TextEditingController();

  // New Controllers
  final _imageUrlController = TextEditingController();
  final _portalUsernameController = TextEditingController();
  final _portalPasswordController = TextEditingController();
  final _salesRepNameController = TextEditingController();
  final _salesRepPhoneController = TextEditingController();
  final _salesRepEmailController = TextEditingController();
  final _purchaseInstructionsController = TextEditingController();

  SupplierType _type = SupplierType.local;
  PaymentTerms _paymentTerms = PaymentTerms.net30;
  TaxTreatment _defaultTaxTreatment = TaxTreatment.taxIncluded;
  bool _isActive = true;
  bool _showPortalPassword = false;

  bool _isSaving = false;
  bool _isLoading = true;
  Supplier? _existing;
  List<PurchaseInvoice> _invoices = [];

  late PurchaseService _purchaseService;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _initialize());
  }

  @override
  void dispose() {
    _nameController.dispose();
    _legalNameController.dispose();
    _tradeNameController.dispose();
    _ownerNameController.dispose();
    _aliasesController.dispose();
    _rutController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _cityController.dispose();
    _regionController.dispose();
    _comunaController.dispose();
    _contactController.dispose();
    _websiteController.dispose();
    _notesController.dispose();
    _imageUrlController.dispose();
    _portalUsernameController.dispose();
    _portalPasswordController.dispose();
    _salesRepNameController.dispose();
    _salesRepPhoneController.dispose();
    _salesRepEmailController.dispose();
    _purchaseInstructionsController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  void _openWebsiteWorkspace() {
    final url = _websiteController.text.trim();
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Por favor ingrese un Sitio Web primero (ej: https://www.proveedor.com)')),
      );
      return;
    }

    final validUrl = url.startsWith('http') ? url : 'https://$url';
    final pageTitle = _nameController.text.isEmpty
        ? 'Portal B2B'
        : 'Portal: ${_nameController.text}';
    final route = Uri(
      path: '/tools/web',
      queryParameters: {
        'url': validUrl,
        'name': pageTitle,
      },
    ).toString();

    try {
      final workspaceManager = context.read<WorkspaceManager>();
      final existingFound =
          workspaceManager.switchToExistingWorkspaceWithRoute(route);
      if (!existingFound) {
        workspaceManager.addWorkspace(
          title: pageTitle,
          initialRoute: route,
        );
      }
    } catch (_) {
      context.go(route);
    }
  }

  void _closePage({bool saved = false}) {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final navigator = Navigator.of(context);
      if (navigator.canPop()) {
        navigator.pop(saved ? true : null);
      } else {
        context.go('/purchases/suppliers');
      }
    });
  }

  Future<void> _initialize() async {
    _purchaseService = context.read<PurchaseService>();
    if (widget.supplierId == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final supplier = await _purchaseService.getSupplier(widget.supplierId!);
      if (supplier != null) {
        _existing = supplier;
        _nameController.text = supplier.name;
        _legalNameController.text = supplier.legalName ?? '';
        _tradeNameController.text = supplier.tradeName ?? '';
        _ownerNameController.text = supplier.ownerName ?? '';
        _aliasesController.text = supplier.aliases.join(', ');
        _rutController.text = supplier.rut ?? '';
        _emailController.text = supplier.email ?? '';
        _phoneController.text = supplier.phone ?? '';
        _addressController.text = supplier.address ?? '';
        _cityController.text = supplier.city ?? '';
        _regionController.text = supplier.region ?? '';
        _comunaController.text = supplier.comuna ?? '';
        _contactController.text = supplier.contactPerson ?? '';
        _websiteController.text = supplier.website ?? '';
        _notesController.text = supplier.notes ?? '';
        _imageUrlController.text = supplier.imageUrl ?? '';
        _portalUsernameController.text = supplier.portalUsername ?? '';
        _portalPasswordController.text = supplier.portalPassword ?? '';
        _salesRepNameController.text = supplier.salesRepName ?? '';
        _salesRepPhoneController.text = supplier.salesRepPhone ?? '';
        _salesRepEmailController.text = supplier.salesRepEmail ?? '';
        _purchaseInstructionsController.text =
            supplier.purchaseInstructions ?? '';
        _type = supplier.type;
        _paymentTerms = supplier.paymentTerms;
        _defaultTaxTreatment = supplier.defaultTaxTreatment;
        _isActive = supplier.isActive;

        // Load invoices
        _invoices = await _purchaseService.getInvoicesBySupplier(supplier.id);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al cargar proveedor: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      // Switch to the edit tab if validation fails
      if (widget.supplierId != null) {
        _tabController.animateTo(0);
      }
      return;
    }

    final now = DateTime.now();
    final supplier = Supplier(
      id: _existing?.id ?? '',
      tenantId: _existing?.tenantId ?? '',
      name: _nameController.text.trim(),
      legalName: _emptyToNull(_legalNameController.text),
      tradeName: _emptyToNull(_tradeNameController.text),
      ownerName: _emptyToNull(_ownerNameController.text),
      aliases: _parseAliases(_aliasesController.text),
      email: _emailController.text.trim().isEmpty
          ? null
          : _emailController.text.trim(),
      phone: _phoneController.text.trim().isEmpty
          ? null
          : _phoneController.text.trim(),
      rut: _rutController.text.trim().isEmpty
          ? null
          : _rutController.text.trim(),
      address: _addressController.text.trim().isEmpty
          ? null
          : _addressController.text.trim(),
      city: _cityController.text.trim().isEmpty
          ? null
          : _cityController.text.trim(),
      region: _regionController.text.trim().isEmpty
          ? null
          : _regionController.text.trim(),
      comuna: _comunaController.text.trim().isEmpty
          ? null
          : _comunaController.text.trim(),
      type: _type,
      contactPerson: _contactController.text.trim().isEmpty
          ? null
          : _contactController.text.trim(),
      website: _websiteController.text.trim().isEmpty
          ? null
          : _websiteController.text.trim(),
      bankDetails: _existing?.bankDetails ?? const {},
      paymentTerms: _paymentTerms,
      defaultTaxTreatment: _defaultTaxTreatment,
      notes: _notesController.text.trim().isEmpty
          ? null
          : _notesController.text.trim(),
      imageUrl: _imageUrlController.text.trim().isEmpty
          ? null
          : _imageUrlController.text.trim(),
      portalUsername: _portalUsernameController.text.trim().isEmpty
          ? null
          : _portalUsernameController.text.trim(),
      portalPassword: _portalPasswordController.text.trim().isEmpty
          ? null
          : _portalPasswordController.text.trim(),
      salesRepName: _salesRepNameController.text.trim().isEmpty
          ? null
          : _salesRepNameController.text.trim(),
      salesRepPhone: _salesRepPhoneController.text.trim().isEmpty
          ? null
          : _salesRepPhoneController.text.trim(),
      salesRepEmail: _salesRepEmailController.text.trim().isEmpty
          ? null
          : _salesRepEmailController.text.trim(),
      purchaseInstructions: _purchaseInstructionsController.text.trim().isEmpty
          ? null
          : _purchaseInstructionsController.text.trim(),
      isActive: _isActive,
      createdAt: _existing?.createdAt ?? now,
      updatedAt: now,
    );

    setState(() => _isSaving = true);

    try {
      await _purchaseService.saveSupplier(supplier);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              _existing == null ? 'Proveedor creado' : 'Proveedor actualizado'),
          backgroundColor: Colors.green,
        ),
      );
      _closePage(saved: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('No se pudo guardar: $e'),
            backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text('$label copiado al portapapeles'),
          duration: const Duration(seconds: 2)),
    );
  }

  String? _emptyToNull(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  List<String> _parseAliases(String value) {
    final aliases = value
        .split(RegExp(r'[,;\n]+'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty);
    final seen = <String>{};
    return aliases.where((alias) {
      final key = alias.toLowerCase();
      if (seen.contains(key)) return false;
      seen.add(key);
      return true;
    }).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 900;

    return MainLayout(
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            _buildHeader(),
            if (_isLoading)
              const Expanded(child: Center(child: BrandedLoading()))
            else if (widget.supplierId == null)
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24.0),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 800),
                      child: Container(
                        padding: const EdgeInsets.all(32.0),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.04),
                              blurRadius: 24,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: _buildForm(isCreation: true),
                      ),
                    ),
                  ),
                ),
              )
            else
              Expanded(
                child: isDesktop
                    ? Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(width: 320, child: _buildProfilePanel()),
                            const SizedBox(width: 24),
                            Expanded(child: _buildRightPanel()),
                          ],
                        ),
                      )
                    : SingleChildScrollView(
                        child: Column(
                          children: [
                            _buildProfilePanel(),
                            SizedBox(
                              height: 800, // Fixed height for mobile tabs
                              child: _buildRightPanel(),
                            )
                          ],
                        ),
                      ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => _closePage(),
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Volver',
          ),
          const SizedBox(width: 8),
          Text(
            widget.supplierId != null
                ? 'Perfil de Proveedor'
                : 'Nuevo Proveedor',
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          AppButton(
            text: 'Guardar Cambios',
            icon: Icons.save,
            onPressed: _isSaving ? null : _save,
            isLoading: _isSaving,
          ),
        ],
      ),
    );
  }

  Widget _buildProfilePanel() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 24,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Stack(
                alignment: Alignment.bottomRight,
                children: [
                  CircleAvatar(
                    radius: 50,
                    backgroundColor: Colors.grey.shade100,
                    backgroundImage: _imageUrlController.text.isNotEmpty
                        ? NetworkImage(_imageUrlController.text)
                        : null,
                    child: _imageUrlController.text.isEmpty
                        ? Text(
                            _nameController.text.isNotEmpty
                                ? _nameController.text
                                    .substring(0, 1)
                                    .toUpperCase()
                                : '?',
                            style: TextStyle(
                                fontSize: 40, color: Colors.grey.shade400),
                          )
                        : null,
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      decoration: BoxDecoration(
                        color: _isActive ? Colors.green : Colors.red,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                      ),
                      width: 20,
                      height: 20,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: Text(
                _nameController.text.isNotEmpty
                    ? _nameController.text
                    : 'Sin Nombre',
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  _type.displayName,
                  style: TextStyle(
                    color: Theme.of(context).primaryColor,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),
            _buildInfoRow(Icons.badge_outlined, 'RUT', _rutController.text),
            _buildInfoRow(Icons.apartment_outlined, 'Razón social',
                _legalNameController.text),
            _buildInfoRow(Icons.storefront_outlined, 'Nombre comercial',
                _tradeNameController.text),
            _buildInfoRow(Icons.hub_outlined, 'Dueño / matriz',
                _ownerNameController.text),
            _buildInfoRow(
                Icons.label_outline, 'Alias OCR', _aliasesController.text),
            _buildInfoRow(Icons.email_outlined, 'Email', _emailController.text),
            _buildInfoRow(
                Icons.phone_outlined, 'Teléfono', _phoneController.text),
            _buildInfoRow(Icons.language, 'Sitio Web', _websiteController.text),
            _buildInfoRow(Icons.location_on_outlined, 'Dirección',
                _addressController.text),
            const SizedBox(height: 24),
            const Text(
              'Contacto Portal/Web',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey),
            ),
            const SizedBox(height: 12),
            _buildCredentialRow('Usuario:', _portalUsernameController.text),
            _buildCredentialRow(
              'Clave:',
              _portalPasswordController.text,
              isSecret: true,
            ),
            const SizedBox(height: 24),
            const Text(
              'Vendedor Asignado',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey),
            ),
            const SizedBox(height: 12),
            _buildInfoRow(
                Icons.person_outline, 'Nombre', _salesRepNameController.text),
            _buildInfoRow(Icons.phone_outlined, 'WhatsApp/Tel',
                _salesRepPhoneController.text),
            _buildInfoRow(
                Icons.email_outlined, 'Email', _salesRepEmailController.text),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Colors.grey.shade500),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style:
                        TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                const SizedBox(height: 2),
                Text(value, style: const TextStyle(fontSize: 14)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCredentialRow(
    String label,
    String value, {
    bool isSecret = false,
  }) {
    if (value.isEmpty) return const SizedBox.shrink();
    final displayValue = isSecret && !_showPortalPassword ? '••••••••' : value;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        children: [
          SizedBox(
            width: 70,
            child: Text(label,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
          ),
          Expanded(
            child: Text(
              displayValue,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (isSecret)
            IconButton(
              icon: Icon(
                _showPortalPassword
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                size: 16,
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              tooltip: _showPortalPassword
                  ? 'Ocultar contraseña'
                  : 'Mostrar contraseña',
              onPressed: () {
                setState(() => _showPortalPassword = !_showPortalPassword);
              },
            ),
          if (isSecret) const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.copy, size: 16),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () => _copyToClipboard(value, 'Credencial'),
            color: Colors.blue,
          ),
        ],
      ),
    );
  }

  Widget _buildRightPanel() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 24,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
            ),
            child: TabBar(
              controller: _tabController,
              labelColor: Theme.of(context).primaryColor,
              unselectedLabelColor: Colors.grey.shade600,
              indicatorColor: Theme.of(context).primaryColor,
              tabs: const [
                Tab(text: 'Editar Datos'),
                Tab(text: 'Historial Facturas'),
                Tab(text: 'Instrucciones & Resumen'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildForm(isCreation: false),
                _buildInvoicesTab(),
                _buildInstructionsAndSummaryTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInstructionsAndSummaryTab() {
    // Calculate basic KPIs
    final totalSpent = _invoices.fold<double>(0, (sum, inv) => sum + inv.total);
    final totalInvoices = _invoices.length;

    return ListView(
      padding: const EdgeInsets.all(24.0),
      children: [
        Row(
          children: [
            Expanded(
              child: _buildKpiCard(
                  'Total Compras',
                  '\$${ChileanUtils.formatCurrency(totalSpent)}',
                  Icons.monetization_on,
                  Colors.green),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildKpiCard(
                  'Facturas', '$totalInvoices', Icons.receipt, Colors.blue),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildKpiCard('Condición Pago', _paymentTerms.displayName,
                  Icons.payment, Colors.orange),
            ),
          ],
        ),
        const SizedBox(height: 32),
        const Text(
          'Instrucciones de Compra',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.blue.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: _purchaseInstructionsController.text.isNotEmpty
              ? Text(
                  _purchaseInstructionsController.text,
                  style: const TextStyle(fontSize: 15, height: 1.5),
                )
              : const Text(
                  'No hay instrucciones de compra configuradas aún. Ve a "Editar Datos" para añadirlas.',
                  style: TextStyle(
                      fontStyle: FontStyle.italic, color: Colors.grey),
                ),
        ),
        const SizedBox(height: 32),
        if (_notesController.text.isNotEmpty) ...[
          const Text(
            'Notas Internas',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              _notesController.text,
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ]
      ],
    );
  }

  Widget _buildKpiCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style:
                        TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInvoicesTab() {
    if (_invoices.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.receipt_long, size: 60, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            const Text(
              'No hay facturas registradas',
              style: TextStyle(color: Colors.grey, fontSize: 16),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _invoices.length,
      separatorBuilder: (context, index) => const Divider(),
      itemBuilder: (context, index) {
        final inv = _invoices[index];
        final isPaid = inv.status == PurchaseInvoiceStatus.paid;
        return ListTile(
          onTap: () => context.push('/purchases/${inv.id}'),
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isPaid ? Colors.green.shade50 : Colors.orange.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              isPaid ? Icons.check_circle : Icons.warning,
              color: isPaid ? Colors.green : Colors.orange,
            ),
          ),
          title: Text(
              'Factura #${inv.invoiceNumber.isNotEmpty ? inv.invoiceNumber : "S/N"}'),
          subtitle: Text(DateFormat('dd/MM/yyyy').format(inv.date)),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '\$${ChileanUtils.formatCurrency(inv.total)}',
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              if (!isPaid)
                Text(
                  'Pendiente: \$${ChileanUtils.formatCurrency(inv.balance)}',
                  style: const TextStyle(color: Colors.red, fontSize: 12),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildForm({required bool isCreation}) {
    return ListView(
      shrinkWrap: isCreation,
      physics: isCreation ? const NeverScrollableScrollPhysics() : null,
      padding: isCreation ? EdgeInsets.zero : const EdgeInsets.all(24.0),
      children: [
        _buildSectionTitle('Datos Básicos'),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Nombre interno / proveedor *',
                  hintText: 'Ej: Starken',
                ),
                validator: (val) =>
                    (val == null || val.trim().isEmpty) ? 'Requerido' : null,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: TextFormField(
                controller: _rutController,
                decoration: const InputDecoration(labelText: 'RUT'),
                autovalidateMode: AutovalidateMode.onUserInteraction,
                validator: (val) => (val != null &&
                        val.trim().isNotEmpty &&
                        !ChileanUtils.isValidRut(val.trim()))
                    ? 'RUT inválido'
                    : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextFormField(
                controller: _legalNameController,
                decoration: const InputDecoration(
                  labelText: 'Razón social / emisor legal',
                  hintText: 'Ej: Kaudat SpA',
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: TextFormField(
                controller: _tradeNameController,
                decoration: const InputDecoration(
                  labelText: 'Nombre comercial / marca',
                  hintText: 'Ej: Starken',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextFormField(
                controller: _ownerNameController,
                decoration: const InputDecoration(
                  labelText: 'Dueño / matriz',
                  hintText: 'Ej: Kaudat SpA',
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: TextFormField(
                controller: _aliasesController,
                decoration: const InputDecoration(
                  labelText: 'Alias OCR / nombres equivalentes',
                  hintText: 'Kaudat, Kaudat SpA, Starken',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _imageUrlController,
          decoration: const InputDecoration(
            labelText: 'URL Imagen de Perfil (Logo)',
            hintText: 'https://...',
            prefixIcon: Icon(Icons.image),
          ),
        ),
        const SizedBox(height: 32),
        _buildSectionTitle('Información de Contacto'),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _emailController,
                decoration:
                    const InputDecoration(labelText: 'Correo principal'),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: TextFormField(
                controller: _phoneController,
                decoration:
                    const InputDecoration(labelText: 'Teléfono principal'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _addressController,
                decoration: const InputDecoration(labelText: 'Dirección'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 32),
        _buildSectionTitle('Portal B2B (Sitio del Proveedor)'),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              flex: 2,
              child: TextFormField(
                controller: _websiteController,
                decoration: const InputDecoration(
                  labelText: 'URL del Portal / Sitio Web',
                  prefixIcon: Icon(Icons.language),
                ),
              ),
            ),
            const SizedBox(width: 16),
            SizedBox(
              height: 52,
              child: AppButton(
                text: 'Abrir Portal',
                icon: Icons.open_in_browser,
                onPressed: _openWebsiteWorkspace,
                type: ButtonType.primary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _portalUsernameController,
                autofillHints: const [AutofillHints.username],
                decoration: const InputDecoration(
                  labelText: 'Usuario / Rut de Acceso',
                  prefixIcon: Icon(Icons.person),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: TextFormField(
                controller: _portalPasswordController,
                obscureText: !_showPortalPassword,
                enableSuggestions: false,
                autocorrect: false,
                autofillHints: const [AutofillHints.password],
                decoration: InputDecoration(
                  labelText: 'Contraseña Portal',
                  prefixIcon: const Icon(Icons.password),
                  suffixIcon: IconButton(
                    tooltip: _showPortalPassword
                        ? 'Ocultar contraseña'
                        : 'Mostrar contraseña',
                    icon: Icon(
                      _showPortalPassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                    onPressed: () {
                      setState(
                        () => _showPortalPassword = !_showPortalPassword,
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 32),
        _buildSectionTitle('Vendedor Asignado'),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _salesRepNameController,
                decoration:
                    const InputDecoration(labelText: 'Nombre del vendedor'),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: TextFormField(
                controller: _salesRepPhoneController,
                decoration:
                    const InputDecoration(labelText: 'Teléfono / WhatsApp'),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: TextFormField(
                controller: _salesRepEmailController,
                decoration:
                    const InputDecoration(labelText: 'Email del vendedor'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 32),
        _buildSectionTitle('Condiciones y Operación'),
        const SizedBox(height: 16),
        TextFormField(
          controller: _purchaseInstructionsController,
          decoration: const InputDecoration(
            labelText:
                'Instrucciones para generar compra (Para nuevos trabajadores)',
            hintText:
                'Ej: Hacer pedido por la web. Luego enviar comprobante por whatsapp a Roberto...',
            alignLabelWithHint: true,
          ),
          maxLines: 4,
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<SupplierType>(
                initialValue: _type,
                decoration: const InputDecoration(labelText: 'Tipo'),
                items: SupplierType.values
                    .map((t) =>
                        DropdownMenuItem(value: t, child: Text(t.displayName)))
                    .toList(),
                onChanged: (val) {
                  if (val != null) setState(() => _type = val);
                },
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: DropdownButtonFormField<PaymentTerms>(
                initialValue: _paymentTerms,
                decoration:
                    const InputDecoration(labelText: 'Términos de Pago'),
                items: PaymentTerms.values
                    .map((t) =>
                        DropdownMenuItem(value: t, child: Text(t.displayName)))
                    .toList(),
                onChanged: (val) {
                  if (val != null) setState(() => _paymentTerms = val);
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<TaxTreatment>(
          initialValue: _defaultTaxTreatment,
          decoration: const InputDecoration(
            labelText: 'Tratamiento de IVA por Defecto',
          ),
          items: const [
            DropdownMenuItem(
                value: TaxTreatment.taxIncluded,
                child: Text('✓ Proveedor cobra IVA (19%)')),
            DropdownMenuItem(
                value: TaxTreatment.noTax,
                child: Text('✗ Sin IVA - Proveedor exento')),
          ],
          onChanged: (val) {
            if (val != null) setState(() => _defaultTaxTreatment = val);
          },
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _notesController,
          decoration: const InputDecoration(labelText: 'Notas adicionales'),
          maxLines: 2,
        ),
        const SizedBox(height: 16),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('Proveedor activo'),
          value: _isActive,
          onChanged: (val) => setState(() => _isActive = val),
        ),
        const SizedBox(height: 64),
      ],
    );
  }

  Widget _buildSectionTitle(String title) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).primaryColor,
          ),
        ),
        const Divider(),
      ],
    );
  }
}
