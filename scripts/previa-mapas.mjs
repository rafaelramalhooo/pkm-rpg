// Prévia visual dos mapas (somente leitura): gera uma folha-contato em HTML com TODOS os mapas,
// com camadas ligáveis (colisão, grama, portais, pontos de interesse, spawn, problemas do linter).
// Uso: node scripts/previa-mapas.mjs [--so id1,id2] [--saida .preview/mapas] [--embutir]
//   --embutir  grava as imagens dentro do HTML (um único arquivo, fácil de enviar/compartilhar)
// A saída vai para .preview/ (ignorada pelo Git: a arte recomposta do Tuxemon não precisa ser duplicada).
import fs from "node:fs";
import path from "node:path";
import { T, carregarMapas } from "./mapas/lib.mjs";
import { lintar } from "./lint-mapas.mjs";

const args = process.argv.slice(2);
const valor = (nome) => { const i = args.indexOf(nome); return i >= 0 ? args[i + 1] : null; };
const filtro = valor("--so")?.split(",").map((s) => s.trim()).filter(Boolean) ?? null;
const saida = path.resolve(valor("--saida") ?? ".preview/mapas");
const embutir = args.includes("--embutir");

const dados = carregarMapas();
const { problemas, resumo } = lintar(dados);
const ids = (filtro ?? [...dados.mapas.keys()]).filter((id) => dados.mapas.has(id));

const png = (id, sufixo) => {
  const arq = path.join(dados.pasta, `${id}${sufixo}.png`);
  if (!fs.existsSync(arq)) return null;
  if (embutir) return `data:image/png;base64,${fs.readFileSync(arq).toString("base64")}`;
  fs.mkdirSync(saida, { recursive: true });
  fs.copyFileSync(arq, path.join(saida, `${id}${sufixo}.png`));
  return `${id}${sufixo}.png`;
};

const MAPAS = ids.map((id) => {
  const m = dados.mapas.get(id);
  return {
    id, nome: m.nome, w: m.w, h: m.h, solido: m.solido, grama: m.grama, spawn: m.spawn ?? null,
    portais: (m.portais ?? []).map((p) => ({ x: p.x, y: p.y, w: p.w ?? 1, h: p.h ?? 1, dest: p.dest, req: p.req_treinador ? "treinador" : p.req_insignias ? `${p.req_insignias} insígnias` : null })),
    pois: (m.pois ?? []).map((p) => ({ x: p.x, y: p.y, id: p.id, tipo: p.tipo })),
    base: png(id, ""), cima: png(id, "-cima"),
    problemas: problemas.filter((p) => p.mapa === id).map((p) => ({ g: p.gravidade, c: p.codigo, msg: p.msg, tiles: p.tiles ?? [] })),
  };
});

