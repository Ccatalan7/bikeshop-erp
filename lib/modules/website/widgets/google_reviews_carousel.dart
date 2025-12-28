import 'package:flutter/material.dart';

class GoogleReviewsCarousel extends StatelessWidget {
  final Map<String, dynamic> data;
  final Color primaryColor;
  final Color accentColor;
  final String? headingFont;
  final String? bodyFont;
  final bool previewMode;

  const GoogleReviewsCarousel({
    super.key,
    required this.data,
    required this.primaryColor,
    required this.accentColor,
    this.headingFont,
    this.bodyFont,
    this.previewMode = false,
  });

  @override
  Widget build(BuildContext context) {
    // 1. Parse Settings
    final title =
        (data['title'] ?? 'Lo que dicen nuestros clientes').toString();
    final backgroundColor = _parseColor(data['backgroundColor']);
    final isDark =
        backgroundColor != null && backgroundColor.computeLuminance() < 0.5;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subTextColor = isDark ? Colors.white70 : Colors.black54;

    // 2. Get Reviews (or Mocks)
    final reviews = _getReviews();

    return Container(
      width: double.infinity,
      color: backgroundColor ?? Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 64),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                Text(
                  title.toUpperCase(),
                  style: TextStyle(
                    fontFamily: headingFont,
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                    color: textColor,
                    height: 1.2,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '4.9',
                      style: TextStyle(
                        fontFamily: bodyFont,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Row(
                      children: List.generate(
                          5,
                          (index) => const Icon(Icons.star,
                              color: Color(0xFFFBBC04), size: 20)),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'en Google',
                      style: TextStyle(
                        fontFamily: bodyFont,
                        fontSize: 16,
                        color: subTextColor,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 48),

          // Scrollable List
          SizedBox(
            height: 280,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              scrollDirection: Axis.horizontal,
              itemCount: reviews.length,
              separatorBuilder: (c, i) => const SizedBox(width: 24),
              itemBuilder: (context, index) {
                final review = reviews[index];
                return _ReviewCard(
                  review: review,
                  bodyFont: bodyFont,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _getReviews() {
    // Check if we have real data (later phase)
    final rawList = data['reviews'] as List?;
    if (rawList != null && rawList.isNotEmpty) {
      return List<Map<String, dynamic>>.from(rawList);
    }

    // Return Mocks
    return [
      {
        'author_name': 'Carlos Rivera',
        'rating': 5,
        'relative_time': 'hace 2 semanas',
        'text':
            'Excelente servicio. Llevé mi bicicleta para un ajuste completo y quedó como nueva. Muy profesionales y rápidos.',
        'photo_url': 'https://randomuser.me/api/portraits/men/32.jpg',
      },
      {
        'author_name': 'Maria José Soto',
        'rating': 5,
        'relative_time': 'hace 1 mes',
        'text':
            'La mejor tienda de Viña. Tienen gran variedad de repuestos y la atención es de primera. 100% recomendados.',
        'photo_url': 'https://randomuser.me/api/portraits/women/44.jpg',
      },
      {
        'author_name': 'Felipe Andrés',
        'rating': 5,
        'relative_time': 'hace 3 semanas',
        'text':
            'Compré mi Trek aquí y me asesoraron en todo momento. El servicio post-venta también ha sido impecable.',
        'photo_url': 'https://randomuser.me/api/portraits/men/85.jpg',
      },
      {
        'author_name': 'Andrea Pvez',
        'rating': 4,
        'relative_time': 'hace 2 meses',
        'text':
            'Muy buen taller mecánico. Solucionaron un ruido que nadie más había podido arreglar.',
        'photo_url': 'https://randomuser.me/api/portraits/women/68.jpg',
      },
    ];
  }

  static Color? _parseColor(dynamic value) {
    if (value == null) return null;
    final hex = value.toString();
    if (hex.isEmpty) return null;
    final buffer = StringBuffer();
    if (hex.length == 6 || hex.length == 7) buffer.write('ff');
    buffer.write(hex.replaceFirst('#', ''));
    try {
      return Color(int.parse(buffer.toString(), radix: 16));
    } catch (_) {
      return null;
    }
  }
}

class _ReviewCard extends StatelessWidget {
  final Map<String, dynamic> review;
  final String? bodyFont;

  const _ReviewCard({
    required this.review,
    this.bodyFont,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 320,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            offset: const Offset(0, 4),
            blurRadius: 12,
          ),
        ],
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Avatar + Name + G Logo
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundImage: NetworkImage(review['photo_url']),
                backgroundColor: Colors.grey.shade200,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      review['author_name'],
                      style: TextStyle(
                        fontFamily: bodyFont,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: Colors.black87,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      review['relative_time'],
                      style: TextStyle(
                        fontFamily: bodyFont,
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
              // Google G Logo (small svg or text or icon)
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                // Using a text G with Google colors for simplicity without assets
                child: const Text(
                  'G',
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontWeight: FontWeight.w900,
                    fontSize: 20,
                    color: Color(0xFF4285F4), // Google Blue
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Stars
          Row(
            children: List.generate(
              5,
              (index) => Icon(
                Icons.star,
                color: index < (review['rating'] ?? 5)
                    ? const Color(0xFFFBBC04)
                    : Colors.grey.shade300,
                size: 16,
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Text
          Expanded(
            child: Text(
              review['text'],
              style: TextStyle(
                fontFamily: bodyFont,
                fontSize: 14,
                color: Colors.black87,
                height: 1.5,
              ),
              maxLines: 6,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
