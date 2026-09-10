import hashlib
import json
import struct
from pathlib import Path

import jax
import jax.numpy as jnp


# ============================================================
# HARDENED RECURSIVE TENSOR INGESTION
# ============================================================

MAGIC = b"ASTRA-I32-TENSOR\x00"
VERSION = 1
HEADER_SIZE = 12
ROWS = 75000
COLS = 5
DTYPE = jnp.int32
EXPECTED_VALUES = ROWS * COLS


class HardenedTensorError(RuntimeError):
    pass


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def read_tensor_binary(path: str):
    p = Path(path)

    if not p.is_file():
        raise HardenedTensorError(f"missing tensor: {p}")

    raw = p.read_bytes()

    if len(raw) < HEADER_SIZE:
        raise HardenedTensorError("truncated tensor header")

    rank, rows, cols = struct.unpack_from("<III", raw, 0)

    if rank != 2:
        raise HardenedTensorError(f"unexpected rank: {rank}")

    if rows != ROWS or cols != COLS:
        raise HardenedTensorError(
            f"unexpected shape: {(rows, cols)}"
        )

    payload = raw[HEADER_SIZE:]

    expected_bytes = EXPECTED_VALUES * 4

    if len(payload) != expected_bytes:
        raise HardenedTensorError(
            f"payload size mismatch: "
            f"{len(payload)} != {expected_bytes}"
        )

    values = struct.unpack(
        f"<{EXPECTED_VALUES}i",
        payload,
    )

    return (
        jnp.asarray(values, dtype=DTYPE)
        .reshape((ROWS, COLS))
    )


def recursively_walk_weights(value, path=()):
    """
    Recursively descend through arbitrary nested JAX/Python
    containers and return leaf arrays.

    Supported:
      dict
      tuple
      list
      JAX arrays
      scalar leaves
    """

    if isinstance(value, dict):
        result = []

        for key in sorted(value.keys(), key=str):
            result.extend(
                recursively_walk_weights(
                    value[key],
                    path + (str(key),),
                )
            )

        return result

    if isinstance(value, (tuple, list)):
        result = []

        for index, item in enumerate(value):
            result.extend(
                recursively_walk_weights(
                    item,
                    path + (str(index),),
                )
            )

        return result

    array = jnp.asarray(value)

    return [
        {
            "path": "/".join(path),
            "array": array,
            "shape": tuple(array.shape),
            "dtype": str(array.dtype),
            "size": int(array.size),
        }
    ]


def validate_leaf(leaf):
    array = leaf["array"]

    if not isinstance(array, jax.Array):
        array = jnp.asarray(array)

    if any(int(x) < 0 for x in array.shape):
        raise HardenedTensorError(
            f"invalid shape at {leaf['path']}"
        )

    if array.size == 0:
        raise HardenedTensorError(
            f"empty tensor at {leaf['path']}"
        )

    if not jnp.issubdtype(array.dtype, jnp.number):
        raise HardenedTensorError(
            f"non-numeric tensor at {leaf['path']}"
        )

    if not bool(jnp.all(jnp.isfinite(
        array.astype(jnp.float32)
    ))):
        raise HardenedTensorError(
            f"non-finite tensor at {leaf['path']}"
        )

    return array


def canonicalize_weights(tree):
    leaves = recursively_walk_weights(tree)

    hardened = {}

    for leaf in leaves:
        array = validate_leaf(leaf)

        key = leaf["path"] or "root"

        if key in hardened:
            raise HardenedTensorError(
                f"duplicate weight path: {key}"
            )

        hardened[key] = array

    return hardened


# ============================================================
# ASTRA WEIGHT CONTAINER
# ============================================================

class AstraWeights:
    def __init__(self, weights):
        self.weights = canonicalize_weights(weights)

    def keys(self):
        return tuple(sorted(self.weights.keys()))

    def __getitem__(self, key):
        return self.weights[key]

    def items(self):
        for key in self.keys():
            yield key, self.weights[key]

    def leaves(self):
        return tuple(self.weights.values())

    def fingerprint(self):
        h = hashlib.sha256()

        for key, array in self.items():
            key_bytes = key.encode("utf-8")

            host = jax.device_get(array)
            raw = host.tobytes()

            h.update(struct.pack("<I", len(key_bytes)))
            h.update(key_bytes)

            h.update(struct.pack(
                "<I",
                len(array.shape),
            ))

            for dimension in array.shape:
                h.update(struct.pack(
                    "<Q",
                    int(dimension),
                ))

            dtype = str(array.dtype).encode("utf-8")

            h.update(struct.pack(
                "<I",
                len(dtype),
            ))

            h.update(dtype)
            h.update(raw)

        return h.hexdigest()

    def manifest(self):
        result = []

        for key, array in self.items():
            result.append(
                {
                    "path": key,
                    "shape": tuple(
                        int(x) for x in array.shape
                    ),
                    "dtype": str(array.dtype),
                    "elements": int(array.size),
                }
            )

        return result


