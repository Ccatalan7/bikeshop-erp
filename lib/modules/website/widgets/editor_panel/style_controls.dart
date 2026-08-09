part of '../website_editor_panel.dart';

const _surfaceVerticalPaddingAxis = WebsiteBlockFieldSchema(
  key: '@surfacePaddingVerticalAxis',
  label: 'Vertical',
  type: WebsiteBlockFieldType.number,
  responsivePolicy: WebsiteResponsivePropertyPolicy.responsiveOptional,
  propertyFamily: WebsiteResponsivePropertyFamily.spacing,
  authoringSurfaces: <WebsiteAuthoringSurface>{
    WebsiteAuthoringSurface.contextSheet,
    WebsiteAuthoringSurface.inspector,
  },
);

const _surfaceHorizontalPaddingAxis = WebsiteBlockFieldSchema(
  key: '@surfacePaddingHorizontalAxis',
  label: 'Horizontal',
  type: WebsiteBlockFieldType.number,
  responsivePolicy: WebsiteResponsivePropertyPolicy.responsiveOptional,
  propertyFamily: WebsiteResponsivePropertyFamily.spacing,
  authoringSurfaces: <WebsiteAuthoringSurface>{
    WebsiteAuthoringSurface.contextSheet,
    WebsiteAuthoringSurface.inspector,
  },
);

/// Canonical surface inspector for Website Builder blocks.
///
/// Storage projection belongs to [WebsiteBlockSurfaceStyle]. This control only
/// turns an explicit operator action into one provider lease/transaction. In
/// particular, sliders keep their draft locally and commit once on release.
class _BlockStyleControls extends StatefulWidget {
  const _BlockStyleControls({
    required this.blockId,
    required this.provider,
    required this.blockData,
    this.collapsible = true,
  });

  final String blockId;
  final WebsiteEditModeProvider provider;
  final Map<String, dynamic> blockData;
  final bool collapsible;

  @override
  State<_BlockStyleControls> createState() => _BlockStyleControlsState();
}

class _BlockStyleControlsState extends State<_BlockStyleControls> {
  WebsiteInlineManipulationLease? _activeLease;

  Map<String, dynamic> get _data => _blockDataOf(widget.blockData);

  WebsiteBlockType get _blockType => parseWebsiteBlockType(
        (widget.blockData['block_type'] ?? widget.blockData['type'] ?? '')
            .toString(),
      );

  WebsiteViewport _effectiveViewport(BuildContext context) =>
      WebsiteEditorAuthoringViewportScope.effectiveOf(
        context,
        fallback: widget.provider.previewViewport,
      );

  WebsiteAuthoringHostClass _hostClass(BuildContext context) =>
      WebsiteEditorChromeScope.maybeOf(context)?.hostClass ??
      WebsiteAuthoringHostClass.desktop;

  WebsiteInlineManipulationTarget? _targetFor({
    required Iterable<WebsiteInlineManipulationProperty> properties,
  }) {
    final viewport = widget.provider.renderedBlockViewportFor(widget.blockId);
    if (viewport == null) return null;
    return WebsiteInlineManipulationTarget(
      blockId: widget.blockId,
      owner: const WebsiteInlineBlockOwner(),
      viewport: viewport,
      properties: properties,
      requiresSelection: true,
    );
  }

  WebsiteInlineManipulationProperty _baseMapProperty(
    Map<String, dynamic> data,
  ) =>
      WebsiteInlineManipulationProperty(
        canonicalKey: WebsiteBlockSurfaceFields.baseMapKey(data),
        policy: WebsiteResponsivePropertyPolicy.sharedOnly,
      );

  void _cancelActiveGesture() {
    final lease = _activeLease;
    _activeLease = null;
    if (lease != null) widget.provider.cancelInlineManipulation(lease);
  }

  bool _beginSharedGesture() {
    _cancelActiveGesture();
    final target = _targetFor(properties: <WebsiteInlineManipulationProperty>[
      _baseMapProperty(_data),
    ]);
    if (target == null) return false;
    _activeLease = widget.provider.beginInlineManipulation(target);
    return _activeLease != null;
  }

  bool _commitSharedGesture(
    Map<WebsiteBlockFieldSchema, Object?> values,
  ) {
    final lease = _activeLease;
    _activeLease = null;
    if (lease == null) return false;
    final sourceData = _blockDataOf(lease.sourceBlock);
    final baseKey = WebsiteBlockSurfaceFields.baseMapKey(sourceData);
    return widget.provider.commitInlineManipulation(
      lease,
      <String, Object?>{
        baseKey: WebsiteBlockSurfaceFields.sharedMapWithValues(
          data: sourceData,
          values: values,
        ),
      },
    );
  }

