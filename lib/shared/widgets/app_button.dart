import 'package:flutter/material.dart';
import '../themes/app_theme.dart';

class AppButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final ButtonType type;
  final bool isLoading;
  final IconData? icon;
  final double? width;
  final bool fullWidth;
  
  const AppButton({
    super.key,
    required this.text,
    this.onPressed,
    this.type = ButtonType.primary,
    this.isLoading = false,
    this.icon,
    this.width,
    this.fullWidth = false,
  });
  
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isMobile = AppTheme.isMobile(context);
    
    Color backgroundColor;
    Color foregroundColor;
    
    switch (type) {
      case ButtonType.primary:
        backgroundColor = theme.primaryColor;
        foregroundColor = Colors.white;
        break;
      case ButtonType.secondary:
        backgroundColor = theme.colorScheme.secondary;
        foregroundColor = Colors.white;
        break;
      case ButtonType.danger:
        backgroundColor = Colors.red[600]!;
        foregroundColor = Colors.white;
        break;
      case ButtonType.outline:
        backgroundColor = Colors.transparent;
        foregroundColor = theme.primaryColor;
        break;
    }
    
    // Mobile-optimized sizing
    final double horizontalPadding = isMobile ? 20.0 : 24.0;
    final double verticalPadding = isMobile ? 14.0 : 12.0;
    final double iconSize = isMobile ? 22.0 : 18.0;
    final double fontSize = isMobile ? 15.0 : 14.0;
    
    Widget buttonChild = Row(
      mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (isLoading) ...[
          SizedBox(
            width: iconSize,
            height: iconSize,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(
                type == ButtonType.outline ? theme.primaryColor : Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 12),
        ] else if (icon != null) ...[
          Icon(icon, size: iconSize),
          const SizedBox(width: 10),
        ],
        Text(
          text,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
    
    if (type == ButtonType.outline) {
      return SizedBox(
        width: fullWidth ? double.infinity : width,
        child: OutlinedButton(
          onPressed: isLoading ? null : onPressed,
          style: OutlinedButton.styleFrom(
            foregroundColor: foregroundColor,
            side: BorderSide(color: theme.primaryColor, width: 1.5),
            minimumSize: Size(
              AppTheme.mobileMinTouchTarget,
              AppTheme.mobileMinTouchTarget,
            ),
            padding: EdgeInsets.symmetric(
              horizontal: horizontalPadding,
              vertical: verticalPadding,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(isMobile ? 10 : 8),
            ),
          ),
          child: buttonChild,
        ),
      );
    }
    
    return SizedBox(
      width: fullWidth ? double.infinity : width,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
          disabledBackgroundColor: backgroundColor.withOpacity(0.5),
          disabledForegroundColor: foregroundColor.withOpacity(0.5),
          minimumSize: Size(
            AppTheme.mobileMinTouchTarget,
            AppTheme.mobileMinTouchTarget,
          ),
          padding: EdgeInsets.symmetric(
            horizontal: horizontalPadding,
            vertical: verticalPadding,
          ),
          elevation: isMobile ? 2 : 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(isMobile ? 10 : 8),
          ),
        ),
        child: buttonChild,
      ),
    );
  }
}

enum ButtonType {
  primary,
  secondary,
  danger,
  outline,
}