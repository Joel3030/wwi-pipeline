const fs = require('fs');
const path = require('path');
const { marked } = require('marked');

const dir = __dirname;
const files = fs.readdirSync(dir).filter(f => /^\d\d-.*\.md$/.test(f)).sort();
console.log('Archivos:', files.length);

const md = files.map(f => fs.readFileSync(path.join(dir, f), 'utf8')).join('\n\n');

const used = {};
function slug(text) {
  let s = text.normalize('NFD').replace(/[̀-ͯ]/g, '')
    .toLowerCase().replace(/[^\w\s-]/g, '').trim().replace(/\s+/g, '-');
  if (!s) s = 'seccion';
  if (used[s] !== undefined) { used[s]++; s += '-' + used[s]; } else { used[s] = 0; }
  return s;
}

const toc = [];
const renderer = new marked.Renderer();
renderer.heading = function (token) {
  const d = token.depth;
  const text = this.parser.parseInline(token.tokens);
  const plain = text.replace(/<[^>]+>/g, '');
  const id = slug(plain);
  if (d === 1 || d === 2) toc.push({ depth: d, text: plain, id });
  return `<h${d} id="${id}">${text}</h${d}>\n`;
};
marked.setOptions({ renderer, gfm: true, breaks: false });

let body = marked.parse(md);

// ── Clasificar recuadros por tipo. La distinción ya existe en el contenido;
//    esto solo la hace visible.
const kinds = [
  ['⚠️', 'warn'],   // advertencia
  ['✅', 'good'],         // buena práctica
  ['💡', 'idea'],   // concepto clave
  ['🎓', 'exam'],   // entrevista
  ['➕', 'extra'],        // tema adicional
  ['🔥', 'warn']    // trampa
];
// El marcador vive en los primeros caracteres del recuadro; se inspecciona esa
// ventana y se descarta el marcado intermedio (<p>, <strong>, <em>).
body = body.replace(/<blockquote>/g, (m, offset) => {
  const head = body.slice(offset, offset + 140).replace(/<[^>]*>/g, '');
  for (const [emo, cls] of kinds) {
    if (head.indexOf(emo) !== -1) return `<blockquote class="cx cx-${cls}">`;
  }
  return m;
});

// Envolver tablas para scroll horizontal (sin depender de JS)
body = body.replace(/<table>/g, '<div class="tw"><table>').replace(/<\/table>/g, '</table></div>');

const tocHtml = toc.map(t => `<li class="l${t.depth}"><a href="#${t.id}">${t.text}</a></li>`).join('\n');

