#!/usr/bin/env python3
"""
Non-Commutative Torus Resonance Spike Simulator
================================================
Models worst-case resonance spikes between epsilon (Holder/regularity),
beta (coupling/amplitude), and rho (basin radius) for an irrational
frequency alpha given by its continued-fraction expansion.

Features
--------
* Accepts alpha as continued fraction [a0; a1, ..., an]
* Computes all convergents p_n/q_n exactly
* Evaluates the Diophantine lower bound |alpha - p_n/q_n| > C / q_n^mu
* Constructs a resonance-amplitude surface over (rho, n)
* Derives analytic threshold conditions on epsilon and beta
* Interactive CLI + optional parameter sweep
* Generates a multi-page PDF scientific report

Usage examples
--------------
python3 nct_resonance_simulator.py \
    --cf "[0;1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1]" \
    --eps 1.0 --beta 0.15 \
    --out golden_resonance_report.pdf --list-convs

python3 nct_resonance_simulator.py \
    --cf "[0;1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1]" \
    --eps 1.0 --beta 0.15 --C 0.25 --mu 2.0 \
    --out golden_resonance_report.pdf

python3 nct_resonance_simulator.py \
    --cf "[0;2,2,2,2,2,2,2,2,2,2]" \
    --eps 1.2 --beta 0.05 \
    --out silver_resonance_report.pdf
"""

from __future__ import annotations

import argparse
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import List, Tuple, Optional, Dict, Any

import numpy as np
import matplotlib.pyplot as plt
from matplotlib.backends.backend_pdf import PdfPages
from matplotlib.gridspec import GridSpec
import matplotlib.ticker as ticker

# Optional exact arithmetic
try:
    from fractions import Fraction
    HAS_FRACTION = True
except ImportError:
    HAS_FRACTION = False

# ---------------------------------------------------------------------------
# 1. Continued-fraction & convergent engine
# ---------------------------------------------------------------------------

@dataclass
class Convergent:
    n: int
    a: int
    p: int
    q: int
    alpha_approx: float
    delta: float          # |alpha - p/q|
    signed_delta: float   # alpha - p/q
    log_q: float
    bound_C_mu: float     # C / q^mu


def continued_fraction_value(cf: List[int]) -> float:
    """Evaluate finite continued fraction [a0; a1, ..., an] as float."""
    if not cf:
        raise ValueError("Empty continued fraction")
    val = float(cf[-1])
    for a in reversed(cf[:-1]):
        val = a + 1.0 / val
    return val


def compute_convergents(cf: List[int], alpha: Optional[float] = None) -> List[Convergent]:
    """
    Standard three-term recurrence for convergents.
    p_{-2}=0, p_{-1}=1, q_{-2}=1, q_{-1}=0
    """
    if alpha is None:
        alpha = continued_fraction_value(cf)

    convergents: List[Convergent] = []
    p_nm2, p_nm1 = 0, 1
    q_nm2, q_nm1 = 1, 0

    for n, a in enumerate(cf):
        p = a * p_nm1 + p_nm2
        q = a * q_nm1 + q_nm2
        approx = p / q if q != 0 else float("inf")
        delta = abs(alpha - approx)
        signed = alpha - approx
        convergents.append(Convergent(
            n=n, a=a, p=p, q=q,
            alpha_approx=approx,
            delta=delta,
            signed_delta=signed,
            log_q=np.log(q) if q > 0 else 0.0,
            bound_C_mu=0.0  # filled later
        ))
        p_nm2, p_nm1 = p_nm1, p
        q_nm2, q_nm1 = q_nm1, q
    return convergents


def fill_diophantine_bounds(convs: List[Convergent], C: float, mu: float) -> None:
    """In-place: bound = C / q^mu"""
    for c in convs:
        if c.q > 0:
            c.bound_C_mu = C / (c.q ** mu)
        else:
            c.bound_C_mu = float("inf")


# ---------------------------------------------------------------------------
# 2. Resonance amplitude model (worst-case spikes)
# ---------------------------------------------------------------------------

