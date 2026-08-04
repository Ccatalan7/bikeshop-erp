part of '../website_editor_panel.dart';

/// Theme tab for global site-wide settings (colors, typography, button styles)
/// Header and Footer are edited via the "Editar" tab when selected
class _ThemeTab extends StatefulWidget {
  @override
  State<_ThemeTab> createState() => _ThemeTabState();
}

class _ThemeTabState extends State<_ThemeTab> {
  // Navigation state
  String? _activeCategory; // null = main menu

  // Colors
  final _primaryColorController = TextEditingController();
  final _accentColorController = TextEditingController();
  final _textColorController = TextEditingController();
  String _productDetailAccent = '#123F68';
  String _productDetailText = '#1E293B';
  String _productDetailLine = '#E8E2D8';

  // Typography
  String _headingFont = WebsiteFontRegistry.headingDefault;
  String _bodyFont = WebsiteFontRegistry.bodyDefault;
  String _headingSize = 'normal';
  String _bodySize = 'normal';

  // Button styles
  String _buttonStyle = 'rounded'; // rounded, sharp, pill
  String _buttonSize = 'medium'; // small, medium, large

  // Global composition spacing. Bounds/presets reuse the canonical page and
  // block-spacing contracts; arbitrary persisted values remain visible and
  // are only snapped when the owner changes the slider.
  double _sectionSpacing = WebsitePageComposition.defaultSectionSpacing;
  double _containerPadding = WebsiteResolvedTheme.defaultContainerPadding;
  static const _sectionSpacingPresets = <double>[0, 16, 32, 64, 96];
  static const _containerPaddingPresets = <double>[16, 24, 32, 48, 64];

  // Page Background
  String _pageBackground = '#FFFFFF';

  bool _loaded = false;

  static const _fonts = WebsiteFontRegistry.supportedFamilies;

  final _sizes = {
    'small': 'Pequeño',
    'normal': 'Normal',
    'large': 'Grande',
    'xlarge': 'Extra Grande',
  };

  final _buttonSizes = {
    'small': 'Pequeño',
    'medium': 'Mediano',
    'large': 'Grande',
  };

  String _sizeKeyFromStoredValue(
      {required bool isHeading, required String raw}) {
    final parsed = double.tryParse(raw.trim());
    if (parsed == null) return 'normal';

    if (isHeading) {
      if (parsed <= 40) return 'small';
      if (parsed <= 48) return 'normal';
      if (parsed <= 56) return 'large';
      return 'xlarge';
    }

    if (parsed <= 14) return 'small';
    if (parsed <= 16) return 'normal';
    if (parsed <= 18) return 'large';
    return 'xlarge';
  }

