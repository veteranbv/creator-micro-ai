'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const root=path.join(__dirname,'..');
const read=p=>fs.readFileSync(path.join(root,p),'utf8');
test('actions are SHA-pinned and the review verdict uses trusted base code',()=>{
 for(const name of fs.readdirSync(path.join(root,'.github/workflows'))){
  const yaml=read('.github/workflows/'+name);
  for(const match of yaml.matchAll(/uses:\s*([^\s#]+)/g))assert.match(match[1],/@[0-9a-f]{40}$/);
 }
 assert.match(read('.github/workflows/review-gate.yml'),/ref: \$\{\{ github.event.pull_request.base.sha \}\}/);
 assert.doesNotMatch(read('.github/workflows/review-gate-retrigger.yml'),/uses:\s*actions\/checkout/);
});
test('published Markdown links resolve within this repository',()=>{
 const files=fs.readdirSync(root).filter(n=>n.endsWith('.md')).concat(fs.readdirSync(path.join(root,'docs')).filter(n=>n.endsWith('.md')).map(n=>'docs/'+n));
 for(const file of files)for(const m of read(file).matchAll(/\]\(([^)]+)\)/g)){
  if(/^(https?:|#)/.test(m[1]))continue;
  assert.ok(fs.existsSync(path.resolve(root,path.dirname(file),m[1].split('#')[0])),`${file}: broken ${m[1]}`);
 }
});
test('layout documents all physical positions without capturing input',()=>{
 const html=read('docs/layout.html');
 assert.match(html,/const controls=/);
 assert.match(html,/Copy response/);assert.match(html,/Select all/);assert.match(html,/Control\+Shift\+D/);
 assert.doesNotMatch(html,/fetch\(|localStorage|navigator\.clipboard|WebSocket/);
});
test('README opens the hosted layout instead of HTML source',()=>{
 assert.match(read('README.md'),/\[interactive side-by-side layout\]\(https:\/\/veteranbv\.github\.io\/creator-micro-ai\/\)/);
 assert.ok(fs.existsSync(path.join(root,'docs/.nojekyll')));
 assert.match(read('docs/index.html'),/url=layout\.html/);
 assert.match(read('docs/index.html'),/href="layout\.html"/);
 assert.match(read('docs/layout.html'),/href="https:\/\/github\.com\/veteranbv\/creator-micro-ai\/blob\/main\/docs\/gotchas\.md"/);
});
test('user documentation names only the supported Control shortcuts',()=>{
 const supported=new Set(['Control+1','Control+3','Control+Shift+D','Control+Shift+M']);
 for(const file of ['README.md','docs/setup.md','docs/gotchas.md','docs/layout.html','docs/verification.md']){
  for(const [shortcut] of read(file).matchAll(/Control\+(?:Shift\+)?[A-Z0-9]\b/g))
   assert.ok(supported.has(shortcut),`${file}: shortcut needs an implemented control`);
 }
});

test('dictation documentation describes a tool-independent toggle contract',()=>{
 assert.match(read('README.md'),/not a universal standard/);
 assert.match(read('README.md'),/Superwhisper is my choice/);
 assert.match(read('docs/setup.md'),/preferred dictation tool's global start\/stop shortcut/);
 assert.match(read('docs/setup.md'),/not a required dependency/);
 assert.match(read('docs/layout.html'),/configure your dictation tool/i);
 assert.doesNotMatch(read('README.md'),/wide key toggles Superwhisper/);
});

test('app opening cannot activate before the stale-generation guard',()=>{
 const source=read('helper/Sources/main.swift');
 assert.match(source,/configuration\.activates = false/);
 assert.doesNotMatch(source,/configuration\.activates = true/);
 assert.match(source,/guard generation == activationGeneration else \{ return \}\s+app\.activate/);
});

test('every selector uses complete traversal and guards read failures before pressing',()=>{
 const source=read('helper/Sources/ControllerActions.swift');
 assert.match(source,/ControllerTargetPolicy\.completeDescendants\(root, limit: limit, children: children\)/);
 assert.match(source,/guard let all = reads\.descendants\(window\) else/);
 assert.match(source,/if reads\.complete, let target, press\(target, app: app, window: window\)/);
 assert.match(source,/else if reads\.complete && attempts > 1/);
 assert.doesNotMatch(source,/\?\? \[\]/);
});

test('approval discovery preserves predicate read failures until selection finishes',()=>{
 const source=read('helper/Sources/ControllerActions.swift');
 const approval=source.slice(source.indexOf('private func approvalTarget'));
 assert.match(approval,/guard reads\.complete else \{ return nil \}/);
 assert.match(approval,/return reads\.complete \? target : nil/);
 const workspace=read('helper/Sources/main.swift').split('private func workspaceControls')[1].split('private func detectMode')[0];
 assert.match(workspace,/ControllerTargetPolicy\.childValues\(status: status, values: raw as\? \[AXUIElement\]\)/);
 assert.doesNotMatch(workspace,/\?\? \[\]/);
});

test('delayed approval stays bound to the original window and control',()=>{
 const source=read('helper/Sources/ControllerActions.swift');
 const receive=source.slice(source.indexOf('private func receive'),source.indexOf('private func value'));
 assert.ok(receive.indexOf('let window = focusedWindow(app)') < receive.indexOf('DispatchQueue.main.asyncAfter'));
 assert.ok(receive.indexOf('let originalTarget =') < receive.indexOf('DispatchQueue.main.asyncAfter'));
 assert.match(receive,/CFEqual\(currentWindow, window\)/);
 assert.match(receive,/CFEqual\(originalTarget, currentTarget\)/);
 assert.match(receive,/approval && originalTarget == nil/);
 const press=source.slice(source.indexOf('private func press'),source.indexOf('private func parent'));
 assert.ok(press.indexOf('CFEqual(currentWindow, window)') < press.indexOf('AXUIElementPerformAction'));
});

test('fixed model shortcut returns before any conversation traversal',()=>{
 const source=read('helper/Sources/ControllerActions.swift').split('private func perform')[1];
 const traversal=source.indexOf('let reads = ControllerAccessibility()');
 const shortcut=source.slice(0,traversal);
 assert.match(shortcut,/if id == 1 && !claude/);
 assert.match(shortcut,/CFEqual\(currentWindow, window\)/);
 assert.match(shortcut,/frontmostApplication\?\.processIdentifier == app\.processIdentifier/);
 assert.match(shortcut,/postToPid\(app\.processIdentifier\)/);
 assert.match(shortcut,/return\s+\}/);
 assert.doesNotMatch(shortcut,/descendants\(/);
});

test('bridge errors retain an in-flight activation before canceling its callbacks',()=>{
 const error=read('helper/Sources/main.swift').split('case "error":')[1].split('default:')[0];
 assert.match(error,/if activationInProgress \{ layerSelection\.interruptActivation\(\) \}/);
 assert.ok(error.indexOf('interruptActivation()') < error.indexOf('activationGeneration += 1'));
 assert.ok(error.indexOf('interruptActivation()') < error.indexOf('activationInProgress = false'));
});
