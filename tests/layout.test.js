'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const vm=require('node:vm');
const {execFileSync}=require('node:child_process');
const root=path.join(__dirname,'..');
const html=fs.readFileSync(path.join(root,'docs/layout.html'),'utf8');

test('the shareable illustration matches the interactive controls and symbols',()=>{
 execFileSync(process.execPath,[path.join(root,'scripts/layout-preview.js'),'--check']);
});

test('the preview check rejects a control-title change with stale wrapped text',()=>{
 const changed=html.replace("'New chat'","'New session'");
 assert.notEqual(changed,html);
 const isolatedRequire=name=>name==='node:fs'?{...fs,readFileSync:(file,...args)=>
  file===path.join(root,'docs/layout.html')?changed:fs.readFileSync(file,...args)}:require(name);
 const script=fs.readFileSync(path.join(root,'scripts/layout-preview.js'),'utf8');
 assert.throws(()=>vm.runInNewContext(script,{require:isolatedRequire,__dirname:path.join(root,'scripts'),
  process:{argv:['node','layout-preview.js','--check']},console}),/Preview label does not match/);
});

function layout(){
 function element(){
  const item={dataset:{},attributes:{},properties:{},children:[],events:{},selected:false};
  item.setAttribute=(name,value)=>{item.attributes[name]=value;};
  item.style={setProperty:(name,value)=>{item.properties[name]=value;}};
  item.classList={toggle:(_,value)=>{item.selected=value;}};
  item.append=child=>item.children.push(child);
  item.addEventListener=(name,callback)=>{item.events[name]=callback;};
  return item;
 }
 const ids=Object.fromEntries(['caps','actions','action-title','action-detail','workspace'].map(id=>[id,element()]));
 const layers=[1,2,3,4].map(n=>{const button=element();button.dataset.layer=String(n);return button;});
 const document={documentElement:element(),createElement:element,getElementById:id=>ids[id],
  querySelectorAll:selector=>selector==='[data-layer]'?layers:[...ids.caps.children,...ids.actions.children]};
 vm.runInNewContext(html.match(/<script>([\s\S]*?)<\/script>/)[1],{document});
 return {ids,layers};
}

test('the illustrated caps and action view share all fifteen grid positions',()=>{
 const {ids}=layout();
 assert.equal(ids.caps.children.length,15);
 assert.equal(ids.actions.children.length,15);
 for(let index=0;index<15;index++){
  const cap=ids.caps.children[index],action=ids.actions.children[index];
  assert.equal(cap.dataset.action,action.dataset.action);
  assert.equal(cap.className,action.className);
  assert.equal(cap.textContent,'');
  if(['newline','dictate'].includes(cap.dataset.action))assert.equal(cap.innerHTML,undefined);
  else assert.ok(cap.innerHTML.includes(`assets/keycaps.svg#${cap.dataset.action}`));
  cap.events.click();
  assert.ok(cap.selected&&action.selected);
  assert.equal(ids.actions.children.filter(button=>button.selected).length,1);
  assert.equal(cap.attributes['aria-pressed'],'true');
  action.events.focus();
  assert.ok(cap.selected&&action.selected);
 }
});

test('layer changes preserve the illustrated controls and matching actions',()=>{
 const {ids,layers}=layout();
 const before=ids.caps.children.map(button=>({...button.properties}));
 layers.forEach((layer,index)=>{
  layer.events.click();
  assert.match(ids.workspace.textContent,new RegExp(`^Layer ${index+1} `));
  assert.equal(layers.filter(button=>button.attributes['aria-pressed']==='true').length,1);
  assert.deepEqual(ids.caps.children.map(button=>({...button.properties})),before);
 });
});

test('the clear action key shows symbols with an accessible shortcut name',()=>{
 const {ids}=layout();
 const button=ids.actions.children.find(item=>item.dataset.action==='newline');
 assert.equal(button.textContent,'⇧ ↵');
 assert.equal(button.attributes['aria-label'],'Shift+Return');
 assert.equal(button.title,'Shift+Return');
});

test('the actual device photo is a separate reference, not a tappable board',()=>{
 const image=fs.readFileSync(path.join(root,'docs/assets/creator-micro-device.png'));
 assert.equal(image.readUInt32BE(16),895);
 assert.equal(image.readUInt32BE(20),880);
 assert.match(html,/src="assets\/creator-micro-device.png" width="895" height="880"/);
 assert.match(html,/<figure class="reference-photo"><img/);
 assert.doesNotMatch(html,/device-photo|const positions=/);
 assert.match(fs.readFileSync(path.join(root,'README.md'),'utf8'),/\]\(docs\/assets\/creator-micro-device.png\)/);
 assert.doesNotMatch(html,/generic stand-ins|chain cap<|No vendor logo or keycap artwork is reproduced/);
});

test('the public demo uses local media without autoplay or third-party embeds',()=>{
 const demo=fs.readFileSync(path.join(root,'docs/demo.html'),'utf8');
 assert.match(demo,/<video controls playsinline preload="none"/);
 assert.match(demo,/video\{[^}]*width:100%;height:auto;/);
 assert.doesNotMatch(demo,/autoplay|<iframe|<script/i);
 assert.match(demo,/<track kind="captions"[^>]*srclang="en"/);
 assert.match(demo,/<summary>Transcript and visual description<\/summary>/);
 for(const match of demo.matchAll(/(?:src|poster)="([^"]+)"/g)){
  assert.ok(!match[1].includes('://'));
  assert.ok(fs.statSync(path.join(root,'docs',match[1])).isFile());
 }
 const video=fs.readFileSync(path.join(root,'docs/assets/creator-micro-demo.mp4'));
 assert.equal(video.toString('ascii',4,8),'ftyp');
 assert.ok(video.length>1000000&&video.length<40*1024*1024);
 const captions=fs.readFileSync(path.join(root,'docs/assets/creator-micro-demo.vtt'),'utf8');
 assert.ok(captions.startsWith('WEBVTT\n'));
 assert.equal((captions.match(/ --> /g)||[]).length,15);
 for(const entry of [html,fs.readFileSync(path.join(root,'README.md'),'utf8')]){
  assert.ok(entry.includes('https://veteranbv.github.io/creator-micro-ai/demo.html'));
 }
});