@dataclass
class ResonanceModel:
    """
    Phenomenological model of resonance spike amplitude on the
    non-commutative torus.

    A_n(rho; eps, beta) =
        beta * (rho / delta_n)^eps * exp(-gamma * q_n * rho)
        / (1 + (q_n * rho)^kappa)

    - The power (rho/delta)^eps captures the small-divisor amplification
      controlled by the regularity eps.
    - The exponential decay models the spatial localization /
      basin cut-off of radius rho.
    - The polynomial denominator regularises the ultraviolet.
    """
    gamma: float = 0.15   # localization strength
    kappa: float = 1.5    # UV regularisation
    C: float = 0.25       # Diophantine constant
    mu: float = 2.0       # Diophantine exponent (2 = badly approximable)

    def amplitude(
        self,
        delta: float,
        q: int,
        rho: np.ndarray,
        eps: float,
        beta: float
    ) -> np.ndarray:
        """Vectorised amplitude over rho array."""
        if delta <= 0:
            return np.zeros_like(rho)
        core = beta * (rho / delta) ** eps
        decay = np.exp(-self.gamma * q * rho)
        uv = 1.0 + (q * rho) ** self.kappa
        return core * decay / uv

    def threshold_eps(self, delta: float, q: int, rho: float, beta: float) -> float:
        """
        Solve A_n(rho; eps, beta) = 1 for eps analytically:
            eps = [log(1/(beta*decay/uv))] / log(rho/delta)
        Returns float('inf') if rho <= delta (no threshold).
        """
        if rho <= delta or rho <= 0 or delta <= 0:
            return float("inf")
        decay = np.exp(-self.gamma * q * rho)
        uv = 1.0 + (q * rho) ** self.kappa
        if decay <= 0 or uv <= 0:
            return float("inf")
        rhs = 1.0 / (beta * decay / uv)
        if rhs <= 0:
            return float("inf")
        log_ratio = np.log(rho / delta)
        if log_ratio <= 0:
            return float("inf")
        return np.log(rhs) / log_ratio

    def threshold_beta(self, delta: float, q: int, rho: float, eps: float) -> float:
        """
        Solve A_n(rho; eps, beta) = 1 for beta analytically:
            beta = (delta/rho)^eps * uv / decay
        """
        if delta <= 0 or rho <= 0:
            return float("inf")
        decay = np.exp(-self.gamma * q * rho)
        uv = 1.0 + (q * rho) ** self.kappa
        if decay <= 0:
            return float("inf")
        return (delta / rho) ** eps * uv / decay


# ---------------------------------------------------------------------------
# 3. Spike survey: build amplitude surface
# ---------------------------------------------------------------------------

@dataclass
class SpikeSurvey:
    """Full resonance spike survey across all convergents and rho values."""
    rho_arr: np.ndarray
    convs: List[Convergent]
    eps: float
    beta: float
    model: ResonanceModel
    surface: np.ndarray = field(init=False)   # shape (N_convs, N_rho)
    peak_rho: np.ndarray = field(init=False)  # argmax rho per convergent
    peak_amp: np.ndarray = field(init=False)  # max amplitude per convergent

    def __post_init__(self) -> None:
        N_c = len(self.convs)
        N_r = len(self.rho_arr)
        self.surface = np.zeros((N_c, N_r))
        self.peak_rho = np.zeros(N_c)
        self.peak_amp = np.zeros(N_c)

        for i, c in enumerate(self.convs):
            if c.delta <= 0:
                continue
            row = self.model.amplitude(
                c.delta, c.q, self.rho_arr, self.eps, self.beta
            )
            self.surface[i] = row
            idx = int(np.argmax(row))
            self.peak_rho[i] = self.rho_arr[idx]
            self.peak_amp[i] = row[idx]

    def threshold_eps_surface(self, rho: float) -> np.ndarray:
        """eps threshold for each convergent at a fixed rho."""
        return np.array([
            self.model.threshold_eps(c.delta, c.q, rho, self.beta)
            for c in self.convs
        ])

    def threshold_beta_surface(self, rho: float) -> np.ndarray:
        """beta threshold for each convergent at a fixed rho."""
        return np.array([
            self.model.threshold_beta(c.delta, c.q, rho, self.eps)
            for c in self.convs
        ])


