
#
# code_* replacements
#

"""
    code_llvm([io], f, types; cpu = "skylake", optimize = true, dump_module = false)

Prints the LLVM IR generated for the method matching the given generic function and type
signature to `io` which defaults to `STDOUT`. The IR is optimized according to `optimize`
(defaults to true), and the entire module, including headers and other functions, is dumped
if `dump_module` is set (defaults to false). The code is optimized for `cpu`, with the pass
order given by `optimize!`, by default we optimize for `"skylake"` and use the Julia pass order.
"""
function code_llvm(io::IO, @nospecialize(func::Core.Function), @nospecialize(types=Tuple);
               cpu::String = "skylake", optlevel=Base.JLOptions().opt_level, kwargs...)

    source = FunctionSpec(func, Base.to_tuple_type(types), false)
    target = NativeCompilerTarget(cpu=cpu)
    job = MCACompilerJob(target, source, optlevel)

    GPUCompiler.code_llvm(io, job, kwargs...)
end
code_llvm(@nospecialize(func), @nospecialize(types=Tuple); kwargs...) = 
    code_llvm(stdout, func, types; kwargs...)

"""
    code_native([io], f, types; cpu = "skylake", dump_module = false, verbose = false)

Emits assembly for the given `cpu` pass pipline.
"""
function code_native(io::IO, @nospecialize(func::Core.Function), @nospecialize(types=Tuple);
                     cpu::String = "skylake", optlevel=Base.JLOptions().opt_level, kwargs...)

    source = FunctionSpec(func, Base.to_tuple_type(types), false)
    target = NativeCompilerTarget(cpu=cpu)
    job = MCACompilerJob(target, source, optlevel)

    GPUCompiler.code_native(io, job, kwargs...)

    # # filter the assembly file
    # foundStart = false
    # start1 = string(LLVM.name(llvmf), ':')
    # start2 = string('"', LLVM.name(llvmf), '"', ':')
    # for line in eachline(asmbuf)
    #     if !foundStart
    #         foundStart = startswith(line, start1) ||
    #                      startswith(line, start2)
    #     end
    #     if foundStart
    #         write(io, line)
    #         if startswith(line, ".Lfunc_end")
    #             break
    #         end
    #         write(io, '\n')
    #     end
    # end
    # if !foundStart
    # 	warn("Did not find the start of the function")
	#     write(io, asm)
    # end
end
code_native(@nospecialize(func), @nospecialize(types=Tuple); kwargs...) =
    code_native(STDOUT, func, types; kwargs...)
