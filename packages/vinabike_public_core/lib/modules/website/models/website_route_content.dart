import 'dart:math' as math;

/// The «Ruta» block (2026-11-17, for the guide «En bici a Lo Vásquez»): one
/// or more ways to the same place drawn on a base map, the reader picks
/// where they leave from, and each way shows its facts, its height profile
/// and its points along the road.
///
/// What a person writes in the inspector is the route itself: the track
/// (latitude and longitude), the profile (kilometre and height) and the
/// points (kilometre, name, note). Every figure the page shows —the
/// distance, the climb, the highest point, the height at each point— is
/// computed here from those, never typed: a figure cannot drift from the
/// route it describes. The Flutter canvas and the HTML storefront both draw
/// from this file, so they show the same numbers and the same marks.

/// A place on the map, latitude and longitude in degrees.
class WebsiteRouteCoordinate {
  const WebsiteRouteCoordinate(this.lat, this.lon);

  final double lat;
  final double lon;
}

/// A sample of a height profile: the distance from the start and the height
/// above the sea, in metres.
class WebsiteRouteSample {
  const WebsiteRouteSample(this.km, this.ele);

  final double km;
  final double ele;
}

/// A point along a route: a kilometre, or a stretch from one kilometre to
/// another (a climb), with its name and a short note.
class WebsiteRoutePoint {
  const WebsiteRoutePoint({
    required this.km,
    this.toKm,
    required this.title,
    this.note = '',
  });

  final double km;
  final double? toKm;
  final String title;
  final String note;

  bool get isStretch => toKm != null;
}

/// A name written on the map: a town, or water (in italics).
class WebsiteRoutePlace {
  const WebsiteRoutePlace({
    required this.name,
    required this.at,
    this.water = false,
  });

  final String name;
  final WebsiteRouteCoordinate at;
  final bool water;
}

/// One way to the destination.
class WebsiteRouteWay {
  WebsiteRouteWay({
    required this.index,
    required this.label,
    required this.start,
    required this.startLabel,
    required this.road,
    required this.climb,
    required this.climbFrom,
    required this.climbTo,
    required this.summary,
    required this.track,
    required this.profile,
    required this.points,
  });

  /// Where it is stored in the block's list of ways.
  final int index;

  /// What the reader picks: «Desde Viña».
  final String label;

  /// The starting point in full: «Plaza Sucre, Viña del Mar».
  final String start;

  /// The start's name on the map: «Viña del Mar».
  final String startLabel;

  /// The roads it takes: «Agua Santa y Ruta 68».
  final String road;

  /// The long climb, shaded on the profile.
  final String climb;
  final double? climbFrom;
  final double? climbTo;

  /// What the profile says in words.
  final String summary;

  final List<WebsiteRouteCoordinate> track;
  final List<WebsiteRouteSample> profile;
  final List<WebsiteRoutePoint> points;

  bool get drawable => track.length >= 2 && profile.length >= 2;

  /// The length of the way: the profile's last kilometre, or the track's own
  /// length when it has no profile.
  double get distanceKm {
    if (profile.isNotEmpty) return profile.last.km;
    var total = 0.0;
    for (var i = 1; i < track.length; i++) {
      total += websiteRouteDistanceKm(track[i - 1], track[i]);
    }
    return total;
  }

  /// The climb added up along the profile, counting a rise only once it
  /// passes 5 m, so the noise of the satellite heights does not add up.
  double get gainM {
    if (profile.length < 2) return 0;
    var gain = 0.0;
    var reference = profile.first.ele;
    for (final sample in profile.skip(1)) {
      if (sample.ele >= reference + 5) {
        gain += sample.ele - reference;
        reference = sample.ele;
      } else if (sample.ele <= reference - 5) {
        reference = sample.ele;
      }
    }
    return gain;
  }

