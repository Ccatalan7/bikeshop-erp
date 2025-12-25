import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../shared/services/user_management_service.dart';
import '../../hr/services/hr_service.dart';
import '../../hr/models/hr_models.dart';
import '../../crm/services/customer_service.dart';
import '../providers/chat_provider.dart';
import '../../bikeshop/services/bikeshop_service.dart';
import '../../sales/services/sales_service.dart';

class NewChatDialog extends StatefulWidget {
  const NewChatDialog({super.key});

  @override
  State<NewChatDialog> createState() => _NewChatDialogState();
}

class _NewChatDialogState extends State<NewChatDialog> {
  // Global Search
  String _searchQuery = '';

  // Data State
  List<ChatCandidate> _internalCandidates = [];
  List<ChatCandidate> _customerCandidates = [];
  bool _isLoading = true;

  // Group State
  final Set<String> _selectedGroupUsers = {};
  final TextEditingController _groupNameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  @override
  void dispose() {
    _groupNameController.dispose();
    super.dispose();
  }

  Future<void> _loadAllData() async {
    try {
      final currentUserId = Supabase.instance.client.auth.currentUser?.id;

      // 1. Fetch Internals (Users + Employees)
      final internalResults = await Future.wait([
        context.read<UserManagementService>().getTenantUsers(),
        context.read<HRService>().getEmployees(forceRefresh: true),
      ]);

      // 2. Fetch Customers
      final customers = await context.read<CustomerService>().getCustomers();

      // Process Internals
      final users = internalResults[0] as List<Map<String, dynamic>>;
      final employees = internalResults[1] as List<Employee>;

      final candidates = <ChatCandidate>[];
      final userIds = <String>{};

      // Add Users
      for (final user in users) {
        final uid = user['id'] as String;
        if (uid == currentUserId) continue; // Skip self

        userIds.add(uid);
        candidates.add(ChatCandidate(
          id: uid,
          displayName: _getUserDisplayName(user),
          subtitle: _getUserSubtitle(user),
          initials: _getUserInitials(user),
          isActive: user['is_active'] as bool? ?? true,
          canChat: user['is_active'] as bool? ?? true,
          type: CandidateType.user,
        ));
      }

      // Add unlinked Employees
      for (final emp in employees) {
        if (emp.userId != null && userIds.contains(emp.userId)) continue;

        candidates.add(ChatCandidate(
          id: emp.id!,
          displayName: '${emp.firstName} ${emp.lastName}',
          subtitle: 'Trabajador sin cuenta activa',
          initials: emp.firstName.isNotEmpty ? emp.firstName[0] : '?',
          isActive: emp.status == EmployeeStatus.active,
          canChat: false,
          type: CandidateType.employee,
          errorMessage: 'Requiere cuenta de usuario',
        ));
      }

      // Process Customers
      final customerCandidates = customers.map((c) {
        final hasAuth = c.authUserId != null;
        return ChatCandidate(
          id: c.authUserId ??
              c.id!, // authId if available, else CRM Id (not usable for chat yet)
          displayName: c.name,
          subtitle: hasAuth ? (c.email ?? 'Cliente App') : 'Cliente sin App',
          initials: c.initials,
          isActive: c.isActive,
          canChat: hasAuth && c.isActive,
          type: CandidateType.customer,
          errorMessage: hasAuth ? null : 'No registrado en App',
        );
      }).toList();

      if (!mounted) return;

      setState(() {
        _internalCandidates = candidates;
        _customerCandidates = customerCandidates;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        debugPrint('Error loading candidates: $e');
      }
    }
  }

  String _getUserDisplayName(Map<String, dynamic> user) {
    final name = user['employee_name'] as String?;
    if (name != null && name.isNotEmpty) return name;
    final email = user['email'] as String? ?? '';
    return email.split('@').first;
  }

  String _getUserSubtitle(Map<String, dynamic> user) {
    final email = user['email'] as String? ?? 'Sin email';
    final role = user['role'] as String? ?? 'Usuario';
    return '$role • $email';
  }

  String _getUserInitials(Map<String, dynamic> user) {
    final name = user['employee_name'] as String?;
    if (name != null && name.isNotEmpty) return name[0];
    final email = user['email'] as String? ?? '';
    return email.isNotEmpty ? email[0].toUpperCase() : '?';
  }

  void _createInternalChat(String userId) async {
    try {
      if (!mounted) return;
      Navigator.of(context).pop();
      await context.read<ChatProvider>().createInternalChat(userId);
    } catch (e) {
      debugPrint('Error creating internal chat: $e');
    }
  }

  void _createCustomerChat(String authUserId) async {
    // Find candidate for display name
    final candidate = _customerCandidates.firstWhere((c) => c.id == authUserId);

    // Show specialized dialog
    showDialog(
      context: context,
      builder: (_) => ContextSelectionDialog(candidate: candidate),
    ).then((result) {
      if (result == true) {
        // If dialog returned true, it handled the creation. Just close parent.
        Navigator.of(context).pop();
      }
    });
  }

  void _createGroupChat() async {
    final name = _groupNameController.text.trim();
    if (name.isEmpty || _selectedGroupUsers.isEmpty) return;

    try {
      if (!mounted) return;
      Navigator.of(context).pop();
      await context.read<ChatProvider>().createGroupChat(
            _selectedGroupUsers.toList(),
            name,
          );
    } catch (e) {
      debugPrint('Error creating group chat: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: DefaultTabController(
        length: 3,
        child: Container(
          width: 500,
          constraints: const BoxConstraints(maxHeight: 700),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(Icons.chat_bubble_outline),
                    const SizedBox(width: 8),
                    const Text('Nuevo Chat',
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(context).pop()),
                  ],
                ),
              ),

              const TabBar(
                labelColor: Colors.blue,
                unselectedLabelColor: Colors.grey,
                indicatorWeight: 3,
                tabs: [
                  Tab(text: 'Internos'),
                  Tab(text: 'Clientes'),
                  Tab(text: 'Grupo'),
                ],
              ),

              const SizedBox(height: 8),

              // Search Bar (Shared)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: 'Buscar...',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    isDense: true,
                  ),
                  onChanged: (value) => setState(() => _searchQuery = value),
                ),
              ),

              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : TabBarView(
                        children: [
                          // Internos Tab
                          _buildList(_internalCandidates,
                              (c) => _createInternalChat(c.id)),

                          // Clientes Tab
                          _buildList(
                            _customerCandidates,
                            (c) => _createCustomerChat(c.id),
                            type: CandidateType.customer,
                          ),

                          // Grupo Tab
                          _buildGroupList(),
                        ],
                      ),
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildList(List<ChatCandidate> source, Function(ChatCandidate) onTap,
      {CandidateType? type}) {
    final filtered = source.where((c) {
      if (_searchQuery.isEmpty) return true;
      return c.displayName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          c.subtitle.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();

    if (filtered.isEmpty) {
      return const Center(child: Text('No se encontraron resultados'));
    }

    return ListView.separated(
      padding: const EdgeInsets.all(8),
      itemCount: filtered.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final candidate = filtered[index];
        return ListTile(
          enabled: candidate.canChat,
          leading: CircleAvatar(
            backgroundColor:
                candidate.isActive ? Colors.blue[100] : Colors.grey[200],
            child: Text(
              candidate.initials,
              style: TextStyle(
                  color:
                      candidate.isActive ? Colors.blue[800] : Colors.grey[600]),
            ),
          ),
          title: Text(candidate.displayName),
          subtitle: Text(
            candidate.errorMessage ?? candidate.subtitle,
            style: TextStyle(
              color: candidate.canChat ? Colors.grey[600] : Colors.red[400],
              fontSize: 12,
            ),
          ),
          trailing: candidate.canChat
              ? const Icon(Icons.chevron_right, size: 16, color: Colors.grey)
              : const Icon(Icons.block, size: 16, color: Colors.grey),
          onTap: candidate.canChat ? () => onTap(candidate) : null,
        );
      },
    );
  }

  Widget _buildGroupList() {
    // Filter out users who can't chat
    final eligible = _internalCandidates.where((c) => c.canChat).toList();
    final filtered = eligible.where((c) {
      if (_searchQuery.isEmpty) return true;
      return c.displayName.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _groupNameController,
            decoration: const InputDecoration(
              labelText: 'Nombre del Grupo',
              hintText: 'Ej. Coordinación Taller',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: filtered.length,
            itemBuilder: (context, index) {
              final candidate = filtered[index];
              final isSelected = _selectedGroupUsers.contains(candidate.id);

              return CheckboxListTile(
                value: isSelected,
                title: Text(candidate.displayName),
                subtitle: Text(candidate.subtitle),
                secondary: CircleAvatar(
                  backgroundColor: Colors.blue[100],
                  child: Text(candidate.initials),
                ),
                onChanged: (val) {
                  setState(() {
                    if (val == true) {
                      _selectedGroupUsers.add(candidate.id);
                    } else {
                      _selectedGroupUsers.remove(candidate.id);
                    }
                  });
                },
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: ElevatedButton(
            onPressed: _groupNameController.text.isNotEmpty &&
                    _selectedGroupUsers.isNotEmpty
                ? _createGroupChat
                : null,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: Text('Crear Grupo (${_selectedGroupUsers.length})'),
          ),
        ),
      ],
    );
  }
}

enum CandidateType { user, employee, customer }

class ChatCandidate {
  final String id;
  final String displayName;
  final String subtitle;
  final String initials;
  final bool isActive;
  final bool canChat;
  final CandidateType type;
  final String? errorMessage;

  ChatCandidate({
    required this.id,
    required this.displayName,
    required this.subtitle,
    required this.initials,
    required this.isActive,
    required this.canChat,
    required this.type,
    this.errorMessage,
  });
}

class ContextSelectionDialog extends StatefulWidget {
  final ChatCandidate candidate;

  const ContextSelectionDialog({super.key, required this.candidate});

  @override
  State<ContextSelectionDialog> createState() => _ContextSelectionDialogState();
}

class _ContextSelectionDialogState extends State<ContextSelectionDialog> {
  bool _isLoading = true;
  final List<ChatContextOption> _options = [];
  ChatContextOption? _selectedOption;

  @override
  void initState() {
    super.initState();
    _loadContexts();
  }

  Future<void> _loadContexts() async {
    try {
      // 1. Fetch Open Jobs
      // Note: customerId in bikeshop is usually the CRM numeric ID, not auth ID.
      // But ChatCandidate ID is authId.
      // We need to map authId to CRM customer ID first?
      // CustomerService usually maps this.

      // Let's deduce CRM ID from user details or trust CustomerService
      // Wait, getCustomers() gives us ALL customers.
      // BikeshopService.getJobs takes `customerId` (numeric string).
      // We need the CRM ID.

      // We need to fetch the customer record by authId to get the numeric ID.
      final customerService = context.read<CustomerService>();
      final customers = await customerService.getCustomers();
      final customer =
          customers.firstWhere((c) => c.authUserId == widget.candidate.id);

      final crmId = customer.id;

      if (crmId != null) {
        final jobs = await context.read<BikeshopService>().getJobs(
              customerId: crmId,
              includeCompleted: false, // Only active jobs
            );

        final invoices = await context.read<SalesService>().getPendingInvoices(
              customerId: crmId,
            );

        _options.addAll(jobs.map((j) => ChatContextOption(
              label: 'Job #${j.jobNumber ?? "Sin N°"}',
              subtitle: j.status.displayName,
              type: 'job',
              id: j.id!,
            )));

        _options.addAll(invoices.map((i) => ChatContextOption(
              label:
                  'Factura ${i.invoiceNumber.isNotEmpty ? i.invoiceNumber : "Borrador"}',
              subtitle: '\$${i.total} - ${i.status.name}',
              type: 'invoice',
              id: i.id!,
            )));
      }

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading contexts: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _confirm() async {
    try {
      if (!mounted) return;
      // Close dialog immediately
      Navigator.of(context).pop(true);

      await context.read<ChatProvider>().createCustomerChat(
            widget.candidate.id,
            contextType: _selectedOption?.type, // Nullable
            contextId: _selectedOption?.id, // Nullable
          );
    } catch (e) {
      debugPrint('Error creating chat with context: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Iniciar chat con ${widget.candidate.displayName}'),
          const SizedBox(height: 4),
          Text(
            'Selecciona un contexto (opcional)',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      content: SizedBox(
        width: 400,
        height: 300,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _options.isEmpty
                ? const Center(
                    child: Text(
                    'No hay trabajos ni facturas pendientes.\nSe iniciará un chat general.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ))
                : ListView(
                    children: [
                      RadioListTile<ChatContextOption?>(
                        title: const Text('Chat General (Sin contexto)'),
                        value: null,
                        groupValue: _selectedOption,
                        onChanged: (val) =>
                            setState(() => _selectedOption = val),
                      ),
                      const Divider(),
                      ..._options.map((opt) => RadioListTile<ChatContextOption>(
                            title: Text(opt.label),
                            subtitle: Text(opt.subtitle),
                            secondary: Icon(
                              opt.type == 'job' ? Icons.build : Icons.receipt,
                              color: Colors.grey,
                            ),
                            value: opt,
                            groupValue: _selectedOption,
                            onChanged: (val) =>
                                setState(() => _selectedOption = val),
                          )),
                    ],
                  ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _confirm,
          child: const Text('Iniciar Chat'),
        ),
      ],
    );
  }
}

class ChatContextOption {
  final String label;
  final String subtitle;
  final String type;
  final String id;

  ChatContextOption({
    required this.label,
    required this.subtitle,
    required this.type,
    required this.id,
  });
}
