import 'package:vinabike_public_core/modules/website/theme/website_theme_roles.dart';

/// `/pedido/<id>` with Flutter's `OrderConfirmationPage` sizes (measured
/// 2026-10-06 at 1440 and 412 px). That page draws with its own colors, not
/// the editor theme's roles — the logo blue hero, warm lines and surfaces,
/// one accent per payment state — so these are the same literals; only the
/// note under the PDF button takes the theme's `onSurfaceVariant`. Its text
/// leaves `fontFamily` to the theme: the body font, bold. Line heights are
/// the whole pixels Flutter lays out (15 px at 1.5 is a 23 px line). Under
/// 980 px the summary goes first; under 820 px of content the hero stacks;
/// under 760 the side margin is 16.
String orderPageCss(WebsiteThemeRoles theme) =>
    '''
:root{--o-blue:#093357;--o-line:#e8e2d8;--o-warm:rgb(247 244 238 / .56);--o-soft:rgb(252 251 248 / .62);--o-ink:rgb(0 0 0 / .87);--o-text:#1e293b;--o-sec:#64748b;--o-onv:${theme.onSurfaceVariant.css};--o-accent:#10b981}
.od-page{position:relative}
.od-page [hidden]{display:none!important}
.od-in{width:min(1320px,calc(100% - 48px));margin:44px auto;container:od/inline-size}
.od-hero{--o-accent:#10b981;padding:42px 34px;background:var(--o-blue);color:#fff}
.od-hero[data-tone=cancelled]{--o-accent:#b45309}
.od-hero[data-tone=failed]{--o-accent:#dc2626}
.od-hero[data-tone=pending]{--o-accent:#f59e0b}
.od-hero[data-tone=transfer]{--o-accent:#093357}
.od-hero-top{display:flex;align-items:flex-end;gap:44px}
.od-hero-text{flex:1;min-width:0}
.od-kick{display:flex;align-items:center;gap:12px}
.od-kick-ic{flex:none;display:grid;place-items:center;width:34px;height:34px;border-radius:50%;background:var(--o-accent);color:#fff}
.od-kick>span:last-child{font:800 12px/18px var(--body);letter-spacing:1.4px;color:rgb(255 255 255 / .78)}
.od-title{margin:28px 0 0;font:700 52px/51px var(--body);letter-spacing:.25px;color:#fff}
.od-sub{margin:18px 0 0;font:400 16px/25px var(--body);letter-spacing:.25px;color:rgb(255 255 255 / .78)}
.od-card{flex:none;display:flex;flex-direction:column;box-sizing:border-box;width:360px;padding:24px;border:1px solid rgb(255 255 255 / .16);background:rgb(255 255 255 / .08)}
.od-card-store{display:-webkit-box;-webkit-box-orient:vertical;-webkit-line-clamp:2;overflow:hidden;font:800 11px/16px var(--body);letter-spacing:1.1px;color:rgb(255 255 255 / .68)}
.od-card-label{margin-top:12px;font:800 12px/18px var(--body);letter-spacing:1.3px;color:rgb(255 255 255 / .68)}
.od-card-number{margin-top:10px;font:700 34px/33px var(--body);letter-spacing:.25px;color:#fff;overflow-wrap:anywhere}
.od-card-rule{display:block;height:1px;margin:18px 0;background:rgb(255 255 255 / .16)}
.od-fact{display:flex;justify-content:space-between;align-items:flex-start;gap:20px}
.od-fact+.od-fact{margin-top:12px}
.od-fact span{font:800 12px/18px var(--body);letter-spacing:.9px;color:rgb(255 255 255 / .62)}
.od-fact b{min-width:0;font:700 14px/19px var(--body);letter-spacing:.25px;text-align:right;color:#fff}
.od-status{display:flex;align-items:flex-start;gap:12px;margin:28px 0 0;padding:14px 16px;border-left:3px solid var(--o-accent);background:rgb(255 255 255 / .08)}
.od-status-ic{flex:none;display:flex;color:var(--o-accent)}
.od-status>span:last-child{flex:1;min-width:0;font:700 14px/20px var(--body);letter-spacing:.25px;color:#fff}
.od-grid{display:grid;grid-template-columns:minmax(0,7fr) minmax(0,4fr);align-items:start;column-gap:28px;margin-top:32px}
.od-main{display:flex;flex-direction:column;gap:24px;min-width:0}
.od-sec,.od-sum{padding:24px;border-block:1px solid var(--o-line)}
.od-sec{background:var(--o-soft)}
.od-sec-title{margin:0 0 18px;font:700 24px/36px var(--body);letter-spacing:.25px;color:var(--o-ink)}
.od-rows{margin:0}
.od-row{display:flex;align-items:flex-start;gap:12px;padding:14px 0;border-bottom:1px solid var(--o-line)}
.od-row:last-child{border-bottom-color:transparent}
.od-row dt{flex:none;width:140px;font:700 12px/18px var(--body);letter-spacing:.7px;color:var(--o-sec)}
.od-row dd{flex:1;min-width:0;margin:0;font:600 15px/23px var(--body);letter-spacing:.25px;color:var(--o-ink);overflow-wrap:anywhere}
.od-rows.pay .od-row{padding:12px 0}
.od-rows.pay .od-row dd{line-height:22px}
.od-lead{margin:0 0 16px;font:400 14px/21px var(--body);letter-spacing:.25px;color:var(--o-ink)}
.od-note{margin:14px 0 0;font:400 12px/18px var(--body);letter-spacing:.25px;color:var(--o-sec)}
.od-items,.od-steps{margin:0;padding:0;list-style:none}
.od-item{display:flex;align-items:flex-start;gap:16px;padding:14px 0;border-bottom:1px solid var(--o-line)}
.od-item:last-child,.od-step:last-child{border-bottom-color:transparent}
.od-item-text{flex:1;min-width:0}
.od-item-name{display:block;font:600 14px/20px var(--body);letter-spacing:.25px;color:var(--o-ink);overflow-wrap:anywhere}
.od-item-sku{display:block;margin-top:4px;font:400 12px/18px var(--body);letter-spacing:.25px;color:var(--o-sec)}
.od-item-qty{flex:none;font:700 13px/20px var(--body);letter-spacing:.25px;color:var(--o-sec)}
.od-item-price{flex:none;font:700 14px/21px var(--body);letter-spacing:.25px;color:var(--o-ink);white-space:nowrap}
.od-step{display:flex;align-items:flex-start;gap:12px;padding:14px 0;border-bottom:1px solid var(--o-line);font:600 14px/21px var(--body);letter-spacing:.25px;color:var(--o-ink)}
.od-step::before{content:"";flex:none;width:7px;height:7px;margin-top:7px;border-radius:50%;background:var(--o-blue)}
.od-sum{background:var(--o-warm);min-width:0}
.od-sum-title{margin:0;font:700 32px/48px var(--body);letter-spacing:.25px;color:var(--o-ink)}
.od-sum-number{display:block;margin-top:14px;font:700 34px/32px var(--body);letter-spacing:.25px;color:var(--o-blue);overflow-wrap:anywhere}
.od-pills{display:flex;flex-wrap:wrap;gap:8px;margin-top:12px}
.od-pill{--o-tone:var(--o-blue);padding:6px 9px;border-radius:999px;background:color-mix(in srgb,var(--o-tone) 8%,transparent);font:700 10px/15px var(--body);letter-spacing:.8px;color:var(--o-tone)}
.od-metrics{display:flex;flex-direction:column;gap:12px;margin-top:18px}
.od-metric{display:flex;justify-content:space-between;gap:16px;font:400 15px/23px var(--body);letter-spacing:.25px;color:var(--o-text)}
.od-metric b{font-weight:700;color:var(--o-ink);white-space:nowrap}
.od-metric.sec,.od-metric.sec b{color:var(--o-sec)}
.od-rule{display:block;height:1px;margin-top:18px;background:var(--o-line)}
.od-rule.b{margin-top:26px}
.od-total{display:flex;justify-content:space-between;align-items:flex-end;gap:16px;margin-top:18px}
.od-total span{font:700 13px/20px var(--body);letter-spacing:.8px;color:var(--o-sec)}
.od-total b{font:700 44px/42px var(--body);letter-spacing:.25px;color:var(--o-blue);white-space:nowrap}
.od-acts{display:flex;flex-direction:column;margin-top:26px}
.od-btn{position:relative;display:flex;align-items:center;justify-content:center;gap:8px;box-sizing:border-box;width:100%;margin:12px 0 0;padding:0 16px;border-radius:6px;font:600 14px/20px var(--body);letter-spacing:.1px;text-decoration:none;cursor:pointer}
.od-acts>.od-btn:first-child,.od-acts>[hidden]+.od-btn{margin-top:0}
.od-btn.fill{height:48px;border:0;background:var(--o-blue);color:#fff}
.od-btn.fill:hover:not(:disabled){background:linear-gradient(rgb(255 255 255 / .08),rgb(255 255 255 / .08)),var(--o-blue)}
.od-btn.line{height:44px;border:1px solid var(--o-blue);background:none;color:var(--o-blue)}
.od-btn.line:hover:not(:disabled){background:color-mix(in srgb,var(--o-blue) 8%,transparent)}
.od-btn:disabled{cursor:default}
.od-btn.fill:disabled{background:color-mix(in srgb,var(--o-text) 12%,transparent);color:color-mix(in srgb,var(--o-text) 38%,transparent)}
.od-btn.line:disabled{border-color:color-mix(in srgb,var(--o-text) 12%,transparent);color:color-mix(in srgb,var(--o-text) 38%,transparent)}
.od-btn-ic{display:flex}
.od-btn.busy .od-btn-ic{display:none}
.od-doc{margin:6px 0 0;font:400 14px/21px var(--body);letter-spacing:.25px;text-align:center;color:var(--o-onv)}
.od-doc+.od-btn{margin-top:12px}
.od-foot{margin:18px 0 0;font:600 14px/21px var(--body);letter-spacing:.25px;color:var(--o-ink)}
.od-spin{width:18px;height:18px;box-sizing:border-box;border:2px solid currentColor;border-right-color:transparent;border-radius:50%;animation:od-turn .8s linear infinite}
@keyframes od-turn{to{transform:rotate(360deg)}}
.od-warn{display:flex;align-items:flex-start;gap:10px;box-sizing:border-box;width:min(1320px,calc(100% - 32px));margin:20px auto 0;padding:14px 16px;border:1px solid #f59e0b;border-radius:8px;background:#fff7ed;color:#92400e}
.od-warn>svg{flex:none}
.od-warn>div{flex:1;min-width:0}
.od-warn p{margin:0;font:600 16px/22px var(--body);letter-spacing:.25px;color:#78350f}
.od-warn-acts{display:flex;flex-wrap:wrap;gap:8px;margin-top:10px}
.od-warn-cart,.od-warn-ok{display:inline-flex;align-items:center;justify-content:center;gap:8px;box-sizing:border-box;height:44px;padding:0 20px;border-radius:6px;font:600 14px/20px var(--body);letter-spacing:.1px;color:#78350f;text-decoration:none;cursor:pointer}
.od-warn-cart{padding:0 19px;border:1px solid #b45309;background:none}
.od-warn-ok{padding:0 20px;border:0;background:none}
.od-warn-cart:hover,.od-warn-ok:hover:not(:disabled){background:rgb(120 53 15 / .08)}
.od-warn-ok:disabled{color:rgb(30 41 59 / .38);cursor:default}
.od-warn-ok .od-spin{width:16px;height:16px}
.od-load{display:grid;place-items:center;min-height:200px;margin:44px 0}
.od-load img,.od-load-name{width:200px;height:200px;object-fit:contain;animation:od-pulse 1.2s ease-in-out infinite alternate}
.od-load-name{display:grid;place-items:center;font:700 24px/1.2 var(--body);color:var(--o-blue);text-align:center}
@keyframes od-pulse{from{transform:scale(.95);opacity:.6}to{transform:scale(1.05);opacity:1}}
.od-state{--o-state:#093357;display:flex;flex-direction:column;align-items:center;box-sizing:border-box;width:min(560px,calc(100% - 48px));margin:44px auto;padding:36px 8px;text-align:center}
.od-state.err{--o-state:#b91c1c}
.od-state-box{display:grid;place-items:center;box-sizing:border-box;width:148px;height:148px;border:1px solid color-mix(in srgb,var(--o-state) 20%,transparent);background:color-mix(in srgb,var(--o-state) 8%,transparent);color:var(--o-state)}
.od-state-title{margin:32px 0 0;font:700 32px/32px var(--body);letter-spacing:.25px;text-transform:uppercase;color:#000}
.od-state-bar{display:block;width:72px;height:2px;margin-top:10px;background:#000}
.od-state>p{margin:16px 0 0;font:400 15px/24px var(--body);letter-spacing:.25px;color:var(--o-sec)}
.od-go{display:inline-flex;align-items:center;justify-content:center;height:48px;margin-top:32px;padding:0 30px;border-radius:6px;background:var(--o-blue);color:#fff;font:600 14px/20px var(--body);letter-spacing:.1px;text-decoration:none}
.od-go:hover{background:linear-gradient(rgb(255 255 255 / .08),rgb(255 255 255 / .08)),var(--o-blue)}
.od-noscript{margin:0;padding:80px 16px;font:400 15px/23px var(--body);color:var(--o-sec);text-align:center}
.od-toast{position:fixed;left:0;right:0;bottom:0;z-index:30;margin:0;padding:14px 16px;background:#323232;color:#fff;font:400 14px/20px var(--body)}
.od-toast.bad{background:#f44336}
.od-btn:focus-visible,.od-go:focus-visible,.od-warn-cart:focus-visible,.od-warn-ok:focus-visible{outline:2px solid var(--o-blue);outline-offset:2px}
@container od (max-width:819.98px){
.od-hero{padding:32px 22px}
.od-hero-top{flex-direction:column;align-items:stretch;gap:28px}
.od-card{width:auto}
}
@media (max-width:979.98px){
.od-in{margin-block:28px}
.od-grid{display:flex;flex-direction:column;gap:24px}
.od-sum{order:-1}
}
@media (max-width:759.98px){.od-in{width:calc(100% - 32px)}.od-state{width:calc(100% - 32px)}}
''';
