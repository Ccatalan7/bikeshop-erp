import 'dart:async';
import 'dart:html' as html;
import 'dart:ui_web' as ui;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// GrapesJS WYSIWYG HTML/CSS Editor for Website Module
/// 
/// This editor provides true WYSIWYG editing - what you see in the editor
/// is EXACTLY what will be deployed to Firebase Hosting.
/// 
/// Features:
/// - Embeds GrapesJS JavaScript library via IFrame
/// - Custom blocks for products, services, bike maintenance
/// - Real-time save to Supabase (HTML + CSS)
/// - Preview mode shows EXACT deployed output
/// - Responsive design editing (mobile, tablet, desktop)
class GrapesJSEditorPage extends StatefulWidget {
  final String? initialHtml;
  final String? initialCss;
  final String? pageId; // For editing existing pages

  const GrapesJSEditorPage({
    super.key,
    this.initialHtml,
    this.initialCss,
    this.pageId,
  });

  @override
  State<GrapesJSEditorPage> createState() => _GrapesJSEditorPageState();
}

class _GrapesJSEditorPageState extends State<GrapesJSEditorPage> {
  final _supabase = Supabase.instance.client;
  bool _isSaving = false;
  DateTime? _lastSaved;
  String _viewKey = 'editor-${DateTime.now().millisecondsSinceEpoch}';
  
  // Auto-save timer
  Timer? _autoSaveTimer;
  String? _currentHtml;
  String? _currentCss;

  @override
  void initState() {
    super.initState();
    _registerView();
    _setupAutoSave();
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    super.dispose();
  }

  /// Register the IFrame view for GrapesJS
  void _registerView() {
    if (!kIsWeb) return; // Only register on web platform
    
    // Create HTML content for GrapesJS editor
    final htmlContent = _buildGrapesJSHTML();
    
    // Register view factory
    ui.platformViewRegistry.registerViewFactory(
      _viewKey,
      (int viewId) {
        final iframe = html.IFrameElement()
          ..style.width = '100%'
          ..style.height = '100%'
          ..style.border = 'none'
          ..srcdoc = htmlContent;

        // Listen for messages from GrapesJS (save events)
        html.window.addEventListener('message', (event) {
          if (event is html.MessageEvent) {
            final data = event.data;
            if (data is Map) {
              if (data['type'] == 'grapesjs-update') {
                final bodyHtml = data['html'] as String?;
                final css = data['css'] as String?;
                
                if (bodyHtml != null && css != null) {
                  // Wrap body content back into a full HTML document
                  _currentHtml = '''
<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Tienda Online</title>
  <link href="https://fonts.googleapis.com/css2?family=Roboto:wght@300;400;500;700&display=swap" rel="stylesheet">
</head>
<body>
$bodyHtml
</body>
</html>
''';
                  _currentCss = css;
                }
              }
            }
          }
        });

        return iframe;
      },
    );
  }

  /// Setup auto-save every 30 seconds
  void _setupAutoSave() {
    _autoSaveTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (_currentHtml != null && _currentCss != null) {
        _saveToDatabase(silent: true);
      }
    });
  }

  /// Build the complete GrapesJS HTML with editor initialization
  String _buildGrapesJSHTML() {
    // MINIMAL GRAPESJS - Let it use defaults, no custom panels
    return '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>GrapesJS Editor</title>
  <link rel="stylesheet" href="https://unpkg.com/grapesjs/dist/css/grapes.min.css">
  <style>
    body, html {
      height: 100%;
      margin: 0;
    }
    #gjs {
      height: 100%;
    }
  </style>
</head>
<body>
  <div id="gjs"></div>
  
  <script src="https://unpkg.com/grapesjs"></script>
  <script src="https://unpkg.com/grapesjs-blocks-basic"></script>
  <script>
    try {
      console.log('🚀 Starting GrapesJS...');
      
      const editor = grapesjs.init({
        container: '#gjs',
        height: '100%',
        width: 'auto',
        storageManager: false,
        fromElement: false,
        plugins: ['gjs-blocks-basic']
      });

      console.log('✅ GrapesJS initialized!');
      console.log('Blocks:', editor.BlockManager.getAll().length);

      // Auto-send updates to Flutter every 2 seconds
      setInterval(() => {
        const html = editor.getHtml();
        const css = editor.getCss();
        
        window.parent.postMessage({
          type: 'grapesjs-update',
          html: html,
          css: css
        }, '*');
      }, 2000);

    } catch (error) {
      console.error('❌ GrapesJS Error:', error);
      document.body.innerHTML = '<div style="padding: 20px; color: red;">Error: ' + error.message + '</div>';
    }
  </script>
</body>
</html>
''';
  }

  /// Save current HTML/CSS to Supabase
  Future<void> _saveToDatabase({bool silent = false}) async {
    if (_currentHtml == null || _currentCss == null) {
      if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No changes to save')),
        );
      }
      return;
    }

    setState(() => _isSaving = true);

    try {
      final user = _supabase.auth.currentUser;
      if (user == null) throw Exception('Not authenticated');

      final tenantId = user.userMetadata?['tenant_id'] as String?;
      if (tenantId == null) throw Exception('No tenant ID found');

      if (widget.pageId != null) {
        // Update existing page
        await _supabase.from('website_pages').update({
          'html_content': _currentHtml,
          'css_content': _currentCss,
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', widget.pageId!).eq('tenant_id', tenantId);
      } else {
        // Create new page (home page)
        await _supabase.from('website_pages').insert({
          'tenant_id': tenantId,
          'page_name': 'home',
          'html_content': _currentHtml,
          'css_content': _currentCss,
          'is_published': true,
        });
      }

      setState(() {
        _lastSaved = DateTime.now();
        _isSaving = false;
      });

      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Website saved successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() => _isSaving = false);
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Preview the current website in new tab
  void _previewWebsite() {
    if (!kIsWeb) return; // Only available on web
    html.window.open('/tienda', '_blank');
  }

  @override
  Widget build(BuildContext context) {
    // GrapesJS editor only works on web platform
    if (!kIsWeb) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Website Editor'),
          backgroundColor: const Color(0xFF2d2d2d),
          foregroundColor: Colors.white,
        ),
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
                  'Editor web no disponible',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  'El editor de sitio web solo está disponible en la versión web.\nAbre la aplicación en un navegador para editar tu sitio.',
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF1e1e1e),
      appBar: AppBar(
        title: const Text('Website Editor'),
        backgroundColor: const Color(0xFF2d2d2d),
        foregroundColor: Colors.white,
        actions: [
          if (_lastSaved != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: Text(
                  'Saved ${_formatTimeSince(_lastSaved!)}',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.preview),
            tooltip: 'Preview',
            onPressed: _previewWebsite,
          ),
          IconButton(
            icon: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.save),
            tooltip: 'Save',
            onPressed: _isSaving ? null : () => _saveToDatabase(),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: HtmlElementView(
        viewType: _viewKey,
      ),
    );
  }

  String _formatTimeSince(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}