const styles = `<style>
:root{
  --paper:#f6f8fa;        /* papel frio, sesgo azul */
  --ink:#161b22;
  --slate:#586374;        /* neutro elegido, no gris puro */
  --slate-soft:#7b8697;
  --rule:#dce2e9;
  --panel:#ffffff;
  --panel-2:#eef2f6;
  --accent:#1f5c8f;       /* azul acero: lenguaje de plano tecnico */
  --accent-wash:#e7eef5;
  --amber:#8a6a1c;        /* semantico: advertencia */
  --amber-wash:#faf3e2;
  --green:#2c6a4b;        /* semantico: buena practica */
  --green-wash:#e9f2ec;
  --violet:#5b4a8a;       /* semantico: entrevista */
  --violet-wash:#eeebf6;
  --code-bg:#eef2f6;
  --shadow:0 1px 2px rgba(22,27,34,.05);

  --serif:Charter,"Bitstream Charter","Iowan Old Style","Source Serif Pro",Georgia,Cambria,serif;
  --sans:ui-sans-serif,"Segoe UI",-apple-system,BlinkMacSystemFont,Roboto,"Helvetica Neue",Arial,sans-serif;
  --mono:ui-monospace,"Cascadia Mono","SF Mono","Segoe UI Mono",Consolas,"Liberation Mono",monospace;

  --measure:38rem;   /* ~65 caracteres con Charter a 17.5px */
}
@media (prefers-color-scheme:dark){
  :root{
    --paper:#11151a; --ink:#dee4ec; --slate:#96a1b2; --slate-soft:#7a8496;
    --rule:#252c35; --panel:#181d24; --panel-2:#1e242c;
    --accent:#6fa8d8; --accent-wash:#182430;
    --amber:#d3a94f; --amber-wash:#241f14;
    --green:#79b894; --green-wash:#152019;
    --violet:#a495d8; --violet-wash:#1c1a26;
    --code-bg:#1a1f27; --shadow:none;
  }
}
:root[data-theme="dark"]{
  --paper:#11151a; --ink:#dee4ec; --slate:#96a1b2; --slate-soft:#7a8496;
  --rule:#252c35; --panel:#181d24; --panel-2:#1e242c;
  --accent:#6fa8d8; --accent-wash:#182430;
  --amber:#d3a94f; --amber-wash:#241f14;
  --green:#79b894; --green-wash:#152019;
  --violet:#a495d8; --violet-wash:#1c1a26;
  --code-bg:#1a1f27; --shadow:none;
}
:root[data-theme="light"]{
  --paper:#f6f8fa; --ink:#161b22; --slate:#586374; --slate-soft:#7b8697;
  --rule:#dce2e9; --panel:#ffffff; --panel-2:#eef2f6;
  --accent:#1f5c8f; --accent-wash:#e7eef5;
  --amber:#8a6a1c; --amber-wash:#faf3e2;
  --green:#2c6a4b; --green-wash:#e9f2ec;
  --violet:#5b4a8a; --violet-wash:#eeebf6;
  --code-bg:#eef2f6; --shadow:0 1px 2px rgba(22,27,34,.05);
}

*,*::before,*::after{box-sizing:border-box}
html{-webkit-text-size-adjust:100%}
@media (prefers-reduced-motion:no-preference){html{scroll-behavior:smooth}}
body{
  margin:0; background:var(--paper); color:var(--ink);
  font-family:var(--serif); font-size:17.5px; line-height:1.7;
  text-rendering:optimizeLegibility;
}
:focus-visible{outline:2px solid var(--accent); outline-offset:2px; border-radius:3px}

/* ── Layout ─────────────────────────────────────── */
.shell{max-width:var(--measure); margin:0 auto; padding:2.75rem 1.15rem 7rem}

/* ── Titulos ────────────────────────────────────── */
h1,h2,h3,h4{font-family:var(--sans); line-height:1.2; text-wrap:balance; font-weight:640}
h1{
  font-size:1.95rem; letter-spacing:-.02em; margin:4rem 0 1.35rem;
  padding-top:1.6rem; border-top:2px solid var(--accent); color:var(--accent);
  scroll-margin-top:1rem;
}
h1:first-of-type{margin-top:.5rem; padding-top:0; border-top:none}
h2{
  font-size:1.34rem; letter-spacing:-.012em; margin:2.9rem 0 .95rem;
  padding-bottom:.4rem; border-bottom:1px solid var(--rule); scroll-margin-top:1rem;
}
h3{font-size:1.05rem; letter-spacing:0; margin:2.1rem 0 .55rem; color:var(--slate)}
h4{font-size:.95rem; margin:1.5rem 0 .45rem; color:var(--slate)}

p{margin:0 0 1.1rem}
ul,ol{margin:0 0 1.1rem; padding-left:1.35rem}
li{margin:.32rem 0}
li>ul,li>ol{margin-top:.32rem; margin-bottom:.32rem}
strong{font-weight:700}
em{font-style:italic}
hr{border:none; border-top:1px solid var(--rule); margin:3.2rem 0}
a{color:var(--accent); text-decoration:none; box-shadow:inset 0 -1px 0 0 color-mix(in srgb,var(--accent) 32%,transparent)}
a:hover{box-shadow:inset 0 -1px 0 0 var(--accent)}

/* ── Codigo y datos ─────────────────────────────── */
code{font-family:var(--mono); font-size:.845em; background:var(--code-bg);
     padding:.1em .34em; border-radius:4px}
pre{
  font-family:var(--mono); background:var(--code-bg); border:1px solid var(--rule);
  border-radius:7px; padding:.95rem 1.05rem; overflow-x:auto; margin:0 0 1.4rem;
  line-height:1.55;
}
pre code{background:none; padding:0; font-size:.795rem; white-space:pre}

.tw{overflow-x:auto; margin:0 0 1.5rem; -webkit-overflow-scrolling:touch;
    border:1px solid var(--rule); border-radius:7px; background:var(--panel)}
table{border-collapse:collapse; width:100%; font-family:var(--sans);
      font-size:.855rem; font-variant-numeric:tabular-nums}
th,td{padding:.52rem .7rem; text-align:left; vertical-align:top;
      border-bottom:1px solid var(--rule)}
th{background:var(--panel-2); font-weight:640; color:var(--ink);
   font-size:.76rem; letter-spacing:.03em; text-transform:uppercase}
tbody tr:last-child td{border-bottom:none}
td code{font-size:.8em}

/* Codigo y tablas respiran mas ancho que el texto */
@media (min-width:860px){
  pre,.tw{margin-inline:-3.2rem; width:calc(100% + 6.4rem)}
  pre{padding-inline:1.5rem}
}

/* ── Recuadros por tipo ─────────────────────────── */
blockquote{
  margin:1.5rem 0; padding:.85rem 1.05rem; border-radius:0 7px 7px 0;
  background:var(--panel); border-left:3px solid var(--slate-soft);
  box-shadow:var(--shadow);
}
blockquote>:last-child{margin-bottom:0}
blockquote.cx-warn {background:var(--amber-wash);  border-left-color:var(--amber)}
blockquote.cx-good {background:var(--green-wash);  border-left-color:var(--green)}
blockquote.cx-idea {background:var(--accent-wash); border-left-color:var(--accent)}
blockquote.cx-exam {background:var(--violet-wash); border-left-color:var(--violet)}
blockquote.cx-extra{background:var(--panel-2);     border-left-color:var(--slate)}
blockquote pre{background:color-mix(in srgb,var(--ink) 6%,transparent)}

/* ── Indice ─────────────────────────────────────── */
#toc{
  background:var(--panel); border:1px solid var(--rule); border-radius:9px;
  padding:1.15rem 1.3rem; margin:2.2rem 0 3.4rem; box-shadow:var(--shadow);
}
#toc>h2{margin:0 0 .7rem; border:none; padding:0; font-size:.78rem;
        letter-spacing:.09em; text-transform:uppercase; color:var(--slate)}
#toc ol{list-style:none; padding:0; margin:0; font-family:var(--sans); font-size:.855rem}
#toc li{margin:.14rem 0; line-height:1.4}
#toc li.l1{margin-top:.75rem; font-weight:650}
#toc li.l1:first-child{margin-top:0}
#toc li.l2{padding-left:1rem; font-size:.8rem; color:var(--slate)}
#toc a{color:inherit; box-shadow:none}
#toc a:hover{color:var(--accent)}

/* Rail fijo en pantallas anchas */
@media (min-width:1240px){
  .shell{margin-left:max(19.5rem,calc(50% - 19rem))}
  #toc{
    position:fixed; top:0; left:0; width:17.5rem; height:100vh; overflow-y:auto;
    margin:0; border-radius:0; border-width:0 1px 0 0; padding:2.75rem 1.2rem 3rem;
    box-shadow:none; overscroll-behavior:contain;
  }
  #toc a.on{color:var(--accent); font-weight:650}
}

/* ── Controles ──────────────────────────────────── */
.bar{position:fixed; top:.7rem; right:.7rem; z-index:60; display:flex; gap:.35rem}
.bar button,.up{
  font-family:var(--sans); font-size:.75rem; letter-spacing:.02em;
  background:var(--panel); color:var(--slate); border:1px solid var(--rule);
  border-radius:999px; padding:.34rem .8rem; cursor:pointer; box-shadow:var(--shadow);
}
.bar button:hover,.up:hover{color:var(--accent); border-color:var(--accent)}
.up{position:fixed; bottom:1rem; right:1rem; z-index:60; opacity:0; pointer-events:none;
    transition:opacity .18s ease}
.up.on{opacity:1; pointer-events:auto}
@media (prefers-reduced-motion:reduce){.up{transition:none}}

/* ── Impresion ──────────────────────────────────── */
@media print{
  :root{--paper:#fff; --ink:#000; --panel:#fff; --panel-2:#f2f2f2; --rule:#bbb;
        --accent:#000; --slate:#333; --code-bg:#f5f5f5; --shadow:none;
        --amber-wash:#f7f4ec; --green-wash:#eef3ef; --accent-wash:#eef1f5;
        --violet-wash:#f1eff6; --amber:#666; --green:#666; --violet:#666}
  body{font-size:10pt; line-height:1.44}
  .shell{max-width:none; margin:0; padding:0}
  .bar,.up,#toc{display:none !important}
  pre,.tw{margin-inline:0; width:100%}
  h1{page-break-before:always; border-top:none; padding-top:0; font-size:17pt; margin-top:0}
  h1:first-of-type{page-break-before:avoid}
  h2{font-size:12.5pt; page-break-after:avoid}
  h3,h4{page-break-after:avoid}
  pre,blockquote,table,.tw{page-break-inside:avoid}
  pre code{font-size:7.6pt}
  table{font-size:8pt}
  a{color:#000; box-shadow:none}
}

@media (max-width:600px){
  body{font-size:16.5px; line-height:1.66}
  .shell{padding:1.5rem .85rem 4.5rem}
  h1{font-size:1.5rem; margin-top:2.6rem}
  h2{font-size:1.16rem}
  pre code{font-size:.735rem}
  table{font-size:.8rem}
}
</style>`;

