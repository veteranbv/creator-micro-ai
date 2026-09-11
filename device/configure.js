'use strict';
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const assert = require('node:assert/strict');
const { unwrap } = require('../helper/Resources/worklouder_device_bridge');

async function configure(command, restorePath, kit, options = {}) {
  const log = options.log || console.log;
  if (!['--check', '--apply', '--restore'].includes(command)) throw new Error('USE_CHECK_APPLY_OR_RESTORE');
  if (command === '--restore' && !restorePath) throw new Error('BACKUP_PATH_REQUIRED');
  const devices = new kit.WLDeviceDiscovery().findWLDevices().filter(d => d.deviceType === 'creator_micro_v2');
  assert.equal(devices.length, 1, 'EXACTLY_ONE_DEVICE_REQUIRED');
  const comm = new kit.WLDeviceCommImpl();
  try {
    assert.notEqual(await comm.connect(devices[0]), false, 'CONNECT_FAILED');
    const api = new kit.WLRPCApi(comm);
    const read = async () => unwrap(await api.readFileChunked('keymap.json')).toString('utf8');
    const after = JSON.parse(fs.readFileSync(command === '--restore' ? restorePath : path.join(__dirname, 'keymap.json'), 'utf8'));
    assert.equal(after.version, 1, 'UNSUPPORTED_BACKUP');
    assert.ok(Array.isArray(after.profiles) && Array.isArray(after.macros), 'INVALID_BACKUP');
    let before;
    try {
      before = await read();
      if (command !== '--restore') {
        const current = JSON.parse(before);
        assert.equal(current.version, 1, 'UNSUPPORTED_KEYMAP_VERSION');
        assert.ok(Array.isArray(current.profiles), 'INVALID_PROFILES');
      }
    } catch (error) {
      if (command !== '--restore') throw error;
    }
    if (command === '--check') {
      log('Compatible keymap schema detected. No changes made. Applying replaces all device profiles and macros.');
      log('Firmware and Input compatibility still require the documented physical tests.');
      return;
    }
    if (before !== undefined) {
      const base = options.backupBase || path.join(os.homedir(), 'Library', 'Application Support', 'Creator Micro AI', 'backups');
      fs.mkdirSync(base, { recursive: true, mode: 0o700 });
      const backup = fs.mkdtempSync(path.join(base, 'device-'));
      fs.chmodSync(backup, 0o700);
      fs.writeFileSync(path.join(backup, 'keymap.before.json'), before, { flag: 'wx', mode: 0o600 });
      log(`Recovery copy: ${path.join(backup, 'keymap.before.json')}`);
    } else {
      log('The current keymap could not be read. Restoring the validated backup without a new recovery copy.');
    }
    unwrap(await api.writeFileChunkedFromStr('keymap.json', JSON.stringify(after), () => {}));
    assert.deepEqual(JSON.parse(await read()), after, 'READBACK_MISMATCH_RESTORE_BACKUP');
    log('Device readback verified. Restart Input to refresh its cached labels. Run the physical acceptance checklist.');
  } finally { await comm.disconnect(); }
}
if (require.main === module) {
  const deadline = setTimeout(() => {
    console.error('Device operation timed out. A write may be incomplete; use your recovery copy to restore it.');
    process.exit(1);
  }, 30000);
  Promise.resolve().then(() => {
    const kit = require('/Applications/input.app/Contents/Resources/app.asar/node_modules/@worklouder/wl-device-kit');
    return configure(process.argv[2] || '--check', process.argv[3], kit);
  }).catch(() => {
    console.error('Device operation failed. No raw device data was logged. If a write was attempted, use the recovery copy reported above.');
    process.exitCode = 1;
  }).finally(() => clearTimeout(deadline));
}
module.exports = { configure };
