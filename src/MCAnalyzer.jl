module MCAnalyzer
export mark_start, mark_end, analyze

import LLVM
import LLVM.Interop: @asmcall

using GPUCompiler

const analyzer = Ref{Any}()

function __init__()
    @assert LLVM.InitializeNativeTarget() == false
    analyzer[] = iaca
end

#=========================================================#
# GPUCompiler
#=========================================================#

module MockRuntime
    signal_exception() = return
    malloc(sz) = C_NULL
    report_oom(sz) = return
    report_exception(ex) = return
    report_exception_name(ex) = return
    report_exception_frame(idx, func, file, line) = return
end

struct CompilerParams <: AbstractCompilerParams end
GPUCompiler.runtime_module(::CompilerJob{<:Any,CompilerParams}) = MockRuntime

function mcjob(@nospecialize(func), @nospecialize(types);
               cpu::String = (LLVM.version() < v"8") ? "" : unsafe_string(LLVM.API.LLVMGetHostCPUName()),
               features::String=(LLVM.version() < v"8") ? "" : unsafe_string(LLVM.API.LLVMGetHostCPUFeatures()),
               kwargs...)
    source = FunctionSpec(func, Base.to_tuple_type(types), #=kernel=# false)
    target = NativeCompilerTarget(cpu=cpu, features=features)
    params = CompilerParams()
    CompilerJob(target, source, params), kwargs
end

include("reflection.jl")

#=========================================================#
# IACA
#=========================================================#

function iaca(march, objfile, asmfile)
    iaca_path = "iaca"
    if haskey(ENV, "IACA_PATH")
        iaca_path = ENV["IACA_PATH"]
    end
    @assert !isempty(iaca_path)
    Base.run(`$iaca_path -arch $march $objfile`)
end

#=========================================================#
# LLVM-MCA
#=========================================================#

function llvm_mca(march, objfile, asmfile)
    llvm_mca = "llvm-mca"
    if haskey(ENV, "LLVM_MCA_PATH")
        llvm_mca = ENV["LLVM_MCA_PATH"]
    end
    @assert !isempty(llvm_mca)
    Base.run(`$llvm_mca -mcpu $(llvm_march(march)) $asmfile`)
end

"""
    analyze(func, types, march = :SKL)

Analyze a given function `func` with the signature `types`.
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

analyze(mysum, (Vector{Float64},))
```

# Changing the analyzer tool

```julia
MCAnalyzer.analyzer[] = MCAnalyzer.llvm_mca
analyze(mysum, (Vector{Float64},))
```
"""
function analyze(@nospecialize(func), @nospecialize(tt), march=:SKL; kwargs...)
    job, kwargs = mcjob(func, tt; cpu=llvm_march(march), kwargs...)
    ir, func = GPUCompiler.compile(:llvm, job; kwargs...)

    GPUCompiler.finish_module!(job, ir)

    mktempdir() do dir
        objfile = joinpath(dir, "a.out")
        asmfile = joinpath(dir, "a.S")

        tm = GPUCompiler.llvm_machine(job.target)
        LLVM.emit(tm, ir, LLVM.API.LLVMAssemblyFile, asmfile)
        LLVM.emit(tm, ir, LLVM.API.LLVMObjectFile, objfile)

        # Now call analyzer
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

#=========================================================#
# Markers 
#=========================================================#

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

end # module
