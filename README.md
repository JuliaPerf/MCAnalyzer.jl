# MCAnalyzer
[![Build Status](https://travis-ci.org/vchuravy/MCAnalyzer.jl.svg?branch=master)](https://travis-ci.org/vchuravy/MCAnalyzer.jl)

`MCAnalyzer.jl` provides a interface to [*LLVM MCA*](https://www.llvm.org/docs/CommandGuide/llvm-mca.html) for Julia functions.

# Usage

`MCAnalyzer.jl` provides the two functions `mark_start` and `mark_end`  both will insert some special markers into you code.
`llvm-mca` will then analyse the generated object file and only analyse the parts in between the two markers.

To invoke `llvm-mca` on a specific method that has been annotated use `analyze(func, types)` where `types` is a tuple of types that gives the type signature of the method.

### Supported architectures

- `HSW`: Haswell
- `BDW`: Broadwell
- `SKL`: Skylake
- `SKX`: Skylake-X

By default `analyse` will use `SKL`, but you can supply a target architecture through `analyze(func, tt, :SKX)`

### Caveats

`iaca` 3.0 currently only supports *throughput* analysis. This means that currently it is only useful to analyze loops.
`mark_start()` has to be in the beginning of the loop body and `mark_end()` has to be after the loop. `iaca` will then treat the loop as an infite loop.

It is recommended to use `@code_llvm`/`@code_native` to inspect the IR/assembly and check that the annotations are
in the expected place.

### Examples

```julia
using MCAnalyzer

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

```julia
using MCAnalyzer

function f(y::Float64)
    x = 0.0
    for i=1:100
        mark_start()
        x += 2*y*i
    end
    mark_end()
    x
end

analyze(f, (Float64,))
```

```julia
using MCAnalyzer

function g(y::Float64)
    x1 = x2 = x3 = x4 = x5 = x6 = x7 = 0.0
    for i=1:7:100
        mark_start()
        x1 += 2*y*i
        x2 += 2*y*(i+1)
        x3 += 2*y*(i+2)
        x4 += 2*y*(i+3)
        x5 += 2*y*(i+4)
        x6 += 2*y*(i+5)
        x7 += 2*y*(i+6)
    end
    mark_end()
    x1 + x2 + x3 + x4 + x5 + x6 + x7
end

analyze(g, Tuple{Float64})
```

## Notes

- http://www.agner.org/optimize/

## Acknowledgment

- @maleadt for [LLVM.jl](https://github.com/maleadt/LLVM.jl)
- @carnaval for [IACA.jl](https://github.com/carnaval/IACA.jl) the original inspiration for this project
