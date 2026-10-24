import 'package:vinabike_public_core/modules/website/theme/website_theme_roles.dart';

/// `/carrito` on the editor theme's roles (2026-10-24, the store's new card:
/// titles as written, photos on a tile of the primary over the surface, the
/// summary in its own card), with the same sizes as Flutter's `CartPage`:
/// its surface, low container (pills), outline variant (every line), ink and
/// muted ink. The red, the amber and the green are the store's fixed
/// `PublicStoreTheme.error`, `.warning` and the card's «En stock». Under
/// 980 px the summary goes below the lines; under 760 the side margin is 16.
String cartPageCss(WebsiteThemeRoles theme) =>
    '''
:root{--k-bg:${theme.background.css};--k-soft:${theme.surfaceContainerLow.css};--k-raised:${theme.surfaceContainer.css};--k-high:${theme.surfaceContainerHigh.css};--k-line:${theme.outlineVariant.css};--k-on:${theme.onSurface.css};--k-onv:${theme.onSurfaceVariant.css};--k-prim:${theme.primary.css};--k-onprim:${theme.onPrimary.css};--k-tile:color-mix(in srgb,var(--k-prim) 6%,var(--k-bg));--k-muted:color-mix(in srgb,var(--k-on) 58%,transparent);--k-dis:color-mix(in srgb,var(--k-on) 38%,transparent);--k-err:#ef4444;--k-warn:#f59e0b;--k-warnbg:color-mix(in srgb,#f59e0b 12%,var(--k-bg));--k-onwarn:#17211b;--k-ok:#1F7A46}
.cart-page{background:var(--k-bg)}
.cart-in{width:min(1240px,calc(100% - 48px));margin:40px auto 72px}
/* A grid, not flex: flex takes the summary's padding out before sharing,
   and Flutter's Expanded does not (2026-10-06). */
.cart-full{display:grid;grid-template-columns:minmax(0,1fr) minmax(0,380px);align-items:start;column-gap:48px}
.cart-main{min-width:0}
.cart-sum{position:sticky;top:24px;min-width:0;padding:28px;border:1px solid var(--k-line);border-radius:20px;background:var(--k-bg);box-shadow:0 18px 40px -28px rgb(15 23 42 / .35)}
.cart-title{margin:0;font:600 36px/1.15 var(--head);letter-spacing:-.01em;color:var(--k-on);text-wrap:balance}
.cart-units{margin:8px 0 0;font:500 15px/1.5 var(--body);color:var(--k-onv)}
.cart-lead{margin:2px 0 0;font:400 14px/1.5 var(--body);color:var(--k-muted)}
.cart-notice{display:flex;align-items:flex-start;margin-top:16px;padding:12px 14px;border:1px solid var(--k-warn);border-radius:12px;background:var(--k-warnbg);color:var(--k-onwarn)}
.cart-notice svg{flex:none;color:var(--k-warn)}
.cart-notice p{flex:1;margin:0 0 0 10px;font:400 13px/19px var(--body);letter-spacing:.25px}
.cart-notice button{flex:none;min-width:48px;height:44px;margin-left:8px;padding:0 12px;border:0;border-radius:22px;background:none;color:inherit;font:600 14px/20px var(--body);cursor:pointer}
.cart-notice button:hover{background:color-mix(in srgb,currentColor 8%,transparent)}
.cart-lines{margin:28px 0 0;padding:0;list-style:none}
.cl{display:flex;gap:20px;padding:20px 0;border-top:1px solid transparent;border-bottom:1px solid var(--k-line)}
.cl.first{border-top-color:var(--k-line)}
.cl-shot{flex:none;display:grid;place-items:center;width:132px;height:132px;padding:12px;border-radius:16px;background:var(--k-tile);color:var(--k-muted);box-sizing:border-box}
.cl-shot img{width:100%;height:100%;object-fit:contain;mix-blend-mode:multiply}
.cl-info{flex:1;min-width:0;display:flex;flex-direction:column}
.cl-top{display:flex;align-items:flex-start;gap:12px}
.cl-id{flex:1;min-width:0}
.cl-pills{display:flex;flex-wrap:wrap;gap:6px;margin-bottom:8px}
.cl-pills span{padding:3px 10px;border-radius:999px;background:var(--k-soft);font:600 12px/18px var(--body);color:var(--k-onv)}
.cl-title{display:block;font:600 18px/1.35 var(--body);color:var(--k-on);text-decoration:none;overflow-wrap:anywhere}
.cl-title:hover{color:var(--k-prim);text-decoration:underline;text-underline-offset:3px}
.cl-sku{margin:4px 0 0;font:500 12px/1.4 var(--body);color:var(--k-muted)}
.cl-x{flex:none;display:grid;place-items:center;width:40px;height:40px;margin:-6px -8px 0 0;padding:0;border:0;border-radius:50%;background:none;color:var(--k-muted);cursor:pointer;transition:color .15s,background-color .15s}
.cl-x:hover{color:var(--k-err);background:color-mix(in srgb,var(--k-err) 8%,transparent)}
.cl-short{margin:12px 0 0;padding:10px 12px;border-radius:10px;background:rgb(239 68 68 / .08);font:600 13px/20px var(--body);color:var(--k-err)}
.cl-buy{display:flex;align-items:center;margin-top:auto;padding-top:16px}
.cl-label{position:absolute;width:1px;height:1px;margin:-1px;overflow:hidden;clip:rect(0 0 0 0);white-space:nowrap}
.cl-qty{display:inline-flex;align-items:center;height:42px;border:1px solid var(--k-line);border-radius:999px;background:var(--k-bg);overflow:hidden}
.cl-qty button{display:grid;place-items:center;width:42px;height:42px;padding:0;border:0;background:none;color:var(--k-on);cursor:pointer}
.cl-qty button:hover:not(:disabled){background:color-mix(in srgb,var(--k-on) 6%,transparent)}
.cl-qty button:disabled{color:var(--k-dis);cursor:default}
.cl-qty output{display:grid;place-items:center;min-width:32px;font:600 15px/1 var(--body);font-variant-numeric:tabular-nums;color:var(--k-on)}
.cl-sub{margin-left:auto;text-align:right}
.cl-total{margin:0;font:700 20px/1.2 var(--body);font-variant-numeric:tabular-nums;color:var(--k-on);white-space:nowrap}
.cl-each{margin:0;font:400 12px/18px var(--body);color:var(--k-muted);white-space:nowrap;font-variant-numeric:tabular-nums}
.cl-each.d{margin-top:2px}
.cl-each.m{display:none}
.cart-more{margin-top:36px;padding:28px;border-radius:20px;background:var(--k-tile)}
.cm-eye{margin:0;font:700 12px/1.3 var(--body);letter-spacing:.12em;text-transform:uppercase;color:var(--k-prim)}
.cm-title{margin:6px 0 0;font:600 24px/1.25 var(--head);letter-spacing:-.005em;color:var(--k-on);text-wrap:balance}
.cm-note{max-width:62ch;margin:6px 0 0;font:400 14px/1.55 var(--body);color:var(--k-onv)}
.cm-row{display:grid;grid-template-columns:repeat(auto-fill,minmax(250px,1fr));gap:12px;margin:20px 0 0;padding:0;list-style:none}
.cm{display:flex;align-items:center;gap:14px;padding:12px;border-radius:16px;background:var(--k-bg);box-shadow:0 1px 2px rgb(15 23 42 / .06)}
.cm-shot{flex:none;display:grid;place-items:center;width:88px;height:88px;padding:8px;border-radius:12px;background:var(--k-tile);color:var(--k-muted);box-sizing:border-box}
.cm-shot img{width:100%;height:100%;object-fit:contain;mix-blend-mode:multiply}
.cm-info{flex:1;min-width:0;display:flex;flex-direction:column;gap:2px}
.cm-brand{margin:0;font:700 11px/1.3 var(--body);letter-spacing:.08em;text-transform:uppercase;color:var(--k-onv);white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.cm-name{font:500 14px/1.35 var(--body);color:var(--k-on);text-decoration:none;display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;overflow:hidden}
.cm-name:hover{text-decoration:underline;text-underline-offset:3px}
.cm-foot{display:flex;align-items:center;justify-content:space-between;gap:8px;margin-top:6px}
.cm-price{font:700 15px/1.2 var(--body);font-variant-numeric:tabular-nums;color:var(--k-on);white-space:nowrap}
.cm-add{display:inline-flex;align-items:center;gap:4px;height:36px;padding:0 14px 0 10px;border:0;border-radius:999px;background:var(--k-prim);color:var(--k-onprim);font:600 13px/1 var(--body);cursor:pointer;transition:transform .14s,background-color .2s}
.cm-add:hover{transform:translateY(-1px)}
.cm-add:focus-visible{outline:2px solid var(--k-prim);outline-offset:2px}
.cm-add.is-done{background:var(--k-ok)}
.cm-add:disabled{cursor:default}
.cs-title{margin:0;font:600 22px/1.25 var(--head);color:var(--k-on)}
.cs-row{display:flex;justify-content:space-between;gap:16px;margin:18px 0 0;font:400 15px/23px var(--body);color:var(--k-on);font-variant-numeric:tabular-nums}
.cs-row+.cs-row{margin-top:8px}
.cs-row b{font-weight:600}
.cs-row.sec{color:var(--k-onv)}
.cs-warn{margin:18px 0 0;padding:10px 12px;border-left:3px solid var(--k-warn);border-radius:0 8px 8px 0;background:var(--k-warnbg);font:600 13px/19px var(--body);color:var(--k-onwarn)}
.cs-rule{height:0;margin:18px 0 0;border:0;border-top:1px solid var(--k-line)}
.cs-total{display:flex;justify-content:space-between;align-items:baseline;gap:16px;margin:18px 0 0}
.cs-total span{font:600 16px/1.3 var(--body);color:var(--k-on)}
.cs-total b{font:700 30px/1.1 var(--body);font-variant-numeric:tabular-nums;color:var(--k-on);white-space:nowrap}
.cs-pay,.cs-more{display:flex;align-items:center;justify-content:center;width:100%;box-sizing:border-box;border-radius:12px;text-decoration:none;cursor:pointer}
.cs-pay{height:54px;margin-top:24px;border:0;background:var(--k-prim);color:var(--k-onprim);font:700 16px/1 var(--body);transition:filter .15s,transform .14s}
.cs-pay:hover{filter:brightness(1.08)}
.cs-pay:active{transform:scale(.99)}
.cs-pay:disabled{background:color-mix(in srgb,var(--k-on) 12%,transparent);color:var(--k-dis);cursor:default;filter:none}
.cs-more{height:48px;margin-top:10px;border:1px solid var(--k-line);background:none;color:var(--k-on);font:600 15px/1 var(--body);transition:border-color .15s}
.cs-more:hover{border-color:var(--k-prim);color:var(--k-prim)}
.cs-rule.b{margin-top:24px}
.cs-perks{display:grid;gap:10px;margin:18px 0 0;padding:0;list-style:none}
.cs-perks li{display:flex;align-items:center;gap:10px;font:500 14px/1.4 var(--body);color:var(--k-on)}
.cs-perks svg{flex:none;color:var(--k-ok)}
.cart-empty{display:flex;flex-direction:column;align-items:center;max-width:520px;margin:0 auto;padding:36px 8px;text-align:center}
.cart-empty-box{display:grid;place-items:center;width:132px;height:132px;border-radius:32px;background:var(--k-tile);color:var(--k-prim)}
.cart-empty .cart-title{margin-top:28px;font-size:30px}
.cart-empty>p{margin:12px 0 0;font:400 15px/1.6 var(--body);color:var(--k-onv)}
.cart-go,.cart-home{display:inline-flex;align-items:center;justify-content:center;gap:8px;border-radius:12px;font:600 15px/1 var(--body);text-decoration:none}
.cart-go{height:52px;margin-top:28px;padding:0 28px;background:var(--k-prim);color:var(--k-onprim)}
.cart-home{height:44px;margin-top:10px;padding:0 20px;color:var(--k-onv)}
.cart-home:hover{color:var(--k-prim)}
.cart-wait,.cart-failed{margin:0;padding:80px 0;font:400 15px/23px var(--body);color:var(--k-onv);text-align:center}
.cart-dialog{width:min(520px,calc(100% - 48px));padding:24px;border:0;border-radius:24px;background:var(--k-bg);color:var(--k-on);box-shadow:0 24px 60px -20px rgb(15 23 42 / .45)}
.cart-dialog::backdrop{background:rgb(15 23 42 / .5)}
.cart-dialog h2{margin:0;font:600 22px/1.3 var(--head);color:var(--k-on)}
.cart-dialog p{margin:12px 0 0;font:400 15px/1.5 var(--body);color:var(--k-onv)}
.cart-dialog-acts{display:flex;justify-content:flex-end;gap:8px;margin-top:24px}
.cart-dialog-acts button{height:44px;padding:0 18px;border:0;border-radius:12px;font:600 15px/1 var(--body);cursor:pointer}
.cart-dialog-no{background:none;color:var(--k-on)}
.cart-dialog-no:hover{background:var(--k-soft)}
.cart-dialog-yes{background:var(--k-err);color:#fff}
.cart-toast{position:fixed;left:50%;bottom:calc(20px + env(safe-area-inset-bottom,0px));z-index:30;margin:0;padding:12px 18px;border-radius:12px;transform:translateX(-50%);background:var(--k-on);color:var(--k-bg);font:500 14px/20px var(--body);box-shadow:0 12px 30px -12px rgb(15 23 42 / .5);white-space:nowrap}
@media (max-width:979.98px){
.cart-in{margin-block:24px 48px}
.cart-full{display:block}
.cart-sum{position:static;margin-top:28px;padding:22px}
.cart-title{font-size:30px}
.cart-lines{margin-top:22px}
.cl{gap:14px;padding-block:16px}
.cl-shot{width:96px;height:96px;padding:8px;border-radius:14px}
.cl-title{font-size:16px}
.cl-buy{flex-wrap:wrap;gap:10px}
.cl-each.m{display:block}
.cl-each.d{display:none}
.cl-sub{display:flex;flex-direction:column;align-items:flex-end}
.cart-more{margin-top:28px;padding:22px 16px}
.cm-title{font-size:21px}
.cm-row{grid-auto-flow:column;grid-template-columns:none;grid-auto-columns:minmax(260px,82%);overflow-x:auto;scroll-snap-type:x mandatory;scrollbar-width:none;margin-inline:-16px;padding:2px 16px 4px;scroll-padding-inline:16px}
.cm-row::-webkit-scrollbar{display:none}
.cm{scroll-snap-align:start}
}
@media (max-width:759.98px){.cart-in{width:calc(100% - 32px)}}
''';
