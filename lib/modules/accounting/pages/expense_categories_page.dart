import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/branded_loading.dart';
import '../../../shared/widgets/main_layout.dart';
import '../../../shared/widgets/search_widget.dart';
import '../models/account.dart';
import '../models/expense_category.dart';
import '../services/accounting_service.dart';
import '../services/expense_service.dart';

class ExpenseCategoriesPage extends StatefulWidget {
  const ExpenseCategoriesPage({super.key});

  @override
  State<ExpenseCategoriesPage> createState() => _ExpenseCategoriesPageState();
}

class _ExpenseCategoriesPageState extends State<ExpenseCategoriesPage> {
  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = true;
  String? _error;

  List<ExpenseCategory> _categories = const [];
  List<ExpenseCategory> _filtered = const [];

  List<Account> _expenseAccounts = const [];
  Map<String, String> _accountLabelById = const {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData({bool refresh = false}) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final expenseService = context.read<ExpenseService>();
      final accountingService = context.read<AccountingService>();

      final categories = await expenseService.fetchCategories(
        forceRefresh: refresh,
      );

      final allAccounts = await accountingService.getAccounts();
      final expenseAccounts = allAccounts
          .where((a) => a.type == AccountType.expense)
          .toList(growable: false);

      setState(() {
        _categories = categories;
        _expenseAccounts = expenseAccounts;
        _accountLabelById = {
          for (final a in expenseAccounts)
            if (a.id != null && a.id!.isNotEmpty)
              a.id!: '${a.code} - ${a.name}',
        };
      });

      _applyFilters();
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _applyFilters() {
    final q = _searchController.text.trim().toLowerCase();
    if (q.isEmpty) {
      setState(() => _filtered = _categories);
      return;
    }

    setState(() {
      _filtered = _categories.where((c) {
        final name = c.name.toLowerCase();
        final desc = (c.description ?? '').toLowerCase();
        return name.contains(q) || desc.contains(q);
      }).toList(growable: false);
    });
  }

  Future<void> _openCategoryDialog({ExpenseCategory? category}) async {
    final isEdit = category != null;

    final nameController = TextEditingController(text: category?.name ?? '');
    final descController =
        TextEditingController(text: category?.description ?? '');
    String? selectedAccountId = category?.defaultAccountId;
    bool isSaving = false;

    final saved = await showDialog<ExpenseCategory>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(isEdit ? 'Editar categoría' : 'Nueva categoría'),
              content: SizedBox(
                width: 520,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'Nombre *',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: descController,
                      decoration: const InputDecoration(
                        labelText: 'Descripción (opcional)',
                        border: OutlineInputBorder(),
                      ),
                      minLines: 2,
                      maxLines: 3,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String?>(
                      initialValue: selectedAccountId,
                      decoration: const InputDecoration(
                        labelText: 'Cuenta por defecto (opcional)',
                        border: OutlineInputBorder(),
                        helperText:
                            'Se usará como cuenta sugerida para esta categoría',
                      ),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('Sin cuenta por defecto'),
                        ),
                        ..._expenseAccounts.map((a) {
                          return DropdownMenuItem<String?>(
                            value: a.id,
                            child: Text('${a.code} - ${a.name}'),
                          );
                        }),
                      ],
                      onChanged: (v) {
                        setDialogState(() => selectedAccountId = v);
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving ? null : () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          final name = nameController.text.trim();
                          final desc = descController.text.trim();

                          if (name.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('El nombre es obligatorio'),
                                backgroundColor: Colors.red,
                              ),
                            );
                            return;
                          }

                          setDialogState(() => isSaving = true);
                          try {
                            final expenseService =
                                context.read<ExpenseService>();
                            final toSave = ExpenseCategory(
                              id: category?.id ?? '',
                              name: name,
                              description: desc.isEmpty ? null : desc,
                              defaultAccountId: selectedAccountId,
                              defaultTaxRate: category?.defaultTaxRate ?? 0,
                              createdAt: category?.createdAt,
                              updatedAt: DateTime.now(),
                            );

                            final stored =
                                await expenseService.saveCategory(toSave);
                            if (context.mounted) {
                              Navigator.pop(context, stored);
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('No se pudo guardar: $e'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                              setDialogState(() => isSaving = false);
                            }
                          }
                        },
                  child: isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Guardar'),
                ),
              ],
            );
          },
        );
      },
    );

    nameController.dispose();
    descController.dispose();

    if (saved == null || !mounted) return;
    await _loadData(refresh: true);
  }

  Future<void> _deleteCategory(ExpenseCategory category) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Eliminar categoría'),
          content: Text(
            '¿Eliminar "${category.name}"?\n\nSi está asociada a gastos, el sistema puede bloquear la eliminación.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Eliminar'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    try {
      final expenseService = context.read<ExpenseService>();
      await expenseService.deleteCategory(category.id);
      await _loadData(refresh: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Categoría eliminada'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se pudo eliminar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      child: Column(
        children: [
          _buildHeader(context),
          Expanded(
            child: _isLoading
                ? const Center(child: BrandedLoading())
                : _error != null
                    ? Center(child: Text(_error!))
                    : _buildList(context),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border:
            Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Volver',
            onPressed: () => context.pop(),
            icon: const Icon(Icons.arrow_back),
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Categorías de gasto',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 320,
            child: SearchWidget(
              controller: _searchController,
              hintText: 'Buscar por nombre...',
              onSearchChanged: (_) => _applyFilters(),
            ),
          ),
          const SizedBox(width: 12),
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _isLoading ? null : () => _loadData(refresh: true),
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 12),
          AppButton(
            text: 'Nueva categoría',
            icon: Icons.add,
            onPressed: () => _openCategoryDialog(),
          ),
        ],
      ),
    );
  }

  Widget _buildList(BuildContext context) {
    if (_filtered.isEmpty) {
      return const Center(child: Text('No hay categorías'));
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _filtered.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final c = _filtered[index];
        final defaultAccountLabel = c.defaultAccountId == null
            ? null
            : _accountLabelById[c.defaultAccountId!];

        return Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.grey.shade200),
          ),
          child: ListTile(
            title: Text(
              c.name,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if ((c.description ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(c.description!.trim()),
                ],
                const SizedBox(height: 6),
                Text(
                  defaultAccountLabel != null
                      ? 'Cuenta por defecto: $defaultAccountLabel'
                      : 'Cuenta por defecto: (sin asignar)',
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                ),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Editar',
                  onPressed: () => _openCategoryDialog(category: c),
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(
                  tooltip: 'Eliminar',
                  onPressed: () => _deleteCategory(c),
                  icon: Icon(Icons.delete_outline, color: Colors.red.shade600),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
