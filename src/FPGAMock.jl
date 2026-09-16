module FPGAMock
export send_pulse_table, apply_control

function send_pulse_table(csv_path::String)
    println("FPGA mock: loading pulse table from ", csv_path)
    return true
end

function apply_control(cmd::Dict)
    println("FPGA mock: apply control ", cmd)
    return true
end

end # module
