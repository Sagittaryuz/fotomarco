// Synthetic diagram from the same geometry as the native layout. NOT an iPhone screenshot.
const fs=require('node:fs'),vm=require('node:vm'),esbuild=require('esbuild'),{createCanvas}=require('@napi-rs/canvas');
const code=esbuild.buildSync({entryPoints:['camera_layout.ts'],bundle:true,write:false,format:'cjs'}).outputFiles[0].text;
const scope={module:{exports:{}},exports:{}};vm.runInNewContext(code,scope);const {cameraLayout}=scope.module.exports;
const core=require('../.validation/core.js'),{drawStamp}=require('../.validation/stamp.js');
fs.mkdirSync('.validation',{recursive:true});
for(const [name,w,h] of [['camera-portrait',390,844],['camera-small',320,568],['camera-landscape',844,390]]){
 const l=cameraLayout(w,h),c=createCanvas(w*2,h*2),x=c.getContext('2d');x.scale(2,2);x.fillStyle='black';x.fillRect(0,0,w,h);
 function text(s,a,b,size=14,color='white'){x.font=`${size}px sans-serif`;x.textAlign='center';x.fillStyle=color;x.fillText(s,a,b)}
 function circle(a,b,r,color,stroke=false){x.beginPath();x.arc(a,b,r,0,Math.PI*2);x[stroke?'strokeStyle':'fillStyle']=color;stroke?x.stroke():x.fill()}
 const left=(w-l.viewWidth)/2,top=(h-l.viewHeight-l.shutter-l.mode-2*l.gap)/2;
 const g=x.createLinearGradient(0,top,w,top+l.viewHeight);g.addColorStop(0,'#5d7275');g.addColorStop(1,'#293b3f');x.fillStyle=g;x.fillRect(left,top,l.viewWidth,l.viewHeight);
 x.fillStyle='#738782';x.fillRect(left+l.viewWidth*.2,top+l.viewHeight*.25,l.viewWidth*.6,l.viewHeight*.5);
 text('VISOR AO VIVO',w/2,top+l.viewHeight*.48,16,'#e4ecea');text('Cena sintética de validação',w/2,top+l.viewHeight*.53,10,'#c6d5d0');
 for(const [cx,labels] of [[left+24,['▣','☷','T']],[left+l.viewWidth-24,['⌖','☀','▧']]]){
  const rail=Math.min(l.railHeight,148),y=top+(l.viewHeight-rail)/2;
  labels.forEach((s,i)=>{if((i+.5)*50<rail){circle(cx,y+22+i*50,22,'rgba(20,25,28,.7)');text(s,cx,y+28+i*50,19)}})
 }
 const sample=core.defaults();sample.gps=true;sample.map=true;sample.timestampCorner='top-right';sample.mapCorner='top-left';sample.logoCorner='bottom-right';
 const map=createCanvas(60,60),mc=map.getContext('2d');mc.fillStyle='#47603e';mc.fillRect(0,0,60,60);mc.fillStyle='#bba';mc.fillRect(25,0,8,60);mc.fillRect(0,25,60,8);
 const logo=createCanvas(80,30),lc=logo.getContext('2d');lc.fillStyle='white';lc.fillRect(0,0,80,30);lc.fillStyle='black';lc.font='14px sans-serif';lc.fillText('MARCA',10,20);
 x.save();x.translate(left,top);x.textAlign='left';
 const adapter={set fillStyle(v){x.fillStyle=v},set font(v){x.font=typeof v==='number'?`${v}px sans-serif`:`${v.size}px ${v.name}`},set textBaseline(v){x.textBaseline=v},fillRect:(...a)=>x.fillRect(...a),fillText:(...a)=>x.fillText(...a),measureText:t=>x.measureText(t),drawImage:(source,...a)=>x.drawImage(source.image,...a)};
 drawStamp(adapter,l.viewWidth,l.viewHeight,sample,{profile:'HAMOA',capturedAt:1794822644000,fix:{latitude:0,longitude:0,timestamp:1794822644000},address:'Endereço sintético'}, {image:map},{image:logo},true);x.restore();
 ['⚡','◷','4:3','⚙'].forEach((s,i)=>{const cx=left+l.viewWidth*(i+.5)/4;circle(cx,top+22,22,'rgba(20,25,28,.7)');text(s,cx,top+28,18)});
 const statusY=top+l.viewHeight-l.status;text('Pronta',left+42,statusY+26,11,'#ccc');for(const [cx,t] of [[left+l.viewWidth-70,'↑'],[left+l.viewWidth-22,'×']]){circle(cx,statusY+22,22,'rgba(20,25,28,.7)');text(t,cx,statusY+28,19)};
 const sy=top+l.viewHeight+l.gap+l.shutter/2;circle(w/2,sy,l.shutter/2-2,'white',true);circle(w/2,sy,l.shutter/2-9,'white');const sw=Math.min(w-32,380),lx=(w-sw)/2+22,rx=(w+sw)/2-22;circle(lx,sy,22,'#252527');circle(rx,sy,22,'#252527');text('▧',lx,sy+7,19);text('↓',rx,sy+7,19);
 const py=sy+l.shutter/2+l.gap, pw=Math.min(w-48,280);x.fillStyle='#252527';x.beginPath();x.roundRect((w-pw)/2,py,pw,44,22);x.fill();x.fillStyle='#646469';x.beginPath();x.roundRect(w/2,py+3,pw/2-3,38,19);x.fill();text('Vídeo',w/2-pw/4,py+28,14);text('Câmera',w/2+pw/4,py+28,14);
 fs.writeFileSync(`.validation/${name}.png`,c.toBuffer('image/png'));
}