  WebsiteInlineMutationResult _commitShared(
    Map<WebsiteBlockFieldSchema, Object?> values,
  ) {
    final data = _data;
    final target = _targetFor(properties: <WebsiteInlineManipulationProperty>[
      _baseMapProperty(data),
    ]);
    if (target == null) return WebsiteInlineMutationResult.rejected;
    final lease = widget.provider.captureInlineMutationLease(target);
    if (lease == null) return WebsiteInlineMutationResult.rejected;
    final sourceData = _blockDataOf(lease.sourceBlock);
    final baseKey = WebsiteBlockSurfaceFields.baseMapKey(sourceData);
    return widget.provider.commitInlineMutation(
      lease,
      <String, Object?>{
        baseKey: WebsiteBlockSurfaceFields.sharedMapWithValues(
          data: sourceData,
          values: values,
        ),
      },
    );
  }

  bool _beginPaddingGesture(Iterable<WebsiteBlockFieldSchema> fields) {
    _cancelActiveGesture();
    final viewport = widget.provider.renderedBlockViewportFor(widget.blockId);
    if (viewport == null) return false;
    final axisFields = fields.toList(growable: false);
    if (axisFields.isEmpty) return false;
    final axisScope = widget.provider.fieldWriteScope(
      blockId: widget.blockId,
      propertyKey: axisFields.first.key,
      policy: axisFields.first.responsivePolicy,
      viewport: viewport,
    );
    for (final field in axisFields.skip(1)) {
      final fieldScope = widget.provider.fieldWriteScope(
        blockId: widget.blockId,
        propertyKey: field.key,
        policy: field.responsivePolicy,
        viewport: viewport,
      );
      if (fieldScope == axisScope) continue;
      widget.provider.setFieldWriteScope(
        blockId: widget.blockId,
        propertyKey: field.key,
        policy: field.responsivePolicy,
        scope: axisScope,
        viewport: viewport,
      );
    }
    final data = _data;
    final properties = <String, WebsiteInlineManipulationProperty>{};
    var needsBaseMap = false;
    for (final field in axisFields) {
      final scope = widget.provider.fieldWriteScope(
        blockId: widget.blockId,
        propertyKey: field.key,
        policy: field.responsivePolicy,
        viewport: viewport,
      );
      if (scope == WebsiteWriteScope.shared) {
        needsBaseMap = true;
      } else {
        properties[field.key] =
            WebsiteInlineManipulationProperty.fromSchema(field);
      }
    }
    if (needsBaseMap) {
      final property = _baseMapProperty(data);
      properties[property.canonicalKey] = property;
    }
    final target = _targetFor(properties: properties.values);
    if (target == null) return false;
    _activeLease = widget.provider.beginInlineManipulation(target);
    return _activeLease != null;
  }

  bool _commitPaddingGesture(
    Map<WebsiteBlockFieldSchema, double> values,
  ) {
    final lease = _activeLease;
    _activeLease = null;
    if (lease == null) return false;
    final sourceData = _blockDataOf(lease.sourceBlock);
    final baseKey = WebsiteBlockSurfaceFields.baseMapKey(sourceData);
    final shared = <WebsiteBlockFieldSchema, Object?>{};
    final operation = <String, Object?>{};
    for (final entry in values.entries) {
      if (lease.writeScopes[entry.key.key] == WebsiteWriteScope.viewport) {
        operation[entry.key.key] = entry.value;
      } else {
        shared[entry.key] = entry.value;
      }
    }
    if (shared.isNotEmpty) {
      operation[baseKey] = WebsiteBlockSurfaceFields.sharedMapWithValues(
        data: sourceData,
        values: shared,
      );
    }
    return widget.provider.commitInlineManipulation(lease, operation);
  }

  void _customizePaddingAxis(
    Iterable<WebsiteBlockFieldSchema> fields,
  ) {
    final viewport = _effectiveViewport(context);
    for (final field in fields) {
      widget.provider.setFieldWriteScope(
        blockId: widget.blockId,
        propertyKey: field.key,
        policy: field.responsivePolicy,
        scope: WebsiteWriteScope.viewport,
        viewport: viewport,
      );
    }
  }

