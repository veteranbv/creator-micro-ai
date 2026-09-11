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
