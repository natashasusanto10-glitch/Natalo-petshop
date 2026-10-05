import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import vm from "node:vm";
import { test } from "node:test";
import ts from "typescript";
import sharp from "sharp";
import { gzipSync } from "node:zlib";

const root = process.cwd();
const manifest = JSON.parse(fs.readFileSync(path.join(root,"components/home/shortcut-assets.json"),"utf8")) as Record<string,{animation:string;still:string}>;

test("all eight delivery compositions have valid, compact image references", async () => {
  assert.equal(Object.keys(manifest).length,8);
  let wireBytes=0;
  const seen=new Set<string>();
  for(const entry of Object.values(manifest)) {
    for(const url of [entry.animation,entry.still]) {
      const bytes=fs.readFileSync(path.join(root,"public",url));
      wireBytes+=gzipSync(bytes).length;
    }
    const composition=JSON.parse(fs.readFileSync(path.join(root,"public",entry.animation),"utf8"));
    assert.equal(composition.fr,30);
    assert.ok(composition.layers.length);
    const assetIds=new Set(composition.assets.map((a:{id:string})=>a.id));
    for(const asset of composition.assets) {
      if(asset.p) {
        const file=path.join(root,"public",asset.u,asset.p);
        const metadata=await sharp(file).metadata();
        assert.equal(metadata.format,"webp");
        assert.ok(Math.max(metadata.width!,metadata.height!)<=384);
        if(!seen.has(file)){wireBytes+=fs.statSync(file).size;seen.add(file);}
      }
      for(const layer of asset.layers||[]) if(layer.refId) assert.ok(assetIds.has(layer.refId));
      for(const layer of asset.layers||[]) {
        if(layer.masksProperties) assert.equal(layer.hasMask,true);
        for(const shape of layer.shapes||[]) {
          if(shape.ty==='st'&&shape.d) {
            assert.equal(new Set(shape.d.map((d:{nm:string})=>d.nm)).size,shape.d.length);
            assert.ok(shape.d.every((d:{nm:string})=>d.nm));
            assert.ok(shape.d.some((d:{n:string})=>d.n==='o'));
          }
        }
      }
    }
  }
  assert.ok(wireBytes<400_000,`Delivered artwork is ${wireBytes} bytes`);
});

function mount(reduced=false) {
  const effects:Array<()=>()=>void>=[],observers:Array<{callback: (entries:{isIntersecting:boolean}[])=>void;disconnected:boolean}>=[];
  const listeners=new Map<string,()=>void>();
  const media={matches:reduced,addEventListener:(_:string,fn:()=>void)=>listeners.set("motion",fn),removeEventListener:()=>listeners.delete("motion")};
  const doc={visibilityState:"visible",addEventListener:(key:string,fn:()=>void)=>listeners.set(key,fn),removeEventListener:(key:string)=>listeners.delete(key)};
  const calls={loads:0,plays:0,pauses:0,destroys:0,subframe:true};
  const instance={play:()=>calls.plays++,pause:()=>calls.pauses++,destroy:()=>calls.destroys++,setSubframe:(v:boolean)=>{calls.subframe=v;},addEventListener:(event:string,fn:()=>void)=>{if(event==="DOMLoaded")queueMicrotask(fn);}};
  const react={useRef:()=>({current:{}}),useState:()=>[false,()=>{}],useEffect:(fn:()=>()=>void)=>effects.push(fn)};
  const source=fs.readFileSync(path.join(root,"components/home/AnimatedShortcutIcon.tsx"),"utf8");
  const compiled=ts.transpileModule(source,{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2017,jsx:ts.JsxEmit.ReactJSX,esModuleInterop:true}}).outputText;
  const exports:Record<string,(props:{artwork:string})=>unknown>={};
  class Observer {
    disconnected=false;
    constructor(public callback:(entries:{isIntersecting:boolean}[])=>void){observers.push(this);}
    observe(){}
    disconnect(){this.disconnected=true;}
  }
  const context=vm.createContext({exports,require:(name:string)=>{
    if(name==="react")return react;
    if(name==="react/jsx-runtime")return {jsx:()=>null,jsxs:()=>null};
    if(name.endsWith("shortcut-assets.json"))return manifest;
    if(name==="lottie-web")return {loadAnimation:(options:{loop:boolean;autoplay:boolean})=>{assert.equal(options.loop,true);assert.equal(options.autoplay,false);calls.loads++;return instance;}};
    throw Error(name);
  },window:{matchMedia:()=>media},document:doc,IntersectionObserver:Observer,fetch:async()=>({ok:true,json:async()=>({})}),structuredClone,queueMicrotask,console});
  vm.runInContext(compiled,context);
  exports.AnimatedShortcutIcon({artwork:"cat-food"});
  const cleanup=effects[0]();
  return {calls,observers,listeners,media,doc,cleanup};
}
const flush=()=>new Promise<void>(resolve=>setImmediate(resolve));

test("only visible shortcuts play; leaving the screen or tab pauses and unmount destroys",async()=>{
  const m=mount();
  assert.equal(m.calls.loads,0);
  m.observers[0].callback([{isIntersecting:true}]);
  await flush();
  assert.equal(m.calls.loads,1);
  assert.equal(m.calls.subframe,false);
  assert.equal(m.calls.plays,0);
  m.observers[1].callback([{isIntersecting:true}]);
  assert.ok(m.calls.plays>0);
  const paused=m.calls.pauses;
  m.observers[1].callback([{isIntersecting:false}]);
  assert.ok(m.calls.pauses>paused);
  m.observers[1].callback([{isIntersecting:true}]);
  m.doc.visibilityState="hidden";
  m.listeners.get("visibilitychange")!();
  m.cleanup();
  assert.equal(m.calls.destroys,1);
  assert.ok(m.observers.every(o=>o.disconnected));
  assert.equal(m.listeners.size,0);
});

test("reduced motion initially uses a still and loads animation when preference changes",async()=>{
  const m=mount(true);
  m.observers[0].callback([{isIntersecting:true}]);
  m.observers[1].callback([{isIntersecting:true}]);
  await flush();
  assert.equal(m.calls.loads,0);
  m.media.matches=false;
  m.listeners.get("motion")!();
  await flush();
  assert.equal(m.calls.loads,1);
  assert.ok(m.calls.plays>0);
  m.media.matches=true;
  const before=m.calls.pauses;
  m.listeners.get("motion")!();
  assert.ok(m.calls.pauses>before);
  m.cleanup();
});
