import 'dart:convert';

import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';
import 'package:vinabike_public_core/modules/website/models/website_route_content.dart';
import 'package:vinabike_public_core/modules/website/theme/website_theme_roles.dart';

import 'block_composition.dart';
import 'css_values.dart';
import 'website_blocks_view.dart';

const _attr = HtmlEscape(HtmlEscapeMode.attribute);
const _el = HtmlEscape(HtmlEscapeMode.element);

/// The wide profile: one drawing for a desktop column (800 wide in a guide).
const _wide = (width: 800.0, height: 300.0);

/// The phone's profile: taller, with bigger type, as the guide's canvas.
const _narrow = (width: 600.0, height: 400.0);

/// How wide a letter of a label on the profile is, in the drawing's units:
/// 13 and 22 units of type (`.rt-ax`), a little over half of it.
const _wideLetter = 7.2;
const _narrowLetter = 12.2;

/// `WebsiteRouteBlockContent`: the «Ruta» block. Beside the map, the reader
/// picks where they leave from (radio buttons, so it works without the
/// script) and reads that way's facts; the map draws every way, the picked
/// one in the accent; under it, the height profile and the points along the
/// road. Every figure comes from [WebsiteRouteContent], as on the canvas.
class RouteBlockView extends StatelessComponent {
  const RouteBlockView(this.composed, this.context, {super.key});

  final ComposedBlock composed;
  final BlockRenderContext context;

  @override
  Component build(BuildContext _) {
    final content = WebsiteRouteContent.fromData(composed.data);
    final ways = content.drawable;
    if (ways.isEmpty) {
      // Nothing to draw for a visitor; the editor's draft says what is
      // missing in its place.
      return div(classes: 'rt-empty', [
        if (context.draft)
          p([
            .text(
              'Escribe en el panel el trazado y el perfil de una salida: el '
              'mapa y el perfil se dibujan con ellos.',
            ),
          ]),
      ]);
    }
    final group = 'rt-${_slug(composed.block.id)}';
    final pick = content.pickLabel.isEmpty
        ? 'Desde dónde sales'
        : content.pickLabel;
    return section(
      classes: 'rt',
      attributes: {'data-route': ''},
      [
        div(classes: 'rt-hero', [
          div(classes: 'rt-side', [
            if (ways.length > 1)
              fieldset(classes: 'rt-pick', [
                legend(classes: 'rt-q', [.text(pick)]),
                div(classes: 'rt-seg', [
                  for (final (i, way) in ways.indexed) ...[
                    input<String>(
                      type: InputType.radio,
                      name: group,
                      id: '$group-$i',
                      value: '$i',
                      checked: i == 0,
                      classes: 'rt-r',
                    ),
                    label(htmlFor: '$group-$i', [.text(way.label)]),
                  ],
                ]),
              ]),
            for (final (i, way) in ways.indexed)
              dl(
                classes: 'rt-facts',
                attributes: {'data-way': '$i'},
                [
                  if (way.start.isNotEmpty) ..._fact('Salida', way.start),
                  ..._fact(
                    'Distancia de ida',
                    '${websiteRouteKm(way.distanceKm)} km',
                  ),
                  ..._fact(
                    'Subida acumulada',
                    '≈${websiteRouteGain(way.gainM)} m',
                  ),
                  if (way.highest case final top?)
                    ..._fact(
                      'Punto más alto',
                      '${top.ele.round()} m, en el km ${websiteRouteKm(top.km)}',
                    ),
                  if (way.road.isNotEmpty) ..._fact('Camino', way.road),
                ],
              ),
          ]),
          if (content.map != null)
            div(classes: 'rt-map', [
              for (final (i, _) in ways.indexed) RawText(_mapSvg(content, i)),
              if (content.credit.isNotEmpty)
                span(classes: 'rt-credit', [.text(content.credit)]),
            ]),
        ]),
        div(classes: 'rt-body', [
          if (content.profileTitle.isNotEmpty)
            h2(classes: 'rt-h', [.text(content.profileTitle)]),
          for (final (i, way) in ways.indexed)
            div(
              classes: 'rt-way',
              attributes: {'data-way': '$i'},
              [
                if (way.summary.isNotEmpty)
                  p(classes: 'rt-sum', [.text(way.summary)]),
                RawText(_chartSvg(way, wide: true)),
                RawText(_chartSvg(way, wide: false)),
                div(classes: 'rt-cap', [
                  span(classes: 'rt-hint rt-w', [
                    .text(
                      'Pasa el mouse sobre el perfil para ver la altura en cada '
                      'kilómetro.',
                    ),
                  ]),
                  span(classes: 'rt-hint rt-n', [
                    .text(
                      'Toca el perfil para ver la altura en cada kilómetro.',
                    ),
                  ]),
                  if (content.source.isNotEmpty) span([.text(content.source)]),
                ]),
                if (way.points.isNotEmpty)
                  div(classes: 'rt-pts', [
                    for (final point in way.points)
                      div(classes: 'rt-pt', [
                        span(classes: 'rt-k', [
                          .text(websiteRoutePointLabel(way, point)),
                        ]),
                        h3(classes: 'rt-t', [.text(point.title)]),
                        if (point.note.isNotEmpty) p([.text(point.note)]),
                      ]),
                  ]),
              ],
            ),
        ]),
      ],
    );
  }

