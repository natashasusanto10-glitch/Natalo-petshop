/* Shared vector artwork and motion for the Flutter and web wishlist. */
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '..');
const C = { ink:'#182C48', orange:'#F6A84C', stripe:'#DE883C', cream:'#FFF0DB', pink:'#F4AF99', dog:'#D99A59', ear:'#B9773D', coral:'#F46C60', teal:'#1974BF', gold:'#F6BD43', white:'#FFFFFF', gray:'#D6DFE8' };
const color = hex => hex.slice(1).match(/../g).map(v => parseInt(v,16)/255);
const fixed = k => ({a:0,k});
function keys(points) {
  return {a:1,k:points.map(([t,s],i) => ({t,s:Array.isArray(s)?s:[s], ...(i < points.length-1 ? {e:Array.isArray(points[i+1][1])?points[i+1][1]:[points[i+1][1]],i:{x:[.65],y:[1]},o:{x:[.35],y:[0]}} : {})}))};
}
function bezier(d) {
  const tokens=d.match(/[MLCZ]|-?\d+(?:\.\d+)?/g); const v=[],i=[],o=[]; let n=0,closed=false;
  while(n<tokens.length){const cmd=tokens[n++];
    if(cmd==='M'||cmd==='L'){v.push([+tokens[n++],+tokens[n++]]);i.push([0,0]);o.push([0,0]);}
    else if(cmd==='C'){const a=[+tokens[n++],+tokens[n++]],b=[+tokens[n++],+tokens[n++]],end=[+tokens[n++],+tokens[n++]];const p=v[v.length-1];o[o.length-1]=[a[0]-p[0],a[1]-p[1]];v.push(end);i.push([b[0]-end[0],b[1]-end[1]]);o.push([0,0]);}
    else if(cmd==='Z'){closed=true;if(v.length>1&&v.at(-1)[0]===v[0][0]&&v.at(-1)[1]===v[0][1]){i[0]=i.pop();v.pop();o.pop();}}
    else throw Error(`Unsupported path token ${cmd}`);
  }
  return {v,i,o,c:closed};
}
const P=(d,fill,stroke=C.ink,width=2.5)=>({kind:'path',d,fill,stroke,width});
const E=(x,y,w,h,fill,stroke=null,width=2)=>({kind:'ellipse',x,y,w,h,fill,stroke,width});
const R=(x,y,w,h,r,fill,stroke=null,width=2)=>({kind:'rect',x,y,w,h,r,fill,stroke,width});
const layers=[];
function layer(name,shapes,p=[0,0],r=0,options={}){
  const groups=shapes.map((s,index)=>{
    const shapes=s.kind==='path'?s.d.split(/(?=M)/).filter(Boolean).map(d=>({ty:'sh',ks:fixed(bezier(d))})):s.kind==='ellipse'?[{ty:'el',p:fixed([s.x,s.y]),s:fixed([s.w,s.h])}]:[{ty:'rc',p:fixed([s.x+s.w/2,s.y+s.h/2]),s:fixed([s.w,s.h]),r:fixed(s.r)}];
    return {ty:'gr',nm:`${name} ${index}`,it:[...shapes,...(s.fill?[{ty:'fl',c:fixed(color(s.fill)),o:fixed(100),r:1}]:[]),...(s.stroke?[{ty:'st',c:fixed(color(s.stroke)),o:fixed(100),w:fixed(s.width),lc:2,lj:2}]:[]),{ty:'tr',p:fixed([0,0]),a:fixed([0,0]),s:fixed([100,100]),r:fixed(0),o:fixed(100)}]};
  });
  const item={ddd:0,ind:layers.length+1,ty:4,nm:name,sr:1,ks:{o:fixed(100),r:fixed(r),p:fixed([...p,0]),a:fixed([0,0,0]),s:fixed([100,100,100]),...options.ks},ao:0,shapes:groups.reverse(),ip:0,op:180,st:0,bm:0,...(options.parent?{parent:options.parent}:{}),_shapes:shapes};
  layers.push(item); return item.ind;
}
layer('Ground', [E(288,423,440,22,'#E9EFF5')]);
// Lottie parenting inherits transforms, but not opacity. Apply visibility to
// every pet layer so eyes and paws cannot remain after the head retreats.
const petVisibility = keys([[0,0],[28,0],[54,100],[145,100],[175,0],[180,0]]);
const cat=layer('Cat head',[
  P('M -62 -19 L -62 -73 C -62 -85 -49 -78 -24 -53 C -5 -61 15 -60 34 -51 C 59 -81 66 -84 69 -66 L 72 -12 C 83 11 68 49 34 60 C 8 73 -31 67 -53 45 C -76 24 -79 1 -62 -19 Z',C.orange,C.ink,2.5),
  P('M -52 -33 L -51 -64 L -29 -43 Z',C.pink,null),P('M 43 -39 L 61 -65 L 62 -29 Z',C.pink,null),
  P('M -26 -52 C -20 -43 -18 -34 -21 -28 C -25 -25 -29 -32 -32 -47 Z',C.stripe,null),P('M -6 -57 C -1 -48 1 -38 -3 -33 C -8 -30 -10 -40 -13 -56 Z',C.stripe,null),
  P('M 11 -55 C 18 -47 21 -38 16 -34 C 12 -33 6 -45 4 -57 Z',C.stripe,null),
  P('M -40 36 C -39 20 -25 16 -15 25 C -5 32 4 29 13 23 C 32 10 51 23 46 41 C 26 65 -17 64 -40 36 Z',C.cream,null),
  E(-44,25,19,10,'#EFAB7E'),E(46,24,18,9,'#EFAB7E'),
  P('M -7 23 C -5 17 5 17 8 23 C 5 30 -4 30 -7 23 Z','#C25C4C',null),
  P('M 1 29 L 1 35 C -9 44 -17 38 -18 34 M 1 35 C 11 44 20 38 21 33',null,C.ink,2.3),
  P('M -43 24 L -75 15 M -44 33 L -77 33 M 43 21 L 74 11 M 44 31 L 78 28',null,C.ink,2.2),
  P('M -29 62 C -6 72 17 71 37 61 L 34 73 C 15 81 -10 80 -29 72 Z',C.teal,null),
], [176,129],0,{ks:{o:petVisibility,p:keys([[0,[176,290,0]],[24,[176,290,0]],[56,[176,129,0]],[142,[176,129,0]],[173,[176,290,0]],[180,[176,290,0]]])}});
const blink=keys([[0,[100,100,100]],[83,[100,100,100]],[88,[100,8,100]],[92,[100,100,100]],[180,[100,100,100]]]);
layer('Cat eyes',[E(-26,6,11,17,C.ink),E(27,6,11,17,C.ink),E(-28,2,3,4,C.white),E(25,2,3,4,C.white)],[0,0],0,{parent:cat,ks:{o:petVisibility,s:blink}});
const dogBody=layer('Dog body',[
  P('M 57 137 C 86 142 88 111 100 116 C 118 132 101 163 70 162 Z',C.ear,C.ink,2.5),
  P('M -18 50 C -5 42 29 47 43 57 C 65 81 74 125 73 174 C 87 192 76 211 48 211 L -23 211 C -48 207 -43 191 -32 177 C -42 126 -37 76 -18 50 Z',C.dog,C.ink,2.5),
  P('M -9 65 C 4 60 22 65 30 80 C 38 113 39 146 25 164 C 8 177 -16 163 -19 137 C -23 108 -18 80 -9 65 Z',C.cream,null),
  P('M 36 145 C 64 136 78 167 67 193 L 49 204 L 24 201 C 15 178 18 156 36 145 Z',C.dog,C.ink,2.2),
  E(47,207,53,20,C.cream,C.ink,2.2),
  P('M 43 207 L 43 214 M 55 207 L 55 214',null,C.ink,1.3),
],[0,0],0,{ks:{o:petVisibility}});
const dog=layer('Dog head',[
  P('M -44 -24 C -65 -66 -32 -74 4 -67 C 43 -65 63 -37 60 -1 C 65 36 33 61 -3 59 C -38 58 -59 26 -44 -24 Z',C.dog,C.ink,2.5),
  P('M -32 -55 C -68 -62 -85 -28 -77 6 C -75 30 -60 41 -48 25 C -40 10 -29 -31 -32 -55 Z',C.ear,C.ink,2.5),
  P('M 36 -47 C 58 -58 83 -25 81 2 C 81 35 67 46 53 29 C 43 15 36 -19 36 -47 Z',C.ear,C.ink,2.5),
  P('M -5 -65 C -12 -41 -7 -24 -16 -8 C -30 8 -22 37 3 49 C 28 44 33 24 22 4 C 9 -16 20 -31 12 -62 Z',C.cream,null),
  E(3,16,49,31,C.cream),
  P('M -8 3 C -4 -4 11 -4 16 3 C 17 14 2 17 -8 3 Z',C.ink,null),
  P('M 4 15 C -5 27 -16 22 -18 15 M 4 15 C 15 26 24 22 25 14',null,C.ink,2.5),
  P('M -6 27 C 1 31 10 32 17 26 L 15 37 C 12 48 -2 48 -5 37 Z',C.coral,C.ink,1.5),
  P('M -21 54 C -1 65 22 60 37 49 L 41 59 C 22 75 -2 77 -25 64 Z',C.teal,null),
], [467,193],0,{ks:{p:keys([[0,[390,260,0]],[27,[390,260,0]],[63,[467,193,0]],[143,[467,193,0]],[174,[390,260,0]],[180,[390,260,0]]]),o:petVisibility,r:keys([[0,0],[65,0],[85,9],[103,9],[118,0],[180,0]])}});
layers.find(item=>item.ind===dogBody).parent=dog;
layer('Dog eyes',[E(-24,-14,10,15,C.ink),E(27,-14,10,15,C.ink),E(-26,-17,3,4,C.white),E(25,-17,3,4,C.white)],[0,0],0,{parent:dog,ks:{o:petVisibility,s:keys([[0,[100,100,100]],[106,[100,100,100]],[111,[100,7,100]],[115,[100,100,100]],[180,[100,100,100]]])}});
function pouch(fill,icon){
  const shapes=[P('M -45 -67 L 44 -67 L 53 72 C 30 79 -31 79 -52 70 Z',fill,C.ink,1.8),R(-47,-75,93,15,4,fill,C.ink,1.8),R(-35,-32,69,69,12,C.cream),P('M -43 -55 L -34 -38 L -29 -55 Z','#FFFFFF',null)];
  if(icon==='bone')shapes.push(P('M -20 -5 C -31 -17 -20 -26 -12 -17 L 12 -17 C 20 -26 31 -17 20 -5 C 31 6 20 17 12 8 L -12 8 C -20 17 -31 6 -20 -5 Z',C.ink,null));
  else shapes.push(P('M -23 -5 L -22 -24 L -10 -17 C -3 -20 6 -20 13 -16 L 24 -24 L 24 -3 C 29 15 18 26 1 25 C -17 25 -29 13 -23 -5 Z',C.coral,null),E(-9,0,4,5,C.ink),E(12,0,4,5,C.ink),P('M -2 8 L 4 8 L 1 12 Z',C.ink,null));
  for(let j=0;j<9;j++)shapes.push(E(-27+j%5*13,54+Math.floor(j/5)*10,12,10,'#A87942',null));
  return shapes;
}
const right=layer('Cat food card',[R(-96,-134,192,270,16,C.white,C.ink,3),...pouch(C.coral,'cat'),R(-61,97,106,7,3,C.gray),R(-61,112,70,6,3,'#E8EDF2')],[362,282],4,{ks:{p:keys([[0,[362,303,0]],[31,[362,282,0]],[145,[362,282,0]],[180,[362,303,0]]])}});
const left=layer('Dog food card',[R(-100,-121,200,255,16,C.white,C.ink,3),...pouch(C.gold,'bone'),R(-62,97,107,7,3,C.gray),R(-62,112,72,6,3,'#E8EDF2')],[176,296],-5,{ks:{p:keys([[0,[176,314,0]],[25,[176,296,0]],[145,[176,296,0]],[180,[176,314,0]]])}});
const heart='M 0 10 C -8 4 -19 -4 -16 -13 C -13 -22 -3 -20 0 -14 C 5 -22 15 -21 18 -13 C 21 -4 9 4 0 10 Z';
for(const [parent,x,y] of [[left,70,-92],[right,66,-102]]){
  layer('Heart outline',[P(heart,null,C.ink,2)],[x,y],0,{parent});
  layer('Saved heart',[P(heart,C.coral,C.coral,2)],[x,y],0,{parent,ks:{o:keys([[0,0],[60,0],[75,100],[146,100],[171,0],[180,0]]),s:keys([[0,[100,100,100]],[70,[100,100,100]],[79,[118,118,100]],[90,[100,100,100]],[180,[100,100,100]]])}});
}
// Forepaws grip the card edges and disappear with the retreating pets.
layer('Cat paws',[E(-29,0,27,22,C.cream,C.ink,2),E(29,0,27,22,C.cream,C.ink,2),P('M -33 0 L -33 7 M -25 0 L -25 8 M 24 0 L 24 7 M 32 0 L 32 7',null,C.ink,1.3)],[0,-122],0,{parent:left,ks:{o:petVisibility}});
layer('Dog paw',[E(0,0,27,39,C.cream,C.ink,2),P('M -3 -9 L 7 -5 M -5 0 L 7 4',null,C.ink,1.3)],[97,-49],0,{parent:right,ks:{o:petVisibility}});
const clean = layers.map(({_shapes,...item})=>item).reverse();
const data={v:'5.12.2',fr:30,ip:0,op:180,w:640,h:460,nm:'Natalo Wishlist - pets saving product cards',ddd:0,assets:[],layers:clean,markers:[{tm:0,cm:'Cards arrive',dr:30},{tm:30,cm:'Pets peek',dr:30},{tm:60,cm:'Save favorites and blink',dr:60},{tm:120,cm:'Hold then reset',dr:60}]};
function at(prop,frame=135){if(!prop.a)return prop.k;const k=prop.k;let point=k[0];for(const p of k){if(p.t>frame)break;point=p;}return point.s;}
function transform(l){const p=at(l.ks.p),r=at(l.ks.r)[0]??at(l.ks.r),s=at(l.ks.s);return `translate(${p[0]} ${p[1]}) rotate(${r}) scale(${s[0]/100} ${s[1]/100})`;}
function shapeSvg(s){const style=`fill="${s.fill||'none'}" stroke="${s.stroke||'none'}" stroke-width="${s.width}" stroke-linecap="round" stroke-linejoin="round"`;return s.kind==='path'?`<path d="${s.d}" ${style}/>`:s.kind==='ellipse'?`<ellipse cx="${s.x}" cy="${s.y}" rx="${s.w/2}" ry="${s.h/2}" ${style}/>`:`<rect x="${s.x}" y="${s.y}" width="${s.w}" height="${s.h}" rx="${s.r}" ${style}/>`;}
let svg='<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 640 460">';
for(const l of layers){let chain=[l],parent=l.parent;while(parent){const p=layers.find(item=>item.ind===parent);chain.unshift(p);parent=p.parent;}svg+=chain.map(item=>`<g transform="${transform(item)}" opacity="${(Array.isArray(at(item.ks.o))?at(item.ks.o)[0]:at(item.ks.o))/100}">`).join('')+l._shapes.map(shapeSvg).join('')+'</g>'.repeat(chain.length);}
svg+='</svg>';
for(const folder of ['public/assets/lottie','flutter_app/assets/lottie']){
  fs.writeFileSync(path.join(root,folder,'wishlist-pets-cards-v1.json'),JSON.stringify(data));
}
fs.writeFileSync(path.join(root,'public/assets/images/wishlist-pets-cards-v1.svg'),svg);
console.log(`Wishlist vector Lottie: ${clean.length} layers, ${JSON.stringify(data).length} bytes, 6 second cycle.`);
