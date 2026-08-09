part of '../website_editor_panel.dart';

/// Tab for adding new blocks - shows available block types in a grid
class _AddBlocksTab extends StatefulWidget {
  final WebsiteEditModeProvider editProvider;
  final VoidCallback onBlockAdded;

  const _AddBlocksTab({
    required this.editProvider,
    required this.onBlockAdded,
  });

  @override
  State<_AddBlocksTab> createState() => _AddBlocksTabState();
}

class _AddBlocksTabState extends State<_AddBlocksTab> {
  // Drag state for block reordering
  String? _draggingBlockId;
  int? _hoveringBlockIndex;
  _AddPanelMode _mode = _AddPanelMode.layers;
  String _insertQuery = '';

  WebsiteEditModeProvider get editProvider => widget.editProvider;

  @override
  Widget build(BuildContext context) {
    final blocks = editProvider.blocks;
    // One catalog for every add-block surface. This tab used to build its own
    // list from the registry, with its own search and its own silent drop of
    // the footer; `AddBlockDialog` built a third. `WebsiteBlockCatalog` is now
    // the single owner, so a family cannot be present here and missing there.
    const categoryOrder = WebsiteBlockCatalog.categoryOrder;
    final blockOptionsByCategory = <String, List<_BlockOption>>{};
    for (final entry in WebsiteBlockCatalog.filtered(
      presentBlockTypes: <String>[
        for (final block in blocks)
          (block['block_type'] ?? block['type'] ?? '').toString(),
      ],
      query: _insertQuery,
    )) {
      blockOptionsByCategory
          .putIfAbsent(entry.category, () => [])
          .add(_BlockOption.fromCatalog(entry));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<_AddPanelMode>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: _AddPanelMode.layers,
                  icon: Icon(Icons.layers_outlined, size: 17),
                  label: Text('Capas'),
                ),
                ButtonSegment(
                  value: _AddPanelMode.insert,
                  icon: Icon(Icons.add_box_outlined, size: 17),
                  label: Text('Insertar'),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: (value) =>
                  setState(() => _mode = value.first),
            ),
          ),
          const SizedBox(height: 18),
          // =========================
          // PAGE STRUCTURE (Wix-like)
          // =========================
          if (_mode == _AddPanelMode.layers) ...[
            const Text(
              'CAPAS DE LA PÁGINA',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF2D2D2D),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              child: blocks.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text(
                        'Aún no hay bloques. Agrega uno desde abajo.',
                        style: TextStyle(color: Colors.white38, fontSize: 12),
                      ),
                    )
                  : Column(
                      children: List.generate(blocks.length, (index) {
                        // Apply visual reordering during drag
                        var displayIndex = index;
                        if (_draggingBlockId != null &&
                            _hoveringBlockIndex != null) {
                          final draggedOriginalIndex = blocks
                              .indexWhere((b) => b['id'] == _draggingBlockId);
                          if (draggedOriginalIndex >= 0) {
                            if (index == _hoveringBlockIndex) {
                              displayIndex = draggedOriginalIndex;
                            } else if (draggedOriginalIndex <
                                    _hoveringBlockIndex! &&
                                index > draggedOriginalIndex &&
                                index <= _hoveringBlockIndex!) {
                              displayIndex = index - 1;
                            } else if (draggedOriginalIndex >
                                    _hoveringBlockIndex! &&
                                index >= _hoveringBlockIndex! &&
                                index < draggedOriginalIndex) {
                              displayIndex = index + 1;
                            }
                          }
                        }
                        displayIndex = displayIndex.clamp(0, blocks.length - 1);

                        final block = blocks[displayIndex];
                        final id = block['id']?.toString() ?? 'block_$index';
                        final type =
                            (block['block_type'] ?? block['type'] ?? '')
                                .toString();
                        final isVisible = block['is_visible'] ?? true;
                        final isSelected = editProvider.selectedBlockId == id;
                        final isDropTarget = _hoveringBlockIndex == index &&
                            _draggingBlockId != null;

                        return DragTarget<WebsiteEditorDragPayload>(
                          key: ValueKey('block_target_$index'),
                          onWillAcceptWithDetails: (details) {
                            final payload = details.data;
                            final document = editProvider.document;
                            return payload is ExistingWebsiteBlockDragPayload &&
                                payload.blockId != id &&
                                payload.matchesDocument(
                                  sessionRevision: document.sessionRevision,
                                  pageId: document.pageId,
                                  pageSlug: document.pageSlug,
                                );
                          },
                          onMove: (details) {
                            if (_hoveringBlockIndex != index) {
                              setState(() {
                                _hoveringBlockIndex = index;
                              });
                            }
                          },
                          onAcceptWithDetails: (details) {
                            final payload = details.data;
                            final document = editProvider.document;
                            if (payload is ExistingWebsiteBlockDragPayload &&
                                payload.matchesDocument(
                                  sessionRevision: document.sessionRevision,
                                  pageId: document.pageId,
                                  pageSlug: document.pageSlug,
                                )) {
                              // Resolve BOTH identities at commit time. The row
                              // index is only preview geometry and may have
                              // changed while the drag feedback was alive.
                              final liveBlocks = editProvider.blocks;
                              final draggedIndex = liveBlocks.indexWhere(
                                (block) =>
                                    block['id']?.toString() == payload.blockId,
                              );
                              final anchorIndex = liveBlocks.indexWhere(
                                (block) => block['id']?.toString() == id,
                              );
                              if (draggedIndex >= 0 &&
                                  anchorIndex >= 0 &&
                                  draggedIndex != anchorIndex) {
                                final insertIndex = draggedIndex < anchorIndex
                                    ? anchorIndex + 1
                                    : anchorIndex;
                                editProvider.reorderBlocks(
                                  draggedIndex,
                                  insertIndex,
                                );
                              }
                            }
                            setState(() {
                              _draggingBlockId = null;
                              _hoveringBlockIndex = null;
                            });
                          },
                          builder: (context, candidateData, rejectedData) {
                            return Container(
                              decoration: BoxDecoration(
                                color: isDropTarget
                                    ? Colors.white.withValues(alpha: 0.08)
                                    : isSelected
                                        ? const Color(0xFF00A09D)
                                            .withValues(alpha: 0.12)
                                        : Colors.transparent,
                                border: Border(
                                  bottom: BorderSide(
                                    color: Colors.white.withValues(alpha: 0.06),
                                  ),
                                ),
                              ),
                              child: InkWell(
                                onTap: () => editProvider.selectBlock(id),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 10),
                                  child: Row(
                                    children: [
                                      Draggable<WebsiteEditorDragPayload>(
                                        data: ExistingWebsiteBlockDragPayload(
                                          blockId: id,
                                          sessionRevision: editProvider
                                              .documentSessionRevision,
                                          pageId: editProvider.currentPageId,
                                          pageSlug:
                                              editProvider.currentPageSlug,
                                        ),
                                        dragAnchorStrategy:
                                            pointerDragAnchorStrategy,
                                        onDragStarted: () {
                                          setState(() {
                                            _draggingBlockId = id;
                                          });
                                        },
                                        onDraggableCanceled: (_, __) {
                                          setState(() {
                                            _draggingBlockId = null;
                                            _hoveringBlockIndex = null;
                                          });
                                        },
                                        feedback: Material(
                                          color: Colors.transparent,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 12, vertical: 8),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF2D2D2D),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: Colors.black
                                                      .withValues(alpha: 0.4),
                                                  blurRadius: 8,
                                                ),
                                              ],
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const Icon(Icons.drag_handle,
                                                    color: Colors.white54,
                                                    size: 18),
                                                const SizedBox(width: 8),
                                                Icon(_blockIcon(type),
                                                    color: Colors.white70,
                                                    size: 16),
                                                const SizedBox(width: 8),
                                                Text(
                                                  _blockLabel(type),
                                                  style: const TextStyle(
                                                    color: Colors.white70,
                                                    fontSize: 13,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                        childWhenDragging: const Icon(
                                          Icons.drag_handle,
                                          color: Colors.white12,
                                          size: 18,
                                        ),
                                        child: const MouseRegion(
                                          cursor: SystemMouseCursors.grab,
                                          child: Icon(
                                            Icons.drag_handle,
                                            color: Colors.white38,
                                            size: 18,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Icon(
                                        _blockIcon(type),
                                        color: Colors.white70,
                                        size: 16,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          _blockLabel(type),
                                          style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 13,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      IconButton(
                                        onPressed: () => editProvider
                                            .toggleBlockVisibility(id),
                                        icon: Icon(
                                          isVisible
                                              ? Icons.visibility
                                              : Icons.visibility_off,
                                          size: 18,
                                          color: isVisible
                                              ? Colors.white54
                                              : Colors.orange.shade300,
                                        ),
                                        tooltip:
                                            isVisible ? 'Ocultar' : 'Mostrar',
                                        constraints: const BoxConstraints(
                                            minWidth: 32, minHeight: 32),
                                        padding: EdgeInsets.zero,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        );
                      }),
                    ),
            ),
            const SizedBox(height: 20),
          ],
          if (_mode == _AddPanelMode.insert) ...[
            TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search, size: 18),
                hintText: 'Buscar bloque o elemento',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (value) => setState(() => _insertQuery = value),
            ),
            const SizedBox(height: 12),
            for (final category in categoryOrder.take(2))
              if (blockOptionsByCategory[category]?.isNotEmpty == true)
                _buildSection(category, blockOptionsByCategory[category]!),
            _buildSection('Canvas (arrastrable)', [
              const _BlockOption(
                'canvas_el:text',
                labelOverride: 'Texto',
                iconOverride: Icons.text_fields_rounded,
              ),
              const _BlockOption(
                'canvas_el:button',
                labelOverride: 'Botón',
                iconOverride: Icons.smart_button_rounded,
              ),
              const _BlockOption(
                'canvas_el:image',
                labelOverride: 'Imagen',
                iconOverride: Icons.image_outlined,
              ),
              const _BlockOption(
                'canvas_el:shape',
                labelOverride: 'Forma',
                iconOverride: Icons.rectangle_outlined,
              ),
              const _BlockOption(
                'canvas_el:product',
                labelOverride: 'Producto',
                iconOverride: Icons.inventory_2_outlined,
              ),
              const _BlockOption(
                'canvas_el:productsGallery',
                labelOverride: 'Galería productos',
                iconOverride: Icons.grid_view_rounded,
              ),
            ]),
            for (final category in categoryOrder.skip(2))
              if (blockOptionsByCategory[category]?.isNotEmpty == true)
                _buildSection(category, blockOptionsByCategory[category]!),
          ],
        ],
      ),
    );
  }

