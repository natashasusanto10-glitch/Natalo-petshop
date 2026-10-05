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
// Reuse the approved vector mascots and food artwork from the wishlist.
const source = JSON.parse(fs.readFileSync(path.join(root,'public/assets/lottie/wishlist-pets-cards-v1.json'),'utf8'));
function mascot(name,p,r=0,parent){
  const item=structuredClone(source.layers.find(l=>l.nm===name));
  item.ind=layers.length+1; item.ks={o:fixed(100),p:fixed([...p,0]),r:fixed(r),a:fixed([0,0,0]),s:fixed([100,100,100])};
  delete item.parent;if(parent)item.parent=parent;layers.push(item);return item.ind;
}
layer('Ground',[E(320,426,550,24,'#E9EFF5')]);
layer('Cat body',[
 P('M 108 278 C 89 303 91 362 108 395 L 185 395 C 208 368 203 308 182 280 Z',C.orange,C.ink),
 P('M 112 355 C 66 354 70 312 52 324 C 29 344 63 390 113 380 Z',C.orange,C.ink),
 E(145,330,49,86,C.cream),E(115,401,48,22,C.cream,C.ink),E(177,401,46,22,C.cream,C.ink),
]);
const cat=mascot('Cat head',[145,230]);
layers.find(l=>l.ind===cat).ks.r=keys([[0,-4],[40,3],[65,8],[95,0],[140,0],[165,-4],[180,-4]]);
const catEyes=mascot('Cat eyes',[0,0],0,cat);
layers.find(l=>l.ind===catEyes).ks.s=keys([[0,[100,100,100]],[99,[100,100,100]],[103,[100,8,100]],[108,[100,100,100]],[180,[100,100,100]]]);
const dogBody=mascot('Dog body',[0,0]);
const dog=mascot('Dog head',[489,210]);
layers.find(l=>l.ind===dogBody).parent=dog;
layers.find(l=>l.ind===dog).ks.r=keys([[0,3],[72,3],[98,-6],[122,0],[157,0],[180,3]]);
const dogEyes=mascot('Dog eyes',[0,0],0,dog);
layers.find(l=>l.ind===dogEyes).ks.s=keys([[0,[100,100,100]],[128,[100,100,100]],[132,[100,8,100]],[138,[100,100,100]],[180,[100,100,100]]]);
layer('Basket handle',[P('M 225 274 L 229 225 C 233 195 404 195 411 225 L 418 274',null,C.teal,12)]);
layer('Basket back',[P('M 208 264 L 429 264 L 406 404 L 233 404 Z','#A8D9EE',C.ink,3)]);
function product(name,position,rotation){
 const item=structuredClone(source.layers.find(l=>l.nm===name));
 // Card frame and text are removed: the pet holds the food pouch itself.
 // Pouch contains 4 base shapes, emblem (1 dog / 4 cat), and 9 kibbles.
 const max=name==='Dog food card'?14:17;
 item.shapes=source.layers.find(l=>l.nm===name).shapes.filter(g=>{const n=Number(g.nm.split(' ').at(-1));return n>=1&&n<=max;});
 item.ind=layers.length+1;delete item.parent;item.ks={o:keys([[0,100],[154,100],[169,0],[173,0],[180,100]]),p:position,r:rotation,a:fixed([0,0,0]),s:fixed([78,78,100])};
 layers.push(item);return item.ind;
}
const catPath=keys([[0,[177,294,0]],[18,[177,294,0]],[43,[246,198,0]],[57,[279,217,0]],[70,[281,292,0]],[154,[281,292,0]],[172,[177,294,0]],[180,[177,294,0]]]);
const dogPath=keys([[0,[464,296,0]],[65,[464,296,0]],[91,[384,191,0]],[104,[359,217,0]],[119,[355,292,0]],[154,[355,292,0]],[172,[464,296,0]],[180,[464,296,0]]]);
const catHand=[[0,[143,310,0]],[18,[143,310,0]],[43,[211,214,0]],[57,[245,232,0]],[66,[245,255,0]],[83,[177,318,0]],[154,[177,318,0]],[180,[143,310,0]]];
const dogHand=[[0,[497,310,0]],[65,[497,310,0]],[91,[418,208,0]],[104,[393,233,0]],[114,[393,258,0]],[131,[461,323,0]],[154,[461,323,0]],[180,[497,310,0]]];
function arm(name,shoulder,points,fill){
 const curve=([x,y])=>bezier(`M ${shoulder[0]} ${shoulder[1]} C ${shoulder[0]} ${shoulder[1]-20} ${x} ${y+20} ${x} ${y}`);
 const d=`M ${shoulder[0]} ${shoulder[1]} L ${points[0][1][0]} ${points[0][1][1]}`;
 const id=layer(name,[P(d,null,C.ink,19),P(d,null,fill,14)]);
 for(const group of layers.find(l=>l.ind===id).shapes){
   group.it.find(s=>s.ty==='sh').ks=keys(points.map(([t,p])=>[t,curve(p)]));
 }
}
arm('Cat arm',[185,300],catHand,C.orange);
arm('Dog arm',[472,292],dogHand,C.dog);
product('Dog food card',catPath,keys([[0,-12],[43,8],[70,-7],[154,-7],[180,-12]]));
product('Cat food card',dogPath,keys([[0,12],[91,-8],[119,6],[154,6],[180,12]]));
layer('Basket front',[
 P('M 208 277 L 429 277 L 406 405 C 365 417 271 417 233 405 Z','#258FC6',C.ink,3),
 R(199,264,238,20,8,'#54BCE8',C.ink,3),
 P('M 242 306 L 251 377 M 279 306 L 283 382 M 319 306 L 319 384 M 358 306 L 354 382 M 395 306 L 386 377',null,'#BFE8F7',8),
]);
// The paws carry each pouch along the same arc, release it, then return.
layer('Cat carrying paw',[E(0,0,26,22,C.cream,C.ink,2),P('M -5 0 L -5 5 M 3 0 L 3 5',null,C.ink,1.3)],[0,0],0,{ks:{p:keys(catHand)}});
layer('Dog carrying paw',[E(0,0,26,25,C.cream,C.ink,2),P('M -5 0 L -5 5 M 3 0 L 3 5',null,C.ink,1.3)],[0,0],0,{ks:{p:keys(dogHand)}});
const data={v:'5.12.2',fr:30,ip:0,op:180,w:640,h:460,nm:'Natalo Cart - pets put products into basket',ddd:0,assets:[],layers:layers.map(({_shapes,...l})=>l).reverse(),markers:[{tm:18,cm:'Cat puts food in basket',dr:52},{tm:65,cm:'Dog puts food in basket',dr:54},{tm:119,cm:'Happy pets hold',dr:35},{tm:154,cm:'Reset',dr:26}]};
for(const folder of ['public/assets/lottie','flutter_app/assets/lottie'])fs.writeFileSync(path.join(root,folder,'cart-pets-basket-v1.json'),JSON.stringify(data));
console.log(`Cart vector Lottie: ${data.layers.length} layers, ${JSON.stringify(data).length} bytes.`);
