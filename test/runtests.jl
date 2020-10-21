using MCAnalyzer
using Test

import MCAnalyzer: code_native, code_llvm

f() = mark_start()
g() = mark_end()

let buf = IOBuffer()
    code_native(buf, f, Tuple{})
    asm = String(take!(buf))
    @test occursin("movl\t\$111, %ebx", asm)
end

let buf = IOBuffer()
    code_native(buf, g, Tuple{})
    asm = String(take!(buf))
    @test occursin("movl\t\$222, %ebx", asm)
end

function mysum(A)
    acc = zero(eltype(A))
    for i in eachindex(A)
        mark_start()
        @inbounds acc += A[i]
    end
    mark_end()
    return acc
end

let buf = IOBuffer()
    code_native(buf, mysum, Tuple{Vector{Float64}})
    asm = String(take!(buf))
    @test occursin("movl\t\$111, %ebx", asm)
    @test occursin("movl\t\$222, %ebx", asm)
end

if Sys.which("iaca") !== nothing
    @test_nowarn analyze(mysum, (Vector{Float64},))
end

using LinearAlgebra

function mynorm(out, X)
    for i in 1:length(X)
        @inbounds out[i] = X[i] / norm(X)
    end
    out
end

fname, io = mktemp()
@test_nowarn code_llvm(io, mynorm, (Vector{Float64}, Vector{Float64}))
close(io)
rm(fname)
