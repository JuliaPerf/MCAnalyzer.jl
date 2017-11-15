# Imported from  CUDAnative.jl

#
# code_* replacements
#

"""
    code_llvm([io], f, types; cpu = "skylake", optimizer! = jloptimize!, optimize = true, dump_module = false)

Prints the LLVM IR generated for the method matching the given generic function and type
signature to `io` which defaults to `STDOUT`. The IR is optimized according to `optimize`
(defaults to true), and the entire module, including headers and other functions, is dumped
if `dump_module` is set (defaults to false). The code is optimized for `cpu`, with the pass
order given by `optimize!`, by default we optimize for `"skylake"` and use the Julia pass order.
"""
function code_llvm(io::IO, @nospecialize(func::Core.Function), @nospecialize(types=Tuple);
               cpu::String = "skylake", optimize!::Core.Function = jloptimize!,
               optimize::Bool = true, dump_module::Bool = false)

    backwardsCompat && error("On 0.6 use Base.code_llvm")

    tt = Base.to_tuple_type(types)
    mod, llvmf = irgen(func, tt)
    if optimize
        target_machine(cpu) do tm
            optimize!(tm, mod)
        end
    end
    if dump_module
        show(io, mod)
    else
        show(io, llvmf)
    end
end
code_llvm(@nospecialize(func), @nospecialize(types=Tuple); kwargs...) = code_llvm(STDOUT, func, types; kwargs...)

"""
    code_native([io], f, types; cpu = "skylake", optimize! = jloptimize!, dump_module = false, verbose = false)

Emits assembly for the given `cpu` and `optimize!` pass pipline. 
"""
function code_native(io::IO, @nospecialize(func::Core.Function), @nospecialize(types=Tuple);
                     cpu::String = "skylake", optimize!::Core.Function = jloptimize!,
                     dump_module::Bool = false, verbose::Bool = false)

    backwardsCompat && error("On 0.6 use Base.code_native")

    tt = Base.to_tuple_type(types)
    mod, llvmf = irgen(func, tt)
    asm = target_machine(cpu) do tm
        optimize!(tm, mod)
        asm_verbosity!(tm, verbose)
        LLVM.emit(tm, mod, LLVM.API.LLVMAssemblyFile)
    end
    dump_module && write(io, asm)

    # filter the assembly file
    foundStart = false
    start1 = string(LLVM.name(llvmf), ':')
    start2 = string('"', LLVM.name(llvmf), '"', ':')
    asmbuf = IOBuffer(asm)
    for line in eachline(asmbuf)
        if !foundStart
            foundStart = startswith(line, start1) ||
                         startswith(line, start2)
        end
        if foundStart
            write(io, line)
            if startswith(line, ".Lfunc_end")
                break
            end
            write(io, '\n')
        end
    end
    if !foundStart
    	warn("Did not find the start of the function")
	    write(io, asm)
    end
end
code_native(@nospecialize(func), @nospecialize(types=Tuple); kwargs...) =
code_native(STDOUT, func, types; kwargs...)