# ---------------------------------------------------------------------------
# 4. CLI argument parsing
# ---------------------------------------------------------------------------

def parse_cf(s: str) -> List[int]:
    """Parse '[a0; a1, a2, ...]' or 'a0,a1,a2,...'."""
    s = s.strip()
    if s.startswith("[") and s.endswith("]"):
        s = s[1:-1]
    parts = [x.strip() for x in s.replace(";", ",").split(",")]
    return [int(x) for x in parts if x]


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        description="Non-Commutative Torus Resonance Spike Simulator"
    )
    p.add_argument("--cf", required=True,
                   help="Continued fraction '[a0; a1, ...]'")
    p.add_argument("--eps", type=float, default=1.0,
                   help="Holder exponent eps (default 1.0)")
    p.add_argument("--beta", type=float, default=0.1,
                   help="Coupling amplitude beta (default 0.1)")
    p.add_argument("--C", type=float, default=0.25,
                   help="Diophantine constant C (default 0.25)")
    p.add_argument("--mu", type=float, default=2.0,
                   help="Diophantine exponent mu (default 2.0)")
    p.add_argument("--gamma", type=float, default=0.15,
                   help="Localization strength gamma (default 0.15)")
    p.add_argument("--kappa", type=float, default=1.5,
                   help="UV regularisation kappa (default 1.5)")
    p.add_argument("--rho-min", type=float, default=1e-4,
                   help="Min basin radius rho")
    p.add_argument("--rho-max", type=float, default=2.0,
                   help="Max basin radius rho")
    p.add_argument("--rho-pts", type=int, default=512,
                   help="Number of rho grid points")
    p.add_argument("--out", default="resonance_report.pdf",
                   help="Output PDF path")
    p.add_argument("--list-convs", action="store_true",
                   help="Print convergent table to stdout")
    p.add_argument("--sweep-eps", nargs=3, type=float, metavar=("MIN", "MAX", "N"),
                   help="Sweep eps over [MIN,MAX] with N steps")
    p.add_argument("--sweep-beta", nargs=3, type=float, metavar=("MIN", "MAX", "N"),
                   help="Sweep beta over [MIN,MAX] with N steps")
    return p


# ---------------------------------------------------------------------------
# 5. Reporting & visualisation
# ---------------------------------------------------------------------------

def fig_convergents(convs: List[Convergent], alpha: float) -> plt.Figure:
    fig, axes = plt.subplots(2, 2, figsize=(12, 8))
    fig.suptitle(f"Convergents: alpha = {alpha:.8f}", fontsize=13)

    qs = [c.q for c in convs]
    deltas = [c.delta for c in convs]
    bounds = [c.bound_C_mu for c in convs]
    ns = [c.n for c in convs]

    ax = axes[0, 0]
    ax.semilogy(ns, deltas, "o-", label="|alpha - p/q|")
    ax.semilogy(ns, bounds, "s--", label="C/q^mu bound")
    ax.set_xlabel("Convergent index n")
    ax.set_ylabel("|alpha - p_n/q_n|")
    ax.set_title("Diophantine approximation quality")
    ax.legend()
    ax.grid(True, alpha=0.3)

    ax = axes[0, 1]
    ax.semilogy(ns, qs, "o-", color="tab:orange")
    ax.set_xlabel("n")
    ax.set_ylabel("q_n")
    ax.set_title("Denominator growth")
    ax.grid(True, alpha=0.3)

    ax = axes[1, 0]
    if len(qs) > 1:
        log_qs = np.log(qs[1:])
        log_qs_prev = np.log(qs[:-1])
        ratios = np.diff(np.log(qs))
        ax.plot(ns[1:], ratios, "o-", color="tab:green")
        ax.set_title("log(q_{n+1}) - log(q_n)  [denominator growth rate]")
    ax.set_xlabel("n")
    ax.grid(True, alpha=0.3)

    ax = axes[1, 1]
    partial_quotients = [c.a for c in convs]
    ax.bar(ns, partial_quotients, color="tab:purple", alpha=0.7)
    ax.set_xlabel("n")
    ax.set_ylabel("a_n")
    ax.set_title("Partial quotients")
    ax.grid(True, alpha=0.3)

    fig.tight_layout()
    return fig


