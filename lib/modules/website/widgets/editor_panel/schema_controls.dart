part of '../website_editor_panel.dart';

/// CTA block controls
/// Generic block controls for types without specific UI
typedef _RepeaterItemEditorBuilder = Widget Function(
  BuildContext context,
  int index,
  Map<String, dynamic> item,
  _SchemaRepeaterItemContext itemContext,
);

typedef _RepeaterCommandCallback = WebsiteRepeaterMutationOutcome Function(
  WebsiteRepeaterCommand command,
);

class _SchemaRepeaterItemContext {
  const _SchemaRepeaterItemContext({
    required this.collectionTarget,
    required this.itemRef,
    required this.index,
  });

  final WebsiteRepeaterCollectionTarget collectionTarget;
  final WebsiteRepeaterItemRef itemRef;
  final int index;
}

class _RepeaterDragPayload {
  const _RepeaterDragPayload({
    required this.source,
    required this.commit,
  });

  final WebsiteRepeaterItemRef source;
  final _RepeaterCommandCallback commit;
}

/// The collection's five operations, reachable by test and by pointer/touch
/// alike. They belong to the shared editor, not to any family.
const Key repeaterAddKey = Key('website-repeater-add');
const Key repeaterMoveBackKey = Key('website-repeater-move-back');
const Key repeaterMoveForwardKey = Key('website-repeater-move-forward');
const Key repeaterDuplicateKey = Key('website-repeater-duplicate');
const Key repeaterDeleteKey = Key('website-repeater-delete');

Key repeaterDragHandleKey(int index) =>
    Key('website-repeater-drag-handle-$index');

/// The ONLY thing in a collection chip that starts a drag.
///
/// A finger that swipes the strip must still scroll it, so the drag is not on
/// the chip and not on the row: it lives on an explicit handle and it starts on
/// long press, which is the gesture a scrollable does not claim. The button
/// pair stays the accessible alternative — `F-06` asks for 48 and for a
/// non-drag path, not for a drag that steals the scroll.
class _RepeaterDragHandle extends StatelessWidget {
  const _RepeaterDragHandle({
    required this.index,
    required this.itemRef,
    required this.commit,
    required this.label,
    required this.color,
    required this.size,
  });

  final int index;
  final WebsiteRepeaterItemRef itemRef;
  final _RepeaterCommandCallback commit;
  final String label;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final handle = SizedBox(
      width: size,
      height: size,
      child: Center(
        child: Icon(Icons.drag_indicator_rounded, size: 18, color: color),
      ),
    );
    final scheme = Theme.of(context).colorScheme;

    return Semantics(
      label: 'Reordenar $label',
      hint: 'Mantén presionado y arrastra',
      child: LongPressDraggable<_RepeaterDragPayload>(
        key: repeaterDragHandleKey(index),
        data: _RepeaterDragPayload(source: itemRef, commit: commit),
        // Touch, mouse and stylus all begin the same way, so pointer and
        // finger keep one behaviour.
        feedback: Material(
          color: Colors.transparent,
          child: Opacity(
            opacity: 0.9,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: scheme.primary),
              ),
              child: handle,
            ),
          ),
        ),
        childWhenDragging: Opacity(opacity: 0.4, child: handle),
        child: handle,
      ),
    );
  }
}

/// Compact, shared inspector for schema-defined collections.
///
/// A collection can contain many rich items (images, focal points, actions,
/// nested collections, and so on). Rendering every item form at once makes the
/// inspector impossible to scan, so this control keeps the collection overview
/// visible while editing exactly one item at a time.
class _SchemaRepeaterEditor extends StatefulWidget {
  const _SchemaRepeaterEditor({
    required this.field,
    required this.target,
    required this.items,
    required this.onCommand,
    required this.itemBuilder,
    this.selectedIndex,
    this.onSelectedIndexChanged,
    this.itemSeed,
    this.attribution,
  });

  final WebsiteBlockFieldSchema field;
  final WebsiteRepeaterCollectionTarget target;
  final List<Map<String, dynamic>> items;
  final _RepeaterCommandCallback onCommand;
  final _RepeaterItemEditorBuilder itemBuilder;

  /// Selection owned by the caller.
  ///
  /// A family whose selection is shared with another surface — the Carousel,
  /// whose active slide also drives the canvas and the inline presenters —
  /// passes it in and keeps ONE selection. Everything else keeps this editor's
  /// own, which is the common case and needs no wiring.
  final int? selectedIndex;
  final ValueChanged<int>? onSelectedIndexChanged;

  /// The content a brand-new item starts with.
  ///
  /// Defaults to the schema's own declared defaults. A family with richer
  /// authored defaults passes them here instead of forking the editor, so the
  /// business content of "add" does not change by adopting this owner.
  final Map<String, dynamic> Function()? itemSeed;
  final Widget? attribution;

  @override
  State<_SchemaRepeaterEditor> createState() => _SchemaRepeaterEditorState();
}

class _SchemaRepeaterEditorState extends State<_SchemaRepeaterEditor> {
  int _internalIndex = 0;

  int get _selectedIndex => widget.selectedIndex ?? _internalIndex;

  @override
  void didUpdateWidget(covariant _SchemaRepeaterEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.items.isEmpty) {
      _internalIndex = 0;
    } else if (_internalIndex >= widget.items.length) {
      _internalIndex = widget.items.length - 1;
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
    final next = index < 0 ? 0 : index;
    final external = widget.onSelectedIndexChanged;
    if (external != null) {
      external(next);
      return;
    }
    setState(() => _internalIndex = next);
  }

  void _select(int index) {
    final external = widget.onSelectedIndexChanged;
    if (external != null) {
      external(index);
      return;
    }
    setState(() => _internalIndex = index);
  }

  void _addItem() {
    final seed = widget.itemSeed?.call() ??
        <String, dynamic>{
          for (final field in widget.field.itemFields)
            field.key: field.defaultValue,
        };
    _selectCommitted(widget.onCommand(WebsiteRepeaterAddItem(seed)));
  }

  /// Copies one item WITHOUT its persisted identity.
  ///
  /// A duplicated slide is a new object: carrying the original id would give
  /// two items the same identity, and every write addressed by identity would
  /// then land on whichever came first. The copy stays index-owned, which is
  /// exactly how these repeaters already address an item that never had an id
  /// — no identity is manufactured here.
  void _duplicateItem(int index) {
    final source = widget.target.itemRef(widget.items[index], index);
    _selectCommitted(
      widget.onCommand(WebsiteRepeaterDuplicateItem(source)),
    );
  }

  void _moveItem(
    WebsiteRepeaterItemRef source,
    WebsiteRepeaterItemRef anchor,
    WebsiteRepeaterMovePlacement placement, {
    _RepeaterCommandCallback? commit,
  }) {
    _selectCommitted(
      (commit ?? widget.onCommand)(
        WebsiteRepeaterMoveItem(
          source: source,
          anchor: anchor,
          placement: placement,
        ),
      ),
    );
  }

