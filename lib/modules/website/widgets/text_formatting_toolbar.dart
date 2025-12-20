import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Text formatting options that can be applied
class TextFormatting {
  final bool isBold;
  final bool isItalic;
  final bool isUnderline;
  final double? fontSize;
  final TextAlign textAlign;
  final Color? textColor;
  final String? linkUrl;
  final double? letterSpacing;
  final double? lineHeight;
  final FontWeight? fontWeight;
  final String? fontFamily;

  const TextFormatting({
    this.isBold = false,
    this.isItalic = false,
    this.isUnderline = false,
    this.fontSize,
    this.textAlign = TextAlign.start,
    this.textColor,
    this.linkUrl,
    this.letterSpacing,
    this.lineHeight,
    this.fontWeight,
    this.fontFamily,
  });

  TextFormatting copyWith({
    bool? isBold,
    bool? isItalic,
    bool? isUnderline,
    double? fontSize,
    TextAlign? textAlign,
    Color? textColor,
    String? linkUrl,
    double? letterSpacing,
    double? lineHeight,
    FontWeight? fontWeight,
    String? fontFamily,
  }) {
    return TextFormatting(
      isBold: isBold ?? this.isBold,
      isItalic: isItalic ?? this.isItalic,
      isUnderline: isUnderline ?? this.isUnderline,
      fontSize: fontSize ?? this.fontSize,
      textAlign: textAlign ?? this.textAlign,
      textColor: textColor ?? this.textColor,
      linkUrl: linkUrl ?? this.linkUrl,
      letterSpacing: letterSpacing ?? this.letterSpacing,
      lineHeight: lineHeight ?? this.lineHeight,
      fontWeight: fontWeight ?? this.fontWeight,
      fontFamily: fontFamily ?? this.fontFamily,
    );
  }

  /// Convert to a map for storage
  Map<String, dynamic> toJson() {
    return {
      if (isBold) 'bold': true,
      if (isItalic) 'italic': true,
      if (isUnderline) 'underline': true,
      if (fontSize != null) 'fontSize': fontSize,
      if (textAlign != TextAlign.start) 'textAlign': textAlign.name,
      if (textColor != null) 'textColor': textColor!.value,
      if (linkUrl != null) 'linkUrl': linkUrl,
      if (letterSpacing != null) 'letterSpacing': letterSpacing,
      if (lineHeight != null) 'lineHeight': lineHeight,
      if (fontWeight != null) 'fontWeight': fontWeight!.index,
      if (fontFamily != null) 'fontFamily': fontFamily,
    };
  }

  /// Create from a map
  factory TextFormatting.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const TextFormatting();
    return TextFormatting(
      isBold: json['bold'] ?? false,
      isItalic: json['italic'] ?? false,
      isUnderline: json['underline'] ?? false,
      fontSize: (json['fontSize'] as num?)?.toDouble(),
      textAlign: _parseTextAlign(json['textAlign']),
      textColor:
          json['textColor'] != null ? Color(json['textColor'] as int) : null,
      linkUrl: json['linkUrl'] as String?,
      letterSpacing: (json['letterSpacing'] as num?)?.toDouble(),
      lineHeight: (json['lineHeight'] as num?)?.toDouble(),
      fontWeight: json['fontWeight'] != null
          ? FontWeight.values[json['fontWeight'] as int]
          : null,
      fontFamily: json['fontFamily'] as String?,
    );
  }

  static TextAlign _parseTextAlign(String? value) {
    switch (value) {
      case 'center':
        return TextAlign.center;
      case 'end':
        return TextAlign.end;
      case 'right':
        return TextAlign.right;
      case 'justify':
        return TextAlign.justify;
      default:
        return TextAlign.start;
    }
  }

  /// Apply formatting to a TextStyle
  TextStyle applyTo(TextStyle baseStyle) {
    return baseStyle.copyWith(
      fontWeight:
          isBold ? FontWeight.bold : (fontWeight ?? baseStyle.fontWeight),
      fontStyle: isItalic ? FontStyle.italic : baseStyle.fontStyle,
      decoration: isUnderline ? TextDecoration.underline : baseStyle.decoration,
      fontSize: fontSize ?? baseStyle.fontSize,
      color: textColor ?? baseStyle.color,
      letterSpacing: letterSpacing ?? baseStyle.letterSpacing,
      height: lineHeight ?? baseStyle.height,
      fontFamily: fontFamily ?? baseStyle.fontFamily,
    );
  }
}

