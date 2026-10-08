import 'package:vinabike_public_core/modules/website/theme/website_theme_roles.dart';

import 'css_values.dart';

/// The login's styles, as `CustomerAuthPage` draws it under the store's
/// theme: the card, the intro and the notices in `PublicStoreTheme`'s fixed
/// colors (as Flutter writes them), the fields, the dialog and the bars in
/// the editor theme's roles (`WebsiteThemeBuilder`).
///
/// Texts: the theme's styles split a line's extra room half and half, as
/// CSS does; a bare `TextStyle` inherits `bodyMedium` (the body font at the
/// theme's body size, height 1.5, spacing .25). A button style that names no
/// font is Roboto 400 with Skia's fake bold (`vb-roboto` and a stroke).
///
/// Boxes: the store's density (−1, −1) takes 4 px off a button's minimum
/// height and its vertical padding; a `Container` border is inside its box.
/// Wide (two columns) from 900 px of page, `LayoutBuilder`'s width: the
/// query reads `.lg`'s content box, the page less its 24 px sides (852).
String loginPageCss(WebsiteThemeRoles roles) {
  final head = roles.headingFont.trim();
  final body = roles.bodyFont.trim();
  final bodySize = roles.bodySize;
  FlutterTextCss heading(double size, double height, {int weight = 600}) =>
      FlutterTextCss(head, size, height, weight, 0, heading: true);
  FlutterTextCss text(
    double size, {
    int weight = 400,
    double height = 1.5,
    double spacing = .25,
  }) => FlutterTextCss(body, size, height, weight, spacing, heading: false);
  String rule(String selector, FlutterTextCss style, [String extra = '']) =>
      '$selector{${style.font}$extra}'
      '$selector>.lg-x{left:${cssPx(style.spacing / 2)}}';

  // `Typography.englishLike2021` under the store's text theme, resized by
  // the editor theme (`bodyLarge` = body + 2, `bodySmall` = body − 2).
  final headline = heading(32, 1.15);
  final headlineCompact = heading(28, 1.15);
  final title = heading(20, 32 / 24);
  final eyebrow = text(12, weight: 700, height: 16 / 12, spacing: 1.1);
  final lead = text(bodySize + 2, spacing: .5);
  final sub = text(bodySize);
  final small = text(bodySize - 2, weight: 600, spacing: .4);
  final error = text(bodySize - 2, spacing: .4);
  final input = text(bodySize + 2, spacing: .5);
  final label13 = text(13, weight: 700);
  final rowTitle = text(15, weight: 700);
  final rowSub = text(13, height: 1.45);
  final question = text(13);
  final notice = text(bodySize, weight: 700);
  final buttonLabel = text(14, weight: 600, height: 20 / 14, spacing: .1);

  final ink = WebsiteRgba.alphaBlend(roles.onSurface, roles.background);
  final ink2 = WebsiteRgba.alphaBlend(roles.onSurfaceVariant, roles.background);
  final high = roles.surfaceContainerHigh;

  // Roboto with Skia's fake bold at [size] (`FlutterTextCss`'s ratio).
  String roboto(double size, {required bool bold, double spacing = 0}) {
    final ratio = 1 / 24 + (size - 9) / 27 * (1 / 32 - 1 / 24);
    final stroke = bold
        ? cssPx(double.parse((size * ratio).toStringAsFixed(3)))
        : '0';
    return 'font:400 ${cssPx(size)}/normal "vb-roboto",var(--body);'
        'letter-spacing:${cssPx(spacing)};-webkit-text-stroke:$stroke currentColor';
  }

  return '''
.lg{container:lg/inline-size;--lg-ink:#1e293b;--lg-ink2:#64748b;--lg-line:rgb(203 213 225 / .9);--lg-fill:${roles.surfaceContainerLow.css};--lg-edge:${roles.outlineVariant.css};--lg-on:${ink.css};--lg-onv:${ink2.css};--lg-prim:${roles.primary.css};--lg-onprim:${roles.onPrimary.css};--lg-err:#ef4444;--lg-high:${high.css};--lg-ons:${roles.onSurface.css};--lg-page:${roles.background.css};box-sizing:border-box;padding:28px 24px 56px;background:#fff;color:var(--lg-ink)}
:where(.lg) *,:where(.lg) *::before,:where(.lg) *::after{box-sizing:border-box}
:where(.lg) :where(p,h1,h2,ul,li){margin:0;padding:0}
:where(.lg) ul{list-style:none}
:where(.lg) button{margin:0;padding:0;border:0;background:none;color:inherit;font:inherit;letter-spacing:inherit;cursor:pointer}
:where(.lg) a{color:inherit;text-decoration:none}
:where(.lg) svg{flex:none;display:block}
.lg [hidden]{display:none!important}
.lg[data-mode=login] [data-only]:not([data-only~=login]),.lg[data-mode=register] [data-only]:not([data-only~=register]),.lg[data-mode=recovery] [data-only]:not([data-only~=recovery]),.lg[data-mode=invitation] [data-only]:not([data-only~=invitation]){display:none!important}
.lg [data-link-panel],.lg[data-link=checking] .lg-form>:not([data-link-panel=checking]),.lg[data-link=invalid] .lg-form>:not([data-link-panel=invalid]){display:none!important}
.lg[data-link=checking] [data-link-panel=checking],.lg[data-link=invalid] [data-link-panel=invalid]{display:flex!important}
.lg-x{position:relative}
.lg-card{max-width:1040px;margin:0 auto;border:1px solid var(--lg-line);border-radius:24px;background:#fff;box-shadow:0 14px 33.3px rgb(0 0 0 / .0706)}
.lg-intro{padding:28px 28px 24px;border-bottom:1px solid rgb(203 213 225 / .75);border-radius:24px 24px 0 0;background:#fff}
${rule('.lg-eyebrow', eyebrow, ';color:var(--lg-ink2)')}
.lg-headline{margin-top:14px!important;${headlineCompact.font};color:var(--lg-ink);overflow-wrap:break-word}
${rule('.lg-lead', lead, ';margin-top:14px!important;color:var(--lg-ink2)')}
.lg-benefits{display:grid;gap:16px;margin-top:28px!important}
.lg-benefits li{display:flex;align-items:flex-start;gap:14px}
.lg-bicon{flex:none;display:flex;align-items:center;justify-content:center;width:40px;height:40px;border:1px solid rgb(203 213 225 / .85);border-radius:12px;background:#fff;color:var(--lg-ink)}
.lg-benefits li>div{flex:1;display:flex;flex-direction:column;gap:4px;min-width:0}
${rule('.lg-benefits strong', rowTitle, ';color:var(--lg-ink)')}
${rule('.lg-benefits li>div>span', rowSub, ';color:var(--lg-ink2)')}
.lg-back{display:none;align-items:center;gap:8px;height:40px;margin-top:28px;${roboto(14, bold: true)};color:var(--lg-ink)}
.lg-back:focus-visible,.lg button:focus-visible{outline:2px solid var(--lg-prim);outline-offset:2px}
.lg-form{padding:30px 28px}
${rule('.lg-title', title, ';color:var(--lg-ink)')}
${rule('.lg-sub', sub, ';margin-top:8px!important;margin-bottom:24px!important;color:var(--lg-ink2)')}
.lg-note{margin-bottom:20px;padding:16px;border:1px solid rgb(203 213 225 / .85);border-radius:16px;background:#f8fafc}
.lg-note.ok{display:flex;align-items:flex-start;gap:12px;border-color:#b7e2c3;background:#eff8f2;color:#2e7d4f}
${rule('.lg-note.ok p', notice, ';color:#1f5d3b')}
${rule('.lg-note[data-verify]>strong', rowTitle, ';display:block;color:var(--lg-ink)')}
${rule('.lg-note[data-verify]>p', rowSub, ';margin-top:8px!important;color:var(--lg-ink2)')}
.lg-resend{display:inline-flex;align-items:center;gap:8px;min-height:40px;margin-top:14px;padding:9px 17px;border:1px solid var(--lg-line)!important;border-radius:12px;color:var(--lg-ink)}
${rule('.lg-resend span', buttonLabel)}
.lg-fields{display:flex;flex-direction:column;gap:16px}
${rule('.lg-field>label', label13, ';display:block;margin-bottom:8px;color:var(--lg-ink)')}
.lg-box{position:relative;display:flex;align-items:center;height:48px;border:1px solid var(--lg-edge);border-radius:8px;background:var(--lg-fill);color:var(--lg-onv)}
.lg-box:focus-within{border:2px solid var(--lg-prim)}
.lg-box .lg-ic{position:absolute;left:9px;top:50%;margin-top:-12px;pointer-events:none}
.lg-box:focus-within .lg-ic{left:8px}
.lg-box input{display:block;width:100%;height:100%;min-width:0;margin:0;padding:0 14px 0 47px;border:0;border-radius:7px;background:transparent;${input.font};color:var(--lg-on);text-overflow:ellipsis;outline:0;-webkit-appearance:none;appearance:none}
.lg-box:focus-within input{padding:0 13px 0 46px}
.lg-box input::placeholder{${sub.font};color:var(--lg-onv);opacity:1;text-overflow:ellipsis}
.lg-box input:-webkit-autofill{-webkit-box-shadow:0 0 0 40px var(--lg-fill) inset;-webkit-text-fill-color:var(--lg-on)}
.lg-box input::-ms-reveal{display:none}
.lg-field[data-field=password] .lg-box input{padding-right:47px}
.lg-field[data-field=password] .lg-box:focus-within input{padding-right:46px}
.lg-eye{position:absolute;right:-3px;top:-1px;display:flex;align-items:center;justify-content:center;width:48px;height:48px;border-radius:50%;color:var(--lg-onv)}
.lg-box:focus-within .lg-eye{right:-4px;top:-2px}
.lg-eye .hide,.lg-eye[aria-pressed=true] .show{display:none}
.lg-eye[aria-pressed=true] .hide{display:block}
.lg-field.bad .lg-box{border-color:var(--lg-err)}
.lg-field.bad .lg-eye{color:var(--lg-err)}
.lg-box:hover{background:linear-gradient(rgb(0 0 0 / .04),rgb(0 0 0 / .04)),var(--lg-fill)}
.lg-field.bad .lg-box:hover .lg-eye{color:#fff}
${rule('.lg-msg', error, ';display:none;padding:4px 16px 0 18px;color:var(--lg-err);white-space:nowrap;overflow:hidden;text-overflow:ellipsis')}
.lg-field.bad .lg-msg,.lg-ff.bad .lg-msg{display:block}
.lg-submit{display:flex;align-items:center;justify-content:center;gap:8px;width:100%;height:38px;margin-top:6px;border-radius:12px;background:var(--lg-ink)!important;color:#fff!important;${roboto(14, bold: true, spacing: .15)}}
.lg-submit[aria-busy=true]>span:not(.lg-spin){display:none}
.lg-spin svg{animation:lg-spin 1.4s linear infinite}
.lg-spin circle{stroke-dasharray:38 13;stroke-linecap:butt}
@keyframes lg-spin{to{transform:rotate(360deg)}}
.lg-or{display:flex;align-items:center;margin:18px 0}
.lg-or::before,.lg-or::after{content:"";flex:1;height:1px;background:var(--lg-line)}
${rule('.lg-or span', small, ';padding:0 14px;color:var(--lg-ink2)')}
.lg-google{display:flex;align-items:center;justify-content:center;gap:8px;width:100%;height:40px;border:1px solid var(--lg-line)!important;border-radius:12px;background:#fff!important;color:var(--lg-ink);${roboto(14, bold: true)}}
.lg-switch{display:flex;flex-wrap:wrap;align-items:center;justify-content:center;gap:4px;margin-top:22px!important}
${rule('.lg-switch>span', question, ';color:var(--lg-ink2)')}
.lg-leave{display:block;height:40px;margin:14px auto 0;padding:0 20px;${roboto(14, bold: true)};color:var(--lg-ink)}
.lg-leave:hover{background:rgb(30 41 59 / .08);border-radius:8px}
.lg-wait{flex-direction:column;align-items:center;gap:18px;padding:24px 0;color:var(--lg-ink)}
.lg-wait svg{width:36px;height:36px}
${rule('.lg-wait p', lead, ';font-weight:600;text-align:center;color:var(--lg-ink2)')}
.lg-bad{flex-direction:column;align-items:stretch;gap:10px;text-align:center}
.lg-bad>svg{align-self:center;color:var(--lg-err);margin-bottom:6px}
${rule('.lg-bad>h2', title, ';color:var(--lg-ink)')}
${rule('.lg-bad>p', sub, ';color:var(--lg-ink2)')}
.lg-bad>.lg-submit{height:48px;margin-top:14px}
.lg-switch>button{height:40px;padding:0 8px;${roboto(13, bold: true)};color:var(--lg-ink)}
.lg-forgot{display:block;height:40px;margin:0 auto;padding:0 20px;${roboto(13, bold: true)};color:var(--lg-ink2)}
.lg-switch>button:hover,.lg-forgot:hover,.lg-back:hover{background:rgb(30 41 59 / .08);border-radius:8px}
.lg[aria-busy=true] .lg-google,.lg[aria-busy=true] .lg-submit{pointer-events:none}
.lg[aria-busy=true] .lg-google{color:rgb(30 41 59 / .38)}
.lg-noscript{max-width:1040px;margin:16px auto 0;${sub.font};color:var(--lg-ink2)}
@container lg (min-width:852px){
.lg-card{margin-top:16px}
.lg-card{display:grid;grid-template-columns:1fr 1fr;align-items:stretch}
.lg-intro{padding:36px 28px;border-bottom:0;border-right:1px solid rgb(203 213 225 / .75);border-radius:24px 0 0 24px;background:#f8fafc}
.lg-headline{${headline.font}}
.lg-back{display:inline-flex}
}
.lg-dlg{position:fixed;inset:0;width:100%;max-width:none;height:100%;max-height:none;margin:0;padding:0;border:0;background:transparent;overflow:hidden}
.lg-dlg::backdrop{background:transparent}
.lg-dlg[open]{display:flex;align-items:center;justify-content:center}
.lg-scrim{position:absolute;inset:0;background:rgb(0 0 0 / .54)}
.lg-alert{position:relative;display:flex;flex-direction:column;width:fit-content;min-width:280px;max-width:calc(100vw - 80px);max-height:calc(100% - 48px);overflow:auto;padding:24px 0 24px;border-radius:28px;background:var(--lg-high);color:var(--lg-on)}
${rule('.lg-alert>h2', title, ';padding:0 24px;color:var(--lg-on)')}
${rule('.lg-alert>p', sub, ';padding:16px 24px 0;color:var(--lg-onv)')}
.lg-ff{position:relative;margin:16px 24px 0;height:48px}
.lg-ff input{display:block;width:100%;height:48px;margin:0;padding:0 14px 0 47px;border:0;border-radius:8px;background:var(--lg-fill);${input.font};color:var(--lg-on);outline:0;-webkit-appearance:none;appearance:none}
.lg-ff .lg-ic{position:absolute;left:9px;top:12px;color:var(--lg-onv);pointer-events:none}
.lg-ff label{position:absolute;left:48px;top:12px;max-width:calc(100% - 62px);${sub.font};color:var(--lg-onv);white-space:nowrap;overflow:hidden;text-overflow:ellipsis;transform-origin:0 0;transition:transform .2s cubic-bezier(.4,0,.2,1),color .2s;pointer-events:none}
.lg-ff fieldset{position:absolute;inset:-5px 0 0;margin:0;padding:0 8px;border:1px solid color-mix(in srgb,var(--lg-edge) 25%,var(--lg-high));border-radius:8px;pointer-events:none}
.lg-ff legend{float:none;width:auto;max-width:0;height:11px;padding:0;font-size:12px;visibility:hidden;white-space:nowrap;transition:max-width .05s}
.lg-ff legend span{padding:0 4px}
.lg-ff input:focus~fieldset{border:2px solid var(--lg-prim);padding-left:7px}
.lg-ff input:focus~label{color:var(--lg-prim)}
.lg-ff input:focus~label,.lg-ff input:not(:placeholder-shown)~label{transform:translate(-30px,-21px) scale(.75)}
.lg-ff input:focus~fieldset legend,.lg-ff input:not(:placeholder-shown)~fieldset legend{max-width:100%;transition:max-width .1s .05s}
.lg-ff.bad fieldset,.lg-ff.bad input:focus~fieldset{border-color:var(--lg-err)}
.lg-ff.bad label{color:var(--lg-err)!important}
.lg-ff .lg-msg{padding:4px 16px 0 18px}
.lg-ff.bad{height:auto}
.lg-actions{display:flex;justify-content:flex-end;align-items:center;gap:8px;padding:24px 24px 0}
.lg-text{height:40px;padding:0 20px!important;border-radius:8px;color:var(--lg-prim)!important}
.lg-fill{height:36px;padding:0 24px!important;border-radius:999px;background:var(--lg-prim)!important;color:var(--lg-onprim)!important}
${rule('.lg-text', buttonLabel)}
${rule('.lg-fill', buttonLabel)}
.lg-text:hover{background:color-mix(in srgb,var(--lg-prim) 8%,transparent)}
.lg-fill:disabled,.lg-text:disabled{opacity:.6;cursor:default}
.lg-toast{position:fixed;left:0;right:0;bottom:0;z-index:60;margin:0;padding:14px 24px;background:linear-gradient(var(--lg-ons),var(--lg-ons)),rgb(0 0 0 / .29);color:var(--lg-page);${sub.font};animation:lg-toast .25s cubic-bezier(0,0,.2,1)}
.lg-toast.bad{background:#f44336;color:#fff}
@keyframes lg-toast{from{transform:translateY(100%)}to{transform:none}}
''';
}
