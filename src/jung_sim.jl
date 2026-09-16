# jung_sim.jl — deterministic Jungian integration simulation (EMA dynamics)
using Random, Statistics, Plots

const N_agents    = 50
const M_archetypes = 6
const T           = 200
const eta         = 0.1
rng               = MersenneTwister(42)

p0 = rand(rng, N_agents, M_archetypes) .* 0.2
m  = zeros(N_agents, M_archetypes, T)

for a in 1:N_agents, t in 20:80
    if a <= N_agents ÷ 2; m[a,1,t] = 0.9; end
end
for a in 1:N_agents, α in 1:M_archetypes, t in 1:T
    m[a,α,t] = max(m[a,α,t], rand(rng) * 0.05)
end

p = zeros(N_agents, M_archetypes, T)
p[:,:,1] = p0
for t in 1:T-1, a in 1:N_agents, α in 1:M_archetypes
    p[a,α,t+1] = clamp(p[a,α,t] + eta * (m[a,α,t] - p[a,α,t]), 0.0, 1.0)
end

weights   = ones(M_archetypes) ./ M_archetypes
wholeness = [dot(weights, p[a,:,t]) for a in 1:N_agents, t in 1:T]

mean_wholeness = mean(wholeness, dims=1)[:]
std_wholeness  = std(wholeness, dims=1)[:]

plot(1:T, mean_wholeness, ribbon=std_wholeness, xlabel="Time", ylabel="Mean wholeness",
     title="Wholeness trajectory (intervention on archetype 1)")
savefig("outputs/wholeness_trajectory.png")
println("Saved outputs/wholeness_trajectory.png")
println("Pre-intervention mean:  ", round(mean(mean_wholeness[1:19]), digits=4))
println("Post-intervention mean: ", round(mean(mean_wholeness[81:120]), digits=4))
