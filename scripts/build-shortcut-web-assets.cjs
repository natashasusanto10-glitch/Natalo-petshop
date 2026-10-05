// Web delivery copies; the approved Flutter assets remain the source of truth.
const fs = require('node:fs/promises');
const path = require('node:path');
const crypto = require('node:crypto');
const sharp = require('sharp');
const source = path.resolve(__dirname, '../flutter_app/assets/lottie/shortcuts');
const target = path.resolve(__dirname, '../public/assets/lottie/shortcuts');
const specs = [
  ['cat-food', 'cat-food-coral.png', '140 40 1200 1000'],
  ['dog-food', 'dog-food-gold.png', '140 40 1200 1000'],
  ['fish-food', 'fish-food-teal.png', '180 30 1200 1000'],
  ['medicine', 'medicine-warm.png', '160 175 1000 1000'],
  ['promo'], ['new-products', 'products-color.png', '70 70 1120 1120'],
  ['voucher'], ['points', 'nl-point-coin.png'],
];
const hash = bytes => crypto.createHash('sha256').update(bytes).digest('hex').slice(0,12);
const generated = new Set();
// Keep the ends of static holds; intermediate identical samples add no motion.
function compact(value) {
  if (!value || typeof value !== 'object') return;
  // The SVG player only normalizes relative mask tangents when hasMask is set.
  if (Array.isArray(value.masksProperties)) value.hasMask = true;
  if (value.ty === 'st' && Array.isArray(value.d)) {
    value.d.forEach((dash,i)=>{dash.nm=`${dash.n==='d'?'Dash':'Gap'} ${i+1}`;});
    if (!value.d.some(d=>d.n==='o')) value.d.push({n:'o',nm:'Offset',v:{a:0,k:0}});
  }
  if (value.a === 1 && Array.isArray(value.k) && value.k[0]?.t !== undefined) {
    value.k = value.k.filter((frame, i, all) => !i || i === all.length-1 ||
      JSON.stringify(all[i-1].s) !== JSON.stringify(frame.s) ||
      JSON.stringify(all[i+1].s) !== JSON.stringify(frame.s));
  }
  Object.values(value).forEach(compact);
}
async function main() {
  await fs.mkdir(target, {recursive:true});
  const imageFiles = new Map();
  for (const file of (await fs.readdir(source)).filter(f=>f.endsWith('.png'))) {
    const bytes = await sharp(path.join(source,file)).resize({width:384,height:384,fit:'inside',withoutEnlargement:true}).webp({quality:85,alphaQuality:100,effort:6}).toBuffer();
    const name = `${path.parse(file).name}.${hash(bytes)}.webp`;
    await fs.writeFile(path.join(target,name),bytes);
    generated.add(name);
    imageFiles.set(file,{name,bytes});
  }
  const manifest = {};
  for (const [id,png,box] of specs) {
    const data = JSON.parse(await fs.readFile(path.join(source,id+'.json'),'utf8'));
    for (const asset of data.assets) if(asset.p) {
      asset.p=imageFiles.get(asset.p).name;
      asset.u='/assets/lottie/shortcuts/';
    }
    compact(data);
    const json=Buffer.from(JSON.stringify(data)),jsonName=`${id}.${hash(json)}.json`;
    await fs.writeFile(path.join(target,jsonName),json);
    generated.add(jsonName);
    let svg;
    if (png) {
      const metadata=await sharp(path.join(source,png)).metadata();
      const image=imageFiles.get(png);
      const view=box||`0 0 ${metadata.width} ${metadata.height}`;
      svg=`<svg xmlns="http://www.w3.org/2000/svg" viewBox="${view}"><image width="${metadata.width}" height="${metadata.height}" href="data:image/webp;base64,${image.bytes.toString('base64')}"/></svg>`;
    } else if(id==='promo') {
      svg='<svg xmlns="http://www.w3.org/2000/svg" viewBox="120 30 1040 1170"><path d="M553 125C590 220 588 317 477 450Q444 380 385 347C390 492 288 546 239 684C151 908 288 1129 626 1138C890 1147 1120 962 1047 701C1012 566 958 450 900 380Q899 515 816 541C845 345 795 174 553 125Z" fill="#F34343" stroke="#063B75" stroke-width="36" stroke-linejoin="round"/><g fill="none" stroke="#FFD45A" stroke-width="62"><circle cx="510" cy="680" r="64"/><circle cx="751" cy="863" r="64"/><path d="M505 918L759 619" stroke-linecap="round"/></g></svg>';
    } else {
      svg='<svg xmlns="http://www.w3.org/2000/svg" viewBox="40 100 920 740"><g transform="rotate(-8 500 430)"><path d="M130 240H870Q900 240 900 270V383C834 383 834 477 900 477V590Q900 620 870 620H130Q100 620 100 590V477C166 477 166 383 100 383V270Q100 240 130 240Z" fill="#129B8C"/><path d="M130 240H500V620H130Q100 620 100 590V477C166 477 166 383 100 383V270Q100 240 130 240Z" fill="#7654C7"/><path d="M500 251V613" stroke="white" stroke-width="10" stroke-dasharray="15 18"/><g fill="none" stroke="#FFF6E5" stroke-width="28"><circle cx="267" cy="359" r="34"/><circle cx="377" cy="497" r="34"/><path d="M254 517L390 337" stroke-linecap="round"/></g><g fill="white" transform="translate(0 20)"><rect x="572" y="326" width="152" height="135" rx="13"/><path d="M735 365H782Q790 365 795 376L822 427V461H735Z"/><path d="M750 382H778L797 412H750Z" fill="#129B8C"/><g stroke="#129B8C" stroke-width="8"><circle cx="611" cy="466" r="27"/><circle cx="784" cy="466" r="27"/></g></g></g></svg>';
    }
    const svgBytes=Buffer.from(svg),stillName=`${id}-still.${hash(svgBytes)}.svg`;
    await fs.writeFile(path.join(target,stillName),svgBytes);
    generated.add(stillName);
    manifest[id]={animation:`/assets/lottie/shortcuts/${jsonName}`,still:`/assets/lottie/shortcuts/${stillName}`};
  }
  await fs.writeFile(path.resolve(__dirname,'../components/home/shortcut-assets.json'),JSON.stringify(manifest,null,2)+'\n');
  // Only retire this builder's obsolete content hashes in its output directory.
  for (const old of await fs.readdir(target)) {
    if (!generated.has(old) && /^[a-z-]+\.[a-f0-9]{12}\.(json|svg|webp)$/.test(old)) {
      const file=path.resolve(target,old);
      if(path.dirname(file)!==target) throw Error('Unexpected asset path');
      await fs.unlink(file);
    }
  }
  const files=await fs.readdir(target);
  const bytes=(await Promise.all(files.map(f=>fs.stat(path.join(target,f))))).reduce((sum,s)=>sum+s.size,0);
  console.log(`Web shortcut delivery: ${files.length} files, ${(bytes/1048576).toFixed(2)} MiB (uncompressed)`);
}
main().catch(error=>{console.error(error);process.exitCode=1;});
