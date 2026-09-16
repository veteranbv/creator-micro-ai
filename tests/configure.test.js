'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const os=require('node:os');
const path=require('node:path');
const {configure}=require('../device/configure');

for(const initial of ['{broken', null]) test('restore repairs '+(initial===null?'unreadable':'malformed')+' current data',async()=>{
 const dir=fs.mkdtempSync(path.join(os.tmpdir(),'profile-test-'));
 try {
  const good={version:1,profiles:[],macros:[]};
  const backup=path.join(dir,'saved.json');fs.writeFileSync(backup,JSON.stringify(good));
  let data=initial,writes=0,disconnects=0;
  const kit={WLDeviceDiscovery:class{findWLDevices(){return [{deviceType:'creator_micro_v2'}];}},
   WLDeviceCommImpl:class{async connect(){return true;}async disconnect(){disconnects++;}},
   WLRPCApi:class{
    async readFileChunked(){if(data===null)throw Error('UNREADABLE');return data;}
    async writeFileChunkedFromStr(name,value){writes++;data=value;return {ok:true};}
   }};
  const backupBase=path.join(dir,'recovery');
  await configure('--restore',backup,kit,{backupBase,log:()=>{}});
  assert.equal(writes,1);assert.equal(disconnects,1);assert.deepEqual(JSON.parse(data),good);
  if(initial!==null){
   const saved=path.join(backupBase,fs.readdirSync(backupBase)[0],'keymap.before.json');
   assert.equal(fs.readFileSync(saved,'utf8'),initial);
  }else assert.equal(fs.existsSync(backupBase),false);
 }finally{fs.rmSync(dir,{recursive:true,force:true});}
});

test('apply refuses damaged current data before writing',async()=>{
 let writes=0;
 const kit={WLDeviceDiscovery:class{findWLDevices(){return [{deviceType:'creator_micro_v2'}];}},
  WLDeviceCommImpl:class{async connect(){return true;}async disconnect(){}},
  WLRPCApi:class{async readFileChunked(){return '{broken';}async writeFileChunkedFromStr(){writes++;}}};
 await assert.rejects(configure('--apply',undefined,kit,{log:()=>{}}));assert.equal(writes,0);
});

for(const command of ['--check','--apply']) for(const macros of [undefined,null,{},'invalid'])
test(command+' rejects non-array current macros: '+JSON.stringify(macros),async()=>{
 let writes=0,disconnects=0;
 const messages=[];
 const kit={WLDeviceDiscovery:class{findWLDevices(){return [{deviceType:'creator_micro_v2'}];}},
  WLDeviceCommImpl:class{async connect(){return true;}async disconnect(){disconnects++;}},
  WLRPCApi:class{async readFileChunked(){return JSON.stringify({version:1,profiles:[],macros});}async writeFileChunkedFromStr(){writes++;}}};
 await assert.rejects(configure(command,undefined,kit,{log:message=>messages.push(message)}),/INVALID_MACROS/);
 assert.equal(writes,0);assert.equal(disconnects,1);assert.deepEqual(messages,[]);
});

test('check accepts both current arrays without writing',async()=>{
 let writes=0,disconnects=0;
 const messages=[];
 const kit={WLDeviceDiscovery:class{findWLDevices(){return [{deviceType:'creator_micro_v2'}];}},
  WLDeviceCommImpl:class{async connect(){return true;}async disconnect(){disconnects++;}},
  WLRPCApi:class{async readFileChunked(){return JSON.stringify({version:1,profiles:[],macros:[]});}async writeFileChunkedFromStr(){writes++;}}};
 const result=await configure('--check',undefined,kit,{log:message=>messages.push(message)});
 assert.equal(result.matches,false);
 assert.equal(writes,0);assert.equal(disconnects,1);assert.match(messages[0],/Compatible keymap schema/);
});

test('check detects the exact profile without a backup or write',async()=>{
 let writes=0,backups=0;
 const data=fs.readFileSync(path.join(__dirname,'../device/keymap.json'),'utf8');
 const kit={WLDeviceDiscovery:class{findWLDevices(){return [{deviceType:'creator_micro_v2'}];}},
  WLDeviceCommImpl:class{async connect(){return true;}async disconnect(){}},
  WLRPCApi:class{async readFileChunked(){return data;}async writeFileChunkedFromStr(){writes++;}}};
 const result=await configure('--check',undefined,kit,{log:()=>{},onBackup:()=>{backups++;}});
 assert.equal(result.matches,true);assert.equal(writes,0);assert.equal(backups,0);
});

for(const failReadback of [false,true]) test('apply reports recovery before writing, readback failure='+failReadback,async()=>{
 const dir=fs.mkdtempSync(path.join(os.tmpdir(),'profile-test-'));
 try{
  const before=JSON.stringify({version:1,profiles:[],macros:[]});
  let data=before,backupPath,disconnects=0;
  const kit={WLDeviceDiscovery:class{findWLDevices(){return [{deviceType:'creator_micro_v2'}];}},
   WLDeviceCommImpl:class{async connect(){return true;}async disconnect(){disconnects++;}},
   WLRPCApi:class{
    async readFileChunked(){return data;}
    async writeFileChunkedFromStr(name,value){
     assert.ok(backupPath);assert.equal(fs.readFileSync(backupPath,'utf8'),before);
     assert.equal(fs.statSync(backupPath).mode&0o777,0o600);
     data=failReadback?before:value;return {ok:true};
    }
   }};
  const operation=configure('--apply',undefined,kit,{backupBase:dir,log:()=>{},onBackup:file=>{backupPath=file;}});
  if(failReadback) await assert.rejects(operation,/READBACK_MISMATCH/);
  else assert.equal((await operation).matches,true);
  assert.equal(disconnects,1);assert.ok(backupPath);
 }finally{fs.rmSync(dir,{recursive:true,force:true});}
});
