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
    final displayedRating = _readDouble(data['rating']) ??
        _readDouble(data['google_rating']) ??
        _calculateAverageRating(reviews);
    final totalReviews = _readInt(data['totalReviews']) ??
        _readInt(data['user_ratings_total']) ??
        _readInt(data['reviewsTotal']);

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
                      displayedRating.toStringAsFixed(1),
                      style: TextStyle(
                        fontFamily: bodyFont,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Row(
                      children: List.generate(5, (index) {
                        return Icon(
                          index < displayedRating.round()
                              ? Icons.star
                              : Icons.star_border,
                          color: const Color(0xFFFBBC04),
                          size: 20,
                        );
                      }),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      totalReviews == null
                          ? 'en Google'
                          : 'en Google ($totalReviews reseñas)',
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

  /// Calculate average rating from reviews list
  double _calculateAverageRating(List<Map<String, dynamic>> reviews) {
    if (reviews.isEmpty) return 0.0;

    double total = 0;
    for (final review in reviews) {
      final ratingValue = review['rating'] ?? review['starRating'];
      if (ratingValue is int) {
        total += ratingValue;
      } else if (ratingValue is String) {
        switch (ratingValue.toUpperCase()) {
          case 'FIVE':
            total += 5;
            break;
          case 'FOUR':
            total += 4;
            break;
          case 'THREE':
            total += 3;
            break;
          case 'TWO':
            total += 2;
            break;
          case 'ONE':
            total += 1;
            break;
          default:
            total += 5; // Assume 5 if unknown
        }
      } else {
        total += 5; // Default to 5 if no rating
      }
    }
    return total / reviews.length;
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

  static double? _readDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value.trim());
    return null;
  }

  static int? _readInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.round();
    if (value is String) return int.tryParse(value.trim());
    return null;
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
    // Handle both mock format and real Google API format
    // Mock: author_name, photo_url, relative_time, rating, text
    // Google API: reviewer.displayName, reviewer.profilePhotoUrl, createTime, starRating (FIVE/FOUR/etc), comment

    // Extract author name
    final String authorName = review['author_name'] ??
        (review['reviewer'] as Map<String, dynamic>?)?['displayName'] ??
        'Usuario';

    // Extract photo URL (with fallback for missing photos)
    final String? photoUrl = review['photo_url'] ??
        (review['reviewer'] as Map<String, dynamic>?)?['profilePhotoUrl'];

    // Extract relative time or format create time
    String relativeTime = review['relative_time'] ?? '';
    if (relativeTime.isEmpty) {
      final createTime = review['createTime'] ?? review['updateTime'];
      if (createTime != null) {
        try {
          final date = DateTime.parse(createTime);
          final diff = DateTime.now().difference(date);
          if (diff.inDays > 30) {
            relativeTime = 'hace ${diff.inDays ~/ 30} meses';
          } else if (diff.inDays > 0) {
            relativeTime = 'hace ${diff.inDays} días';
          } else {
            relativeTime = 'hace ${diff.inHours} horas';
          }
        } catch (_) {
          relativeTime = '';
        }
      }
    }

    // Extract rating (mock: int, Google API: string like "FIVE", "FOUR", etc)
    int rating = 5;
    final ratingValue = review['rating'] ?? review['starRating'];
    if (ratingValue is int) {
      rating = ratingValue;
    } else if (ratingValue is String) {
      switch (ratingValue.toUpperCase()) {
        case 'FIVE':
          rating = 5;
          break;
        case 'FOUR':
          rating = 4;
          break;
        case 'THREE':
          rating = 3;
          break;
        case 'TWO':
          rating = 2;
          break;
        case 'ONE':
          rating = 1;
          break;
      }
    }

    // Extract review text
    final String reviewText =
        (review['text'] ?? review['comment'] ?? '').toString().trim().isNotEmpty
            ? (review['text'] ?? review['comment']).toString().trim()
            : 'Calificación publicada en Google.';

    return Container(
      width: 320,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
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
                backgroundImage:
                    photoUrl != null ? NetworkImage(photoUrl) : null,
                backgroundColor: Colors.grey.shade200,
                child: photoUrl == null
                    ? Text(
                        authorName.isNotEmpty
                            ? authorName[0].toUpperCase()
                            : 'U',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, color: Colors.white),
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      authorName,
                      style: TextStyle(
                        fontFamily: bodyFont,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: Colors.black87,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (relativeTime.isNotEmpty)
                      Text(
                        relativeTime,
                        style: TextStyle(
                          fontFamily: bodyFont,
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                  ],
                ),
              ),
              // Google G Logo
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                child: Text(
                  'G',
                  style: TextStyle(
                    fontFamily: bodyFont,
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
                color: index < rating
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
              reviewText,
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