  List<Component> _fact(String term, String value) => [
    div(classes: 'rt-f', [
      dt([.text(term)]),
      dd([.text(value)]),
    ]),
  ];
}

/// The map of the way at [active]: the base image, the names written on
/// it, the other ways dashed, the picked one in the accent, and its marks.
String _mapSvg(WebsiteRouteContent content, int active) {
  final frame = content.map!;
  final ways = content.drawable;
  final way = ways[active];
  final crop = content.crop()!;
  final buffer = StringBuffer()
    ..write(
      '<svg class="rt-svg" data-way="$active" viewBox="${_n(crop.x)} '
      '${_n(crop.y)} ${_n(crop.w)} ${_n(crop.h)}" '
      'preserveAspectRatio="xMidYMid meet" role="img" aria-label="'
      '${_attr.convert(content.mapLabel(active))}">',
    )
    ..write(
      '<image href="${_attr.convert(frame.image)}" x="0" y="0" '
      'width="${_n(WebsiteRouteMapFrame.width)}" height="${_n(frame.height)}" '
      'preserveAspectRatio="none"/>',
    );
  for (final place in content.mapPlaces(active)) {
    final p = frame.project(place.at);
    buffer.write(
      '<text class="${place.water ? 'rt-water' : 'rt-place'}" '
      'x="${_n(p.x)}" y="${_n(p.y)}" text-anchor="middle">'
      '${_el.convert(place.name)}</text>',
    );
  }
  for (final other in ways) {
    if (identical(other, way)) continue;
    buffer.write(
      '<path class="rt-other" d="${websiteRouteTrackPath(frame, other)}"/>',
    );
  }
  buffer.write(
    '<path class="rt-line" d="${websiteRouteTrackPath(frame, way)}"/>',
  );
  for (final mark in content.mapMarks(active)) {
    final x = mark.x, y = mark.y;
    final lx = mark.end ? x - 16 : x + 16;
    final anchor = mark.end ? 'end' : 'start';
    switch (mark.kind) {
      case WebsiteRouteMarkKind.destination:
        buffer.write(
          '<circle class="rt-dest" cx="${_n(x)}" cy="${_n(y)}" r="9"/>',
        );
      case WebsiteRouteMarkKind.start:
        buffer.write(
          '<circle class="rt-start" cx="${_n(x)}" cy="${_n(y)}" r="8"/>',
        );
      case WebsiteRouteMarkKind.highest:
        buffer.write(
          '<path class="rt-top" d="M${_n(x)},${_n(y - 9)} l8,13 h-16 z"/>',
        );
      case WebsiteRouteMarkKind.point:
        buffer.write(
          '<circle class="rt-dot" cx="${_n(x)}" cy="${_n(y)}" r="5"/>',
        );
      case WebsiteRouteMarkKind.otherStart:
        buffer.write(
          '<text class="rt-place" x="${_n(lx)}" y="${_n(y + 5)}" '
          'text-anchor="$anchor">${_el.convert(mark.title)}</text>',
        );
        continue;
    }
    // The destination's label sits under it, the others beside.
    final ty = mark.kind == WebsiteRouteMarkKind.destination ? y + 40 : y + 5;
    final tx = mark.kind == WebsiteRouteMarkKind.destination ? x - 20 : lx;
    final tAnchor = mark.kind == WebsiteRouteMarkKind.destination
        ? 'end'
        : anchor;
    buffer.write(
      '<text class="rt-key" x="${_n(tx)}" y="${_n(ty)}" '
      'text-anchor="$tAnchor">${_el.convert(mark.title)}</text>',
    );
    if (mark.subtitle.isNotEmpty) {
      buffer.write(
        '<text class="rt-sub" x="${_n(tx)}" y="${_n(ty + 20)}" '
        'text-anchor="$tAnchor">${_el.convert(mark.subtitle)}</text>',
      );
    }
  }
  return (buffer..write('</svg>')).toString();
}

