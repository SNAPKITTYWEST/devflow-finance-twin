module FutharkFFI
using Libdl

const libpath = joinpath(@__DIR__, "..", "futhark", "libwigner.so")
const lib = Libdl.dlopen(libpath)

function wigner_transform(rho_re::Vector{Float64}, rho_im::Vector{Float64}, n::Int, m::Int)
    out = Vector{Float64}(undef, m*m)
    ccall((:futhark_entry_wigner_transform, lib), Cvoid,
          (Cint, Cint, Ptr{Float64}, Ptr{Float64}, Ptr{Float64}),
          n, m, rho_re, rho_im, out)
    return out
end

end # module
