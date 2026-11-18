import 'package:test/test.dart';
import 'package:vinabike_public_core/modules/website/models/website_route_content.dart';

/// The «Ruta» block computes every figure it shows from the route it is
/// given (2026-11-17, guide «En bici a Lo Vásquez»).
void main() {
  Map<String, dynamic> block({String profile = '', String points = ''}) => {
    'map_image': 'https://cdn.example/mapa.png',
    'map_west': -71.995,
    'map_north': -32.975,
    'map_east': -71.345,
    'map_south': -33.300,
    'destination': 'Santuario Lo Vásquez',
    'destination_note': 'km 78,8 de la Ruta 68',
    'places': [
      {'name': 'Quilpué', 'position': '-33.0601, -71.4380'},
      {
        'name': 'Lago Peñuelas',
        'position': '-33.1477, -71.5112',
        'kind': 'water',
      },
      {'name': 'Sin lugar', 'position': ''},
    ],
    'routes': [
      {
        'label': 'Desde Viña',
        'start': 'Plaza Sucre, Viña del Mar',
        'start_label': 'Viña del Mar',
        'road': 'Agua Santa y Ruta 68',
        'climb': 'Agua Santa',
        'climb_from': '1,7',
        'climb_to': 9.1,
        'track': '-33.0250, -71.5522\n-33.1000, -71.5200\n-33.2580, -71.4382',
        'profile': profile.isEmpty
            ? '0, 17\n5, 300\n6, 297\n10, 350\n12, 340\n28.14, 416\n36.18, 291'
            : profile,
        'points': points.isEmpty
            ? '1,7 a 9,1 | Agua Santa | La subida larga.\n'
                  '12,8 | Ruta 68 | Entras por Las Palmas.\n'
                  'no es un punto\n'
                  '36,2 | Santuario | Km 78,8 de la Ruta 68.'
            : points,
      },
      {'label': 'Sin datos'},
    ],
  };

  test('the figures come from the profile, never typed', () {
    final content = WebsiteRouteContent.fromData(block());
    final way = content.ways.first;

    expect(way.distanceKm, 36.18);
    expect(websiteRouteKm(way.distanceKm), '36,2');
    // 17→300 (+283); a dip of 3 m to 297 is noise, so 350 still counts
    // from 300 (+50); 350→340 is a real drop, and 340→416 (+76).
    expect(way.gainM, 283 + 50 + 76);
    expect(websiteRouteGain(way.gainM), '410');
    expect(way.highest!.ele, 416);
    expect(websiteRouteKm(way.highest!.km), '28,1');
    expect(way.eleAt(2.5), closeTo(17 + (300 - 17) * 0.5, 0.001));
    expect(way.climbFrom, 1.7);
    expect(way.climbTo, 9.1);
  });

  test('points read a kilometre or a stretch, and skip what is not one', () {
    final way = WebsiteRouteContent.fromData(block()).ways.first;

    expect(way.points, hasLength(3));
    expect(way.points[0].isStretch, isTrue);
    expect(websiteRoutePointLabel(way, way.points[0]), 'km 1,7 a 9,1');
    expect(
      websiteRoutePointLabel(way, way.points[1]),
      'km 12,8 · ${way.eleAt(12.8).round()} m',
    );
    expect(way.points[2].note, 'Km 78,8 de la Ruta 68.');
  });

  test('a way without a track or a profile is kept but not drawn', () {
    final content = WebsiteRouteContent.fromData(block());

    expect(content.ways, hasLength(2));
    expect(content.drawable.map((way) => way.label), ['Desde Viña']);
    expect(content.places.map((place) => place.name), [
      'Quilpué',
      'Lago Peñuelas',
    ]);
    expect(content.places[1].water, isTrue);
  });

  test('the map projects inside its image and frames the whole way', () {
    final content = WebsiteRouteContent.fromData(block());
    final frame = content.map!;

    // The image is as tall as its degrees of latitude are long against its
    // degrees of longitude at that latitude: 1440 × 860 for this one.
    expect(
      WebsiteRouteMapFrame.width / frame.height,
      closeTo(1440 / 860, 0.01),
    );
    final start = frame.project(content.ways.first.track.first);
    expect(start.x, closeTo((-71.5522 + 71.995) / 0.65 * 1000, 0.01));
    final crop = content.crop()!;
    for (final at in content.ways.first.track) {
      final p = frame.project(at);
      expect(p.x, inInclusiveRange(crop.x, crop.x + crop.w));
      expect(p.y, inInclusiveRange(crop.y, crop.y + crop.h));
    }
    expect(websiteRouteTrackPath(frame, content.ways.first), startsWith('M'));
  });

  test('the map marks the destination and the start first, then what fits', () {
    final marks = WebsiteRouteContent.fromData(block()).mapMarks(0);

    expect(marks.first.kind, WebsiteRouteMarkKind.destination);
    expect(marks.first.subtitle, 'km 36,2 · km 78,8 de la Ruta 68');
    expect(marks[1].kind, WebsiteRouteMarkKind.start);
    expect(marks[1].title, 'Viña del Mar');
    // Two marks never sit on the same spot: the second one is left out.
    for (final (i, a) in marks.indexed) {
      for (final b in marks.skip(i + 1)) {
        expect(
          (a.x - b.x).abs() > 1 || (a.y - b.y).abs() > 1,
          isTrue,
          reason: '${a.title} y ${b.title} se tapan',
        );
      }
    }
  });

  test('the map frames every label, with room under them for the credit', () {
    final content = WebsiteRouteContent.fromData(block());
    final crop = content.crop()!;
    final destination = content.mapMarks(0).first;

    // The destination's name and kilometre go under its dot: before, the
    // frame ended at the route and cut them off.
    expect(destination.kind, WebsiteRouteMarkKind.destination);
    expect(destination.y + 68 + 36, lessThanOrEqualTo(crop.y + crop.h + 1e-6));
  });

  test('a label on the profile sits over the line along its whole width', () {
    final way = WebsiteRouteContent.fromData(block()).ways.first;
    final chart = WebsiteRouteChart(way, width: 800, height: 300);

    for (final mark in chart.marks()) {
      final width = mark.label.length * 7.2;
      final from = mark.last ? mark.labelX - width : mark.labelX;
      for (final point in chart.line) {
        if (point.x >= from && point.x <= from + width) {
          expect(mark.labelY, lessThan(point.y), reason: mark.label);
        }
      }
    }
  });

  test('a label that would cover another goes under the line', () {
    final way = WebsiteRouteContent.fromData(block()).ways.first;
    // The phone's drawing: only the highest point, by its height, and the
    // destination, whose name spans the highest point on a narrow profile.
    final chart = WebsiteRouteChart(
      way,
      width: 600,
      height: 400,
      left: 70,
      right: 16,
      top: 48,
      bottom: 70,
      gridStep: 200,
      tickStep: 10,
    );
    final marks = chart.marks(
      minGap: 160,
      charWidth: 12.2,
      fontSize: 22,
      gap: 16,
      namePoints: false,
      nameHighest: true,
    );

    expect(marks.map((mark) => mark.kind), [
      WebsiteRouteChartMarkKind.highest,
      WebsiteRouteChartMarkKind.destination,
    ]);
    expect(marks.first.label, '416 m');
    expect(marks.first.anchor, 'middle');
    expect(marks.last.label, 'Santuario');
    expect(marks.last.labelY, greaterThan(marks.last.y));
    expect(marks.last.labelY, lessThan(chart.floorY));
  });

  test('a name on the map that would cover a mark is left out', () {
    final data = block();
    data['places'] = [
      // Right on the start's label.
      {'name': 'Viña', 'position': '-33.0250, -71.5480'},
      {'name': 'Quilpué', 'position': '-33.0601, -71.4380'},
    ];
    final content = WebsiteRouteContent.fromData(data);

    expect(content.mapPlaces(0).map((place) => place.name), ['Quilpué']);
  });

  test('kilometres round on tenths and drop a whole ",0"', () {
    expect(websiteRouteKm(16.45), '16,5');
    expect(websiteRouteKm(0), '0');
    expect(websiteRouteKm(36.18), '36,2');
    expect(websiteRouteKm(10.04), '10');
  });

  test('the profile chart scales to its drawing and names its points', () {
    final way = WebsiteRouteContent.fromData(block()).ways.first;
    final chart = WebsiteRouteChart(way, width: 800, height: 300);

    expect(chart.x(0), chart.left);
    expect(chart.x(way.distanceKm), 800 - chart.right);
    expect(chart.y(0), chart.floorY);
    expect(chart.kmAt(chart.x(12.8)), closeTo(12.8, 0.001));
    expect(chart.grid.map((line) => line.label), [
      '100 m',
      '200 m',
      '300 m',
      '400 m',
      '500 m',
    ]);
    expect(chart.ticks.first.label, '0 km');
    expect(chart.climb!.label, 'Agua Santa');
    final marks = chart.marks();
    expect(marks.last.label, 'Santuario');
    expect(marks.last.last, isTrue);
    expect(marks.map((mark) => mark.label), contains('Ruta 68'));
    expect(chart.areaPath, endsWith('Z'));
  });

  test('a decimal comma in a kilometre or a number field is read', () {
    final way = WebsiteRouteContent.fromData(
      block(points: '28,14 | Punto más alto | Desde aquí, bajada.'),
    ).ways.first;

    expect(way.points.single.km, 28.14);
  });
}