  void _resetPaddingAxis(
    Iterable<WebsiteBlockFieldSchema> fields,
  ) {
    final viewport = widget.provider.renderedBlockViewportFor(widget.blockId);
    if (viewport == null || !viewport.supportsOverride) return;
    final responsiveProperty = WebsiteInlineManipulationProperty(
      canonicalKey: WebsiteResponsiveDataCodec.containerKey,
      policy: WebsiteResponsivePropertyPolicy.sharedOnly,
    );
    final target = _targetFor(
      properties: <WebsiteInlineManipulationProperty>[responsiveProperty],
    );
    if (target == null) return;
    final lease = widget.provider.captureInlineMutationLease(target);
    if (lease == null) return;
    final sourceData = _blockDataOf(lease.sourceBlock);
    var next = sourceData;
    for (final field in fields) {
      next = WebsiteResponsiveDataCodec.clearOverride(
        data: next,
        propertyKey: field.key,
        viewport: viewport,
        policies: <String, WebsiteResponsivePropertyPolicy>{
          field.key: field.responsivePolicy,
        },
      );
    }
    final result = widget.provider.commitInlineMutation(
      lease,
      <String, Object?>{
        WebsiteResponsiveDataCodec.containerKey:
            next[WebsiteResponsiveDataCodec.containerKey],
      },
    );
    if (!result.accepted) return;
    for (final field in fields) {
      widget.provider.setFieldWriteScope(
        blockId: widget.blockId,
        propertyKey: field.key,
        policy: field.responsivePolicy,
        scope: WebsiteWriteScope.shared,
        viewport: viewport,
      );
    }
  }

  WebsiteResponsiveFieldState<double> _paddingState({
    required BuildContext context,
    required WebsiteBlockFieldSchema field,
    required WebsiteResolvedResponsiveValue<double> resolved,
    required double fallback,
  }) {
    final viewport = _effectiveViewport(context);
    final effectiveResolved = WebsiteResolvedResponsiveValue<double>(
      shared: resolved.shared ?? fallback,
      value: resolved.value ?? fallback,
      viewport: viewport,
      isOverride: resolved.isOverride,
      isLegacyOverride: resolved.isLegacyOverride,
    );
    return WebsiteResponsiveFieldState<double>.resolve(
      schema: field,
      context: WebsiteAuthoringContext(
        hostClass: _hostClass(context),
        previewViewport: viewport,
        writeScope: widget.provider.fieldWriteScope(
          blockId: widget.blockId,
          propertyKey: field.key,
          policy: field.responsivePolicy,
          viewport: viewport,
        ),
      ),
      resolved: effectiveResolved,
    );
  }

  WebsiteResponsiveFieldState<double> _paddingAxisState({
    required WebsiteBlockFieldSchema schema,
    required List<WebsiteBlockFieldSchema> fields,
    required List<WebsiteResolvedResponsiveValue<double>> resolved,
    required List<double> fallback,
  }) {
    assert(fields.length == 2);
    assert(resolved.length == 2);
    assert(fallback.length == 2);
    final viewport = _effectiveViewport(context);
    final fieldStates = <WebsiteResponsiveFieldState<double>>[
      for (var index = 0; index < fields.length; index++)
        _paddingState(
          context: context,
          field: fields[index],
          resolved: resolved[index],
          fallback: fallback[index],
        ),
    ];
    final values = <double>[
      for (var index = 0; index < resolved.length; index++)
        resolved[index].value ?? fallback[index],
    ];
    final sharedValues = <double>[
      for (var index = 0; index < resolved.length; index++)
        resolved[index].shared ?? fallback[index],
    ];
    final firstScope = fieldStates.first.effectiveWriteScope;
    final scopesMatch = fieldStates.every(
      (state) => state.effectiveWriteScope == firstScope,
    );
    return WebsiteResponsiveFieldState<double>.resolve(
      schema: schema,
      context: WebsiteAuthoringContext(
        hostClass: _hostClass(context),
        previewViewport: viewport,
        writeScope: scopesMatch ? firstScope : WebsiteWriteScope.shared,
      ),
      resolved: WebsiteResolvedResponsiveValue<double>(
        shared: _sameSurfaceValue(sharedValues) ? sharedValues.first : null,
        value: _sameSurfaceValue(values) ? values.first : null,
        viewport: viewport,
        isOverride: resolved.any((value) => value.isOverride),
        isLegacyOverride: resolved.any((value) => value.isLegacyOverride),
      ),
    );
  }

  WebsiteResponsiveFieldState<Object?> _sharedState(
    BuildContext context,
    WebsiteBlockFieldSchema field,
  ) {
    final viewport = _effectiveViewport(context);
    final value = WebsiteBlockSurfaceFields.baseMap(
        _data)[WebsiteBlockSurfaceFields.legacyKey(field)];
    return WebsiteResponsiveFieldState<Object?>.resolve(
      schema: field,
      context: WebsiteAuthoringContext(
        hostClass: _hostClass(context),
        previewViewport: viewport,
        writeScope: WebsiteWriteScope.shared,
      ),
      resolved: WebsiteResolvedResponsiveValue<Object?>(
        shared: value,
        value: value,
        viewport: viewport,
        isOverride: false,
        isLegacyOverride: false,
      ),
    );
  }

