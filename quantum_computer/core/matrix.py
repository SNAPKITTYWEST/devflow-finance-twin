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

"""Matrix operations for quantum computing. Uses Complex from complex.py."""
from typing import List, Optional, Tuple
from quantum_computer.core.complex import Complex, ZERO, ONE, I

class Matrix:
    __slots__ = ('_rows', '_cols', '_data')
    def __init__(self, data: List[List[Complex]]):
        if not data or not data[0]:
            raise ValueError("Matrix data cannot be empty")
        self._rows = len(data)
        self._cols = len(data[0])
        for row in data:
            if len(row) != self._cols:
                raise ValueError("All rows must have equal length")
        self._data = [row[:] for row in data]
    @property
    def rows(self) -> int:
        return self._rows
    @property
    def cols(self) -> int:
        return self._cols
    def get(self, r: int, c: int) -> Complex:
        return self._data[r][c]
    def set(self, r: int, c: int, val: Complex):
        self._data[r][c] = val
    def shape(self) -> Tuple[int, int]:
        return (self._rows, self._cols)
    def is_square(self) -> bool:
        return self._rows == self._cols
    def __eq__(self, other):
        if not isinstance(other, Matrix):
            return NotImplemented
        if self._rows != other._rows or self._cols != other._cols:
            return False
        for r in range(self._rows):
            for c in range(self._cols):
                if self._data[r][c] != other._data[r][c]:
                    return False
        return True
    def __add__(self, other):
        if not isinstance(other, Matrix):
            return NotImplemented
        if self._rows != other._rows or self._cols != other._cols:
            raise ValueError("Matrix dimension mismatch for addition")
        result = []
        for r in range(self._rows):
            row = []
            for c in range(self._cols):
                row.append(self._data[r][c] + other._data[r][c])
            result.append(row)
        return Matrix(result)
    def __sub__(self, other):
        if not isinstance(other, Matrix):
            return NotImplemented
        if self._rows != other._rows or self._cols != other._cols:
            raise ValueError("Matrix dimension mismatch for subtraction")
        result = []
        for r in range(self._rows):
            row = []
            for c in range(self._cols):
                row.append(self._data[r][c] - other._data[r][c])
            result.append(row)
        return Matrix(result)
    def __mul__(self, other):
        if isinstance(other, Matrix):
            if self._cols != other._rows:
                raise ValueError("Matrix dimension mismatch for multiplication")
            result = []
            for r in range(self._rows):
                row = []
                for c in range(other._cols):
                    s = ZERO
                    for k in range(self._cols):
                        s = s + self._data[r][k] * other._data[k][c]
                    row.append(s)
                result.append(row)
            return Matrix(result)
        if isinstance(other, Complex):
            result = []
            for r in range(self._rows):
                row = []
                for c in range(self._cols):
                    row.append(self._data[r][c] * other)
                result.append(row)
            return Matrix(result)
        if isinstance(other, (int, float)):
            return self * Complex(float(other))
        return NotImplemented
    def __rmul__(self, other):
        if isinstance(other, (int, float, Complex)):
            return self.__mul__(other)
        return NotImplemented
    def __neg__(self):
        return self * Complex(-1.0)
    def transpose(self) -> 'Matrix':
        result = []
        for c in range(self._cols):
            row = []
            for r in range(self._rows):
                row.append(self._data[r][c])
            result.append(row)
        return Matrix(result)
    def conjugate(self) -> 'Matrix':
        result = []
        for r in range(self._rows):
            row = []
            for c in range(self._cols):
                row.append(self._data[r][c].conjugate())
            result.append(row)
        return Matrix(result)
    def dagger(self) -> 'Matrix':
        return self.transpose().conjugate()
    def trace(self) -> Complex:
        if not self.is_square():
            raise ValueError("Trace requires square matrix")
        s = ZERO
        for i in range(self._rows):
            s = s + self._data[i][i]
        return s
    def frobenius_norm(self) -> float:
        s = 0.0
        for r in range(self._rows):
            for c in range(self._cols):
                s += self._data[r][c].abs_sq()
        return s ** 0.5
    def is_unitary(self, tol: float = 1e-10) -> bool:
        if not self.is_square():
            return False
        product = self * self.dagger()
        identity = identity_matrix(self._rows)
        return matrix_approx_eq(product, identity, tol)
    def is_hermitian(self, tol: float = 1e-10) -> bool:
        if not self.is_square():
            return False
        return matrix_approx_eq(self, self.dagger(), tol)
    def determinant(self) -> Complex:
        if not self.is_square():
            raise ValueError("Determinant requires square matrix")
        n = self._rows
        if n == 1:
            return self._data[0][0]
        if n == 2:
            return self._data[0][0] * self._data[1][1] - self._data[0][1] * self._data[1][0]
        det = ZERO
        sign = 1
        for c in range(n):
            minor = []
            for r in range(1, n):
                mrow = []
                for cc in range(n):
                    if cc != c:
                        mrow.append(self._data[r][cc])
                minor.append(mrow)
            m = Matrix(minor)
            det = det + Complex(float(sign)) * self._data[0][c] * m.determinant()
            sign *= -1
        return det
    def inverse(self) -> 'Matrix':
        if not self.is_square():
            raise ValueError("Inverse requires square matrix")
        n = self._rows
        det = self.determinant()
        if det.abs_sq() < 1e-24:
            raise ValueError("Matrix is singular")
        if n == 1:
            return Matrix([[ONE / det]])
        adj = self.adjugate()
        return adj * (ONE / det)
    def adjugate(self) -> 'Matrix':
        n = self._rows
        result = []
        for r in range(n):
            row = []
            for c in range(n):
                minor = []
                for mr in range(n):
                    if mr == r:
                        continue
                    mrow = []
                    for mc in range(n):
                        if mc == c:
                            continue
                        mrow.append(self._data[mr][mc])
                    minor.append(mrow)
                m = Matrix(minor)
                cofactor = m.determinant() * Complex(float((-1) ** (r + c)))
                row.append(cofactor)
            result.append(row)
        return Matrix(result).transpose()
    def eigenvalues_hermitian(self) -> List[Complex]:
        if not self.is_hermitian():
            raise ValueError("Eigenvalue decomposition requires Hermitian matrix")
        n = self._rows
        if n == 1:
            return [self._data[0][0]]
        if n == 2:
            a = self._data[0][0].re
            b = self._data[0][1]
            d = self._data[1][1].re
            disc = ((a - d) ** 2 + 4.0 * b.abs_sq()) ** 0.5
            return [Complex((a + d + disc) / 2.0), Complex((a + d - disc) / 2.0)]
        vals = []
        m_data = [row[:] for row in self._data]
        for _ in range(100):
            q, r = qr_decomposition_hermitian(m_data, n)
            m_data = []
            for row_r in range(n):
                mrow = []
                for col_r in range(n):
                    s = ZERO
                    for k in range(n):
                        s = s + r[row_r][k] * q[k][col_r]
                    mrow.append(s)
                m_data.append(mrow)
        for i in range(n):
            vals.append(m_data[i][i])
        return vals
    def to_list(self) -> List[List[Complex]]:
        return [row[:] for row in self._data]
    def __repr__(self):
        lines = []
        for r in range(self._rows):
            vals = [str(self._data[r][c]) for c in range(self._cols)]
            lines.append("[" + ", ".join(vals) + "]")
        return "Matrix([" + "\n ".join(lines) + "])"
    def copy(self) -> 'Matrix':
        return Matrix([row[:] for row in self._data])

