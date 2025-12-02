import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../modules/settings/services/appearance_service.dart';

/// A branded loading indicator that shows the company logo if configured,
/// otherwise falls back to a standard circular progress indicator.
/// 
/// Usage:
/// ```dart
/// // Simple usage - uses logo from AppearanceService
/// const BrandedLoading()
/// 
/// // With custom size
/// const BrandedLoading(size: 64)
/// 
/// // In a center widget
/// const Center(child: BrandedLoading())
/// ```
class BrandedLoading extends StatefulWidget {
  /// The size of the loading indicator (width and height)
  final double size;
  
  /// Whether to show a pulsing animation on the logo
  final bool animate;
  
  /// Optional message to show below the loading indicator
  final String? message;

  const BrandedLoading({
    super.key,
    this.size = 200,
    this.animate = true,
    this.message,
  });

  @override
  State<BrandedLoading> createState() => _BrandedLoadingState();
}

class _BrandedLoadingState extends State<BrandedLoading>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    _opacityAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    if (widget.animate) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appearanceService = context.watch<AppearanceService>();
    final logoUrl = appearanceService.companyLogoUrl;
    final hasLogo = logoUrl != null && logoUrl.isNotEmpty;

    Widget loadingWidget;

    if (hasLogo) {
      // Branded loading with company logo
      loadingWidget = AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Transform.scale(
            scale: widget.animate ? _scaleAnimation.value : 1.0,
            child: Opacity(
              opacity: widget.animate ? _opacityAnimation.value : 1.0,
              child: child,
            ),
          );
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(widget.size * 0.15),
          child: CachedNetworkImage(
            imageUrl: logoUrl,
            width: widget.size,
            height: widget.size,
            fit: BoxFit.contain,
            placeholder: (context, url) => _buildFallbackIndicator(),
            errorWidget: (context, url, error) => _buildFallbackIndicator(),
          ),
        ),
      );
    } else {
      // Standard loading indicator
      loadingWidget = _buildFallbackIndicator();
    }

    if (widget.message != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          loadingWidget,
          const SizedBox(height: 16),
          Text(
            widget.message!,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      );
    }

    return loadingWidget;
  }

  Widget _buildFallbackIndicator() {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Padding(
        padding: EdgeInsets.all(widget.size * 0.15),
        child: CircularProgressIndicator(
          strokeWidth: widget.size > 40 ? 3 : 2,
        ),
      ),
    );
  }
}

/// A full-screen branded loading overlay
class BrandedLoadingOverlay extends StatelessWidget {
  final String? message;
  
  const BrandedLoadingOverlay({
    super.key,
    this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Center(
        child: BrandedLoading(
          size: 80,
          message: message,
        ),
      ),
    );
  }
}