  Widget _buildSection(String title, List<_BlockOption> options) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12, top: 8),
          child: Text(
            title,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1,
            ),
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: options.map((opt) => _buildBlockCard(opt)).toList(),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildBlockCard(_BlockOption option) {
    if (!option.enabled) {
      // Visible, inert and explained — never removed from the list.
      return Tooltip(
        message: option.disabledReason ?? 'No disponible en esta página',
        child: Opacity(
          opacity: 0.55,
          child: Semantics(
            enabled: false,
            label: '${option.label}. '
                '${option.disabledReason ?? 'No disponible en esta página'}',
            child: _buildCardContent(option),
          ),
        ),
      );
    }
    return Builder(
      builder: (context) => Draggable<WebsiteEditorDragPayload>(
        data: option.type.startsWith('canvas_el:')
            ? CanvasElementDragPayload(
                option.type.replaceFirst('canvas_el:', ''),
              )
            : NewWebsiteBlockDragPayload(option.type),
        feedback: Material(
          color: Colors.transparent,
          child: Container(
            width: 90,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF00A09D),
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(option.icon, color: Colors.white, size: 24),
                const SizedBox(height: 6),
                Text(
                  option.label,
                  style: const TextStyle(color: Colors.white, fontSize: 11),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
        childWhenDragging: Opacity(
          opacity: 0.4,
          child: _buildCardContent(option),
        ),
        onDragEnd: (details) {
          // Block will be added via drop target in main content area
        },
        child: GestureDetector(
          onTap: () {
            if (option.type.startsWith('canvas_el:')) {
              final elementType = option.type.replaceFirst('canvas_el:', '');
              final ok =
                  editProvider.addCanvasElementToSelectedCanvas(elementType);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(ok
                      ? 'Elemento "$elementType" agregado al Canvas'
                      : 'Selecciona un bloque Canvas para agregar elementos'),
                  duration: const Duration(seconds: 2),
                  backgroundColor: ok ? const Color(0xFF00A09D) : Colors.orange,
                ),
              );
              return;
            }

            widget.onBlockAdded();
            editProvider.addBlock(option.type);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Bloque "${option.label}" agregado'),
                duration: const Duration(seconds: 2),
                backgroundColor: const Color(0xFF00A09D),
              ),
            );
          },
          child: _buildCardContent(option),
        ),
      ),
    );
  }

  Widget _buildCardContent(_BlockOption option) {
    return Container(
      width: 90,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF2D2D2D),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(option.icon, color: Colors.white70, size: 22),
          const SizedBox(height: 8),
          Text(
            option.label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  static IconData _blockIcon(String type) {
    final blockType = _tryParseWebsiteBlockType(type);
    return blockType?.icon ?? Icons.widgets_rounded;
  }

  static String _blockLabel(String type) {
    final blockType = _tryParseWebsiteBlockType(type);
    if (blockType == null) return type;
    return WebsiteBlockRegistry.definitionFor(blockType).title;
  }

  static WebsiteBlockType? _tryParseWebsiteBlockType(String raw) {
    final normalised = raw.trim();
    if (normalised.isEmpty) return null;

    // Parse using the shared helper, but only accept it if it actually matched.
    final parsed = parseWebsiteBlockType(
      normalised,
      fallback: WebsiteBlockType.hero,
    );

    if (parsed.name.toLowerCase() == normalised.toLowerCase()) {
      return parsed;
    }

    // If we fell back to hero for a non-hero raw value, treat as unknown.
    if (parsed == WebsiteBlockType.hero && normalised.toLowerCase() != 'hero') {
      return null;
    }
    return parsed;
  }
}

enum _AddPanelMode { layers, insert }

class _ActionCard extends StatelessWidget {
  final String title;
  final String description;
  final IconData icon;
  final VoidCallback? onTap;
  final bool enabled;

  const _ActionCard({
    required this.title,
    required this.description,
    required this.icon,
    this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final isEnabled = enabled && onTap != null;
    return InkWell(
      onTap: isEnabled ? onTap : null,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF2D2D2D),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: (isEnabled ? const Color(0xFF00A09D) : Colors.grey)
                    .withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(icon,
                  color: isEnabled ? const Color(0xFF00A09D) : Colors.grey,
                  size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: isEnabled ? Colors.white : Colors.white54,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    description,
                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                ],
              ),
            ),
            if (isEnabled)
              const Icon(Icons.arrow_forward_ios,
                  color: Colors.white30, size: 14),
          ],
        ),
      ),
    );
  }
}

