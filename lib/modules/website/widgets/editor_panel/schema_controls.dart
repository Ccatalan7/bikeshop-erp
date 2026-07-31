part of '../website_editor_panel.dart';

/// CTA block controls
/// Generic block controls for types without specific UI
typedef _RepeaterItemEditorBuilder = Widget Function(
  BuildContext context,
  int index,
  Map<String, dynamic> item,
  ValueChanged<Map<String, dynamic>> onChanged,
);

/// Compact, shared inspector for schema-defined collections.
///
/// A collection can contain many rich items (images, focal points, actions,
/// nested collections, and so on). Rendering every item form at once makes the
/// inspector impossible to scan, so this control keeps the collection overview
/// visible while editing exactly one item at a time.
class _SchemaRepeaterEditor extends StatefulWidget {
  const _SchemaRepeaterEditor({
    required this.field,
    required this.items,
    required this.onChanged,
    required this.itemBuilder,
  });

  final WebsiteBlockFieldSchema field;
  final List<Map<String, dynamic>> items;
  final ValueChanged<List<Map<String, dynamic>>> onChanged;
  final _RepeaterItemEditorBuilder itemBuilder;

  @override
  State<_SchemaRepeaterEditor> createState() => _SchemaRepeaterEditorState();
}

class _SchemaRepeaterEditorState extends State<_SchemaRepeaterEditor> {
  int _selectedIndex = 0;

