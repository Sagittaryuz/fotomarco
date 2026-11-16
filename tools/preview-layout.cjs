// Synthetic diagram from the same geometry as the native layout. NOT an iPhone screenshot.
const fs=require('node:fs'),vm=require('node:vm'),esbuild=require('esbuild'),{createCanvas}=require('@napi-rs/canvas');
const code=esbuild.buildSync({entryPoints:['camera_layout.ts'],bundle:true,write:false,format:'cjs'}).outputFiles[0].text;
const scope={module:{exports:{}},exports:{}};vm.runInNewContext(code,scope);const {cameraLayout}=scope.module.exports;
fs.mkdirSync('.validation',{recursive:true});
for(const [name,w,h] of [['camera-portrait',390,844],['camera-small',320,568],['camera-landscape',844,390]]){
 const l=cameraLayout(w,h),c=createCanvas(w*2,h*2),x=c.getContext('2d');x.scale(2,2);x.fillStyle='black';x.fillRect(0,0,w,h);
 function text(s,a,b,size=14,color='white'){x.font=`${size}px sans-serif`;x.textAlign='center';x.fillStyle=color;x.fillText(s,a,b)}
 function circle(a,b,r,color,stroke=false){x.beginPath();x.arc(a,b,r,0,Math.PI*2);x[stroke?'strokeStyle':'fillStyle']=color;stroke?x.stroke():x.fill()}
 ['⚡','◷','4:3','⚙'].forEach((s,i)=>text(s,w*(i+0.5)/4,l.toolbar/2+6,20));
 const left=(w-l.viewWidth)/2,top=l.toolbar+l.gap;
 const g=x.createLinearGradient(0,top,w,top+l.viewHeight);g.addColorStop(0,'#5d7275');g.addColorStop(1,'#293b3f');x.fillStyle=g;x.fillRect(left,top,l.viewWidth,l.viewHeight);
 x.fillStyle='#738782';x.fillRect(left+l.viewWidth*.2,top+l.viewHeight*.25,l.viewWidth*.6,l.viewHeight*.5);
 text('VISOR AO VIVO',w/2,top+l.viewHeight*.48,16,'#e4ecea');text('Cena sintética de validação',w/2,top+l.viewHeight*.53,10,'#c6d5d0');
 for(const [cx,labels] of [[left+24,['▣','☷','T']],[left+l.viewWidth-24,['⌖','☀','▧']]]){
  const rail=Math.min(l.railHeight,142),y=top+(l.viewHeight-rail)/2;x.fillStyle='rgba(20,25,28,.7)';x.beginPath();x.roundRect(cx-24,y,48,rail,24);x.fill();
  labels.forEach((s,i)=>{if((i+.5)*46<rail)text(s,cx,y+(i+.6)*46,19)})
 }
 const statusY=top+l.viewHeight+l.gap;text('Pronta para fotografar',w/2,statusY+18,11,'#ccc');
 const sy=statusY+l.status+l.gap+l.shutter/2;circle(w/2,sy,l.shutter/2-2,'white',true);circle(w/2,sy,l.shutter/2-9,'white');text('▧',42,sy+7,24);text('↓',w-42,sy+7,24);
 const py=sy+l.shutter/2+l.gap, pw=Math.min(w-48,280);x.fillStyle='#252527';x.beginPath();x.roundRect((w-pw)/2,py,pw,44,22);x.fill();x.fillStyle='#646469';x.beginPath();x.roundRect(w/2,py+3,pw/2-3,38,19);x.fill();text('Vídeo',w/2-pw/4,py+28,14);text('Câmera',w/2+pw/4,py+28,14);
 fs.writeFileSync(`.validation/${name}.png`,c.toBuffer('image/png'));
}
