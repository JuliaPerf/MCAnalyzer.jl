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
    code_native([io], f, types; cpu = "skylake", optimize! = jloptimize!)

Emits assembly for the given `cpu` and `optimize!` pass pipline. 
"""
function code_native(io::IO, @nospecialize(func::Core.Function), @nospecialize(types=Tuple);
                     cpu::String = "skylake", optimize!::Core.Function = jloptimize!)

    backwardsCompat && error("On 0.6 use Base.code_native")

    tt = Base.to_tuple_type(types)
    mod, llvmf = irgen(func, tt)
    asm = target_machine(cpu) do tm
        optimize!(tm, mod)
        LLVM.emit(tm, mod, LLVM.API.LLVMAssemblyFile)
        # TODO: Filter!
    end
    write(io, asm)
end
code_native(@nospecialize(func), @nospecialize(types=Tuple); kwargs...) =
code_native(STDOUT, func, types; kwargs...)