/// The height profile of [way], wide (for a column) or narrow (a phone):
/// the grid, the shaded climb, the line, its points, and the marks the
/// script moves under the pointer. The samples ride along in `data-p` so
/// the script reads the height at any kilometre without a second source.
String _chartSvg(WebsiteRouteWay way, {required bool wide}) {
  final size = wide ? _wide : _narrow;
  final chart = WebsiteRouteChart(
    way,
    width: size.width,
    height: size.height,
    left: wide ? 56 : 70,
    right: wide ? 14 : 16,
    top: wide ? 34 : 48,
    bottom: wide ? 46 : 70,
    gridStep: wide ? 100 : 200,
    tickStep: wide ? 5 : 10,
  );
  final samples = way.profile
      .map((sample) => '${_n(sample.km, 2)},${_n(sample.ele)}')
      .join(';');
  final buffer = StringBuffer()
    ..write(
      '<svg class="rt-chart ${wide ? 'rt-w' : 'rt-n'}" '
      'viewBox="0 0 ${_n(size.width)} ${_n(size.height)}" role="img" '
      'aria-label="${_attr.convert('Perfil de altura ${way.label.toLowerCase()}: '
      'de ${way.profile.first.ele.round()} m a '
      '${way.highest?.ele.round() ?? 0} m en '
      '${websiteRouteKm(way.distanceKm)} km')}" '
      'data-p="$samples" data-g="${_n(chart.left)},${_n(chart.plotWidth)},'
      '${_n(chart.floorY)},${_n(chart.top)},${_n(chart.maxEle)},'
      '${_n(way.distanceKm, 2)}">',
    );
  if (chart.climb case final climb?) {
    buffer
      ..write(
        '<rect class="rt-climb" x="${_n(climb.x0)}" y="${_n(chart.top)}" '
        'width="${_n(climb.x1 - climb.x0)}" '
        'height="${_n(chart.floorY - chart.top)}"/>',
      )
      ..write(
        '<text class="rt-ax rt-cl" x="${_n((climb.x0 + climb.x1) / 2)}" '
        'y="${_n(chart.top + (wide ? 18 : 28))}" text-anchor="middle">'
        '${_el.convert(climb.label)}</text>',
      );
  }
  for (final line in chart.grid) {
    buffer
      ..write(
        '<line class="rt-grid" x1="${_n(chart.left)}" '
        'x2="${_n(size.width - chart.right)}" y1="${_n(line.y)}" '
        'y2="${_n(line.y)}"/>',
      )
      ..write(
        '<text class="rt-ax" x="${_n(chart.left - 10)}" '
        'y="${_n(line.y + (wide ? 4 : 7))}" text-anchor="end">'
        '${line.label}</text>',
      );
  }
  buffer.write(
    '<line class="rt-base" x1="${_n(chart.left)}" '
    'x2="${_n(size.width - chart.right)}" y1="${_n(chart.floorY)}" '
    'y2="${_n(chart.floorY)}"/>',
  );
  for (final tick in chart.ticks) {
    buffer.write(
      '<text class="rt-ax" x="${_n(tick.x)}" '
      'y="${_n(chart.floorY + (wide ? 24 : 36))}" text-anchor="middle">'
      '${tick.label}</text>',
    );
  }
  buffer
    ..write('<path class="rt-area" d="${chart.areaPath}"/>')
    ..write('<path class="rt-prof" d="${chart.linePath}"/>');
  // A column names the way's points; the phone, only the highest one by its
  // height and the destination.
  final marks = chart.marks(
    minGap: wide ? 110 : 160,
    charWidth: wide ? _wideLetter : _narrowLetter,
    fontSize: wide ? 13 : 22,
    gap: wide ? 12 : 16,
    namePoints: wide,
    nameHighest: !wide,
  );
  for (final mark in marks) {
    buffer.write(
      '<circle class="${mark.last ? 'rt-pend' : 'rt-pdot'}" '
      'cx="${_n(mark.x)}" cy="${_n(mark.y)}" r="${wide ? 5 : 7}"/>',
    );
    if (mark.label.isEmpty) continue;
    buffer.write(
      '<text class="rt-ax rt-mk" x="${_n(mark.labelX)}" '
      'y="${_n(mark.labelY)}" text-anchor="${mark.anchor}">'
      '${_el.convert(mark.label)}</text>',
    );
  }
  buffer
    ..write(
      '<g class="rt-hov" style="display:none"><line x1="0" x2="0" '
      'y1="${_n(chart.top)}" '
      'y2="${_n(chart.floorY)}"/><circle r="${wide ? 6 : 8}" cx="0" cy="0"/>'
      '<text class="rt-ax rt-tip" x="0" y="${_n(chart.top - (wide ? 12 : 18))}">'
      '</text></g>',
    )
    ..write(
      '<rect class="rt-hit" x="${_n(chart.left)}" y="${_n(chart.top)}" '
      'width="${_n(chart.plotWidth)}" '
      'height="${_n(chart.floorY - chart.top)}"/>',
    )
    ..write('</svg>');
  return buffer.toString();
}

