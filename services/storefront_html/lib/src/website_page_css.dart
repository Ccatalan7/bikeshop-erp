import 'package:vinabike_public_core/modules/website/theme/website_theme_roles.dart';

import 'block_composition.dart';
import 'policy_page_model.dart';

/// A Flutter text box: each line is the font size times the height, rounded
/// to a whole pixel (SkParagraph's rounding), so a page of paragraphs lands
/// on the same pixels.
String _lh(double fontSize, double height) =>
    '${(fontSize * height).round()}px';

String _n(double value) => value == value.roundToDouble()
    ? '${value.round()}'
    : value.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');

/// The theme's colors and sizes for an editor page (`WebsiteThemeRoles`,
/// the roles `WebsiteThemeBuilder` derives), and the page's rules.
String policyPageCss(WebsiteThemeRoles theme) {
  final heroSize = theme.headingSize;
  final heroPhone = heroSize * 0.8;
  final body = theme.bodySize;
  final (buttonHeight, buttonPadding) = switch (theme.buttonSize) {
    // The theme's minimum and padding less 4 (`VisualDensity(-1, -1)`).
    'small' => (32, 14),
    'large' => (48, 28),
    _ => (40, 20),
  };
  final buttonRadius = switch (theme.buttonStyle) {
    'sharp' => '0',
    'pill' => '999px',
    _ => '8px',
  };
  return '''
:root{--w-bg:${theme.background.css};--w-on:${theme.onSurface.css};--w-onv:${theme.onSurfaceVariant.css};--w-low:${theme.surfaceContainerLow.css};--w-ovar:${theme.outlineVariant.css};--w-prim:${theme.primary.css};--w-prim10:${theme.primary.withAlpha(0.1).css};--w-accent:${theme.accent.css};--w-cp:${_n(theme.containerPadding)}px;--w-btn-h:${buttonHeight}px;--w-btn-px:${buttonPadding}px;--w-btn-r:$buttonRadius}
.pol-page{background:var(--w-bg)}
.pol{max-width:1120px;margin:0 auto;padding:64px 24px}
.pol-icon{display:grid;place-items:center;width:48px;height:48px;border-radius:12px;background:var(--w-prim10);color:var(--w-prim)}
.pol-side h1{margin:24px 0 0;font:800 32px/${_lh(32, 1.1)} var(--body);letter-spacing:-.5px;color:var(--w-on)}
.pol-sum{margin:12px 0 0;font:400 16px/24px var(--body);letter-spacing:.25px;color:var(--w-onv)}
.pol-nav{margin-top:32px}
.pol-nav ul{display:flex;gap:8px;list-style:none;margin:0;padding:0;overflow-x:auto;scrollbar-width:none}
.pol-nav ul::-webkit-scrollbar{display:none}
.pol-nav li{display:flex;align-items:center;flex:none;min-height:48px}
.pol-nav a{display:inline-flex;align-items:center;gap:9.5px;height:35px;padding:0 22px 0 14px;letter-spacing:.1px;border:1px solid var(--w-ovar);border-radius:24px;background:var(--w-bg);color:var(--w-onv);font:500 14px/20px var(--body);text-decoration:none;white-space:nowrap}
.pol-nav a svg{width:16px;height:16px;flex:none}
.pol-nav a[aria-current]{border-color:transparent;background:var(--w-low);color:var(--w-on);font-weight:700}
.pol-main{margin-top:32px}
@media (min-width:816px){
.pol{display:grid;grid-template-columns:240px minmax(0,1fr);column-gap:64px;align-items:start}
.pol-main{margin-top:0}
.pol-nav ul{flex-direction:column;gap:0;overflow:visible}
.pol-nav li{display:block;min-height:0;padding-bottom:8px}
.pol-nav a{display:flex;gap:12px;height:auto;min-height:48px;padding:12px 16px;border:0;border-radius:8px;background:transparent;font:500 15px/${_lh(15, 1.5)} var(--body);letter-spacing:.25px;white-space:normal;transition:background-color .15s}
.pol-nav a svg{width:18px;height:18px}
.pol-nav a:hover,.pol-nav a[aria-current]{background:var(--w-low)}
}
.pol-missing{max-width:720px;margin:0 auto;padding:72px 24px;text-align:center;color:var(--w-onv)}
.pol-missing h1{margin:20px 0 0;font:800 30px/${_lh(30, 1.15)} var(--body);color:var(--w-on)}
.pol-missing p{margin:12px 0 28px;font:400 16px/24px var(--body);letter-spacing:.25px}

/* PageComposition: one column, each block centered and as wide as its
   content (a widget that expands takes the whole width), the theme's side
   padding unless full-bleed, and the space after it. */
.blocks{display:flex;flex-direction:column;align-items:center}
.blk{max-width:100%;width:fit-content;padding-inline:var(--w-cp);margin-bottom:var(--gap,0px)}
.blk.fill{width:100%;container-type:inline-size}
.blk.bleed{padding-inline:0}

/* _PolicyContent: a block read as a title, paragraphs and item cards. The
   column is at most 720 wide, so Flutter's Wrap never puts two cards in a
   row. A text whose style names no letter spacing inherits Material 3's
   (bodyMedium .25, bodyLarge and labelMedium .5, titleMedium .15, chips .1):
   without it a paragraph breaks into fewer lines than Flutter's. */
.psec h2{margin:0 0 16px;font:800 24px/${_lh(24, 1.5)} var(--body);letter-spacing:-.3px;color:var(--w-on)}
.psec p{margin:0 0 16px;font:400 16px/${_lh(16, 1.65)} var(--body);letter-spacing:.25px;color:var(--w-onv)}
.psec-items{display:flex;flex-direction:column;gap:16px;padding-top:8px}
.pitem{width:500px;max-width:100%;padding:20px;border-radius:12px;background:var(--w-low)}
.pitem h3{margin:0;font:800 16px/${_lh(16, 1.5)} var(--body);letter-spacing:.25px;color:var(--w-on)}
.pitem h3+p{margin-top:8px}
.pitem p{margin:0;font:400 15px/${_lh(15, 1.5)} var(--body);letter-spacing:.25px;color:var(--w-onv)}

/* Hero (website_hero_block_content.dart). Oswald bold is the 400 outline
   emboldened, as Flutter draws it. */
.hero-blk{position:relative;overflow:hidden;height:100%;background:#1a1a1a}
.hero-blk.auto{height:520px}.hero-blk.screen{height:100vh}
.hero-fallback{position:absolute;inset:0;background:linear-gradient(to bottom right,#1a1a1a,${WebsiteRgba.lerp(WebsiteRgba.fromArgb(0xFF1A1A1A), const WebsiteRgba(1, 0, 0, 0), 0.2).css})}
.hero-img{position:absolute;inset:0;width:100%;height:100%;object-fit:cover}
.hero-ov{position:absolute;inset:0;pointer-events:none}
.hero-in{position:absolute;inset:0;display:flex;flex-direction:column;align-items:center;justify-content:center;padding:0 24px;text-align:center}
.hero-in[data-align=start]{align-items:flex-start;text-align:left}
.hero-in[data-align=end]{align-items:flex-end;text-align:right}
.hero-t{margin:0;max-width:100%;font:400 ${_n(heroSize)}px/${_lh(heroSize, 1.12)} var(--head);letter-spacing:3px;color:#fff;-webkit-text-stroke:.032em currentColor;overflow-wrap:anywhere}
.hero-s{margin:20px 0 0;font:600 ${_n(body)}px/${_lh(body, 1.33)} var(--body);color:rgb(255 255 255 / .702)}
.hero-in .w-btn{margin-top:40px}
@container (max-width:599.98px){
.hero-blk.auto{height:420px}
.hero-t{font-size:${_n(heroPhone)}px;line-height:${_lh(heroPhone, 1.12)}}
}

/* WebsiteActionButton with the theme's button size and shape. Flutter draws
   the outline inside the padding; here the border takes 1 px of it. */
.w-btn{display:inline-flex;align-items:center;justify-content:center;min-width:64px;min-height:var(--w-btn-h);padding:0 calc(var(--w-btn-px) - 1px);border:1px solid transparent;border-radius:var(--w-btn-r);font:600 14px/20px var(--body);letter-spacing:1.5px;text-decoration:none;white-space:nowrap;transition:background-color .2s}
.w-btn.on-dark{color:#fff}
.w-btn.on-dark.outline{border-color:#fff}
.w-btn.on-dark.outline:hover,.w-btn.on-dark.text:hover{background:rgb(255 255 255 / .08)}
.w-btn.on-dark.filled{background:var(--w-accent);border-color:var(--w-accent)}
.w-btn.plain{border-color:var(--w-ovar);color:var(--w-prim);letter-spacing:0}

/* Contact (website_contact_block_content.dart): laid out by the width the
   block has, as its LayoutBuilder (1088 and 552). */
.contact-blk{padding:64px 24px}
/* 16 on a phone: a canvas under 640, which is the block less its padding. */
@container (max-width:${_n(640 - 2 * theme.containerPadding - 0.02)}px){.contact-blk{padding-inline:16px}}
.contact-in{max-width:1100px;margin:0 auto;container-type:inline-size}
.contact-t{margin:0;text-align:center;font:400 26px/${_lh(26, 1.12)} var(--head);color:var(--w-on);-webkit-text-stroke:.032em currentColor}
.contact-s{margin:12px 0 0;text-align:center;font:400 17px/${_lh(17, 1.45)} var(--body);letter-spacing:.5px;color:var(--w-onv)}
.contact-cards{display:flex;flex-direction:column;gap:24px;margin-top:36px}
.contact-cards[data-count="1"]{align-items:center}
.contact-cards[data-count="1"]>*{width:min(520px,100%)}
@container (min-width:552px){
.contact-t{font-size:34px;line-height:${_lh(34, 1.12)}}
.contact-cards[data-count="2"],.contact-cards[data-count="3"]{display:grid;grid-template-columns:1fr 1fr;align-items:start}
.contact-cards[data-count="3"]>:last-child{grid-column:1/-1}
}
@container (min-width:1088px){
.contact-t{font-size:40px;line-height:${_lh(40, 1.12)}}
.contact-cards[data-count="2"],.contact-cards[data-count="3"]{display:flex;flex-direction:row;justify-content:center;align-items:flex-start}
.contact-cards:not([data-count="1"])>.info{width:320px}
.contact-cards:not([data-count="1"])>.form,.contact-cards:not([data-count="1"])>.map{width:360px}
}
.c-card{padding:24px;border-radius:20px;background:var(--w-low);box-shadow:0 1px 2px rgb(0 0 0 / .18),0 2px 6px rgb(0 0 0 / .1)}
.c-card h3{margin:0 0 16px;font:400 16px/24px var(--head);letter-spacing:.15px;color:var(--w-on);-webkit-text-stroke:.032em currentColor}
.c-detail{display:flex;align-items:flex-start;gap:12px;padding-bottom:12px}
.c-detail svg{flex:none;color:var(--w-prim)}
.c-label{margin:0;font:700 12px/16px var(--body);letter-spacing:.5px;color:var(--w-on)}
.c-value{margin:2px 0 0;font:400 ${_n(body)}px/${_lh(body, 1.5)} var(--body);letter-spacing:.25px;color:var(--w-on);overflow-wrap:anywhere}
.c-value a{color:inherit;text-decoration:none}.c-value a:hover{text-decoration:underline}
.c-field{display:block;margin-bottom:12px}
.c-field span{display:block;margin-bottom:4px;font:400 12px/16px var(--body);color:var(--w-onv)}
.c-field input,.c-field textarea{width:100%;padding:12px;border:1px solid var(--w-ovar);border-radius:4px;background:transparent;font:inherit;resize:none}
.c-send{width:100%;margin-top:8px;padding:10px;border:0;border-radius:8px;background:var(--w-ovar);color:var(--w-onv);font:600 14px/20px var(--body)}
.c-map{display:grid;place-items:center;height:200px;border-radius:16px;background:var(--w-ovar);color:var(--w-onv)}
.c-map-link{display:inline-flex;align-items:center;gap:8px;margin-top:16px;padding:10px 12px;color:var(--w-accent);font:600 14px/20px var(--body);text-decoration:none}
${bandVisibilityCss(policyBands)}
''';
}
