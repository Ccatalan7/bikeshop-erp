import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';
import 'package:vinabike_public_core/modules/website/models/website_google_reviews.dart';

import 'block_composition.dart';
import 'css_values.dart';
import 'material_icons.dart';
import 'website_blocks_view.dart';

const _mdStar =
    'M12 17.27 18.18 21l-1.64-7.03L22 9.24l-7.19-.61L12 2 9.19 8.63 2 9.24l5.46 '
    '4.73L5.82 21z';
const _mdStarBorder =
    'M22 9.24l-7.19-.62L12 2 9.19 8.63 2 9.24l5.46 4.73L5.82 21 12 17.27 18.18 '
    '21l-1.63-7.03L22 9.24zM12 15.4l-3.76 2.27 1-4.28-3.32-2.88 4.38-.38L12 '
    '6.1l1.71 4.04 4.38.38-3.32 2.88 1 4.28L12 15.4z';

/// What the HTML reviews block draws: the store's reviews on the theme's
/// own surface.
bool googleReviewsIsCovered(Map<String, dynamic> data) {
  final style = data['style'];
  final background = data['backgroundColor'];
  final formatting = data['titleFormatting'];
  return (style is! Map || style.isEmpty) &&
      (background == null || background.toString().isEmpty) &&
      (formatting is! Map || formatting.isEmpty);
}

/// `GoogleReviewsCarousel`: the title, the score with its stars and the
/// count, then the review cards in a row that scrolls sideways.
class GoogleReviewsView extends StatelessComponent {
  const GoogleReviewsView(this.composed, this.context, {super.key});

  final ComposedBlock composed;
  final BlockRenderContext context;

  @override
  Component build(BuildContext _) {
    final data = WebsiteGoogleReviewsContent.withSyncedReviews(
      composed.data,
      context.shell.setting,
    );
    final content = WebsiteGoogleReviewsContent.fromData(data);
    final title = (data['title'] ?? 'Lo que dicen nuestros clientes')
        .toString();
    final rating = content.rating;
    final total = content.totalReviews;
    final now = DateTime.now();
    return section(classes: 'rv', [
      h2(classes: 'rv-t', [.text(title.toUpperCase())]),
      if (rating != null)
        div(classes: 'rv-score', [
          span(classes: 'rv-num', [.text(rating.toStringAsFixed(1))]),
          span(
            classes: 'rv-stars',
            attributes: {
              'role': 'img',
              'aria-label': '${rating.toStringAsFixed(1)} de 5 estrellas',
            },
            [
              for (var index = 0; index < 5; index++)
                RawText(
                  materialIcon(
                    index < rating.round() ? _mdStar : _mdStarBorder,
                    size: 20,
                  ),
                ),
            ],
          ),
          span(classes: 'rv-count', [
            .text(total == null ? 'en Google' : 'en Google ($total reseñas)'),
          ]),
        ]),
      if (content.reviews.isNotEmpty)
        ul(classes: 'rv-list', [
          for (final review in content.reviews) _card(review, now),
        ]),
    ]);
  }

  Component _card(WebsiteGoogleReview review, DateTime now) {
    final name = WebsiteGoogleReviewsContent.authorName(review.data);
    final photo = WebsiteGoogleReviewsContent.photoUrl(review.data);
    final time = WebsiteGoogleReviewsContent.relativeTime(review.data, now);
    return li(classes: 'rv-card', [
      div(classes: 'rv-head', [
        if (photo != null && photo.isNotEmpty)
          img(
            classes: 'rv-av',
            src: photo,
            alt: '',
            loading: MediaLoading.lazy,
            attributes: {'referrerpolicy': 'no-referrer'},
          )
        else
          span(classes: 'rv-av', [
            .text(name.isNotEmpty ? name[0].toUpperCase() : 'U'),
          ]),
        div(classes: 'rv-who', [
          p(classes: 'rv-name', [.text(name)]),
          if (time.isNotEmpty) p(classes: 'rv-time', [.text(time)]),
        ]),
        span(
          classes: 'rv-g',
          attributes: {'aria-hidden': 'true'},
          [.text('G')],
        ),
      ]),
      span(
        classes: 'rv-rating',
        attributes: {
          'role': 'img',
          'aria-label': '${review.rating} de 5 estrellas',
        },
        [
          for (var index = 0; index < 5; index++)
            RawText(
              materialIcon(
                _mdStar,
                size: 16,
                classes: index < review.rating ? 'on' : null,
              ),
            ),
        ],
      ),
      p(classes: 'rv-text', [
        .text(WebsiteGoogleReviewsContent.text(review.data)),
      ]),
    ]);
  }
}

/// The block's stylesheet: its padding (64 and 24), the theme's surface and
/// ink, Google's own gold and blue.
final googleReviewsCss = '''
.rv{display:flex;flex-direction:column;align-items:center;${surfacePadding(64, 24, 64, 24)};background:var(--w-bg)}
.rv-t{margin:0;font:400 28px/34px var(--head);letter-spacing:1.5px;color:var(--w-on);-webkit-text-stroke:.032em currentColor;text-align:center}
.rv-score{display:flex;flex-wrap:wrap;justify-content:center;align-items:center;gap:8px;margin-top:12px}
.rv-num{font:700 18px/27px var(--body);letter-spacing:.25px;color:var(--w-prim)}
.rv-stars{display:flex;color:#fbbc04}
.rv-stars svg{width:20px;height:20px}
.rv-count{font:400 16px/24px var(--body);letter-spacing:.25px;color:var(--w-onv)}
.rv-list{display:flex;gap:24px;align-self:stretch;height:280px;margin:48px 0 0;padding:0;list-style:none;overflow-x:auto;scrollbar-width:thin}
.rv-card{flex:none;display:flex;flex-direction:column;width:320px;padding:24px;border:1px solid var(--w-ovar);border-radius:16px;background:var(--w-cont);box-shadow:0 4px 12px rgb(0 0 0 / .05)}
.rv-head{display:flex;align-items:center}
.rv-av{flex:none;display:grid;place-items:center;width:40px;height:40px;border-radius:50%;object-fit:cover;background:var(--w-accent);color:var(--w-onacc);font:700 16px/1 var(--body)}
.rv-who{flex:1;min-width:0;margin-left:12px}
.rv-name{margin:0;font:700 14px/21px var(--body);letter-spacing:.25px;color:var(--w-on);white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.rv-time{margin:0;font:400 12px/18px var(--body);letter-spacing:.25px;color:var(--w-onv)}
/* The «G» keeps the store's 1.5 line, taller than its 24 px box. */
.rv-g{display:grid;place-items:center;width:24px;height:24px;font:900 20px/30px var(--body);color:#4285f4}
.rv-rating{display:flex;margin-top:16px;color:var(--w-ovar)}
.rv-rating svg{width:16px;height:16px}
.rv-rating svg.on{color:#fbbc04}
.rv-text{flex:1;min-height:0;margin:12px 0 0;font:400 14px/21px var(--body);letter-spacing:.25px;color:var(--w-on);display:-webkit-box;-webkit-line-clamp:6;-webkit-box-orient:vertical;overflow:hidden}
''';