String _n(double value, [int digits = 1]) {
  final text = value.toStringAsFixed(digits);
  return text.contains('.') ? text.replaceFirst(RegExp(r'\.?0+$'), '') : text;
}

String _slug(String id) => id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');

/// The stylesheet of the «Ruta» block. The map is a picture of the land
/// and keeps its own dark colors; the rest follows the theme. Inside a
/// guide its columns line up with the guide's (`--g-col`).
String routeBlockCss(WebsiteThemeRoles theme) {
  final heading = cssPx(theme.headingSize);
  return '''
.rt{--rt-col:var(--g-col,1136px);--rt-pad:var(--g-pad,var(--w-cp,16px));container-type:inline-size;color:var(--ink);font-family:var(--body)}
.rt-empty p{max-width:var(--rt-col,800px);margin:0 auto;padding:40px 16px;color:var(--muted);font:400 16px/1.5 var(--body)}
.rt-hero{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));border-bottom:1px solid var(--line)}
.guide-head+.blocks:has(>.blk:first-child>.rt){padding-top:0}
.rt-side{display:flex;flex-direction:column;gap:32px;padding:48px 48px 56px max(var(--rt-pad),calc((100cqw - var(--rt-col)) / 2))}
.rt-pick{margin:0;padding:0;border:0;min-width:0;display:flex;flex-direction:column;gap:12px}
.rt-q{padding:0;font:600 14px/1.3 var(--body);color:var(--on-variant)}
.rt-seg{display:grid;grid-auto-flow:column;grid-auto-columns:minmax(0,1fr);gap:1px;background:var(--outline-variant);border:1px solid var(--outline-variant)}
.rt-r{position:absolute;opacity:0;width:1px;height:1px;pointer-events:none}
.rt-seg label{display:flex;align-items:center;justify-content:center;min-height:52px;padding:0 8px;text-align:center;background:#fff;font:600 16px/1.2 var(--body);color:var(--ink);cursor:pointer}
.rt-seg label:hover{background:color-mix(in srgb,var(--primary) 8%,#fff)}
.rt-r:checked+label{background:var(--primary);color:#fff}
.rt-r:focus-visible+label{outline:3px solid var(--accent);outline-offset:-3px}
.rt-facts{margin:0;border-top:1px solid var(--ink);font-size:16px;line-height:1.45}
.rt-f{display:grid;grid-template-columns:minmax(0,5fr) minmax(0,7fr);column-gap:24px;padding:13px 0;border-bottom:1px solid var(--line);align-items:baseline}
.rt-f dt{color:var(--on-variant)}
.rt-f dd{margin:0;font-weight:600}
.rt-map{position:relative;min-height:600px;background:#0f2036;overflow:hidden}
.rt-svg{position:absolute;inset:0;width:100%;height:100%;display:block}
.rt-credit{position:absolute;right:12px;bottom:8px;font:400 11px/1.3 var(--body);color:#8ea3bb}
.rt-svg text{font-family:var(--body)}
.rt-place{font:500 13px var(--head);letter-spacing:.12em;text-transform:uppercase;fill:#8ea3bb}
.rt-water{font:italic 500 14px var(--body);fill:#8ea3bb}
.rt-key{font:700 15px var(--body);fill:#fff}
.rt-sub{font:500 13px var(--body);fill:#c9d4e0}
.rt-other{fill:none;stroke:#9fb3c8;stroke-width:2;stroke-dasharray:5 6;opacity:.7}
.rt-line{fill:none;stroke:var(--accent);stroke-width:4;stroke-linecap:round;stroke-linejoin:round}
.rt-start{fill:#0b1420;stroke:#fff;stroke-width:3}
.rt-dest{fill:var(--accent);stroke:#0b1420;stroke-width:3}
.rt-top{fill:#fff}
.rt-dot{fill:#fff}
.rt-body{box-sizing:border-box;max-width:calc(var(--rt-col) + 2 * var(--rt-pad));margin:0 auto;padding:64px var(--rt-pad) 24px}
.rt-h{margin:0 0 16px;font:400 $heading/1.15 var(--head);color:var(--ink);text-wrap:balance}
.rt-sum{margin:0 0 32px;max-width:640px;font:400 18px/1.6 var(--body);color:var(--on-variant)}
.rt-chart{display:block;width:100%;height:auto;touch-action:pan-y}
.rt-n,.rt-hint.rt-n{display:none}
.rt-ax{font:400 13px var(--body);fill:var(--muted)}
.rt-n .rt-ax{font-size:22px}
.rt-mk{font-weight:600;fill:var(--ink)}
.rt-cl{font-weight:600;fill:color-mix(in srgb,var(--accent) 75%,#000)}
.rt-climb{fill:var(--accent);opacity:.08}
.rt-grid{stroke:var(--line);stroke-width:1}
.rt-base{stroke:var(--ink);stroke-width:1}
.rt-area{fill:var(--primary);opacity:.08}
.rt-prof{fill:none;stroke:var(--primary);stroke-width:2;stroke-linejoin:round}
.rt-n .rt-prof{stroke-width:3}
.rt-pdot{fill:var(--ink);stroke:#fff;stroke-width:2}
.rt-pend{fill:var(--accent);stroke:#fff;stroke-width:2}
.rt-hov line{stroke:var(--ink);stroke-width:1}
.rt-hov circle{fill:var(--accent);stroke:#fff;stroke-width:2}
.rt-tip{font-weight:700;fill:var(--ink);paint-order:stroke;stroke:#fff;stroke-width:5px;stroke-linejoin:round}
.rt-hit{fill:transparent;cursor:crosshair}
.rt-cap{display:flex;justify-content:space-between;flex-wrap:wrap;gap:8px 24px;margin-top:12px;font:400 15px/1.5 var(--body);color:var(--muted)}
.rt-pts{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));margin-top:40px;border-top:1px solid var(--ink)}
.rt-pt{display:flex;flex-direction:column;gap:8px;min-width:0;padding:24px 28px;border-left:1px solid var(--line)}
.rt-pt:nth-child(3n+1){border-left:0;padding-left:0}
.rt-pt:nth-child(3n){padding-right:0}
.rt-pt:nth-child(n+4){border-top:1px solid var(--line)}
.rt-k{font:600 14px/1.3 var(--body);color:var(--on-variant)}
.rt-t{margin:0;font:500 21px/1.15 var(--head);letter-spacing:.02em;text-transform:uppercase;color:var(--ink)}
.rt-pt p{margin:0;font:400 16px/1.5 var(--body);color:var(--on-variant)}
${[for (var i = 0; i < 4; i++) '.rt:has(.rt-r[value="$i"]:checked) [data-way]:not([data-way="$i"]){display:none}'].join('\n')}
@container (max-width:900px){
.rt-hero{grid-template-columns:minmax(0,1fr)}
.rt-side{padding:40px var(--rt-pad)}
.rt-map{min-height:460px}
}
@container (max-width:719.98px){
.rt-map{min-height:420px}
.rt-key{font-size:21px}
.rt-sub{font-size:17px}
.rt-place{font-size:17px}
.rt-water{font-size:18px}
.rt-body{padding-top:48px}
.rt-h{font-size:min($heading,30px);line-height:1.2}
.rt-w,.rt-hint.rt-w{display:none}
.rt-n{display:block}
.rt-hint.rt-n{display:inline}
.rt-pts{grid-template-columns:minmax(0,1fr)}
.rt-pt,.rt-pt:nth-child(3n+1),.rt-pt:nth-child(3n){padding:20px 0;border-left:0;border-top:1px solid var(--line)}
.rt-pt:first-child{border-top:0}
}
''';
}

