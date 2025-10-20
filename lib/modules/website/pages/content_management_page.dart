import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/website_service.dart';
import '../models/website_models.dart';

/// Page for managing website content (text blocks, pages, etc.)
class ContentManagementPage extends StatefulWidget {
  const ContentManagementPage({super.key});

  @override
  State<ContentManagementPage> createState() => _ContentManagementPageState();
}

class _ContentManagementPageState extends State<ContentManagementPage> {
  // Predefined content sections for the website
  final List<ContentSection> _sections = [
    ContentSection(
      id: 'about_us',
      title: 'Acerca de Nosotros',
      description: 'Historia y misión de la empresa',
      icon: Icons.info_outline,
      color: Colors.blue,
      defaultContent: '''
# Sobre Vinabike

Somos una empresa dedicada a ofrecer las mejores bicicletas y accesorios en Chile.

## Nuestra Misión
Promover el ciclismo como medio de transporte sustentable y deporte saludable.

## Nuestra Historia
Desde 2010, hemos servido a miles de clientes con productos de calidad.
''',
    ),
    ContentSection(
      id: 'terms_conditions',
      title: 'Términos y Condiciones',
      description: 'Condiciones de uso del sitio',
      icon: Icons.description_outlined,
      color: Colors.orange,
      defaultContent: '''
# Términos y Condiciones

**Última actualización:** ${DateTime.now().year}

## 1. Aceptación de Términos
Al usar este sitio, aceptas estos términos y condiciones.

## 2. Productos y Precios
- Los precios están en pesos chilenos (CLP)
- Los precios incluyen IVA
- Nos reservamos el derecho de modificar precios sin previo aviso

## 3. Política de Despacho
- Envíos a todo Chile
- Tiempo estimado: 3-7 días hábiles
- Costo de envío calculado al checkout

## 4. Garantía
- Todos los productos tienen garantía del fabricante
- Período de garantía según producto
''',
    ),
    ContentSection(
      id: 'privacy_policy',
      title: 'Política de Privacidad',
      description: 'Protección de datos personales',
      icon: Icons.privacy_tip_outlined,
      color: Colors.purple,
      defaultContent: '''
# Política de Privacidad

## Recopilación de Información
Recopilamos información personal cuando realizas una compra:
- Nombre completo
- Email
- Teléfono
- Dirección de envío

## Uso de la Información
Usamos tu información para:
- Procesar pedidos
- Enviar confirmaciones
- Mejorar nuestro servicio
- Comunicar ofertas (con tu consentimiento)

## Protección de Datos
- No compartimos tu información con terceros sin autorización
- Usamos encriptación SSL para transacciones
- Cumplimos con la Ley de Protección de Datos Personales de Chile

## Cookies
Usamos cookies para mejorar tu experiencia de navegación.

## Contacto
Para consultas sobre privacidad: contacto@vinabike.cl
''',
    ),
    ContentSection(
      id: 'shipping_info',
      title: 'Información de Envío',
      description: 'Detalles sobre despacho y entrega',
      icon: Icons.local_shipping_outlined,
      color: Colors.green,
      defaultContent: '''
# Información de Envío

## Cobertura
Realizamos envíos a todo Chile continental.

## Tiempos de Entrega
- Santiago: 2-3 días hábiles
- Regiones: 4-7 días hábiles
- Zonas extremas: 7-10 días hábiles

## Costos de Envío
- Calculado según peso y destino
- Envío gratis en compras sobre \$100.000

## Seguimiento
Recibirás un número de seguimiento por email.

## Retiro en Tienda
También puedes retirar tu pedido sin costo en nuestra tienda.
''',
    ),
    ContentSection(
      id: 'return_policy',
      title: 'Política de Devoluciones',
      description: 'Cambios y devoluciones',
      icon: Icons.keyboard_return_outlined,
      color: Colors.red,
      defaultContent: '''
# Política de Devoluciones

## Plazo
Tienes 30 días desde la recepción para solicitar cambio o devolución.

## Condiciones
El producto debe estar:
- Sin uso
- Con etiquetas originales
- En su empaque original
- Con comprobante de compra

## Proceso
1. Contacta a ventas@vinabike.cl
2. Envía fotos del producto
3. Espera autorización
4. Despacha el producto
5. Recibe reembolso o cambio

## Excepciones
No aceptamos devoluciones de:
- Productos personalizados
- Ropa interior o cascos por higiene
- Productos en oferta/liquidación
''',
    ),
    ContentSection(
      id: 'faq',
      title: 'Preguntas Frecuentes (FAQ)',
      description: 'Respuestas a consultas comunes',
      icon: Icons.help_outline,
      color: Colors.teal,
      defaultContent: '''
# Preguntas Frecuentes

## ¿Cómo realizo una compra?
1. Selecciona productos
2. Agrégalos al carrito
3. Procede al checkout
4. Completa tus datos
5. Confirma el pago

## ¿Qué métodos de pago aceptan?
- Tarjetas de crédito/débito
- Transferencia bancaria
- WebPay
- Mercado Pago

## ¿Puedo modificar mi pedido?
Sí, contacta inmediatamente a ventas@vinabike.cl

## ¿Emiten boleta o factura?
Sí, emitimos ambos documentos tributarios.

## ¿Tienen tienda física?
Sí, visítanos en Santiago. Consulta horarios en contacto.

## ¿Hacen mantención de bicicletas?
Sí, ofrecemos servicio técnico. Agenda tu hora.
''',
    ),
    ContentSection(
      id: 'contact',
      title: 'Información de Contacto',
      description: 'Datos de contacto y ubicación',
      icon: Icons.contact_mail_outlined,
      color: Colors.indigo,
      defaultContent: '''
# Contáctanos

## Tienda Física
**Dirección:** Av. Providencia 123, Santiago  
**Horario:** Lunes a Viernes 9:00 - 19:00, Sábados 10:00 - 14:00

## Canales de Contacto
📧 **Email:** contacto@vinabike.cl  
📱 **WhatsApp:** +56 9 1234 5678  
☎️ **Teléfono:** +56 2 2345 6789

## Redes Sociales
🔵 **Facebook:** /vinabikechile  
📸 **Instagram:** @vinabikecl  
🐦 **Twitter:** @vinabike

## Horario de Atención
Respondemos consultas de Lunes a Viernes, 9:00 a 18:00 hrs.
''',
    ),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<WebsiteService>().loadContents();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final websiteService = context.watch<WebsiteService>();

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Contenido del Sitio'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => websiteService.loadContents(),
            tooltip: 'Actualizar',
          ),
        ],
      ),
      body: websiteService.isLoading && websiteService.contents.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Info banner
                Container(
                  padding: const EdgeInsets.all(16),
                  margin: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Gestiona el contenido de tu sitio web',
                              style: TextStyle(
                                color: theme.colorScheme.onPrimaryContainer,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Edita textos de páginas legales, información de contacto, y más',
                              style: TextStyle(
                                color: theme.colorScheme.onPrimaryContainer,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Content sections grid
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.all(16),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                      childAspectRatio: 1.5,
                    ),
                    itemCount: _sections.length,
                    itemBuilder: (context, index) {
                      final section = _sections[index];
                      final savedContent = websiteService.getContentById(section.id);
                      final hasContent = savedContent?.content != null;

                      return _buildSectionCard(
                        context,
                        section,
                        hasContent,
                        savedContent,
                        websiteService,
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildSectionCard(
    BuildContext context,
    ContentSection section,
    bool hasContent,
    WebsiteContent? savedContent,
    WebsiteService service,
  ) {
    return Card(
      elevation: 2,
      child: InkWell(
        onTap: () => _editContent(context, section, savedContent),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Icon and status
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: section.color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      section.icon,
                      color: section.color,
                      size: 24,
                    ),
                  ),
                  const Spacer(),
                  if (hasContent)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(
                            Icons.check_circle,
                            size: 14,
                            color: Colors.green,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'Editado',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.green,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(
                            Icons.edit_outlined,
                            size: 14,
                            color: Colors.orange,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'Por defecto',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.orange,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),

              // Title
              Text(
                section.title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),

              // Description
              Text(
                section.description,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[600],
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const Spacer(),

              // Last updated
              if (savedContent != null) ...[
                const Divider(height: 16),
                Row(
                  children: [
                    Icon(
                      Icons.access_time,
                      size: 12,
                      color: Colors.grey[500],
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Actualizado ${_formatDate(savedContent.updatedAt)}',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey[500],
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      if (difference.inHours == 0) {
        return 'hace ${difference.inMinutes} min';
      }
      return 'hace ${difference.inHours}h';
    } else if (difference.inDays == 1) {
      return 'ayer';
    } else if (difference.inDays < 7) {
      return 'hace ${difference.inDays} días';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }

  void _editContent(
    BuildContext context,
    ContentSection section,
    WebsiteContent? savedContent,
  ) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => _ContentEditorPage(
          section: section,
          savedContent: savedContent,
        ),
      ),
    );
  }
}

// ============================================================================
// Content Section Model
// ============================================================================

class ContentSection {
  final String id;
  final String title;
  final String description;
  final IconData icon;
  final Color color;
  final String defaultContent;

  ContentSection({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
    required this.defaultContent,
  });
}

// ============================================================================
// Content Editor Page
// ============================================================================

class _ContentEditorPage extends StatefulWidget {
  final ContentSection section;
  final WebsiteContent? savedContent;

  const _ContentEditorPage({
    required this.section,
    this.savedContent,
  });

  @override
  State<_ContentEditorPage> createState() => _ContentEditorPageState();
}

class _ContentEditorPageState extends State<_ContentEditorPage> {
  late final TextEditingController _contentController;
  bool _isSaving = false;
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    final initialContent = widget.savedContent?.content ?? widget.section.defaultContent;
    _contentController = TextEditingController(text: initialContent);
    _contentController.addListener(() {
      if (!_hasChanges) {
        setState(() => _hasChanges = true);
      }
    });
  }

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => _handleBack(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Editor de Contenido'),
            Text(
              widget.section.title,
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: [
          if (_hasChanges)
            TextButton.icon(
              onPressed: _resetToDefault,
              icon: const Icon(Icons.restore, size: 18),
              label: const Text('Restaurar'),
            ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: _isSaving ? null : _saveContent,
            icon: _isSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save),
            label: const Text('Guardar'),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: Row(
        children: [
          // Editor
          Expanded(
            flex: 1,
            child: Column(
              children: [
                // Toolbar
                Container(
                  padding: const EdgeInsets.all(8),
                  color: theme.colorScheme.surfaceVariant,
                  child: Row(
                    children: [
                      const Icon(Icons.edit, size: 20),
                      const SizedBox(width: 8),
                      const Text('Markdown'),
                      const Spacer(),
                      Chip(
                        label: Text(
                          _hasChanges ? 'No guardado' : 'Guardado',
                          style: const TextStyle(fontSize: 12),
                        ),
                        backgroundColor: _hasChanges
                            ? Colors.orange.withOpacity(0.2)
                            : Colors.green.withOpacity(0.2),
                        avatar: Icon(
                          _hasChanges ? Icons.edit : Icons.check,
                          size: 16,
                          color: _hasChanges ? Colors.orange : Colors.green,
                        ),
                      ),
                    ],
                  ),
                ),

                // Text editor
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: TextField(
                      controller: _contentController,
                      maxLines: null,
                      expands: true,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 14,
                      ),
                      decoration: const InputDecoration(
                        hintText: 'Escribe el contenido aquí...\n\nPuedes usar Markdown:\n# Título\n## Subtítulo\n**negrita**\n*cursiva*\n- Lista',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.all(16),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Preview
          Container(
            width: 1,
            color: theme.dividerColor,
          ),
          Expanded(
            flex: 1,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  color: theme.colorScheme.surfaceVariant,
                  child: Row(
                    children: const [
                      Icon(Icons.visibility, size: 20),
                      SizedBox(width: 8),
                      Text('Vista Previa'),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: _buildMarkdownPreview(_contentController.text),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMarkdownPreview(String markdown) {
    // Simple markdown-to-widget renderer
    // In production, use flutter_markdown package
    final lines = markdown.split('\n');
    final List<Widget> widgets = [];

    for (var line in lines) {
      if (line.startsWith('# ')) {
        widgets.add(Text(
          line.substring(2),
          style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
        ));
        widgets.add(const SizedBox(height: 16));
      } else if (line.startsWith('## ')) {
        widgets.add(Text(
          line.substring(3),
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ));
        widgets.add(const SizedBox(height: 12));
      } else if (line.startsWith('### ')) {
        widgets.add(Text(
          line.substring(4),
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ));
        widgets.add(const SizedBox(height: 8));
      } else if (line.startsWith('- ') || line.startsWith('* ')) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(left: 16, bottom: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('• ', style: TextStyle(fontSize: 16)),
              Expanded(child: Text(_parseInlineMarkdown(line.substring(2)))),
            ],
          ),
        ));
      } else if (line.trim().isEmpty) {
        widgets.add(const SizedBox(height: 12));
      } else {
        widgets.add(Text(_parseInlineMarkdown(line)));
        widgets.add(const SizedBox(height: 8));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }

  String _parseInlineMarkdown(String text) {
    // Simple inline markdown parsing
    // In production, use proper markdown package
    return text
        .replaceAll(RegExp(r'\*\*(.+?)\*\*'), r'$1') // bold
        .replaceAll(RegExp(r'\*(.+?)\*'), r'$1'); // italic
  }

  void _resetToDefault() {
    setState(() {
      _contentController.text = widget.section.defaultContent;
      _hasChanges = false;
    });
  }

  Future<void> _saveContent() async {
    setState(() => _isSaving = true);

    try {
      final service = context.read<WebsiteService>();
      
      final content = WebsiteContent(
        id: widget.section.id,
        title: widget.section.title,
        content: _contentController.text,
        updatedAt: DateTime.now(),
      );

      await service.saveContent(content);

      if (mounted) {
        setState(() {
          _hasChanges = false;
          _isSaving = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Contenido guardado exitosamente'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _handleBack() async {
    if (_hasChanges) {
      final shouldDiscard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('¿Descartar cambios?'),
          content: const Text('Tienes cambios sin guardar. ¿Deseas salir de todos modos?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Descartar'),
            ),
          ],
        ),
      );

      if (shouldDiscard == true && mounted) {
        Navigator.of(context).pop();
      }
    } else {
      Navigator.of(context).pop();
    }
  }
}