  @override
  void didUpdateWidget(covariant _BlockStyleControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.provider != widget.provider ||
        oldWidget.blockId != widget.blockId) {
      final lease = _activeLease;
      _activeLease = null;
      if (lease != null) oldWidget.provider.cancelInlineManipulation(lease);
    }
  }

  @override
  void dispose() {
    _cancelActiveGesture();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_blockType == WebsiteBlockType.footer) {
      return const VbNotice(
        title: 'Este bloque no tiene apariencia propia',
        body: 'Sólo reserva el espacio del pie de página. El pie visible se '
            'configura en los ajustes del sitio.',
        tone: VbNoticeTone.neutral,
      );
    }
    final data = _data;
    final viewport = _effectiveViewport(context);
    final surface = WebsiteBlockSurfaceStyle.resolve(
      data: data,
      viewport: viewport,
    );
    final fallback = WebsiteBlockSurfaceDefaults.paddingFor(
      blockType: _blockType,
      viewport: viewport,
      data: data,
    );
    final controls = <Widget>[
      const _SectionHeader('Fondo'),
      const SizedBox(height: 8),
      _BackgroundSurfaceControls(
        surface: surface,
        stateFor: (field) => _sharedState(context, field),
        commit: _commitShared,
        beginEdit: _beginSharedGesture,
        commitEdit: _commitSharedGesture,
        cancelEdit: _cancelActiveGesture,
      ),
      const SizedBox(height: 20),
      const _SectionHeader('Relleno'),
      const SizedBox(height: 8),
      ..._paddingControls(
        context: context,
        surface: surface,
        fallback: fallback,
      ),
      const SizedBox(height: 24),
      const _SectionHeader('Borde'),
      const SizedBox(height: 10),
      _BorderSurfaceControls(
        surface: surface,
        stateFor: (field) => _sharedState(context, field),
        commit: _commitShared,
        beginEdit: _beginSharedGesture,
        commitEdit: _commitSharedGesture,
        cancelEdit: _cancelActiveGesture,
      ),
      const SizedBox(height: 24),
      const _SectionHeader('Profundidad'),
      const SizedBox(height: 10),
      _ShadowSurfaceControls(
        surface: surface,
        stateFor: (field) => _sharedState(context, field),
        commit: _commitShared,
      ),
    ];

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: controls,
    );
    if (!widget.collapsible) return content;
    return _CollapsibleSection(
      title: 'Diseño y estilo',
      icon: Icons.brush_outlined,
      initiallyExpanded: false,
      children: controls,
    );
  }

  List<Widget> _paddingControls({
    required BuildContext context,
    required WebsiteBlockSurfaceStyle surface,
    required EdgeInsets fallback,
  }) {
    final axes = <({
      WebsiteBlockFieldSchema schema,
      List<WebsiteBlockFieldSchema> fields,
      List<WebsiteResolvedResponsiveValue<double>> resolved,
      List<double> fallback,
      List<double> choices,
      String key,
    })>[
      (
        schema: _surfaceVerticalPaddingAxis,
        fields: const <WebsiteBlockFieldSchema>[
          WebsiteBlockSurfaceFields.paddingTop,
          WebsiteBlockSurfaceFields.paddingBottom,
        ],
        resolved: <WebsiteResolvedResponsiveValue<double>>[
          surface.paddingTop,
          surface.paddingBottom,
        ],
        fallback: <double>[fallback.top, fallback.bottom],
        choices: WebsiteBlockSurfaceFields.verticalPaddingChoices,
        key: 'surface-padding-vertical',
      ),
      (
        schema: _surfaceHorizontalPaddingAxis,
        fields: const <WebsiteBlockFieldSchema>[
          WebsiteBlockSurfaceFields.paddingLeft,
          WebsiteBlockSurfaceFields.paddingRight,
        ],
        resolved: <WebsiteResolvedResponsiveValue<double>>[
          surface.paddingLeft,
          surface.paddingRight,
        ],
        fallback: <double>[fallback.left, fallback.right],
        choices: WebsiteBlockSurfaceFields.horizontalPaddingChoices,
        key: 'surface-padding-horizontal',
      ),
    ];
    return <Widget>[
      for (var index = 0; index < axes.length; index++) ...[
        if (index > 0) const SizedBox(height: 12),
        Builder(
          builder: (context) {
            final axis = axes[index];
            final values = <double>[
              for (var valueIndex = 0;
                  valueIndex < axis.resolved.length;
                  valueIndex++)
                axis.resolved[valueIndex].value ?? axis.fallback[valueIndex],
            ];
            final selected =
                _sameSurfaceValue(values) && axis.choices.contains(values.first)
                    ? values.first
                    : null;
            final state = _paddingAxisState(
              schema: axis.schema,
              fields: axis.fields,
              resolved: axis.resolved,
              fallback: axis.fallback,
            );
            return ResponsiveFieldShell<double>(
              key: ValueKey<String>('${axis.key}-field'),
              state: state,
              onCustomize: state.canCustomize
                  ? () => _customizePaddingAxis(axis.fields)
                  : null,
              onReset:
                  state.canReset ? () => _resetPaddingAxis(axis.fields) : null,
              child: selected != null
                  ? VbSegmented<double>(
                      key: ValueKey<String>(axis.key),
                      groupLabel: axis.schema.label,
                      value: selected,
                      options: <VbSegmentedOption<double>>[
                        for (final choice in axis.choices)
                          VbSegmentedOption<double>(
                            value: choice,
                            label: _formatSurfaceValue(choice),
                          ),
                      ],
                      onChanged: (value) {
                        if (!_beginPaddingGesture(axis.fields)) return;
                        _commitPaddingGesture(<WebsiteBlockFieldSchema, double>{
                          for (final field in axis.fields) field: value,
                        });
                      },
                    )
                  : _LegacySurfaceNotice(
                      adjustKey: ValueKey<String>('${axis.key}-adjust'),
                      valueLabel:
                          '${values.map(_formatSurfaceValue).join(' / ')} px',
                      onAdjust: () {
                        final adjusted = _nearestPublishedValue(
                          values.reduce((left, right) => left + right) /
                              values.length,
                          axis.choices,
                        );
                        if (!_beginPaddingGesture(axis.fields)) return;
                        _commitPaddingGesture(<WebsiteBlockFieldSchema, double>{
                          for (final field in axis.fields) field: adjusted,
                        });
                      },
                    ),
            );
          },
        ),
      ],
    ];
  }
}