const html = `<!doctype html>
<html lang="pt-BR"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Prévia dos mapas — Rafar</title>
<style>
  :root{--bg:#f4f6f9;--card:#fff;--tx:#1d2530;--mut:#627085;--err:#d32f2f;--av:#e08a00;--ok:#2e8b57;--bd:#d9dfe7}
  *{box-sizing:border-box} body{margin:0;font:14px/1.4 system-ui,sans-serif;background:var(--bg);color:var(--tx)}
  header{position:sticky;top:0;z-index:20;background:#fff;border-bottom:1px solid var(--bd);padding:10px 16px;display:flex;flex-wrap:wrap;gap:14px;align-items:center}
  header h1{font-size:16px;margin:0 8px 0 0} label{display:inline-flex;gap:5px;align-items:center;cursor:pointer;white-space:nowrap}
  .grp{display:flex;gap:12px;flex-wrap:wrap;align-items:center;padding-left:14px;border-left:1px solid var(--bd)}
  .tot b{font-size:15px} .e{color:var(--err)} .a{color:var(--av)} .k{color:var(--ok)}
  main{padding:16px;display:grid;gap:16px;grid-template-columns:repeat(auto-fill,minmax(var(--col,360px),max-content));align-items:start}
  .card{background:var(--card);border:1px solid var(--bd);border-radius:10px;padding:10px;max-width:100%}
  .card.hide{display:none} .card h2{font-size:14px;margin:0 0 6px;display:flex;gap:8px;align-items:baseline;flex-wrap:wrap}
  .card h2 small{color:var(--mut);font-weight:400} .bd{font-size:11px;padding:1px 7px;border-radius:10px;color:#fff}
  .bd.e{background:var(--err)} .bd.a{background:var(--av)} .bd.k{background:var(--ok)}
  .vp{position:relative;overflow:auto;max-height:78vh;border:1px solid var(--bd);border-radius:6px;background:#222}
  .st{position:relative} .st img,.st canvas{position:absolute;left:0;top:0;image-rendering:pixelated;display:block}
  .st canvas{pointer-events:none}
  ul{margin:8px 0 0;padding-left:0;list-style:none;font-size:12px} li{margin:3px 0;display:flex;gap:6px}
  li i{font-style:normal;font-weight:700;min-width:18px} li.E i{color:var(--err)} li.A i{color:var(--av)}
  code{background:#eef1f5;padding:0 4px;border-radius:3px;font-size:11px}
  .leg{font-size:12px;color:var(--mut)} .sw{display:inline-block;width:10px;height:10px;border-radius:2px;vertical-align:-1px;margin-right:3px}
</style></head><body>
<header>
  <h1>Prévia dos mapas</h1>
  <span class="tot"><b>${resumo.mapas}</b> mapas · <b class="e">${resumo.erros}</b> erro(s) · <b class="a">${resumo.avisos}</b> aviso(s)</span>
  <div class="grp"><label><input type="checkbox" id="l-sol"> Colisão</label><label><input type="checkbox" id="l-gra"> Grama alta</label>
    <label><input type="checkbox" id="l-por" checked> Portais</label><label><input type="checkbox" id="l-poi" checked> Pontos de interesse</label>
    <label><input type="checkbox" id="l-pro" checked> Problemas</label><label><input type="checkbox" id="l-gri"> Grade</label><label><input type="checkbox" id="l-cim" checked> Camada superior</label></div>
  <div class="grp"><label>Zoom <select id="zoom"><option value="1">1×</option><option value="2" selected>2×</option><option value="3">3×</option></select></label>
    <label>Mostrar <select id="filtro"><option value="todos">todos</option><option value="prob">só com problemas</option><option value="erro">só com erros</option></select></label></div>
  <div class="grp leg"><span><i class="sw" style="background:rgba(220,40,40,.6)"></i>sólido</span><span><i class="sw" style="background:rgba(40,160,60,.6)"></i>grama</span>
    <span><i class="sw" style="background:rgba(30,120,255,.7)"></i>portal</span><span><i class="sw" style="background:#ffd400"></i>ponto de interesse</span>
    <span><i class="sw" style="background:#d32f2f"></i>erro</span><span><i class="sw" style="background:#e08a00"></i>aviso</span></div>
</header>
<main id="grade"></main>
<script>
const T=${T}, MAPAS=${JSON.stringify(MAPAS)};
const $=(s)=>document.querySelector(s), grade=$('#grade');
const camadas=()=>({sol:$('#l-sol').checked,gra:$('#l-gra').checked,por:$('#l-por').checked,poi:$('#l-poi').checked,pro:$('#l-pro').checked,gri:$('#l-gri').checked,cim:$('#l-cim').checked});

function desenhar(m, cv, z, c){
  const g=cv.getContext('2d'); g.clearRect(0,0,cv.width,cv.height); const S=T*z;
  if(c.sol||c.gra){ for(let y=0;y<m.h;y++)for(let x=0;x<m.w;x++){ const k=y*m.w+x;
    if(c.sol&&m.solido[k]==='1'){g.fillStyle='rgba(220,40,40,.38)';g.fillRect(x*S,y*S,S,S);}
    if(c.gra&&m.grama[k]==='1'){g.fillStyle='rgba(40,160,60,.40)';g.fillRect(x*S,y*S,S,S);} } }
  if(c.gri){ g.strokeStyle='rgba(255,255,255,.18)'; g.lineWidth=1; g.beginPath();
    for(let x=0;x<=m.w;x++){g.moveTo(x*S+.5,0);g.lineTo(x*S+.5,m.h*S);} for(let y=0;y<=m.h;y++){g.moveTo(0,y*S+.5);g.lineTo(m.w*S,y*S+.5);} g.stroke(); }
  g.font='bold '+(5*z+3)+'px system-ui,sans-serif'; g.textBaseline='top';
  const rot=(t,x,y,cor)=>{ g.lineWidth=3; g.strokeStyle='rgba(0,0,0,.85)'; g.strokeText(t,x,y); g.fillStyle=cor; g.fillText(t,x,y); };
  if(c.por) for(const p of m.portais){ g.fillStyle='rgba(30,120,255,.45)'; g.fillRect(p.x*S,p.y*S,p.w*S,p.h*S); g.strokeStyle='#4aa3ff'; g.lineWidth=2; g.strokeRect(p.x*S+1,p.y*S+1,p.w*S-2,p.h*S-2);
    rot('→'+p.dest+(p.req?' 🔒':''),p.x*S+2,p.y*S+2,'#bfe0ff'); }
  if(c.poi) for(const p of m.pois){ g.fillStyle='rgba(255,212,0,.85)'; g.fillRect(p.x*S+S*.25,p.y*S+S*.25,S*.5,S*.5); g.strokeStyle='#000'; g.lineWidth=1; g.strokeRect(p.x*S+S*.25,p.y*S+S*.25,S*.5,S*.5); rot(p.id,p.x*S+S*.8,p.y*S+S*.15,'#fff3a0'); }
  if(m.spawn&&(c.poi||c.por)){ rot('★ spawn',m.spawn.x*S,m.spawn.y*S-(4*z),'#7dff9a'); g.strokeStyle='#7dff9a'; g.lineWidth=2; g.strokeRect(m.spawn.x*S+1,m.spawn.y*S+1,S-2,S-2); }
  if(c.pro) m.problemas.forEach((p,i)=>{ const cor=p.g==='ERRO'?'#d32f2f':'#e08a00';
    for(const [x,y] of p.tiles){ g.fillStyle=p.g==='ERRO'?'rgba(211,47,47,.45)':'rgba(224,138,0,.35)'; g.fillRect(x*S,y*S,S,S); g.strokeStyle=cor; g.lineWidth=2; g.strokeRect(x*S+1,y*S+1,S-2,S-2); }
    if(p.tiles.length){ const [x,y]=p.tiles[0]; g.fillStyle=cor; g.beginPath(); g.arc(x*S+S/2,y*S+S/2,Math.max(7,S*.45),0,7); g.fill(); g.fillStyle='#fff'; g.textBaseline='middle'; g.textAlign='center'; g.font='bold '+(4*z+4)+'px system-ui'; g.fillText(i+1,x*S+S/2,y*S+S/2); g.textAlign='left'; g.textBaseline='top'; } });
}

function montar(){
  const z=+$('#zoom').value, c=camadas(); grade.innerHTML='';
  grade.style.setProperty('--col',Math.min(640*z/2+40,900)+'px');
  for(const m of MAPAS){
    const e=m.problemas.filter(p=>p.g==='ERRO').length, a=m.problemas.length-e;
    const card=document.createElement('section'); card.className='card'; card.dataset.e=e; card.dataset.a=a;
    card.innerHTML='<h2>'+m.nome+' <small><code>'+m.id+'</code> · '+m.w+'×'+m.h+' tiles</small>'+(e?'<span class="bd e">'+e+' erro'+(e>1?'s':'')+'</span>':'')+(a?'<span class="bd a">'+a+' aviso'+(a>1?'s':'')+'</span>':'')+(!e&&!a?'<span class="bd k">ok</span>':'')+'</h2>';
    const vp=document.createElement('div'); vp.className='vp';
    const st=document.createElement('div'); st.className='st'; st.style.width=m.w*T*z+'px'; st.style.height=m.h*T*z+'px';
    const img=(src,cl)=>{ if(!src) return; const i=document.createElement('img'); i.src=src; i.style.width=m.w*T*z+'px'; i.style.height=m.h*T*z+'px'; if(cl) i.className=cl; st.appendChild(i); return i; };
    img(m.base); const ci=img(m.cima,'cima'); if(ci&&!c.cim) ci.style.display='none';
    const cv=document.createElement('canvas'); cv.width=m.w*T*z; cv.height=m.h*T*z; st.appendChild(cv); desenhar(m,cv,z,c);
    vp.appendChild(st); card.appendChild(vp);
    if(m.problemas.length){ const ul=document.createElement('ul');
      m.problemas.forEach((p,i)=>{ const li=document.createElement('li'); li.className=p.g[0]; const c0=p.tiles[0]; li.innerHTML='<i>'+(i+1)+'</i><span><code>'+p.c+'</code> '+p.msg+(c0?' <small>('+c0[0]+','+c0[1]+')</small>':'')+'</span>'; ul.appendChild(li); });
      card.appendChild(ul); }
    grade.appendChild(card);
    const p0=m.problemas.find(p=>p.tiles.length); // abre já rolado até o primeiro problema
    if(p0){ const [x,y]=p0.tiles[0]; vp.scrollTop=Math.max(0,y*T*z-vp.clientHeight/2); vp.scrollLeft=Math.max(0,x*T*z-vp.clientWidth/2); }
  }
  filtrar();
}
function filtrar(){ const f=$('#filtro').value; for(const c of grade.children){ const e=+c.dataset.e,a=+c.dataset.a; c.classList.toggle('hide',(f==='prob'&&!e&&!a)||(f==='erro'&&!e)); } }
document.querySelectorAll('header input,header select').forEach(el=>el.addEventListener('change',()=>el.id==='filtro'?filtrar():montar()));
montar();
</script></body></html>
`;

fs.mkdirSync(saida, { recursive: true });
const arquivo = path.join(saida, "folha-contato.html");
fs.writeFileSync(arquivo, html);
console.log(`Prévia gravada em ${path.relative(process.cwd(), arquivo)} (${ids.length} mapas, ${embutir ? "imagens embutidas" : "imagens ao lado do HTML"}; ${(fs.statSync(arquivo).size / 1024).toFixed(0)} KB)`);