# ============================================================
# RECURSIVE TRANSFORM
# ============================================================

@jax.jit
def recursive_opcode_transform(x):
    """
    Deterministic tensor transform.

    Columns:

      0 = iteration
      1 = cluster opcode
      2 = transform opcode
      3 = verify opcode
      4 = advance opcode
    """

    iteration = x[:, 0]
    cluster = x[:, 1]
    transform = x[:, 2]
    verify = x[:, 3]
    advance = x[:, 4]

    active = cluster != 30

    transformed = jnp.stack(
        (
            iteration,
            cluster,
            transform,
            verify,
            advance,
        ),
        axis=1,
    )

    return jnp.where(
        active[:, None],
        transformed,
        transformed,
    )


@jax.jit
def hardened_cluster_mask(x):
    cluster = x[:, 1]

    return (
        (cluster != 0)
        & (cluster != 30)
    )


@jax.jit
def hardened_iteration_check(x):
    iterations = x[:, 0]

    return (
        iterations[:-1]
        <= iterations[1:]
    )


# ============================================================
# RECURSIVE WEIGHT PACKING
# ============================================================

def pack_tensor_as_weights(tensor):
    return {
        "astra": {
            "opcode_tensor": tensor,
            "metadata": {
                "rows": jnp.asarray(
                    tensor.shape[0],
                    dtype=jnp.int32,
                ),
                "columns": jnp.asarray(
                    tensor.shape[1],
                    dtype=jnp.int32,
                ),
            },
        }
    }


def recursively_harden(tree):
    leaves = recursively_walk_weights(tree)

    output = {}

    for leaf in leaves:
        array = validate_leaf(leaf)

        output[leaf["path"]] = jax.device_put(
            jnp.asarray(array)
        )

    return output


# ============================================================
# HARDENED INGESTION ENTRYPOINT
# ============================================================

def ingest(path):
    tensor = read_tensor_binary(path)

    transformed = recursive_opcode_transform(
        tensor
    )

    ordered = hardened_iteration_check(
        transformed
    )

    if not bool(jnp.all(ordered)):
        raise HardenedTensorError(
            "iteration ordering violation"
        )

    weights = pack_tensor_as_weights(
        transformed
    )

    hardened = AstraWeights(
        recursively_harden(weights)
    )

    return hardened


# ============================================================
# PURE IN-MEMORY EXECUTION
# ============================================================

tensor_path = (
    "/mnt/data/"
    "agnostic_text_remover_tensor_75000_i32.bin"
)

weights = ingest(tensor_path)

print("ASTRA HARDENED WEIGHT INGESTION")
print("=" * 64)
print("JAX version:", jax.__version__)
print("Backend:", jax.default_backend())
print("Weight paths:")

for key in weights.keys():
    print(" ", key)

print()
print("Tensor manifest:")

for item in weights.manifest():
    print(
        item["path"],
        item["shape"],
        item["dtype"],
        item["elements"],
    )

print()
print("Fingerprint:")
print(weights.fingerprint())


# ============================================================
# RECURSIVE CLUSTER EXECUTION
# ============================================================

opcode_tensor = weights[
    "astra/opcode_tensor"
]

cluster_mask = hardened_cluster_mask(
    opcode_tensor
)

active_count = int(
    jnp.sum(cluster_mask)
)

total_count = int(
    opcode_tensor.shape[0]
)

print()
print("Recursive cluster state")
print("=" * 64)
print("Total rows :", total_count)
print("Active rows:", active_count)
print("Exit rows :", total_count - active_count)


# ============================================================
# FINAL JAX DEVICE MATERIALIZATION
# ============================================================

device_tensor = jax.device_put(
    opcode_tensor
)

print()
print("Device tensor:")
print("shape :", device_tensor.shape)
print("dtype :", device_tensor.dtype)
print("device:", device_tensor.devices())


# ============================================================
# OPTIONAL PURE JAX RECURSIVE REDUCTION
# ============================================================

@jax.jit
def reduce_opcode_tensor(x):
    return jnp.asarray(
        [
            jnp.sum(x[:, 0]),
            jnp.sum(x[:, 1]),
            jnp.sum(x[:, 2]),
            jnp.sum(x[:, 3]),
            jnp.sum(x[:, 4]),
        ],
        dtype=jnp.int64,
    )


summary = reduce_opcode_tensor(
    device_tensor
)

print()
print("Opcode reduction:")
print(jax.device_get(summary))