def identity_matrix(n: int) -> 'Matrix':
    data = []
    for r in range(n):
        row = []
        for c in range(n):
            row.append(ONE if r == c else ZERO)
        data.append(row)
    return Matrix(data)

def zero_matrix(rows: int, cols: int) -> 'Matrix':
    return Matrix([[ZERO] * cols for _ in range(rows)])

def diagonal_matrix(diag: List[Complex]) -> 'Matrix':
    n = len(diag)
    data = []
    for r in range(n):
        row = []
        for c in range(n):
            row.append(diag[r] if r == c else ZERO)
        data.append(row)
    return Matrix(data)

def matrix_approx_eq(a: 'Matrix', b: 'Matrix', tol: float = 1e-10) -> bool:
    if a.rows != b.rows or a.cols != b.cols:
        return False
    for r in range(a.rows):
        for c in range(a.cols):
            diff = a.get(r, c) - b.get(r, c)
            if diff.abs_sq() > tol * tol:
                return False
    return True

def tensor_product(a: 'Matrix', b: 'Matrix') -> 'Matrix':
    result = []
    for r1 in range(a.rows):
        for r2 in range(b.rows):
            row = []
            for c1 in range(a.cols):
                for c2 in range(b.cols):
                    row.append(a.get(r1, c1) * b.get(r2, c2))
            result.append(row)
    return Matrix(result)

