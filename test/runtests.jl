using IACA
using Base.Test

f() = iaca_start()
g() = iaca_end()

buf = IOBuffer()
code_native(buf, f, Tuple{})
asm = String(take!(buf))
@test contains(asm, "movl\t\$111, %ebx")
buf = IOBuffer()
code_native(buf, g, Tuple{})
asm = String(take!(buf))
@test contains(asm, "movl\t\$222, %ebx")

function mysum(A)
    acc = zero(eltype(A))
    for a in A
        iaca_start()
        acc += a
    end
    iaca_end()
    return acc
end
code_native(buf, mysum, Tuple{Vector{Float64}})
asm = String(take!(buf))
@test contains(asm, "movl\t\$111, %ebx")
@test contains(asm, "movl\t\$222, %ebx")
