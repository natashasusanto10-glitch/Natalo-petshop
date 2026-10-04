// Offline conversion of the approved SVG/CSS previews to native Lottie.
// No browser, screenshots, image modification, or remote assets are involved.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const {DOMParser} = require('@xmldom/xmldom');
const out = path.resolve(__dirname, '../../assets/lottie/shortcuts');
const fonts = JSON.parse(fs.readFileSync(path.join(__dirname,'text-outlines.json'),'utf8').replace(/^\uFEFF/,''));
const FPS = 30, PAD = 1500, SIZE = 4096;
const entries = [
  ['cat-food',3.2,[140,40,1200,1000]], ['dog-food',3.2,[140,40,1200,1000]],
  ['fish-food',4,[180,30,1200,1000]], ['medicine',4.2,[160,175,1000,1000]],
  ['promo',2.9,[120,30,1040,1170]], ['new-products',4.1,[70,70,1120,1120]],
  ['voucher',5,[40,100,920,740]], ['points',5,[100,50,440,500]],
];
const children = n => Array.from(n.childNodes||[]).filter(n=>n.nodeType===1);
const descendants = n => children(n).flatMap(c=>[c,...descendants(c)]);
const attrs = n => Object.fromEntries(Array.from(n.attributes||[]).map(a=>[a.name,a.value]));
const numbers = s => (String(s).match(/[-+]?(?:\d*\.\d+|\d+\.?\d*)(?:e[-+]?\d+)?/gi)||[]).map(Number);
const round = x => Math.round(x*10000)/10000;
const identity = () => [1,0,0,1,0,0];
const mul = (a,b) => [a[0]*b[0]+a[2]*b[1],a[1]*b[0]+a[3]*b[1],a[0]*b[2]+a[2]*b[3],a[1]*b[2]+a[3]*b[3],a[0]*b[4]+a[2]*b[5]+a[4],a[1]*b[4]+a[3]*b[5]+a[5]];
const translate = (x,y=0) => [1,0,0,1,x,y];
function matrix(str='') {
  let result=identity();
  for(const m of str.matchAll(/(\w+)\(([^)]*)\)/g)) {
    const v=numbers(m[2]), a=v[0]||0, b=v[1]||0, rad=a*Math.PI/180;
    let t;
    switch(m[1]) {
      case 'translate': t=translate(a,b); break;
      case 'translateX': t=translate(a,0); break;
      case 'translateY': t=translate(0,a); break;
      case 'scale': t=[a,0,0,v[1]??a,0,0]; break;
      case 'scaleX': t=[a,0,0,1,0,0]; break;
      case 'rotate': t=[Math.cos(rad),Math.sin(rad),-Math.sin(rad),Math.cos(rad),0,0]; if(v.length===3)t=mul(mul(translate(b,v[2]),t),translate(-b,-v[2])); break;
      case 'skewX': t=[1,0,Math.tan(rad),1,0,0]; break;
      case 'skewY': t=[1,Math.tan(rad),0,1,0,0]; break;
      case 'matrix': t=v; break;
      default: throw Error('Unsupported transform '+m[1]);
    }
    result=mul(result,t);
  }
  return result;
}
function decompose(m) {
  const sx=Math.hypot(m[0],m[1])||1e-8, sy=(m[0]*m[3]-m[1]*m[2])/sx;
  return {p:[m[4],m[5],0],s:[sx*100,sy*100,100],r:Math.atan2(m[1],m[0])*180/Math.PI,sk:-Math.atan2(m[0]*m[2]+m[1]*m[3],sx*sx)*180/Math.PI};
}
function prop(values, shape=false) {
  if(values.every(v=>JSON.stringify(v)===JSON.stringify(values[0]))) return {a:0,k:values[0]};
  const wrap=v=>shape?[v]:(Array.isArray(v)?v:[v]);
  return {a:1,k:values.map((v,i)=>({t:i,s:wrap(v),...(i+1<values.length?{e:wrap(values[i+1]),o:{x:[0.333],y:[0.333]},i:{x:[0.667],y:[0.667]}}:{})}))};
}
const constant = k => ({a:0,k});
function transform(mats,opacity,pad=0,anchor=0) {
  const d=mats.map(decompose);
  return {a:constant([anchor,anchor,0]),p:prop(d.map(v=>[round(v.p[0]+pad),round(v.p[1]+pad),0])),s:prop(d.map(v=>v.s.map(round))),r:prop(d.map(v=>round(v.r))),sk:prop(d.map(v=>round(v.sk))),sa:constant(0),o:prop(opacity.map(x=>round(x*100)))};
}
// SVG paths in these sources use absolute M/L/H/V/C/Q/Z commands.
// Convert quadratic curves to cubic Beziers for Lottie's shape format.
function parsePath(d,offset=0) {
  const tokens=d.match(/[a-zA-Z]|[-+]?(?:\d*\.\d+|\d+\.?\d*)(?:e[-+]?\d+)?/g)||[];
  let idx=0,cmd,x=0,y=0,cur; const paths=[];
  const num=()=>Number(tokens[idx++]);
  const point=(nx,ny)=>{cur.v.push([nx+offset,ny+offset]);cur.i.push([0,0]);cur.o.push([0,0]);x=nx;y=ny;};
  while(idx<tokens.length) {
    if(/^[a-zA-Z]$/.test(tokens[idx]))cmd=tokens[idx++];
    switch(cmd) {
      case 'M': cur={v:[],i:[],o:[],c:false};paths.push(cur);point(num(),num());cmd='L';break;
      case 'L': point(num(),num());break;
      case 'H': point(num(),y);break;
      case 'V': point(x,num());break;
      case 'C': {const cx1=num(),cy1=num(),cx2=num(),cy2=num(),nx=num(),ny=num();cur.o[cur.o.length-1]=[cx1-x,cy1-y];point(nx,ny);cur.i[cur.i.length-1]=[cx2-nx,cy2-ny];break;}
      case 'Q': {const cx=num(),cy=num(),nx=num(),ny=num();cur.o[cur.o.length-1]=[(cx-x)*2/3,(cy-y)*2/3];point(nx,ny);cur.i[cur.i.length-1]=[(cx-nx)*2/3,(cy-ny)*2/3];break;}
      case 'Z': cur.c=true;cmd=null;break;
      default: throw Error('Unsupported path command: '+cmd+' in '+d);
    }
  }
  return paths;
}
function shapePath(n,offset=0) {
  const a=attrs(n),val=(k,f=0)=>Number(a[k]??f);
  if(n.tagName==='path')return parsePath(a.d,offset);
  if(n.tagName==='text') {
    const glyph=fonts[n.textContent], [bx,by,bw,bh]=glyph.bounds;
    const dx=val('x')-bx-bw/2+offset,dy=val('y')-by-bh+offset;
    let cur;const paths=[];
    for(let j=0;j<glyph.points.length;j++) {
      const [x,y]=glyph.points[j],type=glyph.types[j]&7;
      if(type===0){cur={v:[],i:[],o:[],c:false};paths.push(cur);}
      if(type===3){const [x2,y2]=glyph.points[j+1],[x3,y3]=glyph.points[j+2],last=cur.v.at(-1);cur.o[cur.o.length-1]=[x+dx-last[0],y+dy-last[1]];cur.v.push([x3+dx,y3+dy]);cur.i.push([x2-x3,y2-y3]);cur.o.push([0,0]);j+=2;}
      else {cur.v.push([x+dx,y+dy]);cur.i.push([0,0]);cur.o.push([0,0]);}
      if(glyph.types[j]&128)cur.c=true;
    }
    return paths;
  }
  const k=.5522847498;
  if(n.tagName==='ellipse'||n.tagName==='circle') {
    const cx=val('cx')+offset,cy=val('cy')+offset,rx=val('rx',val('r')),ry=val('ry',val('r'));
    return [{v:[[cx,cy-ry],[cx+rx,cy],[cx,cy+ry],[cx-rx,cy]],i:[[-rx*k,0],[0,-ry*k],[rx*k,0],[0,ry*k]],o:[[rx*k,0],[0,ry*k],[-rx*k,0],[0,-ry*k]],c:true}];
  }
  if(n.tagName==='rect') {
    const x=val('x'),y=val('y'),w=val('width'),h=val('height'),r=Math.min(val('rx'),w/2,h/2),s=r*k;
    return parsePath(`M${x+r} ${y}H${x+w-r}C${x+w-r+s} ${y} ${x+w} ${y+r-s} ${x+w} ${y+r}V${y+h-r}C${x+w} ${y+h-r+s} ${x+w-r+s} ${y+h} ${x+w-r} ${y+h}H${x+r}C${x+r-s} ${y+h} ${x} ${y+h-r+s} ${x} ${y+h-r}V${y+r}C${x} ${y+r-s} ${x+r-s} ${y} ${x+r} ${y}Z`,offset);
  }
  throw Error('Unsupported shape '+n.tagName);
}
const color=s=>{if(s==='white')s='#FFFFFF';if(s==='black')s='#000000';if(!/^#[\da-f]{6}$/i.test(s))throw Error('Unsupported color '+s);return [1,3,5].map(i=>parseInt(s.slice(i,i+2),16)/255).concat(1);};
function svgRuntime(html) {
  const roots=new Map(),stubs=new Map();
  const query=(root,selector)=>descendants(root).filter(n=>selector[0]==='.'?(n.getAttribute('class')||'').split(/\s+/).includes(selector.slice(1)):n.tagName===selector);
  function enhance(root){for(const n of [root,...descendants(root)]){n.querySelectorAll=s=>query(n,s);n.querySelector=s=>query(n,s)[0];n.dataset=Object.fromEntries(Object.entries(attrs(n)).filter(([k])=>k.startsWith('data-')).map(([k,v])=>[k.slice(5),v]));}return root;}
  const document={getElementById(id){if(!stubs.has(id))stubs.set(id,{checked:false,addEventListener(){},setAttribute(){},set innerHTML(s){roots.set(id,enhance(new DOMParser().parseFromString(s,'image/svg+xml').documentElement));}});return stubs.get(id);},querySelectorAll(s){if(s==='.icon svg')return [...roots.values()];return [...roots.values()].flatMap(r=>query(r,s));},addEventListener(){}};
  const ctx=vm.createContext({document,matchMedia:()=>({matches:false,addEventListener(){}}),requestAnimationFrame(){},Math});
  vm.runInContext(html.match(/<script>([\s\S]*?)<\/script>/)[1],ctx);
  return {root:roots.get('large'),sample:t=>vm.runInContext(`typeof draw==='function'?draw(${t}):render(${t})`,ctx)};
}
function bezier(x,c=[.25,.1,.25,1]) {let lo=0,hi=1,t;const at=(t,a,b)=>3*(1-t)**2*t*a+3*(1-t)*t*t*b+t**3;for(let i=0;i<18;i++){t=(lo+hi)/2;if(at(t,c[0],c[2])<x)lo=t;else hi=t;}return at((lo+hi)/2,c[1],c[3]);}
function cssRuntime(html,root,name) {
  const keys={};
  for(const block of html.matchAll(/@keyframes (\w+)\{((?:[^{}]+\{[^{}]*\})+)\}/g)) {
    keys[block[1]]=[];
    for(const step of block[2].matchAll(/([\d%,.\s]+)\{([^}]+)\}/g)) {
      const a=Object.fromEntries(step[2].split(';').filter(Boolean).map(v=>v.split(':').map(s=>s.trim())));
      for(const percent of step[1].matchAll(/([\d.]+)%/g))keys[block[1]].push({p:Number(percent[1])/100,a});
    }
    keys[block[1]].sort((a,b)=>a.p-b.p);
  }
  const bindings={pellet1:'drop1',pellet2:'drop2',jar:'pour',lid:'lid','lid-turn':'unscrew','cap-grooves':'grooves',thread:'thread',grain:'grain',g2:'grain2',g3:'grain3','bottle-cap':'unscrew',grooves:'grip','tube-cap':'uncap','gel-reveal':'gel','tablet-one':'tabletOne','tablet-two':'tabletTwo','tablet-three':'tabletThree'};
  const origins={jar:[735,800],'lid-turn':[735,335],'tablet-one':[865,462.5],'tablet-two':[865,462.5],'tablet-three':[865,462.5]};
  const tracks=descendants(root).map(n=>{const classes=(n.getAttribute('class')||'').split(/\s+/);const key=classes.map(c=>bindings[c]).filter(Boolean).at(-1);return {n,key,origin:classes.map(c=>origins[c]).find(Boolean)||[0,0]};}).filter(v=>v.key&&keys[v.key]);
  return p=>{for(const {n,key,origin} of tracks){const steps=keys[key];let a=steps[0],b=steps.at(-1);for(let i=1;i<steps.length;i++){if(p<=steps[i].p){a=steps[i-1];b=steps[i];break;}}const u=bezier(Math.max(0,Math.min(1,(p-a.p)/(b.p-a.p||1))),name==='medicine'?[.3,.05,.3,1]:undefined);for(const field of new Set([...Object.keys(a.a),...Object.keys(b.a)])){if(field==='transform') {const ma=decompose(matrix(a.a[field])),mb=decompose(matrix(b.a[field]));const lerp=(v,w)=>v+(w-v)*u;const pos=ma.p.map((v,i)=>lerp(v,mb.p[i])),scale=ma.s.map((v,i)=>lerp(v,mb.s[i]));const m=matrix(`translate(${pos[0]} ${pos[1]}) rotate(${lerp(ma.r,mb.r)}) skewX(${-lerp(ma.sk,mb.sk)}) scale(${scale[0]/100} ${scale[1]/100})`);n.setAttribute('transform','matrix('+mul(mul(translate(...origin),m),translate(-origin[0],-origin[1])).join(' ')+')');}else{const va=Number(a.a[field]??(field==='opacity'?1:0)),vb=Number(b.a[field]??va);n.setAttribute(field,String(va+(vb-va)*u));}}}};
}
for(const [name,duration,box] of entries) {
  const html=fs.readFileSync(path.join(__dirname,'sources',name+'.html'),'utf8');
  const frameCount=Math.round(duration*FPS),assets=[],imageIds=new Map(); let nextId=1;
  let root,sample;
  if(['cat-food','dog-food','fish-food','medicine'].includes(name)) {root=new DOMParser().parseFromString(html.match(/<svg class="large"[\s\S]*?<\/svg>/)[0],'image/svg+xml').documentElement;const run=cssRuntime(html,root,name);sample=t=>run(t/duration);}
  else {const runtime=svgRuntime(html);root=runtime.root;sample=t=>runtime.sample(name==='promo'?t:Math.min(t,{'new-products':3,voucher:3.6,points:3.8}[name]));}
  if(name==='medicine') {
    // The flattened artwork hides this bottle corner behind the tube cap.
    // Supply its silhouette underneath so opening the cap reveals a whole bottle.
    const group=descendants(root).find(n=>n.getAttribute('id')==='medicineArt');
    const repair=root.ownerDocument.createElement('path');
    repair.setAttribute('d','M710 824L803 824L808 966L789 966Q704 966 704 918Z');
    repair.setAttribute('fill','#FFFFFF');
    repair.setAttribute('stroke','#263B3A');
    repair.setAttribute('stroke-width','18');
    group.insertBefore(repair,group.firstChild);
  }
  // Match the approved compact gallery: retain symbols, omit illegible labels.
  if(name==='voucher') {const nodes=descendants(root);for(const n of nodes){if(n.getAttribute('class')==='percent')n.parentNode.setAttribute('transform','');if(n.getAttribute('class')==='truck')n.parentNode.setAttribute('transform','translate(0 20)');}}
  const nodes=[root,...descendants(root)],tracks=new Map(nodes.map(n=>[n,[]]));
  for(let f=0;f<=frameCount;f++){sample(f/FPS);for(const n of nodes)tracks.get(n).push(attrs(n));}
  const ids=new Map(nodes.filter(n=>n.hasAttribute('id')).map(n=>[n.getAttribute('id'),n]));
  const base=(label,ty)=>({ddd:0,ind:nextId++,ty,nm:label,sr:1,ip:0,op:frameCount+1,st:0,bm:0});
  const reference=a=>ids.get(a.match(/#([^)'"\s]+)/)?.[1]);
  function maskPaths(n,mode='a') {return children(n).flatMap(c=>{
    const frames=(tracks.get(c)||[attrs(c)]).map(a=>c.tagName==='path'?parsePath(a.d,PAD):shapePath(c,PAD));
    return frames[0].map((_,i)=>({inv:false,mode,pt:prop(frames.map(p=>p[i]),true),o:constant(100),x:constant(0)}));
  });}
  function build(n,inherited={fill:'black'},ancestry=[]) {
    if(ancestry.includes(n))throw Error('Cyclic SVG use');
    const a=attrs(n),tag=n.tagName,label=a.id||a.class||tag;
    if(['defs','clipPath','mask'].includes(tag))return null;
    if(['discount','free'].includes(a.class)||(tag==='text'&&n.textContent==='REWARD'))return null;
    const style={...inherited,...Object.fromEntries(Object.entries(a).filter(([k])=>['fill','stroke','stroke-width','stroke-linecap','stroke-linejoin','stroke-dasharray'].includes(k)))};
    const frames=tracks.get(n)||Array(frameCount+1).fill(a),mats=frames.map(a=>matrix(a.transform)),opacity=frames.map(a=>Number(a.opacity??1));
    let layer;
    if(['g','svg','use','image'].includes(tag)) {
      let kids=[];
      if(tag==='use'){const target=ids.get((a.href||a['xlink:href']).slice(1));if(!target)throw Error('Missing use');kids=[build(target,style,[...ancestry,n])];}
      else if(tag==='image') {
        const file=a.href;let image=imageIds.get(file);
        if(!image) {const bytes=fs.readFileSync(path.join(out,file));image={id:'image_'+imageIds.size,w:bytes.readUInt32BE(16),h:bytes.readUInt32BE(20),u:'',p:file,e:0};imageIds.set(file,image);assets.push(image);}
        const m=[Number(a.width)/image.w,0,0,Number(a.height)/image.h,Number(a.x||0),Number(a.y||0)];
        kids=[{...base(file,2),refId:image.id,ks:transform([m],[1],PAD)}];
      } else kids=children(n).map(c=>build(c,style,[...ancestry,n])).filter(Boolean);
      const refId='comp_'+nextId++;
      assets.push({id:refId,layers:kids.reverse()});
      layer={...base(label,0),refId,w:SIZE,h:SIZE,ks:transform(mats,opacity,PAD,PAD)};
      if(a['clip-path'])layer.masksProperties=maskPaths(reference(a['clip-path']));
      if(a.mask&&a.mask!=='url(#gelMask)') {
        const mask=reference(a.mask);
        layer.masksProperties=children(mask).flatMap(c=>shapePath(c,PAD).map(p=>({inv:false,mode:c.getAttribute('fill')==='black'?'s':'a',pt:constant(p),o:constant(100),x:constant(0)})));
      }
    } else {
      const paths=frames.map(f=>{if(tag==='path')return parsePath(f.d||a.d);return shapePath(n);});
      const shapes=paths[0].map((_,i)=>({ty:'sh',ks:prop(paths.map(p=>p[i]),true),nm:label}));
      if(style.fill!=='none')shapes.push({ty:'fl',c:constant(color(style.fill)),o:constant(100),r:2});
      if(style.stroke&&style.stroke!=='none') {
        const stroke={ty:'st',c:constant(color(style.stroke)),o:constant(100),w:constant(Number(style['stroke-width']||1)),lc:style['stroke-linecap']==='round'?2:1,lj:style['stroke-linejoin']==='round'?2:1,ml:4};
        if(style['stroke-dasharray'])stroke.d=numbers(style['stroke-dasharray']).map((v,i)=>({n:i%2?'g':'d',v:constant(v)}));
        shapes.push(stroke);
      }
      if(ancestry.some(p=>p.getAttribute('mask')==='url(#gelMask)')) {
        const reveal=nodes.find(p=>(p.getAttribute('class')||'').includes('gel-reveal'));
        shapes.push({ty:'tm',s:constant(0),e:prop(tracks.get(reveal).map(f=>100-Number(f['stroke-dashoffset']??250)/2.5)),o:constant(0),m:1});
      }
      layer={...base(label,4),ks:transform(mats,opacity,PAD),shapes};
    }
    return layer;
  }
  const top=build(root),[x,y,w,h]=box,scale=800/Math.max(w,h);
  top.ks=transform([[scale,0,0,scale,(800-w*scale)/2-x*scale,(800-h*scale)/2-y*scale]],[1],0,PAD);
  const animation={v:'5.12.2',fr:FPS,ip:0,op:frameCount,w:800,h:800,nm:'Natalo '+name,ddd:0,assets,layers:[top],markers:[]};
  fs.writeFileSync(path.join(out,name+'.json'),JSON.stringify(animation));
  console.log(`${name}: ${frameCount} frames, ${assets.length} assets`);
}
