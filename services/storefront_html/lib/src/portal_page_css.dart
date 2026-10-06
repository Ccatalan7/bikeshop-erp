import 'package:vinabike_public_core/modules/website/theme/website_theme_roles.dart';

import 'css_values.dart';

/// The portal's styles, «Sendero» as Flutter's `PortalStyle` draws it: every
/// color from the editor theme's roles, square corners, the heading font in
/// capitals, sizes and gaps from `customer_portal_style.dart`,
/// `customer_portal_layout.dart` and the rows, tiles and cards.
///
/// How a Flutter text is copied: its line is the size times the style's
/// height, rounded (SkParagraph). Every portal style derives from the
/// theme's Material 3 text styles, which split a line's extra room half and
/// half (`TextLeadingDistribution.even`, `Typography.englishLike2021`) as
/// CSS does, so the glyphs sit where CSS puts them; a bare `TextStyle` would
/// be proportional instead (the mega menu's). The heading font ships one
/// file, so its 600 and up is the regular outline emboldened by Skia, a
/// stroke of 1/24 of the size at 9 px to 1/32 at 36 px. SkParagraph puts
/// half of the letter spacing before each glyph and half after; CSS all of
/// it after, so a text moves right by half (`.pt-x`).
///
/// Boxes: the store theme's density (−1, −1) takes 4 px off a button's
/// minimum size and vertical padding, never off its horizontal padding
/// (`ButtonStyleButton`: `dx = max(0, …)`), so a portal button is 44 high
/// with its 24 px a side, and the site theme's text buttons keep their 20.
/// A button's side, a `DecoratedBox` border or a `Material` shape is painted
/// inside the box, over the padding (a `Container` adds it): here the
/// padding is 1 px less.
///
/// The layout breakpoints are Flutter's `LayoutBuilder`s, as container
/// queries: `pt` is the page's width (the band, the tabs, the service
/// band), `ptc` the content column's (rows, tiles, cards).
String portalPageCss(WebsiteThemeRoles roles) {
  final c = _PortalColors(roles);
  final head = _family(roles.headingFont);
  final body = _family(roles.bodyFont);

  _TextStyle heading(
    double size, {
    int weight = 600,
    double spacing = 1,
    double height = 1.05,
  }) => _TextStyle(head, size, height, weight, spacing, heading: true);
  _TextStyle text(double size, {int weight = 400, double height = 1.45}) =>
      _TextStyle(body, size, height, weight, 0.25, heading: false);

  final eyebrow = heading(13, weight: 500, spacing: 2.6);
  final label = heading(14, weight: 500, spacing: 1.6, height: 1.2);
  final label13 = heading(13, weight: 500, spacing: 1.6, height: 1.2);
  final label12 = heading(12, weight: 500, spacing: 1.6, height: 1.2);
  final tag = heading(12, weight: 500, spacing: 1.4, height: 1.1);
  final micro = heading(11, weight: 500, spacing: 1.3, height: 1.25);
  final figure = heading(20, spacing: 0.5);
  final figureSmall = heading(17, spacing: 0.5);
  final rowTitle = text(16, weight: 600, height: 1.3);
  final rowMeta = text(14, height: 1.4);
  final nextStep = text(14, weight: 600, height: 1.4);
  final subtitle = text(16);
  final number = heading(14, weight: 500);

  String rule(String selector, _TextStyle style, [String extra = '']) =>
      '$selector{${style.font}$extra}'
      '$selector>.pt-x{left:${cssPx(style.spacing / 2)}}';

  return '''
.pt{container:pt/inline-size;--pt-page:${c.page.css};--pt-well:${c.well.css};--pt-line:${c.line.css};--pt-ink:${c.ink.css};--pt-ink2:${c.ink2.css};--pt-act:${c.action.css};--pt-onact:${c.onAction.css};--pt-att:${c.attention.css};--pt-onatt:${c.onAttention.css};--pt-ok:${c.success.css};--pt-onok:${c.onSuccess.css};--pt-bad:${c.danger.css};--pt-onbad:${c.onDanger.css};--pt-hi:${c.highest.css};--pt-g:32px;background:var(--pt-page);color:var(--pt-ink)}
@container pt (max-width:559.98px){.pt *{--pt-g:16px}}
:where(.pt) *,:where(.pt) *::before,:where(.pt) *::after{box-sizing:border-box}
:where(.pt) :where(p,h1,h2,h3,dl,dd){margin:0}
:where(.pt) button{margin:0;padding:0;border:0;background:none;color:inherit;font:inherit;letter-spacing:inherit;text-align:inherit;cursor:pointer}
:where(.pt) a{color:inherit;text-decoration:none}
:where(.pt) svg{flex:none;display:block}
.pt-x{position:relative}
.pt-col{width:100%;max-width:calc(1120px + 2 * var(--pt-g));margin-inline:auto;padding-inline:var(--pt-g)}
.pt-noscript{max-width:480px;margin:0 auto;padding:40px 16px}

/* La franja: la foto del portal, el título abajo a la izquierda. */
.pt-band{position:relative;display:flex;flex-direction:column;justify-content:flex-end;min-height:210px;overflow:hidden;background:var(--pt-ink);color:var(--pt-page)}
.pt-band.prom{min-height:300px}
.pt-band.photo{color:#fff}
.pt-band-img{position:absolute;inset:0;width:100%;height:100%;object-fit:cover;object-position:30% 55%}
.pt-band-veil{position:absolute;inset:0;background:linear-gradient(90deg,rgb(10 11 11 / .8),rgb(10 11 11 / .451) 55%,rgb(10 11 11 / .149))}
.pt-band-in{position:relative;padding-block:48px 40px}
.pt-band-row{display:flex;align-items:flex-end;gap:24px}
.pt-band-head{flex:1;min-width:0}
${rule('.pt-eyebrow', eyebrow, ';display:block;text-transform:uppercase;opacity:.86')}
.pt-band .pt-eyebrow{margin-bottom:10px}
${rule('.pt-display', heading(72, height: 0.95), ';text-transform:uppercase;overflow-wrap:anywhere')}
${rule('.pt-title', heading(48, height: 0.95), ';text-transform:uppercase;overflow-wrap:anywhere')}
${rule('.pt-meta', text(15, height: 1.55), ';opacity:.88')}
.pt-band-head .pt-meta{max-width:620px;margin-top:10px}
.pt-band-row>.pt-meta{max-width:360px;text-align:right}
.pt-salir{display:none;position:absolute;top:6px;right:calc(var(--pt-g) - 8px);min-width:40px;min-height:40px;padding:0 20px}
${rule('.pt-salir', label12, ';text-transform:uppercase')}
.pt-band.out .pt-band-in{padding-top:64px}
@container pt (min-width:900px){.pt-band.out .pt-band-in{padding-top:48px}}
@container pt (max-width:899.98px){.pt-band.out .pt-salir{display:block}}
@container pt (max-width:559.98px){
.pt-band{min-height:170px}.pt-band.prom{min-height:240px}
.pt-band-veil{background:linear-gradient(0deg,rgb(10 11 11 / .851),rgb(10 11 11 / .302))}
.pt-band-in{padding-bottom:24px}
.pt-band-row{flex-direction:column;align-items:flex-start;gap:0}
.pt-band-row>.pt-meta{max-width:none;margin-top:10px;text-align:left}
.pt-band-head .pt-meta{max-width:none}
.pt-band-row>.pt-btn{margin-top:16px}
${rule('.pt-display', heading(44, height: 0.95))}
${rule('.pt-title', heading(34, height: 0.95))}
${rule('.pt-meta', text(14, height: 1.55))}
}

/* La banda de lo pendiente. */
.pt-pend{display:block;width:100%;background:var(--pt-ink);color:var(--pt-page)}
.pt-pend-in{display:flex;align-items:center;height:44px}
.pt-pend-dot{flex:none;width:8px;height:8px;margin-right:12px;background:var(--pt-att)}
${rule('.pt-pend-text', label13, ';flex:1;min-width:0;text-transform:uppercase;white-space:nowrap;overflow:hidden;text-overflow:ellipsis')}
.pt-pend-go{flex:none;display:flex;align-items:center;gap:8px;margin-left:16px;padding-bottom:2px;border-bottom:1px solid currentColor}
${rule('.pt-pend-go', label13, ';text-transform:uppercase')}

/* Las pestañas. */
.pt-tabs{height:60px;background:var(--pt-page);box-shadow:inset 0 -1px var(--pt-line)}
.pt-tabs-in{display:flex;height:100%}
.pt-tabs-scroll{flex:1;min-width:0;display:flex;overflow-x:auto;scrollbar-width:none}
.pt-tabs-scroll::-webkit-scrollbar{display:none}
.pt-tab{flex:none;display:flex;align-items:center;height:60px;padding:3px 14px 0;border-bottom:3px solid transparent;color:var(--pt-ink2)}
${rule('.pt-tab', label, ';text-transform:uppercase;white-space:nowrap')}
.pt-tab.on{border-bottom-color:var(--pt-act);color:var(--pt-ink)}
${rule('.pt-tab.on', heading(14, spacing: 1.6, height: 1.2))}
.pt-out{flex:none;display:none;align-items:center;justify-content:center;min-width:60px;height:60px;margin-left:24px;padding:0 20px;color:var(--pt-ink2)}
${rule('.pt-out', label12, ';text-transform:uppercase;white-space:nowrap')}
@container pt (min-width:900px){.pt-out{display:flex}}
@container pt (max-width:559.98px){.pt-tabs-in{padding-inline:4px}}
.pt-tab:hover,.pt-out:hover,.pt-salir:hover{background:color-mix(in srgb,currentColor 8%,transparent)}
.pt-tab:focus-visible,.pt-out:focus-visible,.pt-salir:focus-visible,.pt-btn:focus-visible,.pt-link:focus-visible,.pt-chip:focus-visible,.pt-row:focus-visible,.pt-bike:focus-visible,.pt-pend:focus-visible,.pt-wtile:focus-visible,.pt-close:focus-visible,.pt-back:focus-visible,.pt-file:focus-visible{outline:2px solid var(--pt-act);outline-offset:2px}

/* El contenido. */
.pt-main{padding-block:56px 80px}
.pt-main.with-foot{padding-bottom:72px}
@container pt (max-width:899.98px){.pt-main{padding-top:32px}}
.pt-content{container:ptc/inline-size}
.pt-back{display:inline-flex;align-items:center;gap:8px;min-height:40px;padding-inline:4px;margin-bottom:12px;color:var(--pt-ink)}
${rule('.pt-back', label13, ';text-transform:uppercase')}
.pt-sections{display:flex;flex-direction:column;gap:88px}
@container ptc (max-width:559.98px){.pt-sections{gap:56px}}
.pt-section{display:flex;flex-direction:column;gap:24px}
.pt-gap72{display:block;height:72px}
.pt-sh{display:flex;align-items:flex-end;gap:16px}
.pt-sh-main{flex:1;min-width:0}
.pt-sh-bar{display:block;width:36px;height:3px;margin-bottom:12px;background:var(--pt-act)}
.pt-sh-row{display:flex;flex-wrap:wrap;align-items:center;gap:8px 12px}
${rule('.pt-sh-title', heading(28, height: 1), ';text-transform:uppercase')}
@container pt (max-width:559.98px){${rule('.pt-sh-title', heading(24, height: 1))}}
.pt-count{display:inline-flex;align-items:center;justify-content:center;min-width:26px;min-height:26px;padding:4px 7px;background:var(--pt-att);color:var(--pt-onatt)}
${rule('.pt-count', heading(14, spacing: 0))}

/* Botones, enlaces, filtros y etiquetas. */
.pt-btn{display:inline-flex;align-items:center;justify-content:center;gap:10px;max-width:100%;min-height:44px;padding:0 23px;border:1px solid var(--pt-act);background:var(--pt-act);color:var(--pt-onact);vertical-align:middle}
${rule('.pt-btn', label, ';text-transform:uppercase;white-space:nowrap')}
.pt-btn-label{min-width:0;overflow:hidden;text-overflow:ellipsis}
${rule('.pt-btn-label', label)}
.pt-btn.sec{border-color:var(--pt-ink);background:transparent;color:var(--pt-ink)}
.pt-btn.photo{border-color:#fff;background:#fff;color:#111}
.pt-btn.full{display:flex;width:100%}
.pt-btn:hover{background-image:linear-gradient(color-mix(in srgb,currentColor 10%,transparent),color-mix(in srgb,currentColor 10%,transparent))}
.pt-link{display:inline-flex;align-items:center;min-height:44px;color:var(--pt-ink)}
.pt-link-in{display:inline-flex;align-items:center;gap:8px;padding-bottom:3px;border-bottom:1px solid currentColor}
${rule('.pt-link-in', label13, ';text-transform:uppercase')}
.pt-chips{display:flex;flex-wrap:wrap;gap:8px;margin-bottom:40px}
.pt-chip{display:inline-flex;align-items:center;gap:8px;max-width:100%;min-height:44px;padding:0 15px;border:1px solid var(--pt-line);color:var(--pt-ink)}
.pt-chip.on{border-color:var(--pt-ink);background:var(--pt-ink);color:var(--pt-page)}
.pt-chip.narrow{max-width:260px}
${rule('.pt-chip-label', label13, ';min-width:0;text-transform:uppercase;white-space:nowrap;overflow:hidden;text-overflow:ellipsis')}
${rule('.pt-chip-count', label13, ';opacity:.7;font-variant-numeric:tabular-nums')}
.pt-tag{display:inline-block;max-width:100%;padding:4px 9px;border:1px solid;vertical-align:top;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
${rule('.pt-tag', tag, ';text-transform:uppercase')}
.pt-tag.attention{border-color:var(--pt-att);background:var(--pt-att);color:var(--pt-onatt)}
.pt-tag.success{border-color:var(--pt-ok);background:var(--pt-ok);color:var(--pt-onok)}
.pt-tag.danger{border-color:var(--pt-bad);background:var(--pt-bad);color:var(--pt-onbad)}
.pt-tag.ink{border-color:var(--pt-ink);background:var(--pt-ink);color:var(--pt-page)}
.pt-tag.outline{border-color:var(--pt-ink);color:var(--pt-ink)}
.pt-tag.quiet{border-color:var(--pt-line);color:var(--pt-ink2)}
${rule('.pt-micro', micro, ';display:block;text-transform:uppercase;color:var(--pt-ink2)')}

/* Avisos y vacíos. */
.pt-notice{display:flex;flex-wrap:wrap;align-items:center;justify-content:space-between;gap:4px 16px;padding:10px 16px;background:var(--pt-well)}
.pt-notice-main{display:flex;align-items:center;gap:12px;max-width:640px}
${rule('.pt-notice-main>p', rowMeta, ';padding-block:8px;color:var(--pt-ink)')}
.pt-empty{padding:24px 24px 20px;background:var(--pt-well)}
${rule('.pt-empty-title', text(17, weight: 600, height: 1.3))}
${rule('.pt-empty-msg', rowMeta, ';max-width:560px;margin-top:6px;color:var(--pt-ink2)')}
.pt-empty-actions{display:flex;flex-wrap:wrap;align-items:center;gap:8px 24px;margin-top:16px}

/* Listas: una línea fuerte arriba, finas entre filas. */
.pt-th{display:none;align-items:center;padding-bottom:12px}
.pt-th-lead{flex:none;width:92px}
.pt-th-tail{flex:none;width:34px}
${rule('.pt-th-c', micro, ';flex:none;text-transform:uppercase;color:var(--pt-ink2)')}
.pt-th-c.pt-grow{flex:1;min-width:0}
.pt-th-total{width:110px;text-align:right}
@container ptc (min-width:880px){.pt-th{display:flex}}
.pt-rows{border-top:1px solid var(--pt-ink)}
.pt-row{display:block;width:100%;padding-block:12px;border-bottom:1px solid var(--pt-line);color:var(--pt-ink)}
.pt-row:hover{background:color-mix(in srgb,var(--pt-ink) 4%,transparent)}
.pt-row-table,.pt-row-mid,.pt-row-phone{display:none;align-items:center}
.pt-row-table>.pt-thumb,.pt-row-mid>.pt-thumb{margin-right:20px}
.pt-row-table>.pt-what,.pt-row-mid>.pt-what{flex:1;min-width:0}
.pt-row-table>svg,.pt-row-mid>svg{margin-left:16px}
@container ptc (min-width:880px){.pt-row-table{display:flex}}
@container ptc (min-width:560px) and (max-width:879.98px){.pt-row-mid{display:flex}}
@container ptc (max-width:559.98px){.pt-row-phone{display:flex}}
.pt-row-phone{align-items:flex-start}
.pt-row-phone>.pt-thumb{margin-right:14px}
.pt-row-phone>.pt-what{flex:1;min-width:0}
.pt-what{display:flex;flex-direction:column;align-items:flex-start;min-width:0}
.pt-what>.pt-what{align-self:stretch}
${rule('.pt-row-title', rowTitle, ';max-width:100%;overflow:hidden;display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical')}
.pt-row-title.one{-webkit-line-clamp:1}
.pt-row-title+.pt-row-meta{margin-top:3px}
${rule('.pt-row-meta', rowMeta, ';color:var(--pt-ink2)')}
.pt-row-meta.two{max-width:100%;overflow:hidden;display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical}
.pt-what>.pt-what+.pt-row-meta{margin-top:4px}
${rule('.pt-next', nextStep, ';margin-top:4px;color:var(--pt-ink)')}
${rule('.pt-row-num', number, ';flex:none;color:var(--pt-ink2)')}
${rule('.pt-row-date', rowMeta, ';flex:none;width:120px;color:var(--pt-ink2)')}
.pt-row-state{flex:none;width:200px;display:flex;min-width:0}
${rule('.pt-row-total', figure, ';flex:none;width:110px;text-align:right;font-variant-numeric:tabular-nums')}
.pt-row-end{flex:none;display:flex;flex-direction:column;align-items:flex-end;gap:8px;margin-left:16px}
${rule('.pt-fig', figure, ';font-variant-numeric:tabular-nums;white-space:nowrap')}
${rule('.pt-fig.small', figureSmall)}
.pt-row-foot{display:flex;flex-wrap:wrap;align-items:center;justify-content:space-between;gap:8px;align-self:stretch;margin-top:10px}
.pt-row-foot.job{row-gap:6px}
.pt-what>.pt-what+.pt-row-foot.job{margin-top:10px}
.pt-thumb{flex:none;display:flex;align-items:center;justify-content:center;background:var(--pt-well);color:var(--pt-ink2)}
.pt-thumb .pt-draw{color:var(--pt-ink)}
.pt-thumb-img{display:flex;width:100%;height:100%}

/* Fotos sobre el gris y el dibujo de la bici. */
.pt-pimg{display:flex;align-items:center;justify-content:center;width:100%;height:100%}
.pt-pimg>img{display:block;max-width:100%;max-height:100%;object-fit:contain;mix-blend-mode:multiply}
.pt-pimg.failed>img{display:none}
.pt-draw{display:block;flex:none;max-width:100%;color:var(--pt-ink)}
.pt-draw>svg{width:100%;height:auto;overflow:visible}
.pt-well{position:relative;display:block;height:220px;background:var(--pt-well)}
.pt-well-in{position:absolute;inset:0;display:flex;align-items:center;justify-content:center;padding:44px 24px 16px}
.pt-well-tl{position:absolute;top:16px;left:16px;display:flex}
${rule('.pt-well-tr', heading(12, weight: 500, spacing: 2), ';position:absolute;top:20px;right:16px;color:var(--pt-ink2)')}
.pt-well-icon{color:var(--pt-ink2)}
.pt-well-draw{display:flex;align-items:center;justify-content:center;width:100%;height:100%}
.pt-draw-compact{display:none}
.pt-draw-wide,.pt-draw-compact{max-width:100%;max-height:100%;justify-content:center;align-items:center}
.pt-draw-wide{display:flex}

/* Fichas grandes: de a dos con el mismo alto, una acostada si es la única. */
.pt-tiles{display:grid;grid-template-columns:1fr 1fr;gap:56px 40px}
.pt-tiles.solo{display:block}
.pt-ftile{display:flex;flex-direction:column;min-width:0}
.pt-ftile>.pt-well{flex:none}
.pt-ftile-body{flex:1;display:flex;flex-direction:column;margin-top:24px;min-width:0}
.pt-ftile.solo{display:grid;grid-template-columns:1fr 1fr;column-gap:48px;align-items:start}
.pt-ftile.solo>.pt-well{height:300px}
.pt-ftile.solo>.pt-ftile-body{margin-top:0;padding-top:4px}
.pt-ftile-state{display:flex}
${rule('.pt-feature', heading(34, spacing: 0.5), ';margin-top:12px;text-transform:uppercase;overflow:hidden;display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical')}
${rule('.pt-sub', subtitle, ';margin-top:12px;color:var(--pt-ink2)')}
.pt-facts-strip{display:flex;margin-top:16px;padding-block:11px;border-block:1px solid var(--pt-line)}
.pt-facts-strip>div{flex:1;min-width:0}
${rule('.pt-fact-v', text(15, weight: 600), ';display:block;margin-top:4px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;font-variant-numeric:tabular-nums')}
.pt-ftile-gap{display:block;height:4px}
.pt-ftile.pair .pt-ftile-gap{flex:1}
.pt-actions{display:flex;flex-wrap:wrap;gap:12px;margin-top:20px}
.pt-actions.job{align-items:center}
.pt-steps{margin-top:18px}
.pt-steps-row{display:flex;gap:3px;align-items:flex-start}
.pt-step{flex:1;min-width:0;display:flex;flex-direction:column}
.pt-step-bar{display:block;height:6px;background:var(--pt-line)}
.pt-step-bar.done{background:var(--pt-act)}
.pt-step-bar.ok{background:var(--pt-ok)}
.pt-step-bar.wait{background:var(--pt-att)}
.pt-step-bar.now{background:var(--pt-ink)}
${rule('.pt-step-name', heading(11, weight: 500, spacing: 0.8, height: 1.25), ';margin-top:8px;text-transform:uppercase;white-space:nowrap;overflow:hidden;color:var(--pt-ink2);-webkit-mask-image:linear-gradient(90deg,#000 calc(100% - 12px),transparent)')}
${rule('.pt-step-name.on', heading(11, weight: 700, spacing: 0.8, height: 1.25), ';color:var(--pt-ink)')}
.pt-steps-text{display:none;margin-top:8px}
${rule('.pt-steps-text', heading(12, weight: 500, spacing: 1.3, height: 1.25), ';text-transform:uppercase;color:var(--pt-ink2)')}
${rule('.pt-steps-text>b', heading(12, weight: 700, spacing: 1.3, height: 1.25), ';color:var(--pt-ink)')}
@container ptc (min-width:760px){.pt-tiles:not(.solo){grid-template-columns:1fr 1fr}}
@container ptc (max-width:759.98px){
.pt-tiles{grid-template-columns:1fr;row-gap:48px}
.pt-ftile.solo{display:flex}
.pt-ftile.solo>.pt-well{height:220px}
.pt-ftile.solo>.pt-ftile-body{margin-top:24px;padding-top:0}
.pt-ftile.pair .pt-ftile-gap{flex:none}
.pt-ftile .pt-draw-wide .pt-draw{width:270px!important;height:160px!important}
}
@container ptc (max-width:559.98px){
.pt-ftile>.pt-well,.pt-ftile.solo>.pt-well{height:190px}
.pt-ftile-body,.pt-ftile.solo>.pt-ftile-body{margin-top:20px}
${rule('.pt-feature', heading(28, spacing: 0.5))}
.pt-ftile .pt-draw-wide{display:none}.pt-ftile .pt-draw-compact{display:flex}
.pt-ftile .pt-steps-row .pt-step-name{display:none}
.pt-ftile .pt-steps-text{display:block}
.pt-actions{flex-direction:column;flex-wrap:nowrap;align-items:stretch;gap:0}
.pt-actions.job{gap:10px}
.pt-btn.full-compact{display:flex;width:100%}
.pt-link.wide-only{display:none}
}

/* Bicicletas. */
.pt-bike{display:flex;flex-direction:column;width:100%;color:var(--pt-ink)}
.pt-bike>.pt-well{height:250px}
${rule('.pt-bike-title', heading(24, spacing: 0.5, height: 1.1), ';margin-top:16px;text-transform:uppercase;overflow:hidden;display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical')}
${rule('.pt-bike-details', text(15), ';margin-top:6px;color:var(--pt-ink2)')}
.pt-bike-foot{display:flex;align-items:center;gap:12px;margin-top:12px;padding-block:11px 12px;border-top:1px solid var(--pt-line)}
${rule('.pt-bike-foot>span', text(14, weight: 500), ';flex:1;min-width:0')}
.pt-bike.compact>.pt-well{height:200px}
.pt-bike.compact .pt-draw-wide{display:none}.pt-bike.compact .pt-draw-compact{display:flex}
${rule('.pt-bike.compact .pt-bike-title', heading(20, spacing: 0.5, height: 1.1))}
.pt-bgrid{display:grid;grid-template-columns:repeat(3,1fr);gap:40px 32px;align-items:start}
@container ptc (max-width:859.98px){.pt-bgrid{grid-template-columns:repeat(2,1fr)}}
@container ptc (max-width:559.98px){
.pt-bgrid{grid-template-columns:1fr}
.pt-bike.grid>.pt-well{height:200px}
.pt-bike.grid .pt-draw-wide{display:none}.pt-bike.grid .pt-draw-compact{display:flex}
${rule('.pt-bike.grid .pt-bike-title', heading(20, spacing: 0.5, height: 1.1))}
}
.pt-brow-wide{display:grid;grid-template-columns:repeat(3,1fr);gap:32px}
.pt-brow-cell{min-width:0;align-self:start}
.pt-brow-one,.pt-brow-slide{display:none}
.pt-brow-slide{gap:16px;overflow-x:auto;scrollbar-width:none;margin-inline:calc(-1 * var(--pt-g));padding-inline:var(--pt-g)}
.pt-brow-slide::-webkit-scrollbar{display:none}
.pt-brow-item{flex:none;width:280px}
@container ptc (max-width:759.98px){.pt-brow-wide{display:none}.pt-brow-one{display:block}.pt-brow-slide{display:flex}}
.pt-wtile{position:relative;display:flex;align-items:flex-end;min-height:360px;overflow:hidden;background:var(--pt-ink);color:var(--pt-page)}
.pt-wtile.photo{color:#fff}
.pt-wtile-img{position:absolute;inset:0;width:100%;height:100%;object-fit:cover}
.pt-wtile-veil{position:absolute;inset:0;background:linear-gradient(0deg,rgb(10 11 11 / .859),rgb(10 11 11 / .349) 55%,rgb(10 11 11 / .051))}
.pt-wtile-in{position:relative;display:flex;flex-direction:column;align-items:flex-start;padding:28px}
.pt-wtile .pt-eyebrow{opacity:.86}
${rule('.pt-wtile-title', heading(30), ';display:block;margin-top:10px;text-transform:uppercase')}
${rule('.pt-wtile-msg', text(15), ';display:block;margin-top:10px;opacity:.88')}
.pt-wtile .pt-btn{margin-top:18px}

/* La franja de servicio al pie del resumen. */
.pt-svc{background:var(--pt-well)}
.pt-svc-in{display:flex;gap:56px;padding-block:52px}
.pt-svc-item{flex:1;min-width:0}
.pt-svc-head{display:flex;flex-direction:column;align-items:flex-start;gap:12px}
${rule('.pt-svc-title', heading(18), ';text-transform:uppercase')}
${rule('.pt-svc-msg', text(15), ';margin-top:10px;margin-bottom:4px;color:var(--pt-ink2)')}
@container pt (max-width:819.98px){
.pt-svc-in{flex-direction:column;gap:0;padding-block:12px 28px}
.pt-svc-item{padding-block:20px}
.pt-svc-item+.pt-svc-item{padding-top:19px;border-top:1px solid var(--pt-line)}
.pt-svc-head{flex-direction:row;align-items:center}
.pt-svc-head>svg{width:24px;height:24px}
${rule('.pt-svc-title', heading(16))}
}

/* La puerta del portal. */
.pt-gate{display:flex;flex-direction:column;max-width:480px;padding-block:40px}
${rule('.pt-gate-msg', text(17), ';margin-bottom:28px')}
.pt-gate .pt-btn+.pt-btn,.pt-gate .pt-btn+.pt-gate-new{margin-top:12px}
${rule('.pt-gate-new', rowMeta, ';color:var(--pt-ink2)')}
.pt-spin{display:block;width:28px;height:28px;color:var(--pt-act)}
.pt-spin svg{animation:pt-rot 1.4s linear infinite}
.pt-spin circle{stroke-dasharray:60 200;stroke-dashoffset:0;animation:pt-dash 1.4s ease-in-out infinite;transform-origin:center}
@keyframes pt-rot{to{transform:rotate(360deg)}}
@keyframes pt-dash{0%{stroke-dasharray:1 200;stroke-dashoffset:0}50%{stroke-dasharray:60 200;stroke-dashoffset:-15}100%{stroke-dasharray:60 200;stroke-dashoffset:-79}}

/* Las fichas: diálogo recto en ancho, hoja desde abajo en teléfono. */
.pt-dlg{position:fixed;inset:0;width:100%;height:100%;max-width:none;max-height:none;margin:0;padding:0;border:0;background:transparent;overflow:hidden;color:var(--pt-ink)}
.pt-dlg::backdrop{background:transparent}
.pt-dlg[open]{display:flex;align-items:center;justify-content:center}
.pt-scrim{position:absolute;inset:0;background:rgb(0 0 0 / .541);opacity:0;transition:opacity .15s ease}
.pt-panel{position:relative;display:flex;flex-direction:column;width:calc(100% - 80px);max-width:560px;min-width:280px;max-height:84vh;max-height:84dvh;margin:24px 40px;background:var(--pt-page);opacity:0;transition:opacity .15s cubic-bezier(0,0,.58,1)}
.pt-dlg.in .pt-scrim,.pt-dlg.in .pt-panel{opacity:1}
.pt-panel-bar{flex:none;display:block;height:4px;background:var(--pt-act)}
.pt-panel-head{flex:none;display:flex;align-items:flex-start;padding:20px 12px 0 24px}
.pt-panel-headings{flex:1;min-width:0;padding-top:8px}
${rule('.pt-panel-title', heading(28, spacing: 0.5), ';text-transform:uppercase')}
.pt-panel-sub{margin-top:6px}
.pt-panel-status{margin-top:14px}
.pt-sheet-tag{display:flex}
.pt-close{flex:none;display:flex;align-items:center;justify-content:center;width:40px;height:36px;color:var(--pt-ink)}
.pt-close:hover{background:color-mix(in srgb,currentColor 8%,transparent)}
.pt-panel-body{flex:1 1 auto;min-height:0;overflow-y:auto;margin-top:20px;padding:20px 24px;border-top:1px solid var(--pt-ink)}
.pt-panel-actions{flex:none;display:flex;flex-wrap:wrap;justify-content:flex-end;gap:12px;padding:16px 24px;border-top:1px solid var(--pt-line)}
.pt-steps.sheet{margin-top:16px}
@media (max-width:599.98px){
.pt-steps.sheet .pt-step-name{display:none}
.pt-steps.sheet .pt-steps-text{display:block}
.pt-dlg[open]{align-items:flex-end}
.pt-panel{width:100%;max-width:none;min-width:0;max-height:88vh;max-height:88dvh;margin:0;padding-bottom:env(safe-area-inset-bottom,0px);opacity:1;transform:translateY(100%);transition:transform .2s cubic-bezier(0,0,.2,1)}
.pt-dlg.in .pt-panel{transform:none;transition-duration:.25s}
.pt-scrim{transition-duration:.2s}
.pt-dlg.in .pt-scrim{transition-duration:.25s}
}
.pt-facts{display:flex;flex-direction:column}
.pt-facts>div+div{margin-top:12px;padding-top:12px;border-top:1px solid var(--pt-line)}
${rule('.pt-fact', text(16, weight: 500, height: 1.4), ';margin-top:4px')}
.pt-files{margin-top:24px}
${rule('.pt-files-title', _TextStyle(head, 14, 1.43, 500, 0.1, heading: true))}
.pt-files-grid{display:flex;flex-wrap:wrap;gap:10px;margin-top:12px}
.pt-file{display:flex;align-items:center;justify-content:center;width:96px;height:96px;overflow:hidden;border-radius:8px;background:var(--pt-hi)}
.pt-file img{width:100%;height:100%;object-fit:cover}
.pt-files-error{margin-top:12px;color:var(--pt-bad)}
.pt-dlg-lock{overflow:hidden}
''';
}

