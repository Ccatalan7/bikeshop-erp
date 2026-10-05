import 'package:vinabike_public_core/modules/website/theme/website_theme_roles.dart';

/// The page's stylesheet: Flutter's sizes on the editor theme's roles
/// (surface, its low container, outline variant, ink and muted ink; the
/// WhatsApp card is the inverse surface, the ink on the page color).
String contactPageCss(WebsiteThemeRoles theme) =>
    '''
:root{--c-bg:${theme.background.css};--c-low:${theme.surfaceContainerLow.css};--c-ovar:${theme.outlineVariant.css};--c-on:${theme.onSurface.css};--c-onv:${theme.onSurfaceVariant.css};--c-prim:${theme.primary.css};--c-onprim:${theme.onPrimary.css}}
.ct-hero{padding:40px 24px 32px;background:var(--c-bg);text-align:center}
.ct-hero>*{max-width:1120px;margin-inline:auto}
.ct-hero h1{margin:0;font:800 42px/63px var(--body);color:var(--c-on)}
.ct-hero p{margin:12px auto 0;font:400 18px/27px var(--body);letter-spacing:.25px;color:var(--c-onv)}
.ct-main{background:var(--c-low)}
.ct-in{display:grid;grid-template-columns:minmax(0,3fr) minmax(0,2fr);gap:48px;align-items:start;max-width:1200px;margin:0 auto;padding:64px 24px}
.ct-form{position:relative;padding:40px;border:1px solid var(--c-ovar);border-radius:12px;background:var(--c-bg)}
.ct-form h2{margin:0;font:800 24px/36px var(--body);letter-spacing:-.3px;color:var(--c-on)}
.ct-lead{margin:12px 0 36px;font:400 15px/23px var(--body);letter-spacing:.25px;color:var(--c-onv)}
/* A Row: an error under one field centers the other beside it. */
.ct-pair{display:grid;grid-template-columns:1fr 1fr;gap:16px;align-items:center}
.ct-field{position:relative;margin-bottom:20px}
.ct-pair .ct-field{margin-bottom:0}.ct-pair{margin-bottom:20px}
/* 16 + a 23 px line + 16, less the compact density's 4: 51 px; five lines
   in the message. */
.ct-field input,.ct-field textarea{display:block;width:100%;height:51px;margin:0;padding:0 16px 0 48px;border:1px solid var(--c-ovar);border-radius:8px;background:var(--c-low);font:400 15px/23px var(--body);color:var(--c-on);outline:none;resize:none}
.ct-field textarea{height:143px;padding-block:14px}
.ct-field input::placeholder,.ct-field textarea::placeholder{color:transparent}
.ct-field :focus::placeholder{color:var(--c-onv)}
.ct-field :focus{border:2px solid var(--c-prim);padding-left:47px}
.ct-field textarea:focus{padding-block:13px}
/* The resting label is the theme's bodyLarge: the body size + 2. */
.ct-field label{position:absolute;left:48px;top:25.5px;translate:0 -50%;max-width:calc(100% - 64px);font:400 ${_px(theme.bodySize + 2)}px/1.5 var(--body);letter-spacing:.5px;color:var(--c-onv);white-space:nowrap;overflow:hidden;text-overflow:ellipsis;pointer-events:none;transform-origin:left center;transition:top .2s,left .2s,scale .2s}
.ct-field.area label{top:71.5px}
.ct-field :focus+label,.ct-field :not(:placeholder-shown)+label{top:0;left:12px;scale:.75;padding:0 4px;background:linear-gradient(var(--c-bg) 50%,var(--c-low) 50%)}
.ct-field :focus+label{color:var(--c-prim)}
.ct-ico{position:absolute;left:14px;top:15.5px;color:var(--c-onv);pointer-events:none}
.ct-field.area .ct-ico{top:61.5px}
.ct-error{margin:0;padding:4px 16px 0;font:400 12px/16px var(--body);letter-spacing:.4px;color:#b3261e}
.ct-error:empty{display:none}
.ct-field [aria-invalid]{border-color:#b3261e}
.ct-field [aria-invalid]+label{color:#b3261e}
.ct-send{display:flex;align-items:center;justify-content:center;gap:8px;width:100%;height:52px;margin-top:32px;border:0;border-radius:12px;background:var(--c-prim);color:var(--c-onprim);font:600 16px/24px var(--body);letter-spacing:.1px;cursor:pointer}
.ct-send:hover{background:linear-gradient(rgb(255 255 255 / .08),rgb(255 255 255 / .08)),var(--c-prim)}
.ct-send:disabled{background:rgb(0 0 0 / .12);color:rgb(0 0 0 / .38);cursor:default}
.ct-toast{position:fixed;left:50%;bottom:24px;z-index:20;translate:-50% 0;margin:0;padding:14px 16px;border-radius:4px;background:#4caf50;color:#fff;font:400 14px/20px var(--body);box-shadow:0 3px 5px -1px rgb(0 0 0 / .2),0 6px 10px rgb(0 0 0 / .14)}
.ct-info{display:flex;flex-direction:column;gap:24px}
.ct-card{padding:32px;border-radius:12px;background:var(--c-low)}
.ct-head{display:flex;align-items:center;gap:16px;margin-bottom:24px}
.ct-badge{display:grid;place-items:center;flex:none;width:46px;height:46px;border:1px solid var(--c-ovar);border-radius:10px;background:var(--c-bg);color:var(--c-on)}
.ct-card h2{margin:0;font:800 18px/27px var(--body);letter-spacing:.25px;color:var(--c-on)}
.ct-detail{display:flex;align-items:flex-start;gap:12px;color:var(--c-onv)}
.ct-detail+.ct-detail{margin-top:16px}
.ct-detail svg{flex:none}
.ct-dt{margin:0 0 4px;font:600 14px/21px var(--body);letter-spacing:.25px;color:var(--c-on)}
.ct-dd{display:block;margin:0;font:400 15px/23px var(--body);letter-spacing:.25px;color:var(--c-onv);text-decoration:none}
a.ct-dd:hover{text-decoration:underline}
.ct-hours{margin:0;padding:0;list-style:none}
.ct-hours li{display:flex;justify-content:space-between;gap:16px;padding:10px 0;font:600 15px/23px var(--body);letter-spacing:.25px;color:var(--c-on)}
.ct-time{display:flex;align-items:center;color:var(--c-onv)}
.ct-time::before{content:"";width:6px;height:6px;margin-right:8px;border-radius:50%;background:var(--c-onv)}
.ct-hours .open .ct-time{color:var(--c-on)}.ct-hours .open .ct-time::before{background:#10b981}
/* The theme's divider is 1 px with no space of its own: 18 above, 14 below. */
.ct-rule{margin:18px 0 14px;border:0;border-top:1px solid var(--c-ovar)}
.ct-note{margin:0 0 18px;font:400 15px/23px var(--body);letter-spacing:.25px;color:var(--c-onv)}
/* Flutter's buttons are compact on every screen, phone included (measured
   at 1440 and 412 px): 14 + a 17.6 px label + 14 − 8, held at Material's
   40 px minimum; the WhatsApp one 16 + 17.6 + 16 − 8. Their label has no
   family of its own and falls to the engine's Roboto; here it keeps the
   store's, as «Iniciar sesión» does. */
.ct-maps,.ct-social a{display:flex;align-items:center;justify-content:center;gap:8px;height:40px;padding:0 16px;border:1px solid var(--c-ovar);border-radius:8px;background:var(--c-bg);color:var(--c-on);font:700 15px/18px var(--body);letter-spacing:.1px;text-decoration:none}
.ct-maps:hover,.ct-social a:hover{background:linear-gradient(rgb(0 0 0 / .04),rgb(0 0 0 / .04)),var(--c-bg)}
.ct-wa{padding:28px;background:var(--c-on);color:var(--c-bg)}
.ct-wa-head{display:flex;align-items:center;gap:12px}
.ct-wa h2{color:var(--c-bg)}
.ct-wa p{margin:12px 0 20px;font:400 15px/23px var(--body);letter-spacing:.25px;color:color-mix(in srgb,var(--c-bg) 72%,transparent)}
.ct-wa a{display:flex;align-items:center;justify-content:center;height:42px;padding:0 16px;border-radius:8px;background:var(--c-bg);color:var(--c-on);font:700 15px/18px var(--body);letter-spacing:.1px;text-decoration:none}
.ct-follow{padding:28px}
.ct-follow h2{margin-bottom:16px}
.ct-social{display:flex;gap:12px}
.ct-social a{flex:1;font-weight:600}
.ct-social .ig{color:#e4405f}.ct-social .fb{color:#1877f2}
.ct-off{display:flex;flex-direction:column;align-items:center;max-width:460px;margin:0 auto;padding:96px 24px;text-align:center;color:var(--c-onv)}
.ct-off h1{margin:16px 0 8px;font:700 22px/28px var(--body);color:var(--c-on)}
.ct-off p{margin:0;font:400 14px/1.4 var(--body);letter-spacing:.25px}
@media (max-width:900px){.ct-in{grid-template-columns:minmax(0,1fr)}.ct-info{order:-1}}
@media (max-width:500px){.ct-pair{grid-template-columns:minmax(0,1fr);gap:20px}}
''';

String _px(double value) =>
    value == value.roundToDouble() ? '${value.round()}' : '$value';