/// Moves the profile's mark under the pointer (or the finger) and writes
/// the kilometre and the height there, read from the samples the drawing
/// carries. Without it the profile is still whole, with its points.
const routeScript = r'''
(()=>{for(const svg of document.querySelectorAll('.rt-chart')){
const p=svg.dataset.p.split(';').map(s=>s.split(',').map(Number));
const [l,w,fl,tp,mx,d]=svg.dataset.g.split(',').map(Number);
const g=svg.querySelector('.rt-hov'),ln=g.querySelector('line'),c=g.querySelector('circle'),t=g.querySelector('text');
const ele=k=>{for(let i=1;i<p.length;i++){if(p[i][0]>=k){const a=p[i-1],b=p[i],s=(b[0]-a[0])||1;return a[1]+(b[1]-a[1])*(k-a[0])/s}}return p[p.length-1][1]};
const show=e=>{const r=svg.getBoundingClientRect(),vb=svg.viewBox.baseVal,x=(e.clientX-r.left)/r.width*vb.width;
const k=Math.max(0,Math.min(1,(x-l)/w))*d,h=ele(k),X=l+k/d*w,Y=fl-h/mx*(fl-tp);
ln.setAttribute('x1',X);ln.setAttribute('x2',X);c.setAttribute('cx',X);c.setAttribute('cy',Y);
t.textContent='km '+k.toFixed(1).replace('.',',')+' · '+Math.round(h)+' m';
const end=X>l+w*.7;t.setAttribute('x',end?X-10:X+10);t.setAttribute('text-anchor',end?'end':'start');g.style.display=''};
const hit=svg.querySelector('.rt-hit');hit.addEventListener('pointermove',show);hit.addEventListener('pointerdown',show);
hit.addEventListener('pointerleave',()=>{g.style.display='none'})}})();
''';
