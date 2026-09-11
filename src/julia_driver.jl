# julia_driver.jl
# TCP server: receives Quipper measurement bits, applies EMA update per archetype,
# records belief trajectories to CSV, and plots on shutdown.
#
# Usage:
#   julia --project=. julia_driver.jl [--host 127.0.0.1] [--port 9001] [--eta 0.1] [--symbols symbols.json]

using Sockets, JSON, CSV, DataFrames, Statistics
try; using Plots; global has_plots = true; catch; @warn "Plots.jl not available"; global has_plots = false; end

const DEFAULT_HOST       = "127.0.0.1"
const DEFAULT_PORT       = 9001
const DEFAULT_ETA        = 0.1
const DEFAULT_ARCHETYPES = ["mandala","tower","stone","sun","star","dream","snake","chalice",
                             "fire","anima_mundi","alchemy","light_dark","gates","room","opposites"]

function parse_args()
    host = DEFAULT_HOST; port = DEFAULT_PORT; eta = DEFAULT_ETA; archetypes = DEFAULT_ARCHETYPES
    i = 1
    while i <= length(ARGS)
        arg = ARGS[i]
        if     arg == "--host"    && i+1 <= length(ARGS); host       = ARGS[i+1]; i += 2
        elseif arg == "--port"    && i+1 <= length(ARGS); port       = parse(Int,     ARGS[i+1]); i += 2
        elseif arg == "--eta"     && i+1 <= length(ARGS); eta        = parse(Float64, ARGS[i+1]); i += 2
        elseif arg == "--symbols" && i+1 <= length(ARGS)
            archetypes = JSON.parse(read(ARGS[i+1], String)); i += 2
        else; println("Unknown arg: $arg"); i += 1
        end
    end
    return host, port, eta, archetypes
end

clamp01(x) = x < 0 ? 0.0 : x > 1 ? 1.0 : x

function bits_to_evidence(bits::Vector{Int}, n::Int)
    m = zeros(Float64, n)
    for i in 1:min(n, length(bits)); m[i] = bits[i] == 1 ? 1.0 : 0.0; end
    return m
end

function ema_update!(p::Vector{Float64}, m::Vector{Float64}, eta::Float64)
    for i in eachindex(p); p[i] = clamp01(p[i] + eta * (m[i] - p[i])); end
end

mutable struct Recorder
    trials::Vector{Int}
    timestamps::Vector{Float64}
    beliefs::Vector{Vector{Float64}}
    events::Vector{Vector{Int}}
end
Recorder() = Recorder(Int[], Float64[], Vector{Vector{Float64}}(), Vector{Vector{Int}}())

function record!(rec::Recorder, trial::Int, p::Vector{Float64}, bits::Vector{Int})
    push!(rec.trials, trial); push!(rec.timestamps, time())
    push!(rec.beliefs, copy(p)); push!(rec.events, copy(bits))
end

function dump_csv(rec::Recorder, archetypes::Vector{String}, outpath::String="beliefs.csv")
    n = length(archetypes)
    rows = []
    for (i, t) in enumerate(rec.trials)
        row = Dict{String,Any}("trial"=>t, "timestamp"=>rec.timestamps[i],
                               "bits"=>join(rec.events[i],";"))
        for j in 1:n; row[archetypes[j]] = rec.beliefs[i][j]; end
        push!(rows, row)
    end
    CSV.write(outpath, DataFrame(rows))
    println("Wrote CSV to $outpath")
end

function plot_trajectories(rec::Recorder, archetypes::Vector{String}; outpath="beliefs_plot.png")
    !has_plots && return
    T = length(rec.trials); n = length(archetypes)
    plt = plot(title="Belief trajectories", xlabel="trial", ylabel="belief", legend=:outerright)
    for j in 1:n
        vals = [rec.beliefs[i][j] for i in 1:T]
        plot!(plt, 1:T, vals, label=archetypes[j])
    end
    savefig(plt, outpath); println("Saved plot to $outpath")
end

function run_server(host::String, port::Int, eta::Float64, archetypes::Vector{String})
    n = length(archetypes)
    p = fill(0.1, n)
    rec = Recorder()
    server = listen(host, port)
    println("Listening on $host:$port")
    try
        while true
            sock = accept(server)
            @async begin
                try
                    while !eof(sock)
                        line = readline(sock)
                        isempty(strip(line)) && continue
                        try
                            msg   = JSON.parse(line)
                            trial = haskey(msg,"trial") ? Int(msg["trial"]) : -1
                            bits  = [Int(b) for b in get(msg,"bits",[])]
                            m_vec = bits_to_evidence(bits, n)
                            ema_update!(p, m_vec, eta)
                            record!(rec, trial, p, bits)
                            println("trial=$(trial) bits=$(bits) p=$(round.(p, digits=4))")
                        catch e; @warn "Parse error: $e"; end
                    end
                catch e; @warn "Connection error: $e"
                finally; close(sock); println("Connection closed.")
                end
            end
        end
    finally
        close(server)
        dump_csv(rec, archetypes)
        plot_trajectories(rec, archetypes)
    end
end

function main()
    host, port, eta, archetypes = parse_args()
    println("Julia driver: host=$host port=$port eta=$eta archetypes=$(length(archetypes))")
    run_server(host, port, eta, archetypes)
end

if abspath(PROGRAM_FILE) == @__FILE__; main(); end