  @override
  void didUpdateWidget(covariant _SchemaRepeaterEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.items.isEmpty) {
      _selectedIndex = 0;
    } else if (_selectedIndex >= widget.items.length) {
      _selectedIndex = widget.items.length - 1;
    }
  }

  String _itemTitle(Map<String, dynamic> item, int index) {
    const preferredKeys = [
      'title',
      'name',
      'question',
      'label',
      'heading',
      'value',
    ];
    for (final key in preferredKeys) {
      final value = item[key]?.toString().trim() ?? '';
      if (value.isNotEmpty) return value;
    }
    return '${widget.field.itemLabel ?? 'Item'} ${index + 1}';
  }

  void _selectAfterChange(int index) {
    setState(() => _selectedIndex = index < 0 ? 0 : index);
  }

  void _addItem() {
    final next = List<Map<String, dynamic>>.from(widget.items);
    final seed = <String, dynamic>{};
    for (final field in widget.field.itemFields) {
      seed[field.key] = field.defaultValue;
    }
    next.add(seed);
    widget.onChanged(next);
    _selectAfterChange(next.length - 1);
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    final canAdd =
        widget.field.maxItems == null || items.length < widget.field.maxItems!;
    final safeIndex =
        items.isEmpty ? 0 : _selectedIndex.clamp(0, items.length - 1).toInt();
    const accent = Color(0xFF20C5C1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                widget.field.label,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${items.length}',
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
            ),
            const SizedBox(width: 6),
            IconButton(
              tooltip: 'Agregar ${widget.field.itemLabel ?? 'item'}',
              visualDensity: VisualDensity.compact,
              iconSize: 18,
              color: accent,
              onPressed: canAdd ? _addItem : null,
              icon: const Icon(Icons.add_circle_outline_rounded),
            ),
          ],
        ),
        if (items.isEmpty) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.025),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Column(
              children: [
                const Text(
                  'Todavía no hay elementos',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
                if (canAdd) ...[
                  const SizedBox(height: 8),
                  _AddItemButton(
                    label: 'Agregar ${widget.field.itemLabel ?? 'item'}',
                    onPressed: _addItem,
                  ),
                ],
              ],
            ),
          ),
        ] else ...[
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: List.generate(items.length, (index) {
                final selected = index == safeIndex;
                return Padding(
                  padding: EdgeInsets.only(
                    right: index == items.length - 1 ? 0 : 6,
                  ),
                  child: Tooltip(
                    message: _itemTitle(items[index], index),
                    child: Material(
                      color: selected
                          ? accent.withValues(alpha: 0.16)
                          : Colors.white.withValues(alpha: 0.045),
                      borderRadius: BorderRadius.circular(8),
                      child: InkWell(
                        onTap: () => setState(() => _selectedIndex = index),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          constraints: const BoxConstraints(
                            minWidth: 42,
                            maxWidth: 132,
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: selected
                                  ? accent.withValues(alpha: 0.65)
                                  : Colors.white.withValues(alpha: 0.08),
                            ),
                          ),
                          child: Text(
                            '${index + 1}  ${_itemTitle(items[index], index)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: selected ? Colors.white : Colors.white60,
                              fontSize: 11.5,
                              fontWeight:
                                  selected ? FontWeight.w600 : FontWeight.w400,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            decoration: BoxDecoration(
              color: const Color(0xFF292929),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _itemTitle(items[safeIndex], safeIndex),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Mover hacia arriba',
                      visualDensity: VisualDensity.compact,
                      iconSize: 16,
                      onPressed: safeIndex > 0
                          ? () {
                              final next =
                                  List<Map<String, dynamic>>.from(items);
                              final previous = next[safeIndex - 1];
                              next[safeIndex - 1] = next[safeIndex];
                              next[safeIndex] = previous;
                              widget.onChanged(next);
                              _selectAfterChange(safeIndex - 1);
                            }
                          : null,
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                    IconButton(
                      tooltip: 'Mover hacia abajo',
                      visualDensity: VisualDensity.compact,
                      iconSize: 16,
                      onPressed: safeIndex < items.length - 1
                          ? () {
                              final next =
                                  List<Map<String, dynamic>>.from(items);
                              final following = next[safeIndex + 1];
                              next[safeIndex + 1] = next[safeIndex];
                              next[safeIndex] = following;
                              widget.onChanged(next);
                              _selectAfterChange(safeIndex + 1);
                            }
                          : null,
                      icon: const Icon(Icons.arrow_forward_rounded),
                    ),
                    IconButton(
                      tooltip: 'Duplicar',
                      visualDensity: VisualDensity.compact,
                      iconSize: 16,
                      onPressed: canAdd
                          ? () {
                              final next =
                                  List<Map<String, dynamic>>.from(items)
                                    ..insert(
                                      safeIndex + 1,
                                      Map<String, dynamic>.from(
                                        items[safeIndex],
                                      ),
                                    );
                              widget.onChanged(next);
                              _selectAfterChange(safeIndex + 1);
                            }
                          : null,
                      icon: const Icon(Icons.copy_outlined),
                    ),
                    IconButton(
                      tooltip: 'Eliminar',
                      visualDensity: VisualDensity.compact,
                      iconSize: 16,
                      color: Colors.red.shade300,
                      onPressed: widget.field.minItems == null ||
                              items.length > widget.field.minItems!
                          ? () {
                              final next =
                                  List<Map<String, dynamic>>.from(items)
                                    ..removeAt(safeIndex);
                              widget.onChanged(next);
                              _selectAfterChange(
                                next.isEmpty
                                    ? 0
                                    : safeIndex.clamp(0, next.length - 1),
                              );
                            }
                          : null,
                      icon: const Icon(Icons.delete_outline_rounded),
                    ),
                  ],
                ),
                const Divider(height: 14, color: Colors.white10),
                widget.itemBuilder(
                  context,
                  safeIndex,
                  items[safeIndex],
                  (nextItem) {
                    final next = List<Map<String, dynamic>>.from(items);
                    next[safeIndex] = nextItem;
                    widget.onChanged(next);
                  },
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _GenericBlockControls extends StatelessWidget {
  final Map<String, dynamic> data;
  final String blockId;
  final WebsiteEditModeProvider provider;
  final WebsiteBlockType? blockType;
  final String? rawBlockType;

  const _GenericBlockControls({
    required this.data,
    required this.blockId,
    required this.provider,
    required this.blockType,
    required this.rawBlockType,
  });

  List<String> _toStringList(dynamic value) {
    if (value is List) {
      return value
          .map((e) => e?.toString() ?? '')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    if (value is String) {
      return value
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    return const [];
  }

  List<Map<String, dynamic>> _toMapList(dynamic value) {
    if (value is List) {
      return value
          .map((item) => item is Map
              ? Map<String, dynamic>.from(item)
              : <String, dynamic>{'label': item.toString()})
          .toList();
    }
    return const [];
  }

  Widget _helpText(String? text) {
    if (text == null || text.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        text,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.45),
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _buildTextFormattingInspector({
    required WebsiteBlockFieldSchema field,
    required Map<String, dynamic> currentData,
    required void Function(String key, dynamic value) setRelatedValue,
  }) {
    if (!field.supportsFormatting) return const SizedBox.shrink();

    final rawFormatting = currentData[field.resolvedFormattingKey];
    final formatting = TextFormatting.fromJson(
      rawFormatting is Map ? Map<String, dynamic>.from(rawFormatting) : null,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 10),
        const _SectionHeader('Formato'),
        const SizedBox(height: 8),
        TextFormattingToolbar(
          currentFormatting: formatting,
          preset: TextToolbarPreset.basic,
          showAdvancedOptions: false,
          onFormattingChanged: (value) => setRelatedValue(
            field.resolvedFormattingKey,
            value.toJson(),
          ),
        ),
      ],
    );
  }

  Widget _buildSchemaField({
    required BuildContext context,
    required WebsiteBlockFieldSchema field,
    required Map<String, dynamic> currentData,
    required void Function(dynamic value) setValue,
    required void Function(String key, dynamic value) setRelatedValue,
    required void Function(Map<String, dynamic> values) setRelatedValues,
    WebsiteBlockFieldSchema? actionLabelField,
  }) {
    dynamic raw = currentData[field.key];
    for (final alias in field.migrationAliases) {
      raw ??= currentData[alias];
    }
    final label = field.label;

    switch (field.type) {
      case WebsiteBlockFieldType.text:
        if (field.key == 'videoUrl') {
          final current =
              raw?.toString() ?? (field.defaultValue?.toString() ?? '');
          return _CollapsibleSection(
            title: 'YouTube / enlace avanzado',
            icon: Icons.link_rounded,
            initiallyExpanded: current.trim().isNotEmpty,
            children: [
              _EditorTextField(
                label: label,
                value: current,
                onChanged: (v) {
                  setValue(v);
                  if (v.trim().isNotEmpty &&
                      currentData.containsKey('videoFileUrl')) {
                    provider.updateBlockData(blockId, 'videoFileUrl', '');
                  }
                },
              ),
              _helpText(field.helpText),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _EditorTextField(
              label: label,
              value: raw?.toString() ?? (field.defaultValue?.toString() ?? ''),
              onChanged: (v) => setValue(v),
            ),
            _buildTextFormattingInspector(
              field: field,
              currentData: currentData,
              setRelatedValue: setRelatedValue,
            ),
            _helpText(field.helpText),
          ],
        );
      case WebsiteBlockFieldType.textarea:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _EditorTextField(
              label: label,
              value: raw?.toString() ?? (field.defaultValue?.toString() ?? ''),
              onChanged: (v) => setValue(v),
              maxLines: 4,
            ),
            _buildTextFormattingInspector(
              field: field,
              currentData: currentData,
              setRelatedValue: setRelatedValue,
            ),
            _helpText(field.helpText),
          ],
        );
      case WebsiteBlockFieldType.richtext:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _EditorTextField(
              label: label,
              value: raw?.toString() ?? (field.defaultValue?.toString() ?? ''),
              onChanged: (v) => setValue(v),
              maxLines: 6,
              hint: '<p>...</p>',
            ),
            _helpText(field.helpText ?? 'Acepta HTML.'),
          ],
        );
      case WebsiteBlockFieldType.link:
        final current =
            raw?.toString() ?? (field.defaultValue?.toString() ?? '');
        final actionLabelKey = field.actionLabelKey;
        if (actionLabelKey != null) {
          final labelKeys = <String>[
            actionLabelKey,
            ...?actionLabelField?.migrationAliases,
          ];
          final hrefKeys = <String>[field.key, ...field.migrationAliases];
          final label = labelKeys
              .map((key) => currentData[key]?.toString().trim() ?? '')
              .firstWhere((value) => value.isNotEmpty, orElse: () => 'Ver más');
          final variantKey = field.actionVariantKey;
          final fallbackVariant = WebsiteActionVariant.fromStorage(
            variantKey == null ? null : currentData[variantKey]?.toString(),
          );
          final action = WebsiteActionValue.resolvePrimary(
                currentData,
                labelKeys: labelKeys,
                hrefKeys: hrefKeys,
                variantKeys:
                    variantKey == null ? const ['actionVariant'] : [variantKey],
                defaultLabel: label,
                defaultHref: current,
                defaultVariant: fallbackVariant,
              ) ??
              WebsiteActionValue(
                label: label,
                href: current,
                variant: fallbackVariant,
              );

          return WebsiteActionEditor(
            value: action,
            darkStyle: true,
            dense: true,
            showVariant: variantKey != null,
            onChanged: (next) {
              final updates = <String, dynamic>{
                field.key: next.href,
                actionLabelKey: next.label,
              };
              for (final alias in field.migrationAliases) {
                updates[alias] = next.href;
              }
              for (final alias
                  in actionLabelField?.migrationAliases ?? const <String>[]) {
                updates[alias] = next.label;
              }
              if (variantKey != null) {
                updates[variantKey] = next.variant.storageValue;
              }
              updates['actions'] = WebsiteActionValue.mergePrimary(
                currentData['actions'],
                next,
              );
              setRelatedValues(updates);
            },
          );
        }
        return WebsiteLinkValueEditor(
          label: label,
          value: current,
          helpText: field.helpText,
          dense: true,
          darkStyle: true,
          onChanged: (v) => setValue(v),
        );
      case WebsiteBlockFieldType.color:
        final current =
            raw?.toString() ?? (field.defaultValue?.toString() ?? '');
        return WebsiteColorPickerField(
          label: label,
          value: current.isEmpty ? '#000000' : current,
          helperText: field.helpText,
          allowAlpha: true,
          onChanged: (value) => setValue(value),
        );
      case WebsiteBlockFieldType.image:
        final currentUrl = raw?.toString();
        final focalX =
            (currentData[field.focalPointXKey] as num?)?.toDouble() ?? 0.5;
        final focalY =
            (currentData[field.focalPointYKey] as num?)?.toDouble() ?? 0.5;
        final mobileFocalX =
            (currentData[field.mobileFocalPointXKey] as num?)?.toDouble() ??
                focalX;
        final mobileFocalY =
            (currentData[field.mobileFocalPointYKey] as num?)?.toDouble() ??
                focalY;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 8),
            _ImagePicker(
              currentUrl: currentUrl,
              onChanged: (url) => setValue(url),
            ),
            if (field.hasFocalPointControl &&
                currentUrl?.isNotEmpty == true) ...[
              const SizedBox(height: 12),
              const _SectionHeader('Foco de imagen'),
              const SizedBox(height: 8),
              FocalPointPicker(
                imageUrl: currentUrl,
                focalX: focalX,
                focalY: focalY,
                onChanged: (x, y) {
                  setRelatedValue(field.focalPointXKey, x);
                  setRelatedValue(field.focalPointYKey, y);
                },
              ),
              if (field.isCoverMedia) ...[
                const SizedBox(height: 12),
                const _SectionHeader('Foco móvil'),
                const SizedBox(height: 8),
                FocalPointPicker(
                  imageUrl: currentUrl,
                  focalX: mobileFocalX,
                  focalY: mobileFocalY,
                  onChanged: (x, y) {
                    setRelatedValue(field.mobileFocalPointXKey, x);
                    setRelatedValue(field.mobileFocalPointYKey, y);
                  },
                ),
              ],
            ],
            if (field.hasAltTextControl) ...[
              const SizedBox(height: 12),
              _EditorTextField(
                label: 'Texto alternativo',
                value: currentData[field.altTextKey]?.toString() ?? '',
                hint: 'Describe la imagen',
                onChanged: (value) => setRelatedValue(field.altTextKey, value),
              ),
            ],
            _helpText(field.helpText),
          ],
        );
      case WebsiteBlockFieldType.video:
        final currentUrl = raw?.toString();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 8),
            _VideoPicker(
              currentUrl: currentUrl,
              onChanged: (url) {
                setValue(url);
                if (field.key == 'videoFileUrl' && url.trim().isNotEmpty) {
                  // If uploading a file, clear any YouTube URL.
                  provider.updateBlockData(blockId, 'videoUrl', '');
                }
              },
            ),
            _helpText(field.helpText),
          ],
        );
      case WebsiteBlockFieldType.number:
        final min = field.min?.toDouble();
        final max = field.max?.toDouble();
        final step = field.step?.toDouble();
        final currentNum = (raw is num)
            ? raw.toDouble()
            : double.tryParse(raw?.toString() ?? '') ??
                (field.defaultValue is num
                    ? (field.defaultValue as num).toDouble()
                    : 0.0);

        if (min != null && max != null) {
          int? divisions;
          if (step != null && step > 0) {
            final rawDiv = ((max - min) / step).round();
            if (rawDiv > 0 && rawDiv <= 200) divisions = rawDiv;
          }
          final clamped = currentNum.clamp(min, max);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _EditorSlider(
                label: label,
                value: clamped,
                min: min,
                max: max,
                divisions: divisions,
                valueLabel: clamped.toStringAsFixed(0),
                onChanged: (v) => setValue(v),
              ),
              _helpText(field.helpText),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _EditorTextField(
              label: label,
              value: raw?.toString() ?? (field.defaultValue?.toString() ?? ''),
              hint: '0',
              onChanged: (v) {
                final parsed = num.tryParse(v);
                if (parsed != null) setValue(parsed);
              },
            ),
            _helpText(field.helpText),
          ],
        );
      case WebsiteBlockFieldType.toggle:
        final currentBool =
            (raw is bool) ? raw : (raw?.toString().toLowerCase() == 'true');
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _EditorToggle(
              label: label,
              value: currentBool,
              onChanged: (v) => setValue(v),
            ),
            _helpText(field.helpText),
          ],
        );
      case WebsiteBlockFieldType.select:
        final options = field.options
            .map((opt) => (opt.value, opt.label))
            .toList(growable: false);
        final current = raw?.toString() ??
            (field.defaultValue?.toString() ??
                (options.isNotEmpty ? options.first.$1 : ''));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _EditorDropdown(
              label: label,
              value: current,
              options: options,
              onChanged: (v) => setValue(v),
            ),
            _helpText(field.helpText),
          ],
        );
      case WebsiteBlockFieldType.chips:
        final chips = _toStringList(raw);
        final display = chips.join(', ');
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _EditorTextField(
              label: label,
              value: display,
              hint: 'separado por comas',
              onChanged: (v) {
                final parsed = _toStringList(v);
                setValue(parsed);
              },
              maxLines: 2,
            ),
            _helpText(field.helpText),
          ],
        );
      case WebsiteBlockFieldType.repeater:
        final items = _toMapList(raw);
        final actionLabelKeys = field.itemFields
            .where((itemField) => itemField.actionLabelKey != null)
            .map((itemField) => itemField.actionLabelKey!)
            .toSet();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SchemaRepeaterEditor(
              field: field,
              items: items,
              onChanged: (next) => setValue(next),
              itemBuilder: (
                context,
                index,
                itemData,
                onItemChanged,
              ) {
                final visibleFields = field.itemFields
                    .where(
                      (subField) => !actionLabelKeys.contains(subField.key),
                    )
                    .toList();
                final contentFields = <WebsiteBlockFieldSchema>[];
                final mediaFields = <WebsiteBlockFieldSchema>[];
                final actionFields = <WebsiteBlockFieldSchema>[];
                final collectionFields = <WebsiteBlockFieldSchema>[];
                final optionFields = <WebsiteBlockFieldSchema>[];

                for (final subField in visibleFields) {
                  if (subField.type == WebsiteBlockFieldType.image ||
                      subField.type == WebsiteBlockFieldType.video) {
                    mediaFields.add(subField);
                  } else if (subField.type == WebsiteBlockFieldType.link) {
                    actionFields.add(subField);
                  } else if (subField.type == WebsiteBlockFieldType.repeater) {
                    collectionFields.add(subField);
                  } else if (subField.group == 'style' ||
                      subField.group == 'layout' ||
                      subField.type == WebsiteBlockFieldType.color) {
                    optionFields.add(subField);
                  } else {
                    contentFields.add(subField);
                  }
                }

                Widget buildSubField(WebsiteBlockFieldSchema subField) {
                  WebsiteBlockFieldSchema? actionLabelField;
                  final actionLabelKey = subField.actionLabelKey;
                  if (actionLabelKey != null) {
                    for (final candidate in field.itemFields) {
                      if (candidate.key == actionLabelKey) {
                        actionLabelField = candidate;
                        break;
                      }
                    }
                  }

                  void updateValue(dynamic value) {
                    final nextItem = Map<String, dynamic>.from(itemData);
                    nextItem[subField.key] = value;
                    for (final alias in subField.migrationAliases) {
                      nextItem[alias] = value;
                    }
                    onItemChanged(nextItem);
                  }

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _buildSchemaField(
                      context: context,
                      field: subField,
                      currentData: itemData,
                      setValue: updateValue,
                      setRelatedValue: (key, value) {
                        final nextItem = Map<String, dynamic>.from(itemData);
                        nextItem[key] = value;
                        onItemChanged(nextItem);
                      },
                      setRelatedValues: (values) {
                        final nextItem = Map<String, dynamic>.from(itemData)
                          ..addAll(values);
                        onItemChanged(nextItem);
                      },
                      actionLabelField: actionLabelField,
                    ),
                  );
                }

                Widget buildGroup({
                  required String title,
                  required IconData icon,
                  required List<WebsiteBlockFieldSchema> fields,
                  required bool expanded,
                }) {
                  return _CollapsibleSection(
                    title: title,
                    icon: icon,
                    initiallyExpanded: expanded,
                    children: fields.map(buildSubField).toList(),
                  );
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (contentFields.isNotEmpty)
                      buildGroup(
                        title: 'Texto y datos',
                        icon: Icons.text_fields_rounded,
                        fields: contentFields,
                        expanded: true,
                      ),
                    if (mediaFields.isNotEmpty)
                      buildGroup(
                        title: 'Imagen y medios',
                        icon: Icons.image_outlined,
                        fields: mediaFields,
                        expanded: false,
                      ),
                    if (actionFields.isNotEmpty)
                      buildGroup(
                        title: 'Acción y enlace',
                        icon: Icons.ads_click_rounded,
                        fields: actionFields,
                        expanded: false,
                      ),
                    if (collectionFields.isNotEmpty)
                      buildGroup(
                        title: 'Elementos relacionados',
                        icon: Icons.format_list_bulleted_rounded,
                        fields: collectionFields,
                        expanded: false,
                      ),
                    if (optionFields.isNotEmpty)
                      buildGroup(
                        title: 'Opciones',
                        icon: Icons.tune_rounded,
                        fields: optionFields,
                        expanded: false,
                      ),
                  ],
                );
              },
            ),
            _helpText(field.helpText),
          ],
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final parsed = blockType;
    final definition =
        parsed != null ? WebsiteBlockRegistry.definitionFor(parsed) : null;
    final fields = definition?.fields ?? const <WebsiteBlockFieldSchema>[];

    void setFieldValue(String key, dynamic value) {
      provider.updateBlockData(blockId, key, value);

      // Backwards compatibility: historically CTA subtitle lived under
      // 'description'. Keep them in sync so older renderers/data don't drift.
      if (rawBlockType == 'cta' && key == 'subtitle') {
        provider.updateBlockData(blockId, 'description', value);
      }
    }

    void setSchemaFieldValue(WebsiteBlockFieldSchema field, dynamic value) {
      provider.updateBlockDataMultiple(
        blockId,
        <String, dynamic>{
          field.key: value,
          for (final alias in field.migrationAliases) alias: value,
          if (rawBlockType == 'cta' && field.key == 'subtitle')
            'description': value,
        },
      );
    }

    if (definition != null && fields.isNotEmpty) {
      final sections = definition.controlSections;
      final fieldByKey = {for (final f in fields) f.key: f};
      final actionLabelKeys = fields
          .where((field) => field.actionLabelKey != null)
          .map((field) => field.actionLabelKey!)
          .toSet();
      final usedKeys = <String>{};

      final sectionWidgets = <Widget>[];
      if (sections.isNotEmpty) {
        for (final section in sections) {
          final allSectionFields = section.fieldKeys
              .map((k) => fieldByKey[k])
              .whereType<WebsiteBlockFieldSchema>()
              .toList();
          final sectionFields = allSectionFields
              .where((field) => !actionLabelKeys.contains(field.key))
              .toList();

          if (sectionFields.isEmpty) continue;
          usedKeys.addAll(allSectionFields.map((f) => f.key));
          final isFirstVisibleSection = sectionWidgets.isEmpty;

          sectionWidgets.add(
            _CollapsibleSection(
              title: section.label,
              initiallyExpanded: isFirstVisibleSection,
              children: [
                if (section.description != null &&
                    section.description!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      section.description!,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 12,
                      ),
                    ),
                  ),
                ...sectionFields.expand((f) sync* {
                  yield _buildSchemaField(
                    context: context,
                    field: f,
                    currentData: data,
                    setValue: (v) => setSchemaFieldValue(f, v),
                    setRelatedValue: setFieldValue,
                    setRelatedValues: (values) =>
                        provider.updateBlockDataMultiple(blockId, values),
                    actionLabelField: f.actionLabelKey == null
                        ? null
                        : fieldByKey[f.actionLabelKey],
                  );
                  yield const SizedBox(height: 16);
                }),
              ],
            ),
          );
          sectionWidgets.add(const SizedBox(height: 12));
        }
      }

      final remainingFields = fields
          .where((f) => !usedKeys.contains(f.key))
          .where((f) => !actionLabelKeys.contains(f.key))
          .toList();
      if (remainingFields.isNotEmpty) {
        sectionWidgets.add(
          _CollapsibleSection(
            title: 'Otros',
            initiallyExpanded: sections.isEmpty,
            children: [
              ...remainingFields.expand((f) sync* {
                yield _buildSchemaField(
                  context: context,
                  field: f,
                  currentData: data,
                  setValue: (v) => setSchemaFieldValue(f, v),
                  setRelatedValue: setFieldValue,
                  setRelatedValues: (values) =>
                      provider.updateBlockDataMultiple(blockId, values),
                  actionLabelField: f.actionLabelKey == null
                      ? null
                      : fieldByKey[f.actionLabelKey],
                );
                yield const SizedBox(height: 16);
              }),
            ],
          ),
        );
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...sectionWidgets,
        ],
      );
    }

    // Legacy fallback: show title/subtitle/description if they exist
    final hasTitle = data.containsKey('title');
    final hasSubtitle = data.containsKey('subtitle');
    final hasDescription = data.containsKey('description');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasTitle) ...[
          _EditorTextField(
            label: 'Título',
            value: data['title']?.toString() ?? '',
            onChanged: (v) => setFieldValue('title', v),
          ),
          const SizedBox(height: 16),
        ],
        if (hasSubtitle) ...[
          _EditorTextField(
            label: 'Subtítulo',
            value: data['subtitle']?.toString() ?? '',
            onChanged: (v) => setFieldValue('subtitle', v),
          ),
          const SizedBox(height: 16),
        ],
        if (hasDescription) ...[
          _EditorTextField(
            label: 'Descripción',
            value: data['description']?.toString() ?? '',
            onChanged: (v) =>
                provider.updateBlockData(blockId, 'description', v),
            maxLines: 3,
          ),
        ],
        if (!hasTitle && !hasSubtitle && !hasDescription)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'Edición avanzada disponible próximamente',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
              ),
            ),
          ),
      ],
    );
  }
}
