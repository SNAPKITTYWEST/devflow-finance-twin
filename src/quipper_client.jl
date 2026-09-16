# quipper_client.jl — minimal TCP listener for Quipper measurement bits with EMA update
using Sockets, JSON

p = 0.1  # initial belief

function handle_bits(bits)
    return bits[1]
end

function run_client(host::String="127.0.0.1", port::Int=9001)
    server = listen(host, port)
    println("Listening on $host:$port")
    while true
        sock = accept(server)
        @async begin
            try
                while !eof(sock)
                    line = readline(sock)
                    isempty(strip(line)) && continue
                    msg   = JSON.parse(line)
                    trial = msg["trial"]
                    bits  = msg["bits"]
                    println("Received trial $trial bits: $bits")
                    s     = handle_bits([Int(b) for b in bits])
                    m_t   = s
                    eta   = 0.1
                    q1    = 0.8; q0 = 0.05
                    global p
                    p = clamp(p + eta * (m_t - p), 0.0, 1.0)
                    println("Updated p = $p")
                end
            catch e; @warn "Client handler error: $e"
            finally; close(sock); end
        end
    end
end

if abspath(PROGRAM_FILE) == @__FILE__; run_client(); end