/// Floating toolbar for text formatting
/// Appears when text is being edited, positioned near the text field
class TextFormattingToolbar extends StatefulWidget {
  final TextFormatting currentFormatting;
  final ValueChanged<TextFormatting> onFormattingChanged;
  final VoidCallback? onClose;
  final TextStyle? baseStyle;
  final bool showAdvancedOptions;
  final Offset? position; // If null, toolbar decides position

  const TextFormattingToolbar({
    super.key,
    required this.currentFormatting,
    required this.onFormattingChanged,
    this.onClose,
    this.baseStyle,
    this.showAdvancedOptions = true,
    this.position,
  });

  @override
  State<TextFormattingToolbar> createState() => _TextFormattingToolbarState();
}

class _TextFormattingToolbarState extends State<TextFormattingToolbar> {
  bool _showColorPicker = false;
  bool _showFontSizePicker = false;
  bool _showMoreOptions = false;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(8),
      color: Colors.grey.shade900,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Main toolbar row
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Bold
                _ToolbarButton(
                  icon: Icons.format_bold,
                  tooltip: 'Negrita (Ctrl+B)',
                  isActive: widget.currentFormatting.isBold,
                  onPressed: () => _toggleBold(),
                ),

                // Italic
                _ToolbarButton(
                  icon: Icons.format_italic,
                  tooltip: 'Cursiva (Ctrl+I)',
                  isActive: widget.currentFormatting.isItalic,
                  onPressed: () => _toggleItalic(),
                ),

                // Underline
                _ToolbarButton(
                  icon: Icons.format_underlined,
                  tooltip: 'Subrayado (Ctrl+U)',
                  isActive: widget.currentFormatting.isUnderline,
                  onPressed: () => _toggleUnderline(),
                ),

                _ToolbarDivider(),

                // Text alignment
                _ToolbarButton(
                  icon: _getAlignIcon(widget.currentFormatting.textAlign),
                  tooltip: 'Alineación',
                  onPressed: () => _cycleAlignment(),
                ),

                _ToolbarDivider(),

                // Font size
                _FontSizeButton(
                  currentSize: widget.currentFormatting.fontSize ??
                      widget.baseStyle?.fontSize ??
                      16,
                  onSizeChanged: (size) => _setFontSize(size),
                  isExpanded: _showFontSizePicker,
                  onToggleExpanded: () => setState(() {
                    _showFontSizePicker = !_showFontSizePicker;
                    _showColorPicker = false;
                    _showMoreOptions = false;
                  }),
                ),

                _ToolbarDivider(),

                // Text color
                _ColorPickerButton(
                  currentColor: widget.currentFormatting.textColor ??
                      widget.baseStyle?.color ??
                      Colors.white,
                  onColorChanged: (color) => _setTextColor(color),
                  isExpanded: _showColorPicker,
                  onToggleExpanded: () => setState(() {
                    _showColorPicker = !_showColorPicker;
                    _showFontSizePicker = false;
                    _showMoreOptions = false;
                  }),
                ),

                _ToolbarDivider(),

                // Link
                _ToolbarButton(
                  icon: Icons.link,
                  tooltip: 'Insertar enlace',
                  isActive: widget.currentFormatting.linkUrl != null,
                  onPressed: () => _showLinkDialog(),
                ),