  void _selectCommitted(WebsiteRepeaterMutationOutcome outcome) {
    if (outcome.result != WebsiteRepeaterMutationResult.committed) return;
    final index = outcome.selectionIndex;
    if (index != null) _selectAfterChange(index);
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    final canAdd =
        widget.field.maxItems == null || items.length < widget.field.maxItems!;
    final safeIndex =
        items.isEmpty ? 0 : _selectedIndex.clamp(0, items.length - 1).toInt();
    // The inspector's own graphite scheme, resolved by
    // `WebsiteEditorInspectorTheme` above this subtree. Consuming it here is
    // what keeps O-05 dark end to end without this control owning a second
    // palette or a literal of its own.
    final scheme = Theme.of(context).colorScheme;
    final accent = scheme.primary;
    // `F-06`: under 900 the density is forced to touch, and these are the
    // collection's only actions. 48 is the floor for all of them.
    const minTarget = 48.0;
    const targetConstraints = BoxConstraints(
      minWidth: minTarget,
      minHeight: minTarget,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                widget.field.label,
                style: TextStyle(
                  color: scheme.onSurface,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (widget.attribution != null) ...[
              const SizedBox(width: 6),
              widget.attribution!,
              const SizedBox(width: 6),
            ],
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${items.length}',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11),
              ),
            ),
            const SizedBox(width: 6),
            IconButton(
              key: repeaterAddKey,
              tooltip: 'Agregar ${widget.field.itemLabel ?? 'item'}',
              constraints: targetConstraints,
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
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Column(
              children: [
                Text(
                  'Todavía no hay elementos',
                  style:
                      TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
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
                final anchor = widget.target.itemRef(items[index], index);
                return Padding(
                  padding: EdgeInsets.only(
                    right: index == items.length - 1 ? 0 : 6,
                  ),
                  child: DragTarget<_RepeaterDragPayload>(
                    onWillAcceptWithDetails: (details) =>
                        details.data.source != anchor,
                    onAcceptWithDetails: (details) => _moveItem(
                      details.data.source,
                      anchor,
                      details.data.source.fallbackIndex < anchor.fallbackIndex
                          ? WebsiteRepeaterMovePlacement.after
                          : WebsiteRepeaterMovePlacement.before,
                      commit: details.data.commit,
                    ),
                    builder: (context, candidate, rejected) {
                      final receiving = candidate.isNotEmpty;
                      return Tooltip(
                        message: _itemTitle(items[index], index),
                        child: Material(
                          color: selected
                              ? accent.withValues(alpha: 0.16)
                              : scheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                          child: InkWell(
                            onTap: () => _select(index),
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              // The chip grew by exactly the handle's 48: the
                              // label keeps the room it had.
                              constraints: const BoxConstraints(
                                minWidth: 42 + minTarget,
                                maxWidth: 132 + minTarget,
                              ),
                              padding: const EdgeInsets.only(right: 10),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: receiving
                                      ? accent
                                      : selected
                                          ? accent.withValues(alpha: 0.65)
                                          : scheme.outlineVariant,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _RepeaterDragHandle(
                                    index: index,
                                    itemRef: anchor,
                                    commit: widget.onCommand,
                                    label: _itemTitle(items[index], index),
                                    color: selected
                                        ? scheme.onSurface
                                        : scheme.onSurfaceVariant,
                                    size: minTarget,
                                  ),
                                  Flexible(
                                    child: Text(
                                      '${index + 1}  '
                                      '${_itemTitle(items[index], index)}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: selected
                                            ? scheme.onSurface
                                            : scheme.onSurfaceVariant,
                                        fontSize: 11.5,
                                        fontWeight: selected
                                            ? FontWeight.w600
                                            : FontWeight.w400,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            decoration: BoxDecoration(
              color: scheme.surfaceContainer,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: scheme.outlineVariant),
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
                        style: TextStyle(
                          color: scheme.onSurface,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      key: repeaterMoveBackKey,
                      tooltip: 'Mover hacia arriba',
                      constraints: targetConstraints,
                      iconSize: 18,
                      onPressed: safeIndex > 0
                          ? () => _moveItem(
                                widget.target.itemRef(
                                  items[safeIndex],
                                  safeIndex,
                                ),
                                widget.target.itemRef(
                                  items[safeIndex - 1],
                                  safeIndex - 1,
                                ),
                                WebsiteRepeaterMovePlacement.before,
                              )
                          : null,
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                    IconButton(
                      key: repeaterMoveForwardKey,
                      tooltip: 'Mover hacia abajo',
                      constraints: targetConstraints,
                      iconSize: 18,
                      onPressed: safeIndex < items.length - 1
                          ? () => _moveItem(
                                widget.target.itemRef(
                                  items[safeIndex],
                                  safeIndex,
                                ),
                                widget.target.itemRef(
                                  items[safeIndex + 1],
                                  safeIndex + 1,
                                ),
                                WebsiteRepeaterMovePlacement.after,
                              )
                          : null,
                      icon: const Icon(Icons.arrow_forward_rounded),
                    ),
                    IconButton(
                      key: repeaterDuplicateKey,
                      tooltip: 'Duplicar',
                      constraints: targetConstraints,
                      iconSize: 18,
                      onPressed:
                          canAdd ? () => _duplicateItem(safeIndex) : null,
                      icon: const Icon(Icons.copy_outlined),
                    ),
                    IconButton(
                      key: repeaterDeleteKey,
                      tooltip: 'Eliminar',
                      constraints: targetConstraints,
                      iconSize: 18,
                      color: scheme.error,
                      onPressed: widget.field.minItems == null ||
                              items.length > widget.field.minItems!
                          ? () {
                              _selectCommitted(
                                widget.onCommand(
                                  WebsiteRepeaterDeleteItem(
                                    widget.target.itemRef(
                                      items[safeIndex],
                                      safeIndex,
                                    ),
                                  ),
                                ),
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
                  _SchemaRepeaterItemContext(
                    collectionTarget: widget.target,
                    itemRef: widget.target.itemRef(
                      items[safeIndex],
                      safeIndex,
                    ),
                    index: safeIndex,
                  ),
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
          .map(
            (item) => item is Map
                ? Map<String, dynamic>.from(item)
                : <String, dynamic>{'label': item.toString()},
          )
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

  /// `F-06` · the density the editor chrome publishes for this host.
  WebsiteAuthoringHostClass _hostClass(BuildContext context) =>
      WebsiteEditorChromeScope.maybeOf(context)?.hostClass ??
      WebsiteAuthoringHostClass.desktop;

  WebsiteViewport _effectiveViewport(BuildContext context) =>
      WebsiteEditorAuthoringViewportScope.effectiveOf(
        context,
        fallback: provider.previewViewport,
      );

  String _responsiveOwnerScope(WebsiteResponsiveFieldOwner owner) {
    return jsonEncode(
      switch (owner) {
        WebsiteResponsiveRootField() => <String, Object?>{
            'owner': 'root',
          },
        WebsiteResponsiveRepeaterField(
          collectionKeys: final collectionKeys,
          itemIndex: final itemIndex,
          identityKey: final identityKey,
          identityValue: final identityValue,
        ) =>
          <String, Object?>{
            'owner': 'repeater',
            'collections': collectionKeys,
            'index': itemIndex,
            'identityKey': identityKey,
            'identityValue': identityValue,
          },
      },
    );
  }

  String _nestedItemScope(_SchemaRepeaterItemContext itemContext) {
    Map<String, Object?> item(WebsiteRepeaterItemRef ref) => <String, Object?>{
          'index': ref.fallbackIndex,
          'identityKey': ref.identityKey,
          'identityValue': ref.identityValue,
        };

    return jsonEncode(<String, Object?>{
      'owner': 'nested-repeater',
      'ancestors': itemContext.collectionTarget.ancestors
          .map(
            (ancestor) => <String, Object?>{
              'collections': ancestor.collectionKeys,
              'item': item(ancestor.item),
            },
          )
          .toList(growable: false),
      'collections': itemContext.collectionTarget.collectionKeys,
      'item': item(itemContext.itemRef),
    });
  }

  String _schemaAsyncScope({
    required BuildContext context,
    required String ownerScope,
    required String propertyKey,
  }) {
    return jsonEncode(<String, Object?>{
      'surface': 'schema',
      'viewport': _effectiveViewport(context).name,
      'owner': ownerScope,
      'property': propertyKey,
    });
  }

  WebsiteAsyncFieldBinding _schemaAsyncBinding({
    required BuildContext context,
    required WebsiteResponsiveFieldOwner owner,
    required String propertyKey,
  }) {
    return WebsiteAsyncFieldBinding.pageBlock(
      provider: provider,
      target: WebsiteAsyncFieldTarget.block(
        blockId: blockId,
        scopeKey: _schemaAsyncScope(
          context: context,
          ownerScope: _responsiveOwnerScope(owner),
          propertyKey: propertyKey,
        ),
      ),
    );
  }

  WebsiteAsyncFieldBinding _nestedAsyncBinding({
    required BuildContext context,
    required _SchemaRepeaterItemContext itemContext,
    required String propertyKey,
  }) {
    return WebsiteAsyncFieldBinding.pageBlock(
      provider: provider,
      target: WebsiteAsyncFieldTarget.block(
        blockId: blockId,
        scopeKey: _schemaAsyncScope(
          context: context,
          ownerScope: _nestedItemScope(itemContext),
          propertyKey: propertyKey,
        ),
      ),
    );
  }

  /// The one binding every non-media schema field uses.
  ///
  /// `sharedCompanionKeys` carries the duplicates the product still reads for
  /// the same value; the binding writes them on a shared write only.
  WebsiteResponsiveScalarBinding<T> _scalarBinding<T>({
    required BuildContext context,
    required WebsiteBlockFieldSchema field,
    required WebsiteResponsiveFieldOwner owner,
    required WebsiteResponsiveDecoder<T> decode,
    T? fallback,
    List<String> sharedCompanionKeys = const <String>[],
  }) {
    return WebsiteResponsiveScalarBinding<T>.forField(
      provider: provider,
      blockId: blockId,
      field: field,
      owner: owner,
      decode: decode,
      fallback: fallback,
      hostClass: _hostClass(context),
      viewport: _effectiveViewport(context),
      sharedCompanionKeys: sharedCompanionKeys,
    );
  }

  WebsiteResponsiveScalarBinding<T> _schemaFieldBinding<T>({
    required BuildContext context,
    required WebsiteBlockFieldSchema field,
    required WebsiteResponsiveFieldOwner owner,
    required WebsiteResponsiveDecoder<T> decode,
    T? fallback,
  }) {
    return _scalarBinding<T>(
      context: context,
      field: field,
      owner: owner,
      decode: decode,
      fallback: fallback,
      sharedCompanionKeys: <String>[
        // Historical CTA documents stored the subtitle under both keys. The
        // binding commits both in one exact lease instead of letting the
        // inspector issue a second history entry after the primary write.
        if (rawBlockType == 'cta' && field.key == 'subtitle') 'description',
      ],
    );
  }

  Widget _bindingAttribution<T>(
    WebsiteResponsiveScalarBinding<T> binding,
  ) {
    return ResponsiveFieldAttribution<T>(state: binding.state);
  }

  WebsiteInlineManipulationOwner _inlineOwnerFor(
    WebsiteResponsiveFieldOwner owner,
  ) {
    return switch (owner) {
      WebsiteResponsiveRootField() => const WebsiteInlineBlockOwner(),
      WebsiteResponsiveRepeaterField(
        collectionKeys: final collectionKeys,
        itemIndex: final itemIndex,
        identityKey: final identityKey,
        identityValue: final identityValue,
      ) =>
        WebsiteInlineRepeaterOwner(
          collectionKeys: collectionKeys,
          itemIndex: itemIndex,
          identityKey: identityKey,
          identityValue: identityValue,
        ),
    };
  }

  WebsiteInlineMutationResult Function(Map<String, Object?>)
      _schemaTransaction({
    required BuildContext context,
    required WebsiteResponsiveFieldOwner owner,
    required List<WebsiteInlineManipulationProperty> properties,
    bool recaptureAccepted = true,
  }) {
    final target = WebsiteInlineManipulationTarget(
      blockId: blockId,
      owner: _inlineOwnerFor(owner),
      viewport: _effectiveViewport(context),
      properties: properties,
      requiresSelection: true,
    );
    var lease = provider.captureInlineMutationLease(target);
    return (values) {
      final currentLease = lease;
      if (currentLease == null) return WebsiteInlineMutationResult.rejected;
      lease = null;
      final result = provider.commitInlineMutation(currentLease, values);
      if (recaptureAccepted && result.accepted) {
        lease = provider.captureInlineMutationLease(target);
      }
      return result;
    };
  }

  _RepeaterCommandCallback _repeaterCommandBinding(
    WebsiteRepeaterCollectionTarget target, {
    bool recaptureAccepted = false,
  }) {
    var lease = provider.captureRepeaterMutationLease(target);
    return (command) {
      final currentLease = lease;
      if (currentLease == null) {
        return const WebsiteRepeaterMutationOutcome.rejected();
      }
      lease = null;
      final outcome = provider.commitRepeaterMutation(currentLease, command);
      // Structural controls deliberately never recapture before a rebuild:
      // their button/drag intent was rendered from one exact collection.
      // PatchItem is semantic rather than list-replacing, so text/IME fields
      // may safely recapture after an admitted patch.
      if (recaptureAccepted && outcome.result.accepted) {
        lease = provider.captureRepeaterMutationLease(target);
      }
      return outcome;
    };
  }

  WebsiteRepeaterMutationResult Function(Map<String, dynamic>)
      _nestedItemPatchBinding(_SchemaRepeaterItemContext itemContext) {
    final commit = _repeaterCommandBinding(
      itemContext.collectionTarget,
      recaptureAccepted: true,
    );
    return (updates) => commit(
          WebsiteRepeaterPatchItem(
            target: itemContext.itemRef,
            updates: updates,
          ),
        ).result;
  }

  WebsiteRepeaterCollectionTarget _collectionTarget({
    required WebsiteBlockFieldSchema field,
    required WebsiteResponsiveFieldOwner owner,
    _SchemaRepeaterItemContext? parentItem,
  }) {
    final keys = <String>[field.key, ...field.migrationAliases];
    if (parentItem != null) {
      return parentItem.collectionTarget.nested(
        parentItem: parentItem.itemRef,
        collectionKeys: keys,
        minItems: field.minItems,
        maxItems: field.maxItems,
      );
    }
    return switch (owner) {
      WebsiteResponsiveRootField() => WebsiteRepeaterCollectionTarget(
          blockId: blockId,
          collectionKeys: keys,
          minItems: field.minItems,
          maxItems: field.maxItems,
        ),
      WebsiteResponsiveRepeaterField(
        collectionKeys: final parentKeys,
        itemIndex: final itemIndex,
        identityKey: final identityKey,
        identityValue: final identityValue,
      ) =>
        WebsiteRepeaterCollectionTarget(
          blockId: blockId,
          ancestors: <WebsiteRepeaterAncestorRef>[
            WebsiteRepeaterAncestorRef(
              collectionKeys: parentKeys,
              item: identityKey != null && identityValue != null
                  ? WebsiteRepeaterItemRef.persisted(
                      fallbackIndex: itemIndex,
                      identityKey: identityKey,
                      identityValue: identityValue,
                    )
                  : WebsiteRepeaterItemRef.index(itemIndex),
              itemIdentityKey: identityKey ?? 'id',
            ),
          ],
          collectionKeys: keys,
          minItems: field.minItems,
          maxItems: field.maxItems,
        ),
    };
  }

  Widget _buildDeepNestedSharedField({
    required BuildContext context,
    required WebsiteBlockFieldSchema field,
    required Map<String, dynamic> currentData,
    required _SchemaRepeaterItemContext itemContext,
    WebsiteBlockFieldSchema? actionLabelField,
    WebsiteBlockFieldSchema? actionVariantField,
  }) {
    dynamic raw = currentData[field.key];
    for (final alias in field.migrationAliases) {
      raw ??= currentData[alias];
    }
    final write = _nestedItemPatchBinding(itemContext);

    Map<String, dynamic> valueUpdates(dynamic value) => <String, dynamic>{
          field.key: value,
          for (final alias in field.migrationAliases) alias: value,
        };

    switch (field.type) {
      case WebsiteBlockFieldType.text:
      case WebsiteBlockFieldType.textarea:
      case WebsiteBlockFieldType.richtext:
        final formattingKey = field.resolvedFormattingKey;
        final formattingBinding = _nestedAsyncBinding(
          context: context,
          itemContext: itemContext,
          propertyKey: formattingKey,
        );
        final textBinding = _nestedAsyncBinding(
          context: context,
          itemContext: itemContext,
          propertyKey: field.key,
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _EditorTextField(
              label: field.label,
              value: raw?.toString() ?? field.defaultValue?.toString() ?? '',
              asyncBinding: textBinding,
              onChanged: (value) => write(valueUpdates(value)),
              maxLines: switch (field.type) {
                WebsiteBlockFieldType.text => 1,
                WebsiteBlockFieldType.textarea => 4,
                _ => 6,
              },
              hint: field.type == WebsiteBlockFieldType.richtext
                  ? '<p>...</p>'
                  : null,
            ),
            if (field.supportsFormatting) ...[
              const SizedBox(height: 10),
              const _SectionHeader('Formato'),
              const SizedBox(height: 8),
              TextFormattingToolbar(
                currentFormatting: TextFormatting.fromJson(
                  currentData[formattingKey] is Map
                      ? Map<String, dynamic>.from(
                          currentData[formattingKey] as Map,
                        )
                      : null,
                ),
                preset: TextToolbarPreset.basic,
                showAdvancedOptions: false,
                transactionIdentity: formattingBinding.identity,
                asyncBinding: formattingBinding,
                onFormattingChanged: (value) => write(
                  <String, dynamic>{formattingKey: value.toJson()},
                ),
              ),
            ],
            _helpText(
              field.helpText ??
                  (field.type == WebsiteBlockFieldType.richtext
                      ? 'Acepta HTML.'
                      : null),
            ),
          ],
        );

      case WebsiteBlockFieldType.link:
        final current = raw?.toString() ?? field.defaultValue?.toString() ?? '';
        final asyncBinding = _nestedAsyncBinding(
          context: context,
          itemContext: itemContext,
          propertyKey: field.key,
        );
        final actionLabelKey = field.actionLabelKey;
        if (actionLabelKey == null) {
          return WebsiteLinkValueEditor(
            label: field.label,
            value: current,
            helpText: field.helpText,
            dense: true,
            darkStyle: true,
            asyncBinding: asyncBinding,
            onChanged: (value) => write(valueUpdates(value)),
          );
        }
        final labelKeys = <String>[
          actionLabelKey,
          ...?actionLabelField?.migrationAliases,
        ];
        final hrefKeys = <String>[field.key, ...field.migrationAliases];
        final label = labelKeys
            .map((key) => currentData[key]?.toString().trim() ?? '')
            .firstWhere((value) => value.isNotEmpty, orElse: () => 'Ver más');
        final variantKey = field.actionVariantKey;
        final editsVariantHere =
            variantKey != null && actionVariantField == null;
        Object? workingActions = currentData['actions'];
        return WebsiteActionEditor(
          value: WebsiteActionValue.resolvePrimary(
                currentData,
                labelKeys: labelKeys,
                hrefKeys: hrefKeys,
                defaultLabel: label,
                defaultHref: current,
              ) ??
              WebsiteActionValue(label: label, href: current),
          darkStyle: true,
          dense: true,
          showVariant: editsVariantHere,
          asyncBinding: asyncBinding,
          onChanged: (next) {
            final updates = <String, dynamic>{
              ...valueUpdates(next.href),
              actionLabelKey: next.label,
              for (final alias
                  in actionLabelField?.migrationAliases ?? const <String>[])
                alias: next.label,
              if (editsVariantHere) variantKey: next.variant.storageValue,
              'actions': WebsiteActionValue.mergePrimary(workingActions, next),
            };
            final result = write(updates);
            if (result.accepted) workingActions = updates['actions'];
            return result;
          },
        );

      case WebsiteBlockFieldType.number:
        final current = raw is num
            ? raw.toDouble()
            : double.tryParse(raw?.toString() ?? '') ??
                (field.defaultValue as num?)?.toDouble() ??
                0;
        final min = field.min?.toDouble();
        final max = field.max?.toDouble();
        if (min != null && max != null) {
          final asyncBinding = _nestedAsyncBinding(
            context: context,
            itemContext: itemContext,
            propertyKey: field.key,
          );
          return _EditorSlider(
            label: field.label,
            value: current.clamp(min, max),
            min: min,
            max: max,
            transactionIdentity: asyncBinding.identity,
            asyncBinding: asyncBinding,
            onCommit: (value) => write(valueUpdates(value)),
          );
        }
        final asyncBinding = _nestedAsyncBinding(
          context: context,
          itemContext: itemContext,
          propertyKey: field.key,
        );
        return _EditorTextField(
          label: field.label,
          value: current.toString(),
          asyncBinding: asyncBinding,
          onChanged: (value) {
            final parsed = num.tryParse(value);
            if (parsed != null) write(valueUpdates(parsed));
          },
        );

      case WebsiteBlockFieldType.toggle:
        return _EditorToggle(
          label: field.label,
          value: raw == true,
          onChanged: (value) => write(valueUpdates(value)),
        );

      case WebsiteBlockFieldType.select:
        return _EditorDropdown(
          label: field.label,
          value: raw?.toString() ?? field.defaultValue?.toString() ?? '',
          options: field.options
              .map((option) => (option.value, option.label))
              .toList(growable: false),
          onChanged: (value) => write(valueUpdates(value)),
        );

      case WebsiteBlockFieldType.chips:
        final asyncBinding = _nestedAsyncBinding(
          context: context,
          itemContext: itemContext,
          propertyKey: field.key,
        );
        return _EditorTextField(
          label: field.label,
          value: _toStringList(raw).join(', '),
          hint: 'separado por comas',
          maxLines: 2,
          asyncBinding: asyncBinding,
          onChanged: (value) => write(valueUpdates(_toStringList(value))),
        );

      case WebsiteBlockFieldType.color:
        final current = raw?.toString() ?? field.defaultValue?.toString() ?? '';
        return WebsiteColorPickerField(
          label: field.label,
          value: current.isEmpty ? '#000000' : current,
          helperText: field.helpText,
          allowAlpha: true,
          asyncBinding: _nestedAsyncBinding(
            context: context,
            itemContext: itemContext,
            propertyKey: field.key,
          ),
          onChanged: (value) => write(valueUpdates(value)),
        );

      case WebsiteBlockFieldType.video:
        return _VideoPicker(
          currentUrl: raw?.toString(),
          asyncBinding: _nestedAsyncBinding(
            context: context,
            itemContext: itemContext,
            propertyKey: field.key,
          ),
          onChanged: (value) => write(valueUpdates(value)),
        );

      case WebsiteBlockFieldType.image:
      case WebsiteBlockFieldType.repeater:
        // The current nested schema contains shared text/link fields. Media is
        // intentionally not downgraded to a URL-only picker; repeater routing
        // remains in the canonical collection branch below.
        return const SizedBox.shrink();
    }
  }

  /// Mounts a control under the canonical inheritance shell.
  ///
  /// The shell owns label, help, status badge, scope sentence and the
  /// customize/reset action, so the control inside is given an EMPTY label and
  /// no help line: two labels for one field is the duplication this protocol
  /// exists to remove.
  Widget _responsiveField<T>({
    required WebsiteResponsiveScalarBinding<T> binding,
    required Widget child,
    String? helpText,
  }) {
    return ResponsiveFieldShell<T>(
      state: binding.state,
      onCustomize: binding.customize,
      onReset: binding.reset,
      helpText: helpText,
      child: child,
    );
  }

  /// Compact truth label for a `sharedOnly` field.
  ///
  /// The control keeps its existing label and geometry; only fields that can
  /// actually inherit or override receive the full [ResponsiveFieldShell].
  Widget _sharedAttribution({
    required BuildContext context,
    required WebsiteBlockFieldSchema field,
    required WebsiteResponsiveFieldOwner owner,
  }) {
    assert(
      !field.allowsViewportOverride,
      'Responsive fields must use ResponsiveFieldShell, not compact '
      'shared attribution.',
    );
    final binding = _scalarBinding<Object?>(
      context: context,
      field: field,
      owner: owner,
      decode: (raw) => raw,
      fallback: field.defaultValue,
    );
    return ResponsiveFieldAttribution<Object?>(state: binding.state);
  }

  Widget _buildTextFormattingInspector({
    required BuildContext context,
    required WebsiteBlockFieldSchema field,
    required Map<String, dynamic> currentData,
    required WebsiteResponsiveFieldOwner owner,
  }) {
    if (!field.supportsFormatting) return const SizedBox.shrink();

    final rawFormatting = currentData[field.resolvedFormattingKey];
    final formatting = TextFormatting.fromJson(
      rawFormatting is Map ? Map<String, dynamic>.from(rawFormatting) : null,
    );
    final formattingKey = field.resolvedFormattingKey;
    final formattingBinding = _schemaAsyncBinding(
      context: context,
      owner: owner,
      propertyKey: formattingKey,
    );
    final writeFormatting = _schemaTransaction(
      context: context,
      owner: owner,
      recaptureAccepted: false,
      properties: <WebsiteInlineManipulationProperty>[
        WebsiteInlineManipulationProperty(
          canonicalKey: formattingKey,
          policy: WebsiteResponsivePropertyPolicy.sharedOnly,
        ),
      ],
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
          transactionIdentity: formattingBinding.identity,
          asyncBinding: formattingBinding,
          onFormattingChanged: (value) => writeFormatting(
            <String, Object?>{formattingKey: value.toJson()},
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
    WebsiteBlockFieldSchema? actionLabelField,
    WebsiteBlockFieldSchema? actionVariantField,
    _SchemaRepeaterItemContext? itemContext,
    // Which document node this field belongs to. Explicit and required in
    // spirit: a nested field that fell back to the root used to write the
    // block instead of the item.
    WebsiteResponsiveFieldOwner owner = const WebsiteResponsiveRootField(),
  }) {
    dynamic raw = currentData[field.key];
    for (final alias in field.migrationAliases) {
      raw ??= currentData[alias];
    }
    if (itemContext != null &&
        itemContext.collectionTarget.ancestors.isNotEmpty &&
        field.type != WebsiteBlockFieldType.repeater) {
      return _buildDeepNestedSharedField(
        context: context,
        field: field,
        currentData: currentData,
        itemContext: itemContext,
        actionLabelField: actionLabelField,
        actionVariantField: actionVariantField,
      );
    }
    final label = field.label;
    final isResponsive = field.allowsViewportOverride;
    switch (field.type) {
      case WebsiteBlockFieldType.text:
        final binding = _schemaFieldBinding<String>(
          context: context,
          field: field,
          owner: owner,
          decode: WebsiteResponsiveScalarBinding.decodeText,
          fallback: field.defaultValue?.toString(),
        );
        if (field.key == 'videoUrl') {
          final current = binding.value ?? '';
          final writeVideoUrl = _schemaTransaction(
            context: context,
            owner: owner,
            properties: <WebsiteInlineManipulationProperty>[
              WebsiteInlineManipulationProperty.fromSchema(field),
              WebsiteInlineManipulationProperty(
                canonicalKey: 'videoFileUrl',
                policy: WebsiteResponsivePropertyPolicy.sharedOnly,
              ),
            ],
          );
          return _CollapsibleSection(
            title: 'YouTube / enlace avanzado',
            icon: Icons.link_rounded,
            initiallyExpanded: current.trim().isNotEmpty,
            children: [
              _EditorTextField(
                label: label,
                value: current,
                attribution: _bindingAttribution(binding),
                asyncBinding: _schemaAsyncBinding(
                  context: context,
                  owner: owner,
                  propertyKey: field.key,
                ),
                onChanged: (v) => writeVideoUrl(
                  <String, Object?>{
                    field.key: v,
                    if (v.trim().isNotEmpty) 'videoFileUrl': '',
                  },
                ),
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
              value: binding.value ?? '',
              attribution: _bindingAttribution(binding),
              asyncBinding: _schemaAsyncBinding(
                context: context,
                owner: owner,
                propertyKey: field.key,
              ),
              onChanged: binding.write,
            ),
            _buildTextFormattingInspector(
              context: context,
              field: field,
              currentData: currentData,
              owner: owner,
            ),
            _helpText(field.helpText),
          ],
        );
      case WebsiteBlockFieldType.textarea:
        final binding = _schemaFieldBinding<String>(
          context: context,
          field: field,
          owner: owner,
          decode: WebsiteResponsiveScalarBinding.decodeText,
          fallback: field.defaultValue?.toString(),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _EditorTextField(
              label: label,
              value: binding.value ?? '',
              attribution: _bindingAttribution(binding),
              asyncBinding: _schemaAsyncBinding(
                context: context,
                owner: owner,
                propertyKey: field.key,
              ),
              onChanged: binding.write,
              maxLines: 4,
            ),
            _buildTextFormattingInspector(
              context: context,
              field: field,
              currentData: currentData,
              owner: owner,
            ),
            _helpText(field.helpText),
          ],
        );
      case WebsiteBlockFieldType.richtext:
        final binding = _schemaFieldBinding<String>(
          context: context,
          field: field,
          owner: owner,
          decode: WebsiteResponsiveScalarBinding.decodeText,
          fallback: field.defaultValue?.toString(),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _EditorTextField(
              label: label,
              value: binding.value ?? '',
              attribution: _bindingAttribution(binding),
              asyncBinding: _schemaAsyncBinding(
                context: context,
                owner: owner,
                propertyKey: field.key,
              ),
              onChanged: binding.write,
              maxLines: 6,
              hint: '<p>...</p>',
            ),
            _helpText(field.helpText ?? 'Acepta HTML.'),
          ],
        );
      case WebsiteBlockFieldType.link:
        final binding = _schemaFieldBinding<String>(
          context: context,
          field: field,
          owner: owner,
          decode: WebsiteResponsiveScalarBinding.decodeText,
          fallback: field.defaultValue?.toString(),
        );
        final asyncBinding = _schemaAsyncBinding(
          context: context,
          owner: owner,
          propertyKey: field.key,
        );
        final current = binding.value ?? '';
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
          final editsVariantHere =
              variantKey != null && actionVariantField == null;
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
          final actionProperties = <WebsiteInlineManipulationProperty>[
            WebsiteInlineManipulationProperty.fromSchema(field),
            actionLabelField == null
                ? WebsiteInlineManipulationProperty(
                    canonicalKey: actionLabelKey,
                    policy: WebsiteResponsivePropertyPolicy.sharedOnly,
                  )
                : WebsiteInlineManipulationProperty.fromSchema(
                    actionLabelField,
                  ),
            if (editsVariantHere)
              WebsiteInlineManipulationProperty(
                canonicalKey: variantKey,
                policy: WebsiteResponsivePropertyPolicy.sharedOnly,
              ),
            WebsiteInlineManipulationProperty(
              canonicalKey: 'actions',
              policy: WebsiteResponsivePropertyPolicy.sharedOnly,
            ),
          ];
          final writeAction = _schemaTransaction(
            context: context,
            owner: owner,
            properties: actionProperties,
          );
          Object? workingActions = currentData['actions'];

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: _bindingAttribution(binding),
              ),
              const SizedBox(height: 6),
              WebsiteActionEditor(
                value: action,
                darkStyle: true,
                dense: true,
                asyncBinding: asyncBinding,
                // A schema-owned variant already has its own responsive shell
                // in Diseño. Showing it here would create a second control
                // with a different scope attribution for the same key.
                showVariant: editsVariantHere,
                onChanged: (next) {
                  final updates = <String, Object?>{
                    field.key: next.href,
                    actionLabelKey: next.label,
                  };
                  if (editsVariantHere) {
                    updates[variantKey] = next.variant.storageValue;
                  }
                  updates['actions'] = WebsiteActionValue.mergePrimary(
                    workingActions,
                    next,
                  );
                  final result = writeAction(updates);
                  if (result.accepted) workingActions = updates['actions'];
                  return result;
                },
              ),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _EditorFieldLabel(
              label: label,
              attribution: _bindingAttribution(binding),
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 6),
            WebsiteLinkValueEditor(
              label: '',
              value: current,
              helpText: field.helpText,
              dense: true,
              darkStyle: true,
              asyncBinding: asyncBinding,
              onChanged: binding.write,
            ),
          ],
        );
      case WebsiteBlockFieldType.color:
        final binding = _schemaFieldBinding<String>(
          context: context,
          field: field,
          owner: owner,
          decode: WebsiteResponsiveScalarBinding.decodeColor,
          fallback: field.defaultValue?.toString(),
        );
        final asyncBinding = _schemaAsyncBinding(
          context: context,
          owner: owner,
          propertyKey: field.key,
        );
        if (isResponsive) {
          final resolvedColor =
              binding.value ?? (field.defaultValue?.toString() ?? '');
          return _responsiveField<String>(
            binding: binding,
            child: WebsiteColorPickerField(
              label: '',
              value: resolvedColor.isEmpty ? '#000000' : resolvedColor,
              allowAlpha: true,
              asyncBinding: asyncBinding,
              onChanged: binding.write,
            ),
          );
        }
        final current = binding.value ?? '';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _EditorFieldLabel(
              label: label,
              attribution: _bindingAttribution(binding),
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 6),
            WebsiteColorPickerField(
              label: '',
              value: current.isEmpty ? '#000000' : current,
              helperText: field.helpText,
              allowAlpha: true,
              asyncBinding: asyncBinding,
              onChanged: binding.write,
            ),
          ],
        );
      case WebsiteBlockFieldType.image:
        // ONE media owner. The picker plus a desktop focal editor plus a
        // separate "Foco móvil" used to be mounted at the same time, each with
        // its own inheritance rule; the framing now belongs to the viewport
        // being previewed and opens only on demand.
        // The owner decides which factory, and therefore which node is
        // written. A nested image used to reach `root` here and write the
        // block's own `imageUrl` while the user was editing an item.
        final binding = switch (owner) {
          WebsiteResponsiveRootField() => WebsiteResponsiveMediaBinding.root(
              provider: provider,
              blockId: blockId,
              field: field,
              hostClass: _hostClass(context),
              viewport: _effectiveViewport(context),
            ),
          WebsiteResponsiveRepeaterField(
            collectionKeys: final collectionKeys,
            itemIndex: final itemIndex,
            identityKey: final identityKey,
            identityValue: final identityValue,
          ) =>
            WebsiteResponsiveMediaBinding.repeaterItem(
              provider: provider,
              blockId: blockId,
              field: field,
              collectionKeys: collectionKeys,
              itemIndex: itemIndex,
              identityKey: identityKey,
              identityValue: identityValue,
              hostClass: _hostClass(context),
              viewport: _effectiveViewport(context),
            ),
        };
        final altBinding = field.hasAltTextControl
            ? _schemaFieldBinding<String>(
                context: context,
                field: field.altTextField!,
                owner: owner,
                decode: WebsiteResponsiveScalarBinding.decodeText,
                fallback: '',
              )
            : null;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ResponsiveMediaField(
              state: binding.urlState,
              focalState: binding.focalState,
              onChanged: binding.writeUrl,
              onFocalChanged: binding.writeFocal,
              onCustomize: binding.customizeUrl,
              onReset: binding.resetUrl,
              onFocalCustomize: binding.customizeFocal,
              onFocalReset: binding.resetFocal,
              asyncBinding: _schemaAsyncBinding(
                context: context,
                owner: owner,
                propertyKey: field.key,
              ),
              focalAsyncBinding: _schemaAsyncBinding(
                context: context,
                owner: owner,
                propertyKey: '${field.key}.focal',
              ),
            ),
            // Alt text stays shared-only and appears exactly once: one subject,
            // one description.
            if (field.hasAltTextControl) ...[
              const SizedBox(height: 12),
              _EditorTextField(
                label: field.altTextField!.label,
                value: altBinding!.value ?? '',
                hint: 'Describe la imagen',
                attribution: _bindingAttribution(altBinding),
                asyncBinding: _schemaAsyncBinding(
                  context: context,
                  owner: owner,
                  propertyKey: field.altTextField!.key,
                ),
                onChanged: altBinding.write,
              ),
            ],
            _helpText(field.helpText),
          ],
        );
      case WebsiteBlockFieldType.video:
        final binding = _schemaFieldBinding<String>(
          context: context,
          field: field,
          owner: owner,
          decode: WebsiteResponsiveScalarBinding.decodeText,
        );
        final clearsYoutube = field.key == 'videoFileUrl';
        final writeVideo = _schemaTransaction(
          context: context,
          owner: owner,
          properties: <WebsiteInlineManipulationProperty>[
            WebsiteInlineManipulationProperty.fromSchema(field),
            if (clearsYoutube)
              WebsiteInlineManipulationProperty(
                canonicalKey: 'videoUrl',
                policy: WebsiteResponsivePropertyPolicy.sharedOnly,
              ),
          ],
        );
        final currentUrl = binding.value;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _EditorFieldLabel(
              label: label,
              attribution: _bindingAttribution(binding),
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 8),
            _VideoPicker(
              currentUrl: currentUrl,
              asyncBinding: _schemaAsyncBinding(
                context: context,
                owner: owner,
                propertyKey: field.key,
              ),
              onChanged: (url) => writeVideo(
                <String, Object?>{
                  field.key: url,
                  if (clearsYoutube && url.trim().isNotEmpty) 'videoUrl': '',
                },
              ),
            ),
            _helpText(field.helpText),
          ],
        );
      case WebsiteBlockFieldType.number:
        final min = field.min?.toDouble();
        final max = field.max?.toDouble();
        final step = field.step?.toDouble();
        final numberBinding = _schemaFieldBinding<num>(
          context: context,
          field: field,
          owner: owner,
          decode: WebsiteResponsiveScalarBinding.decodeNumber,
          fallback: field.defaultValue is num ? field.defaultValue as num : 0,
        );
        final currentNum = numberBinding.value?.toDouble() ?? 0.0;

        void writeNumber(num value) {
          numberBinding.write(value);
        }

        if (min != null && max != null) {
          int? divisions;
          if (step != null && step > 0) {
            final rawDiv = ((max - min) / step).round();
            if (rawDiv > 0 && rawDiv <= 200) divisions = rawDiv;
          }
          final clamped = currentNum.clamp(min, max);
          final asyncBinding = _schemaAsyncBinding(
            context: context,
            owner: owner,
            propertyKey: field.key,
          );
          final slider = _EditorSlider(
            label: isResponsive ? '' : label,
            attribution:
                isResponsive ? null : _bindingAttribution(numberBinding),
            value: clamped,
            min: min,
            max: max,
            divisions: divisions,
            valueLabel: clamped.toStringAsFixed(0),
            transactionIdentity: asyncBinding.identity,
            asyncBinding: asyncBinding,
            onCommit: writeNumber,
          );
          if (isResponsive) {
            return _responsiveField<num>(
              binding: numberBinding,
              child: slider,
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [slider, _helpText(field.helpText)],
          );
        }

        final numberField = _EditorTextField(
          label: isResponsive ? '' : label,
          attribution: isResponsive ? null : _bindingAttribution(numberBinding),
          value: numberBinding.value?.toString() ?? '',
          hint: '0',
          asyncBinding: _schemaAsyncBinding(
            context: context,
            owner: owner,
            propertyKey: field.key,
          ),
          onChanged: (v) {
            final parsed = num.tryParse(v);
            if (parsed != null) writeNumber(parsed);
          },
        );
        if (isResponsive) {
          return _responsiveField<num>(
            binding: numberBinding,
            child: numberField,
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [numberField, _helpText(field.helpText)],
        );
      case WebsiteBlockFieldType.toggle:
        final binding = _schemaFieldBinding<bool>(
          context: context,
          field: field,
          owner: owner,
          decode: WebsiteResponsiveScalarBinding.decodeBoolean,
          fallback: field.defaultValue == true,
        );
        if (isResponsive) {
          return _responsiveField<bool>(
            binding: binding,
            child: _EditorToggle(
              label: '',
              value: binding.value ?? (field.defaultValue == true),
              onChanged: binding.write,
            ),
          );
        }
        final currentBool = binding.value ?? false;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _EditorToggle(
              label: label,
              attribution: _bindingAttribution(binding),
              value: currentBool,
              onChanged: binding.write,
            ),
            _helpText(field.helpText),
          ],
        );
      case WebsiteBlockFieldType.select:
        final options = field.options
            .map((opt) => (opt.value, opt.label))
            .toList(growable: false);
        final binding = _schemaFieldBinding<String>(
          context: context,
          field: field,
          owner: owner,
          decode: WebsiteResponsiveScalarBinding.decodeOption,
          fallback: field.defaultValue?.toString() ??
              (options.isNotEmpty ? options.first.$1 : ''),
        );
        if (isResponsive) {
          return _responsiveField<String>(
            binding: binding,
            child: _EditorDropdown(
              label: '',
              value: binding.value ??
                  (field.defaultValue?.toString() ??
                      (options.isNotEmpty ? options.first.$1 : '')),
              options: options,
              onChanged: binding.write,
            ),
          );
        }
        final current = binding.value ?? '';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _EditorDropdown(
              label: label,
              attribution: _bindingAttribution(binding),
              value: current,
              options: options,
              onChanged: binding.write,
            ),
            _helpText(field.helpText),
          ],
        );
      case WebsiteBlockFieldType.chips:
        final binding = _schemaFieldBinding<List<String>>(
          context: context,
          field: field,
          owner: owner,
          decode: WebsiteResponsiveScalarBinding.decodeStringList,
          fallback: _toStringList(field.defaultValue),
        );
        if (isResponsive) {
          return _responsiveField<List<String>>(
            binding: binding,
            child: _EditorTextField(
              label: '',
              value: (binding.value ?? const <String>[]).join(', '),
              hint: 'separado por comas',
              asyncBinding: _schemaAsyncBinding(
                context: context,
                owner: owner,
                propertyKey: field.key,
              ),
              onChanged: (v) => binding.write(_toStringList(v)),
              maxLines: 2,
            ),
          );
        }
        final chips = binding.value ?? const <String>[];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _EditorTextField(
              label: label,
              attribution: _bindingAttribution(binding),
              value: chips.join(', '),
              hint: 'separado por comas',
              asyncBinding: _schemaAsyncBinding(
                context: context,
                owner: owner,
                propertyKey: field.key,
              ),
              onChanged: (v) => binding.write(_toStringList(v)),
              maxLines: 2,
            ),
            _helpText(field.helpText),
          ],
        );
      case WebsiteBlockFieldType.repeater:
        final items = _toMapList(raw);
        final collectionTarget = _collectionTarget(
          field: field,
          owner: owner,
          parentItem: itemContext,
        );
        final actionLabelKeys = field.itemFields
            .where((itemField) => itemField.actionLabelKey != null)
            .map((itemField) => itemField.actionLabelKey!)
            .toSet();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SchemaRepeaterEditor(
              field: field,
              target: collectionTarget,
              items: items,
              attribution: _sharedAttribution(
                context: context,
                field: field,
                owner: owner,
              ),
              onCommand: _repeaterCommandBinding(collectionTarget),
              itemBuilder: (
                context,
                index,
                itemData,
                childItemContext,
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
                  WebsiteBlockFieldSchema? actionVariantField;
                  final actionVariantKey = subField.actionVariantKey;
                  if (actionVariantKey != null) {
                    for (final candidate in field.itemFields) {
                      if (candidate.key == actionVariantKey) {
                        actionVariantField = candidate;
                        break;
                      }
                    }
                  }

                  final patchItem = _nestedItemPatchBinding(childItemContext);

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _buildSchemaField(
                      context: context,
                      field: subField,
                      currentData: itemData,
                      setValue: (value) => patchItem(<String, dynamic>{
                        subField.key: value,
                        for (final alias in subField.migrationAliases)
                          alias: value,
                      }),
                      actionLabelField: actionLabelField,
                      actionVariantField: actionVariantField,
                      itemContext: childItemContext,
                      // The item is the owner of everything below it. Identity
                      // is used when the item already has one; otherwise the
                      // explicit index addresses it, and nothing is invented.
                      owner: WebsiteResponsiveRepeaterField.forItem(
                        collectionKeys: <String>[
                          field.key,
                          ...field.migrationAliases,
                        ],
                        itemIndex: index,
                        item: itemData,
                      ),
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
                    actionLabelField: f.actionLabelKey == null
                        ? null
                        : fieldByKey[f.actionLabelKey],
                    actionVariantField: f.actionVariantKey == null
                        ? null
                        : fieldByKey[f.actionVariantKey],
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
                  actionLabelField: f.actionLabelKey == null
                      ? null
                      : fieldByKey[f.actionLabelKey],
                  actionVariantField: f.actionVariantKey == null
                      ? null
                      : fieldByKey[f.actionVariantKey],
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
            asyncBinding: WebsiteAsyncFieldBinding.pageBlock(
              provider: provider,
              target: WebsiteAsyncFieldTarget.block(
                blockId: blockId,
                scopeKey: 'legacy.root.title',
              ),
            ),
            onChanged: (v) => setFieldValue('title', v),
          ),
          const SizedBox(height: 16),
        ],
        if (hasSubtitle) ...[
          _EditorTextField(
            label: 'Subtítulo',
            value: data['subtitle']?.toString() ?? '',
            asyncBinding: WebsiteAsyncFieldBinding.pageBlock(
              provider: provider,
              target: WebsiteAsyncFieldTarget.block(
                blockId: blockId,
                scopeKey: 'legacy.root.subtitle',
              ),
            ),
            onChanged: (v) => setFieldValue('subtitle', v),
          ),
          const SizedBox(height: 16),
        ],
        if (hasDescription) ...[
          _EditorTextField(
            label: 'Descripción',
            value: data['description']?.toString() ?? '',
            asyncBinding: WebsiteAsyncFieldBinding.pageBlock(
              provider: provider,
              target: WebsiteAsyncFieldTarget.block(
                blockId: blockId,
                scopeKey: 'legacy.root.description',
              ),
            ),
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
