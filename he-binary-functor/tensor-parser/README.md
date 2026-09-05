# tensor-parser

**SPARK Ada Zero-Copy Tensor Parser** — Formally verified zero-copy parser for BTEN binary tensor format with SHA-256, CRC-64, HMAC-SHA-256, and SHA-256 reverse hash implementations.

## Subdirectories

| Directory | Description |
|-----------|-------------|
| [test_fixtures/](test_fixtures/) | 10 BTEN test vectors (valid + malformed) |

## Source Files

| File | Language | Description |
|------|----------|-------------|
| `format.ads` | SPARK Ada | DBTC binary format spec |
| `format_mltr.ads` | SPARK Ada | MLTR format variant |
| `format_bten.ads` / `.adb` | SPARK Ada | BTEN format spec + body |
| `parser.ads` / `.adb` | SPARK Ada | Zero-copy parser |
| `parser_mltr.ads` / `.adb` | SPARK Ada | MLTR parser |
| `parser_bten.ads` / `.adb` | SPARK Ada | BTEN parser |
| `parser_final.adb` | SPARK Ada | Final optimized parser |
| `validation.ads` / `.adb` | SPARK Ada | Validation logic |
| `validation_mltr.ads` / `.adb` | SPARK Ada | MLTR validation |
| `validation_final.ads` / `.adb` | SPARK Ada | Final validation |
| `sha256.ads` / `.adb` | SPARK Ada | FIPS-180-4 SHA-256 |
| `crc64.ads` / `.adb` | SPARK Ada | CRC-64 (ISO 3309) |
| `hmac_sha256.ads` / `.adb` | SPARK Ada | HMAC-SHA-256 |
| `sha256_reverse.ads` / `.adb` | SPARK Ada | Bounded pre-image search |
| `ModelParserRefinement.hs` | Haskell | Refinement model |
| `assembly_correspondence.txt` | Text | Assembly correspondence |
| `verification_report.txt` | Text | Verification report |

## BTEN Format

```
BTEN Header:
  magic: u32 (0x4254454E "BTEN")
  version: u8
  tensor_count: u32
  flags: u8

Tensor Descriptor (per tensor):
  id: u32
  rank: u8
  dtype: u8 (0=FP32, 1=FP16, 2=INT8, 3=UINT8)
  shape: [u32; rank]
  offset: u64
  length: u64
  crc32: u32
  sha256_seal: [u8; 32]

Payload: Concatenated tensor data
```

## Test Fixtures (10 files)

| Fixture | Description |
|---------|-------------|
| `valid_2tensors.bten` | Valid 2-tensor file |
| `valid_2tensors_v2.bten` | V2 valid file |
| `empty_model.bten` | Empty tensor list |
| `max_tensor_count.bten` | Maximum tensors |
| `max_rank.bten` | Maximum rank |
| `malformed_magic_v1.bten` | Bad magic bytes |
| `malformed_magic_v2.bten` | Bad magic bytes v2 |
| `truncated_descriptor_v1.bten` | Truncated descriptor |
| `truncated_descriptor_v2.bten` | Truncated descriptor v2 |
| `invalid_dtype.bten` | Invalid dtype |

## Build & Verify

```bash
# SPARK proof
cd tensor-parser && gnatprove -P project.gpr

# Compile
gnatmake -P project.gpr
```

## Cryptographic Primitives

| Primitive | File | Standard |
|-----------|------|----------|
| SHA-256 | sha256.ads/.adb | FIPS-180-4 |
| CRC-64 | crc64.ads/.adb | ISO 3309 |
| HMAC-SHA-256 | hmac_sha256.ads/.adb | RFC 2104 |
| SHA-256 Reverse | sha256_reverse.ads/.adb | Bounded search |