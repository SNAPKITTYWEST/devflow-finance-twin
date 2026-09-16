module FPGA_API
using Sockets, JSON

const FPGA_HOST = get(ENV, "FPGA_HOST", "127.0.0.1")
const FPGA_PORT = parse(Int, get(ENV, "FPGA_PORT", "9001"))

function send_command(cmd::Dict)
    sock = connect(FPGA_HOST, FPGA_PORT)
    write(sock, JSON.json(cmd) * "\n")
    flush(sock)
    resp = readline(sock)
    close(sock)
    return JSON.parse(resp)
end

function load_pulse_table(csv_path::String)
    return send_command(Dict("cmd"=>"load_pulse_table", "path"=>csv_path))
end

function set_dds_register(reg::Int, value::Int)
    return send_command(Dict("cmd"=>"set_dds", "reg"=>reg, "value"=>value))
end

function trigger_sequence(seq_id::String)
    return send_command(Dict("cmd"=>"trigger", "seq"=>seq_id))
end

end # module
