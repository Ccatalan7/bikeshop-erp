import 'package:flutter/material.dart';

import '../../../shared/themes/vinabike_theme_roles.dart';
import '../../../shared/widgets/vb_segmented.dart';
import '../models/website_responsive_field_state.dart';
import 'focal_point_picker.dart';
import 'responsive_field_shell.dart';
import 'website_media_picker.dart';

/// One reusable media control for every consumer: schema, Hero, Carousel and,
/// later, Canvas.
///
/// Design source: `Website Builder Responsive Authoring` t10 frames 10a
/// (compact media row), 10b (override) and 10f (phone sheet).
///
/// The screenshot that started the plan showed a large picker plus a desktop
/// focal editor plus a mobile focal editor, all expanded at once. This widget
/// makes that impossible by construction:
///
/// * the collapsed state is **one** row — 48 thumbnail, name, state, actions;
/// * `Reencuadrar` is on-demand precision, not a permanently mounted editor;
/// * there is exactly **one** focal editor, for the viewport being previewed,
///   because the resolved value already belongs to that viewport.
///
/// It never touches persistence. Every write leaves through the callbacks, and
/// the inheritance state comes from an already-resolved
/// [WebsiteResponsiveFieldState] owned by the provider.
class ResponsiveMediaField extends StatefulWidget {
  const ResponsiveMediaField({
    super.key,
    required this.state,
    required this.onChanged,
    required this.focalState,
    required this.onFocalChanged,
    this.onCustomize,
    this.onReset,
    this.onFocalCustomize,
    this.onFocalReset,
    this.allowProductLink = false,
    this.density,
  });

  /// Inheritance state of the image URL itself.
  final WebsiteResponsiveFieldState<String> state;

  /// Emits the newly chosen asset URL. Persistence belongs to the caller.
  final ValueChanged<String> onChanged;

  /// Inheritance state of the focal point, or null when the schema declares no
  /// focal capability.
  ///
  /// A logo, an avatar or inline media has nothing to reframe. In that case the
  /// control offers no `Reencuadrar` action, mounts no focal shell or picker,
  /// and can therefore never write a focal key.
  final WebsiteResponsiveFieldState<Offset>? focalState;

  /// Emits the new normalized focal point. Null when focal is unsupported.
  final void Function(double x, double y)? onFocalChanged;

  final VoidCallback? onCustomize;
  final VoidCallback? onReset;
  final VoidCallback? onFocalCustomize;
  final VoidCallback? onFocalReset;

  final bool allowProductLink;
  final VbDensity? density;

  @visibleForTesting
  static const Key replaceActionKey = Key('responsive-media-replace');

  @visibleForTesting
  static const Key reframeActionKey = Key('responsive-media-reframe');

  @visibleForTesting
  static const Key focalEditorKey = Key('responsive-media-focal-editor');

  @visibleForTesting
  static const Key thumbnailKey = Key('responsive-media-thumbnail');

  /// t10 frame 10a · the compact media row thumbnail.
  static const double thumbnailSize = 48;

  @override
  State<ResponsiveMediaField> createState() => _ResponsiveMediaFieldState();
}

class _ResponsiveMediaFieldState extends State<ResponsiveMediaField> {
  /// Transient. Reframing is a mode, never published data.
  bool _reframing = false;

  String get _url => widget.state.resolved.value?.trim() ?? '';

  bool get _hasImage => _url.isNotEmpty;

  /// Declared by the schema, never assumed from the fact that it is an image.
  bool get _supportsFocalPoint =>
      widget.focalState != null && widget.onFocalChanged != null;

  Future<void> _replace() async {
    final asset = await showWebsiteMediaPicker(
      context: context,
      currentUrl: _hasImage ? _url : null,
      allowProductLink: widget.allowProductLink,
    );
    if (asset == null) return;
    widget.onChanged(asset.publicUrl);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final density = widget.density ?? VbDensity.resolve(context);

    // The shell owns label, status, scope sentence and the customize/reset
    // actions. This widget only supplies the control itself.
    return ResponsiveFieldShell<String>(
      state: widget.state,
      onCustomize: widget.onCustomize,
      onReset: widget.onReset,
      density: density,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _MediaRow(
            url: _url,
            density: density,
            roles: roles,
            theme: theme,
            reframing: _reframing,
            onReplace: _replace,
            // No focal capability, no reframing affordance at all.
            onToggleReframe: _hasImage && _supportsFocalPoint
                ? () => setState(() => _reframing = !_reframing)
                : null,
            showReframe: _supportsFocalPoint,
          ),
          // Precision on demand, and only ever ONE focal editor: the resolved
          // focal already belongs to the viewport being previewed.
          if (_reframing && _hasImage && _supportsFocalPoint) ...[
            const SizedBox(height: 8),
            _FocalEditor(
              key: ResponsiveMediaField.focalEditorKey,
              url: _url,
              focalState: widget.focalState!,
              onFocalChanged: widget.onFocalChanged!,
              onCustomize: widget.onFocalCustomize,
              onReset: widget.onFocalReset,
              density: density,
            ),
          ],
        ],
      ),
    );
  }
}

