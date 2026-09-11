'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const {PassThrough}=require('node:stream');
const {EventEmitter}=require('node:events');
const {commandFrom,frameInput,unwrap,run}=require('../helper/Resources/worklouder_device_bridge');
test('commands accept only fixed focus tokens and positive integer IDs',()=>{
  const c={type:'focus',token:'cc.worklouder.ai.codex',requestId:1};
  assert.deepEqual(commandFrom(JSON.stringify(c)),c);
  for(const bad of [{...c,token:'__proto__'},{...c,requestId:-1},{...c,type:'shell'},{...c,requestId:'1'},null])
    assert.equal(commandFrom(JSON.stringify(bad)),null);
  assert.equal(commandFrom('x'.repeat(5000)),null);
});
test('framing handles split lines, rejects oversized records and recovers',()=>{
  const stream=new PassThrough(), lines=[];let errors=0;
  frameInput(stream,s=>lines.push(s),()=>errors++);
  stream.write('ab');stream.write('c\n');stream.write('x'.repeat(9000));stream.write('\nok\n');
  assert.deepEqual(lines,['abc','ok']);assert.equal(errors,1);
});
test('RPC failure discards vendor error text',()=>{
  assert.throws(()=>unwrap({ok:false,error:{message:'PRIVATE_SENTINEL'}}),{message:'RPC_FAILED'});
  assert.equal(unwrap({ok:true,value:4}),4);
});
test('mock USB emits only protocol data and closes when the parent closes',async()=>{
  let layer=1, disconnected=0, exited=false, token;
  const io=new EventEmitter();io.stdin=new PassThrough();io.stdout=new PassThrough();io.exit=()=>{exited=true;};
  let output='';io.stdout.on('data',d=>output+=d);
  const kit={WLDeviceDiscovery:class{findWLDevices(){return [{deviceType:'creator_micro_v2'}];}},
    WLDeviceCommImpl:class{async connect(){return true;}async disconnect(){disconnected++;}},
    WLRPCApi:class{async getDeviceStatus(){return {ok:true,value:{selectedLayerIndex:layer}};}
      async sendFocusApp(v){token=v.process;layer=2;return {ok:true};}}};
  await run(kit,io);
  await new Promise(r=>setImmediate(r));
  io.stdin.write(JSON.stringify({type:'focus',token:'cc.worklouder.ai.chatgpt',requestId:7})+'\n');
  await new Promise(r=>setImmediate(r));io.stdin.end();
  await new Promise(r=>setImmediate(r));
  assert.equal(token,'cc.worklouder.ai.chatgpt');assert.equal(disconnected,1);assert.ok(exited);
  assert.deepEqual(output.trim().split('\n').map(JSON.parse),[{type:'ready',layer:1},{type:'applied',requestId:7,layer:2}]);
});
test('a stalled vendor operation exits the child for parent recovery',async()=>{
 const io=new EventEmitter();io.stdin=new PassThrough();io.stdout=new PassThrough();
 let exitCode;io.exit=code=>{exitCode=code;};
 const kit={WLDeviceDiscovery:class{findWLDevices(){return [{deviceType:'creator_micro_v2'}];}},
  WLDeviceCommImpl:class{async connect(){return true;}async disconnect(){}},
  WLRPCApi:class{getDeviceStatus(){return new Promise(()=>{});}}};
 await run(kit,io,{operationTimeoutMs:10});
 await new Promise(resolve=>setTimeout(resolve,30));
 assert.equal(exitCode,1);
 io.stdin.end();
});
