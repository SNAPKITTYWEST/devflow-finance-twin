// SPDX-License-Identifier: GPL-3.0-or-later OR Apache-2.0

import Foundation

/// Wrapper for the ARM64 assembly CRC32 hot path, with a pure-Swift fallback
/// for non-ARM64 platforms.  IEEE polynomial 0xEDB88320, init/final XOR 0xFFFFFFFF.
public enum AssemblyBridge {

    // MARK: - Assembly entry point (ARM64 + Darwin only)

    #if arch(arm64) && canImport(Darwin)

    @_silgen_name("_crc32_asm")
    private static func _crc32_asm(_ buf: UnsafeRawPointer, _ len: Int) -> UInt32

    public static func crc32(of data: Data) -> UInt32 {
        data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return _swiftCRC32(Data()) }
            return _crc32_asm(base, raw.count)
        }
    }

    #else

    public static func crc32(of data: Data) -> UInt32 {
        _swiftCRC32(data)
    }

    #endif

    // MARK: - Pure-Swift fallback (byte-at-a-time reflected)

    /// IEEE CRC32 identical to :erlang.crc32 and the assembly implementation.
    /// Polynomial 0xEDB88320, init XOR 0xFFFFFFFF, final XOR 0xFFFFFFFF.
    private static func _swiftCRC32(_ data: Data) -> UInt32 {
        let poly: UInt32 = 0xEDB8_8320
        var crc: UInt32 = 0xFFFF_FFFF

        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                if crc & 1 != 0 {
                    crc = (crc >> 1) ^ poly
                } else {
                    crc >>= 1
                }
            }
        }

        return crc ^ 0xFFFF_FFFF
    }
}
