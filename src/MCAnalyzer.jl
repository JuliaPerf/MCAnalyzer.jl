module MCAnalyzer
export mark_start, mark_end, analyze, timeline, bottleneck, allstats

import LLVM
import LLVM.Interop: @asmcall

using GPUCompiler
import LLVM_jll

function __init__()
    @assert LLVM.InitializeNativeTarget() == false
end

#=========================================================#
# GPUCompiler
#=========================================================#

module MockRuntime
    signal_exception() = return
    malloc(sz) = ccall("extern malloc", llvmcall, Ptr{Int8}, (Int64,), sz)
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
# LLVM-MCA
#=========================================================#

if isdefined(LLVM_jll, :llvm_mca)
    import LLVM_jll: llvm_mca
else
    function llvm_mca(f)
        llvm_mca = get(ENV, "LLVM_MCA_PATH", joinpath(LLVM_jll.artifact_dir, "tools", "llvm_mca"))
        @assert !isempty(llvm_mca)
        f(llvm_mca)
    end
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
"""
function analyze(@nospecialize(func), @nospecialize(tt), march=:SKL; kwargs...)
    job, kwargs = mcjob(func, tt; cpu=llvm_march(march), kwargs...)
    mi, _ = GPUCompiler.emit_julia(job)
    ir, func = GPUCompiler.emit_llvm(job, mi; ctx=JuliaContext(), only_entry=false, kwargs...)

    mktempdir() do dir
        asmfile = joinpath(dir, "a.S")

        tm = GPUCompiler.llvm_machine(job.target)
        LLVM.emit(tm, ir, LLVM.API.LLVMAssemblyFile, asmfile)

        # Now call analyzer
        llvm_mca() do llvm_mca_path
            Base.run(`$llvm_mca_path -mcpu $(llvm_march(march)) $asmfile`)
        end
    end
    return nothing
end

"""
    timeline(func, types, march = :SKL)

Analyze a given function `func` with the signature `types` to produce a timeline
of execution, showing instruction dependencies.
The specific method needs to be annotated with the `IACA` markers.
Supported `march` are :HSW, :BDW, :SKL, and :SKX.

See [the documentation of llvm-mca](https://www.llvm.org/docs/CommandGuide/llvm-mca.html#timeline-view) for more information.

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

timeline(mysum, (Vector{Float64},))
```
"""
function timeline(@nospecialize(func), @nospecialize(tt), march=:SKL; kwargs...)
    job, kwargs = mcjob(func, tt; cpu=llvm_march(march), kwargs...)
    mi, _ = GPUCompiler.emit_julia(job)
    ir, func = GPUCompiler.emit_llvm(job, mi; ctx=JuliaContext(), only_entry=false, kwargs...)

    mktempdir() do dir
        asmfile = joinpath(dir, "a.S")

        tm = GPUCompiler.llvm_machine(job.target)
        LLVM.emit(tm, ir, LLVM.API.LLVMAssemblyFile, asmfile)

        # Now call analyzer
        llvm_mca() do llvm_mca_path
            Base.run(`$llvm_mca_path -mcpu $(llvm_march(march)) -timeline $asmfile`)
        end
    end
    return nothing
end

"""
    bottleneck(func, types, march = :SKL)

Analyze a given function `func` with the signature `types` to produce a report
of possible bottlenecks during execution.
The specific method needs to be annotated with the `IACA` markers.
Supported `march` are :HSW, :BDW, :SKL, and :SKX.

See [the documentation of llvm-mca](https://www.llvm.org/docs/CommandGuide/llvm-mca.html#bottleneck-analysis) for more information.

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

bottleneck(mysum, (Vector{Float64},))
```
"""
function bottleneck(@nospecialize(func), @nospecialize(tt), march=:SKL; kwargs...)
    job, kwargs = mcjob(func, tt; cpu=llvm_march(march), kwargs...)
    mi, _ = GPUCompiler.emit_julia(job)
    ir, func = GPUCompiler.emit_llvm(job, mi; ctx=JuliaContext(), only_entry=false, kwargs...)

    mktempdir() do dir
        asmfile = joinpath(dir, "a.S")

        tm = GPUCompiler.llvm_machine(job.target)
        LLVM.emit(tm, ir, LLVM.API.LLVMAssemblyFile, asmfile)

        # Now call analyzer
        llvm_mca() do llvm_mca_path
            Base.run(`$llvm_mca_path -mcpu $(llvm_march(march)) -bottleneck-analysis $asmfile`)
        end
    end
    return nothing
end

function allstats(@nospecialize(func), @nospecialize(tt), march=:SKL; kwargs...)
    job, kwargs = mcjob(func, tt; cpu=llvm_march(march), kwargs...)
    mi, _ = GPUCompiler.emit_julia(job)
    ir, func = GPUCompiler.emit_llvm(job, mi; ctx=JuliaContext(), only_entry=false, kwargs...)

    mktempdir() do dir
        asmfile = joinpath(dir, "a.S")

        tm = GPUCompiler.llvm_machine(job.target)
        LLVM.emit(tm, ir, LLVM.API.LLVMAssemblyFile, asmfile)

        # Now call analyzer
        llvm_mca() do llvm_mca_path
            Base.run(`$llvm_mca_path -mcpu $(llvm_march(march)) -all-stats $asmfile`)
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

#=========================================================#
# Markers 
#=========================================================#

"""
    mark_start()

Insert `iaca` and `llvm-mca` start markers at this position.
"""
function mark_start()
    @asmcall("""
    # LLVM-MCA-BEGIN
    """, "~{memory}", true)
end

"""
    mark_end()

Insert `iaca` and `llvm-mca` end markers at this position.
"""
function mark_end()
    @asmcall("""
    # LLVM-MCA-END
    """, "~{memory}", true)
end

end # module
