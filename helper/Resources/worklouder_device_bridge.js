'use strict';

const modes = Object.freeze({
  'cc.worklouder.ai.codex': { name: 'Codex workspace', layer: 1 },
  'cc.worklouder.ai.chatgpt': { name: 'ChatGPT workspace', layer: 2 },
  'cc.worklouder.ai.claude-code': { name: 'Claude Code workspace', layer: 3 },
  'cc.worklouder.ai.claude': { name: 'Claude workspace', layer: 4 }
});

function unwrap(result) {
  if (result && typeof result.ok === 'boolean') {
    if (!result.ok) throw new Error('RPC_FAILED');
    return result.value;
  }
  return result;
}

function commandFrom(line) {
  if (Buffer.byteLength(line) > 4096) return null;
  try {
    const command = JSON.parse(line);
    if (command?.type !== 'focus' || !Object.hasOwn(modes, command.token) ||
        !Number.isSafeInteger(command.requestId) || command.requestId < 1) return null;
    return { type: 'focus', token: command.token, requestId: command.requestId };
  } catch { return null; }
}

function frameInput(stream, accept, invalid) {
  let buffer = Buffer.alloc(0), dropping = false;
  stream.on('data', chunk => {
    for (const byte of chunk) {
      if (byte === 10) {
        if (!dropping) accept(buffer.toString('utf8'));
        buffer = Buffer.alloc(0); dropping = false;
      } else if (!dropping) {
        if (buffer.length >= 4096) { buffer = Buffer.alloc(0); dropping = true; invalid(); }
        else buffer = Buffer.concat([buffer, Buffer.from([byte])]);
      }
    }
  });
}

async function run(kit, io = process, { operationTimeoutMs = 5000 } = {}) {
  let communication, api, lastLayer, stopped = false, reconnectAfter = 0;
  let work = Promise.resolve(), pending = 0, pollPending = false;
  const emit = message => { if (!stopped) io.stdout.write(`${JSON.stringify(message)}\n`); };
  const fail = requestId => emit({ type: 'error', ...(requestId ? { requestId } : {}) });
  const queue = task => {
    if (stopped || pending >= 8) { fail(); return; }
    pending++;
    work = work.then(async () => {
      if (stopped) return;
      // A never-settling vendor RPC cannot be cancelled safely in-process.
      // Exit this child so the parent can start a fresh USB connection.
      const deadline = setTimeout(() => {
        stopped = true;
        clearInterval(interval);
        io.exit(1);
      }, operationTimeoutMs);
      try { await task(); }
      finally { clearTimeout(deadline); }
    }).catch(() => fail()).finally(() => { pending--; });
  };
  const disconnect = async () => {
    const current = communication;
    communication = api = lastLayer = undefined;
    if (current) { try { await current.disconnect(); } catch {} }
  };
  const status = async () => {
    const value = unwrap(await api.getDeviceStatus());
    if (!Number.isInteger(value?.selectedLayerIndex) || value.selectedLayerIndex < 1 || value.selectedLayerIndex > 4)
      throw new Error('INVALID_LAYER');
    return value.selectedLayerIndex;
  };
  const connect = async () => {
    if (api) return;
    if (Date.now() < reconnectAfter) throw new Error('RECONNECTING');
    const devices = new kit.WLDeviceDiscovery().findWLDevices().filter(d => d.deviceType === 'creator_micro_v2');
    if (devices.length !== 1) throw new Error('DEVICE_COUNT');
    communication = new kit.WLDeviceCommImpl();
    if (await communication.connect(devices[0]) === false) throw new Error('CONNECT_FAILED');
    api = new kit.WLRPCApi(communication);
    lastLayer = await status();
    emit({ type: 'ready', layer: lastLayer });
  };
  const recover = async requestId => {
    fail(requestId);
    await disconnect();
    reconnectAfter = Date.now() + 1500;
  };
  const poll = () => {
    if (stopped || pollPending || Date.now() < reconnectAfter || pending >= 8) return;
    pollPending = true;
    queue(async () => {
      try {
        await connect();
        const layer = await status();
        if (layer !== lastLayer) { lastLayer = layer; emit({ type: 'layer', layer }); }
      } catch { await recover(); }
      finally { pollPending = false; }
    });
  };
  const interval = setInterval(poll, 750);
  frameInput(io.stdin, line => {
    const command = commandFrom(line);
    if (!command) { fail(); return; }
    queue(async () => {
      try {
        await connect();
        const mode = modes[command.token];
        unwrap(await api.sendFocusApp({ appName: mode.name, process: command.token, path: '' }));
        lastLayer = await status();
        if (lastLayer !== mode.layer) throw new Error('LAYER_MISMATCH');
        emit({ type: 'applied', requestId: command.requestId, layer: lastLayer });
      } catch { await recover(command.requestId); }
    });
  }, () => fail());
  const stop = async () => {
    if (stopped) return;
    stopped = true;
    clearInterval(interval);
    // A stuck USB RPC must not leave an orphan after the parent exits.
    const deadline = setTimeout(() => io.exit(0), 2000);
    await work;
    await disconnect();
    clearTimeout(deadline);
    io.exit(0);
  };
  io.stdin.once('end', stop);
  io.once('SIGTERM', stop);
  io.once('SIGINT', stop);
  poll();
}

if (require.main === module) {
  // Vendor code is loaded from the user's Input installation, never redistributed.
  try {
    const kit = require('/Applications/input.app/Contents/Resources/app.asar/node_modules/@worklouder/wl-device-kit');
    run(kit).catch(() => process.exit(1));
  } catch { process.exit(1); }
}
module.exports = { modes, unwrap, commandFrom, frameInput, run };