def controlled_matrix(control_gate: 'Matrix', n_qubits: int, control: int, target: int) -> 'Matrix':
    dim = 1 << n_qubits
    result = []
    for row in range(dim):
        resultrow = []
        for col in range(dim):
            resultrow.append(ZERO)
        result.append(resultrow)
    for state in range(dim):
        ctrl_bit = (state >> (n_qubits - 1 - control)) & 1
        tgt_bit = (state >> (n_qubits - 1 - target)) & 1
        if ctrl_bit == 0:
            result[state][state] = ONE
        else:
            tgt_index = 0
            for bit in range(n_qubits):
                if bit == target:
                    continue
                bval = (state >> (n_qubits - 1 - bit)) & 1
                tgt_index |= bval << (int.bit_length(control_gate.rows) - 1 - bit)
            for new_tgt in range(control_gate.rows):
                new_state = state
                if new_tgt != tgt_bit:
                    new_state ^= (1 << (n_qubits - 1 - target))
                for k in range(control_gate.cols):
                    if ((new_tgt >> k) & 1) == tgt_bit:
                        pass
            ctrl_state = tgt_bit
            new_ctrl_state = 0
            for k in range(control_gate.rows):
                coeff = control_gate.get(ctrl_state, k)
                if coeff.abs_sq() > 1e-24:
                    new_state = state
                    if k != tgt_bit:
                        new_state = state ^ (1 << (n_qubits - 1 - target))
                        if k == 1:
                            new_state = state | (1 << (n_qubits - 1 - target))
                        elif k == 0:
                            new_state = state & ~(1 << (n_qubits - 1 - target))
                    result[new_state][state] = result[new_state][state] + coeff
    return Matrix(result)

def sparse_controlled_unitary(gate_data: List[List[Complex]], n_qubits: int, control: int, target: int) -> 'Matrix':
    dim = 1 << n_qubits
    gate_dim = len(gate_data)
    data = [[ZERO] * dim for _ in range(dim)]
    for state in range(dim):
        ctrl_bit = (state >> (n_qubits - 1 - control)) & 1
        if ctrl_bit == 0:
            data[state][state] = ONE
        else:
            tgt_val = 0
            other_bits = 0
            for b in range(n_qubits):
                if b == target:
                    tgt_val = (state >> (n_qubits - 1 - b)) & 1
                else:
                    pos = gate_dim - 1 - (b if b < target else b - 1)
                    if b < target:
                        pos = n_qubits - 2 - b
                    else:
                        pos = n_qubits - 2 - b
                    other_bits |= ((state >> (n_qubits - 1 - b)) & 1) << pos
            for new_tgt in range(gate_dim):
                coeff = gate_data[tgt_val][new_tgt]
                if coeff.abs_sq() < 1e-24:
                    continue
                new_state = 0
                remaining = other_bits
                for b in range(n_qubits):
                    if b == target:
                        new_state |= new_tgt << (n_qubits - 1 - b)
                    else:
                        pos = n_qubits - 2 - (b if b < target else b - 1)
                        bit_val = (remaining >> pos) & 1
                        new_state |= bit_val << (n_qubits - 1 - b)
                data[new_state][state] = data[new_state][state] + coeff
    return Matrix(data)

