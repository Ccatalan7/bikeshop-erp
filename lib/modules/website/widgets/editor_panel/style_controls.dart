part of '../website_editor_panel.dart';

/// Tab for generic block styling (Background, Spacing, etc.)
/// New optimized block style controls for inline editing
class _BlockStyleControls extends StatefulWidget {
  final String blockId;
  final WebsiteEditModeProvider provider;
  final Map<String, dynamic> blockData;
  final bool collapsible;

  const _BlockStyleControls({
    required this.blockId,
    required this.provider,
    required this.blockData,
    this.collapsible = true,
  });

  @override
  State<_BlockStyleControls> createState() => _BlockStyleControlsState();
}

class _BlockStyleControlsState extends State<_BlockStyleControls> {
  bool _paddingLinked = true;

  void _updateStyle(String key, dynamic value) {
    final currentData =
        Map<String, dynamic>.from(widget.blockData['block_data'] ?? {});
    final currentStyle = Map<String, dynamic>.from(currentData['style'] ?? {});

    currentStyle[key] = value;
    widget.provider.updateBlockData(widget.blockId, 'style', currentStyle);
  }

  Map<String, dynamic> get _style {
    return widget.blockData['block_data']?['style'] ?? {};
  }

  @override
  Widget build(BuildContext context) {
    final controls = <Widget>[
      // Background
      const _SectionHeader('Fondo del bloque'),
      const SizedBox(height: 8),
      _BackgroundTypeControl(
        style: _style,
        onChanged: (key, value) => _updateStyle(key, value),
      ),
      const SizedBox(height: 20),

      // Padding
      const _SectionHeader('Relleno (Padding)'),
      const SizedBox(height: 12),
      _FullPaddingControl(
        paddingTop: (_style['paddingTop'] as num?)?.toDouble() ?? 40.0,
        paddingRight: (_style['paddingRight'] as num?)?.toDouble() ?? 20.0,
        paddingBottom: (_style['paddingBottom'] as num?)?.toDouble() ?? 40.0,
        paddingLeft: (_style['paddingLeft'] as num?)?.toDouble() ?? 20.0,
        linked: _paddingLinked,
        onLinkedChanged: (v) => setState(() => _paddingLinked = v),
        onChanged: (top, right, bottom, left) {
          final newStyle = Map<String, dynamic>.from(_style);
          newStyle['paddingTop'] = top;
          newStyle['paddingRight'] = right;
          newStyle['paddingBottom'] = bottom;
          newStyle['paddingLeft'] = left;
          widget.provider.updateBlockData(widget.blockId, 'style', newStyle);
        },
      ),
      const SizedBox(height: 24),

      // Border
      const _SectionHeader('Borde'),
      const SizedBox(height: 12),
      _BorderControl(
        borderWidth: (_style['borderWidth'] as num?)?.toDouble() ?? 0.0,
        borderColor: _style['borderColor']?.toString() ?? '#E0E0E0',
        borderStyle: _style['borderStyle']?.toString() ?? 'solid',
        borderRadius: (_style['borderRadius'] as num?)?.toDouble() ?? 0.0,
        onChanged: (width, color, borderStyle, radius) {
          final newStyle = Map<String, dynamic>.from(_style);
          newStyle['borderWidth'] = width;
          newStyle['borderColor'] = color;
          newStyle['borderStyle'] = borderStyle;
          newStyle['borderRadius'] = radius;
          widget.provider.updateBlockData(widget.blockId, 'style', newStyle);
        },
      ),
      const SizedBox(height: 24),

      // Shadow
      const _SectionHeader('Sombra'),
      const SizedBox(height: 12),
      _BoxShadowControl(
        enabled: _style['shadowEnabled'] == true,
        offsetX: (_style['shadowOffsetX'] as num?)?.toDouble() ?? 0.0,
        offsetY: (_style['shadowOffsetY'] as num?)?.toDouble() ?? 4.0,
        blur: (_style['shadowBlur'] as num?)?.toDouble() ?? 12.0,
        spread: (_style['shadowSpread'] as num?)?.toDouble() ?? 0.0,
        color: _style['shadowColor']?.toString() ?? 'rgba(0,0,0,0.15)',
        onChanged: (enabled, offsetX, offsetY, blur, spread, color) {
          final newStyle = Map<String, dynamic>.from(_style);
          newStyle['shadowEnabled'] = enabled;
          newStyle['shadowOffsetX'] = offsetX;
          newStyle['shadowOffsetY'] = offsetY;
          newStyle['shadowBlur'] = blur;
          newStyle['shadowSpread'] = spread;
          newStyle['shadowColor'] = color;
          widget.provider.updateBlockData(widget.blockId, 'style', newStyle);
        },
      ),
    ];

    if (!widget.collapsible) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: controls,
      );
    }

    return _CollapsibleSection(
      title: 'Diseño y estilo',
      icon: Icons.brush_outlined,
      initiallyExpanded: false,
      children: controls,
    );
  }

  // Helper text controls removed as they are built-in now
}