  /// The highest sample (the first of equals).
  WebsiteRouteSample? get highest {
    WebsiteRouteSample? best;
    for (final sample in profile) {
      if (best == null || sample.ele > best.ele) best = sample;
    }
    return best;
  }

  double get lowestEle =>
      profile.isEmpty ? 0 : profile.map((s) => s.ele).reduce(math.min);

  /// The height at [km], between the two samples around it.
  double eleAt(double km) {
    if (profile.isEmpty) return 0;
    if (km <= profile.first.km) return profile.first.ele;
    for (var i = 1; i < profile.length; i++) {
      final b = profile[i];
      if (b.km >= km) {
        final a = profile[i - 1];
        final span = b.km - a.km;
        final t = span <= 0 ? 0.0 : (km - a.km) / span;
        return a.ele + (b.ele - a.ele) * t;
      }
    }
    return profile.last.ele;
  }

  /// Where along the track the kilometre [km] falls, measured on the track
  /// and scaled to the profile's length (the two are measured apart).
  WebsiteRouteCoordinate? coordinateAt(double km) {
    if (track.length < 2) return null;
    final lengths = <double>[0];
    for (var i = 1; i < track.length; i++) {
      lengths.add(
        lengths.last + websiteRouteDistanceKm(track[i - 1], track[i]),
      );
    }
    final total = lengths.last;
    if (total <= 0) return track.first;
    final target = (km / (distanceKm <= 0 ? total : distanceKm)) * total;
    for (var i = 1; i < track.length; i++) {
      if (lengths[i] >= target) {
        final span = lengths[i] - lengths[i - 1];
        final t = span <= 0 ? 0.0 : (target - lengths[i - 1]) / span;
        final a = track[i - 1], b = track[i];
        return WebsiteRouteCoordinate(
          a.lat + (b.lat - a.lat) * t,
          a.lon + (b.lon - a.lon) * t,
        );
      }
    }
    return track.last;
  }
}

/// The base map: an image that covers exactly [west]..[east] and
/// [north]..[south] in degrees, drawn in map units 1000 wide.
class WebsiteRouteMapFrame {
  const WebsiteRouteMapFrame({
    required this.image,
    required this.west,
    required this.north,
    required this.east,
    required this.south,
  });

  final String image;
  final double west;
  final double north;
  final double east;
  final double south;

  static const double width = 1000;

  /// The image's height in map units: a degree of longitude is shorter than
  /// one of latitude by the cosine of the latitude.
  double get height {
    final mid = (north + south) / 2 * math.pi / 180;
    final lonSpan = (east - west) * math.cos(mid);
    if (lonSpan <= 0) return width;
    return width * (north - south) / lonSpan;
  }

  bool get valid => east > west && north > south;

  ({double x, double y}) project(WebsiteRouteCoordinate at) => (
    x: (at.lon - west) / (east - west) * width,
    y: (north - at.lat) / (north - south) * height,
  );
}

/// What a mark on the map is.
enum WebsiteRouteMarkKind { start, otherStart, point, highest, destination }

/// A mark on the map, already placed: a mark that would cover another is
/// left out, the same way in both renderers.
class WebsiteRouteMapMark {
  const WebsiteRouteMapMark({
    required this.kind,
    required this.x,
    required this.y,
    required this.title,
    this.subtitle = '',
    this.end = false,
  });

  final WebsiteRouteMarkKind kind;
  final double x;
  final double y;
  final String title;
  final String subtitle;

  /// The label goes to the left of the mark (text-anchor end).
  final bool end;
}

/// Everything the block shows, read once from its data.
class WebsiteRouteContent {
  WebsiteRouteContent({
    required this.ways,
    required this.map,
    required this.destination,
    required this.destinationNote,
    required this.places,
    required this.pickLabel,
    required this.profileTitle,
    required this.credit,
    required this.source,
    this.mapAlt = '',
  });

  final List<WebsiteRouteWay> ways;
  final WebsiteRouteMapFrame? map;
  final String destination;
  final String destinationNote;
  final List<WebsiteRoutePlace> places;

