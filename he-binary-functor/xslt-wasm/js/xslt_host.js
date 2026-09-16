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

/// JavaScript Host Runtime for XSLT WASM Modules
/// Loads compiled WASM, provides DOM bridge, handles transform requests.

const fs = require('fs');
const path = require('path');

class XsltWasmHost {
    constructor(wasmPath) {
        this.wasmPath = wasmPath;
        this.instance = null;
        this.memory = null;
    }

    async init() {
        const wasmBuffer = fs.readFileSync(this.wasmPath);
        const wasmModule = await WebAssembly.instantiate(wasmBuffer, {
            env: { memory: new WebAssembly.Memory({ initial: 1 }) }
        });
        this.instance = wasmModule.instance;
        this.memory = this.instance.exports.memory;
        console.log(`[XSLT WASM] Loaded: ${this.wasmPath}`);
    }

    transform(xmlString, _xsltString) {
        if (!this.instance) throw new Error('WASM not initialized');

        const encoder = new TextEncoder();
        const xmlBytes = encoder.encode(xmlString);

        // Write XML into WASM memory
        const ptr = 0;
        const memView = new Uint8Array(this.memory.buffer);
        memView.set(xmlBytes, ptr);

        // Call transform
        const resultPtr = this.instance.exports.transform(ptr, xmlBytes.length);

        // Read result (simplified â€” real impl reads null-terminated string)
        const resultBytes = [];
        for (let i = resultPtr; memView[i] !== 0; i++) {
            resultBytes.push(memView[i]);
        }
        return new TextDecoder().decode(new Uint8Array(resultBytes));
    }
}

async function main() {
    const args = process.argv.slice(2);
    if (args.length < 2) {
        console.log('Usage: node xslt_host.js <xslt.wasm> <input.xml>');
        process.exit(1);
    }

    const [wasmPath, xmlPath] = args;
    const host = new XsltWasmHost(wasmPath);
    await host.init();

    const xml = fs.readFileSync(xmlPath, 'utf8');
    const result = host.transform(xml, '');
    console.log(result);
}

module.exports = { XsltWasmHost };

if (require.main === module) {
    main().catch(console.error);
}
