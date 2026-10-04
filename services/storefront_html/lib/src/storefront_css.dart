/// The storefront's stylesheet. Colors come from the editor's theme
/// (`theme_primary_color`, `theme_accent_color`); the fonts and the logo are
/// the ones Firebase Hosting already serves for the Flutter store.
///
/// Header, footer and theme are drawn twice (here and in Flutter) only until
/// phase 2 moves the editor canvas to this renderer.
String storefrontCss({required String primary, required String accent}) =>
    '''
@font-face{font-family:Oswald;src:url(/assets/assets/fonts/Oswald-wght.ttf) format("truetype");font-weight:200 700;font-display:swap}
@font-face{font-family:Barlow;src:url(/assets/assets/fonts/Barlow-Regular.ttf) format("truetype");font-weight:400;font-display:swap}
@font-face{font-family:Barlow;src:url(/assets/assets/fonts/Barlow-Medium.ttf) format("truetype");font-weight:500;font-display:swap}
@font-face{font-family:Barlow;src:url(/assets/assets/fonts/Barlow-SemiBold.ttf) format("truetype");font-weight:600;font-display:swap}
@font-face{font-family:Barlow;src:url(/assets/assets/fonts/Barlow-Bold.ttf) format("truetype");font-weight:700;font-display:swap}
:root{--primary:$primary;--accent:$accent;--ink:#141b24;--muted:#5a6878;--line:#e2e7ee;--soft:#f4f6f9;--ok:#14804a;--bad:#b42318;--r:14px;
--head:Oswald,"Arial Narrow",Arial,sans-serif;--body:Barlow,"Segoe UI",Roboto,Arial,sans-serif}
*{box-sizing:border-box}html{-webkit-text-size-adjust:100%}
body{margin:0;background:#fff;color:var(--ink);font:400 17px/1.55 var(--body)}
img{max-width:100%;display:block}a{color:var(--primary)}
.wrap{max-width:1280px;margin:0 auto;padding-inline:24px}
.skip{position:absolute;left:-999px}.skip:focus{left:16px;top:8px;z-index:9;background:#fff;padding:8px 12px}
.sr{position:absolute;width:1px;height:1px;overflow:hidden;clip:rect(0 0 0 0)}
.top{position:sticky;top:0;z-index:5;background:rgba(255,255,255,.94);backdrop-filter:saturate(1.4) blur(10px);border-bottom:1px solid var(--line)}
.bar{display:flex;align-items:center;gap:28px;height:68px}
.logo img{height:34px;width:auto}
.menu{flex:1}.menu-toggle{position:absolute;opacity:0;pointer-events:none}.menu-button{display:none}
.menu nav>ul{display:flex;gap:26px;list-style:none;margin:0;padding:0}
.menu nav>ul>li{position:relative}
.menu nav>ul>li>a{display:block;padding:22px 0;font:500 14px/1 var(--body);letter-spacing:.08em;text-transform:uppercase;color:var(--ink);text-decoration:none}
.menu nav>ul>li>a:hover{color:var(--primary)}
.has-sub>a::after{content:"";display:inline-block;width:6px;height:6px;margin-left:7px;border:solid currentColor;border-width:0 1.6px 1.6px 0;transform:translateY(-3px) rotate(45deg)}
.sub{display:none;position:absolute;top:100%;left:-18px;min-width:220px;list-style:none;margin:0;padding:10px;background:#fff;border:1px solid var(--line);border-radius:12px;box-shadow:0 18px 40px rgba(20,27,36,.12)}
.has-sub:hover .sub,.has-sub:focus-within .sub{display:block}
.sub a{display:block;padding:8px 10px;border-radius:8px;color:var(--ink);text-decoration:none;font-size:15px}.sub a:hover{background:var(--soft)}
.tools{display:flex;align-items:center;gap:18px;color:var(--ink)}.tools a{color:inherit;display:flex}
.login{border:1px solid var(--line);border-radius:999px;padding:8px 14px;font:600 13px/1 var(--body);letter-spacing:.06em;text-transform:uppercase;text-decoration:none}
.crumbs ol{display:flex;flex-wrap:wrap;gap:6px;list-style:none;margin:0;padding:18px 0 6px;font-size:14px;color:var(--muted)}
.crumbs li+li::before{content:"/";margin-right:6px;color:#b6c0cc}
.crumbs a{color:var(--muted);text-decoration:none}.crumbs a:hover{color:var(--primary);text-decoration:underline}
.crumbs [aria-current] span{color:var(--ink)}
.product{display:grid;grid-template-columns:minmax(0,1.15fr) minmax(0,1fr);gap:56px;padding-block:18px 56px;align-items:start}
.stage{margin:0;background:var(--soft);border-radius:var(--r);aspect-ratio:1/1;display:grid;place-items:center;overflow:hidden}
.stage img{width:100%;height:100%;object-fit:contain;mix-blend-mode:multiply;padding:6%}
.thumbs{display:flex;gap:10px;list-style:none;margin:12px 0 0;padding:0;overflow-x:auto}
.thumbs button{border:1.5px solid transparent;border-radius:10px;padding:0;background:var(--soft);cursor:pointer;width:76px;height:76px}
.thumbs button[aria-current]{border-color:var(--primary)}
.thumbs img{width:100%;height:100%;object-fit:contain;mix-blend-mode:multiply}
.buy{position:sticky;top:92px}
.brand{margin:0 0 8px;font:600 13px/1 var(--body);letter-spacing:.16em;text-transform:uppercase;color:var(--accent)}
h1{margin:0;font:600 clamp(28px,3.1vw,40px)/1.06 var(--head);text-transform:uppercase;letter-spacing:.01em;text-wrap:balance}
.ids{display:flex;gap:16px;flex-wrap:wrap;margin:12px 0 0;color:var(--muted);font-size:14px}
.price-row{margin:26px 0 6px;display:flex;align-items:baseline;gap:14px;flex-wrap:wrap}
.price{margin:0;font:600 42px/1 var(--head);color:var(--primary);font-variant-numeric:tabular-nums}
.tax{margin:0;color:var(--muted);font-size:14px}
.stock{display:inline-flex;align-items:center;gap:8px;margin:6px 0 0;font-weight:600;font-size:15px}
.stock span{width:8px;height:8px;border-radius:50%;background:currentColor}
.stock.ok{color:var(--ok)}.stock.out{color:var(--bad)}
.highlights{display:grid;grid-template-columns:1fr 1fr;gap:1px;margin:24px 0 0;background:var(--line);border:1px solid var(--line);border-radius:12px;overflow:hidden}
.highlights div{background:#fff;padding:14px 16px}
.highlights dt{font-size:13px;color:var(--muted)}.highlights dd{margin:2px 0 0;font-weight:700;font-size:16px}
.to-sheet{display:inline-block;margin-top:10px;font-weight:600;font-size:15px}
.cart{display:flex;gap:12px;margin-top:26px}
.qty input{width:84px;height:54px;border:1px solid var(--line);border-radius:12px;font:600 17px var(--body);text-align:center}
button.primary{flex:1;height:54px;border:0;border-radius:12px;background:var(--primary);color:#fff;font:600 15px/1 var(--body);letter-spacing:.08em;text-transform:uppercase;cursor:pointer}
button.primary:hover{filter:brightness(1.12)}button.primary:disabled{background:#c7cfd9;cursor:not-allowed}
button.primary:focus-visible,.secondary:focus-visible,a:focus-visible{outline:3px solid var(--accent);outline-offset:2px}
.cart-note{margin:8px 0 0;font-size:14px;color:var(--muted)}
.secondary{display:flex;align-items:center;justify-content:center;height:50px;margin-top:10px;border:1.5px solid var(--primary);border-radius:12px;color:var(--primary);font:600 14px/1 var(--body);letter-spacing:.08em;text-transform:uppercase;text-decoration:none}
.promises{list-style:none;margin:26px 0 0;padding:0;border-top:1px solid var(--line)}
.promises li{display:grid;gap:2px;padding:14px 0;border-bottom:1px solid var(--line);font-size:15px}
.promises span{color:var(--muted)}
.details{padding-block:56px;border-top:1px solid var(--line)}
h2{margin:0 0 26px;font:600 30px/1.1 var(--head);text-transform:uppercase;letter-spacing:.02em}
.description{max-width:70ch;margin-bottom:34px;font-size:18px}.description p{margin:0 0 14px}
.sheet{columns:2 420px;column-gap:48px}
.group{break-inside:avoid;margin-bottom:30px}
.group h3{margin:0 0 6px;font:600 14px/1 var(--body);letter-spacing:.14em;text-transform:uppercase;color:var(--accent)}
.group dl{margin:0}.group dl div{display:grid;grid-template-columns:minmax(150px,40%) 1fr;gap:16px;padding:12px 0;border-bottom:1px solid var(--line)}
.group dt{color:var(--muted)}.group dt small{display:block;font-size:13px;color:#8693a3;margin-top:2px}
.group dd{margin:0;font-weight:600}.detail{font-weight:400;color:var(--muted)}
.related{padding-block:48px 64px;border-top:1px solid var(--line)}
.related-head{display:flex;align-items:baseline;justify-content:space-between;gap:16px}
.related-head a{font-weight:600}
.related ul{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:22px;list-style:none;margin:0;padding:0}
.related li a{display:grid;gap:8px;color:var(--ink);text-decoration:none}
.related img{aspect-ratio:1/1;object-fit:contain;background:var(--soft);border-radius:12px;padding:10%;mix-blend-mode:multiply;width:100%}
.related .name{font-weight:600;line-height:1.3;display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;overflow:hidden}
.related .p{color:var(--primary);font:600 18px var(--head)}
.foot{background:var(--primary);color:#dfe7f1;padding-top:52px;margin-top:8px}
.foot .cols{display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:36px}
.foot p{margin:0 0 6px}.foot a{color:#fff;text-decoration:none}.foot a:hover{text-decoration:underline}
.foot-name{font:600 24px var(--head);color:#fff;text-transform:uppercase}
.foot-title{font:600 13px/1 var(--body)!important;letter-spacing:.14em;text-transform:uppercase;color:#9fb4cc;margin-bottom:12px!important}
.foot ul{list-style:none;margin:0;padding:0;display:grid;gap:8px}
.hours{margin:0;display:grid;gap:6px}.hours div{display:flex;justify-content:space-between;gap:12px}.hours dd{margin:0;color:#fff}
.legal{margin:40px auto 0!important;padding-block:18px;border-top:1px solid rgba(255,255,255,.14);font-size:13px;color:#9fb4cc}
.buybar{display:none}
.logo-name{font:600 24px var(--head);text-transform:uppercase;color:var(--ink)}
@media (min-width:761px){.nav-no-desktop{display:none!important}}
@media (max-width:760px){.nav-no-mobile{display:none!important}}
@media (max-width:980px){
.product{grid-template-columns:1fr;gap:26px}.buy{position:static}
.related ul{grid-template-columns:repeat(2,minmax(0,1fr))}
}
@media (max-width:760px){
body{font-size:16px}.wrap{padding-inline:16px}
.bar{gap:12px;height:60px}.logo{order:1;margin-right:auto}.logo img{height:28px}.tools{order:2;gap:14px}.tools .login{display:none}
.crumbs ol{flex-wrap:nowrap;overflow-x:auto;white-space:nowrap;scrollbar-width:none;padding-top:12px}.crumbs [aria-current]{display:none}
.menu-button{order:3;display:grid;gap:4px;width:28px;cursor:pointer}
.menu-button span{height:2px;background:var(--ink);border-radius:2px}
.menu-toggle:focus-visible+.menu-button{outline:3px solid var(--accent);outline-offset:4px}
.menu{display:none;position:fixed;inset:60px 0 auto;max-height:calc(100vh - 60px);overflow:auto;background:#fff;border-bottom:1px solid var(--line);padding:8px 16px 20px}
.menu-toggle:checked~.menu{display:block}
.menu nav>ul{flex-direction:column;gap:0}.menu nav>ul>li>a{padding:14px 0;border-bottom:1px solid var(--line)}
.sub{position:static;display:block;border:0;box-shadow:none;padding:0 0 8px 12px}.has-sub>a::after{display:none}
.price{font-size:36px}.sheet{columns:1}.group dl div{grid-template-columns:1fr;gap:2px}
.buybar{display:flex;position:fixed;left:0;right:0;bottom:0;z-index:6;gap:14px;align-items:center;padding:10px 16px calc(10px + env(safe-area-inset-bottom,0px));background:#fff;border-top:1px solid var(--line);box-shadow:0 -10px 30px rgba(20,27,36,.08)}
.buybar span{font:600 24px var(--head);color:var(--primary)}.buybar button{height:48px}
body{padding-bottom:76px}
}
''';
