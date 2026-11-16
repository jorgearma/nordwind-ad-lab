"use strict";
/* ============================================================
   MOTOR DE REPRODUCCIÓN — compartido por todas las páginas animadas
   del Nordwind AD Lab (ataque.html, fundamentos.html, …).

   Se carga ANTES del script de la página. La página define sus datos
   y su dibujo, y termina llamando a start('<consola por defecto>'):

     NODES, INFO, STEPS      datos: piezas, fichas y escenas
     PROMPT, TITLE           consolas disponibles: {clave:[prompt, clase]} / {clave:título}
     build()                 dibuja el SVG y rellena L.nodes
     G                       acciones que usan las escenas en los "set"
     resetGraph()            devuelve el esquema al estado inicial
     doPkt(a,my), doBeam(a,my)   animación de paquetes y haces
     idleWire()              texto del panel de red cuando está vacío

   Acciones de una escena: cmd / out / cm / pkt / beam / wire / set / wait.
   Solo las acciones "set" cambian el estado del esquema, así que saltar
   a un paso = volver a aplicar los "set" de los pasos anteriores.
   ============================================================ */
const NS='http://www.w3.org/2000/svg', $=id=>document.getElementById(id);
const svg=$('g');
function el(tag,attrs,parent,text){const e=document.createElementNS(NS,tag);for(const k in attrs)e.setAttribute(k,attrs[k]);if(text!=null)e.textContent=text;(parent||svg).appendChild(e);return e;}
const ICONS={
  user:'M0-9a5 5 0 1 0 .01 0M-9 11c0-6 4-8 9-8s9 2 9 8',
  group:'M-5-8a4 4 0 1 0 .01 0M6-6a3.5 3.5 0 1 0 .01 0M-13 10c0-5 3-7 8-7s8 2 8 7M5 3c5 0 8 2 8 6',
  pc:'M-11-10h22v15h-22zM-5 11h10M0 5v6',
  folder:'M-12-9h8l3 3h13v15h-24z'
};
let L={};   // capas y nodos del SVG; los rellena build()
function clickable(elem,key,label){
  elem.__key=key;
  elem.classList.add('click');elem.setAttribute('tabindex','0');elem.setAttribute('role','button');
  if(label)elem.setAttribute('aria-label',label+' — ver explicación');
  const open=e=>{e.stopPropagation();openFicha(key);};
  elem.addEventListener('click',open);
  elem.addEventListener('keydown',e=>{if(e.key==='Enter'||e.key===' '){e.preventDefault();open(e);}});
}

/* ---- estado y tiempo ---- */
const CANCEL=Symbol('cancel');
const reduce=matchMedia('(prefers-reduced-motion: reduce)').matches;
let cur=-1, run=0, busy=false, paused=false, instant=false, speed=1;
let HOST='';   // consola por defecto de la página; la fija start()
const term=$('term');

function wait(ms,my){
  if(instant||reduce) return my===run?Promise.resolve():Promise.reject(CANCEL);
  return new Promise((res,rej)=>{
    let left=ms/speed,last=performance.now();
    (function tick(){
      if(my!==run)return rej(CANCEL);
      const now=performance.now(); if(!paused)left-=now-last; last=now;
      if(left<=0)return res(); setTimeout(tick,16);
    })();
  });
}
function tween(g,x0,y0,x1,y1,dur,my){
  return new Promise((res,rej)=>{
    let t=0,last=performance.now();
    (function f(now){
      if(my!==run){g.remove();return rej(CANCEL);}
      if(!paused)t+=(now-last)*speed; last=now;
      const p=Math.min(1,t/dur),e=p<.5?2*p*p:1-Math.pow(-2*p+2,2)/2;
      g.setAttribute('transform',`translate(${x0+(x1-x0)*e},${y0+(y1-y0)*e})`);
      if(p<1)requestAnimationFrame(f);else res();
    })(performance.now());
  });
}

/* ---- terminal ---- */
function line(cls){const d=document.createElement('div');d.className='ln '+(cls||'');term.appendChild(d);term.scrollTop=term.scrollHeight;return d;}
async function doCmd(a,my){
  const h=a.host||HOST; $('termtitle').textContent=TITLE[h];
  const d=line('cmd'),ps=document.createElement('span');ps.className='ps '+PROMPT[h][1];ps.textContent=PROMPT[h][0];d.appendChild(ps);
  const t=document.createElement('span');t.className='typing';d.appendChild(t);
  await wait(250,my);
  for(let i=0;i<a.s.length;i+=2){t.textContent=a.s.slice(0,i+2);term.scrollTop=term.scrollHeight;await wait(20,my);}
  t.textContent=a.s; await wait(350,my); t.className='';
}
async function doOut(a,my){
  for(const l of a.lines){const [c,s]=Array.isArray(l)?l:['',l];line(c).textContent=s;await wait(130,my);}
  await wait(350,my);
}

/* ---- texto enriquecido: `código` y [enlace](url) ---- */
function rich(node,text){
  node.textContent='';
  text.split('`').forEach((s,i)=>{
    if(i%2){const c=document.createElement('code');c.textContent=s;node.appendChild(c);return;}
    const re=/\[([^\]]+)\]\(([^)]+)\)/g; let last=0,m;
    while((m=re.exec(s))){
      node.appendChild(document.createTextNode(s.slice(last,m.index)));
      const a=document.createElement('a');a.href=m[2];a.textContent=m[1];node.appendChild(a);
      last=re.lastIndex;
    }
    node.appendChild(document.createTextNode(s.slice(last)));
  });
}

