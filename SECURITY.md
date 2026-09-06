# Security Policy

## Supported Versions

| Version | Supported | Status |
|---------|-----------|--------|
| v2.0.x | ✅ | Active — Inverted Monorepo |
| v1.2.x | ✅ | Active — Ahmad deliverables |
| v1.1.x | ✅ | Active — Cold boot + ICP |
| v1.0.x | ❌ | End of life |

## Threat Model

### Storage Integrity
- **WORM (Write Once Read Many)**: All records appended with SHA-256 chain linking. Tampering breaks Merkle chain validation.
- **Atomic Writes**: File operations use temp-file + fsync + rename to prevent partial writes.
- **500MB File Limit**: Hard cap prevents resource exhaustion attacks.

### Runtime Security
- **WASM Sandboxing**: All execution within WebAssembly linear memory sandbox. No system access.
- **Thread Safety**: WORM operations use `threading.Lock` for concurrent access protection.
- **CSPRNG Entropy**: `os.urandom()` for all cryptographic randomness, never `random`.

### Input Validation
- **Account ID Format**: Regex-enforced `^[A-Z0-9_]{1,64}$`
- **Transaction Amount**: Must be finite, non-negative, max $1 trillion
- **Storage Path**: Must be writable directory

### Quantum Isolation
- Quantum layer outputs are **suggestions only**. Deterministic approval gate required before state mutation.

### Cryptographic Primitives
| Primitive | Implementation | Purpose |
|-----------|---------------|---------|
| SHA-256 | SPARK Ada (`sha256.ads`) | WORM chain linking |
| CRC-64 | SPARK Ada (`crc64.ads`) | Structural seal |
| HMAC-SHA-256 | SPARK Ada (`hmac_sha256.ads`) | Structural seal |
| FNV-1a | Rust/C++ | Fast non-crypto hashing |
| BLAKE3 | Python | Firmware integrity |

### Formal Verification
- **Lean 4**: 12 deed files, 0 sorry policy
- **Kani**: 31 bounded proof harnesses
- **SPARK Mode**: All Ada crypto in `SPARK_Mode => On`

## Reporting a Vulnerability

Contact: `ahmedparr93@gmail.com`

**Do not open public GitHub issues for security vulnerabilities.**

All reports are triaged within 48 hours. Critical vulnerabilities in WORM chain integrity or cryptographic primitives receive immediate attention.

## Security Practices

- No secrets or API keys committed to repository
- All dependencies pinned to exact versions
- CI pipeline runs `bandit` (Python), `cargo-audit` (Rust), `gnatprove` (Ada)
- Branch protection: requires PR review + passing CI before merge
- Force push disabled on `master`
