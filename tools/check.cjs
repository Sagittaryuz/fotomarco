const fs = require('node:fs'), path = require('node:path'), esbuild = require('esbuild'), ts = require('typescript');
(async()=>{
  const root=path.resolve(__dirname,'..');
  const m=JSON.parse(fs.readFileSync(path.join(root,'script.json'),'utf8'));
  for(const key of ['name','version','icon','color']) if(!m[key]) throw Error('Missing manifest '+key);
  if(m.version!=='0.7.0') throw Error('Version mismatch');
  const program=ts.createProgram([path.join(root,'core.ts'),path.join(root,'stamp.ts'),path.join(root,'camera_layout.ts'),path.join(root,'meteorology.ts')],{strict:true,noEmit:true,target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.CommonJS,lib:['lib.es2022.d.ts','lib.dom.d.ts']});
  const errors=ts.getPreEmitDiagnostics(program); if(errors.length) throw Error(ts.formatDiagnosticsWithColorAndContext(errors,{getCanonicalFileName:x=>x,getCurrentDirectory:()=>root,getNewLine:()=> '\n'}));
  await esbuild.build({entryPoints:[path.join(root,'index.tsx')],bundle:true,write:false,format:'esm',target:'es2022',jsx:'automatic',jsxImportSource:'scripting',external:['scripting','scripting/jsx-runtime']});
  const index=fs.readFileSync(path.join(root,'index.tsx'),'utf8');
  if(/shouldMoveFile/.test(index)) throw Error('Invalid Photos API option');
  if(/import\s*\{[^}]*\b(FileManager|Photos|Location|UIImage)\b[^}]*\}\s*from\s*["']scripting/s.test(index)) throw Error('Global API incorrectly imported');
  console.log('PASS manifest, strict pure-core TypeScript, complete TSX/module syntax and documented globals. Native host typecheck NOT RUN: requires device-synced declarations.');
})().catch(e=>{console.error(e);process.exit(1)});