const content = `${styles}

<div class="bar">
  <button id="theme" type="button" aria-label="Cambiar entre tema claro y oscuro">Tema</button>
  <button id="print" type="button">Imprimir / PDF</button>
</div>
<button class="up" id="up" type="button">Arriba</button>

<nav id="toc" aria-label="Contenido del libro">
<h2>Contenido</h2>
<ol>
${tocHtml}
</ol>
</nav>

<main class="shell">
${body}
</main>

<script>
(function(){
  var root=document.documentElement;

  // Tema: la preferencia explicita gana sobre la del sistema, en ambos sentidos.
  try{ var s=localStorage.getItem('bi-book-theme'); if(s) root.setAttribute('data-theme',s); }catch(e){}
  document.getElementById('theme').addEventListener('click',function(){
    var cur=root.getAttribute('data-theme');
    if(!cur) cur=window.matchMedia('(prefers-color-scheme: dark)').matches?'dark':'light';
    var next=cur==='dark'?'light':'dark';
    root.setAttribute('data-theme',next);
    try{ localStorage.setItem('bi-book-theme',next); }catch(e){}
  });

  document.getElementById('print').addEventListener('click',function(){window.print();});

  var up=document.getElementById('up');
  up.addEventListener('click',function(){
    var reduce=window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    window.scrollTo({top:0,behavior:reduce?'auto':'smooth'});
  });
  window.addEventListener('scroll',function(){ up.classList.toggle('on', window.scrollY>900); },{passive:true});

  // Resaltar la seccion actual en el rail
  if(window.IntersectionObserver && window.matchMedia('(min-width:1240px)').matches){
    var links={}, nav=document.getElementById('toc');
    nav.querySelectorAll('a').forEach(function(a){ links[a.getAttribute('href').slice(1)]=a; });
    var current=null;
    var io=new IntersectionObserver(function(entries){
      entries.forEach(function(en){
        if(!en.isIntersecting) return;
        var a=links[en.target.id];
        if(!a || a===current) return;
        if(current) current.classList.remove('on');
        a.classList.add('on'); current=a;
        var r=a.getBoundingClientRect();
        if(r.top<60 || r.bottom>window.innerHeight-60) a.scrollIntoView({block:'center'});
      });
    },{rootMargin:'0px 0px -75% 0px'});
    document.querySelectorAll('main h1[id], main h2[id]').forEach(function(h){ io.observe(h); });
  }
})();
</script>`;

const TITLE = 'De OLTP a Dashboard — Pipeline de datos, Data Warehouse y Power BI';

// 1) Documento completo: se abre desde disco, se imprime, se adjunta.
const standalone = `<!doctype html>
<html lang="es">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${TITLE}</title>
<meta name="description" content="Guia completa de construccion de un pipeline de datos con SQL Server, Data Warehouse y Power BI, sobre WideWorldImporters.">
</head>
<body>
${content}
</body>
</html>`;

// 2) Fragmento: el publicador aporta doctype/html/head/body.
const fragment = `<title>${TITLE}</title>\n${content}`;

const outA = path.join(dir, 'guia-pipeline-datos-bi.html');
const outB = path.join(dir, 'guia-web.html');
fs.writeFileSync(outA, standalone, 'utf8');
fs.writeFileSync(outB, fragment, 'utf8');

console.log('completo  ->', path.basename(outA), (Buffer.byteLength(standalone) / 1024).toFixed(0), 'KB');
console.log('fragmento ->', path.basename(outB), (Buffer.byteLength(fragment) / 1024).toFixed(0), 'KB');
console.log('Palabras:', md.split(/\s+/).length.toLocaleString());
console.log('Indice:', toc.length, 'entradas');
