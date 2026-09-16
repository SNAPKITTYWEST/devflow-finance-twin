-- wigner_futhark.fut
-- Futhark kernels for discrete Wigner transform (1-mode truncated Fock) and Monte Carlo resampling.
-- Compile with: futhark opencl wigner_futhark.fut  (or futhark c)

module main

let pi = 3.141592653589793

-- Discrete Wigner function for truncated Fock state rho (n x n real arrays for real/imag parts)
-- Input: rho_re, rho_im flattened row-major length n*n
-- Output: wigner grid of size m x m
let wigner_transform [n][m] (rho_re: [n*n]f64) (rho_im: [n*n]f64) : [m*m]f64 =
  let dx = 1.0 / f64 m
  in map2 (\k l ->
    let x = (f64 k - f64 m / 2.0) * dx
    let p = (f64 l - f64 m / 2.0) * dx
    let sum = reduce (+) 0.0 (map2 (\i j ->
      let idxmn = i*n + j
      let r = rho_re[idxmn]
      let phi = f64.exp(- (x*x + p*p)) * f64.cos((f64 (i-j)) * (x + p))
      r * phi
    ) (iota n) (iota n))
    in sum
  ) (iota m) (iota m)

-- Systematic resampling
let systematic_resample [N] (weights: [N]f64) : [N]i64 =
  let Nf = f64 N
  let cdf = scan (+) 0.0 weights
  let u0 = 0.5 / Nf
  let positions = map (\i -> u0 + f64 i / Nf) (iota N)
  in map (\u ->
    let idx = loop j = 0i64 for j2 < N do
      if cdf[j2] >= u then break j2 else j2 + 1i64
    in idx
  ) positions

let resample_particles [N] (weights: [N]f64) (particles: [N]i64) : [N]i64 =
  let idxs = systematic_resample weights
  in map (\i -> particles[i]) idxs

entry main (n: i64) (m: i64) : [m*m]f64 =
  let rho_re = replicate (n*n) 0.0
  let rho_im = replicate (n*n) 0.0
  in wigner_transform rho_re rho_im
