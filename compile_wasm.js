const wabtFactory = require('wabt');
const fs = require('fs');

const watFiles = [
  'wasm/runtime.wat',
  'wasm/isa.wat',
  'wasm/ledger_replay.wat',
  'wasm/account_registry.wat',
  'wasm/sha256.wat'
];

async function compileAll() {
  const wabt = await wabtFactory();
  for (const watFile of watFiles) {
    const wasmFile = watFile.replace('.wat', '.wasm');
    try {
      const watContent = fs.readFileSync(watFile, 'utf8');
      const module = wabt.parseWat(watFile, watContent);
      module.applyNames();
      const { buffer } = module.toBinary({ write_debug_names: true });
      fs.writeFileSync(wasmFile, Buffer.from(buffer));
      console.log('OK: ' + watFile + ' -> ' + wasmFile + ' (' + buffer.byteLength + ' bytes)');
      module.destroy();
    } catch (e) {
      console.error('FAIL: ' + watFile + ': ' + (e.message || e));
    }
  }
}

compileAll();
