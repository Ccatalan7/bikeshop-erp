import 'dart:html' as html;
import 'dart:ui_web' as ui;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Static HTML Renderer for Public Store
/// 
/// This page fetches HTML/CSS from the database (saved by GrapesJS editor)
/// and renders it directly without Flutter widget conversion.
/// 
/// ✅ WYSIWYG Guarantee: What you see in GrapesJS === What deploys === What shows here
class StaticHTMLHomePage extends StatefulWidget {
  final String? tenantSubdomain;

  const StaticHTMLHomePage({
    super.key,
    this.tenantSubdomain,
  });

  @override
  State<StaticHTMLHomePage> createState() => _StaticHTMLHomePageState();
}

class _StaticHTMLHomePageState extends State<StaticHTMLHomePage> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;
  String? _error;
  String? _htmlContent;
  String? _cssContent;
  String _viewKey = 'static-html-${DateTime.now().millisecondsSinceEpoch}';

  @override
  void initState() {
    super.initState();
    _loadWebsiteContent();
  }

  /// Load website content from database
  Future<void> _loadWebsiteContent() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Get tenant_id from subdomain (if provided) or from current user
      String? tenantId;
      
      if (widget.tenantSubdomain != null) {
        // Public access: get tenant from subdomain
        final result = await _supabase
          .from('company_settings')
          .select('tenant_id')
          .eq('website_subdomain', widget.tenantSubdomain!)
          .maybeSingle();
        
        if (result != null) {
          tenantId = result['tenant_id'] as String?;
        }
      } else {
        // Authenticated access: get from current user
        final user = _supabase.auth.currentUser;
        tenantId = user?.userMetadata?['tenant_id'] as String?;
      }

      if (tenantId == null) {
        throw Exception('No se pudo determinar el tenant');
      }

      // Fetch home page content
      final pageData = await _supabase
        .from('website_pages')
        .select('html_content, css_content')
        .eq('tenant_id', tenantId)
        .eq('page_name', 'home')
        .eq('is_published', true)
        .maybeSingle();

      if (pageData == null) {
        throw Exception('No se encontró contenido del sitio web. Configura tu sitio primero.');
      }

      setState(() {
        _htmlContent = pageData['html_content'] as String?;
        _cssContent = pageData['css_content'] as String?;
        _isLoading = false;
      });

      // Register IFrame with HTML content
      if (_htmlContent != null && kIsWeb) {
        _registerHTMLView();
      }

    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  /// Register IFrame view with complete HTML document
  void _registerHTMLView() {
    if (!kIsWeb) return; // Only register on web platform
    
    final completeHTML = '''
<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Tienda Online</title>
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700&display=swap" rel="stylesheet">
  <style>
    * {
      margin: 0;
      padding: 0;
      box-sizing: border-box;
    }
    body {
      font-family: 'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, sans-serif;
      line-height: 1.6;
    }
    ${_cssContent ?? ''}
  </style>
</head>
<body>
  ${_htmlContent ?? ''}
  
  <script>
    // Make links work within IFrame
    document.querySelectorAll('a').forEach(link => {
      link.addEventListener('click', (e) => {
        e.preventDefault();
        const href = link.getAttribute('href');
        if (href && !href.startsWith('#')) {
          window.parent.location.href = href;
        }
      });
    });
    
    // Add to cart functionality (example)
    document.querySelectorAll('button').forEach(button => {
      if (button.textContent.includes('Add to Cart') || button.textContent.includes('Agregar')) {
        button.addEventListener('click', () => {
          alert('Producto agregado al carrito');
          // TODO: Integrate with shopping cart system
        });
      }
    });
  </script>
</body>
</html>
    ''';

    // Register view factory
    ui.platformViewRegistry.registerViewFactory(
      _viewKey,
      (int viewId) {
        final iframe = html.IFrameElement()
          ..style.width = '100%'
          ..style.height = '100%'
          ..style.border = 'none'
          ..srcdoc = completeHTML;
        return iframe;
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // Static HTML renderer only works on web platform
    if (!kIsWeb) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.web,
                  size: 64,
                  color: Colors.grey,
                ),
                const SizedBox(height: 16),
                Text(
                  'Vista previa no disponible',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  'La vista previa del sitio web solo está disponible en la versión web.\nAbre la aplicación en un navegador.',
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }
    
    if (_isLoading) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                'Cargando sitio web...',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
        ),
      );
    }

    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.error_outline,
                  size: 64,
                  color: Colors.red,
                ),
                const SizedBox(height: 16),
                Text(
                  'Error al cargar el sitio web',
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.red,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: _loadWebsiteContent,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reintentar'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: HtmlElementView(
        viewType: _viewKey,
      ),
    );
  }
}
