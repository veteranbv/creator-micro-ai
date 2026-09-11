'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const p = require('../device/keymap.json');
test('four layers share physical controls and a single dictation switch', () => {
  assert.deepEqual(p.profiles[0].layers.map(l => l.name), ['Codex', 'ChatGPT', 'Claude Code', 'Claude']);
  for (const layer of p.profiles[0].layers) {
    assert.deepEqual(layer.layout, p.profiles[0].layers[0].layout);
    assert.deepEqual(layer.layout.keymap[3], ['KA_A8', 'KC_NONE', 'KC_ENT']);
  }
  assert.deepEqual(JSON.parse(p.deviceSpecificConfig).mergedKey, { lineIndex: 3, index: 0, direction: 'right' });
});
test('dictation has one balanced 40ms chord, with no paste', () => {
  const actions = p.macros.find(m => m.id === 8).actions;
  assert.deepEqual(actions.map(a => [a.kc,a.act,a.delay]), [
    ['KC_LCTL',1,40],['KC_LSFT',1,40],['KC_D',1,40],['KC_D',0,40],['KC_LSFT',0,40],['KC_LCTL',0,40]
  ]);
});
test('every macro releases what it presses, with unique IDs and no dangling references', () => {
  assert.equal(new Set(p.macros.map(m=>m.id)).size,p.macros.length);
  for (const macro of p.macros) {
    const down = new Set();
    for (const event of macro.actions) {
      if (event.act === 1) { assert.ok(!down.has(event.kc)); down.add(event.kc); }
      else if (event.act === 0) { assert.ok(down.delete(event.kc)); }
      else assert.equal(event.act, 2);
    }
    assert.equal(down.size,0);
  }
  const refs=JSON.stringify(p.profiles).match(/KA_A\d+/g);
  for(const ref of refs) assert.ok(p.macros.some(m=>`KA_A${m.id}`===ref));
});
test('eight physical directions have their intended native sends', () => {
  const sectors=p.profiles[0].layers[0].layout.joystick.sectors;
  assert.deepEqual(sectors.map(s=>s.k),['KC_DOWN','KA_A11','KC_LEFT','KA_A13','KC_UP','KC_TAB','KC_RGHT','KA_A12']);
  for (const [id,key] of [[11,'KC_C'],[12,'KC_V'],[13,'KC_A']]) {
    assert.deepEqual(p.macros.find(m=>m.id===id).actions.map(a=>a.kc),['KC_LGUI',key,key,'KC_LGUI']);
  }
});
test('every shipped macro is assigned and usage lists match the layouts', () => {
  const assigned = profile => [...new Set(profile.layers.flatMap(layer =>
    (JSON.stringify(layer.layout).match(/KA_A\d+/g) || []).map(ref => Number(ref.slice(4)))))].sort((a,b) => a-b);
  const expected = [...new Set(p.profiles.flatMap(assigned))].sort((a,b) => a-b);
  assert.deepEqual(p.macros.map(m => m.id).sort((a,b) => a-b), expected);
  for (const profile of p.profiles) assert.deepEqual(profile.macrosUsed, assigned(profile));
  assert.deepEqual(p.macrosGroups.flatMap(group => group.actionIds).sort((a,b) => a-b), expected);
});
