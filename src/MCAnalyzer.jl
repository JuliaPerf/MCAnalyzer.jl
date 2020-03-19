module MCAnalyzer
export mark_start, mark_end, analyze

using LLVM
using LLVM.Interop

# import LLVM_jll: llvm_mca
function llvm_mca(f)
    if Sys.iswindows()
        SUFFIX=".exe"
    else
        SUFFIX=""
    end
    llvm_mca_path = joinpath(Sys.BINDIR, "..", "tools", "llvm-mca$(SUFFIX)")
    f(llvm_mca_path)
end

function __init__()
    @assert LLVM.InitializeNativeTarget() == false
end

include("irgen.jl")

"""
    analyze(func, tt, march = :SKL)

Analyze a given function `func` with the type signature `tt`.
The specific method needs to be annotated with the `IACA` markers.
Supported `march` are :HSW, :BDW, :SKL, and :SKX.

# Example

```julia
function mysum(A)
    acc = zero(eltype(A))
    for i in eachindex(A)
        mark_start()
        @inbounds acc += A[i]
    end
    mark_end()
    return acc
end

analyze(mysum, Tuple{Vector{Float64}})
```

# Advanced usage
## Switching opt-level

```julia
analyze(mysum, Tuple{Vector{Float64}}, march = :SKL, opt_level=3)
```

## Changing the optimization pipeline

```julia
myoptimize!(tm, mod) = ...
analyze(mysum, Tuple{Vector{Float64}}, myoptimize!)
```

"""
function analyze(@nospecialize(func), @nospecialize(tt), optimize!::Core.Function = jloptimize!;
                 march=:SKL, optlevel=Base.JLOptions().opt_level)
    mktempdir() do dir
        objfile = joinpath(dir, "a.out")
        asmfile = joinpath(dir, "a.S")
        mod, _ = irgen(func, tt)
        target_machine(llvm_march(march)) do tm
            optimize!(tm, mod, optlevel)
            LLVM.emit(tm, mod, LLVM.API.LLVMAssemblyFile, asmfile)
        end

        llvm_mca() do llvm_mca_path
            Base.run(`$llvm_mca_path -mcpu $(llvm_march(march)) $asmfile`)
        end
    end
    return nothing
end

function llvm_march(march)
    cpus = Dict(
        :HSW => "haswell",
        :BDW => "broadwell",
        :SKL => "skylake",
        :SKX => "skx",
    )
    @assert haskey(cpus, march) "Arch: $march not supported"
    return cpus[march]
end

nameof(f::Core.Function) = String(typeof(f).name.mt.name)

function target_machine(lambda, cpu, features = "")
    triple = LLVM.triple()
    target = LLVM.Target(triple)
    LLVM.TargetMachine(lambda, target, triple, cpu, features)
end

"""
    jloptimize!(tm, mod, optlevel)

Runs the Julia optimizer pipeline.
"""
function jloptimize!(tm::LLVM.TargetMachine, mod::LLVM.Module, optlevel)
    ModulePassManager() do pm
        add_library_info!(pm, triple(mod))
        add_transform_info!(pm, tm)
        ccall(:jl_add_optimization_passes, Nothing,
              (LLVM.API.LLVMPassManagerRef, Cint),
               LLVM.ref(pm), optlevel)
        run!(pm, mod)
    end
end

"""
    mark_start()

Insert `iaca` and `llvm-mca` start markers at this position.
"""
function mark_start()
    @asmcall("""
    movl \$\$111, %ebx
    .byte 0x64, 0x67, 0x90
    # LLVM-MCA-BEGIN
    """, "~{memory},~{ebx}", true)
end

"""
    mark_end()

Insert `iaca` and `llvm-mca` end markers at this position.
"""
function mark_end()
    @asmcall("""
    # LLVM-MCA-END
    movl \$\$222, %ebx
    .byte 0x64, 0x67, 0x90
    """, "~{memory},~{ebx}", true)
end

include("reflection.jl")
end # module
