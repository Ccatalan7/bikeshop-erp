import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/public_store/widgets/public_store_layout.dart';

void main() {
  test('compact storefront header fits the supported mobile widths', () {
    for (final width in <double>[320, 375, 599, 1079]) {
      final geometry = PublicStoreHeaderGeometry.resolve(width);

      expect(geometry.isDesktop, isFalse, reason: 'width=$width');
      expect(
        geometry.compactRequiredWidth,
        lessThanOrEqualTo(width),
        reason: 'width=$width',
      );
      expect(geometry.iconBox, greaterThanOrEqualTo(48),
          reason: 'width=$width');
      expect(geometry.logoHitBox, greaterThanOrEqualTo(48),
          reason: 'width=$width');
    }
  });

  test('320 px uses the narrow wordmark composition', () {
    final narrow = PublicStoreHeaderGeometry.resolve(320);
    final regular = PublicStoreHeaderGeometry.resolve(375);

    expect(narrow.logoMaxWidth!, lessThan(regular.logoMaxWidth!));
    expect(narrow.logoGap, lessThan(regular.logoGap));
    expect(narrow.horizontalPadding, lessThan(regular.horizontalPadding));
    expect(narrow.logoHeight, lessThan(regular.logoHeight));
  });

  test('desktop keeps the full navigation composition', () {
    final compact = PublicStoreHeaderGeometry.resolve(1079);
    final desktop = PublicStoreHeaderGeometry.resolve(1080);

    expect(compact.isDesktop, isFalse);
    expect(desktop.isDesktop, isTrue);
    expect(desktop.logoMaxWidth, isNull);
    expect(desktop.iconBox, 40);
  });
}
