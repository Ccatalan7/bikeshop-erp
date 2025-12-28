import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../../shared/services/image_service.dart';

/// Inline editable image widget for Odoo-style editing.
/// When edit mode is active, clicking on image shows upload options.
class InlineEditableImage extends StatefulWidget {
  final String? imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final bool isEditMode;
  final ValueChanged<String>? onChanged;
  final String? tenantId;
  final Widget? placeholder;
  final BorderRadius? borderRadius;

  const InlineEditableImage({
    super.key,
    this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.isEditMode = false,
    this.onChanged,
    this.tenantId,
    this.placeholder,
    this.borderRadius,
  });

  @override
  State<InlineEditableImage> createState() => _InlineEditableImageState();
}

class _InlineEditableImageState extends State<InlineEditableImage> {
  bool _isUploading = false;
  bool _isHovering = false;

  Future<void> _pickAndUploadImage() async {
    if (!widget.isEditMode) return;

    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1920,
      maxHeight: 1080,
      imageQuality: 85,
    );

    if (pickedFile == null) return;

    setState(() => _isUploading = true);

    try {
      final bytes = await pickedFile.readAsBytes();
      final fileName = 'website_${DateTime.now().millisecondsSinceEpoch}_${pickedFile.name}';
      
      // Upload with automatic optimization (resizes to max 1200px, compresses as JPEG)
      final url = await ImageService.uploadWebsiteImageWithOptimization(
        bytes: bytes,
        fileName: fileName,
      );

      if (url != null) {
        widget.onChanged?.call(url);
      }
    } catch (e) {
      debugPrint('Error uploading image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al subir imagen: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
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
            if (_isHovering || _isUploading)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    borderRadius: widget.borderRadius,
                  ),
                  child: Center(
                    child: _isUploading
                        ? const Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircularProgressIndicator(color: Colors.white),
                              SizedBox(height: 8),
                              Text(
                                'Subiendo...',
                                style: TextStyle(color: Colors.white),
                              ),
                            ],
                          )
                        : Column(
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
                    color: _isHovering ? Colors.blue : Colors.blue.withValues(alpha: 0.3),
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
        ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
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
