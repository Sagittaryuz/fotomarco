const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),esbuild=require('esbuild');
const {createCanvas,loadImage}=require('@napi-rs/canvas');
const out=path.resolve(__dirname,'../.validation');fs.mkdirSync(out,{recursive:true});
esbuild.buildSync({entryPoints:[path.resolve(__dirname,'../core.ts'),path.resolve(__dirname,'../stamp.ts')],bundle:true,platform:'node',format:'cjs',outdir:out});
const c=require(out+'/core.js'),{drawStamp,fitText}=require(out+'/stamp.js');
let checks=0;function test(name,fn){fn();checks++;console.log('PASS '+name)}
const now=1794822600000,fix={latitude:-17.9,longitude:-51.7,timestamp:now};
const record={id:'synthetic',original:'',file:'',capturedAt:now,profile:'HAMOA',stamped:true,saved:false,fix,address:'Rua de teste · Exemplo',warnings:[]};
test('invalid storage is recovered',()=>{assert.deepEqual(c.normalizeSettings(null),c.defaults());assert.equal(c.normalizeSettings({profile:'BAD',gps:'yes',profiles:{HAMOA:{title:'',note:'a\nb'}}}).profiles.HAMOA.note,'a b')});
test('profiles persist independently',()=>{const s=c.defaults();s.profiles.HAMOA.note='Academia';s.profile='PIRESCO';assert.equal(c.normalizeSettings(s).profiles.HAMOA.note,'Academia');assert.equal(c.normalizeSettings(s).profiles.PIRESCO.note,'')});
test('GPS valid/future/stale/bounds/missing',()=>{assert.deepEqual(c.validFix(fix,now),fix);assert.equal(c.validFix({...fix,timestamp:now-60001},now),null);assert.equal(c.validFix({...fix,timestamp:now+5001},now),null);assert.equal(c.validFix({...fix,latitude:91},now),null);assert.equal(c.validFix(null,now),null)});
test('dimensions never upsample or distort aspect',()=>{assert.deepEqual(c.outputSize(4032,3024),{width:3072,height:2304});assert.deepEqual(c.outputSize(320,240),{width:320,height:240});assert.throws(()=>c.outputSize(0,2))});
test('GPS off never leaks coordinates or address into stamp',()=>{const lines=c.stampLines(c.defaults(),record).join(' ');assert.ok(!lines.includes('-17.9'));assert.ok(!lines.includes('Rua'))});
test('missing GPS not silently labeled current',()=>{const s=c.defaults();s.gps=true;assert.ok(c.stampLines(s,{...record,fix:null}).includes('GPS indisponível no disparo'))});
test('EXIF 5–8 swaps encoded axes',()=>{assert.deepEqual(c.orientedSize(4032,3024,6),{width:3024,height:4032});assert.deepEqual(c.orientedSize(4032,3024,1),{width:4032,height:3024})});
test('timestamp includes local UTC offset',()=>assert.match(c.dateLabel(now),/UTC[+−]\d{2}:\d{2}/));
for(const size of [[1200,1600],[1600,1200],[320,240],[3072,4096]])for(const position of ['top','bottom'])for(const compact of ['compact','regular']){
 const s=c.defaults();s.position=position;s.size=compact;s.gps=true;
 test(`layout ${size} ${position} ${compact}`,()=>{const b=c.layoutStamp(...size,5,s,true,true);assert.ok(b.x>=0&&b.y>=0&&b.x+b.w<=size[0]&&b.y+b.h<=size[1]);assert.ok(b.textW>0)})
}
function makePreview(w,h,file,mapOn=false,logoOn=false){
 const canvas=createCanvas(w,h),ctx=canvas.getContext('2d');
 const g=ctx.createLinearGradient(0,0,w,h);g.addColorStop(0,'#7b9ca4');g.addColorStop(1,'#243844');ctx.fillStyle=g;ctx.fillRect(0,0,w,h);
 ctx.fillStyle='#c8bca2';ctx.fillRect(w*.1,h*.3,w*.7,h*.5);ctx.fillStyle='#829095';ctx.fillRect(w*.1,h*.3,w*.7,h*.05);
 ctx.fillStyle='#2f4349';for(let i=0;i<4;i++)ctx.fillRect(w*(.16+i*.16),h*.42,w*.1,h*.18);
 const map=createCanvas(170,170);let m=map.getContext('2d');m.fillStyle='#47603e';m.fillRect(0,0,170,170);m.fillStyle='#c1b79e';m.fillRect(70,0,20,170);m.fillRect(0,70,170,20);m.fillStyle='#f05948';m.beginPath();m.arc(85,85,7,0,Math.PI*2);m.fill();
 const logo=createCanvas(180,70);let l=logo.getContext('2d');l.fillStyle='white';l.fillRect(0,0,180,70);l.fillStyle='#244941';l.font='bold 24px sans-serif';l.fillText('MARCA',38,43);
 const adapter={get fillStyle(){return ctx.fillStyle},set fillStyle(v){ctx.fillStyle=v},set font(v){ctx.font=`${v}px sans-serif`},set textBaseline(v){ctx.textBaseline=v},fillRect:(...a)=>ctx.fillRect(...a),fillText:(...a)=>ctx.fillText(...a),measureText:t=>ctx.measureText(t),drawImage:(source,...a)=>ctx.drawImage(source.image,...a)};
 const s=c.defaults();s.gps=true;s.profiles.HAMOA.note='Registro de serviço • foto sintética de teste';
 drawStamp(adapter,w,h,s,record,mapOn?{image:map}:null,logoOn?{image:logo}:null);
 fs.writeFileSync(out+'/'+file,canvas.toBuffer('image/png'));
 const p=ctx.getImageData(40,h-50,1,1).data;assert.ok(p[3]>0);
}
makePreview(900,1200,'portrait.png',true,true);makePreview(1200,900,'landscape.png',true,true);makePreview(360,480,'small.png');
test('actual pixels rendered for three synthetic photo sizes',()=>assert.equal(fs.existsSync(out+'/portrait.png'),true));
(async()=>{const value=await c.within(new Promise(()=>{}),10,null);assert.equal(value,null);assert.equal(await c.within(Promise.resolve(7),100,null),7);checks++;console.log('PASS bounded network timeout + fast response');console.log(`${checks} core/layout/render checks passed. Synthetic Canvas adapter, not native iPhone rendering.`)})().catch(e=>{console.error(e);process.exit(1)});
