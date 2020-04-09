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

using  GPUCompiler
import GPUCompiler: NativeCompilerTarget, FunctionSpec

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

Base.@kwdef struct MCACompilerJob <: AbstractCompilerJob
    target::NativeCompilerTarget
    source::FunctionSpec
    optlevel::Int=Base.JLOptions().opt_level
end

import GPUCompiler: target, source, runtime_slug
target(job::MCACompilerJob) = job.target
source(job::MCACompilerJob) = job.source

Base.similar(job::MCACompilerJob, source::FunctionSpec) =
    MCACompilerJob(target=job.target, source=source)

function Base.show(io::IO, job::MCACompilerJob)
    print(io, "Native CompilerJob of ", source(job))
    print(io, " for $(target(job).cpu) $(target(job).features)")
end

# TODO: encode debug build or not in the compiler job
#       https://github.com/JuliaGPU/CUDAnative.jl/issues/368
runtime_slug(job::MCACompilerJob) = "native_$(target(job).cpu)$(target(job).features)"

function GPUCompiler.optimize!(job::MCACompilerJob, mod::LLVM.Module, entry::LLVM.Function)
    tm = GPUCompiler.llvm_machine(target(job))

    ModulePassManager() do pm
        add_library_info!(pm, triple(mod))
        add_transform_info!(pm, tm)
        ccall(:jl_add_optimization_passes, Nothing,
              (LLVM.API.LLVMPassManagerRef, Cint),
               LLVM.ref(pm), job.optlevel)
        run!(pm, mod)
    end

    return entry
end

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
function analyze(@nospecialize(func), @nospecialize(tt);
                 march=:SKL, optlevel=Base.JLOptions().opt_level)
    mktempdir() do dir
        objfile = joinpath(dir, "a.out")
        asmfile = joinpath(dir, "a.S")

        source = FunctionSpec(func, Base.to_tuple_type(tt), false)
        target = NativeCompilerTarget(cpu=llvm_march(march))
        job = MCACompilerJob(target, source, optlevel)

        open(asmfile, "w") do io
            GPUCompiler.code_native(io, job, raw=true)
        end
        
        llvm_mca() do llvm_mca_path
            Base.run(`$llvm_mca_path -mcpu $(llvm_march(march)) $asmfile`)
        end
    end
    return nothing
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
