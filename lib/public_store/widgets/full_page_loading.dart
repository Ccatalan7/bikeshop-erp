import 'package:flutter/material.dart';
import '../../shared/widgets/branded_loading.dart';
import '../../shared/widgets/safe_layout_builder.dart';

/// A loading indicator that fills the full viewport height.
/// This prevents the footer from jumping up while content loads.
///
/// Usage:
/// ```dart
/// if (_isLoading) {
///   return const FullPageLoading();
/// }
/// ```
class FullPageLoading extends StatelessWidget {
  final String? message;
  final double size;

  const FullPageLoading({
    super.key,
    this.message,
    this.size = 80,
  });

  @override
  Widget build(BuildContext context) {
    // Use ConstraintLayoutBuilder to fill the full available height
    // This ensures the footer stays at the bottom of the viewport
    return ConstraintLayoutBuilder(
      builder: (context, constraints) {
        // Calculate minimum height to fill viewport (minus header/footer space)
        final viewportHeight = MediaQuery.of(context).size.height;
        // Keep at least 400px or viewport height minus estimated header/footer
        final minHeight = (viewportHeight - 300).clamp(400.0, viewportHeight);

        return SizedBox(
          height: minHeight,
          child: Center(
            child: BrandedLoading(
              size: size,
              message: message,
            ),
          ),
        );
      },
    );
  }
}
