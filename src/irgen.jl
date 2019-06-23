const globalUnique = Ref{Int64}(0)
using DataStructures

function compile_method_instance(method_instance::Core.MethodInstance, world)
    function postprocess(ir)
        # get rid of jfptr wrappers
        for llvmf in functions(ir)
            startswith(LLVM.name(llvmf), "jfptr_") && unsafe_delete!(ir, llvmf)
        end

        return
    end

    # set-up the compiler interface
    last_method_instance = nothing
    call_stack = Vector{Core.MethodInstance}()
    dependencies = MultiDict{Core.MethodInstance,LLVM.Function}()

    function hook_module_activation(ref::Ptr{Cvoid})
        ref = convert(LLVM.API.LLVMModuleRef, ref)
        ir = LLVM.Module(ref)
        postprocess(ir)

        # find the function that this module defines
        llvmfs = filter(llvmf -> !isdeclaration(llvmf) &&
                                 linkage(llvmf) == LLVM.API.LLVMExternalLinkage,
                        collect(functions(ir)))

        llvmf = nothing
        if length(llvmfs) == 1
            llvmf = first(llvmfs)
        elseif length(llvmfs) > 1
            llvmfs = filter!(llvmf -> startswith(LLVM.name(llvmf), "julia_"), llvmfs)
            if length(llvmfs) == 1
                llvmf = first(llvmfs)
            end
        end

        @assert llvmf !== nothing

        insert!(dependencies, last_method_instance, llvmf)
    end
    function hook_emit_function(method_instance, code, world)
        push!(call_stack, method_instance)

        # check for recursion
        if method_instance in call_stack[1:end-1]
            @error "call_stack" call_stack
            error("recursion is currently not supported")
        end
    end
    function hook_emitted_function(method, code, world)
        @assert last(call_stack) == method
        last_method_instance = pop!(call_stack)
    end
    params = Base.CodegenParams(cached             = false,
                                track_allocations  = false,
                                code_coverage      = false,
                                static_alloc       = false,
                                prefer_specsig     = true,
                                module_activation  = hook_module_activation,
                                emit_function      = hook_emit_function,
                                emitted_function   = hook_emitted_function)

    # get the code
    ref = ccall(:jl_get_llvmf_defn, LLVM.API.LLVMValueRef,
                (Any, UInt, Bool, Bool, Base.CodegenParams),
                method_instance, world, #=wrapper=#false, #=optimize=#false, params)
    if ref == C_NULL
        throw(InternalCompilerError(job, "the Julia compiler could not generate LLVM IR"))
    end
    llvmf = LLVM.Function(ref)
    ir = LLVM.parent(llvmf)
    postprocess(ir)

    return llvmf, dependencies
end

function irgen(method_instance::Core.MethodInstance, world)
    entry, dependencies = compile_method_instance(method_instance, world)
    mod = LLVM.parent(entry)

    begin
        # we disable Julia's compilation cache not to poison it with GPU-specific code.
        # as a result, we might get multiple modules for a single method instance.
        cache = Dict{String,String}()

        for called_method_instance in keys(dependencies)
            llvmfs = dependencies[called_method_instance]

            # link the first module
            llvmf = popfirst!(llvmfs)
            llvmfn = LLVM.name(llvmf)
            link!(mod, LLVM.parent(llvmf))

            # process subsequent duplicate modules
            for dup_llvmf in llvmfs
                # don't link them, but note the called function name in a cache
                dup_llvmfn = LLVM.name(dup_llvmf)
                cache[dup_llvmfn] = llvmfn
            end
        end

        # resolve function declarations with cached entries
        for llvmf in filter(isdeclaration, collect(functions(mod)))
            llvmfn = LLVM.name(llvmf)
            if haskey(cache, llvmfn)
                def_llvmfn = cache[llvmfn]
                replace_uses!(llvmf, functions(mod)[def_llvmfn])

                @assert isempty(uses(llvmf)) job
                unsafe_delete!(LLVM.parent(llvmf), llvmf)
            end
        end
    end

    llvmfn = replace(LLVM.name(entry), r"_\d+$"=>"")
    ## append a global unique counter
    global globalUnique
    globalUnique += 1
    llvmfn *= "_$globalUnique"
    LLVM.name!(entry, llvmfn)

    # minimal required optimization
    ModulePassManager() do pm
        linkage!(entry, LLVM.API.LLVMExternalLinkage)
        internalize!(pm, [LLVM.name(entry)])

        always_inliner!(pm)
        run!(pm, mod)
    end

    return mod, entry
end

function get_methodinstance(@nospecialize(sig))
    world = typemax(UInt)
    m = ccall(:jl_gf_invoke_lookup, Any, (Any, UInt), sig, world)
    meth = m.func::Method

    (ti, env) = ccall(:jl_type_intersection_with_env, Any,
                      (Any, Any), sig, meth.sig)::Core.SimpleVector
    if VERSION >= v"1.2.0-DEV.320"
        meth = Base.func_for_method_checked(meth, ti, env)
    else
        meth = Base.func_for_method_checked(meth, ti)
    end

    linfo = ccall(:jl_specializations_get_linfo, Ref{Core.MethodInstance},
                  (Any, Any, Any, UInt), meth, ti, env, world)
    return linfo::Core.MethodInstance, world
end

function lookup_sig(@nospecialize(func), @nospecialize(tt))
    isa(func, Core.Builtin) && error("function is not a generic function")
    return Base.signature_type(func, tt)::Type
end

function irgen(@nospecialize(func), @nospecialize(tt))
    sig = lookup_sig(func, tt)
    irgen(sig)
end

function irgen(@nospecialize(sig))
    mi, world = get_methodinstance(sig)
    return irgen(mi, world)
end