  /// The question over the picker: «Desde dónde sales».
  final String pickLabel;

  /// The heading over the profile: «El perfil».
  final String profileTitle;

  /// The map's credit: «© colaboradores de OpenStreetMap».
  final String credit;

  /// Where the heights come from, under the profile.
  final String source;

  /// What the base picture shows, for a screen reader (`map_image_alt`).
  final String mapAlt;

  /// What the map of the way at [active] says to a screen reader: the way
  /// and where it goes, then what the base picture shows, when written.
  String mapLabel(int active) {
    final all = drawable;
    if (all.isEmpty) return mapAlt;
    final way = all[active.clamp(0, all.length - 1)];
    return [
      'Mapa de la ruta ${way.label.toLowerCase()}'
          '${destination.isEmpty ? '' : ' a $destination'}',
      if (mapAlt.isNotEmpty) mapAlt,
    ].join('. ');
  }

  /// The ways that can be drawn, in their stored order.
  List<WebsiteRouteWay> get drawable => [
    for (final way in ways)
      if (way.drawable) way,
  ];

  static WebsiteRouteContent fromData(Map<String, dynamic> data) {
    final rawWays = data['routes'];
    final ways = <WebsiteRouteWay>[
      if (rawWays is List)
        for (final (index, raw) in rawWays.indexed)
          if (raw is Map) _way(index, Map<String, dynamic>.from(raw)),
    ];
    final image = _text(data['map_image']);
    final west = _number(data['map_west']);
    final north = _number(data['map_north']);
    final east = _number(data['map_east']);
    final south = _number(data['map_south']);
    final frame =
        image.isEmpty ||
            west == null ||
            north == null ||
            east == null ||
            south == null
        ? null
        : WebsiteRouteMapFrame(
            image: image,
            west: west,
            north: north,
            east: east,
            south: south,
          );
    final rawPlaces = data['places'];
    return WebsiteRouteContent(
      ways: ways,
      map: frame != null && frame.valid ? frame : null,
      destination: _text(data['destination']),
      destinationNote: _text(data['destination_note']),
      places: [
        if (rawPlaces is List)
          for (final raw in rawPlaces)
            if (raw is Map) ?_place(Map<String, dynamic>.from(raw)),
      ],
      pickLabel: _text(data['pick_label']),
      profileTitle: _text(data['profile_title']),
      credit: _text(data['map_credit']),
      source: _text(data['source']),
      mapAlt: _text(data['map_image_alt']),
    );
  }

  static WebsiteRouteWay _way(int index, Map<String, dynamic> raw) =>
      WebsiteRouteWay(
        index: index,
        label: _text(raw['label']),
        start: _text(raw['start']),
        startLabel: _text(raw['start_label']),
        road: _text(raw['road']),
        climb: _text(raw['climb']),
        climbFrom: _number(raw['climb_from']),
        climbTo: _number(raw['climb_to']),
        summary: _text(raw['summary']),
        track: websiteRouteParseTrack(_text(raw['track'])),
        profile: websiteRouteParseProfile(_text(raw['profile'])),
        points: websiteRouteParsePoints(_text(raw['points'])),
      );

  static WebsiteRoutePlace? _place(Map<String, dynamic> raw) {
    final name = _text(raw['name']);
    final at = websiteRouteParseTrack(_text(raw['position']));
    if (name.isEmpty || at.isEmpty) return null;
    return WebsiteRoutePlace(
      name: name,
      at: at.first,
      water: _text(raw['kind']) == 'water',
    );
  }