/// The family a theme names, as `var(--head)`/`var(--body)` spell it.
String _family(String font) => font.trim();

/// One Flutter text style, as CSS.
class _TextStyle {
  const _TextStyle(
    this.family,
    this.size,
    this.height,
    this.weight,
    this.spacing, {
    required this.heading,
  });

  final String family;
  final double size;
  final double height;
  final int weight;
  final double spacing;

  /// The heading font ships only its regular file.
  final bool heading;

  int get line => (size * height).round();

  /// Skia's fake-bold stroke width for [size].
  double get _embolden {
    final ratio = size <= 9
        ? 1 / 24
        : size >= 36
        ? 1 / 32
        : 1 / 24 + (size - 9) / 27 * (1 / 32 - 1 / 24);
    return double.parse((size * ratio).toStringAsFixed(3));
  }

  String get font {
    final drawnWeight = heading ? 400 : weight;
    final stroke = heading && weight >= 600
        ? ';-webkit-text-stroke:${cssPx(_embolden)} currentColor'
        : ';-webkit-text-stroke:0';
    return 'font:$drawnWeight ${cssPx(size)}/${line}px '
        'var(--${heading ? 'head' : 'body'});'
        'letter-spacing:${cssPx(spacing)}$stroke';
  }
}

/// `PortalStyle`'s colors from the editor theme's roles
/// (`PublicStoreSurfaceTheme`).
class _PortalColors {
  _PortalColors(WebsiteThemeRoles roles)
    : page = roles.background,
      well = roles.surfaceContainer,
      line = roles.outlineVariant,
      ink = WebsiteRgba.alphaBlend(roles.onSurface, roles.background),
      ink2 = WebsiteRgba.alphaBlend(roles.onSurfaceVariant, roles.background),
      action = roles.primary,
      onAction = roles.onPrimary,
      attention = roles.accent,
      onAttention = roles.onAccent,
      highest = WebsiteRgba.lerp(roles.background, roles.onSurface, 0.13),
      success = _ensureContrast(_successGreen, roles.background),
      danger = _error,
      onDanger = WebsiteRgba.white;

