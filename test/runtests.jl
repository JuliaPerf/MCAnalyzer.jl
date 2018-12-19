using MCAnalyzer
using Test
using InteractiveUtils

f() = mark_start()
g() = mark_end()

buf = IOBuffer()
code_native(buf, f, Tuple{})
asm = String(take!(buf))
@test occursin("movl\t\$111, %ebx", asm)
buf = IOBuffer()
code_native(buf, g, Tuple{})
asm = String(take!(buf))
@test occursin("movl\t\$222, %ebx", asm)

function mysum(A)
    acc = zero(eltype(A))
    for i in eachindex(A)
        mark_start()
        @inbounds acc += A[i]
    end
    mark_end()
    return acc
end
code_native(buf, mysum, Tuple{Vector{Float64}})
asm = String(take!(buf))
@test occursin("movl\t\$111, %ebx", asm)
@test occursin("movl\t\$222, %ebx", asm)

@test_nowarn analyze(mysum, Tuple{Vector{Float64}})

using LinearAlgebra

function mynorm(out, X)
    for i in 1:length(X)
        @inbounds out[i] = X[i] / norm(X)
    end
    out
end

fname, io = mktemp()
@test_nowarn MCAnalyzer.code_llvm(io, mynorm, Tuple{Vector{Float64}, Vector{Float64}})
close(io)
rm(fname)