  /// The part of the map the block shows: every drawable way, the
  /// destination and the label of every mark, with room around them and,
  /// under the lowest label, room for the map's credit. A frame that does
  /// not fit the block shows more of the base map beside it, never less of
  /// the route.
  ({double x, double y, double w, double h})? crop() {
    final base = _trackCrop();
    if (base == null) return null;
    var l = base.x, t = base.y;
    var r = base.x + base.w, b = base.y + base.h;
    for (var i = 0; i < drawable.length; i++) {
      for (final mark in _marks(i, base)) {
        final box = _markBox(mark);
        l = math.min(l, box.l - 16);
        t = math.min(t, box.t - 16);
        r = math.max(r, box.r + 16);
        b = math.max(b, box.b + 36);
      }
    }
    return (x: l, y: t, w: r - l, h: b - t);
  }

  /// The ways alone with room around them: where a mark's label goes, to
  /// its left or its right, is decided inside this frame.
  ({double x, double y, double w, double h})? _trackCrop() {
    final frame = map;
    if (frame == null) return null;
    var minX = double.infinity, minY = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity;
    for (final way in drawable) {
      for (final at in way.track) {
        final p = frame.project(at);
        minX = math.min(minX, p.x);
        minY = math.min(minY, p.y);
        maxX = math.max(maxX, p.x);
        maxY = math.max(maxY, p.y);
      }
    }
    if (!minX.isFinite) return null;
    final w = math.max(maxX - minX, 40.0);
    final h = math.max(maxY - minY, 40.0);
    final padX = w * 0.16 + 24;
    final padY = h * 0.08 + 24;
    return (x: minX - padX, y: minY - padY, w: w + 2 * padX, h: h + 2 * padY);
  }

  /// The marks of the way at [active] on the map, in the order they are
  /// drawn: the other ways' starts, the destination, the start, the highest
  /// point and the points of the way. A mark whose label would cover one
  /// already placed is left out.
  List<WebsiteRouteMapMark> mapMarks(int active) {
    final box = _trackCrop();
    return box == null ? const [] : _marks(active, box);
  }

  List<WebsiteRouteMapMark> _marks(
    int active,
    ({double x, double y, double w, double h}) box,
  ) {
    final frame = map;
    final ways = drawable;
    if (frame == null || ways.isEmpty) return const [];
    final way = ways[active.clamp(0, ways.length - 1)];
    final placed = <WebsiteRouteMapMark>[];
    bool right(double x) => x > box.x + box.w * 0.62;
    void add(WebsiteRouteMapMark mark, {bool force = false}) {
      final area = _markBox(mark);
      if (force || placed.every((other) => !_hit(_markBox(other), area))) {
        placed.add(mark);
      }
    }

    final end = way.track.last;
    final endAt = frame.project(end);
    add(
      WebsiteRouteMapMark(
        kind: WebsiteRouteMarkKind.destination,
        x: endAt.x,
        y: endAt.y,
        title: destination,
        subtitle: [
          'km ${websiteRouteKm(way.distanceKm)}',
          if (destinationNote.isNotEmpty) destinationNote,
        ].join(' · '),
        end: true,
      ),
      force: true,
    );
    final startAt = frame.project(way.track.first);
    add(
      WebsiteRouteMapMark(
        kind: WebsiteRouteMarkKind.start,
        x: startAt.x,
        y: startAt.y,
        title: way.startLabel.isEmpty ? way.label : way.startLabel,
        subtitle: 'km 0 · salida',
        end: right(startAt.x),
      ),
      force: true,
    );
    for (final other in ways) {
      if (identical(other, way)) continue;
      final at = frame.project(other.track.first);
      add(
        WebsiteRouteMapMark(
          kind: WebsiteRouteMarkKind.otherStart,
          x: at.x,
          y: at.y,
          title: other.startLabel.isEmpty ? other.label : other.startLabel,
          end: right(at.x),
        ),
      );
    }
    if (way.highest case final top?) {
      if (way.coordinateAt(top.km) case final at?) {
        final p = frame.project(at);
        add(
          WebsiteRouteMapMark(
            kind: WebsiteRouteMarkKind.highest,
            x: p.x,
            y: p.y,
            title: '${top.ele.round()} m',
            subtitle: 'punto más alto · km ${websiteRouteKm(top.km)}',
            end: right(p.x),
          ),
        );
      }
    }
    for (final point in way.points) {
      if (point.isStretch) continue;
      if (point.km <= 0.5 || point.km >= way.distanceKm - 0.5) continue;
      if (way.coordinateAt(point.km) case final at?) {
        final p = frame.project(at);
        add(
          WebsiteRouteMapMark(
            kind: WebsiteRouteMarkKind.point,
            x: p.x,
            y: p.y,
            title: point.title,
            subtitle: 'km ${websiteRouteKm(point.km)}',
            end: right(p.x),
          ),
        );
      }
    }
    return placed;
  }