                if (widget.showAdvancedOptions) ...[
                  _ToolbarDivider(),

                  // More options
                  _ToolbarButton(
                    icon:
                        _showMoreOptions ? Icons.expand_less : Icons.more_horiz,
                    tooltip: 'Más opciones',
                    onPressed: () => setState(() {
                      _showMoreOptions = !_showMoreOptions;
                      _showColorPicker = false;
                      _showFontSizePicker = false;
                    }),
                  ),
                ],
              ],
            ),

            // Font size picker dropdown
            if (_showFontSizePicker)
              _FontSizePickerPanel(
                currentSize: widget.currentFormatting.fontSize ??
                    widget.baseStyle?.fontSize ??
                    16,
                onSizeSelected: (size) {
                  _setFontSize(size);
                  setState(() => _showFontSizePicker = false);
                },
              ),

            // Color picker dropdown
            if (_showColorPicker)
              _ColorPickerPanel(
                currentColor: widget.currentFormatting.textColor ??
                    widget.baseStyle?.color ??
                    Colors.white,
                onColorSelected: (color) {
                  _setTextColor(color);
                  setState(() => _showColorPicker = false);
                },
              ),

            // Advanced options panel
            if (_showMoreOptions)
              _AdvancedOptionsPanel(
                formatting: widget.currentFormatting,
                onFormattingChanged: widget.onFormattingChanged,
              ),
          ],
        ),
      ),
    );
  }

  IconData _getAlignIcon(TextAlign align) {
    switch (align) {
      case TextAlign.center:
        return Icons.format_align_center;
      case TextAlign.right:
      case TextAlign.end:
        return Icons.format_align_right;
      case TextAlign.justify:
        return Icons.format_align_justify;
      default:
        return Icons.format_align_left;
    }
  }

  void _toggleBold() {
    widget.onFormattingChanged(
      widget.currentFormatting
          .copyWith(isBold: !widget.currentFormatting.isBold),
    );
    HapticFeedback.selectionClick();
  }

  void _toggleItalic() {
    widget.onFormattingChanged(
      widget.currentFormatting
          .copyWith(isItalic: !widget.currentFormatting.isItalic),
    );
    HapticFeedback.selectionClick();
  }

  void _toggleUnderline() {
    widget.onFormattingChanged(
      widget.currentFormatting
          .copyWith(isUnderline: !widget.currentFormatting.isUnderline),
    );
    HapticFeedback.selectionClick();
  }

  void _cycleAlignment() {
    final alignments = [
      TextAlign.left,
      TextAlign.center,
      TextAlign.right,
      TextAlign.justify
    ];
    final currentIndex = alignments.indexOf(widget.currentFormatting.textAlign);
    final nextIndex = (currentIndex + 1) % alignments.length;
    widget.onFormattingChanged(
      widget.currentFormatting.copyWith(textAlign: alignments[nextIndex]),
    );
    HapticFeedback.selectionClick();
  }

  void _setFontSize(double size) {
    widget.onFormattingChanged(
      widget.currentFormatting.copyWith(fontSize: size),
    );
  }

  void _setTextColor(Color color) {
    widget.onFormattingChanged(
      widget.currentFormatting.copyWith(textColor: color),
    );
  }

  void _showLinkDialog() {
    final controller =
        TextEditingController(text: widget.currentFormatting.linkUrl ?? '');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Insertar Enlace'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'URL',
            hintText: 'https://ejemplo.com',
            prefixIcon: Icon(Icons.link),
          ),
          autofocus: true,
          keyboardType: TextInputType.url,
        ),
        actions: [
          if (widget.currentFormatting.linkUrl != null)
            TextButton(
              onPressed: () {
                widget.onFormattingChanged(
                  widget.currentFormatting.copyWith(linkUrl: null),
                );
                Navigator.pop(context);
              },
              child: const Text('Eliminar enlace',
                  style: TextStyle(color: Colors.red)),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              final url = controller.text.trim();
              if (url.isNotEmpty) {
                widget.onFormattingChanged(
                  widget.currentFormatting.copyWith(linkUrl: url),
                );
              }
              Navigator.pop(context);
            },
            child: const Text('Aplicar'),
          ),
        ],
      ),
    );
  }
}

/// Individual toolbar button
class _ToolbarButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool isActive;
  final VoidCallback onPressed;

  const _ToolbarButton({
    required this.icon,
    required this.tooltip,
    this.isActive = false,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: isActive ? Colors.blue : Colors.transparent,
        borderRadius: BorderRadius.circular(4),
        child: InkWell(
          canRequestFocus: false,
          onTap: onPressed,
          borderRadius: BorderRadius.circular(4),
          child: Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            child: Icon(
              icon,
              size: 18,
              color: isActive ? Colors.white : Colors.white70,
            ),
          ),
        ),
      ),
    );
  }
}

/// Vertical divider for toolbar
class _ToolbarDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 20,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      color: Colors.white24,
    );
  }
}

/// Font size button with dropdown
class _FontSizeButton extends StatelessWidget {
  final double currentSize;
  final ValueChanged<double> onSizeChanged;
  final bool isExpanded;
  final VoidCallback onToggleExpanded;