  String _storedValueFromSizeKey(
      {required bool isHeading, required String key}) {
    if (isHeading) {
      switch (key) {
        case 'small':
          return '40';
        case 'large':
          return '56';
        case 'xlarge':
          return '64';
        case 'normal':
        default:
          return '48';
      }
    }

    switch (key) {
      case 'small':
        return '14';
      case 'large':
        return '18';
      case 'xlarge':
        return '20';
      case 'normal':
      default:
        return '16';
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadSettings();
      });
      _loaded = true;
    }
  }

  Future<void> _loadSettings() async {
    try {
      final service = context.read<WebsiteService>();
      await service.loadSettings();

      if (mounted) {
        final editProvider = context.read<WebsiteEditModeProvider>();
        final resolved = WebsiteResolvedTheme.resolve(
          (key, fallback) {
            final saved = service.getSetting(key, fallback);
            return editProvider.isInEditorContext
                ? editProvider.getEffectiveThemeSetting(key, saved)
                : saved;
          },
        );
        setState(() {
          _primaryColorController.text =
              serializeWebsiteEditorColor(resolved.primaryColor);
          _accentColorController.text =
              serializeWebsiteEditorColor(resolved.accentColor);
          _textColorController.text =
              serializeWebsiteEditorColor(resolved.textColor);
          _productDetailAccent = serializeWebsiteEditorColor(
            resolved.commerceAccentColor,
          );
          _productDetailText = serializeWebsiteEditorColor(
            resolved.commerceTextColor,
          );
          _productDetailLine = serializeWebsiteEditorColor(
            resolved.commerceLineColor,
          );
          _headingFont = resolved.headingFont;
          _bodyFont = resolved.bodyFont;
          _headingSize = _sizeKeyFromStoredValue(
            isHeading: true,
            raw: resolved.headingSize.toString(),
          );
          _bodySize = _sizeKeyFromStoredValue(
            isHeading: false,
            raw: resolved.bodySize.toString(),
          );
          _buttonStyle = resolved.buttonStyle;
          _buttonSize = resolved.buttonSize;
          _sectionSpacing = resolved.sectionSpacing;
          _containerPadding = resolved.containerPadding;
          _pageBackground =
              serializeWebsiteEditorColor(resolved.backgroundColor);
        });
      }
    } catch (e) {
      debugPrint('Error loading theme: $e');
    }
  }

  @override
  void dispose() {
    _primaryColorController.dispose();
    _accentColorController.dispose();
    _textColorController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_activeCategory != null) {
      return Column(
        children: [
          _buildCategoryHeader(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: _buildCategoryContent(),
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'DISEÑO DEL SITIO',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Personaliza la apariencia global de tu sitio web.',
                style: TextStyle(color: Colors.white38, fontSize: 13),
              ),
            ],
          ),
        ),
        const Divider(color: Colors.white10),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            children: [
              _buildMenuItem(
                'Colores',
                'Paleta de colores principal',
                Icons.palette_outlined,
                'colors',
              ),
              _buildMenuItem(
                'Textos',
                'Tipografía y tamaños',
                Icons.text_fields,
                'text',
              ),
              _buildMenuItem(
                'Botones',
                'Estilo de botones',
                Icons.smart_button,
                'buttons',
              ),
              _buildMenuItem(
                'Fondo de página',
                'Color base del sitio',
                Icons.wallpaper,
                'background',
              ),
              _buildMenuItem(
                'Espaciado',
                'Separación y márgenes globales',
                Icons.space_bar,
                'spacing',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMenuItem(
      String title, String subtitle, IconData icon, String category) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF2D2D2D),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white10),
      ),
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFF00A09D)),
        title: Text(title, style: const TextStyle(color: Colors.white)),
        subtitle: Text(subtitle,
            style: const TextStyle(color: Colors.white54, fontSize: 12)),
        trailing: const Icon(Icons.chevron_right, color: Colors.white24),
        onTap: () => setState(() => _activeCategory = category),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Widget _buildCategoryHeader() {
    String title = '';
    switch (_activeCategory) {
      case 'colors':
        title = 'Colores';
        break;
      case 'text':
        title = 'Textos';
        break;
      case 'buttons':
        title = 'Botones';
        break;
      case 'background':
        title = 'Fondo';
        break;
      case 'spacing':
        title = 'Espaciado';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white10)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => setState(() => _activeCategory = null),
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryContent() {
    switch (_activeCategory) {
      case 'colors':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionHeader('COLOR PRINCIPAL'),
            const SizedBox(height: 12),
            WebsiteColorPickerField(
              label: 'Color principal',
              value: _primaryColorController.text,
              allowAlpha: false,
              onChanged: (val) {
                setState(() => _primaryColorController.text = val);
                context
                    .read<WebsiteEditModeProvider>()
                    .updateThemeSetting('theme_primary_color', val);
              },
            ),
            const SizedBox(height: 24),
            const _SectionHeader('COLOR DE ACENTO'),
            const SizedBox(height: 12),
            WebsiteColorPickerField(
              label: 'Color de acento',
              value: _accentColorController.text,
              allowAlpha: false,
              onChanged: (val) {
                setState(() => _accentColorController.text = val);
                context
                    .read<WebsiteEditModeProvider>()
                    .updateThemeSetting('theme_accent_color', val);
              },
            ),
            const SizedBox(height: 24),
            const _SectionHeader('COLOR DE TEXTO'),
            const SizedBox(height: 12),
            WebsiteColorPickerField(
              label: 'Color de texto',
              value: _textColorController.text,
              allowAlpha: false,
              onChanged: (val) {
                setState(() => _textColorController.text = val);
                context
                    .read<WebsiteEditModeProvider>()
                    .updateThemeSetting('theme_text_color', val);
              },
            ),
            const SizedBox(height: 28),
            const Divider(color: Colors.white12),
            const SizedBox(height: 20),
            const _SectionHeader('FICHA DE PRODUCTO'),
            const SizedBox(height: 8),
            const Text(
              'Paleta de precio, acciones, títulos y divisores de la ficha.',
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
            const SizedBox(height: 16),
            WebsiteColorPickerField(
              label: 'Acciones y precio',
              value: _productDetailAccent,
              allowAlpha: false,
              onChanged: (val) {
                setState(() => _productDetailAccent = val);
                context.read<WebsiteEditModeProvider>().updateThemeSetting(
                      'theme_product_detail_accent_color',
                      val,
                    );
              },
            ),
            const SizedBox(height: 16),
            WebsiteColorPickerField(
              label: 'Títulos y texto principal',
              value: _productDetailText,
              allowAlpha: false,
              onChanged: (val) {
                setState(() => _productDetailText = val);
                context.read<WebsiteEditModeProvider>().updateThemeSetting(
                      'theme_product_detail_text_color',
                      val,
                    );
              },
            ),
            const SizedBox(height: 16),
            WebsiteColorPickerField(
              label: 'Divisores',
              value: _productDetailLine,
              allowAlpha: false,
              onChanged: (val) {
                setState(() => _productDetailLine = val);
                context.read<WebsiteEditModeProvider>().updateThemeSetting(
                      'theme_product_detail_line_color',
                      val,
                    );
              },
            ),
          ],
        );

      case 'text':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionHeader('TÍTULOS'),
            const SizedBox(height: 12),
            _buildDropdown(
              label: 'Fuente',
              value: _headingFont,
              items: _fonts,
              labels: WebsiteFontRegistry.labelsByFamily,
              onChanged: (v) {
                if (v == null) return;
                setState(() => _headingFont = v);
                context
                    .read<WebsiteEditModeProvider>()
                    .updateThemeSetting('theme_heading_font', v);
              },
            ),
            const SizedBox(height: 12),
            _buildDropdown(
              label: 'Tamaño Base',
              value: _headingSize,
              items: _sizes.keys.toList(),
              labels: _sizes,
              onChanged: (v) {
                if (v == null) return;
                setState(() => _headingSize = v);
                context.read<WebsiteEditModeProvider>().updateThemeSetting(
                      'theme_heading_size',
                      _storedValueFromSizeKey(isHeading: true, key: v),
                    );
              },
            ),
            const SizedBox(height: 24),
            const _SectionHeader('PARRAFOS'),
            const SizedBox(height: 12),
            _buildDropdown(
              label: 'Fuente',
              value: _bodyFont,
              items: _fonts,
              labels: WebsiteFontRegistry.labelsByFamily,
              onChanged: (v) {
                if (v == null) return;
                setState(() => _bodyFont = v);
                context
                    .read<WebsiteEditModeProvider>()
                    .updateThemeSetting('theme_body_font', v);
              },
            ),
            const SizedBox(height: 12),
            _buildDropdown(
              label: 'Tamaño Base',
              value: _bodySize,
              items: _sizes.keys.toList(),
              labels: _sizes,
              onChanged: (v) {
                if (v == null) return;
                setState(() => _bodySize = v);
                context.read<WebsiteEditModeProvider>().updateThemeSetting(
                      'theme_body_size',
                      _storedValueFromSizeKey(isHeading: false, key: v),
                    );
              },
            ),
          ],
        );

      case 'buttons':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionHeader('FORMA'),
            const SizedBox(height: 12),
            Row(
              children: [
                _buildStyleOption('Cuadrado', 'sharp', _buttonStyle == 'sharp'),
                const SizedBox(width: 8),
                _buildStyleOption(
                    'Redondeado', 'rounded', _buttonStyle == 'rounded'),
                const SizedBox(width: 8),
                _buildStyleOption('Píldora', 'pill', _buttonStyle == 'pill'),
              ],
            ),
            const SizedBox(height: 24),
            const _SectionHeader('TAMAÑO'),
            const SizedBox(height: 12),
            _buildDropdown(
              label: 'Tamaño predeterminado',
              value: _buttonSize,
              items: _buttonSizes.keys.toList(),
              labels: _buttonSizes,
              onChanged: (v) {
                if (v == null) return;
                setState(() => _buttonSize = v);
                context
                    .read<WebsiteEditModeProvider>()
                    .updateThemeSetting('button_size', v);
              },
            ),
          ],
        );

      case 'background':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionHeader('FONDO DEL SITIO'),
            const SizedBox(height: 8),
            const Text(
              'Este color se aplicará al fondo de todas las páginas.',
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
            const SizedBox(height: 16),
            WebsiteColorPickerField(
              label: 'Color de fondo',
              value: _pageBackground,
              allowAlpha: false,
              onChanged: (val) {
                setState(() => _pageBackground = val);
                context
                    .read<WebsiteEditModeProvider>()
                    .updateThemeSetting('theme_background_color', val);
              },
            ),
          ],
        );

      case 'spacing':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionHeader('SEPARACIÓN ENTRE SECCIONES'),
            const SizedBox(height: 8),
            _buildThemeDimensionControl(
              label: 'Espaciado base',
              description:
                  'Se aplica a los bloques que heredan el espaciado global.',
              value: _sectionSpacing,
              min: WebsitePageComposition.minimumSpacing,
              max: WebsitePageComposition.maximumSpacing,
              divisions: 50,
              presets: _sectionSpacingPresets,
              onChanged: (value) {
                setState(() => _sectionSpacing = value);
                context.read<WebsiteEditModeProvider>().updateThemeSetting(
                      'theme_section_spacing',
                      value.round().toString(),
                    );
              },
            ),
            const SizedBox(height: 24),
            const _SectionHeader('MARGEN INTERIOR DEL CONTENIDO'),
            const SizedBox(height: 8),
            _buildThemeDimensionControl(
              label: 'Margen del contenedor',
              description:
                  'Define el espacio interior global del contenido de página.',
              value: _containerPadding,
              min: WebsiteResolvedTheme.minContainerPadding,
              max: WebsiteResolvedTheme.maxContainerPadding,
              divisions: 12,
              presets: _containerPaddingPresets,
              onChanged: (value) {
                setState(() => _containerPadding = value);
                context.read<WebsiteEditModeProvider>().updateThemeSetting(
                      'theme_container_padding',
                      value.round().toString(),
                    );
              },
            ),
          ],
        );

      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildThemeDimensionControl({
    required String label,
    required String description,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required List<double> presets,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const Spacer(),
            Text(
              '${value.round()}px',
              style: const TextStyle(
                color: Color(0xFF00A09D),
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (var index = 0; index < presets.length; index++) ...[
              _SpacingPresetButton(
                label: presets[index].round().toString(),
                isSelected: value == presets[index],
                onTap: () => onChanged(presets[index]),
              ),
              if (index < presets.length - 1) const SizedBox(width: 6),
            ],
          ],
        ),
        const SizedBox(height: 6),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: const Color(0xFF00A09D),
            inactiveTrackColor: Colors.white12,
            thumbColor: const Color(0xFF00A09D),
            overlayColor: const Color(0xFF00A09D).withValues(alpha: 0.2),
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            trackHeight: 3,
          ),
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: (next) => onChanged(next.roundToDouble()),
          ),
        ),
        Text(
          description,
          style: const TextStyle(color: Colors.white24, fontSize: 9),
        ),
      ],
    );
  }

  Widget _buildStyleOption(String label, String value, bool isSelected) {
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() => _buttonStyle = value);
          context
              .read<WebsiteEditModeProvider>()
              .updateThemeSetting('button_style', value);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFF00A09D).withValues(alpha: 0.2)
                : const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(
                value == 'pill' ? 20 : (value == 'rounded' ? 8 : 0)),
            border: Border.all(
              color: isSelected ? const Color(0xFF00A09D) : Colors.white12,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: isSelected ? const Color(0xFF00A09D) : Colors.white70,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDropdown({
    required String label,
    required String value,
    required List<String> items,
    Map<String, String>? labels,
    required ValueChanged<String?> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(color: Colors.white54, fontSize: 12)),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.white12),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: items.contains(value) ? value : null,
              isExpanded: true,
              dropdownColor: const Color(0xFF2D2D2D),
              style: const TextStyle(color: Colors.white, fontSize: 13),
              icon: const Icon(Icons.keyboard_arrow_down,
                  color: Colors.white54, size: 20),
              items: items.map((item) {
                return DropdownMenuItem(
                  value: item,
                  child: Text(labels?[item] ?? item),
                );
              }).toList(),
              onChanged: (newValue) {
                debugPrint(
                    '🎛️ [ThemeTab] Dropdown "$label" changed: "$value" -> "${newValue ?? 'null'}"');
                final editProvider = context.read<WebsiteEditModeProvider>();
                debugPrint(
                    '🎨 [ThemeTab] isInEditorContext=${editProvider.isInEditorContext} isEditMode=${editProvider.isEditMode} pendingThemeKeys=${editProvider.pendingThemeSettings.keys.join(', ')}');
                onChanged(newValue);
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// Logo uploader widget with image preview
class _LogoUploader extends StatefulWidget {
  final String? currentUrl;
  final Function(String) onChanged;

  const _LogoUploader({
    this.currentUrl,
    required this.onChanged,
  });

  @override
  State<_LogoUploader> createState() => _LogoUploaderState();
}

class _LogoUploaderState extends State<_LogoUploader> {
  bool _isUploading = false;

  Future<void> _pickAndUploadLogo() async {
    try {
      final asset = await showWebsiteMediaPicker(
        context: context,
        currentUrl: widget.currentUrl,
      );
      if (asset == null) return;
      widget.onChanged(asset.publicUrl);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Logo actualizado'),
            backgroundColor: Color(0xFF00A09D),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error uploading logo: $e');
      if (mounted) {
        setState(() => _isUploading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error subiendo logo: $e'),
            backgroundColor: Colors.red,
          ),
        );
      } else {
        _isUploading = false;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasLogo = widget.currentUrl != null && widget.currentUrl!.isNotEmpty;

    return Column(
      children: [
        InkWell(
          onTap: _isUploading ? null : _pickAndUploadLogo,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            height: 110,
            width: double.infinity,
            padding: hasLogo && !_isUploading
                ? const EdgeInsets.symmetric(horizontal: 12, vertical: 10)
                : EdgeInsets.zero,
            decoration: BoxDecoration(
              color: const Color(0xFF2D2D2D),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _isUploading
                    ? const Color(0xFF00A09D)
                    : Colors.white.withValues(alpha: 0.1),
                width: _isUploading ? 2 : 1,
              ),
              image: hasLogo && !_isUploading
                  ? DecorationImage(
                      image: NetworkImage(widget.currentUrl!),
                      fit: BoxFit.contain,
                    )
                  : null,
            ),
            child: _isUploading
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(
                        width: 32,
                        height: 32,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Color(0xFF00A09D),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Subiendo logo...',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  )
                : hasLogo
                    ? Align(
                        alignment: Alignment.topRight,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildActionButton(
                              icon: Icons.edit,
                              tooltip: 'Cambiar logo',
                              onTap: _pickAndUploadLogo,
                            ),
                            const SizedBox(width: 4),
                            _buildActionButton(
                              icon: Icons.delete,
                              tooltip: 'Eliminar',
                              onTap: () => widget.onChanged(''),
                              isDestructive: true,
                            ),
                          ],
                        ),
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF00A09D)
                                  .withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(50),
                            ),
                            child: const Icon(
                              Icons.cloud_upload_outlined,
                              color: Color(0xFF00A09D),
                              size: 28,
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Haz clic para subir logo',
                            style: TextStyle(
                              color: Color(0xFF00A09D),
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'JPG, PNG, WebP • Recomendado 500x200',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.4),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: isDestructive
                ? Colors.red.shade700.withValues(alpha: 0.9)
                : Colors.black.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(icon, color: Colors.white, size: 16),
        ),
      ),
    );
  }
}