  /// The names written on the map with the way at [active]: a name whose
  /// label would cover a mark's is left out.
  List<WebsiteRoutePlace> mapPlaces(int active) {
    final frame = map;
    if (frame == null) return const [];
    final marks = [for (final mark in mapMarks(active)) _markBox(mark)];
    return [
      for (final place in places)
        if (_placeBox(frame, place) case final area
            when marks.every((mark) => !_hit(mark, area)))
          place,
    ];
  }
}

typedef _Box = ({double l, double t, double r, double b});

bool _hit(_Box a, _Box b) => a.l < b.r && b.l < a.r && a.t < b.b && b.t < a.b;

/// Where a mark and its label fall, in map units, a little wider than the
/// desktop's type so the phone's bigger labels do not touch either.
_Box _markBox(WebsiteRouteMapMark mark) {
  final chars = math.max(mark.title.length, mark.subtitle.length);
  final w = chars * 9.5;
  final bottom = mark.y + (mark.subtitle.isEmpty ? 12 : 32);
  return switch (mark.kind) {
    WebsiteRouteMarkKind.destination => (
      l: mark.x - 20 - w,
      t: mark.y - 12,
      r: mark.x + 12,
      b: mark.y + (mark.subtitle.isEmpty ? 48 : 68),
    ),
    _ when mark.end => (
      l: mark.x - 16 - w,
      t: mark.y - 14,
      r: mark.x + 10,
      b: bottom,
    ),
    _ => (l: mark.x - 10, t: mark.y - 14, r: mark.x + 16 + w, b: bottom),
  };
}

_Box _placeBox(WebsiteRouteMapFrame frame, WebsiteRoutePlace place) {
  final p = frame.project(place.at);
  final w = place.name.length * (place.water ? 8 : 10.5);
  return (l: p.x - w / 2, t: p.y - 16, r: p.x + w / 2, b: p.y + 6);
}

/// The projected track of [way] as SVG path data in map units.
String websiteRouteTrackPath(WebsiteRouteMapFrame frame, WebsiteRouteWay way) {
  final buffer = StringBuffer();
  for (final (i, at) in way.track.indexed) {
    final p = frame.project(at);
    buffer
      ..write(i == 0 ? 'M' : ' L')
      ..write(_fixed(p.x))
      ..write(',')
      ..write(_fixed(p.y));
  }
  return buffer.toString();
}

/// The height profile of a way laid out in a [width] × [height] drawing,
/// with room for the axes: the same numbers for the canvas and the HTML.
class WebsiteRouteChart {
  WebsiteRouteChart(
    this.way, {
    required this.width,
    required this.height,
    this.left = 56,
    this.right = 14,
    this.top = 30,
    this.bottom = 50,
    this.gridStep = 100,
    this.tickStep = 5,
  });

  final WebsiteRouteWay way;
  final double width;
  final double height;
  final double left;
  final double right;
  final double top;
  final double bottom;

  /// Metres between the grid's lines.
  final double gridStep;

  /// Kilometres between the ticks under the axis.
  final double tickStep;

  double get plotWidth => width - left - right;
  double get floorY => height - bottom;