  const _FontSizeButton({
    required this.currentSize,
    required this.onSizeChanged,
    required this.isExpanded,
    required this.onToggleExpanded,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Tamaño de fuente',
      child: Material(
        color: isExpanded
            ? Colors.blue.withValues(alpha: 0.3)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(4),
        child: InkWell(
          canRequestFocus: false,
          onTap: onToggleExpanded,
          borderRadius: BorderRadius.circular(4),
          child: Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${currentSize.toInt()}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 2),
                Icon(
                  isExpanded ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                  size: 16,
                  color: Colors.white70,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Font size picker panel
class _FontSizePickerPanel extends StatelessWidget {
  final double currentSize;
  final ValueChanged<double> onSizeSelected;

  const _FontSizePickerPanel({
    required this.currentSize,
    required this.onSizeSelected,
  });

  static const List<double> presetSizes = [
    10,
    12,
    14,
    16,
    18,
    20,
    24,
    28,
    32,
    36,
    42,
    48,
    56,
    64,
    72,
    96
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.grey.shade800,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Preset sizes grid
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: presetSizes.map((size) {
              final isSelected = (currentSize - size).abs() < 0.5;
              return InkWell(
                canRequestFocus: false,
                onTap: () => onSizeSelected(size),
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  width: 36,
                  height: 28,
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.blue : Colors.transparent,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: isSelected ? Colors.blue : Colors.white24,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '${size.toInt()}',
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.white70,
                      fontSize: 12,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 8),

          // Custom size slider
          Row(
            children: [
              const Icon(Icons.text_fields, size: 14, color: Colors.white54),
              const SizedBox(width: 8),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 2,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 6),
                  ),
                  child: Slider(
                    value: currentSize.clamp(8, 120),
                    min: 8,
                    max: 120,
                    divisions: 112,
                    onChanged: onSizeSelected,
                  ),
                ),
              ),
              SizedBox(
                width: 40,
                child: Text(
                  '${currentSize.toInt()}px',
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Color picker button
class _ColorPickerButton extends StatelessWidget {
  final Color currentColor;
  final ValueChanged<Color> onColorChanged;
  final bool isExpanded;
  final VoidCallback onToggleExpanded;

  const _ColorPickerButton({
    required this.currentColor,
    required this.onColorChanged,
    required this.isExpanded,
    required this.onToggleExpanded,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Color de texto',
      child: Material(
        color: isExpanded
            ? Colors.blue.withValues(alpha: 0.3)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(4),
        child: InkWell(
          canRequestFocus: false,
          onTap: onToggleExpanded,
          borderRadius: BorderRadius.circular(4),
          child: Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.format_color_text,
                  size: 16,
                  color: Colors.white70,
                ),
                Container(
                  width: 14,
                  height: 3,
                  decoration: BoxDecoration(
                    color: currentColor,
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Color picker panel
class _ColorPickerPanel extends StatelessWidget {
  final Color currentColor;
  final ValueChanged<Color> onColorSelected;

  const _ColorPickerPanel({
    required this.currentColor,
    required this.onColorSelected,
  });

  static const List<Color> presetColors = [
    Colors.white,
    Color(0xFFF5F5F5),
    Color(0xFFE0E0E0),
    Color(0xFF9E9E9E),
    Color(0xFF616161),
    Color(0xFF212121),
    Colors.black,

    Color(0xFFEF5350), // Red
    Color(0xFFEC407A), // Pink
    Color(0xFFAB47BC), // Purple
    Color(0xFF7E57C2), // Deep Purple
    Color(0xFF5C6BC0), // Indigo
    Color(0xFF42A5F5), // Blue
    Color(0xFF29B6F6), // Light Blue

    Color(0xFF26C6DA), // Cyan
    Color(0xFF26A69A), // Teal
    Color(0xFF66BB6A), // Green
    Color(0xFF9CCC65), // Light Green
    Color(0xFFD4E157), // Lime
    Color(0xFFFFEE58), // Yellow
    Color(0xFFFFCA28), // Amber

    Color(0xFFFFA726), // Orange
    Color(0xFFFF7043), // Deep Orange
    Color(0xFF8D6E63), // Brown
    Color(0xFF78909C), // Blue Grey
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.grey.shade800,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Preset colors grid
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: presetColors.map((color) {
              final isSelected = currentColor.value == color.value;
              return InkWell(
                canRequestFocus: false,
                onTap: () => onColorSelected(color),
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: isSelected ? Colors.blue : Colors.white24,
                      width: isSelected ? 2 : 1,
                    ),
                  ),
                  child: isSelected
                      ? Icon(
                          Icons.check,
                          size: 14,
                          color: color.computeLuminance() > 0.5
                              ? Colors.black
                              : Colors.white,
                        )
                      : null,
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 8),

          // Custom color input
          Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: currentColor,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.white24),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _HexColorInput(
                  color: currentColor,
                  onColorChanged: onColorSelected,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Hex color input field
class _HexColorInput extends StatefulWidget {
  final Color color;
  final ValueChanged<Color> onColorChanged;

  const _HexColorInput({
    required this.color,
    required this.onColorChanged,
  });

  @override
  State<_HexColorInput> createState() => _HexColorInputState();
}

class _HexColorInputState extends State<_HexColorInput> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _colorToHex(widget.color));
  }

  @override
  void didUpdateWidget(_HexColorInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.color != widget.color) {
      _controller.text = _colorToHex(widget.color);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _colorToHex(Color color) {
    return '#${color.value.toRadixString(16).substring(2).toUpperCase()}';
  }

  Color? _hexToColor(String hex) {
    hex = hex.replaceAll('#', '');
    if (hex.length == 6) {
      return Color(int.parse('FF$hex', radix: 16));
    } else if (hex.length == 8) {
      return Color(int.parse(hex, radix: 16));
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      style: const TextStyle(color: Colors.white, fontSize: 12),
      decoration: InputDecoration(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        hintText: '#FFFFFF',
        hintStyle: TextStyle(color: Colors.white38, fontSize: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide(color: Colors.white24),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide(color: Colors.white24),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide(color: Colors.blue),
        ),
      ),
      onSubmitted: (value) {
        final color = _hexToColor(value);
        if (color != null) {
          widget.onColorChanged(color);
        }
      },
    );
  }
}

/// Advanced options panel (letter spacing, line height, etc.)
class _AdvancedOptionsPanel extends StatelessWidget {
  final TextFormatting formatting;
  final ValueChanged<TextFormatting> onFormattingChanged;

  const _AdvancedOptionsPanel({
    required this.formatting,
    required this.onFormattingChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.grey.shade800,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Letter spacing
          _SliderOption(
            label: 'Espaciado de letras',
            icon: Icons.space_bar,
            value: formatting.letterSpacing ?? 0,
            min: -2,
            max: 10,
            onChanged: (value) => onFormattingChanged(
              formatting.copyWith(letterSpacing: value),
            ),
            valueLabel:
                '${(formatting.letterSpacing ?? 0).toStringAsFixed(1)}px',
          ),

          const SizedBox(height: 8),

          // Line height
          _SliderOption(
            label: 'Altura de línea',
            icon: Icons.format_line_spacing,
            value: formatting.lineHeight ?? 1.2,
            min: 0.8,
            max: 3.0,
            onChanged: (value) => onFormattingChanged(
              formatting.copyWith(lineHeight: value),
            ),
            valueLabel: (formatting.lineHeight ?? 1.2).toStringAsFixed(1),
          ),

          const SizedBox(height: 8),

          // Font weight
          _FontWeightSelector(
            currentWeight: formatting.fontWeight,
            onWeightChanged: (weight) => onFormattingChanged(
              formatting.copyWith(fontWeight: weight),
            ),
          ),
        ],
      ),
    );
  }
}

/// Slider option row
class _SliderOption extends StatelessWidget {
  final String label;
  final IconData icon;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final String valueLabel;

  const _SliderOption({
    required this.label,
    required this.icon,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    required this.valueLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: Colors.white54),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(color: Colors.white70, fontSize: 11),
              ),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 2,
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 5),
                ),
                child: Slider(
                  value: value.clamp(min, max),
                  min: min,
                  max: max,
                  onChanged: onChanged,
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          width: 45,
          child: Text(
            valueLabel,
            style: const TextStyle(color: Colors.white70, fontSize: 11),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}

/// Font weight selector
class _FontWeightSelector extends StatelessWidget {
  final FontWeight? currentWeight;
  final ValueChanged<FontWeight?> onWeightChanged;

  const _FontWeightSelector({
    required this.currentWeight,
    required this.onWeightChanged,
  });

  static const Map<FontWeight, String> weights = {
    FontWeight.w100: 'Thin',
    FontWeight.w200: 'ExtraLight',
    FontWeight.w300: 'Light',
    FontWeight.w400: 'Regular',
    FontWeight.w500: 'Medium',
    FontWeight.w600: 'SemiBold',
    FontWeight.w700: 'Bold',
    FontWeight.w800: 'ExtraBold',
    FontWeight.w900: 'Black',
  };

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.format_bold, size: 14, color: Colors.white54),
        const SizedBox(width: 8),
        const Text(
          'Peso de fuente',
          style: TextStyle(color: Colors.white70, fontSize: 11),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: Colors.grey.shade700,
            borderRadius: BorderRadius.circular(4),
          ),
          child: DropdownButton<FontWeight?>(
            value: currentWeight,
            hint: const Text('Normal',
                style: TextStyle(color: Colors.white70, fontSize: 12)),
            dropdownColor: Colors.grey.shade700,
            underline: const SizedBox(),
            isDense: true,
            style: const TextStyle(color: Colors.white, fontSize: 12),
            items: [
              const DropdownMenuItem(
                value: null,
                child: Text('Normal'),
              ),
              ...weights.entries.map((entry) => DropdownMenuItem(
                    value: entry.key,
                    child: Text(entry.value),
                  )),
            ],
            onChanged: onWeightChanged,
          ),
        ),
      ],
    );
  }
}