class _MediaRow extends StatelessWidget {
  const _MediaRow({
    required this.url,
    required this.density,
    required this.roles,
    required this.theme,
    required this.reframing,
    required this.onReplace,
    required this.onToggleReframe,
    required this.showReframe,
  });

  final String url;
  final VbDensity density;
  final VinabikeThemeRoles roles;
  final ThemeData theme;
  final bool reframing;
  final VoidCallback onReplace;
  final VoidCallback? onToggleReframe;
  final bool showReframe;

  @override
  Widget build(BuildContext context) {
    final hasImage = url.isNotEmpty;
    final labelStyle = (theme.textTheme.labelMedium ?? const TextStyle())
        .copyWith(fontSize: 11, fontWeight: FontWeight.w500);

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        // `F-05`: a surface inside a surface earns surfaceSunken or a hairline,
        // never a shadow.
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: roles.neutral.border),
      ),
      // The row must survive a NESTED width: inside a repeater's indented
      // section at 390 it receives roughly 250 px, and a fixed single line
      // overflowed there. `Wrap` keeps the same one-line composition whenever
      // it fits and moves the actions to a second line when it does not — no
      // new value, no truncated label, no hidden action. The identity is
      // capped at the full row width so a long file name ellipsizes instead of
      // pushing the actions out.
      child: LayoutBuilder(
        builder: (context, constraints) {
          final identity = ConstrainedBox(
            constraints: BoxConstraints(maxWidth: constraints.maxWidth),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  key: ResponsiveMediaField.thumbnailKey,
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: ResponsiveMediaField.thumbnailSize,
                    height: ResponsiveMediaField.thumbnailSize,
                    child: hasImage
                        ? Image.network(
                            url,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => ColoredBox(
                              color: roles.neutral.container,
                              child: Icon(
                                Icons.broken_image_outlined,
                                size: 18,
                                color: roles.neutral.onContainer,
                              ),
                            ),
                          )
                        : ColoredBox(
                            color: roles.neutral.container,
                            child: Icon(
                              Icons.image_outlined,
                              size: 18,
                              color: roles.neutral.onContainer,
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    hasImage ? _fileNameOf(url) : 'Sin imagen',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        labelStyle.copyWith(color: theme.colorScheme.onSurface),
                  ),
                ),
              ],
            ),
          );

          return Wrap(
            // The gap the row already used between identity and actions.
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              identity,
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _RowAction(
                    key: ResponsiveMediaField.replaceActionKey,
                    label: hasImage ? 'Cambiar' : 'Elegir',
                    density: density,
                    onPressed: onReplace,
                  ),
                  if (showReframe)
                    _RowAction(
                      key: ResponsiveMediaField.reframeActionKey,
                      label: 'Reencuadrar',
                      density: density,
                      selected: reframing,
                      onPressed: onToggleReframe,
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  static String _fileNameOf(String url) {
    final path = Uri.tryParse(url)?.pathSegments;
    if (path == null || path.isEmpty) return url;
    return path.last.isEmpty ? url : path.last;
  }
}

class _RowAction extends StatelessWidget {
  const _RowAction({
    super.key,
    required this.label,
    required this.density,
    required this.onPressed,
    this.selected = false,
  });

  final String label;
  final VbDensity density;
  final VoidCallback? onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        // `F-06`: touch forces 48.
        minimumSize: Size(0, density.controlHeight),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          // Selection is legible without colour.
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
    );
  }
}

/// The single focal editor, wrapped in its own shell so its inheritance is as
/// explicit as the asset's.
class _FocalEditor extends StatelessWidget {
  const _FocalEditor({
    super.key,
    required this.url,
    required this.focalState,
    required this.onFocalChanged,
    required this.onCustomize,
    required this.onReset,
    required this.density,
  });

  final String url;
  final WebsiteResponsiveFieldState<Offset> focalState;
  final void Function(double x, double y) onFocalChanged;
  final VoidCallback? onCustomize;
  final VoidCallback? onReset;
  final VbDensity density;

  @override
  Widget build(BuildContext context) {
    final focal = focalState.resolved.value ?? const Offset(0.5, 0.5);
    return ResponsiveFieldShell<Offset>(
      state: focalState,
      onCustomize: onCustomize,
      onReset: onReset,
      density: density,
      child: FocalPointPicker(
        imageUrl: url,
        focalX: focal.dx,
        focalY: focal.dy,
        onChanged: onFocalChanged,
      ),
    );
  }
}
