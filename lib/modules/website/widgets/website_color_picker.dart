import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

/// Canonical visual color control for the Website Builder.
///
/// The normal workflow is visual: preview, named color, palette, and opacity.
/// The serialized hexadecimal value remains available only inside the advanced
/// section of the picker for compatibility and precise interchange.
class WebsiteColorPickerField extends StatefulWidget {
  const WebsiteColorPickerField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.allowAlpha = true,
    this.allowTransparent = false,
    this.helperText,
    this.palette = websiteEditorColorPalette,
  });

  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  final bool allowAlpha;
  final bool allowTransparent;
  final String? helperText;
  final List<String> palette;

  @override
  State<WebsiteColorPickerField> createState() =>
      _WebsiteColorPickerFieldState();
}

const List<String> websiteEditorColorPalette = [
  '#FFFFFF',
  '#F7F7F5',
  '#E8E6DF',
  '#B9B8B2',
  '#5B625F',
  '#202725',
  '#08100D',
  '#000000',
  '#00A09D',
  '#0F4C5C',
  '#2F6B4F',
  '#D96B3B',
  '#F0642F',
  '#D9A441',
  '#A33A32',
  '#66507A',
];

class _WebsiteColorPickerFieldState extends State<WebsiteColorPickerField> {
  static final LinkedHashSet<String> _recentColors = LinkedHashSet<String>();

  Color get _currentColor => parseWebsiteEditorColor(widget.value);

  void _remember(Color color) {
    final serialized = serializeWebsiteEditorColor(
      color,
      includeAlpha: widget.allowAlpha,
    );
    _recentColors.remove(serialized);
    _recentColors.add(serialized);
    while (_recentColors.length > 8) {
      _recentColors.remove(_recentColors.first);
    }
  }

  void _changeOpacity(double opacity) {
    final next = _currentColor.withValues(alpha: opacity.clamp(0.0, 1.0));
    _remember(next);
    widget.onChanged(
      serializeWebsiteEditorColor(next, includeAlpha: widget.allowAlpha),
    );
  }

