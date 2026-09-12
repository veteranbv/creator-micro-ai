'use strict';
// Render the same controls and symbols as the interactive reference for sharing.
const fs=require('node:fs');
const path=require('node:path');
const vm=require('node:vm');
const root=path.join(__dirname,'..');
const page=fs.readFileSync(path.join(root,'docs/layout.html'),'utf8');
const definition=page.match(/const controls=(\[[\s\S]*?\n\]);/)[1];
const controls=vm.runInNewContext(definition);
const symbols=fs.readFileSync(path.join(root,'docs/assets/keycaps.svg'),'utf8').match(/<defs>([\s\S]*?)<\/defs>/)[1];
const wrap={dial:['Navigate','/ Search'],new:['New chat'],escape:['Escape'],joystick:['8-way','joystick'],context:['Context @'],backspace:['Backspace'],undo:['Undo'],model:['Choose','model'],copy:['Copy','response'],approve:['Allow once'],deny:['Deny'],newline:['⇧ ↵'],layer:['Layers'],dictate:['Dictate'],submit:['Submit']};
for(const [id,,title] of controls){
 if(!wrap[id]||wrap[id].join(' ')!==title)throw new Error('Preview label does not match its control title.');
}
let drawing='';
for(const [board,offset] of [['caps',26],['actions',522]]){
 drawing+=`<rect x="${offset}" y="100" width="452" height="464" rx="35" fill="#090d11"/><rect x="${offset+10}" y="110" width="432" height="444" rx="27" fill="url(#deck)" stroke="#88caff" stroke-width="3"/>`;
 for(let index=0;index<controls.length;index++){
  const [id,,,style]=controls[index];
  const row=index<12?Math.floor(index/4):3;
  const column=index<12?index%4:id==='layer'?0:id==='dictate'?1:3;
  const sensor=id==='layer';
  const width=id==='dictate'?188:sensor?64:88;
  const height=sensor?64:88;
  const x=offset+32+column*98+(sensor?12:0),y=132+row*100+(sensor?12:0);
  const clear=style.includes('clear'),radius=style.includes('round')?44:19;
  drawing+=`<g color="${clear?'#122b39':'#dcebe7'}"><rect x="${x}" y="${y+5}" width="${width}" height="${height}" rx="${radius}" fill="#05090b"/><rect x="${x}" y="${y}" width="${width}" height="${height}" rx="${radius}" fill="${clear?'url(#clear)':sensor?'#10171c':'url(#cap)'}" stroke="${clear?'#baf3ff':'#5a656b'}"/>`;
  if(clear){
   for(const fraction of id==='dictate'?[.25,.75]:[.5])drawing+=`<circle cx="${x+width*fraction}" cy="${y+height*.63}" r="17" fill="#668ae0" opacity=".35"/>`;
  }
  if(board==='caps'&&!clear)drawing+=`<use href="#${id}" x="${x+(width-44)/2}" y="${y+(height-44)/2}" width="44" height="44"/>`;
  if(board==='actions'){
   const lines=wrap[id];
   lines.forEach((line,lineIndex)=>{drawing+=`<text x="${x+width/2}" y="${y+height/2-(lines.length-1)*10+lineIndex*20+6}" text-anchor="middle" font-size="${sensor?14:16}" fill="currentColor">${line}</text>`;});
  }
  drawing+='</g>';
 }
}
const svg=`<svg xmlns="http://www.w3.org/2000/svg" width="1800" height="1080" viewBox="0 0 1000 600" role="img" aria-labelledby="title description">
<title id="title">Creator Micro AI: keycaps and actions</title><desc id="description">Two illustrated controllers, with matching keycap symbols on the left and actions on the right. The device photograph is separate.</desc>
<defs>${symbols}<linearGradient id="deck" x2="1" y2="1"><stop stop-color="#2b343b"/><stop offset="1" stop-color="#171e25"/></linearGradient><radialGradient id="cap" cx=".47" cy=".37" r=".8"><stop stop-color="#262c2e"/><stop offset=".8" stop-color="#3a4042"/><stop offset="1" stop-color="#262e33"/></radialGradient><linearGradient id="clear" x2="1" y2="1"><stop stop-color="#4bdbd6"/><stop offset="1" stop-color="#cae6f8"/></linearGradient></defs>
<rect width="1000" height="600" rx="24" fill="#10151b"/><g font-family="Arial,Helvetica,sans-serif"><text x="26" y="43" font-size="25" fill="#f4f2ec">What your hands see</text><text x="522" y="43" font-size="25" fill="#f4f2ec">What the controls do</text><text x="26" y="72" font-size="16" fill="#a9b8c4">Illustrated keycaps matching the physical setup</text><text x="522" y="72" font-size="16" fill="#a9b8c4">Same controls across all four layers</text>${drawing}</g></svg>`;
const output=path.join(root,'docs/assets/layout-reference.svg');
if(process.argv.includes('--check')){
 if(fs.readFileSync(output,'utf8')!==svg)throw new Error('Run node scripts/layout-preview.js to update the illustrated reference.');
 console.log('Illustrated reference matches the current controls and symbols.');
}else{
 fs.writeFileSync(output,svg);
 console.log('Rendered illustrated layout reference. No photo overlay.');
}
