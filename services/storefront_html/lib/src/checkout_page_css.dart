import 'package:vinabike_public_core/modules/website/theme/website_theme_roles.dart';

/// `/checkout` on the editor theme's roles like the cart, with the store's
/// new look since 2026-10-24 (titles as written, each section a card on the
/// page surface, the summary in its own card, the photos on the products'
/// tile); the fields keep Flutter's `CheckoutPage` sizes (measured
/// 2026-10-06 at 1440 and 412 px), outline variant for every line. The store
/// theme's visual density (−1) takes 4 px off fields, radios and checkboxes
/// and 4 px of padding off each side of a button: a field is 18 + 27 + 18 −
/// 4 = 59 px, a radio 36. Field text is the theme's `bodyLarge` (18 px),
/// labels its `bodyMedium` (16 px). Under 980 px the summary goes below the
/// form; under 760 the side margin is 16; under 640 address fields stack.
/// Flutter rounds each line of a paragraph to whole pixels (15 × 1.55 is a
/// 23 px line, 13 × 1.45 a 19 px one): the line heights here are rounded.
String checkoutPageCss(WebsiteThemeRoles theme) =>
    '''
:root{--k-tile:color-mix(in srgb,${theme.primary.css} 6%,${theme.background.css});--k-bg:${theme.background.css};--k-soft:${theme.surfaceContainerLow.css};--k-raised:${theme.surfaceContainer.css};--k-high:${theme.surfaceContainerHigh.css};--k-line:${theme.outlineVariant.css};--k-on:${theme.onSurface.css};--k-onv:${theme.onSurfaceVariant.css};--k-prim:${theme.primary.css};--k-onprim:${theme.onPrimary.css};--k-muted:color-mix(in srgb,var(--k-on) 58%,transparent);--k-dis:color-mix(in srgb,var(--k-on) 38%,transparent);--k-err:#ef4444;--k-warn:#f59e0b;--k-warnbg:color-mix(in srgb,#f59e0b 12%,var(--k-bg));--k-onwarn:#17211b}
.co-page{background:var(--k-bg)}
.co-page .sr{position:absolute;width:1px;height:1px;margin:-1px;padding:0;overflow:hidden;clip:rect(0 0 0 0);white-space:nowrap;border:0}
.co-in{width:min(1240px,calc(100% - 48px));margin:40px auto 72px}
.co-full{display:grid;grid-template-columns:minmax(0,1fr) minmax(0,400px);align-items:start;column-gap:48px}
.co-main{min-width:0}
.co-title{margin:0;font:600 36px/1.15 var(--head);letter-spacing:-.01em;color:var(--k-on);text-wrap:balance}
.co-lead{margin:8px 0 0;font:400 15px/23px var(--body);color:var(--k-onv)}
.co-form{margin-top:28px}
.co-sec{padding:28px;border:1px solid var(--k-line);border-radius:20px;background:var(--k-bg);container-type:inline-size}
.co-sec+.co-sec{margin-top:16px}
.co-sec-title{margin:0 0 20px;font:600 22px/1.25 var(--head);letter-spacing:-.01em;color:var(--k-on)}
.co-stack{display:grid;gap:18px}
/* Fields: Material's outlined, filled field. The label rests in the
   middle and floats onto the border, which opens for it (the legend). */
.co-f{position:relative;min-width:0}
.co-f-box{position:relative;border-radius:12px;background:var(--k-bg)}
.co-f-box:hover{background:color-mix(in srgb,var(--k-on) 4%,var(--k-bg))}
.co-f-ic{position:absolute;left:14px;top:19.5px;display:flex;color:var(--k-onv);pointer-events:none}
.co-f input,.co-f textarea,.co-f select{position:relative;display:block;box-sizing:border-box;width:100%;height:59px;margin:0;padding:16px 16px 16px 48px;border:0;border-radius:12px;background:transparent;font:400 18px/27px var(--body);letter-spacing:.5px;color:var(--k-on);outline:0;-webkit-appearance:none;appearance:none}
.co-f input::placeholder,.co-f textarea::placeholder{color:var(--k-onv);opacity:0;transition:opacity .15s}
.co-f input:focus::placeholder,.co-f textarea:focus::placeholder{opacity:1}
.co-f input:-webkit-autofill{-webkit-box-shadow:0 0 0 40px var(--k-bg) inset;-webkit-text-fill-color:var(--k-on)}
.co-f textarea{height:140px;padding-top:32px;padding-bottom:12px;resize:vertical}
.co-f.ta .co-f-ic{top:60px}
.co-f select{padding-right:44px;cursor:pointer}
.co-f-caret{position:absolute;right:12px;top:17.5px;display:flex;color:var(--k-onv);pointer-events:none}
.co-f label{position:absolute;left:48px;top:17.5px;z-index:1;max-width:calc(100% - 64px);overflow:hidden;font:400 16px/24px var(--body);letter-spacing:.25px;white-space:nowrap;text-overflow:ellipsis;color:var(--k-onv);pointer-events:none;transform-origin:left top;transition:transform .15s cubic-bezier(.4,0,.2,1),max-width .15s}
.co-f.ta label{top:58px}
.co-f fieldset{position:absolute;inset:-8px 0 0;z-index:0;min-width:0;margin:0;padding:0 0 0 15px;border:1px solid var(--k-line);border-radius:12px;pointer-events:none}
.co-f legend{display:block;height:16px;max-width:0;padding:0;overflow:hidden;font:400 12px/16px var(--body);letter-spacing:.19px;white-space:nowrap;visibility:hidden}
.co-f legend span{display:inline-block;padding:0 4px}
.co-f input:focus~fieldset,.co-f textarea:focus~fieldset,.co-f select:focus~fieldset{border:1.5px solid var(--k-prim);padding-left:14.5px}
.co-f input:focus~label,.co-f input:not(:placeholder-shown)~label,.co-f textarea:focus~label,.co-f textarea:not(:placeholder-shown)~label,.co-f select~label,.co-f.up label{max-width:calc(133% - 40px);transform:translate(-28px,-26.5px) scale(.75)}
.co-f.ta textarea:focus~label,.co-f.ta textarea:not(:placeholder-shown)~label,.co-f.ta.up label{transform:translate(-28px,-67px) scale(.75)}
.co-f input:focus~fieldset legend,.co-f input:not(:placeholder-shown)~fieldset legend,.co-f textarea:focus~fieldset legend,.co-f textarea:not(:placeholder-shown)~fieldset legend,.co-f select~fieldset legend,.co-f.up legend{max-width:100%}
.co-f.bad fieldset{border-color:var(--k-err)}
.co-f.bad input:focus~fieldset,.co-f.bad textarea:focus~fieldset{border:1.5px solid var(--k-err);padding-left:14.5px}
.co-f.bad label,.co-f.bad .co-f-ic{color:var(--k-err)}
.co-f-msg{margin:4px 0 0;padding:0 16px 0 20px;font:400 14px/21px var(--body);letter-spacing:.4px;color:var(--k-onv)}
.co-f-msg:empty{display:none}
.co-f.bad .co-f-msg{color:var(--k-err)}
.co-f-eye{position:absolute;right:0;top:5.5px;z-index:2;display:grid;place-items:center;width:48px;height:48px;padding:0;border:0;border-radius:50%;background:none;color:var(--k-onv);cursor:pointer}
.co-f-eye:hover{background:color-mix(in srgb,var(--k-on) 8%,transparent)}
.co-f.pw input{padding-right:52px}
/* Checkbox and radio, Material's 18 and 20 px marks in 36 px targets. */
.co-check{display:flex;align-items:center;gap:0;cursor:pointer}
.co-check input{position:absolute;opacity:0;width:1px;height:1px;margin:0}
.co-check-mark{position:relative;flex:none;display:grid;place-items:center;width:36px;height:36px;margin-right:18px;border-radius:50%}
.co-check-mark::before{content:"";width:14px;height:14px;border:2px solid var(--k-on);border-radius:2px}
.co-check:hover .co-check-mark{background:color-mix(in srgb,var(--k-on) 8%,transparent)}
.co-check input:focus-visible+.co-check-mark{background:color-mix(in srgb,var(--k-on) 10%,transparent)}
.co-check input:checked+.co-check-mark::before{border-color:var(--k-prim);background:var(--k-prim) url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24'%3E%3Cpath fill='none' stroke='white' stroke-width='3' d='M5 12.5l4.5 4.5L19 7.5'/%3E%3C/svg%3E") center/14px no-repeat}
.co-check-text{flex:1;min-width:0;padding-block:8px}
.co-check-text b{display:block;font:700 16px/24px var(--body);letter-spacing:.25px;color:var(--k-on)}
.co-check-text span{display:block;font:400 16px/24px var(--body);letter-spacing:.25px;color:var(--k-onv)}
.co-box{padding:18px;border:1px solid var(--k-line);border-radius:14px;background:var(--k-bg)}
.co-box .co-stack{gap:14px;margin-top:14px}
.co-box .co-stack:empty,.co-box [hidden]+.co-stack{margin-top:0}
.co-opts{margin:0;padding:0;border:0}
.co-opt{display:flex;align-items:flex-start;padding:14px 0;border-bottom:1px solid var(--k-line);cursor:pointer}
.co-opt:last-child{border-bottom-color:transparent}
.co-opt input{position:absolute;opacity:0;width:1px;height:1px;margin:0}
.co-radio{position:relative;flex:none;display:grid;place-items:center;width:36px;height:36px;border-radius:50%}
.co-radio::before{content:"";box-sizing:border-box;width:20px;height:20px;border:2px solid var(--k-onv);border-radius:50%}
.co-opt:hover .co-radio{background:color-mix(in srgb,var(--k-on) 8%,transparent)}
.co-opt input:focus-visible+.co-radio{background:color-mix(in srgb,var(--k-prim) 12%,transparent)}
.co-opt input:checked+.co-radio::before{border-color:var(--k-prim);background:radial-gradient(circle,var(--k-prim) 0 5px,transparent 5.5px)}
.co-opt-ic{flex:none;display:flex;margin-left:8px;color:var(--k-onv)}
.co-opt input:checked~.co-opt-ic{color:var(--k-prim)}
.co-opt-body{display:block;flex:1;min-width:0;margin-left:12px}
.co-opt-body.no-ic{margin-left:8px}
.co-opt-title{display:flex;align-items:center;gap:8px;margin:0;font:600 15px/23px var(--body);letter-spacing:.25px;color:var(--k-on)}
.co-opt input:checked~.co-opt-body .co-opt-title{font-weight:700}
.co-opt-sub{display:block;margin:4px 0 0;font:400 13px/19px var(--body);letter-spacing:.4px;color:var(--k-onv)}
.co-pill{padding:4px 8px;border-radius:999px;background:color-mix(in srgb,var(--k-prim) 8%,transparent);font:700 10px/14.5px var(--body);letter-spacing:.7px;color:var(--k-prim)}
.co-ship{margin-top:18px}
.co-hint{margin:8px 0 0;font:400 12px/18px var(--body);letter-spacing:.4px;color:var(--k-onv)}
.co-hint.solo{margin:0}
.co-addr{display:grid;grid-template-columns:minmax(0,1fr) minmax(0,1fr);gap:14px;margin-top:18px}
.co-addr .co-f.half{grid-column:1;width:calc(100% - 1px)}
.co-search{position:relative}
.co-sugs{position:absolute;left:0;right:0;top:63px;z-index:20;max-height:320px;margin:0;padding:8px 0;overflow:auto;list-style:none;border-radius:4px;background:var(--k-bg);box-shadow:0 2px 4px rgb(0 0 0 / .2),0 4px 10px rgb(0 0 0 / .14)}
.co-sugs li{display:flex;align-items:center;gap:16px;min-height:48px;padding:8px 16px;font:400 16px/24px var(--body);letter-spacing:.25px;color:var(--k-on);cursor:pointer}
.co-sugs li[aria-selected=true],.co-sugs li:hover{background:color-mix(in srgb,var(--k-on) 8%,transparent)}
.co-sugs li svg{flex:none;color:var(--k-onv)}
.co-sugs .co-sugs-note{justify-content:center;color:var(--k-onv);cursor:default}
.co-sugs .co-sugs-note:hover{background:none}
.co-label-row{margin-top:16px}
.co-save{margin-top:0}
.co-save .co-check-text{padding-block:6px}
.co-save .co-check-text b{font-weight:400}
.co-manage{display:inline-flex;align-items:center;gap:8px;margin-top:12px;font:600 14px/20px var(--body);letter-spacing:.1px;color:var(--k-prim);text-decoration:none}
.co-pick-head{display:flex;align-items:flex-start;gap:12px}
.co-pick-head svg{flex:none;color:var(--k-prim)}
.co-pick-head b{display:block;font:800 15px/23px var(--body);letter-spacing:.25px;color:var(--k-on)}
.co-pick-head span{display:block;margin-top:4px;font:400 13px/19px var(--body);letter-spacing:.4px;color:var(--k-onv)}
.co-pick-rows{display:grid;gap:10px;margin:16px 0 0}
.co-pick-rows div{display:flex;align-items:flex-start}
.co-pick-rows dt{flex:none;width:128px;margin:0;font:700 12px/17px var(--body);letter-spacing:.5px;color:var(--k-onv)}
.co-pick-rows dd{flex:1;min-width:0;margin:0;font:600 13px/18px var(--body);letter-spacing:.4px;color:var(--k-on)}
.co-pay-warn{padding:12px 14px;border-left:3px solid var(--k-warn);background:var(--k-warnbg);font:400 14px/20px var(--body);letter-spacing:.4px;color:var(--k-onwarn)}
.co-restored{display:flex;align-items:flex-start;gap:14px;padding:20px;border-left:4px solid var(--k-prim);border-radius:0 14px 14px 0;background:var(--k-tile)}
.co-restored svg{flex:none;color:var(--k-prim)}
.co-restored b{display:block;font:800 14px/20px var(--body);letter-spacing:.6px;color:var(--k-prim)}
.co-restored p{margin:6px 0 0;font:400 16px/24px var(--body);letter-spacing:.25px;color:var(--k-onv)}
.co-locked .co-sec{pointer-events:none}
/* The summary. */
.co-sum{position:sticky;top:24px;min-width:0;padding:28px;border:1px solid var(--k-line);border-radius:20px;background:var(--k-bg);box-shadow:0 18px 40px -28px rgb(15 23 42 / .35)}
.co-sum-title{margin:0;font:600 22px/1.25 var(--head);letter-spacing:-.01em;color:var(--k-on)}
.co-frozen{margin:18px 0 -10px;padding:10px 12px;border-radius:10px;background:var(--k-tile);font:800 10px/14.5px var(--body);letter-spacing:.5px;color:var(--k-prim)}
.co-rows{margin:18px 0 0;padding:0;list-style:none}
.co-row{display:flex;align-items:flex-start;gap:12px;padding:14px 0;border-bottom:1px solid var(--k-line)}
.co-row:last-child{border-bottom-color:transparent}
.co-row-shot{flex:none;display:grid;place-items:center;box-sizing:border-box;width:64px;height:64px;padding:8px;border-radius:12px;background:var(--k-tile);color:var(--k-muted)}
.co-row-shot img{width:100%;height:100%;object-fit:contain;mix-blend-mode:multiply}
.co-row-body{flex:1;min-width:0}
.co-row-name{display:-webkit-box;margin:0;overflow:hidden;-webkit-line-clamp:2;-webkit-box-orient:vertical;font:600 14px/20px var(--body);letter-spacing:.25px;color:var(--k-on)}
.co-row-q{margin:6px 0 0;font:400 12px/18px var(--body);letter-spacing:.4px;color:var(--k-onv)}
.co-row-sub{flex:none;margin:0;font:700 14px/21px var(--body);font-variant-numeric:tabular-nums;color:var(--k-on);white-space:nowrap}
.co-rule{height:0;margin:18px 0 0;border:0;border-top:1px solid var(--k-line)}
.co-metric{display:flex;justify-content:space-between;gap:16px;margin:18px 0 0;font:400 15px/23px var(--body);font-variant-numeric:tabular-nums;color:var(--k-on)}
.co-metric+.co-metric,[data-co-amounts]+.co-metric{margin-top:12px}
[data-co-amounts]:empty+.co-metric{margin-top:18px}
.co-metric b{font-weight:700;white-space:nowrap}
.co-metric.sec{color:var(--k-onv)}
.co-warn{margin:18px 0 0;padding:10px 12px;border-left:3px solid var(--k-warn);background:var(--k-warnbg);font:600 13px/19px var(--body);letter-spacing:.4px;color:var(--k-onwarn)}
.co-warn+.co-metric{margin-top:12px}
.co-ship-note{margin:8px 0 0;font:400 12px/17px var(--body);letter-spacing:.4px;color:var(--k-muted)}
.co-progress{position:relative;height:2px;margin-top:12px;overflow:hidden;background:color-mix(in srgb,var(--k-prim) 24%,transparent)}
.co-progress::after{content:"";position:absolute;inset:0 auto 0 0;width:40%;background:var(--k-prim);animation:co-slide 1.2s cubic-bezier(.4,0,.2,1) infinite}
@keyframes co-slide{from{transform:translateX(-100%)}to{transform:translateX(250%)}}
.co-ship-err{display:flex;align-items:flex-start;gap:8px;margin-top:12px;color:var(--k-err)}
.co-ship-err svg{flex:none}
.co-ship-err p{flex:1;margin:0;font:400 13px/18px var(--body);letter-spacing:.4px}
.co-ship-err button{flex:none;height:40px;margin-top:-11px;padding:0 12px;border:0;border-radius:20px;background:none;color:var(--k-prim);font:600 14px/20px var(--body);letter-spacing:.1px;cursor:pointer}
.co-total{display:flex;justify-content:space-between;align-items:baseline;gap:16px;margin:18px 0 0}
.co-total span{font:600 16px/1.3 var(--body);color:var(--k-on)}
.co-total b{font:700 30px/1.1 var(--body);font-variant-numeric:tabular-nums;color:var(--k-on);white-space:nowrap}
.co-recovery{margin:26px 0 -10px;padding:12px 14px;border-left:3px solid var(--k-warn);border-radius:0 10px 10px 0;background:var(--k-warnbg);font:400 13px/19px var(--body);letter-spacing:.4px;color:var(--k-onwarn)}
.co-pay,.co-back{display:flex;align-items:center;justify-content:center;gap:8px;box-sizing:border-box;width:100%;border-radius:12px;text-decoration:none;cursor:pointer}
.co-pay{height:54px;margin-top:24px;border:0;background:var(--k-prim);color:var(--k-onprim);font:700 16px/1 var(--body);transition:filter .15s}
.co-pay:hover:not(:disabled){filter:brightness(1.08)}
.co-pay:disabled{background:color-mix(in srgb,var(--k-on) 12%,transparent);color:var(--k-dis);cursor:default}
.co-pay.busy:disabled{background:var(--k-prim);color:var(--k-onprim)}
.co-spin{width:20px;height:20px;box-sizing:border-box;border:2px solid currentColor;border-right-color:transparent;border-radius:50%;animation:co-turn .8s linear infinite}
@keyframes co-turn{to{transform:rotate(360deg)}}
.co-back{height:48px;margin-top:10px;border:1px solid var(--k-line);background:none;color:var(--k-on);font:600 15px/1 var(--body)}
.co-back:hover{border-color:var(--k-prim);color:var(--k-prim)}
.co-back.off{border-color:color-mix(in srgb,var(--k-on) 12%,transparent);color:var(--k-dis);pointer-events:none}
.co-rule.b{margin-top:26px}
.co-safe{position:relative;margin:18px 0 0;padding-left:19px;font:600 14px/21px var(--body);color:var(--k-on)}
.co-safe::before{content:"";position:absolute;left:0;top:6px;width:7px;height:7px;border-radius:50%;background:var(--k-prim)}
.co-empty{display:flex;flex-direction:column;align-items:center;max-width:560px;margin:0 auto;padding:36px 8px;text-align:center}
.co-empty-box{display:grid;place-items:center;width:132px;height:132px;border-radius:32px;background:var(--k-tile);color:var(--k-prim)}
.co-empty .co-title{margin-top:28px;font-size:30px}
.co-empty>p{margin:12px 0 0;font:400 15px/1.6 var(--body);color:var(--k-onv)}
.co-go{display:inline-flex;align-items:center;justify-content:center;gap:8px;height:52px;margin-top:28px;padding:0 28px;border-radius:12px;background:var(--k-prim);color:var(--k-onprim);font:600 15px/1 var(--body);text-decoration:none}
.co-wait,.co-failed{margin:0;padding:80px 0;font:400 15px/23px var(--body);color:var(--k-onv);text-align:center}
.co-toast{position:fixed;left:50%;bottom:calc(20px + env(safe-area-inset-bottom,0px));z-index:30;max-width:calc(100% - 32px);margin:0;padding:12px 18px;border-radius:12px;transform:translateX(-50%);background:var(--k-on);color:var(--k-bg);font:500 14px/20px var(--body);box-shadow:0 12px 30px -12px rgb(15 23 42 / .5)}
@media (max-width:979.98px){
.co-in{margin-block:24px 48px}
.co-full{display:block}
.co-title{font-size:30px}
.co-form{margin-top:22px}
.co-sec{padding:20px 16px}
.co-sum{position:static;margin-top:24px;padding:22px}
}
@media (max-width:759.98px){.co-in{width:calc(100% - 32px)}}
/* Flutter's LayoutBuilder: two columns from 640 px of section content. */
@container (max-width:639.98px){.co-addr{grid-template-columns:minmax(0,1fr)}.co-addr .co-f.half{width:auto}}
''';
