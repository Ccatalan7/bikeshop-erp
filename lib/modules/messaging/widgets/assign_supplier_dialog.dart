import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../shared/models/supplier.dart';
import '../../purchases/services/purchase_service.dart';
import '../services/messaging_service.dart';

/// «Es de un proveedor»: un chat de WhatsApp que entró por Mensajería es de
/// una persona de un proveedor (2026-10-13: el vendedor nuevo de Comercial
/// Ciclo escribió desde un número que el ERP no conocía).
///
/// Elegir el proveedor guarda el número como contacto suyo —con el nombre de
/// WhatsApp— y el servidor pasa el chat entero a Proveedores. Lo mismo ocurre
/// solo si el número se agrega desde la ficha del proveedor; esto es el atajo
/// desde el chat. Devuelve el resultado al cerrar con éxito.
class AssignSupplierDialog extends StatefulWidget {
  const AssignSupplierDialog({
    super.key,
    required this.conversationId,
    required this.contactName,
    required this.phoneLabel,
    this.messagingService,
  });

  final String conversationId;
  final String? contactName;
  final String? phoneLabel;
  final MessagingService? messagingService;

  @override
  State<AssignSupplierDialog> createState() => _AssignSupplierDialogState();
}

class _AssignSupplierDialogState extends State<AssignSupplierDialog> {
  final _searchController = TextEditingController();
  late final TextEditingController _nameController;
  // Una sola operación por diálogo: un doble toque o un acuse perdido repite
  // el recibo en vez de crear dos contactos.
  final String _operationId = const Uuid().v4();

  List<Supplier> _suppliers = const [];
  Supplier? _selected;
  bool _isPrimary = true;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.contactName ?? '');
    _loadSuppliers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadSuppliers() async {
    try {
      final suppliers =
          await context.read<PurchaseService>().getSuppliers(activeOnly: true);
      final sorted = [...suppliers]
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      if (!mounted) return;
      setState(() {
        _suppliers = sorted;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'No se pudieron cargar los proveedores.';
      });
    }
  }

  List<Supplier> get _visibleSuppliers {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return _suppliers;
    return _suppliers.where((supplier) {
      final haystack = [
        supplier.name,
        supplier.legalName,
        supplier.tradeName,
        supplier.rut,
        supplier.salesRepName,
        ...supplier.aliases,
      ].whereType<String>().join(' ').toLowerCase();
      return haystack.contains(query);
    }).toList();
  }

  Future<void> _submit() async {
    final supplier = _selected;
    if (supplier == null || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result = await (widget.messagingService ?? MessagingService())
          .assignConversationToSupplier(
        conversationId: widget.conversationId,
        supplierId: supplier.id,
        operationId: _operationId,
        contactName: _nameController.text,
        isPrimary: _isPrimary,
      );
      if (!mounted) return;
      Navigator.of(context).pop(result);
    } on PostgrestException catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = _readableError(error.message);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'No se pudo pasar el chat a Proveedores. Inténtalo de nuevo.';
      });
    }
  }

  String _readableError(String message) {
    if (message.contains('unido a un cliente')) {
      return 'Este chat está unido a un cliente, así que se queda en '
          'Mensajería. Si la persona es de un proveedor, agrégala desde su '
          'ficha y escríbele desde Proveedores.';
    }
    if (message.contains('already has that phone')) {
      return 'Ese proveedor ya tiene a otra persona con este número.';
    }
    if (message.startsWith('Sólo') ||
        message.startsWith('El chat') ||
        message.startsWith('Este chat')) {
      return message;
    }
    return 'No se pudo pasar el chat a Proveedores. Inténtalo de nuevo.';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final visible = _visibleSuppliers;
    final phone = widget.phoneLabel?.trim();

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: scheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.storefront_outlined,
                      size: 20,
                      color: scheme.onSecondaryContainer,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Es de un proveedor',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cerrar',
                    onPressed:
                        _saving ? null : () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '${phone == null || phone.isEmpty ? 'Este número' : phone} '
                'queda como contacto del proveedor y el chat pasa a '
                'Proveedores con todos sus mensajes.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                key: const ValueKey('assign-supplier-search'),
                controller: _searchController,
                enabled: !_saving,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  hintText: 'Buscar proveedor',
                  prefixIcon: Icon(Icons.search_rounded, size: 19),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 120),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(color: scheme.outlineVariant),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: _loading
                          ? const Center(
                              child: Padding(
                                padding: EdgeInsets.all(24),
                                child: CircularProgressIndicator(),
                              ),
                            )
                          : visible.isEmpty
                              ? Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(20),
                                    child: Text(
                                      'Ningún proveedor coincide.',
                                      style:
                                          theme.textTheme.bodyMedium?.copyWith(
                                        color: scheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                )
                              : ListView.separated(
                                  shrinkWrap: true,
                                  itemCount: visible.length,
                                  separatorBuilder: (_, __) => Divider(
                                    height: 1,
                                    color: scheme.outlineVariant,
                                  ),
                                  itemBuilder: (context, index) {
                                    final supplier = visible[index];
                                    final selected =
                                        _selected?.id == supplier.id;
                                    final rep = supplier.salesRepName?.trim();
                                    return ListTile(
                                      key: ValueKey(
                                          'assign-supplier-${supplier.id}'),
                                      dense: true,
                                      selected: selected,
                                      selectedTileColor: scheme.primaryContainer
                                          .withValues(alpha: 0.45),
                                      enabled: !_saving,
                                      onTap: () =>
                                          setState(() => _selected = supplier),
                                      title: Text(
                                        supplier.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w600),
                                      ),
                                      subtitle: rep == null || rep.isEmpty
                                          ? null
                                          : Text(
                                              'Vendedor: $rep',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                      trailing: selected
                                          ? Icon(Icons.check_circle_rounded,
                                              color: scheme.primary)
                                          : null,
                                    );
                                  },
                                ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                key: const ValueKey('assign-supplier-contact-name'),
                controller: _nameController,
                enabled: !_saving,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Nombre de la persona',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 4),
              SwitchListTile(
                key: const ValueKey('assign-supplier-primary'),
                contentPadding: EdgeInsets.zero,
                value: _isPrimary,
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _isPrimary = value),
                title: const Text('Es su vendedor principal'),
                subtitle: Text(
                  _selected?.salesRepName?.trim().isNotEmpty == true
                      ? 'Reemplaza a ${_selected!.salesRepName!.trim()} como la persona a la que el ERP le escribe.'
                      : 'El ERP le escribe a esta persona por defecto.',
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: scheme.errorContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _error!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onErrorContainer,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed:
                        _saving ? null : () => Navigator.of(context).pop(),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    key: const ValueKey('assign-supplier-submit'),
                    onPressed: _selected == null || _saving ? null : _submit,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.move_up_rounded, size: 18),
                    label: const Text('Pasar a Proveedores'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