  /// The top of the scale: the highest point rounded up to the grid, with
  /// room over it for its label.
  double get maxEle {
    final top = way.highest?.ele ?? gridStep;
    return (top / gridStep).ceil() * gridStep + gridStep * 0.12;
  }

  double x(double km) {
    final distance = way.distanceKm;
    return left + (distance <= 0 ? 0 : km / distance) * plotWidth;
  }

  double y(double ele) => floorY - ele / maxEle * (floorY - top);

  /// The kilometre under the horizontal position [atX].
  double kmAt(double atX) {
    final t = ((atX - left) / plotWidth).clamp(0.0, 1.0);
    return t * way.distanceKm;
  }

  List<({double x, double y})> get line => [
    for (final sample in way.profile) (x: x(sample.km), y: y(sample.ele)),
  ];

  String get linePath => _path(line);

  String get areaPath {
    final points = line;
    if (points.isEmpty) return '';
    return '${_path(points)} L${_fixed(points.last.x)},${_fixed(floorY)} '
        'L${_fixed(points.first.x)},${_fixed(floorY)} Z';
  }

  /// The grid's lines over zero, each with its label.
  List<({double y, String label})> get grid => [
    for (var ele = gridStep; ele < maxEle; ele += gridStep)
      (y: y(ele), label: '${ele.round()} m'),
  ];

  List<({double x, String label})> get ticks => [
    for (var km = 0.0; km <= way.distanceKm + 0.001; km += tickStep)
      (x: x(km), label: km == 0 ? '0 km' : km.round().toString()),
  ];

  /// The shaded climb, when the way names one.
  ({double x0, double x1, String label})? get climb {
    final from = way.climbFrom, to = way.climbTo;
    if (from == null || to == null || to <= from) return null;
    return (x0: x(from), x1: x(to), label: way.climb);
  }

  /// The baseline of a label written over the line between [x0] and [x1]:
  /// [gap] above the line's highest point there, so the line never runs
  /// through its letters.
  double labelBaseline(double x0, double x1, {double gap = 12}) {
    var top = math.min(y(way.eleAt(kmAt(x0))), y(way.eleAt(kmAt(x1))));
    for (final point in line) {
      if (point.x > x0 && point.x < x1) top = math.min(top, point.y);
    }
    return top - gap;
  }

  /// The top of a label written under the line between [x0] and [x1]:
  /// [gap] below the line's lowest point there.
  double labelTopUnder(double x0, double x1, {double gap = 12}) {
    var bottom = math.max(y(way.eleAt(kmAt(x0))), y(way.eleAt(kmAt(x1))));
    for (final point in line) {
      if (point.x > x0 && point.x < x1) bottom = math.max(bottom, point.y);
    }
    return bottom + gap;
  }

