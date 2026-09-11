# ========================================================================
# SOVEREIGN LEVIATHAN NODE LICENSE
# License-ID: SL-AGPL3-001 | Covenant-Version: 1.0
# Copyright (C) 2026 SnapKittyWest. Ahmad Ali Parr, Bel Esprit D'Accord Irrevocable Trust.
# ========================================================================
#
# This file is a covered work under the GNU Affero General Public License,
# version 3, together with the Sovereign Leviathan additional terms.
#
# Hark, though this node be but a spark,
# Its covenant endureth through the dark.
#
# Ignorantia juris non excusat.
# ========================================================================

"""Complex number arithmetic for quantum computing. Pure Python, no dependencies."""
import math
import cmath
import json
from typing import Tuple, List

class Complex:
    __slots__ = ('_re', '_im')
    def __init__(self, re: float = 0.0, im: float = 0.0):
        self._re = float(re)
        self._im = float(im)
    @property
    def re(self) -> float:
        return self._re
    @property
    def im(self) -> float:
        return self._im
    def __add__(self, other):
        if isinstance(other, Complex):
            return Complex(self._re + other._re, self._im + other._im)
        if isinstance(other, (int, float)):
            return Complex(self._re + float(other), self._im)
        return NotImplemented
    def __radd__(self, other):
        return self.__add__(other)
    def __sub__(self, other):
        if isinstance(other, Complex):
            return Complex(self._re - other._re, self._im - other._im)
        if isinstance(other, (int, float)):
            return Complex(self._re - float(other), self._im)
        return NotImplemented
    def __rsub__(self, other):
        if isinstance(other, (int, float)):
            return Complex(float(other) - self._re, -self._im)
        return NotImplemented
    def __mul__(self, other):
        if isinstance(other, Complex):
            return Complex(
                self._re * other._re - self._im * other._im,
                self._re * other._im + self._im * other._re
            )
        if isinstance(other, (int, float)):
            return Complex(self._re * float(other), self._im * float(other))
        return NotImplemented
    def __rmul__(self, other):
        return self.__mul__(other)
    def __truediv__(self, other):
        if isinstance(other, Complex):
            d = other._re * other._re + other._im * other._im
            if d == 0.0:
                raise ZeroDivisionError("Complex division by zero")
            return Complex(
                (self._re * other._re + self._im * other._im) / d,
                (self._im * other._re - self._re * other._im) / d
            )
        if isinstance(other, (int, float)):
            if other == 0.0:
                raise ZeroDivisionError("Complex division by zero")
            f = float(other)
            return Complex(self._re / f, self._im / f)
        return NotImplemented
    def __rtruediv__(self, other):
        if isinstance(other, (int, float)):
            return Complex(float(other), 0.0) / self
        return NotImplemented
    def __neg__(self):
        return Complex(-self._re, -self._im)
    def __abs__(self) -> float:
        return math.sqrt(self._re * self._re + self._im * self._im)
    def __eq__(self, other):
        if isinstance(other, Complex):
            return math.isclose(self._re, other._re, abs_tol=1e-12) and math.isclose(self._im, other._im, abs_tol=1e-12)
        if isinstance(other, (int, float)):
            return math.isclose(self._re, float(other), abs_tol=1e-12) and math.isclose(self._im, 0.0, abs_tol=1e-12)
        return NotImplemented
    def __ne__(self, other):
        result = self.__eq__(other)
        return not result if result is not NotImplemented else NotImplemented
    def __hash__(self):
        return hash((round(self._re, 12), round(self._im, 12)))
    def __repr__(self):
        if math.isclose(self._im, 0.0, abs_tol=1e-12):
            return f"Complex({self._re})"
        if math.isclose(self._re, 0.0, abs_tol=1e-12):
            return f"Complex({self._im}j)"
        sign = "+" if self._im >= 0 else "-"
        return f"Complex({self._re} {sign} {abs(self._im)}j)"
    def __str__(self):
        if math.isclose(self._im, 0.0, abs_tol=1e-12):
            return str(self._re)
        if math.isclose(self._re, 0.0, abs_tol=1e-12):
            return f"{self._im}j"
        sign = "+" if self._im >= 0 else "-"
        return f"{self._re}{sign}{abs(self._im)}j"
    def conjugate(self) -> 'Complex':
        return Complex(self._re, -self._im)
    def abs_sq(self) -> float:
        return self._re * self._re + self._im * self._im
    def abs_val(self) -> float:
        return math.sqrt(self.abs_sq())
    def phase(self) -> float:
        return math.atan2(self._im, self._re)
    def exp(self) -> 'Complex':
        er = math.exp(self._re)
        return Complex(er * math.cos(self._im), er * math.sin(self._im))
    def pow(self, n: int) -> 'Complex':
        if n == 0:
            return Complex(1.0, 0.0)
        if n < 0:
            return Complex(1.0, 0.0) / self.pow(-n)
        result = Complex(1.0, 0.0)
        base = self
        exp = n
        while exp > 0:
            if exp & 1:
                result = result * base
            base = base * base
            exp >>= 1
        return result
    def sqrt(self) -> 'Complex':
        r = self.abs_val()
        theta = self.phase()
        sr = math.sqrt(r)
        return Complex(sr * math.cos(theta / 2), sr * math.sin(theta / 2))
    def to_json(self) -> dict:
        return {"re": self._re, "im": self._im}
    @staticmethod
    def from_json(d: dict) -> 'Complex':
        return Complex(d["re"], d["im"])
    @staticmethod
    def from_polar(r: float, theta: float) -> 'Complex':
        return Complex(r * math.cos(theta), r * math.sin(theta))

