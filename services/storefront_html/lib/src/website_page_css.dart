import 'package:vinabike_public_core/modules/website/theme/website_theme_roles.dart';

import 'block_composition.dart';
import 'home_page_model.dart';
import 'website_brand_logos_view.dart';
import 'website_reviews_view.dart';
import 'website_video_banner_view.dart';
import 'policy_page_model.dart';

/// A Flutter text box: each line is the font size times the height, rounded
/// to a whole pixel (SkParagraph's rounding), so a page of paragraphs lands
/// on the same pixels.
String _lh(double fontSize, double height) =>
    '${(fontSize * height).round()}px';

String _n(double value) => value == value.roundToDouble()
    ? '${value.round()}'
    : value.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');

/// The editor theme as CSS variables (`WebsiteThemeRoles`, the roles
/// `WebsiteThemeBuilder` derives) and the rules every editor block shares
/// (composition, hero, buttons, contact), for any page that draws blocks.
String websiteBlocksCss(WebsiteThemeRoles theme) {
  final heroSize = theme.headingSize;
  final heroPhone = heroSize * 0.8;
  final body = theme.bodySize;
  final heading = theme.headingSize;
  final caption = body * 0.9;
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
:root{--w-bg:${theme.background.css};--w-on:${theme.onSurface.css};--w-onv:${theme.onSurfaceVariant.css};--w-low:${theme.surfaceContainerLow.css};--w-cont:${theme.surfaceContainer.css};--w-onacc:${theme.onAccent.css};--w-ovar:${theme.outlineVariant.css};--w-prim:${theme.primary.css};--w-prim10:${theme.primary.withAlpha(0.1).css};--w-accent:${theme.accent.css};--w-cp:${_n(theme.containerPadding)}px;--w-btn-h:${buttonHeight}px;--w-btn-px:${buttonPadding}px;--w-btn-r:$buttonRadius}
/* PageComposition: one column, each block centered and as wide as its
   content (a widget that expands takes the whole width), the theme's side
   padding unless full-bleed, and the space after it. */
.blocks{display:flex;flex-direction:column;align-items:center}
.blk{max-width:100%;width:fit-content;padding-inline:var(--w-cp);margin-bottom:var(--gap,0px)}
.blk.fill{width:100%;container-type:inline-size}
.blk.bleed{padding-inline:0}
.blk.minh{display:flex;flex-direction:column}.blk.minh>*{flex:1 0 auto}

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

/* Text (WebsiteTextBlockContent): the theme's styles for each preset, with
   Material 3's letter spacing, in a column at most maxWidth wide. Its line
   breaks and spaces are kept, as Flutter's Text keeps them; an empty text
   is still a line, as in Flutter, and so is a last line break. The weight
   of the heading and subheading is written on each, by its font. */
/* A Flutter Text (flutterText): its own spaces and breaks; an empty one is
   a line, and so is a last break. */
.ft{white-space:pre-wrap;overflow-wrap:break-word}
.ft:empty::before,.ft[data-break]::after{content:"\\200b"}
.txt{margin:0 auto;color:var(--w-on)}
.txt.heading{font:400 ${_n(heading)}px/${_lh(heading, 36 / 28)} var(--head)}
.txt.subheading{font:400 18px/${_lh(18, 28 / 22)} var(--head)}
.txt.paragraph{font:400 ${_n(body)}px/${_lh(body, 1.5)} var(--body);letter-spacing:.5px}
.txt.caption{font:400 ${_n(caption)}px/${_lh(caption, 1.5)} var(--body);letter-spacing:.4px}

/* Button block: the theme's button across the block, its label in the body
   font at the body size (labelLarge's height and spacing); HoverScale
   grows it 3 % under the pointer and presses it to 98 %. */
.w-btn.b-blk{display:flex;width:100%;font-size:${_n(body)}px;line-height:${_lh(body, 20 / 14)};letter-spacing:.1px;white-space:normal;text-align:center;transition:background-color .2s,box-shadow .2s,transform .14s cubic-bezier(.215,.61,.355,1)}
/* ElevatedButton: elevation 1 at rest and 3 under the pointer, measured
   against Flutter's shadow. */
.w-btn.b-blk.filled{background:var(--w-accent);border-color:var(--w-accent);color:#fff;box-shadow:0 .7px 1px rgb(0 0 0 / .18),0 0 1px rgb(0 0 0 / .04)}
.w-btn.b-blk.filled:hover{box-shadow:0 2px 3px rgb(0 0 0 / .18),0 1px 5px rgb(0 0 0 / .08)}
.w-btn.b-blk.outline{border-color:var(--w-accent);color:var(--w-accent)}
.w-btn.b-blk.text{color:var(--w-accent)}
.w-btn.b-blk.filled:hover{background:color-mix(in srgb,#fff 8%,var(--w-accent))}
.w-btn.b-blk.outline:hover,.w-btn.b-blk.text:hover{background:color-mix(in srgb,var(--w-accent) 8%,transparent)}
.w-btn.b-blk:hover{transform:scale(1.03)}
.w-btn.b-blk:active{transform:scale(.98)}

/* Divider: a centered line. */
.dv{margin:0 auto}

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
''';
}

/// An information page: [websiteBlocksCss], its frame and its sections.
String policyPageCss(WebsiteThemeRoles theme) =>
    '''
${websiteBlocksCss(theme)}
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

${bandVisibilityCss(policyBands)}
''';

/// The home: [websiteBlocksCss] and the blocks only the home has so far.
String homePageCss(WebsiteThemeRoles theme) =>
    '''
${websiteBlocksCss(theme)}
${carouselCss(theme)}
$productsBlockCss
${categoryGridCss(theme)}
$brandLogosCss
$videoBannerCss
$googleReviewsCss
${contentBlocksCss(theme)}
${bandVisibilityCss(homeBands)}
''';

/// The content blocks (website_content_blocks_view.dart): FAQ, call to
/// action, features and «about us». Their titles change size by the width
/// of their column, as their LayoutBuilders read it.
String contentBlocksCss(WebsiteThemeRoles theme) {
  final body = theme.bodySize;
  final cta = body + 2;
  // A phone is a canvas under 640 (the block less the theme's side
  // padding): the side padding of these blocks is 16 there, 24 otherwise.
  final phone = _n(640 - 2 * theme.containerPadding - 0.02);
  final dark = WebsiteRgba.lerp(
    theme.primary,
    const WebsiteRgba(1, 0, 0, 0),
    0.2,
  );
  final highest = WebsiteRgba.lerp(theme.background, theme.onSurface, 0.13);
  return '''
/* FAQ: ExpansionTile cards (Card radius 16, the theme's low container).
   A Material 3 card at elevation 1 with the theme's 14 % shadow, as
   measured against Flutter's. */
:root{--card-shadow:0 2px 3.5px -1px rgb(0 0 0 / .05),0 0 1px rgb(0 0 0 / .01)}
.faq-blk,.ft-blk,.ab-blk{padding:64px 24px}
@container (max-width:${phone}px){.faq-blk,.ft-blk,.ab-blk{padding-inline:16px}}
.faq-in{max-width:900px;margin:0 auto;container-type:inline-size}
.faq-t,.ft-t{margin:0;text-align:center;font:400 26px/${_lh(26, 1.15)} var(--head);letter-spacing:.25px;color:var(--w-on)}
@container (min-width:600px){.faq-t{font-size:34px;line-height:${_lh(34, 1.15)}}}
@container (min-width:900px){.faq-t{font-size:40px;line-height:${_lh(40, 1.15)}}}
.faq-s{margin:12px 0 0;text-align:center;font:400 17px/${_lh(17, 1.45)} var(--body);letter-spacing:.25px;color:var(--w-onv)}
.faq-list{margin-top:32px}
.faq-it{margin-bottom:16px;border-radius:16px;background:var(--w-low);box-shadow:var(--card-shadow);overflow:hidden}
.faq-q{display:flex;align-items:center;gap:16px;min-height:54px;padding:0 24px 0 16px;list-style:none;cursor:pointer;transition:background-color .15s}
.faq-q::-webkit-details-marker{display:none}
/* ListTile's hover is the theme's hoverColor: black at 4 %. */
.faq-q:hover{background:rgb(0 0 0 / .04)}
.faq-q:focus-visible{outline:2px solid var(--w-prim);outline-offset:-2px}
/* The question row as measured: at least 54 tall, 9 above and below a
   question of several lines. */
.faq-qt{flex:1;min-width:0;font:400 16px/24px var(--head);letter-spacing:.15px;color:var(--w-on);padding-block:9px}
.faq-chev{flex:none;color:var(--w-prim);transition:transform .2s}
.faq-it[open] .faq-chev{transform:rotate(180deg)}
.faq-a{padding:12px 16px}
.faq-at{margin:0;font:400 ${_n(body)}px/${_lh(body, 1.5)} var(--body);letter-spacing:.25px;color:var(--w-onv)}
.faq-it::details-content{block-size:0;overflow:hidden;transition:block-size .2s,content-visibility .2s allow-discrete}
.faq-it[open]::details-content{block-size:auto}
@supports (interpolate-size:allow-keywords){:root{interpolate-size:allow-keywords}}

/* Call to action: the photo with its veil, or the primary color running to
   20 % black along the diagonal (Flutter's top-left to bottom-right; the
   page script sets the angle by the block's shape). Its content is never
   clipped: a height smaller than it runs past the bottom, as Flutter's
   Stack. */
.cta-blk{position:relative;display:flex;flex-direction:column;justify-content:safe center;padding:56px 24px;background:linear-gradient(var(--diag,to bottom right),${theme.primary.css},${dark.css})}
.cta-blk.fixed{padding-block:0}
@container (max-width:${phone}px){.cta-blk{padding-inline:16px}}
.cta-img{position:absolute;inset:0;width:100%;height:100%;object-fit:cover}
.cta-ov{position:absolute;inset:0;pointer-events:none}
.cta-in{position:relative;display:flex;flex-direction:column;align-items:center;max-width:800px;width:100%;margin:0 auto}
.cta-t{margin:0;max-width:100%;text-align:center;font:400 24px/36px var(--head);letter-spacing:1px;color:#fff}
.cta-s{margin:12px 0 0;max-width:100%;text-align:center;font:400 ${_n(cta)}px/${_lh(cta, 1.5)} var(--body);letter-spacing:.5px;color:rgb(255 255 255 / .702)}
.cta-btn{margin-top:24px;min-height:44px;max-width:100%;letter-spacing:1px;white-space:normal;overflow-wrap:anywhere;text-align:center;font-family:var(--body)}
.cta-btn.outline{border-color:#fff;color:#fff}
.cta-btn.text{color:#fff}
.cta-btn.filled{background:var(--w-accent);border-color:var(--w-accent);color:#fff;box-shadow:0 .7px 1px rgb(0 0 0 / .18),0 0 1px rgb(0 0 0 / .04);transition:background-color .2s,box-shadow .2s}
.cta-btn.filled:hover{background:color-mix(in srgb,#fff 8%,var(--w-accent));box-shadow:0 2px 3px rgb(0 0 0 / .18),0 1px 5px rgb(0 0 0 / .08)}
.cta-btn.outline:hover,.cta-btn.text:hover{background:rgb(255 255 255 / .08)}
.cta-btn.off{border-color:rgb(255 255 255 / .12);background:transparent;color:rgb(255 255 255 / .38);cursor:default}

/* Features: cards of 320 in a centered wrap (the whole column on a phone),
   or a list with the icon in a circle of the primary at 10 %. */
.ft-in{max-width:1100px;margin:0 auto;container-type:inline-size}
@container (min-width:600px){.ft-t{font-size:34px;line-height:${_lh(34, 1.15)}}}
@container (min-width:1100px){.ft-t{font-size:40px;line-height:${_lh(40, 1.15)}}}
.ft-grid{display:flex;flex-wrap:wrap;justify-content:center;align-items:flex-start;gap:24px;margin-top:48px}
.ft-card{box-sizing:border-box;width:100%;display:flex;flex-direction:column;align-items:center;padding:24px;border-radius:12px;background:var(--w-low);box-shadow:var(--card-shadow);text-align:center}
@container (min-width:600px){.ft-card{width:320px}}
.ft-ic{color:var(--w-prim)}
.ft-ct{margin:16px 0 0;font:400 18px/${_lh(18, 28 / 22)} var(--head);color:var(--w-on)}
.ft-cd{margin:8px 0 0;font:400 ${_n(body)}px/${_lh(body, 1.5)} var(--body);letter-spacing:.25px;color:var(--w-onv)}
.ft-list{display:flex;flex-direction:column;gap:32px;margin-top:48px}
.ft-row{display:flex;align-items:flex-start;gap:20px}
.ft-dot{flex:none;display:grid;place-items:center;width:52px;height:52px;border-radius:50%;background:var(--w-prim10);color:var(--w-prim)}
.ft-rtx{flex:1;min-width:0}
.ft-rt{margin:0;font:400 18px/27px var(--head);letter-spacing:.25px;color:var(--w-on)}
.ft-rd{margin:8px 0 0;font:400 15px/${_lh(15, 1.5)} var(--body);letter-spacing:.25px;color:var(--w-onv)}

/* About: the text beside the photo (4:3) from a block of 900, the photo
   above it (16:9, 3:2 on a phone) below that, a column of 700 without one. */
.ab-in{max-width:1200px;margin:0 auto}
.ab-blk:not([data-media]) .ab-tx{width:fit-content;max-width:700px;margin:0 auto}
.ab-tx{display:flex;flex-direction:column;align-items:flex-start}
.ab-t{margin:0;font:400 26px/${_lh(26, 1.15)} var(--head);letter-spacing:.25px;color:var(--w-on)}
.ab-c{margin:24px 0 0;font:400 16px/${_lh(16, 1.6)} var(--body);letter-spacing:.25px;color:var(--w-onv)}
.ab-media{aspect-ratio:3/2;border-radius:16px;overflow:hidden;background:${highest.css}}
.ab-media img{display:block;width:100%;height:100%;object-fit:cover}
.ab-blk[data-media] .ab-in{display:flex;flex-direction:column;gap:24px}
@container (min-width:600px){
.ab-t{font-size:34px;line-height:${_lh(34, 1.15)}}
.ab-c{font-size:16.5px;line-height:${_lh(16.5, 1.6)}}
.ab-media{aspect-ratio:16/9}
.ab-blk[data-media] .ab-in{gap:32px}
}
@container (min-width:900px){
.ab-t{font-size:40px;line-height:${_lh(40, 1.15)}}
.ab-c{font-size:17px;line-height:${_lh(17, 1.6)}}
.ab-media{aspect-ratio:4/3}
.ab-blk[data-media] .ab-in{display:grid;grid-template-columns:1fr 1fr;align-items:center;gap:48px}
.ab-blk[data-media=right] .ab-media{order:2}
}
''';
}

/// An editor page without blocks (`DynamicWebsitePage._buildEmptyState`).
String editorPageEmptyCss(WebsiteThemeRoles theme) {
  final heading = theme.headingSize * 0.5;
  final body = theme.bodySize;
  return '''
.pg-empty{display:flex;flex-direction:column;align-items:center;justify-content:center;padding:${_n(theme.containerPadding)}px;text-align:center}
.pg-empty svg{color:${theme.onSurface.withAlpha(theme.onSurface.a * .3).css}}
.pg-empty-t{margin:16px 0 0;font:400 ${_n(heading)}px/${_lh(heading, 1.5)} var(--head);letter-spacing:.25px;color:${theme.onSurface.withAlpha(theme.onSurface.a * .6).css}}
.pg-empty-s{margin:8px 0 0;font:400 ${_n(body)}px/${_lh(body, 1.5)} var(--body);letter-spacing:.25px;color:${theme.onSurface.withAlpha(theme.onSurface.a * .4).css}}
''';
}

/// Carousel (`WebsiteCarouselBlockContent`) and the layers of a composed
/// slide (`CanvasBlock`).
String carouselCss(WebsiteThemeRoles theme) {
  final title = theme.headingSize;
  final subtitle = theme.bodySize * 1.2;
  // Curves.easeOutCubic. The slide coming in and the one going out share it:
  // Flutter's switcher plays the outgoing one in reverse with the switch-out
  // curve, which over time is this same curve.
  const ease = 'cubic-bezier(.215,.61,.355,1)';
  return '''
/* Every slide stacked; the current one on top. A fade cross-fades, a slide
   comes in from 15 % to the right, a zoom from 95 %. */
.car{position:relative;height:100%;overflow:hidden;container:car/inline-size}
.car.auto{height:520px}
.car-slide{position:absolute;inset:0;overflow:hidden;visibility:hidden;transition:opacity var(--car-dur) $ease,translate var(--car-dur) $ease,scale var(--car-dur) $ease,visibility 0s var(--car-dur)}
.car-slide.on{z-index:1;visibility:visible;transition:opacity var(--car-dur) $ease,translate var(--car-dur) $ease,scale var(--car-dur) $ease}
[data-anim=fade]>.car-slide:not(.on){opacity:0}
[data-anim=slide]>.car-slide:not(.on){translate:15% 0}
[data-anim=zoom]>.car-slide:not(.on){scale:.95}
.car-img{position:absolute;inset:0;width:100%;height:100%;object-fit:cover}
.car-ov{position:absolute;inset:0;pointer-events:none}
.car-in{position:absolute;inset:0;display:flex;align-items:center;justify-content:center;padding:0 32px}
.car-col{display:flex;flex-direction:column;align-items:center;max-width:min(900px,100%);text-align:center}
.car-t{margin:0;max-width:100%;font:400 ${_n(title)}px/${_lh(title, 1.12)} var(--head);letter-spacing:3px;color:#fff;-webkit-text-stroke:.032em currentColor;overflow-wrap:break-word}
.car-s{margin:20px 0 0;max-width:100%;font:600 ${_n(subtitle)}px/${_lh(subtitle, 32 / 24)} var(--body);color:rgb(255 255 255 / .702)}
.car-col .w-btn{margin-top:40px;font-size:13px}

/* Arrows at the sides and dots 32 px from the bottom; on a phone one row 16
   px from the bottom. An arrow is a 28 px glyph in 8 px of padding and a
   1 px ring (6 and 24 on a phone); a dot is a 12 px circle in a 28 px
   target. */
.car-nav{position:absolute;inset:0;z-index:2;pointer-events:none}
.car-nav>*{pointer-events:auto}
.car-arrow{position:absolute;top:50%;margin-top:-23px;display:grid;place-items:center;width:46px;height:46px;padding:0;border:1px solid rgb(255 255 255 / .4);border-radius:50%;background:rgb(0 0 0 / .451);color:#fff;cursor:pointer}
.car-arrow svg{width:28px;height:28px}
.car-arrow.prev{left:24px}.car-arrow.next{right:24px}
.car-arrow:focus-visible,.car-dot:focus-visible{outline:2px solid #fff;outline-offset:2px}
.car-dots{position:absolute;left:0;right:0;bottom:32px;display:flex;justify-content:center;pointer-events:none}
.car-dot{display:grid;place-items:center;width:28px;height:28px;padding:0;border:0;background:none;cursor:pointer;pointer-events:auto}
.car-dot span{width:12px;height:12px;border-radius:50%;background:rgb(255 255 255 / .4);transition:background-color .25s}
.car-dot[aria-pressed=true] span{background:#fff}
@container car (max-width:639.98px){
.ph640 .car-nav{inset:auto 0 16px;display:flex;justify-content:center;align-items:center}
.ph640 .car-arrow{position:static;margin:0;width:38px;height:38px}
.ph640 .car-arrow svg{width:24px;height:24px}
.ph640 .car-arrow.prev{margin-right:12px}.ph640 .car-arrow.next{margin-left:12px}
.ph640 .car-dots{position:static}
}
@container car (max-width:599.98px){
.ph600 .car-nav{inset:auto 0 16px;display:flex;justify-content:center;align-items:center}
.ph600 .car-arrow{position:static;margin:0;width:38px;height:38px}
.ph600 .car-arrow svg{width:24px;height:24px}
.ph600 .car-arrow.prev{margin-right:12px}.ph600 .car-arrow.next{margin-left:12px}
.ph600 .car-dots{position:static}
}

/* Canvas layers: placed in the design width (--dw), scaled down to the
   canvas and never up (--s, px per design unit), centered when the canvas
   is wider (--ox). Text keeps its size, as in Flutter. */
.cnv{position:absolute;inset:0;container:cnv/inline-size;overflow:hidden}
.cnv-set{display:none;position:absolute;inset:0;--s:min(100cqw / var(--dw),1px);--ox:max(0px,(100cqw - var(--dw) * var(--s)) / 2)}
@container cnv (max-width:599.98px){.cnv-set[data-vp~=mobile]{display:block}}
@container cnv (min-width:600px) and (max-width:899.98px){.cnv-set[data-vp~=tablet]{display:block}}
@container cnv (min-width:900px){.cnv-set[data-vp~=desktop]{display:block}}
.cl{position:absolute;left:calc(var(--x) * var(--s) + var(--ox));top:calc(var(--y) * var(--s));width:calc(var(--w) * var(--s));height:calc(var(--h) * var(--s));margin:0}
.cl-text{display:flex;align-items:safe center}
.cl-text.al-center{justify-content:center}.cl-text.al-right{justify-content:flex-end}
.cl-text p{margin:0;max-width:100%;overflow-wrap:break-word}
.cl-img{display:block;overflow:hidden}
.cl-img.empty{background:rgb(0 0 0 / .04)}
.cl-btn{display:flex;align-items:center;justify-content:center;border:1px solid transparent;font-family:var(--body);font-weight:600;line-height:1.2;text-decoration:none;white-space:nowrap;overflow:hidden}
.cl-btn:hover{box-shadow:inset 0 0 0 999px rgb(255 255 255 / .08)}
@keyframes cl-fade{from{opacity:0}}
@keyframes cl-fadeup{from{opacity:0;translate:0 8%}}
.car-slide.on .cl-a-fade{animation:cl-fade var(--ad) $ease both}
.car-slide.on .cl-a-fadeUp{animation:cl-fadeup var(--ad) $ease both}
@media (prefers-reduced-motion:reduce){.car-slide,.car-slide.on{transition:none}.cl{animation:none!important}}
''';
}

/// Products (`_ProductsBlockWidget` and `PremiumProductCard`). The phone and
/// tablet bands are the window's: 640 and 1024 for a legacy document (`lg`),
/// 600 and 900 for a canonical one (`cn`).
const productsBlockCss = '''
.prod-blk{background:#fff;padding:48px 24px}
.prod-in{max-width:1200px;margin:0 auto}
.prod-head{display:flex;align-items:center}
.prod-bar{flex:none;width:4px;height:28px;margin-right:12px;background:#000}
.prod-head h2{flex:1;min-width:0;margin:0;font:700 22px/33px var(--body);letter-spacing:.5px;color:#000;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.prod-sub{margin:12px 0 0;padding-left:16px;font:400 14px/21px var(--body);letter-spacing:.25px;color:rgb(0 0 0 / .54)}
.prod-grid{display:grid;grid-template-columns:repeat(var(--cols),minmax(0,1fr));gap:20px;list-style:none;margin:32px 0 0;padding:0}
.pcard{display:flex;flex-direction:column;aspect-ratio:3/4;background:#fff;color:inherit;text-decoration:none;transition:transform .2s}
.pcard:hover{transform:translateY(-2px)}
.pcard:focus-visible{outline:2px solid var(--w-prim);outline-offset:2px}
.pcard-shot{position:relative;flex:4 1 0;min-height:0;display:grid;place-items:center;padding:16px;color:#bdbdbd}
.pcard-shot img{position:absolute;inset:16px;display:block;width:calc(100% - 32px);height:calc(100% - 32px);object-fit:contain}
.pcard-cta{display:none;position:absolute;left:50%;bottom:12px;translate:-50% 0;padding:8px 16px;border-radius:2px;background:#000;color:#fff;font:600 11px/15px var(--body);letter-spacing:.5px;white-space:nowrap}
@media (min-width:600px){.pcard:hover .pcard-cta{display:block}}
.pcard-info{flex:3 1 0;min-height:0;display:flex;flex-direction:column;justify-content:center;padding:12px}
.pcard-brand{margin-bottom:4px;font:600 10px/15px var(--body);letter-spacing:.4px;color:rgb(0 0 0 / .54);white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.pcard-name{font:500 12px/16px var(--body);letter-spacing:.3px;color:rgb(0 0 0 / .87);display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;overflow:hidden}
.pcard-sku{margin-top:4px;font:500 10px/15px var(--body);letter-spacing:.25px;color:rgb(0 0 0 / .54)}
.pcard-price{margin-top:6px;font:700 14px/21px var(--body);letter-spacing:.25px;color:#000}
.prod-all{margin-top:40px;text-align:center}
.w-btn.ink{border-color:#000;color:#000;letter-spacing:1px}
.w-btn.ink:hover{background:rgb(0 0 0 / .08)}
.prod-blk.empty{display:flex;flex-direction:column;align-items:center;padding:24px;color:#bdbdbd}
.prod-blk.empty .prod-head{justify-content:center}
.prod-blk.empty .prod-bar{height:24px}
.prod-blk.empty h2{flex:none;font-size:20px;line-height:30px}
.prod-blk.empty .prod-sub{padding:0;text-align:center}
.prod-blk.empty svg{margin-top:24px}
.prod-none{margin:12px 0 0;font:400 16px/24px var(--body);letter-spacing:.25px;color:#757575}
@media (max-width:1023.98px){.prod-blk.lg .prod-grid{--cols:2!important}}
@media (max-width:899.98px){.prod-blk.cn .prod-grid{--cols:2!important}}
@media (max-width:639.98px){.prod-blk.lg{padding-inline:16px}.prod-blk.lg .prod-grid{--cols:1!important}}
@media (max-width:599.98px){.prod-blk.cn{padding-inline:16px}.prod-blk.cn .prod-grid{--cols:1!important}}
''';

/// Category grid (`_AutoCategoryGrid`, `_CategoryGridLayout` and
/// `_CategoryCard`): a 12-column grid so a row of one, two, three or four
/// cards shares the width as Flutter's `Expanded`s do. Texts take the
/// store's 1.5 line (`bodyMedium`), unrounded, as Flutter lays them out.
String categoryGridCss(WebsiteThemeRoles theme) {
  final subtitle = (theme.bodySize + 2).clamp(10, 40).toDouble();
  return '''
.cat-blk{background:#fff;padding:48px 0}
.cat-t{margin:0;padding:0 24px;font:400 32px/40px var(--head);color:rgb(0 0 0 / .87);-webkit-text-stroke:.032em currentColor}
.cat-s{margin:8px 0 0;padding:0 24px;font:400 ${_n(subtitle)}px/1.5 var(--body);letter-spacing:.5px;color:rgb(0 0 0 / .54)}
.cat-t~.cat-grid{margin-top:32px}
.cat-grid{display:grid;grid-template-columns:repeat(12,minmax(0,1fr));gap:4px}
.cat-grid.no-lg{padding-top:4px}
.cat{grid-column:span var(--span);position:relative;display:flex;flex-direction:column;overflow:hidden;text-decoration:none}
.cat.lg{height:380px}.cat.sm{height:220px}
.cat:focus-visible{outline:2px solid var(--w-prim);outline-offset:-2px}
.cat.light{background:#f1f0ed;color:#141414;transition:background-color .2s}
.cat.light:hover{background:#e7e6e4}
.cat-shot{position:relative;flex:1 1 0;min-height:0}
.cat-shot img{position:absolute;top:32px;left:32px;width:calc(100% - 64px);height:calc(100% - 44px);object-fit:contain;mix-blend-mode:multiply}
.cat-info{display:flex;flex-direction:column;padding:0 24px 22px}
.cat-name{font:700 26px/1.5 var(--body);letter-spacing:1px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.cat-sub{margin-top:4px;font:400 13px/1.5 var(--body);letter-spacing:.25px;color:#55544f;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.cat-cta{display:flex;align-items:center;gap:6px;margin-top:10px;font:700 11px/1.5 var(--body);letter-spacing:1.5px;white-space:nowrap}
.cat-cta span{min-width:0;overflow:hidden;text-overflow:ellipsis}
.cat-cta svg{flex:none;width:14px;height:14px}
.cat.light.sm .cat-shot img{top:16px;left:16px;width:calc(100% - 32px);height:calc(100% - 20px)}
.cat.light.sm .cat-info{padding:0 16px 14px}
.cat.light.sm .cat-name{font-size:17px}
.cat.light.sm .cat-sub{display:none}
.cat.light.sm .cat-cta{margin-top:4px}
.cat.dark{justify-content:flex-end;padding:24px;background:linear-gradient(to bottom right,#3a3a3a,#1a1a1a);color:#fff}
.cat.dark:has(.cat-bg){background:#2a2a2a}
.cat.dark::after{content:"";position:absolute;inset:0;background:rgb(0 0 0 / .2);opacity:0;transition:opacity .2s;pointer-events:none}
.cat.dark:hover::after{opacity:1}
.cat-bg{position:absolute;inset:0;width:100%;height:100%;object-fit:cover;filter:brightness(.62)}
.cat-in{position:relative;z-index:1;display:flex;flex-direction:column;align-items:flex-start}
.cat.dark .cat-name{max-width:100%;font-size:28px;text-shadow:0 0 10px rgb(0 0 0 / .5)}
.cat.dark.sm .cat-name{font-size:20px}
.cat.dark .cat-sub{margin-top:6px;color:rgb(255 255 255 / .702)}
.cat-btn{margin-top:16px;padding:10px 20px;border:1px solid rgb(255 255 255 / .3);background:#000;font:600 11px/1.5 var(--body);letter-spacing:1.5px}
@media (min-width:600px){.cat.xd{display:none}}
@media (max-width:599.98px){
.cat-grid{grid-template-columns:1fr 1fr}
.cat-grid.no-lg{padding-top:0}
.cat-grid.only-lg{padding-bottom:4px}
.cat.lg{grid-column:1/-1;height:300px}
.cat.sm{grid-column:auto}
.cat.fo{margin-top:4px}
.cat.light.lg .cat-name,.cat.dark.lg .cat-name{font-size:20px}
}
''';
}