  final WebsiteRgba page;
  final WebsiteRgba well;
  final WebsiteRgba line;
  final WebsiteRgba ink;
  final WebsiteRgba ink2;
  final WebsiteRgba action;
  final WebsiteRgba onAction;
  final WebsiteRgba attention;
  final WebsiteRgba onAttention;
  final WebsiteRgba highest;
  final WebsiteRgba success;
  final WebsiteRgba danger;
  final WebsiteRgba onDanger;

  WebsiteRgba get onSuccess => WebsiteRgba.readableOn(success);

  /// `PublicStoreTheme.successGreen` and `.error`.
  static final _successGreen = WebsiteRgba.fromArgb(0xFF10B981);
  static final _error = WebsiteRgba.fromArgb(0xFFEF4444);

  /// `PublicStoreSurfaceTheme._ensureContrast` at 4.5.
  static WebsiteRgba _ensureContrast(WebsiteRgba color, WebsiteRgba ground) {
    if (WebsiteRgba.contrast(color, ground) >= 4.5) return color;
    final target = WebsiteRgba.readableOn(ground);
    for (var step = 1; step <= 20; step++) {
      final candidate = WebsiteRgba.lerp(color, target, step / 20);
      if (WebsiteRgba.contrast(candidate, ground) >= 4.5) return candidate;
    }
    return target;
  }
}