  Future<void> _openPicker() async {
    var draft = _currentColor;
    if (!widget.allowAlpha) draft = draft.withValues(alpha: 1);
    final codeController = TextEditingController(
      text: serializeWebsiteEditorColor(
        draft,
        includeAlpha: widget.allowAlpha,
      ),
    );

    final selected = await showDialog<Color>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          void setDraft(Color color) {
            setDialogState(() {
              draft = widget.allowAlpha ? color : color.withValues(alpha: 1);
              codeController.text = serializeWebsiteEditorColor(
                draft,
                includeAlpha: widget.allowAlpha,
              );
            });
          }

          final recent = _recentColors.toList().reversed.toList();
          final opacity = websiteEditorColorOpacity(draft);

          return Dialog(
            backgroundColor: const Color(0xFF202221),
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: Colors.white12),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460, maxHeight: 720),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 16, 10, 12),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.palette_outlined,
                          color: Color(0xFF20C5C1),
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.label,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const Text(
                                'Selecciona visualmente el color y su intensidad.',
                                style: TextStyle(
                                  color: Colors.white54,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Cerrar',
                          onPressed: () => Navigator.of(dialogContext).pop(),
                          icon: const Icon(Icons.close, color: Colors.white60),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1, color: Colors.white12),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _ColorPreviewRow(color: draft),
                          const SizedBox(height: 16),
                          const _PickerSectionLabel('Paleta del sitio'),
                          const SizedBox(height: 8),
                          _ColorSwatchGrid(
                            colors: widget.palette,
                            selected: draft,
                            onSelected: setDraft,
                          ),
                          if (recent.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            const _PickerSectionLabel('Usados recientemente'),
                            const SizedBox(height: 8),
                            _ColorSwatchGrid(
                              colors: recent,
                              selected: draft,
                              onSelected: setDraft,
                            ),
                          ],
                          const SizedBox(height: 18),
                          ColorPicker(
                            pickerColor: draft,
                            onColorChanged: (color) => setDraft(
                              color.withValues(
                                alpha: opacity == 0 ? 1 : opacity,
                              ),
                            ),
                            enableAlpha: false,
                            displayThumbColor: true,
                            paletteType: PaletteType.hsvWithHue,
                            pickerAreaHeightPercent: 0.68,
                            labelTypes: const [],
                            hexInputBar: false,
                            portraitOnly: true,
                          ),
                          if (widget.allowAlpha) ...[
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Expanded(
                                  child: Text(
                                    'Opacidad',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                                Text(
                                  '${(opacity * 100).round()}%',
                                  style: const TextStyle(
                                    color: Color(0xFF20C5C1),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            Slider(
                              key: const ValueKey(
                                'website_color_picker_dialog_opacity',
                              ),
                              value: opacity,
                              onChanged: (value) => setDraft(
                                draft.withValues(alpha: value),
                              ),
                            ),
                          ],
                          if (widget.allowTransparent) ...[
                            const SizedBox(height: 6),
                            OutlinedButton.icon(
                              onPressed: () =>
                                  setDraft(draft.withValues(alpha: 0)),
                              icon: const Icon(Icons.block, size: 16),
                              label: const Text('Sin color'),
                            ),
                          ],
                          const SizedBox(height: 8),
                          Theme(
                            data: Theme.of(context).copyWith(
                              dividerColor: Colors.transparent,
                            ),
                            child: ExpansionTile(
                              key: const ValueKey(
                                'website_color_picker_advanced',
                              ),
                              tilePadding: EdgeInsets.zero,
                              childrenPadding: const EdgeInsets.only(bottom: 8),
                              title: const Text(
                                'Código avanzado',
                                style: TextStyle(
                                  color: Colors.white60,
                                  fontSize: 12,
                                ),
                              ),
                              children: [
                                TextField(
                                  controller: codeController,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontFamily: 'monospace',
                                    fontSize: 12,
                                  ),
                                  decoration: InputDecoration(
                                    labelText: widget.allowAlpha
                                        ? '#AARRGGBB o #RRGGBB'
                                        : '#RRGGBB',
                                    helperText:
                                        'Sólo para copiar o introducir un código exacto.',
                                    filled: true,
                                    fillColor: Colors.black26,
                                    border: const OutlineInputBorder(),
                                  ),
                                  onChanged: (value) {
                                    final parsed = tryParseWebsiteEditorColor(
                                      value,
                                    );
                                    if (parsed != null) {
                                      setDialogState(() {
                                        draft = widget.allowAlpha
                                            ? parsed
                                            : parsed.withValues(alpha: 1);
                                      });
                                    }
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Divider(height: 1, color: Colors.white12),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.of(dialogContext).pop(),
                          child: const Text('Cancelar'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          key: const ValueKey('website_color_picker_apply'),
                          onPressed: () =>
                              Navigator.of(dialogContext).pop(draft),
                          child: const Text('Aplicar'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    codeController.dispose();
    if (selected == null || !mounted) return;
    _remember(selected);
    widget.onChanged(
      serializeWebsiteEditorColor(
        selected,
        includeAlpha: widget.allowAlpha,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = _currentColor;
    final opacity = websiteEditorColorOpacity(color);
    final helperText = widget.helperText;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 7),
        Semantics(
          button: true,
          label: 'Elegir ${widget.label}',
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              key: ValueKey('website_color_picker_${widget.label}'),
              onTap: _openPicker,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF2D2D2D),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(
                  children: [
                    _CheckerboardSwatch(color: color, size: 38),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            websiteEditorColorName(color),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Text(
                            widget.allowAlpha
                                ? 'Opacidad ${(opacity * 100).round()}%'
                                : 'Color sólido',
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.tune_rounded,
                      color: Color(0xFF20C5C1),
                      size: 18,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (widget.allowAlpha) ...[
          const SizedBox(height: 7),
          Row(
            children: [
              const SizedBox(
                width: 66,
                child: Text(
                  'Opacidad',
                  style: TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ),
              Expanded(
                child: Slider(
                  key: ValueKey(
                    'website_color_opacity_${widget.label}',
                  ),
                  value: opacity,
                  onChanged: _changeOpacity,
                ),
              ),
              SizedBox(
                width: 38,
                child: Text(
                  '${(opacity * 100).round()}%',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    color: Color(0xFF20C5C1),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
        if (helperText != null && helperText.trim().isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            helperText,
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 11,
              height: 1.3,
            ),
          ),
        ],
      ],
    );
  }
}

class _PickerSectionLabel extends StatelessWidget {
  const _PickerSectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Text(
        label.toUpperCase(),
        style: const TextStyle(
          color: Colors.white54,
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.8,
        ),
      );
}

class _ColorSwatchGrid extends StatelessWidget {
  const _ColorSwatchGrid({
    required this.colors,
    required this.selected,
    required this.onSelected,
  });

  final List<String> colors;
  final Color selected;
  final ValueChanged<Color> onSelected;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: colors.map((raw) {
          final color = parseWebsiteEditorColor(raw);
          final isSelected = (selected.toARGB32() & 0x00FFFFFF) ==
              (color.toARGB32() & 0x00FFFFFF);
          return Tooltip(
            message: websiteEditorColorName(color),
            child: InkWell(
              key: ValueKey('website_color_swatch_$raw'),
              onTap: () {
                final opacity = websiteEditorColorOpacity(selected);
                onSelected(
                  color.withValues(alpha: opacity == 0 ? 1 : opacity),
                );
              },
              borderRadius: BorderRadius.circular(7),
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(
                    color:
                        isSelected ? const Color(0xFF20C5C1) : Colors.white24,
                    width: isSelected ? 2 : 1,
                  ),
                ),
                child: isSelected
                    ? Icon(
                        Icons.check,
                        size: 16,
                        color: color.computeLuminance() > .5
                            ? Colors.black
                            : Colors.white,
                      )
                    : null,
              ),
            ),
          );
        }).toList(),
      );
}

class _ColorPreviewRow extends StatelessWidget {
  const _ColorPreviewRow({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          _CheckerboardSwatch(color: color, size: 52),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  websiteEditorColorName(color),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  'Opacidad ${(websiteEditorColorOpacity(color) * 100).round()}%',
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      );
}

class _CheckerboardSwatch extends StatelessWidget {
  const _CheckerboardSwatch({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(7),
        child: SizedBox(
          width: size,
          height: size,
          child: CustomPaint(
            painter: const _CheckerboardPainter(),
            child: ColoredBox(color: color),
          ),
        ),
      );
}

class _CheckerboardPainter extends CustomPainter {
  const _CheckerboardPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const cell = 6.0;
    final light = Paint()..color = const Color(0xFFE7E7E7);
    final dark = Paint()..color = const Color(0xFFBDBDBD);
    for (var y = 0.0; y < size.height; y += cell) {
      for (var x = 0.0; x < size.width; x += cell) {
        final even = ((x / cell).floor() + (y / cell).floor()).isEven;
        canvas.drawRect(
          Rect.fromLTWH(x, y, cell, cell),
          even ? light : dark,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

Color parseWebsiteEditorColor(String? raw) =>
    tryParseWebsiteEditorColor(raw) ?? const Color(0xFF808080);

Color? tryParseWebsiteEditorColor(String? raw) {
  if (raw == null) return null;
  var value = raw.trim().replaceFirst('#', '');
  if (value.length == 3) {
    value = value.split('').map((part) => '$part$part').join();
  }
  if (value.length == 6) value = 'FF$value';
  if (value.length != 8) return null;
  final parsed = int.tryParse(value, radix: 16);
  return parsed == null ? null : Color(parsed);
}

String serializeWebsiteEditorColor(
  Color color, {
  bool includeAlpha = true,
}) {
  final argb = color.toARGB32();
  final alpha = (argb >> 24) & 0xFF;
  if (includeAlpha && alpha < 255) {
    return '#${argb.toRadixString(16).padLeft(8, '0').toUpperCase()}';
  }
  final rgb = argb & 0x00FFFFFF;
  return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

double websiteEditorColorOpacity(Color color) =>
    ((color.toARGB32() >> 24) & 0xFF) / 255;

String websiteEditorColorName(Color color) {
  final opacity = websiteEditorColorOpacity(color);
  if (opacity == 0) return 'Transparente';

  final hsv = HSVColor.fromColor(color);
  if (hsv.saturation < .08) {
    if (hsv.value > .94) return 'Blanco';
    if (hsv.value > .72) return 'Gris claro';
    if (hsv.value > .35) return 'Gris';
    if (hsv.value > .12) return 'Gris oscuro';
    return 'Negro';
  }

  final hue = hsv.hue;
  if (hue < 15 || hue >= 345) return 'Rojo';
  if (hue < 45) return 'Naranja';
  if (hue < 70) return 'Amarillo';
  if (hue < 155) return 'Verde';
  if (hue < 190) return 'Turquesa';
  if (hue < 255) return 'Azul';
  if (hue < 290) return 'Violeta';
  if (hue < 345) return 'Rosa';
  return 'Color personalizado';
}
