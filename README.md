# IACA
[![Build Status](https://travis-ci.org/vchuravy/IACA.jl.svg?branch=master)](https://travis-ci.org/vchuravy/IACA.jl)

`IACA.jl` provides a interface to the [*Intel Architecture Code Analyzer*](https://software.intel.com/en-us/articles/intel-architecture-code-analyzer) for Julia functions.

## Installation 
First manually install **IACA** from https://software.intel.com/en-us/articles/intel-architecture-code-analyzer and then install this package.
If `iaca` is not on your path set the environment variable `IACA_PATH=...` to point to the `iaca` binary that you downloaded from Intel.

## Usage

`IACA.jl` provides the two functions `iaca_start` and `iaca_end`  both will insert some special markers into you code.
`iaca` will then analyse the generated object file and only analyse the parts in between the two markers.

To invoke `iaca` on a specific method that has been annotated use `analyze(func, tt)` where `tt` is a tuple of types that gives the type signature of the method.

#### Supported architectures
- `HSW`: Haswell
- `BDW`: Broadwell
- `SKL`: Skylake
- `SKX`: Skylake-X

By default `analyse` will use `SKL`, but you can supply a target architecture through `analyze(func, tt, :SKX)`

### Caveats
`iaca` 3.0 currently only supports *throughput* analysis. This means that currently it is only useful to analyse loops.
`iaca_start()` has to be in the beginning of the loop body and `iaca_end()` has to be after the loop. `iaca` will then treat the loop as an infite loop. 

### Examples

```julia
using IACA

function mysum(A)
    acc = zero(eltype(A))
    for a in A
        iaca_start()
        acc += a
    end
    iaca_end()
    return acc
end

analyze(mysum, Tuple{Vector{Float64}})
```

```julia
using IACA

function f(y::Float64)
    x = 0.0
    for i=1:100
        iaca_start()
        x += 2*y*i
    end
    iaca_end()
    x
end

analyze(f, Tuple{Float64})
```

```julia
using IACA

function g(y::Float64)
    x1 = x2 = x3 = x4 = x5 = x6 = x7 = 0.0
    for i=1:7:100
        iaca_start()
        x1 += 2*y*i
        x2 += 2*y*(i+1)
        x3 += 2*y*(i+2)
        x4 += 2*y*(i+3)
        x5 += 2*y*(i+4)
        x6 += 2*y*(i+5)
        x7 += 2*y*(i+6)
    end
    iaca_end()
    x1 + x2 + x3 + x4 + x5 + x6 + x7
end

analyze(g, Tuple{Float64})
```

### Advanced usage
#### Switching opt-level (0.7 only)

```julia
IACA.optlevel[] = 3
analyze(mysum, Tuple{Vector{Float64}}, :SKL)
````
#### Changing the optimization pipeline

```julia
myoptimize!(tm, mod) = ...
analyze(mysum. Tuple{Vector{Float64}}, :SKL, #=optimize!=# myoptimize!)
````

## Notes
`IACA.jl` only supports version 3.0 of `iaca` at the time of this writing there has been no documentation released for version 3.0.

- Version 3.0 only support [`Throughput Analysis`](https://software.intel.com/en-us/articles/intel-architecture-code-analyzer#Throughput Analysis)
- The user guide for version 2.0 is available at https://progforperf.github.io/IACA-Guide.pdf
- http://www.agner.org/optimize/

## Acknowledgment
- @maleadt for [LLVM.jl](https://github.com/maleadt/LLVM.jl)
- @carnaval for the original [IACA.jl](https://github.com/carnaval/IACA.jl)
