# jung_rwpt_sim.jl — combined RWPT-like symbol generation with Bayesian integration updates
using Random, Statistics, Plots

N_agents    = 50
M_archetypes = 4
T            = 200
rng          = MersenneTwister(123)

p = rand(rng, N_agents, M_archetypes) .* 0.1

q1 = 0.8   # P(symbol | integrated)
q0 = 0.05  # P(symbol | not integrated)

function bayes_update(p_prior, s, q1, q0)
    num = p_prior * (s ? q1 : (1 - q1))
    den = num + (1 - p_prior) * (s ? q0 : (1 - q0))
    den == 0 ? p_prior : num / den
end

function sample_symbol_events(N_agents, M_archetypes, T; rng=Random.GLOBAL_RNG)
    events = falses(N_agents, M_archetypes, T)
    for a in 1:N_agents, α in 1:M_archetypes
        base = 0.02
        t = 1
        while t <= T
            if rand(rng) < 0.005
                for dt in 0:5
                    if t+dt <= T && rand(rng) < 0.8; events[a,α,t+dt] = true; end
                end
            else
                events[a,α,t] = rand(rng) < base
            end
            t += 1
        end
    end
    return events
end

events  = sample_symbol_events(N_agents, M_archetypes, T; rng=rng)
p_traj  = zeros(N_agents, M_archetypes, T)
p_traj[:,:,1] = p

for t in 1:T-1, a in 1:N_agents, α in 1:M_archetypes
    s = events[a,α,t]
    p[a,α] = bayes_update(p[a,α], s, q1, q0)
    p_traj[a,α,t+1] = p[a,α]
end

mean_p = [mean(p_traj[:,:,t]) for t in 1:T]
plot(1:T, mean_p, xlabel="Time", ylabel="Mean integration probability",
     title="Combined RWPT-Jung simulation")
savefig("outputs/combined_integration.png")
println("Saved outputs/combined_integration.png")