/// Background control with solid color or gradient option
class _BackgroundTypeControl extends StatelessWidget {
  final Map<String, dynamic> style;
  final Function(String key, dynamic value) onChanged;

  const _BackgroundTypeControl({
    required this.style,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final backgroundType = style['backgroundType']?.toString() ?? 'solid';
    final isSolid = backgroundType != 'gradient';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Toggle between solid and gradient
        Row(
          children: [
            _buildTypeButton(
                'Sólido', isSolid, () => onChanged('backgroundType', 'solid')),
            const SizedBox(width: 8),
            _buildTypeButton('Degradado', !isSolid,
                () => onChanged('backgroundType', 'gradient')),
          ],
        ),
        const SizedBox(height: 16),

        if (isSolid) ...[
          _BackgroundColorControl(
            currentValue: style['backgroundColor'],
            onChanged: (val) => onChanged('backgroundColor', val),
          ),
        ] else ...[
          // Gradient controls
          const Text('Color inicial',
              style: TextStyle(color: Colors.white54, fontSize: 11)),
          const SizedBox(height: 8),
          _BackgroundColorControl(
            currentValue: style['gradientColor1'] ?? '#FFFFFF',
            onChanged: (val) => onChanged('gradientColor1', val),
          ),
          const SizedBox(height: 16),
          const Text('Color final',
              style: TextStyle(color: Colors.white54, fontSize: 11)),
          const SizedBox(height: 8),
          _BackgroundColorControl(
            currentValue: style['gradientColor2'] ?? '#F0F0F0',
            onChanged: (val) => onChanged('gradientColor2', val),
          ),
          const SizedBox(height: 16),
          const Text('Dirección',
              style: TextStyle(color: Colors.white54, fontSize: 11)),
          const SizedBox(height: 8),
          _GradientDirectionPicker(
            currentDirection:
                style['gradientDirection']?.toString() ?? 'to-bottom',
            onChanged: (dir) => onChanged('gradientDirection', dir),
          ),
        ],
      ],
    );
  }

  Widget _buildTypeButton(String label, bool isSelected, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFF00A09D).withValues(alpha: 0.2)
                : const Color(0xFF2D2D2D),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isSelected ? const Color(0xFF00A09D) : Colors.white12,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: isSelected ? const Color(0xFF00A09D) : Colors.white54,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Gradient direction picker with 8 direction options
class _GradientDirectionPicker extends StatelessWidget {
  final String currentDirection;
  final Function(String) onChanged;

