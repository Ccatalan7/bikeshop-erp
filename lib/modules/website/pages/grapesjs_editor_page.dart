import 'dart:async';
import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:ui_web' as ui;

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
                _currentHtml = data['html'] as String?;
                _currentCss = data['css'] as String?;
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
    final initialHtml = widget.initialHtml ?? '<div>Start building your website...</div>';
    final initialCss = widget.initialCss ?? '';

    return r'''
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>GrapesJS Editor</title>
  <link rel="stylesheet" href="https://unpkg.com/grapesjs/dist/css/grapes.min.css">
  <script src="https://unpkg.com/grapesjs"></script>
  <script src="https://unpkg.com/grapesjs-blocks-basic"></script>
  <style>
    body, html {
      height: 100%;
      margin: 0;
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, sans-serif;
    }
    #gjs {
      height: 100%;
      overflow: hidden;
    }
    .gjs-one-bg {
      background-color: #1e1e1e;
    }
    .gjs-two-color {
      color: #e0e0e0;
    }
    .gjs-three-bg {
      background-color: #2d2d2d;
      color: #e0e0e0;
    }
    .gjs-four-color,
    .gjs-four-color-h:hover {
      color: #2196F3;
    }
  </style>
</head>
<body>
  <div id="gjs"></div>
  
  <script>
    const editor = grapesjs.init({
      container: '#gjs',
      height: '100%',
      width: 'auto',
      storageManager: false, // We handle storage via Supabase
      fromElement: true,
      plugins: ['gjs-blocks-basic'],
      pluginsOpts: {
        'gjs-blocks-basic': {}
      },
      canvas: {
        styles: [
          'https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700&display=swap'
        ]
      },
      blockManager: {
        appendTo: '.gjs-pn-panel',
      },
      panels: {
        defaults: [
          {
            id: 'layers',
            el: '.panel__right',
            resizable: {
              maxDim: 350,
              minDim: 200,
              tc: 0,
              cl: 1,
              cr: 0,
              bc: 0,
            },
          },
          {
            id: 'panel-switcher',
            el: '.panel__switcher',
            buttons: [
              {
                id: 'show-layers',
                active: true,
                label: 'Layers',
                command: 'show-layers',
                togglable: false,
              },
              {
                id: 'show-style',
                active: true,
                label: 'Styles',
                command: 'show-styles',
                togglable: false,
              },
              {
                id: 'show-traits',
                active: true,
                label: 'Traits',
                command: 'show-traits',
                togglable: false,
              }
            ],
          },
          {
            id: 'panel-devices',
            el: '.panel__devices',
            buttons: [
              {
                id: 'device-desktop',
                label: '<i class="fa fa-desktop"></i>',
                command: 'set-device-desktop',
                active: true,
                togglable: false,
              },
              {
                id: 'device-tablet',
                label: '<i class="fa fa-tablet"></i>',
                command: 'set-device-tablet',
                togglable: false,
              },
              {
                id: 'device-mobile',
                label: '<i class="fa fa-mobile"></i>',
                command: 'set-device-mobile',
                togglable: false,
              },
            ],
          }
        ]
      },
      deviceManager: {
        devices: [
          {
            name: 'Desktop',
            width: '',
          },
          {
            name: 'Tablet',
            width: '768px',
            widthMedia: '992px',
          },
          {
            name: 'Mobile',
            width: '375px',
            widthMedia: '480px',
          },
        ]
      },
      styleManager: {
        sectors: [
          {
            name: 'General',
            open: false,
            buildProps: ['float', 'display', 'position', 'top', 'right', 'left', 'bottom']
          },
          {
            name: 'Dimension',
            open: false,
            buildProps: ['width', 'height', 'max-width', 'min-height', 'margin', 'padding']
          },
          {
            name: 'Typography',
            open: false,
            buildProps: ['font-family', 'font-size', 'font-weight', 'letter-spacing', 'color', 'line-height', 'text-align']
          },
          {
            name: 'Decorations',
            open: false,
            buildProps: ['background-color', 'border-radius', 'border', 'box-shadow', 'background']
          },
          {
            name: 'Extra',
            open: false,
            buildProps: ['transition', 'perspective', 'transform']
          }
        ]
      }
    });

    // Load initial content
    ''' + "editor.setComponents('''$initialHtml''');\n" +
    "editor.setStyle('''$initialCss''');\n" + r'''

    // Add custom blocks for bike shop
    editor.BlockManager.add('product-card', {
      label: 'Product Card',
      category: 'Bike Shop',
      content: `
        <div class="product-card" style="border: 1px solid #ddd; border-radius: 8px; padding: 20px; margin: 10px; text-align: center; max-width: 300px;">
          <img src="https://via.placeholder.com/250x200/2196F3/ffffff?text=Product+Image" style="width: 100%; border-radius: 4px; margin-bottom: 15px;">
          <h3 style="margin: 10px 0; font-size: 18px;">Product Name</h3>
          <p style="color: #666; margin: 10px 0;">Product description goes here...</p>
          <p style="font-size: 24px; font-weight: bold; color: #2196F3; margin: 15px 0;">$29.990</p>
          <button style="background: #2196F3; color: white; border: none; padding: 12px 24px; border-radius: 4px; cursor: pointer; font-size: 16px;">Add to Cart</button>
        </div>
      `,
      media: '<svg viewBox="0 0 24 24"><path fill="currentColor" d="M19,6H17C17,3.24 14.76,1 12,1C9.24,1 7,3.24 7,6H5C3.9,6 3,6.9 3,8V20C3,21.1 3.9,22 5,22H19C20.1,22 21,21.1 21,20V8C21,6.9 20.1,6 19,6M12,3C13.66,3 15,4.34 15,6H9C9,4.34 10.34,3 12,3M19,20H5V8H19V20M12,12C10.34,12 9,10.66 9,9H7C7,11.76 9.24,14 12,14C14.76,14 17,11.76 17,9H15C15,10.66 13.66,12 12,12Z" /></svg>'
    });

    editor.BlockManager.add('service-card', {
      label: 'Service Card',
      category: 'Bike Shop',
      content: `
        <div class="service-card" style="border-left: 4px solid #4CAF50; padding: 20px; margin: 10px; background: #f9f9f9; border-radius: 4px;">
          <h3 style="margin: 0 0 10px 0; color: #4CAF50; font-size: 20px;">Service Name</h3>
          <p style="color: #666; margin: 10px 0; line-height: 1.6;">Service description and details...</p>
          <p style="font-size: 18px; font-weight: 600; color: #333; margin: 15px 0;">From $15.000</p>
          <button style="background: #4CAF50; color: white; border: none; padding: 10px 20px; border-radius: 4px; cursor: pointer;">Book Now</button>
        </div>
      `,
      media: '<svg viewBox="0 0 24 24"><path fill="currentColor" d="M12,15.5A3.5,3.5 0 0,1 8.5,12A3.5,3.5 0 0,1 12,8.5A3.5,3.5 0 0,1 15.5,12A3.5,3.5 0 0,1 12,15.5M19.43,12.97C19.47,12.65 19.5,12.33 19.5,12C19.5,11.67 19.47,11.34 19.43,11L21.54,9.37C21.73,9.22 21.78,8.95 21.66,8.73L19.66,5.27C19.54,5.05 19.27,4.96 19.05,5.05L16.56,6.05C16.04,5.66 15.5,5.32 14.87,5.07L14.5,2.42C14.46,2.18 14.25,2 14,2H10C9.75,2 9.54,2.18 9.5,2.42L9.13,5.07C8.5,5.32 7.96,5.66 7.44,6.05L4.95,5.05C4.73,4.96 4.46,5.05 4.34,5.27L2.34,8.73C2.21,8.95 2.27,9.22 2.46,9.37L4.57,11C4.53,11.34 4.5,11.67 4.5,12C4.5,12.33 4.53,12.65 4.57,12.97L2.46,14.63C2.27,14.78 2.21,15.05 2.34,15.27L4.34,18.73C4.46,18.95 4.73,19.03 4.95,18.95L7.44,17.94C7.96,18.34 8.5,18.68 9.13,18.93L9.5,21.58C9.54,21.82 9.75,22 10,22H14C14.25,22 14.46,21.82 14.5,21.58L14.87,18.93C15.5,18.67 16.04,18.34 16.56,17.94L19.05,18.95C19.27,19.03 19.54,18.95 19.66,18.73L21.66,15.27C21.78,15.05 21.73,14.78 21.54,14.63L19.43,12.97Z" /></svg>'
    });

    editor.BlockManager.add('hero-section', {
      label: 'Hero Section',
      category: 'Bike Shop',
      content: `
        <div class="hero-section" style="background: linear-gradient(135deg, #2196F3 0%, #1976D2 100%); color: white; padding: 80px 20px; text-align: center;">
          <h1 style="font-size: 48px; margin: 0 0 20px 0; font-weight: 700;">Welcome to Our Bike Shop</h1>
          <p style="font-size: 20px; margin: 0 0 30px 0; opacity: 0.9;">Quality bikes and expert service</p>
          <button style="background: white; color: #2196F3; border: none; padding: 15px 40px; border-radius: 50px; cursor: pointer; font-size: 18px; font-weight: 600; box-shadow: 0 4px 15px rgba(0,0,0,0.2);">Shop Now</button>
        </div>
      `,
      media: '<svg viewBox="0 0 24 24"><path fill="currentColor" d="M21,16V4H3V16H21M21,2A2,2 0 0,1 23,4V16A2,2 0 0,1 21,18H14V20H16V22H8V20H10V18H3C1.89,18 1,17.1 1,16V4C1,2.89 1.89,2 3,2H21M5,6H14V11H5V6M15,6H19V8H15V6M19,9V14H15V9H19M5,12H9V14H5V12M10,12H14V14H10V12Z" /></svg>'
    });

    // Commands for device switching
    editor.Commands.add('set-device-desktop', {
      run: editor => editor.setDevice('Desktop')
    });
    editor.Commands.add('set-device-tablet', {
      run: editor => editor.setDevice('Tablet')
    });
    editor.Commands.add('set-device-mobile', {
      run: editor => editor.setDevice('Mobile')
    });

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

    // Make editor responsive
    window.addEventListener('resize', () => {
      editor.refresh();
    });
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
    html.window.open('/tienda', '_blank');
  }

  @override
  Widget build(BuildContext context) {
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