typedef _SurfaceCommit = WebsiteInlineMutationResult Function(
  Map<WebsiteBlockFieldSchema, Object?> values,
);
typedef _SurfaceGestureCommit = bool Function(
  Map<WebsiteBlockFieldSchema, Object?> values,
);
typedef _SurfaceStateFor = WebsiteResponsiveFieldState<Object?> Function(
  WebsiteBlockFieldSchema field,
);

class _BackgroundSurfaceControls extends StatelessWidget {
  const _BackgroundSurfaceControls({
    required this.surface,
    required this.stateFor,
    required this.commit,
    required this.beginEdit,
    required this.commitEdit,
    required this.cancelEdit,
  });

  final WebsiteBlockSurfaceStyle surface;
  final _SurfaceStateFor stateFor;
  final _SurfaceCommit commit;
  final bool Function() beginEdit;
  final _SurfaceGestureCommit commitEdit;
  final VoidCallback cancelEdit;

  String? _raw(WebsiteBlockFieldSchema field) =>
      surface.base[WebsiteBlockSurfaceFields.legacyKey(field)]?.toString();

  @override
  Widget build(BuildContext context) {
    final isGradient = surface.backgroundType == 'gradient';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SharedSurfaceField(
          label: WebsiteBlockSurfaceFields.backgroundType.label,
          state: stateFor(WebsiteBlockSurfaceFields.backgroundType),
          child: _SurfaceChoiceRow(
            groupLabel: 'Tipo de fondo',
            choices: const <_SurfaceChoice>[
              _SurfaceChoice('solid', 'Sólido'),
              _SurfaceChoice('gradient', 'Degradado'),
              _SurfaceChoice('transparent', 'Transparente'),
            ],
            selected: surface.backgroundType,
            keyPrefix: 'surface-background-type',
            onSelected: (value) => commit(
              <WebsiteBlockFieldSchema, Object?>{
                WebsiteBlockSurfaceFields.backgroundType: value,
              },
            ),
          ),
        ),
        const SizedBox(height: 14),
        if (!isGradient && surface.backgroundType != 'transparent')
          _SharedSurfaceField(
            label: WebsiteBlockSurfaceFields.backgroundColor.label,
            state: stateFor(WebsiteBlockSurfaceFields.backgroundColor),
            child: WebsiteColorPickerField(
              label: 'Color',
              value: _raw(WebsiteBlockSurfaceFields.backgroundColor) ??
                  '#00000000',
              allowAlpha: true,
              allowTransparent: true,
              showInlineOpacity: false,
              onEditStart: beginEdit,
              onEditCancel: cancelEdit,
              onChanged: (value) {
                final color = parseWebsiteEditorColor(value);
                commitEdit(<WebsiteBlockFieldSchema, Object?>{
                  WebsiteBlockSurfaceFields.backgroundColor:
                      websiteEditorColorOpacity(color) == 0 ? null : value,
                });
              },
            ),
          )
        else if (isGradient) ...[
          _SharedSurfaceField(
            label: WebsiteBlockSurfaceFields.gradientColor1.label,
            state: stateFor(WebsiteBlockSurfaceFields.gradientColor1),
            child: WebsiteColorPickerField(
              label: 'Color inicial',
              value:
                  _raw(WebsiteBlockSurfaceFields.gradientColor1) ?? '#FFFFFF',
              showInlineOpacity: false,
              onEditStart: beginEdit,
              onEditCancel: cancelEdit,
              onChanged: (value) => commitEdit(
                <WebsiteBlockFieldSchema, Object?>{
                  WebsiteBlockSurfaceFields.gradientColor1: value,
                },
              ),
            ),
          ),
          const SizedBox(height: 14),
          _SharedSurfaceField(
            label: WebsiteBlockSurfaceFields.gradientColor2.label,
            state: stateFor(WebsiteBlockSurfaceFields.gradientColor2),
            child: WebsiteColorPickerField(
              label: 'Color final',
              value:
                  _raw(WebsiteBlockSurfaceFields.gradientColor2) ?? '#F0F0F0',
              showInlineOpacity: false,
              onEditStart: beginEdit,
              onEditCancel: cancelEdit,
              onChanged: (value) => commitEdit(
                <WebsiteBlockFieldSchema, Object?>{
                  WebsiteBlockSurfaceFields.gradientColor2: value,
                },
              ),
            ),
          ),
          const SizedBox(height: 14),
          _SharedSurfaceField(
            label: WebsiteBlockSurfaceFields.gradientDirection.label,
            state: stateFor(WebsiteBlockSurfaceFields.gradientDirection),
            child: _GradientDirectionPicker(
              currentDirection: surface.gradientDirection,
              onChanged: (value) => commit(
                <WebsiteBlockFieldSchema, Object?>{
                  WebsiteBlockSurfaceFields.gradientDirection: value,
                },
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _BorderSurfaceControls extends StatelessWidget {
  const _BorderSurfaceControls({
    required this.surface,
    required this.stateFor,
    required this.commit,
    required this.beginEdit,
    required this.commitEdit,
    required this.cancelEdit,
  });

  final WebsiteBlockSurfaceStyle surface;
  final _SurfaceStateFor stateFor;
  final _SurfaceCommit commit;
  final bool Function() beginEdit;
  final _SurfaceGestureCommit commitEdit;
  final VoidCallback cancelEdit;

  String? _raw(WebsiteBlockFieldSchema field) =>
      surface.base[WebsiteBlockSurfaceFields.legacyKey(field)]?.toString();

  @override
  Widget build(BuildContext context) {
    final hasBorder = surface.borderWidth > 0 && surface.borderStyle != 'none';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SharedSurfaceField(
          label: 'Borde',
          state: stateFor(WebsiteBlockSurfaceFields.borderWidth),
          helpText: 'Hairline es 1 px. El sistema no tiene bordes '
              'decorativos más gruesos.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SurfaceChoiceRow(
                groupLabel: 'Borde',
                choices: const <_SurfaceChoice>[
                  _SurfaceChoice('0', 'Ninguno'),
                  _SurfaceChoice('1', 'Hairline'),
                ],
                selected: WebsiteBlockSurfaceFields.borderWidthChoices
                        .contains(surface.borderWidth)
                    ? surface.borderWidth.toStringAsFixed(0)
                    : '',
                keyPrefix: 'surface-border-preset',
                onSelected: (value) {
                  final width = double.parse(value);
                  commit(<WebsiteBlockFieldSchema, Object?>{
                    WebsiteBlockSurfaceFields.borderWidth: width,
                    WebsiteBlockSurfaceFields.borderStyle:
                        width == 0 ? 'none' : 'solid',
                  });
                },
              ),
              if (!WebsiteBlockSurfaceFields.borderWidthChoices
                  .contains(surface.borderWidth)) ...[
                const SizedBox(height: 8),
                _LegacySurfaceNotice(
                  adjustKey: const ValueKey<String>(
                    'surface-border-preset-adjust',
                  ),
                  valueLabel: '${_formatSurfaceValue(surface.borderWidth)} px',
                  onAdjust: () => commit(<WebsiteBlockFieldSchema, Object?>{
                    WebsiteBlockSurfaceFields.borderWidth:
                        surface.borderWidth < 0.5 ? 0.0 : 1.0,
                    WebsiteBlockSurfaceFields.borderStyle:
                        surface.borderWidth < 0.5 ? 'none' : 'solid',
                  }),
                ),
              ],
            ],
          ),
        ),
        if (hasBorder) ...[
          const SizedBox(height: 14),
          _SharedSurfaceField(
            label: WebsiteBlockSurfaceFields.borderColor.label,
            state: stateFor(WebsiteBlockSurfaceFields.borderColor),
            child: WebsiteColorPickerField(
              label: 'Color',
              value: _raw(WebsiteBlockSurfaceFields.borderColor) ?? '#E0E0E0',
              allowAlpha: true,
              showInlineOpacity: false,
              onEditStart: beginEdit,
              onEditCancel: cancelEdit,
              onChanged: (value) => commitEdit(
                <WebsiteBlockFieldSchema, Object?>{
                  WebsiteBlockSurfaceFields.borderColor: value,
                  WebsiteBlockSurfaceFields.borderStyle: 'solid',
                },
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        _SharedSurfaceField(
          label: 'Radio',
          state: stateFor(WebsiteBlockSurfaceFields.borderRadius),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SurfaceChoiceRow(
                groupLabel: 'Radio',
                choices: const <_SurfaceChoice>[
                  _SurfaceChoice('0', 'Ninguno'),
                  _SurfaceChoice('4', '4'),
                  _SurfaceChoice('10', '10'),
                  _SurfaceChoice('14', '14'),
                ],
                selected: WebsiteBlockSurfaceFields.borderRadiusChoices
                        .contains(surface.borderRadius)
                    ? surface.borderRadius.toStringAsFixed(0)
                    : '',
                keyPrefix: 'surface-radius-preset',
                onSelected: (value) => commit(
                  <WebsiteBlockFieldSchema, Object?>{
                    WebsiteBlockSurfaceFields.borderRadius: double.parse(value),
                  },
                ),
              ),
              if (!WebsiteBlockSurfaceFields.borderRadiusChoices
                  .contains(surface.borderRadius)) ...[
                const SizedBox(height: 8),
                _LegacySurfaceNotice(
                  adjustKey: const ValueKey<String>(
                    'surface-radius-preset-adjust',
                  ),
                  valueLabel: '${_formatSurfaceValue(surface.borderRadius)} px',
                  onAdjust: () => commit(
                    <WebsiteBlockFieldSchema, Object?>{
                      WebsiteBlockSurfaceFields.borderRadius:
                          _nearestPublishedValue(
                        surface.borderRadius,
                        WebsiteBlockSurfaceFields.borderRadiusChoices,
                      ),
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ShadowSurfaceControls extends StatelessWidget {
  const _ShadowSurfaceControls({
    required this.surface,
    required this.stateFor,
    required this.commit,
  });

  final WebsiteBlockSurfaceStyle surface;
  final _SurfaceStateFor stateFor;
  final _SurfaceCommit commit;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SharedSurfaceField(
          label: 'Profundidad',
          state: stateFor(WebsiteBlockSurfaceFields.shadowEnabled),
          helpText: 'Tres alturas y nada más. Una tarjeta dentro de una '
              'tarjeta no gana sombra.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SurfaceChoiceRow(
                groupLabel: 'Profundidad',
                choices: const <_SurfaceChoice>[
                  _SurfaceChoice('none', 'Ninguna'),
                  _SurfaceChoice('raised', 'Elevada'),
                  _SurfaceChoice('popover', 'Flotante'),
                  _SurfaceChoice('overlay', 'Superpuesta'),
                ],
                selected: surface.depthPreset ?? '',
                keyPrefix: 'surface-shadow-preset',
                onSelected: (value) => commit(
                  WebsiteBlockSurfaceFields.depthValuesFor(value),
                ),
              ),
              if (surface.depthPreset == null) ...[
                const SizedBox(height: 8),
                _LegacySurfaceNotice(
                  adjustKey: const ValueKey<String>(
                    'surface-shadow-preset-adjust',
                  ),
                  title: 'Este bloque guarda una sombra que el sistema ya no '
                      'ofrece',
                  valueLabel: 'Se sigue publicando tal cual.',
                  onAdjust: () => commit(
                    WebsiteBlockSurfaceFields.depthValuesFor('popover'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _SharedSurfaceField extends StatelessWidget {
  const _SharedSurfaceField({
    required this.label,
    required this.state,
    required this.child,
    this.helpText,
  });

  final String label;
  final WebsiteResponsiveFieldState<Object?> state;
  final Widget child;
  final String? helpText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
            const SizedBox(width: 6),
            ResponsiveFieldAttribution<Object?>(state: state),
          ],
        ),
        if (helpText != null) ...[
          const SizedBox(height: 4),
          Text(
            helpText!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

class _LegacySurfaceNotice extends StatelessWidget {
  const _LegacySurfaceNotice({
    this.title = 'Personalizado heredado',
    this.adjustKey,
    required this.valueLabel,
    required this.onAdjust,
  });

  final String title;
  final Key? adjustKey;
  final String valueLabel;
  final VoidCallback onAdjust;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    return Semantics(
      container: true,
      label: '$title. $valueLabel',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          VbStatusBadge(
            label: title,
            tone: VbStatusTone.warning,
            dense: true,
          ),
          const SizedBox(height: 4),
          Text(
            valueLabel,
            style: theme.textTheme.bodySmall?.copyWith(
              color: roles.warning.accent,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Viene de un diseño anterior y no está en la escala. Se publica '
            'tal cual.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          TextButton(
            key: adjustKey,
            onPressed: onAdjust,
            child: const Text('Ajustar a la escala'),
          ),
        ],
      ),
    );
  }
}

double _nearestPublishedValue(double value, List<double> choices) {
  return choices.reduce(
    (best, candidate) =>
        (candidate - value).abs() < (best - value).abs() ? candidate : best,
  );
}

String _formatSurfaceValue(double value) => value == value.roundToDouble()
    ? value.toStringAsFixed(0)
    : value.toStringAsFixed(1);

bool _sameSurfaceValue(List<double> values) => values.length < 2
    ? true
    : values.skip(1).every((value) => (value - values.first).abs() < 0.001);

class _SurfaceChoice {
  const _SurfaceChoice(this.value, this.label);

  final String value;
  final String label;
}

class _SurfaceChoiceRow extends StatelessWidget {
  const _SurfaceChoiceRow({
    required this.groupLabel,
    required this.choices,
    required this.selected,
    required this.keyPrefix,
    required this.onSelected,
  });

  final String groupLabel;
  final List<_SurfaceChoice> choices;
  final String selected;
  final String keyPrefix;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    if (!choices.any((choice) => choice.value == selected)) {
      return const SizedBox.shrink();
    }
    return VbSegmented<String>(
      key: ValueKey<String>(keyPrefix),
      groupLabel: groupLabel,
      value: selected,
      options: <VbSegmentedOption<String>>[
        for (final choice in choices)
          VbSegmentedOption<String>(
            value: choice.value,
            label: choice.label,
          ),
      ],
      onChanged: onSelected,
    );
  }
}

class _GradientDirectionPicker extends StatelessWidget {
  const _GradientDirectionPicker({
    required this.currentDirection,
    required this.onChanged,
  });

  final String currentDirection;
  final ValueChanged<String> onChanged;

  static const _directions = <({String value, IconData icon, String label})>[
    (value: 'to-top', icon: Icons.arrow_upward, label: 'Arriba'),
    (value: 'to-top-right', icon: Icons.north_east, label: 'Arriba derecha'),
    (value: 'to-right', icon: Icons.arrow_forward, label: 'Derecha'),
    (
      value: 'to-bottom-right',
      icon: Icons.south_east,
      label: 'Abajo derecha',
    ),
    (value: 'to-bottom', icon: Icons.arrow_downward, label: 'Abajo'),
    (
      value: 'to-bottom-left',
      icon: Icons.south_west,
      label: 'Abajo izquierda',
    ),
    (value: 'to-left', icon: Icons.arrow_back, label: 'Izquierda'),
    (
      value: 'to-top-left',
      icon: Icons.north_west,
      label: 'Arriba izquierda',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final direction in _directions)
          Tooltip(
            message: direction.label,
            child: WebsiteEditorControlTarget(
              targetKey: ValueKey<String>(
                'surface-gradient-${direction.value}',
              ),
              semanticLabel: direction.label,
              minimumWidth: true,
              selected: currentDirection == direction.value,
              onTap: () => onChanged(direction.value),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: currentDirection == direction.value
                      ? roles.selectionContainer
                      : theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: currentDirection == direction.value
                        ? roles.info.border
                        : theme.dividerColor,
                  ),
                ),
                child: Icon(
                  direction.icon,
                  size: 16,
                  color: currentDirection == direction.value
                      ? roles.onSelectionContainer
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

Map<String, dynamic> _blockDataOf(Map<String, dynamic> block) {
  final raw = block['block_data'];
  if (raw is Map) return Map<String, dynamic>.from(raw);
  // A lease source for an item would already be block_data. Style always owns
  // the root block, but accepting this shape keeps the storage bridge pure.
  return Map<String, dynamic>.from(block);
}