  /// The points named on the profile, in the order they are placed: with
  /// [nameHighest], the highest point by its height; with [namePoints], the
  /// way's points, one too close to another left out; and the destination,
  /// always, at the end.
  ///
  /// Each label sits over the line along its whole width ([charWidth] a
  /// letter of [fontSize] type, [gap] from the line). One that would cover
  /// a label already placed goes under the line instead, and one that fits
  /// neither way is left out, its dot still drawn (an empty [label]).
  List<WebsiteRouteChartMark> marks({
    double minGap = 110,
    double charWidth = 7.2,
    double fontSize = 13,
    double gap = 12,
    bool namePoints = true,
    bool nameHighest = false,
  }) {
    final out = <WebsiteRouteChartMark>[];
    final placed = <_Box>[];
    _Box box(double l, double r, double baseline) => (
      l: l,
      t: baseline - fontSize * 0.8,
      r: r,
      b: baseline + fontSize * 0.25,
    );
    void add(double km, String text, WebsiteRouteChartMarkKind kind) {
      final cx = x(km);
      final width = text.length * charWidth;
      // The span the label covers, and where its baseline point is.
      final (l, r, labelX) = switch (kind) {
        WebsiteRouteChartMarkKind.destination => (
          cx - 10 - width,
          cx - 10,
          cx - 10,
        ),
        WebsiteRouteChartMarkKind.highest => (
          cx - width / 2,
          cx + width / 2,
          cx,
        ),
        WebsiteRouteChartMarkKind.point => (cx, cx + 9 + width, cx + 9),
      };
      var label = text;
      var labelY = labelBaseline(l, r, gap: gap);
      var area = box(l, r, labelY);
      if (placed.any((other) => _hit(other, area))) {
        labelY = labelTopUnder(l, r, gap: gap) + fontSize * 0.8;
        area = box(l, r, labelY);
        if (area.b > floorY || placed.any((other) => _hit(other, area))) {
          label = '';
        }
      }
      if (label.isNotEmpty) placed.add(area);
      out.add((
        kind: kind,
        x: cx,
        y: y(way.eleAt(km)),
        label: label,
        labelX: labelX,
        labelY: labelY,
      ));
    }

    final end = way.distanceKm;
    final endX = x(end);
    if (nameHighest) {
      if (way.highest case final top?) {
        add(top.km, '${top.ele.round()} m', WebsiteRouteChartMarkKind.highest);
      }
    }
    if (namePoints) {
      for (final point in way.points) {
        if (point.isStretch || point.km <= 0.5 || point.km >= end - 0.5) {
          continue;
        }
        final cx = x(point.km);
        if ((endX - cx).abs() < minGap) continue;
        if (out.any((mark) => (mark.x - cx).abs() < minGap)) continue;
        add(point.km, point.title, WebsiteRouteChartMarkKind.point);
      }
    }
    final last = way.points.isEmpty ? null : way.points.last;
    if (last != null && !last.isStretch && last.km >= end - 0.5) {
      add(end, last.title, WebsiteRouteChartMarkKind.destination);
    }
    return out;
  }
}

enum WebsiteRouteChartMarkKind { point, highest, destination }

/// A point named on the profile: the dot at ([x], [y]) and its label's
/// baseline point at ([labelX], [labelY]) — the label starts there, is
/// centered on it or ends there ([WebsiteRouteChartMarkPlacement.anchor]).
typedef WebsiteRouteChartMark = ({
  WebsiteRouteChartMarkKind kind,
  double x,
  double y,
  String label,
  double labelX,
  double labelY,
});

extension WebsiteRouteChartMarkPlacement on WebsiteRouteChartMark {
  /// The destination, drawn in the accent.
  bool get last => kind == WebsiteRouteChartMarkKind.destination;

  /// Which part of the label sits on ([labelX], [labelY]), named as SVG's
  /// `text-anchor`.
  String get anchor => switch (kind) {
    WebsiteRouteChartMarkKind.point => 'start',
    WebsiteRouteChartMarkKind.highest => 'middle',
    WebsiteRouteChartMarkKind.destination => 'end',
  };
}

/// Kilometres as the store writes them: one decimal with a comma, none when
/// it is whole («km 0», «km 36,2»).
String websiteRouteKm(double km) {
  // Rounded on tenths, so 16,45 reads 16,5 and not the 16,4 a binary
  // 16.449999… would give.
  final tenths = (km * 10).round();
  final whole = tenths ~/ 10, rest = (tenths % 10).abs();
  return rest == 0 ? '$whole' : '$whole,$rest';
}

/// The climb as the page says it: rounded to ten metres.
String websiteRouteGain(double metres) =>
    ((metres / 10).round() * 10).toString();

/// How a point's kilometre is written: «km 12,8 · 370 m», or «km 1,7 a 9,1»
/// for a stretch.
String websiteRoutePointLabel(WebsiteRouteWay way, WebsiteRoutePoint point) {
  if (point.toKm case final to?) {
    return 'km ${websiteRouteKm(point.km)} a ${websiteRouteKm(to)}';
  }
  return 'km ${websiteRouteKm(point.km)} · ${way.eleAt(point.km).round()} m';
}

