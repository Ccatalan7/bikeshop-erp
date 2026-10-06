/// Website and e-commerce data models
library;

export 'package:vinabike_public_core/public_store/models/online_order.dart';

import '../theme/website_resolved_theme.dart';
import 'website_font_registry.dart';

class WebsiteBanner {
  final String id;
  final String tenantId;
  final String title;
  final String? subtitle;
  final String? imageUrl;
  final String? link;
  final String? ctaText;
  final String? ctaLink;
  final bool active;
  final int orderIndex;
  final DateTime createdAt;
  final DateTime updatedAt;

  WebsiteBanner({
    required this.id,
    required this.tenantId,
    required this.title,
    this.subtitle,
    this.imageUrl,
    this.link,
    this.ctaText,
    this.ctaLink,
    required this.active,
    required this.orderIndex,
    required this.createdAt,
    required this.updatedAt,
  });

  factory WebsiteBanner.fromJson(Map<String, dynamic> json) {
    return WebsiteBanner(
      id: json['id'] as String,
      tenantId: json['tenant_id']?.toString() ?? '',
      title: json['title'] as String,
      subtitle: json['subtitle'] as String?,
      imageUrl: json['image_url'] as String?,
      link: json['link'] as String?,
      ctaText: json['cta_text'] as String?,
      ctaLink: json['cta_link'] as String?,
      active: json['active'] as bool? ?? true,
      orderIndex: json['order_index'] as int? ?? 0,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'tenant_id': tenantId,
      'title': title,
      'subtitle': subtitle,
      'image_url': imageUrl,
      'link': link,
      'cta_text': ctaText,
      'cta_link': ctaLink,
      'active': active,
      'order_index': orderIndex,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  WebsiteBanner copyWith({
    String? id,
    String? tenantId,
    String? title,
    String? subtitle,
    String? imageUrl,
    String? link,
    String? ctaText,
    String? ctaLink,
    bool? active,
    int? orderIndex,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return WebsiteBanner(
      id: id ?? this.id,
      tenantId: tenantId ?? this.tenantId,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      imageUrl: imageUrl ?? this.imageUrl,
      link: link ?? this.link,
      ctaText: ctaText ?? this.ctaText,
      ctaLink: ctaLink ?? this.ctaLink,
      active: active ?? this.active,
      orderIndex: orderIndex ?? this.orderIndex,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class FeaturedProduct {
  final String id;
  final String tenantId;
  final String productId;
  final bool active;
  final int orderIndex;
  final DateTime createdAt;

  FeaturedProduct({
    required this.id,
    required this.tenantId,
    required this.productId,
    required this.active,
    required this.orderIndex,
    required this.createdAt,
  });

  factory FeaturedProduct.fromJson(Map<String, dynamic> json) {
    return FeaturedProduct(
      id: json['id'] as String,
      tenantId: json['tenant_id']?.toString() ?? '',
      productId: json['product_id'] as String,
      active: json['active'] as bool? ?? true,
      orderIndex: json['order_index'] as int? ?? 0,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'tenant_id': tenantId,
      'product_id': productId,
      'active': active,
      'order_index': orderIndex,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

class WebsiteContent {
  final String id;
  final String tenantId;
  final String title;
  final String? content;
  final DateTime updatedAt;

  WebsiteContent({
    required this.id,
    required this.tenantId,
    required this.title,
    this.content,
    required this.updatedAt,
  });

  factory WebsiteContent.fromJson(Map<String, dynamic> json) {
    return WebsiteContent(
      id: json['id'] as String,
      tenantId: json['tenant_id']?.toString() ?? '',
      title: json['title'] as String,
      content: json['content'] as String?,
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'tenant_id': tenantId,
      'title': title,
      'content': content,
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}

class ThemePreset {
  final String id;
  final String tenantId;
  final String name;
  final String? description;
  final int primaryColor;
  final int accentColor;
  final int backgroundColor;
  final int textColor;
  final String headingFont;
  final String bodyFont;
  final double headingSize;
  final double bodySize;
  final double sectionSpacing;
  final double containerPadding;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ThemePreset({
    required this.id,
    required this.tenantId,
    required this.name,
    this.description,
    required this.primaryColor,
    required this.accentColor,
    required this.backgroundColor,
    required this.textColor,
    required this.headingFont,
    required this.bodyFont,
    required this.headingSize,
    required this.bodySize,
    required this.sectionSpacing,
    required this.containerPadding,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ThemePreset.fromJson(Map<String, dynamic> json) {
    double parseDouble(dynamic value, double fallback) {
      if (value is num) return value.toDouble();
      if (value is String) {
        final parsed = double.tryParse(value);
        if (parsed != null) return parsed;
      }
      return fallback;
    }

    int parseColor(dynamic value, int fallback) {
      if (value is int) return value;
      if (value is String) {
        final trimmed = value.trim();
        if (trimmed.isEmpty) return fallback;
        final parsed = int.tryParse(trimmed);
        if (parsed != null) return parsed;
        final hex = trimmed.replaceAll('#', '');
        final hexValue = int.tryParse(hex, radix: 16);
        if (hexValue != null) {
          return hex.length <= 6 ? 0xFF000000 | hexValue : hexValue;
        }
      }
      return fallback;
    }

    DateTime parseDate(dynamic value, DateTime fallback) {
      if (value is DateTime) return value;
      if (value is String) {
        final parsed = DateTime.tryParse(value);
        if (parsed != null) return parsed.toUtc();
      }
      return fallback;
    }

    final now = DateTime.now().toUtc();

    return ThemePreset(
      id: (json['id'] ?? '').toString(),
      tenantId: json['tenant_id']?.toString() ?? '',
      name: (json['name'] ?? 'Preset sin título').toString(),
      description: json['description'] as String?,
      primaryColor: parseColor(
        json['primaryColor'],
        WebsiteResolvedTheme.defaultPrimaryColor.toARGB32(),
      ),
      accentColor: parseColor(
        json['accentColor'],
        WebsiteResolvedTheme.defaultAccentColor.toARGB32(),
      ),
      backgroundColor: parseColor(json['backgroundColor'], 0xFFFFFFFF),
      textColor: parseColor(json['textColor'], 0xFF212121),
      headingFont: WebsiteFontRegistry.resolveHeadingFont(
        json['headingFont']?.toString(),
      ),
      bodyFont: WebsiteFontRegistry.resolveBodyFont(
        json['bodyFont']?.toString(),
      ),
      headingSize: parseDouble(json['headingSize'], 48.0),
      bodySize: parseDouble(json['bodySize'], 16.0),
      sectionSpacing: parseDouble(json['sectionSpacing'], 64.0),
      containerPadding: parseDouble(json['containerPadding'], 24.0),
      createdAt: parseDate(json['createdAt'], now),
      updatedAt: parseDate(json['updatedAt'], now),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'tenant_id': tenantId,
      'name': name,
      'description': description,
      'primaryColor': primaryColor,
      'accentColor': accentColor,
      'backgroundColor': backgroundColor,
      'textColor': textColor,
      'headingFont': headingFont,
      'bodyFont': bodyFont,
      'headingSize': headingSize,
      'bodySize': bodySize,
      'sectionSpacing': sectionSpacing,
      'containerPadding': containerPadding,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  ThemePreset copyWith({
    String? id,
    String? tenantId,
    String? name,
    String? description,
    int? primaryColor,
    int? accentColor,
    int? backgroundColor,
    int? textColor,
    String? headingFont,
    String? bodyFont,
    double? headingSize,
    double? bodySize,
    double? sectionSpacing,
    double? containerPadding,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ThemePreset(
      id: id ?? this.id,
      tenantId: tenantId ?? this.tenantId,
      name: name ?? this.name,
      description: description ?? this.description,
      primaryColor: primaryColor ?? this.primaryColor,
      accentColor: accentColor ?? this.accentColor,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      textColor: textColor ?? this.textColor,
      headingFont: headingFont ?? this.headingFont,
      bodyFont: bodyFont ?? this.bodyFont,
      headingSize: headingSize ?? this.headingSize,
      bodySize: bodySize ?? this.bodySize,
      sectionSpacing: sectionSpacing ?? this.sectionSpacing,
      containerPadding: containerPadding ?? this.containerPadding,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class WebsiteSetting {
  final String id;
  final String tenantId;
  final String key;
  final String? value;
  final String? description;
  final DateTime updatedAt;

  WebsiteSetting({
    required this.id,
    required this.tenantId,
    required this.key,
    this.value,
    this.description,
    required this.updatedAt,
  });

  factory WebsiteSetting.fromJson(Map<String, dynamic> json) {
    return WebsiteSetting(
      id: json['id'] as String,
      tenantId: json['tenant_id']?.toString() ?? '',
      key: json['key'] as String,
      value: json['value'] as String?,
      description: json['description'] as String?,
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'tenant_id': tenantId,
      'key': key,
      'value': value,
      'description': description,
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}
