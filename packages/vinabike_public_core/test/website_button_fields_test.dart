import 'package:test/test.dart';
import 'package:vinabike_public_core/modules/website/models/website_action.dart';

void main() {
  test('a button is named by its spec and read back from it', () {
    for (final fields in WebsiteButtonFields.values) {
      final spec = fields.spec(3);
      final parsed = WebsiteButtonFields.parse(spec);
      expect(parsed?.fields, fields, reason: spec);
      expect(parsed?.index, fields.collection.isEmpty ? 0 : 3, reason: spec);
    }
    expect(WebsiteButtonFields.cta.spec(), 'cta');
    expect(WebsiteButtonFields.plan.spec(2), 'plan#2');
  });

  test('a spec the editor does not know names no button', () {
    for (final spec in [
      '',
      'title',
      'cta#1',
      'plan',
      'plan#',
      'plan#-1',
      'plan#99999',
      'plan#1#2',
      'slide#x',
      'Cta',
    ]) {
      expect(WebsiteButtonFields.parse(spec), isNull, reason: spec);
    }
  });

  test('only the main buttons mirror the block primary action', () {
    expect(WebsiteButtonFields.cta.actionsKey, 'actions');
    expect(WebsiteButtonFields.ctaSecondary.actionsKey, isNull);
    expect(WebsiteButtonFields.ctaSecondary.variant, isEmpty);
    expect(WebsiteButtonFields.button.variant, ['style']);
    expect(WebsiteButtonFields.plan.collection.first, 'plans');
  });

  test('a button is edited as stored: empty stays empty, the look by the '
      'block default, a block written before the fields by its actions', () {
    expect(
      WebsiteButtonFields.hero.storedIn({'ctaText': 'Agendar', 'ctaLink': ''}),
      isA<WebsiteActionValue>()
          .having((a) => a.label, 'label', 'Agendar')
          .having((a) => a.href, 'href', '')
          .having((a) => a.variant, 'variant', WebsiteActionVariant.outline),
    );
    final cta = WebsiteButtonFields.cta.storedIn({
      'actions': [
        {'type': 'navigate', 'label': 'Escríbenos', 'to': '/contacto'},
      ],
    });
    expect(cta.label, 'Escríbenos');
    expect(cta.href, '/contacto');
    expect(cta.variant, WebsiteActionVariant.filled);
    final second = WebsiteButtonFields.ctaSecondary.storedIn({
      'secondaryText': 'Cómo llegar',
      'actions': [
        {'type': 'navigate', 'label': 'Escríbenos', 'to': '/contacto'},
      ],
    });
    expect(second.label, 'Cómo llegar');
    expect(second.href, '');
    expect(second.variant, WebsiteActionVariant.outline);
    expect(
      WebsiteButtonFields.button.storedIn({
        'label': 'Ver',
        'link': '/productos',
        'style': 'text',
      }).variant,
      WebsiteActionVariant.text,
    );
  });
}
