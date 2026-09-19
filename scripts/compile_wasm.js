// ========================================================================
// SOVEREIGN LEVIATHAN NODE LICENSE
// License-ID: SL-AGPL3-001 | Covenant-Version: 1.0
// Copyright (C) 2026 SnapKittyWest. Ahmad Ali Parr, Bel Esprit D'Accord Irrevocable Trust.
// ========================================================================
//
// This file is a covered work under the GNU Affero General Public License,
// version 3, together with the Sovereign Leviathan additional terms.
//
// Hark, though this node be but a spark,
// Its covenant endureth through the dark.
//
// Ignorantia juris non excusat.
// ========================================================================

const wabtFactory = require('wabt');
const fs = require('fs');

const watFiles = [
  'wasm/runtime.wat',
  'wasm/isa.wat',
  'wasm/ledger_replay.wat',
  'wasm/account_registry.wat',
  'wasm/sha256.wat',
  'wasm/worm_frame.wat'
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