/// The great-circle distance between two places, in kilometres.
double websiteRouteDistanceKm(
  WebsiteRouteCoordinate a,
  WebsiteRouteCoordinate b,
) {
  const earth = 6371.0088;
  final la1 = a.lat * math.pi / 180, la2 = b.lat * math.pi / 180;
  final dLa = la2 - la1;
  final dLo = (b.lon - a.lon) * math.pi / 180;
  final h =
      math.sin(dLa / 2) * math.sin(dLa / 2) +
      math.cos(la1) * math.cos(la2) * math.sin(dLo / 2) * math.sin(dLo / 2);
  return 2 * earth * math.asin(math.min(1, math.sqrt(h)));
}

/// A track as written in the inspector: one place per line (or separated
/// by «;»), latitude then longitude with a point for the decimals:
/// `-33.0245, -71.5518`. A line that is not a place is skipped.
List<WebsiteRouteCoordinate> websiteRouteParseTrack(String text) => [
  for (final pair in _pairs(text))
    if (pair.$1.abs() <= 90 && pair.$2.abs() <= 180)
      WebsiteRouteCoordinate(pair.$1, pair.$2),
];

/// A profile as written in the inspector: one sample per line (or separated
/// by «;»), kilometre then height: `12.8, 370`. Samples go in order of
/// distance; one that goes back is skipped.
List<WebsiteRouteSample> websiteRouteParseProfile(String text) {
  final out = <WebsiteRouteSample>[];
  for (final pair in _pairs(text)) {
    if (pair.$1 < 0) continue;
    if (out.isNotEmpty && pair.$1 < out.last.km) continue;
    out.add(WebsiteRouteSample(pair.$1, pair.$2));
  }
  return out;
}

/// The points as written in the inspector, one per line:
/// `12,8 | Ruta 68 | Entras por Las Palmas.`, or a stretch
/// `1,7 a 9,1 | Agua Santa | La subida larga.` The kilometre takes a comma
/// or a point.
List<WebsiteRoutePoint> websiteRouteParsePoints(String text) {
  final out = <WebsiteRoutePoint>[];
  for (final line in text.split('\n')) {
    final parts = line.split('|').map((part) => part.trim()).toList();
    if (parts.length < 2 || parts[1].isEmpty) continue;
    final range = RegExp(
      r'^\s*([\d.,]+)\s*(?:a|-|–)\s*([\d.,]+)\s*$',
    ).firstMatch(parts[0]);
    final from = _number(range?.group(1) ?? parts[0]);
    if (from == null) continue;
    final to = range == null ? null : _number(range.group(2));
    out.add(
      WebsiteRoutePoint(
        km: from,
        toKm: to != null && to > from ? to : null,
        title: parts[1],
        note: parts.length > 2 ? parts.sublist(2).join(' | ') : '',
      ),
    );
  }
  return out;
}

Iterable<(double, double)> _pairs(String text) sync* {
  for (final chunk in text.split(RegExp(r'[\n;]'))) {
    final numbers = RegExp(
      r'-?\d+(?:\.\d+)?',
    ).allMatches(chunk).map((match) => double.parse(match.group(0)!)).toList();
    if (numbers.length >= 2) yield (numbers[0], numbers[1]);
  }
}

String _text(Object? value) => value?.toString().trim() ?? '';

double? _number(Object? value) {
  if (value is num) return value.toDouble();
  final text = _text(value).replaceAll(',', '.');
  if (text.isEmpty) return null;
  return double.tryParse(text);
}

String _fixed(double value) => value.toStringAsFixed(1);

String _path(List<({double x, double y})> points) {
  final buffer = StringBuffer();
  for (final (i, point) in points.indexed) {
    buffer
      ..write(i == 0 ? 'M' : ' L')
      ..write(_fixed(point.x))
      ..write(',')
      ..write(_fixed(point.y));
  }
  return buffer.toString();
}
