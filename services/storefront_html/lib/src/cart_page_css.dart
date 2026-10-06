import 'package:vinabike_public_core/modules/website/theme/website_theme_roles.dart';

/// `/carrito` with Flutter's `CartPage` sizes (measured 2026-10-06 at 1440
/// and 412 px) on the editor theme's roles: its surface, low container
/// (photos, pills, the empty box), container (the summary), outline variant
/// (every line), ink and muted ink. The red and the amber are the store's
/// fixed `PublicStoreTheme.error` and `.warning`. Under 980 px the summary
/// goes below the lines and each line gets the phone's layout; under 760
/// the side margin is 16.
String cartPageCss(WebsiteThemeRoles theme) =>
    '''
:root{--k-bg:${theme.background.css};--k-soft:${theme.surfaceContainerLow.css};--k-raised:${theme.surfaceContainer.css};--k-high:${theme.surfaceContainerHigh.css};--k-line:${theme.outlineVariant.css};--k-on:${theme.onSurface.css};--k-onv:${theme.onSurfaceVariant.css};--k-prim:${theme.primary.css};--k-onprim:${theme.onPrimary.css};--k-muted:color-mix(in srgb,var(--k-on) 58%,transparent);--k-dis:color-mix(in srgb,var(--k-on) 38%,transparent);--k-err:#ef4444;--k-warn:#f59e0b;--k-warnbg:color-mix(in srgb,#f59e0b 12%,var(--k-bg));--k-onwarn:#17211b}
.cart-page{background:var(--k-bg)}
.cart-in{width:min(1320px,calc(100% - 48px));margin:44px auto}
/* A grid, not flex 7/4: flex takes the summary's padding out before
   sharing, and Flutter's Expanded does not (30 px off, 2026-10-06). */
.cart-full{display:grid;grid-template-columns:minmax(0,7fr) minmax(0,4fr);align-items:start;column-gap:28px}
.cart-main{min-width:0}
.cart-sum{min-width:0;padding:24px;border-block:1px solid var(--k-line);background:var(--k-raised)}
.cart-title{margin:0;font:400 32px/32px var(--head);text-transform:uppercase;color:var(--k-on);-webkit-text-stroke:.032em currentColor}
.cart-bar{display:block;width:72px;height:2px;margin-top:10px;background:var(--k-prim)}
.cart-units{margin:12px 0 0;font:400 18px/27px var(--body);letter-spacing:.5px;color:var(--k-onv)}
.cart-lead{margin:8px 0 0;font:400 14px/21px var(--body);letter-spacing:.25px;color:var(--k-onv)}
.cart-notice{display:flex;align-items:flex-start;margin-top:14px;padding:12px 14px;border:1px solid var(--k-warn);border-radius:10px;background:var(--k-warnbg);color:var(--k-onwarn)}
.cart-notice svg{flex:none;color:var(--k-warn)}
.cart-notice p{flex:1;margin:0 0 0 10px;font:400 13px/19px var(--body);letter-spacing:.25px}
.cart-notice button{flex:none;min-width:48px;height:44px;margin-left:8px;padding:0 12px;border:0;border-radius:22px;background:none;color:inherit;font:600 14px/20px var(--body);letter-spacing:.1px;cursor:pointer}
.cart-notice button:hover{background:color-mix(in srgb,currentColor 8%,transparent)}
.cart-lines{margin:34px 0 0;padding:0;list-style:none}
.cl{display:flex;gap:24px;padding:24px 0;border-top:1px solid transparent;border-bottom:1px solid var(--k-line)}
.cl.first{border-top-color:var(--k-line)}
.cl-shot{flex:none;display:grid;place-items:center;width:168px;height:144px;padding:12px;background:var(--k-soft);color:var(--k-muted)}
.cl-shot img{width:100%;height:100%;object-fit:contain}
.cl-info{flex:1;min-width:0}
.cl-top{display:flex;align-items:flex-start;gap:12px}
.cl-id{flex:1;min-width:0}
.cl-pills{display:flex;flex-wrap:wrap;gap:8px;margin-bottom:14px}
.cl-pills span{padding:6px 9px;border-radius:999px;background:var(--k-soft);font:700 10px/15px var(--body);letter-spacing:.8px;color:var(--k-onv)}
.cl-title{display:block;font:400 28px/30px var(--head);text-transform:uppercase;color:var(--k-on);text-decoration:none;-webkit-text-stroke:.032em currentColor;overflow-wrap:anywhere}
.cl-title:hover{color:var(--k-prim)}
.cl-sku{margin:8px 0 0;font:700 12px/17px var(--body);letter-spacing:.7px;color:var(--k-muted)}
.cl-x{flex:none;display:grid;place-items:center;width:40px;height:40px;padding:0;border:0;border-radius:50%;background:none;color:var(--k-err);cursor:pointer}
.cl-x:hover{background:color-mix(in srgb,var(--k-err) 8%,transparent)}
.cl-short{margin:16px 0 0;padding:12px 14px;border:1px solid rgb(239 68 68 / .25);background:rgb(239 68 68 / .08);font:700 13px/20px var(--body);color:var(--k-err)}
.cl-buy{display:flex;align-items:flex-end;margin-top:22px}
.cl-label{margin:0 0 10px;font:700 12px/17px var(--body);letter-spacing:.7px;color:var(--k-onv)}
.cl-qty{display:inline-flex;border:1px solid var(--k-line);background:var(--k-bg)}
.cl-qty button{display:grid;place-items:center;width:40px;height:46px;padding:0;border:0;background:none;color:var(--k-on);cursor:pointer}
.cl-qty button:hover:not(:disabled){background:color-mix(in srgb,var(--k-on) 6%,transparent)}
.cl-qty button:disabled{color:var(--k-dis);cursor:default}
.cl-qty output{display:grid;place-items:center;width:50px;height:46px;border-inline:1px solid var(--k-line);font:700 15px/21px var(--body);color:var(--k-on)}
.cl-sub{margin-left:auto;text-align:right}
.cl-total{margin:0;font:400 34px/32px var(--head);color:var(--k-prim);-webkit-text-stroke:.032em currentColor;white-space:nowrap}
.cl-each{margin:0;font:400 12px/18px var(--body);letter-spacing:.4px;color:var(--k-muted);white-space:nowrap}
.cl-each.d{margin-top:4px}
.cl-each.m{display:none}
.cs-title{margin:0;font:400 32px/41px var(--head);color:var(--k-on);-webkit-text-stroke:.032em currentColor}
.cs-row{display:flex;justify-content:space-between;gap:16px;margin:18px 0 0;font:400 15px/23px var(--body);letter-spacing:.25px;color:var(--k-on)}
.cs-row+.cs-row{margin-top:12px}
.cs-row b{font-weight:700}
.cs-row.sec{color:var(--k-onv)}
.cs-warn{margin:18px 0 0;padding:10px 12px;border-left:3px solid var(--k-warn);background:var(--k-warnbg);font:600 13px/19px var(--body);color:var(--k-onwarn)}
.cs-rule{height:0;margin:18px 0 0;border:0;border-top:1px solid var(--k-line)}
.cs-total{display:flex;justify-content:space-between;align-items:flex-end;gap:16px;margin:18px 0 0}
.cs-total span{font:700 13px/19px var(--body);letter-spacing:.8px;color:var(--k-onv)}
.cs-total b{font:400 44px/42px var(--head);color:var(--k-prim);-webkit-text-stroke:.032em currentColor;white-space:nowrap}
.cs-pay,.cs-more{display:flex;align-items:center;justify-content:center;width:100%;border-radius:6px;font:600 14px/20px var(--body);letter-spacing:.1px;text-decoration:none;text-transform:uppercase;cursor:pointer}
.cs-pay{height:48px;margin-top:26px;border:0;background:var(--k-prim);color:var(--k-onprim)}
.cs-pay:hover{background:linear-gradient(rgb(255 255 255 / .08),rgb(255 255 255 / .08)),var(--k-prim)}
.cs-pay:disabled{background:color-mix(in srgb,var(--k-on) 12%,transparent);color:var(--k-dis);cursor:default}
.cs-more{height:44px;margin-top:12px;border:1px solid var(--k-prim);background:none;color:var(--k-prim)}
.cs-more:hover{background:color-mix(in srgb,var(--k-prim) 8%,transparent)}
.cs-rule.b{margin-top:26px}
.cs-perks{margin:18px 0 0;padding:0;list-style:none}
.cs-perks li{position:relative;padding:14px 0 14px 19px;border-bottom:1px solid var(--k-line);font:600 14px/21px var(--body);color:var(--k-on)}
.cs-perks li:last-child{border-bottom-color:transparent}
.cs-perks li::before{content:"";position:absolute;left:0;top:20px;width:7px;height:7px;border-radius:50%;background:var(--k-prim)}
.cart-empty{display:flex;flex-direction:column;align-items:center;max-width:560px;margin:0 auto;padding:36px 8px;text-align:center}
.cart-empty-box{display:grid;place-items:center;width:148px;height:148px;border:1px solid var(--k-line);background:var(--k-soft);color:var(--k-muted)}
.cart-empty-head{display:flex;flex-direction:column;align-items:flex-start;margin-top:32px;text-align:left}
.cart-empty>p{margin:16px 0 0;font:400 15px/24px var(--body);letter-spacing:.25px;color:var(--k-onv)}
.cart-go,.cart-home{display:inline-flex;align-items:center;justify-content:center;gap:8px;border-radius:6px;font:600 14px/20px var(--body);letter-spacing:.1px;text-decoration:none;text-transform:uppercase}
.cart-go{height:48px;margin-top:32px;padding:0 30px;background:var(--k-prim);color:var(--k-onprim)}
/* Material's 24 px, less the compact density, on its narrower label. */
.cart-home{height:40px;margin-top:16px;padding:0 19px;border:1px solid var(--k-prim);color:var(--k-prim)}
.cart-wait,.cart-failed{margin:0;padding:80px 0;font:400 15px/23px var(--body);color:var(--k-onv);text-align:center}
.cart-dialog{width:min(560px,calc(100% - 48px));padding:24px;border:0;border-radius:28px;background:var(--k-high);color:var(--k-on)}
.cart-dialog::backdrop{background:rgb(0 0 0 / .54)}
.cart-dialog h2{margin:0;font:400 24px/32px var(--body);color:var(--k-on)}
.cart-dialog p{margin:16px 0 0;font:400 14px/20px var(--body);letter-spacing:.25px;color:var(--k-onv)}
.cart-dialog-acts{display:flex;justify-content:flex-end;gap:8px;margin-top:24px}
.cart-dialog-acts button{height:40px;padding:0 16px;border:0;border-radius:20px;font:600 14px/20px var(--body);letter-spacing:.1px;text-transform:uppercase;cursor:pointer}
.cart-dialog-no{background:none;color:var(--k-prim)}
.cart-dialog-yes{padding:0 24px!important;background:var(--k-err);color:#fff;box-shadow:0 1px 3px rgb(0 0 0 / .2)}
.cart-toast{position:fixed;left:0;right:0;bottom:0;z-index:30;margin:0;padding:14px 16px;background:var(--k-on);color:var(--k-bg);font:400 14px/20px var(--body)}
@media (max-width:979.98px){
.cart-in{margin-block:28px}
.cart-full{display:block}
.cart-sum{margin-top:32px;padding:20px}
.cart-lines{margin-top:28px}
.cl{gap:16px;padding-block:18px}
.cl-shot{width:116px;height:108px}
.cl-title{font-size:24px;line-height:26px}
.cl-buy{display:block;margin-top:16px}
.cl-sub{display:flex;justify-content:space-between;align-items:flex-end;gap:12px;margin:18px 0 0;text-align:left}
.cl-each.m{display:block;font-size:13px;line-height:20px;letter-spacing:.4px}
.cl-each.d{display:none}
.cs-title{font-size:28px;line-height:36px}
}
@media (max-width:759.98px){.cart-in{width:calc(100% - 32px)}}
''';