def qr_decomposition_hermitian(m_data: List[List[Complex]], n: int) -> Tuple:
    q = [[ZERO] * n for _ in range(n)]
    r = [[ZERO] * n for _ in range(n)]
    for j in range(n):
        for i in range(n):
            q[i][j] = m_data[i][j]
        for k in range(j):
            s = ZERO
            for i in range(n):
                s = s + q[i][k].conjugate() * m_data[i][j]
            r[k][j] = s
            for i in range(n):
                q[i][j] = q[i][j] - s * q[i][k]
        norm = ZERO
        for i in range(n):
            norm = norm + q[i][j].abs_sq()
        norm_val = norm.re ** 0.5
        if norm_val < 1e-24:
            q[j][j] = ONE
            r[j][j] = ZERO
        else:
            r[j][j] = Complex(norm_val)
            inv = ONE / Complex(norm_val)
            for i in range(n):
                q[i][j] = q[i][j] * inv
    return q, r

def matrix_from_lists(data: List[List[float]]) -> 'Matrix':
    return Matrix([[Complex(x) for x in row] for row in data])

def matrix_from_complex_lists(data: List[List[Complex]]) -> 'Matrix':
    return Matrix(data)

def kronecker_product(a: 'Matrix', b: 'Matrix') -> 'Matrix':
    return tensor_product(a, b)

def matrix_power(m: 'Matrix', n: int) -> 'Matrix':
    if not m.is_square():
        raise ValueError("Matrix power requires square matrix")
    if n == 0:
        return identity_matrix(m.rows)
    if n == 1:
        return m.copy()
    if n < 0:
        return m.inverse().power(-n)
    result = identity_matrix(m.rows)
    base = m.copy()
    exp = n
    while exp > 0:
        if exp & 1:
            result = result * base
        base = base * base
        exp >>= 1
    return result

def matrix_exp(m: 'Matrix', terms: int = 20) -> 'Matrix':
    if not m.is_square():
        raise ValueError("Matrix exponential requires square matrix")
    n = m.rows
    result = identity_matrix(n)
    term = identity_matrix(n)
    for k in range(1, terms):
        term = term * m * (ONE / Complex(float(k)))
        result = result + term
    return result

def spectral_decomposition_hermitian(m: 'Matrix') -> Tuple[List[Complex], 'Matrix']:
    if not m.is_hermitian():
        raise ValueError("Spectral decomposition requires Hermitian matrix")
    eigenvals = m.eigenvalues_hermitian()
    n = m.rows
    eigenvecs = []
    for val in eigenvals:
        shifted = m - diagonal_matrix([val] * n)
        vec = [Complex(0.0)] * n
        vec[-1] = ONE
        for _ in range(n * 10):
            new_vec = [ZERO] * n
            for r in range(n):
                s = ZERO
                for c in range(n):
                    s = s + shifted.get(r, c) * vec[c]
                new_vec[r] = s
            norm_sq = sum(x.abs_sq() for x in new_vec)
            if norm_sq > 1e-24:
                norm = norm_sq ** 0.5
                vec = [x / norm for x in new_vec]
            else:
                break
        eigenvecs.append(vec)
    vec_matrix = []
    for c in range(n):
        col = [eigenvecs[r][c] for r in range(n)]
        vec_matrix.append(col)
    vec_mat = Matrix(vec_matrix).transpose()
    return eigenvals, vec_mat
