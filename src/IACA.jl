__precompile__(true)
module IACA
export iaca_start, iaca_end, analyze

using LLVM
import Compat: @nospecialize

const jlctx = Ref{LLVM.Context}()

function __init__()
    jlctx[] = LLVM.Context(convert(LLVM.API.LLVMContextRef,
                                   cglobal(:jl_LLVMContext, Void)))

end

"""
    write_objectfile(mod, path)

Writes a LLVM module as a objectfile to the given `path`.
"""
function write_objectfile(mod::LLVM.Module, path::String)
    host_triple = LLVM.triple()
    host_t = LLVM.Target(host_triple)
    LLVM.TargetMachine(host_t, host_triple) do tm
        LLVM.emit(tm, mod, LLVM.API.LLVMObjectFile, path)
    end
end

"""
    analyze(func, tt)

Analyze a given function `func` with the type signature `tt`.
The specific method needs to be annotated with the `IACA` markers.

# Example

```julia
function mysum(A)
    acc = zero(eltype(A))
    for a in A
        iaca_start()
        acc += a
    end
    iaca_end()
    return acc
end

analyze(mysum, Tuple{Vector{Float64}})
````
"""
function analyze(@nospecialize(func), @nospecialize(tt))
    mod = parse(LLVM.Module,
                Base._dump_function(func, tt,
                                    #=native=#false, #=wrapper=#false, #=strip=#false,
                                    #=dump_module=#true, #=syntax=#:att, #=optimize=#true), jlctx[])

    iaca_path = "iaca"
    if haskey(ENV, "IACA_PATH")
        iaca_path = ENV["IACA_PATH"]
    end

    # TODO: pickup arch host, and allow to set target specifically so that we can test other arch
    arch = "SKL"
    mktempdir() do dir
        objfile = joinpath(dir, "temp.o") 
        path = write_objectfile(mod, objfile)
        Base.run(`$iaca_path -arch $arch $objfile`)
    end
end

function gen_iaca(code, name)
    mod = LLVM.Module("IACA", jlctx[])
    ft = LLVM.FunctionType(LLVM.VoidType(jlctx[]))
    # ATT syntax target comes last
    raw_asm = """
        movl \$\$$code, %ebx
        .byte 0x64, 0x67, 0x90
        """
    # defined in iacaMarks.h as volatile with a memory clobber
    # dirflag, fpsr, flags are taken from clang
    asm = InlineAsm(ft, raw_asm, #=constraints=# "~{memory},~{dirflag},~{fpsr},~{flags}", #=side-effects=# true )
    llvmf = LLVM.Function(mod, "iaca_$name", ft)

    Builder(jlctx[]) do builder
        entry = BasicBlock(llvmf, "entry", jlctx[])
        position!(builder, entry)

        # insert call to asm
        call!(builder, asm)
        ret!(builder)
    end
    push!(function_attributes(llvmf), EnumAttribute("alwaysinline"))

    return llvmf
end

"""
    iaca_start()

Insertes IACA start marker at this position.
"""
@generated function iaca_start()
    llvmf = gen_iaca("111", "start")
    quote
        Base.@_inline_meta
        Base.llvmcall(LLVM.ref($llvmf), Void, Tuple{})
        return nothing
    end
end

"""
    iaca_end()

Insertes IACA end marker at this position.
"""
@generated function iaca_end()
    llvmf = gen_iaca("222", "end")
    quote
        Base.@_inline_meta
        Base.llvmcall(LLVM.ref($llvmf), Void, Tuple{})
        return nothing
    end
end

end # module
