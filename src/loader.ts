// Copyright (c) 2026 SnapKittyWest. Ahmad Ali Parr, Bel Esprit D'Accord Irrevocable Trust.
// SPDX-License-Identifier: FSL-1.1

import { readFileSync } from 'fs';

let isaInstance: WebAssembly.Instance | null;

async function getIsaEngine(): Promise<WebAssembly.Instance> {
  if (!isaInstance) {
    const wasmBytes = readFileSync('./cli_isa.wasm');
    const compiled = await WebAssembly.instantiate(wasmBytes, {
      env: {
        abort: (msg: number, file: number, line: number, column: number) => {
          throw new Error(`AssemblyScript abort at line ${line}:${column}`);
        }
      }
    });
    isaInstance = compiled.instance;
  }
  return isaInstance;
}

export async function executeCliInstruction(opcode: number, payload: Uint8Array): Promise<boolean> {
  const instance = await getIsaEngine();
  const memory = instance.exports.memory as WebAssembly.Memory;
  const execute = instance.exports.execute_binary_isa as (ptr: number, len: number) => number;

  const buffer = new Uint8Array(memory.buffer);
  const baseOffset = 2048;

  buffer[baseOffset] = opcode;
  buffer.set(payload, baseOffset + 1);

  const result = execute(baseOffset, 1 + payload.length);
  return result === 1;
}

let runtimeInstance: WebAssembly.Instance | null;

export async function getRuntimeEngine(): Promise<WebAssembly.Instance> {
  if (!runtimeInstance) {
    const wasmBytes = readFileSync('./runtime.wasm');
    const compiled = await WebAssembly.instantiate(wasmBytes);
    runtimeInstance = compiled.instance;
    (runtimeInstance.exports.initialize as () => void)();
  }
  return runtimeInstance;
}

export async function runEngineTick(): Promise<number> {
  const instance = await getRuntimeEngine();
  const tick = instance.exports.engine_tick as () => number;
  return tick();
}
