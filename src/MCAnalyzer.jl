module MCAnalyzer
export mark_start, mark_end, analyze

using LLVM
using LLVM.Interop

const optlevel = Ref{Int}()
const analyzer = Ref{Any}()

function __init__()
    @assert LLVM.InitializeNativeTarget() == false
    optlevel[] = Base.JLOptions().opt_level
    analyzer[] = iaca
end

function iaca(march, objfile, asmfile)
    iaca_path = "iaca"
    if haskey(ENV, "IACA_PATH")
        iaca_path = ENV["IACA_PATH"]
    end
    @assert !isempty(iaca_path)
    Base.run(`$iaca_path -arch $march $objfile`)
end

function llvm_mca(march, objfile, asmfile)
    llvm_mca = "llvm-mca"
    if haskey(ENV, "LLVM_MCA_PATH")
        llvm_mca = ENV["LLVM_MCA_PATH"]
    end
    @assert !isempty(llvm_mca)
    Base.run(`$llvm_mca -mcpu $(llvm_march(march)) $asmfile`)
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
MCAnalyzer.optlevel[] = 3
analyze(mysum, Tuple{Vector{Float64}}, :SKL)
````

## Changing the optimization pipeline

```julia
myoptimize!(tm, mod) = ...
analyze(mysum, Tuple{Vector{Float64}}, :SKL, myoptimize!)
````

## Changing the analyzer tool
MCAnalyzer.analyzer[] = MCAnalyzer.llvm_mca
analyze(mysum, Tuple{Vector{Float64}})
"""
function analyze(@nospecialize(func), @nospecialize(tt), march=:SKL, optimize!::Core.Function = jloptimize!)
    mktempdir() do dir
        objfile = joinpath(dir, "a.out")
        asmfile = joinpath(dir, "a.S")
        mod, _ = irgen(func, tt)
        target_machine(llvm_march(march)) do tm
            optimize!(tm, mod)
            LLVM.emit(tm, mod, LLVM.API.LLVMAssemblyFile, asmfile)
            LLVM.emit(tm, mod, LLVM.API.LLVMObjectFile, objfile)
        end
        Base.invokelatest(analyzer[], march, objfile, asmfile)
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
    jloptimize!(tm, mod)

Runs the Julia optimizer pipeline.
"""
function jloptimize!(tm::LLVM.TargetMachine, mod::LLVM.Module)
    ModulePassManager() do pm
        add_library_info!(pm, triple(mod))
        add_transform_info!(pm, tm)
        ccall(:jl_add_optimization_passes, Nothing,
              (LLVM.API.LLVMPassManagerRef, Cint),
               LLVM.ref(pm), optlevel[])
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
