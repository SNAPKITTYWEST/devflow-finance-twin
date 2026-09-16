module RWPT

using QuantumOptics
using LinearAlgebra
using Libdl
using Random
using Plots

include("FutharkFFI.jl")
include("FPGAMock.jl")

export run_ensemble, propagate_step, jump_update, init_system

const N    = 12
const g    = 1.0
const κ    = 0.2
const γ    = 0.05
const ωc   = 0.0
const ωa   = 0.0
const drive = 0.5

const hc   = FockBasis(N)
const ha   = SpinBasis(1//2)
const a    = tensor(destroy(hc), identity(ha))
const sm   = tensor(identity(hc), sigmam(ha))
const n_op = dagger(a)*a

function init_system()
    H  = ωc*dagger(a)*a + ωa*dagger(sm)*sm + g*(dagger(a)*sm + a*dagger(sm)) + drive*(a + dagger(a))
    Ls = [sqrt(κ)*a, sqrt(γ)*sm]
    ψ0 = tensor(fockstate(hc,0), spinup(ha))
    ρ0 = ket2dm(ψ0)
    return (H, Ls, ρ0)
end

function propagate_step(ρ, H, Ls, dt)
    L = -1im*(H*ρ - ρ*H)
    for Lc in Ls
        L += Lc*ρ*dagger(Lc) - 0.5*(dagger(Lc)*Lc*ρ + ρ*dagger(Lc)*Lc)
    end
    return ρ + dt * L
end

function jump_update(ρ, L)
    num   = L * ρ * dagger(L)
    denom = real(tr(dagger(L)*L*ρ))
    if denom == 0; return num; else return num / denom; end
end

function run_ensemble(ntraj::Int=200; t_final=10.0, dt=0.01)
    H, Ls, ρ0 = init_system()
    n_steps = Int(round(t_final/dt))
    all_n   = zeros(ntraj, n_steps)
    for k in 1:ntraj
        ρ = deepcopy(ρ0)
        for i in 1:n_steps
            ρ_pred    = propagate_step(ρ, H, Ls, dt)
            rates     = [real(expect(dagger(L)*L, ρ_pred)) for L in Ls]
            total_rate = sum(rates)
            p_jump    = 1 - exp(-total_rate * dt)
            if rand() < p_jump && total_rate > 0
                r = rand() * total_rate; acc = 0.0; chosen = 1
                for (j, rate) in enumerate(rates)
                    acc += rate
                    if r <= acc; chosen = j; break; end
                end
                ρ = jump_update(ρ_pred, Ls[chosen])
            else
                ρ = ρ_pred / real(tr(ρ_pred))
            end
            all_n[k, i] = real(expect(n_op, ρ))
        end
    end
    return all_n
end

end # module
