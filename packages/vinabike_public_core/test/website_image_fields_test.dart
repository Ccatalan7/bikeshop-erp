import 'package:test/test.dart';
import 'package:vinabike_public_core/modules/website/models/website_image_fields.dart';

void main() {
  test('a photo is named by its spec and read back from it', () {
    for (final fields in WebsiteImageFields.values) {
      final parsed = WebsiteImageFields.parse(fields.spec(4));
      expect(parsed?.fields, fields);
      expect(parsed?.index, fields.collection.isEmpty ? 0 : 4);
    }
    expect(WebsiteImageFields.about.spec(), 'about');
    expect(WebsiteImageFields.gallery.spec(2), 'gallery#2');
  });

  test('a spec the editor does not know names no photo', () {
    for (final spec in ['', 'hero', 'about#1', 'gallery', 'team#x', 'Team#1']) {
      expect(WebsiteImageFields.parse(spec), isNull, reason: spec);
    }
  });
}