/* ---- ficha explicativa (al pulsar un elemento del esquema) ---- */
let fichaResume=false, fichaSel=null;
function openFicha(key){
  const d=INFO[key]; if(!d)return;
  if(busy&&!paused){paused=true;ui();fichaResume=true;} else fichaResume=false;
  if(fichaSel)fichaSel.classList.remove('sel');
  fichaSel=[...svg.querySelectorAll('.click')].find(e=>e.__key===key)||null;
  if(fichaSel)fichaSel.classList.add('sel');
  $('f-type').textContent=d.type; $('f-title').textContent=d.title; $('f-dn').textContent=d.dn;
  const body=$('f-body'); body.textContent='';
  for(const [h,p] of d.secs){const H=document.createElement('h4');H.textContent=h;const P=document.createElement('p');rich(P,p);body.append(H,P);}
  body.scrollTop=0;
  const ff=$('ficha'); ff.hidden=false; $('f-close').focus();
}
function closeFicha(){
  const ff=$('ficha'); if(ff.hidden)return;
  ff.hidden=true;
  if(fichaSel){fichaSel.classList.remove('sel');fichaSel=null;}
  if(fichaResume){paused=false;fichaResume=false;ui();}
}

/* ---- panel "qué viaja por la red" ---- */
function doWire(a){
  const box=$('wire'); if(box.firstElementChild&&box.firstElementChild.classList.contains('idle'))box.textContent='';
  const w=document.createElement('div');w.className='wmsg';box.appendChild(w);
  const t=document.createElement('div');t.className='wire-t';t.textContent=(box.childElementCount)+' · '+a.title;w.appendChild(t);
  const ps=document.createElement('div');ps.className='parts';w.appendChild(ps);
  for(const [k,v,c] of a.parts){const p=document.createElement('div');p.className='part '+(c||'');const b=document.createElement('b');b.textContent=k;const s=document.createElement('span');s.textContent=v;p.append(b,s);ps.appendChild(p);}
  const n=document.createElement('div');n.className='wire-n';n.textContent=a.note;w.appendChild(n);
}

/* ---- reproducción de un paso ---- */
async function exec(a,my){
  switch(a.t){
    case 'cmd': return doCmd(a,my);
    case 'out': return doOut(a,my);
    case 'cm':  line('cm').textContent=a.s; return wait(900,my);
    case 'pkt': return doPkt(a,my);
    case 'beam':return doBeam(a,my);
    case 'wire':doWire(a); return wait(1300,my);
    case 'set': a.f(G); return wait(500,my);
    case 'wait':return wait(a.ms,my);
  }
}
function meta(i){
  const s=STEPS[i];
  $('i-num').textContent='PASO '+(i+1)+' / '+STEPS.length; $('i-title').textContent=s.title; $('i-need').textContent=s.need; $('i-sum').textContent=s.sum;
  s.cards.forEach((c,k)=>{$('c'+(k+1)+'t').textContent=c[0];rich($('c'+(k+1)),c[1]);});
}
function ui(){
  [...$('steps').children].forEach((c,k)=>{c.className='chip'+(k===cur?' cur':k<cur?' done':'')+(!busy&&k===cur+1?' nextup':'');});
}
async function go(i,opt){
  opt=opt||{}; closeFicha(); const my=++run; cur=i; paused=false; instant=!!opt.instant;
  const st=$('start'); if(st)st.remove();
  resetGraph(); idleWire();
  for(let k=0;k<i;k++)for(const a of STEPS[k].script)if(a.t==='set')a.f(G);
  term.textContent=''; $('termtitle').textContent=TITLE[HOST]; meta(i);
  busy=true; ui();
  if(history.replaceState)history.replaceState(null,'','#paso='+(i+1));
  try{
    for(const a of STEPS[i].script)await exec(a,my);
    busy=false; instant=false; ui();
  }catch(e){ if(e!==CANCEL)throw e; }
}
function toggle(){
  if(cur<0)return go(0);
  if(busy){paused=!paused;ui();return;}
  if(cur<STEPS.length-1)go(cur+1);
}

/* ---- arranque: lo llama cada página al final de su script ---- */
function start(defaultHost){
  HOST=defaultHost;
  build(); idleWire(); meta(0);
  STEPS.forEach((s,i)=>{const b=document.createElement('button');b.className='chip';b.setAttribute('role','tab');const n=document.createElement('b');n.textContent=i+1;b.append(n,s.chip);b.onclick=()=>{if(i===cur&&busy)go(i,{instant:true});else go(i);};$('steps').appendChild(b);});
  $('startbtn').onclick=()=>go(0);
  $('f-close').onclick=closeFicha;
  $('ficha').addEventListener('click',e=>{if(e.target===$('ficha'))closeFicha();});
  const step=d=>{if(busy&&d>0)return go(cur,{instant:true});const n=cur+d;if(n>=0&&n<STEPS.length)go(n);};
  addEventListener('keydown',e=>{
    if(e.key==='Escape'&&!$('ficha').hidden){e.preventDefault();closeFicha();return;}
    if(e.target.closest('a')||e.ctrlKey||e.metaKey||e.altKey)return;
    if(e.key==='ArrowRight'){e.preventDefault();step(1);}
    else if(e.key==='ArrowLeft'){e.preventDefault();step(-1);}
    else if(e.key===' '){e.preventDefault();toggle();}
    else if((e.key==='r'||e.key==='R')&&cur>=0){go(cur);}
  });
  ui();
  // Enlace directo a un paso ya resuelto: pagina.html#paso=5 (añade "anim" para verlo animado)
  const m=location.hash.match(/paso=(\d+)/);
  if(m){const i=Math.min(STEPS.length,Math.max(1,+m[1]))-1;if(/anim/.test(location.hash))go(i);else go(i,{instant:true});}
}
