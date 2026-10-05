import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";
import { test } from "node:test";
import ts from "typescript";

test("rejected autoplay cannot retry itself through the slot release callback", async () => {
  const effects: Array<() => () => void> = [];
  let notify: () => void = () => {};
  let intersect: (entries: {isIntersecting:boolean;intersectionRatio:number}[]) => void = () => {};
  let plays = 0;
  let releases = 0;
  const video = {
    paused: true,
    pause() {},
    play() {
      plays++;
      // A second unresolved call makes the old feedback loop fail safely
      // in this test instead of freezing the test process.
      return plays === 1 ? Promise.reject(new Error("Autoplay denied")) : new Promise<void>(() => {});
    },
  };
  let refs = 0;
  const react = {
    useId: () => "test-video",
    useRef: () => ({ current: ++refs === 1 ? {} : video }),
    useState: () => [false, () => {}],
    useEffect: (fn: () => () => void) => effects.push(fn),
  };
  class Observer {
    constructor(callback: typeof intersect) { intersect = callback; }
    observe() {}
    disconnect() {}
  }
  const source = fs.readFileSync("components/product/ProductCardVideo.tsx", "utf8");
  const compiled = ts.transpileModule(source, {compilerOptions: {
    module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020,
    jsx: ts.JsxEmit.ReactJSX, esModuleInterop: true,
  }}).outputText;
  const exports: Record<string, (props: {mp4Url:string;poster:null;alt:string}) => unknown> = {};
  vm.runInNewContext(compiled, {exports, IntersectionObserver:Observer, require: (name:string) => {
    if (name === "react") return react;
    if (name === "react/jsx-runtime") return {jsx: () => null, jsxs: () => null};
    if (name === "next/image") return () => null;
    if (name.includes("image-placeholder")) return {};
    if (name.includes("video-autoplay-registry")) return {
      requestPlay: () => true,
      releasePlay: () => { releases++; notify(); },
      subscribeSlotFree: (fn: () => void) => { notify = fn; return () => { notify = () => {}; }; },
    };
    throw Error(name);
  }});
  exports.ProductCardVideo({mp4Url:"https://example.test/video.mp4", poster:null, alt:"Product"});
  const cleanup = effects[0]();
  intersect([{isIntersecting:true, intersectionRatio:1}]);
  await new Promise<void>(resolve => setImmediate(resolve));
  assert.equal(plays, 1);
  assert.equal(releases, 1);
  notify();
  intersect([{isIntersecting:false, intersectionRatio:0}]);
  intersect([{isIntersecting:true, intersectionRatio:1}]);
  assert.equal(plays, 1, "Failed videos stay on their poster until remount");
  cleanup();
});
