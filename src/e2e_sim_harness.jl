# e2e_sim_harness.jl — end-to-end RWPT simulation with FPGA mock and Allan deviation output
using RWPT, FPGAMock, Plots, Statistics

FPGAMock.send_pulse_table("pulse_table.csv")

ntraj   = 200
t_final = 10.0
dt      = 0.01

println("Running ensemble RWPT simulation...")
all_n = RWPT.run_ensemble(ntraj; t_final=t_final, dt=dt)

mean_n  = mean(all_n, dims=1)
times   = collect(0:dt:t_final-dt)

k_gain  = 1e-3
freq_err = k_gain .* (vec(mean_n) .- mean(vec(mean_n)))

function allan_dev(x, dt, tau)
    m = Int(round(tau/dt))
    if m < 1; return NaN; end
    nseg = div(length(x), m)
    if nseg < 2; return NaN; end
    means = [mean(x[(i-1)*m+1:i*m]) for i in 1:nseg]
    return sqrt(0.5 * mean(diff(means).^2))
end

taus = [dt * 2^k for k in 0:floor(Int, log2(length(times)/4))]
adev = [allan_dev(freq_err, dt, τ) for τ in taus]

p1 = plot(times, freq_err, xlabel="t (s)", ylabel="freq error (arb)",
          title="Mock LO frequency error (convergence)")
savefig("lock_convergence.png")
println("Saved lock_convergence.png")

p2 = plot(taus, adev, xscale=:log10, yscale=:log10, marker=:o,
          xlabel="tau (s)", ylabel="Allan dev", title="Allan deviation (mock)")
savefig("allan_dev.png")
println("Saved allan_dev.png")
println("E2E simulation complete.")