def fig_amplitude_surface(survey: SpikeSurvey) -> plt.Figure:
    fig = plt.figure(figsize=(14, 9))
    gs = GridSpec(2, 3, figure=fig, hspace=0.4, wspace=0.35)

    ax_surf = fig.add_subplot(gs[0, :])
    im = ax_surf.pcolormesh(
        survey.rho_arr,
        np.arange(len(survey.convs)),
        survey.surface,
        cmap="plasma", shading="auto"
    )
    fig.colorbar(im, ax=ax_surf, label="Amplitude A_n(rho)")
    ax_surf.set_xlabel("rho (basin radius)")
    ax_surf.set_ylabel("Convergent index n")
    ax_surf.set_title(
        f"Resonance amplitude surface  (eps={survey.eps:.2f}, beta={survey.beta:.3f})"
    )

    ax_peak = fig.add_subplot(gs[1, 0])
    ax_peak.semilogy(
        np.arange(len(survey.convs)), survey.peak_amp, "o-", color="tab:red"
    )
    ax_peak.set_xlabel("n")
    ax_peak.set_ylabel("Peak A_n")
    ax_peak.set_title("Peak amplitude per convergent")
    ax_peak.grid(True, alpha=0.3)

    ax_rho = fig.add_subplot(gs[1, 1])
    ax_rho.plot(
        np.arange(len(survey.convs)), survey.peak_rho, "s-", color="tab:blue"
    )
    ax_rho.set_xlabel("n")
    ax_rho.set_ylabel("rho at peak")
    ax_rho.set_title("Basin radius at peak spike")
    ax_rho.grid(True, alpha=0.3)

    ax_cuts = fig.add_subplot(gs[1, 2])
    for i, c in enumerate(survey.convs[::max(1, len(survey.convs)//5)]):
        ax_cuts.plot(
            survey.rho_arr, survey.surface[i],
            label=f"n={c.n}, q={c.q}"
        )
    ax_cuts.set_xlabel("rho")
    ax_cuts.set_ylabel("Amplitude")
    ax_cuts.set_title("Selected rho slices")
    ax_cuts.legend(fontsize=7)
    ax_cuts.grid(True, alpha=0.3)

    return fig


def fig_threshold_analysis(survey: SpikeSurvey, rho_probe: float) -> plt.Figure:
    fig, axes = plt.subplots(1, 2, figsize=(12, 5))
    fig.suptitle(f"Threshold analysis at rho = {rho_probe:.3f}", fontsize=13)

    ns = np.arange(len(survey.convs))

    eps_thresh = survey.threshold_eps_surface(rho_probe)
    finite_mask = np.isfinite(eps_thresh)
    ax = axes[0]
    if finite_mask.any():
        ax.plot(ns[finite_mask], eps_thresh[finite_mask], "o-", color="tab:green")
    ax.axhline(survey.eps, color="red", linestyle="--", label=f"current eps={survey.eps:.2f}")
    ax.set_xlabel("Convergent index n")
    ax.set_ylabel("epsilon threshold")
    ax.set_title("Threshold epsilon  (amplitude = 1)")
    ax.legend()
    ax.grid(True, alpha=0.3)

    beta_thresh = survey.threshold_beta_surface(rho_probe)
    finite_mask = np.isfinite(beta_thresh)
    ax = axes[1]
    if finite_mask.any():
        ax.semilogy(ns[finite_mask], beta_thresh[finite_mask], "s-", color="tab:orange")
    ax.axhline(survey.beta, color="red", linestyle="--", label=f"current beta={survey.beta:.3f}")
    ax.set_xlabel("Convergent index n")
    ax.set_ylabel("beta threshold")
    ax.set_title("Threshold beta  (amplitude = 1)")
    ax.legend()
    ax.grid(True, alpha=0.3)

    fig.tight_layout()
    return fig


def fig_parameter_sweep(
    convs: List[Convergent],
    model: ResonanceModel,
    rho_arr: np.ndarray,
    param_name: str,
    param_vals: np.ndarray,
    eps: float,
    beta: float
) -> plt.Figure:
    """Sweep one of eps/beta and show max peak amplitude vs parameter."""
    peak_amps = []
    for val in param_vals:
        e = val if param_name == "eps" else eps
        b = val if param_name == "beta" else beta
        survey = SpikeSurvey(rho_arr, convs, e, b, model)
        peak_amps.append(float(np.max(survey.peak_amp)))

    fig, ax = plt.subplots(figsize=(8, 5))
    ax.semilogy(param_vals, peak_amps, "o-")
    ax.set_xlabel(param_name)
    ax.set_ylabel("Global peak amplitude")
    ax.set_title(f"Peak amplitude vs {param_name} sweep")
    ax.grid(True, alpha=0.3)
    fig.tight_layout()
    return fig


def print_convergent_table(convs: List[Convergent], alpha: float) -> None:
    hdr = (
        f"{'n':>4} {'a_n':>6} {'p_n':>12} {'q_n':>12} "
        f"{'p/q':>14} {'alpha-p/q':>14} {'C/q^mu':>12}"
    )
    print(f"\nalpha = {alpha:.12f}")
    print(hdr)
    print("-" * len(hdr))
    for c in convs:
        print(
            f"{c.n:>4} {c.a:>6} {c.p:>12} {c.q:>12} "
            f"{c.alpha_approx:>14.9f} {c.signed_delta:>14.4e} {c.bound_C_mu:>12.4e}"
        )


# ---------------------------------------------------------------------------
# 6. Main entry point
# ---------------------------------------------------------------------------

def main() -> None:
    parser = build_parser()
    args = parser.parse_args()

    cf = parse_cf(args.cf)
    alpha = continued_fraction_value(cf)
    convs = compute_convergents(cf, alpha)
    fill_diophantine_bounds(convs, args.C, args.mu)

    if args.list_convs:
        print_convergent_table(convs, alpha)

    rho_arr = np.linspace(args.rho_min, args.rho_max, args.rho_pts)

    model = ResonanceModel(
        gamma=args.gamma,
        kappa=args.kappa,
        C=args.C,
        mu=args.mu,
    )

    survey = SpikeSurvey(rho_arr, convs, args.eps, args.beta, model)

    rho_probe = float(rho_arr[len(rho_arr) // 3])

    out_path = Path(args.out)
    with PdfPages(out_path) as pdf:
        print(f"[NCT-SIM] Generating report -> {out_path}")

        fig = fig_convergents(convs, alpha)
        pdf.savefig(fig)
        plt.close(fig)

        fig = fig_amplitude_surface(survey)
        pdf.savefig(fig)
        plt.close(fig)

        fig = fig_threshold_analysis(survey, rho_probe)
        pdf.savefig(fig)
        plt.close(fig)

        if args.sweep_eps:
            lo, hi, n = args.sweep_eps
            vals = np.linspace(lo, hi, int(n))
            fig = fig_parameter_sweep(
                convs, model, rho_arr, "eps", vals, args.eps, args.beta
            )
            pdf.savefig(fig)
            plt.close(fig)

        if args.sweep_beta:
            lo, hi, n = args.sweep_beta
            vals = np.linspace(lo, hi, int(n))
            fig = fig_parameter_sweep(
                convs, model, rho_arr, "beta", vals, args.eps, args.beta
            )
            pdf.savefig(fig)
            plt.close(fig)

        d = pdf.infodict()
        d["Title"] = "NCT Resonance Spike Report"
        d["Author"] = "nct_resonance_simulator.py"
        d["Subject"] = (
            f"alpha=[{','.join(str(a) for a in cf)}], "
            f"eps={args.eps}, beta={args.beta}"
        )

    print(f"[NCT-SIM] Done. Report saved to {out_path}")

    max_n = int(np.argmax(survey.peak_amp))
    print(
        f"[NCT-SIM] Worst convergent: n={max_n}, "
        f"q={convs[max_n].q}, peak_amp={survey.peak_amp[max_n]:.4f}, "
        f"at rho={survey.peak_rho[max_n]:.4f}"
    )


if __name__ == "__main__":
    main()
