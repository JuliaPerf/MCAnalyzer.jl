using IACA
using Test
using InteractiveUtils

f() = iaca_start()
g() = iaca_end()

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
    iaca_start()
    for a in A
        acc += a
    end
    iaca_end()
    return acc
end
code_native(buf, mysum, Tuple{Vector{Float64}})
asm = String(take!(buf))
@test occursin("movl\t\$111, %ebx", asm)
@test occursin("movl\t\$222, %ebx", asm)

@test_nowarn analyze(mysum, Tuple{Vector{Float64}})
