'use strict';
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const assert = require('node:assert/strict');
const { unwrap } = require('../helper/Resources/worklouder_device_bridge');

async function configure() {
  const command = process.argv[2] || '--check';
  if (!['--check', '--apply', '--restore'].includes(command)) throw new Error('USE_CHECK_APPLY_OR_RESTORE');
  if (command === '--restore' && !process.argv[3]) throw new Error('BACKUP_PATH_REQUIRED');
  const kit = require('/Applications/input.app/Contents/Resources/app.asar/node_modules/@worklouder/wl-device-kit');
  const devices = new kit.WLDeviceDiscovery().findWLDevices().filter(d => d.deviceType === 'creator_micro_v2');
  assert.equal(devices.length, 1, 'EXACTLY_ONE_DEVICE_REQUIRED');
  const comm = new kit.WLDeviceCommImpl();
  try {
    assert.notEqual(await comm.connect(devices[0]), false, 'CONNECT_FAILED');
    const api = new kit.WLRPCApi(comm);
    const read = async () => JSON.parse(unwrap(await api.readFileChunked('keymap.json')).toString('utf8'));
    const before = await read();
    assert.equal(before.version, 1, 'UNSUPPORTED_KEYMAP_VERSION');
    assert.ok(Array.isArray(before.profiles), 'INVALID_PROFILES');
    const after = JSON.parse(fs.readFileSync(command === '--restore' ? process.argv[3] : path.join(__dirname, 'keymap.json'), 'utf8'));
    assert.equal(after.version, 1, 'UNSUPPORTED_BACKUP');
    assert.ok(Array.isArray(after.profiles) && Array.isArray(after.macros), 'INVALID_BACKUP');
    if (command === '--check') {
      console.log('Compatible keymap schema detected. No changes made. Applying replaces all device profiles and macros.');
      console.log('Firmware and Input compatibility still require the documented physical tests.');
      return;
    }
    const base = path.join(os.homedir(), 'Library', 'Application Support', 'Creator Micro AI', 'backups');
    fs.mkdirSync(base, { recursive: true, mode: 0o700 });
    const backup = fs.mkdtempSync(path.join(base, 'device-'));
    fs.chmodSync(backup, 0o700);
    fs.writeFileSync(path.join(backup, 'keymap.before.json'), JSON.stringify(before, null, 2), { flag: 'wx', mode: 0o600 });
    console.log(`Recovery copy: ${path.join(backup, 'keymap.before.json')}`);
    unwrap(await api.writeFileChunkedFromStr('keymap.json', JSON.stringify(after), () => {}));
    assert.deepEqual(await read(), after, 'READBACK_MISMATCH_RESTORE_BACKUP');
    console.log('Device readback verified. Restart Input to refresh its cached labels. Run the physical acceptance checklist.');
  } finally { await comm.disconnect(); }
}
configure().catch(() => {
  console.error('Device operation failed. No raw device data was logged. If a write was attempted, use the recovery copy reported above.');
  process.exitCode = 1;
});