  const _GradientDirectionPicker({
    required this.currentDirection,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final directions = [
      ('to-top', Icons.arrow_upward, 'Arriba'),
      ('to-top-right', Icons.north_east, 'Arriba Der.'),
      ('to-right', Icons.arrow_forward, 'Derecha'),
      ('to-bottom-right', Icons.south_east, 'Abajo Der.'),
      ('to-bottom', Icons.arrow_downward, 'Abajo'),
      ('to-bottom-left', Icons.south_west, 'Abajo Izq.'),
      ('to-left', Icons.arrow_back, 'Izquierda'),
      ('to-top-left', Icons.north_west, 'Arriba Izq.'),
    ];

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: directions.map((d) {
        final isSelected = d.$1 == currentDirection;
        return Tooltip(
          message: d.$3,
          child: GestureDetector(
            onTap: () => onChanged(d.$1),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: isSelected
                    ? const Color(0xFF00A09D)
                    : const Color(0xFF2D2D2D),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: isSelected ? const Color(0xFF00A09D) : Colors.white12,
                ),
              ),
              child: Icon(
                d.$2,
                size: 16,
                color: isSelected ? Colors.white : Colors.white54,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

/// Full padding control with all 4 sides and linked toggle
class _FullPaddingControl extends StatelessWidget {
  final double paddingTop;
  final double paddingRight;
  final double paddingBottom;
  final double paddingLeft;
  final bool linked;
  final Function(bool) onLinkedChanged;
  final Function(double, double, double, double) onChanged;

  const _FullPaddingControl({
    required this.paddingTop,
    required this.paddingRight,
    required this.paddingBottom,
    required this.paddingLeft,
    required this.linked,
    required this.onLinkedChanged,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Linked toggle
        Row(
          children: [
            Icon(
              linked ? Icons.link : Icons.link_off,
              size: 16,
              color: linked ? const Color(0xFF00A09D) : Colors.white38,
            ),
            const SizedBox(width: 8),
            Text(
              linked ? 'Valores vinculados' : 'Valores independientes',
              style: TextStyle(
                color: linked ? const Color(0xFF00A09D) : Colors.white38,
                fontSize: 11,
              ),
            ),
            const Spacer(),
            Switch(
              value: linked,
              onChanged: onLinkedChanged,
              activeThumbColor: Colors.white,
              activeTrackColor: const Color(0xFF00A09D),
              inactiveThumbColor: Colors.grey.shade400,
              inactiveTrackColor: Colors.grey.shade700,
            ),
          ],
        ),
        const SizedBox(height: 8),

        if (linked) ...[
          // Single slider that affects all sides proportionally
          _paddingSlider('Vertical', paddingTop, (val) {
            onChanged(val, paddingRight, val, paddingLeft);
          }),
          const SizedBox(height: 12),
          _paddingSlider('Horizontal', paddingLeft, (val) {
            onChanged(paddingTop, val, paddingBottom, val);
          }),
        ] else ...[
          // Individual sliders for each side
          _paddingSlider('Arriba', paddingTop, (val) {
            onChanged(val, paddingRight, paddingBottom, paddingLeft);
          }),
          const SizedBox(height: 8),
          _paddingSlider('Derecha', paddingRight, (val) {
            onChanged(paddingTop, val, paddingBottom, paddingLeft);
          }),
          const SizedBox(height: 8),
          _paddingSlider('Abajo', paddingBottom, (val) {
            onChanged(paddingTop, paddingRight, val, paddingLeft);
          }),
          const SizedBox(height: 8),
          _paddingSlider('Izquierda', paddingLeft, (val) {
            onChanged(paddingTop, paddingRight, paddingBottom, val);
          }),
        ],
      ],
    );
  }

  Widget _paddingSlider(String label, double value, Function(double) onChange) {
    return Row(
      children: [
        SizedBox(
          width: 70,
          child: Text(label,
              style: const TextStyle(color: Colors.white54, fontSize: 11)),
        ),
        Expanded(
          child: SliderTheme(
            data: const SliderThemeData(
              activeTrackColor: Color(0xFF00A09D),
              inactiveTrackColor: Colors.white10,
              thumbColor: Colors.white,
              trackHeight: 2,
              thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
            ),
            child: Slider(
              value: value.clamp(0.0, 200.0),
              min: 0,
              max: 200,
              divisions: 40,
              onChanged: onChange,
            ),
          ),
        ),
        SizedBox(
          width: 40,
          child: Text(
            '${value.round()}',
            style: const TextStyle(color: Color(0xFF00A09D), fontSize: 11),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}

/// Border control with width, color, style, and radius
class _BorderControl extends StatelessWidget {
  final double borderWidth;
  final String borderColor;
  final String borderStyle;
  final double borderRadius;
  final Function(double, String, String, double) onChanged;

  const _BorderControl({
    required this.borderWidth,
    required this.borderColor,
    required this.borderStyle,
    required this.borderRadius,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final hasBorder = borderWidth > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Quick presets
        Row(
          children: [
            _buildPreset('Ninguno', borderWidth == 0,
                () => onChanged(0, borderColor, borderStyle, borderRadius)),
            const SizedBox(width: 6),
            _buildPreset('Sutil', borderWidth == 1,
                () => onChanged(1, borderColor, 'solid', borderRadius)),
            const SizedBox(width: 6),
            _buildPreset('Medio', borderWidth == 2,
                () => onChanged(2, borderColor, 'solid', borderRadius)),
            const SizedBox(width: 6),
            _buildPreset('Grueso', borderWidth >= 4,
                () => onChanged(4, borderColor, 'solid', borderRadius)),
          ],
        ),

        if (hasBorder) ...[
          const SizedBox(height: 16),
          // Width slider
          _buildSliderRow('Grosor', borderWidth, 0, 20, (val) {
            onChanged(val, borderColor, borderStyle, borderRadius);
          }),
          const SizedBox(height: 12),
          // Style dropdown
          Row(
            children: [
              const SizedBox(
                width: 70,
                child: Text('Estilo',
                    style: TextStyle(color: Colors.white54, fontSize: 11)),
              ),
              Expanded(
                child: Row(
                  children: [
                    _buildStyleButton(
                        'solid', 'Sólido', borderStyle == 'solid'),
                    const SizedBox(width: 6),
                    _buildStyleButton(
                        'dashed', 'Rayado', borderStyle == 'dashed'),
                    const SizedBox(width: 6),
                    _buildStyleButton(
                        'dotted', 'Puntos', borderStyle == 'dotted'),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Color
          const Text('Color',
              style: TextStyle(color: Colors.white54, fontSize: 11)),
          const SizedBox(height: 8),
          _BorderColorPicker(
            currentColor: borderColor,
            onChanged: (color) =>
                onChanged(borderWidth, color, borderStyle, borderRadius),
          ),
        ],

        const SizedBox(height: 16),
        // Border radius (always show)
        const Text('Esquinas',
            style: TextStyle(color: Colors.white54, fontSize: 11)),
        const SizedBox(height: 8),
        Row(
          children: [
            _buildRadiusPreset('Ninguna', 0, borderRadius),
            const SizedBox(width: 6),
            _buildRadiusPreset('Sutil', 4, borderRadius),
            const SizedBox(width: 6),
            _buildRadiusPreset('Redondeada', 12, borderRadius),
            const SizedBox(width: 6),
            _buildRadiusPreset('Píldora', 50, borderRadius),
          ],
        ),
        const SizedBox(height: 8),
        _buildSliderRow('Radio', borderRadius, 0, 50, (val) {
          onChanged(borderWidth, borderColor, borderStyle, val);
        }),
      ],
    );
  }

  Widget _buildPreset(String label, bool isSelected, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFF00A09D).withValues(alpha: 0.2)
                : const Color(0xFF2D2D2D),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isSelected ? const Color(0xFF00A09D) : Colors.white12,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: isSelected ? const Color(0xFF00A09D) : Colors.white54,
                fontSize: 10,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStyleButton(String value, String label, bool isSelected) {
    return Expanded(
      child: GestureDetector(
        onTap: () => onChanged(borderWidth, borderColor, value, borderRadius),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFF00A09D).withValues(alpha: 0.2)
                : const Color(0xFF2D2D2D),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isSelected ? const Color(0xFF00A09D) : Colors.white12,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: isSelected ? const Color(0xFF00A09D) : Colors.white54,
                fontSize: 10,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRadiusPreset(String label, double value, double current) {
    final isSelected = (current - value).abs() < 2;
    return Expanded(
      child: GestureDetector(
        onTap: () => onChanged(borderWidth, borderColor, borderStyle, value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFF00A09D).withValues(alpha: 0.2)
                : const Color(0xFF2D2D2D),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isSelected ? const Color(0xFF00A09D) : Colors.white12,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: isSelected ? const Color(0xFF00A09D) : Colors.white54,
                fontSize: 10,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSliderRow(String label, double value, double min, double max,
      Function(double) onChange) {
    return Row(
      children: [
        SizedBox(
          width: 50,
          child: Text(label,
              style: const TextStyle(color: Colors.white54, fontSize: 11)),
        ),
        Expanded(
          child: SliderTheme(
            data: const SliderThemeData(
              activeTrackColor: Color(0xFF00A09D),
              inactiveTrackColor: Colors.white10,
              thumbColor: Colors.white,
              trackHeight: 2,
              thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: (max - min).toInt(),
              onChanged: onChange,
            ),
          ),
        ),
        SizedBox(
          width: 30,
          child: Text(
            '${value.round()}',
            style: const TextStyle(color: Color(0xFF00A09D), fontSize: 11),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}

/// Border color picker
class _BorderColorPicker extends StatelessWidget {
  final String currentColor;
  final Function(String) onChanged;

  const _BorderColorPicker({
    required this.currentColor,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => WebsiteColorPickerField(
        label: 'Color del borde',
        value: currentColor,
        allowAlpha: true,
        onChanged: onChanged,
      );
}

/// Box shadow control
class _BoxShadowControl extends StatelessWidget {
  final bool enabled;
  final double offsetX;
  final double offsetY;
  final double blur;
  final double spread;
  final String color;
  final Function(bool, double, double, double, double, String) onChanged;

  const _BoxShadowControl({
    required this.enabled,
    required this.offsetX,
    required this.offsetY,
    required this.blur,
    required this.spread,
    required this.color,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Quick presets
        Row(
          children: [
            _buildPreset(
                'Ninguna', !enabled, () => onChanged(false, 0, 0, 0, 0, color)),
            const SizedBox(width: 6),
            _buildPreset('Sutil', enabled && blur <= 8,
                () => onChanged(true, 0, 2, 6, 0, 'rgba(0,0,0,0.1)')),
            const SizedBox(width: 6),
            _buildPreset('Media', enabled && blur > 8 && blur <= 16,
                () => onChanged(true, 0, 4, 12, 0, 'rgba(0,0,0,0.15)')),
            const SizedBox(width: 6),
            _buildPreset('Fuerte', enabled && blur > 16,
                () => onChanged(true, 0, 8, 24, 0, 'rgba(0,0,0,0.2)')),
          ],
        ),

        if (enabled) ...[
          const SizedBox(height: 16),
          _buildSlider('Despl. X', offsetX, -30, 30,
              (val) => onChanged(enabled, val, offsetY, blur, spread, color)),
          const SizedBox(height: 8),
          _buildSlider('Despl. Y', offsetY, -30, 30,
              (val) => onChanged(enabled, offsetX, val, blur, spread, color)),
          const SizedBox(height: 8),
          _buildSlider(
              'Difuminado',
              blur,
              0,
              50,
              (val) =>
                  onChanged(enabled, offsetX, offsetY, val, spread, color)),
          const SizedBox(height: 8),
          _buildSlider('Extensión', spread, -20, 20,
              (val) => onChanged(enabled, offsetX, offsetY, blur, val, color)),
        ],
      ],
    );
  }

  Widget _buildPreset(String label, bool isSelected, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFF00A09D).withValues(alpha: 0.2)
                : const Color(0xFF2D2D2D),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isSelected ? const Color(0xFF00A09D) : Colors.white12,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: isSelected ? const Color(0xFF00A09D) : Colors.white54,
                fontSize: 10,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSlider(String label, double value, double min, double max,
      Function(double) onChange) {
    return Row(
      children: [
        SizedBox(
          width: 70,
          child: Text(label,
              style: const TextStyle(color: Colors.white54, fontSize: 11)),
        ),
        Expanded(
          child: SliderTheme(
            data: const SliderThemeData(
              activeTrackColor: Color(0xFF00A09D),
              inactiveTrackColor: Colors.white10,
              thumbColor: Colors.white,
              trackHeight: 2,
              thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: (max - min).toInt(),
              onChanged: onChange,
            ),
          ),
        ),
        SizedBox(
          width: 30,
          child: Text(
            '${value.round()}',
            style: const TextStyle(color: Color(0xFF00A09D), fontSize: 11),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}

class _BackgroundColorControl extends StatelessWidget {
  final String? currentValue;
  final Function(String?) onChanged;

  const _BackgroundColorControl({this.currentValue, required this.onChanged});

  @override
  Widget build(BuildContext context) => WebsiteColorPickerField(
        label: 'Color',
        value: (currentValue == null || currentValue!.isEmpty)
            ? '#00000000'
            : currentValue!,
        allowAlpha: true,
        allowTransparent: true,
        onChanged: (value) {
          final color = parseWebsiteEditorColor(value);
          onChanged(
            websiteEditorColorOpacity(color) == 0 ? null : value,
          );
        },
      );
}