ZERO = Complex(0.0, 0.0)
ONE = Complex(1.0, 0.0)
I = Complex(0.0, 1.0)
NEG_ONE = Complex(-1.0, 0.0)
INV_SQRT2 = Complex(1.0 / math.sqrt(2), 0.0)
NEG_I = Complex(0.0, -1.0)

def inner_product(a: List[Complex], b: List[Complex]) -> Complex:
    if len(a) != len(b):
        raise ValueError("Vector length mismatch")
    result = ZERO
    for i in range(len(a)):
        result = result + a[i].conjugate() * b[i]
    return result

def outer_product(a: List[Complex], b: List[Complex]) -> List[List[Complex]]:
    result = []
    for ai in a:
        row = []
        for bj in b:
            row.append(ai * bj.conjugate())
        result.append(row)
    return result

def tensor_product_vectors(a: List[Complex], b: List[Complex]) -> List[Complex]:
    result = []
    for ai in a:
        for bj in b:
            result.append(ai * bj)
    return result

def normalize_vector(v: List[Complex]) -> List[Complex]:
    norm_sq = sum(x.abs_sq() for x in v)
    if norm_sq < 1e-24:
        raise ValueError("Cannot normalize zero vector")
    norm = math.sqrt(norm_sq)
    inv_norm = 1.0 / norm
    return [x * inv_norm for x in v]

def vector_norm(v: List[Complex]) -> float:
    return math.sqrt(sum(x.abs_sq() for x in v))

def vector_add(a: List[Complex], b: List[Complex]) -> List[Complex]:
    if len(a) != len(b):
        raise ValueError("Vector length mismatch")
    return [a[i] + b[i] for i in range(len(a))]

def vector_sub(a: List[Complex], b: List[Complex]) -> List[Complex]:
    if len(a) != len(b):
        raise ValueError("Vector length mismatch")
    return [a[i] - b[i] for i in range(len(a))]

def scalar_mult(s: Complex, v: List[Complex]) -> List[Complex]:
    return [s * x for x in v]

def dot_product(a: List[Complex], b: List[Complex]) -> Complex:
    return inner_product(a, b)
