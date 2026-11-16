// Synthetic layout inspection from mocked TSX tree. Not SwiftUI, not an iPhone screenshot.
const {app}=require('../tests/google_photos_ui.cjs'),{createCanvas}=require('@napi-rs/canvas'),fs=require('node:fs'),assert=require('node:assert/strict');
async function preview(mode){
 const a=app();a.enable();await a.press('Verificar disponibilidade');a.answers.push(0);await a.press('Conectar Google Fotos');
 if(mode!=='local'){
  a.capture({id:'capture-cloud-20261116',original:'capture-cloud-20261116-original.jpg',file:'capture-cloud-20261116.jpg',capturedAt:1,profile:'PESSOAL',saved:false,storageIntent:'cloud'});
  a.receipt({captureId:'capture-cloud-20261116',status:mode,ownerSub:'owner',originalMediaItemId:'original-id',finalMediaItemId:'final-id',message:mode==='partial'?'Remoção parcial. O original já foi removido após verificação; a foto final ainda está local. Retome a verificação sem reenviar.':'Original e foto final verificados no Google Fotos; JPEGs removidos do Momentra. JSON e cache continuam no iPhone.'});
  await a.press('Ver foto selecionada');
 }
 await a.press('Consultar minhas fotos');
 const width=320,inset=18,usable=width-inset*2,measure=createCanvas(1,1).getContext('2d'),draw=[],rects=[];let y=24;
 function wrap(text,max){const lines=[];let line='';for(const word of text.split(/\s+/)){if(measure.measureText(line+(line?' ':'')+word).width<=max){line+=(line?' ':'')+word;continue}if(line)lines.push(line);line='';for(const ch of word){if(measure.measureText(line+ch).width>max){lines.push(line);line=''}line+=ch}}if(line)lines.push(line);return lines}
 function text(value,x,baseline,font,color){draw.push(ctx=>{ctx.font=font;ctx.fillStyle=color;ctx.fillText(value,x,baseline)})}
 function rect(x,top,w,h,color){draw.push(ctx=>{ctx.fillStyle=color;ctx.fillRect(x,top,w,h)})}
 text('SIMULAÇÃO · 320 pt · NÃO É IPHONE',inset,y,'bold 13px sans-serif','#4f5365');y+=26;
 for(const n of a.all()){
  if(n.type==='Text'&&typeof n.props.children==='string'){
   const font=n.props.font==='headline'?'bold 18px sans-serif':'14px sans-serif';measure.font=font;
   for(const line of wrap(n.props.children,usable)){assert.ok(measure.measureText(line).width<=usable);text(line,inset,y,font,'#242733');y+=20}y+=12;
  }else if(n.type==='Button'){
   measure.font='16px sans-serif';const lines=wrap(n.props.title,usable-20);assert.equal(lines.length,1,'button must fit: '+n.props.title);const h=Math.max(44,lines.length*22+16);
   rect(inset,y-12,usable,h,n.props.disabled?'#e3e4e9':'#dce9ff');lines.forEach((line,i)=>text(line,inset+10,y+10+i*22,'16px sans-serif',n.props.disabled?'#747780':'#1454b6'));
   rects.push({x:inset,width:usable,height:h});y+=h+12;
  }else if(n.type==='Image'){
   rect(inset,y,usable,180,'#d4d7df');text('Miniatura simulada (sem download)',inset+10,y+90,'14px sans-serif','#414857');y+=192;
  }
 }
 assert.ok(rects.every(r=>r.x+r.width<=width-inset&&r.height>=44));assert.equal(a.calls.upload.length,0);assert.equal(a.calls.archive.length,0);assert.equal(a.calls.open.length,0);
 // Allocate after measurement so long cloud status text cannot truncate the bottom.
 const canvas=createCanvas(width*2,Math.ceil((y+20)*2)),ctx=canvas.getContext('2d');ctx.scale(2,2);ctx.fillStyle='#f4f4f8';ctx.fillRect(0,0,width,y+20);draw.forEach(fn=>fn(ctx));
 fs.mkdirSync('.validation',{recursive:true});const name=mode==='local'?'photos-panel-320.png':'photos-panel-cloud-'+mode+'-320.png';fs.writeFileSync('.validation/'+name,canvas.toBuffer('image/png'));
 console.log('PASS synthetic '+mode+' width320: '+rects.length+' controls, '+Math.ceil(y+20)+'pt full height, no horizontal or vertical crop. Text wrapping simulated; native layout unverified.');
}
(async()=>{for(const mode of process.argv.includes('--cloud')?['partial','cloud-only']:['local'])await preview(mode)})().catch(e=>{console.error(e);process.exit(1)});