class _BlockOption {
  final String type;
  final String? labelOverride;
  final IconData? iconOverride;

  /// Non-insertable families stay listed and explain themselves (`O-01`).
  final bool enabled;
  final String? disabledReason;

  const _BlockOption(
    this.type, {
    this.labelOverride,
    this.iconOverride,
    this.enabled = true,
    this.disabledReason,
  });

  /// The catalog entry as this tab's card model. Canvas elements keep the
  /// plain constructor: they are not page blocks and are not in the catalog.
  factory _BlockOption.fromCatalog(WebsiteBlockCatalogEntry entry) {
    return _BlockOption(
      entry.type.name,
      labelOverride: entry.title,
      iconOverride: entry.icon,
      enabled: entry.isInsertable,
      disabledReason: entry.unavailableReason,
    );
  }

  WebsiteBlockType? get _blockType {
    if (type.startsWith('canvas_el:')) return null;

    final parsed = parseWebsiteBlockType(type, fallback: WebsiteBlockType.hero);
    if (parsed.name.toLowerCase() == type.toLowerCase()) return parsed;
    if (parsed == WebsiteBlockType.hero && type.toLowerCase() != 'hero') {
      return null;
    }
    return parsed;
  }

  String get label {
    if (labelOverride != null) return labelOverride!;
    final blockType = _blockType;
    if (blockType == null) return type;
    return WebsiteBlockRegistry.definitionFor(blockType).title;
  }

  IconData get icon {
    if (iconOverride != null) return iconOverride!;
    final blockType = _blockType;
    return blockType?.icon ?? Icons.widgets_rounded;
  }
}
