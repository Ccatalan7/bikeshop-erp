import 'package:flutter/material.dart';

import 'website_block_content_presenters.dart';
import 'website_media_picker.dart';

/// Inline editable image widget for Odoo-style editing.
/// When edit mode is active, clicking on image shows upload options.
///
/// [editAffordance] selects the edit-mode interaction policy:
/// [WebsiteInlineMediaEditAffordance.hoverOverlay] (default) keeps the
/// classic full-surface hover/tap picker for simple images, while
/// [WebsiteInlineMediaEditAffordance.inspectorOnly] renders the image
/// completely passively — no hover overlay, no gesture surface, no inline
/// chrome — because the image is an interactive background under real
/// content (hero/carousel CTA, arrows, dots, nested selection) and its
/// canonical editing control lives in the block/slide inspector.
class InlineEditableImage extends StatefulWidget {
  final String? imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Alignment alignment;
  final bool isEditMode;
  final ValueChanged<String>? onChanged;
  final String? tenantId;
  final Widget? placeholder;
  final BorderRadius? borderRadius;
  final WebsiteInlineMediaEditAffordance editAffordance;

  const InlineEditableImage({
    super.key,
    this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.isEditMode = false,
    this.onChanged,
    this.tenantId,
    this.placeholder,
    this.borderRadius,
    this.editAffordance = WebsiteInlineMediaEditAffordance.hoverOverlay,
  });

  /// The classic full-surface hover overlay (hoverOverlay policy only).
  @visibleForTesting
  static const hoverOverlayKey =
      ValueKey<String>('website-inline-media-hover-overlay');

  @override
  State<InlineEditableImage> createState() => _InlineEditableImageState();
}

class _InlineEditableImageState extends State<InlineEditableImage> {
  bool _isHovering = false;

  Future<void> _pickAndUploadImage() async {
    if (!widget.isEditMode) return;
    try {
      final selection = await showWebsiteMediaPicker(
        context: context,
        currentUrl: widget.imageUrl,
      );
      if (selection != null) widget.onChanged?.call(selection.publicUrl);
    } catch (e) {
      debugPrint('Error selecting image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al seleccionar imagen: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasImage = widget.imageUrl != null && widget.imageUrl!.isNotEmpty;

    Widget imageWidget;

    if (hasImage) {
      imageWidget = Image.network(
        widget.imageUrl!,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        alignment: widget.alignment,
        errorBuilder: (context, error, stackTrace) {
          return _buildPlaceholder();
        },
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return _buildLoadingPlaceholder(loadingProgress);
        },
      );
    } else {
      imageWidget = _buildPlaceholder();
    }

    if (widget.borderRadius != null) {
      imageWidget = ClipRRect(
        borderRadius: widget.borderRadius!,
        child: imageWidget,
      );
    }

    if (!widget.isEditMode) {
      return imageWidget;
    }

    if (widget.editAffordance ==
        WebsiteInlineMediaEditAffordance.inspectorOnly) {
      // Interactive-background policy: the image renders exactly like the
      // public build — no hover overlay, no gesture surface, no inline
      // chrome — so the content above (CTA, arrows, dots, selection) keeps
      // its full surface. The canonical "change image" control is the
      // block/slide inspector's picker.
      return imageWidget;
    }

    // Edit mode - show upload overlay on hover/tap
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: GestureDetector(
        onTap: _pickAndUploadImage,
        child: Stack(
          children: [
            imageWidget,

            // Hover overlay
            if (_isHovering)
              Positioned.fill(
                key: InlineEditableImage.hoverOverlayKey,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    borderRadius: widget.borderRadius,
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.blue,
                            borderRadius: BorderRadius.circular(50),
                          ),
                          child: const Icon(
                            Icons.camera_alt,
                            color: Colors.white,
                            size: 32,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Cambiar imagen',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // Edit border
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: _isHovering
                        ? Colors.blue
                        : Colors.blue.withValues(alpha: 0.3),
                    width: _isHovering ? 3 : 1,
                  ),
                  borderRadius: widget.borderRadius,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return widget.placeholder ??
        Container(
          width: widget.width,
          height: widget.height ?? 200,
          color: Colors.grey.shade200,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.image,
                size: 48,
                color: Colors.grey.shade400,
              ),
              if (widget.isEditMode) ...[
                const SizedBox(height: 8),
                Text(
                  'Haz clic para agregar imagen',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 14,
                  ),
                ),
              ],
            ],
          ),
        );
  }

  Widget _buildLoadingPlaceholder(ImageChunkEvent loadingProgress) {
    final progress = loadingProgress.expectedTotalBytes != null
        ? loadingProgress.cumulativeBytesLoaded /
            loadingProgress.expectedTotalBytes!
        : null;

    return Container(
      width: widget.width,
      height: widget.height ?? 200,
      color: Colors.grey.shade100,
      child: Center(
        child: CircularProgressIndicator(value: progress),
      ),
    );
  }
}
