import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/widgets/main_layout.dart';
import '../../../shared/widgets/app_button.dart';

class PurchaseOrderFormPage extends StatefulWidget {
  final String? orderId;

  const PurchaseOrderFormPage({super.key, this.orderId});

  @override
  State<PurchaseOrderFormPage> createState() => _PurchaseOrderFormPageState();
}

class _PurchaseOrderFormPageState extends State<PurchaseOrderFormPage> {
  final _formKey = GlobalKey<FormState>();
  final bool _isSaving = false;

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            // Header
            LayoutBuilder(
              builder: (context, constraints) {
                final isMobile = constraints.maxWidth < 600;

                return Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => context.pop(),
                        icon: const Icon(Icons.arrow_back),
                      ),
                      Expanded(
                        child: Text(
                          widget.orderId != null
                              ? 'Editar Orden'
                              : 'Nueva Orden',
                          style: TextStyle(
                            fontSize: isMobile ? 20 : 24,
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isMobile)
                        IconButton(
                          onPressed: _isSaving
                              ? null
                              : () {
                                  // TODO: Implement save
                                  context.pop();
                                },
                          icon: _isSaving
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.save, color: Colors.blue),
                        )
                      else
                        AppButton(
                          text: 'Guardar',
                          icon: Icons.save,
                          onPressed: () {
                            // TODO: Implement save
                            context.pop();
                          },
                          isLoading: _isSaving,
                        ),
                    ],
                  ),
                );
              },
            ),

            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.shopping_cart,
                      size: 80,
                      color: Colors.grey[400],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Formulario de Orden',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'En desarrollo...',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
