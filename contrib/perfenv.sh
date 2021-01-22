# fish script that setups an environment suitable to investigate various codegen issues

###
# Random notes:
# Use `$OPT $OPTFLAGS $JLPASSES -S -o opt.ll src.ll` to run the julia passes 
# Use `$OPT -dot-cfg opt.ll` to get a control flow graph, to render use:
# `dot -Tpdf my.dot -o my.pdf`
#
# TODO: Probably better to integrate with `-print-before`

if test -z "$JULIA_PATH"
    set JULIA_PATH $HOME/builds/julia-debug/usr
end

set LLVM_PATH $JULIA_PATH/tools

if test -e $JULIA_PATH/bin/julia-debug
    set SUFFIX "-debug"
else
    set SUFFIX ""
end

set -x JL $JULIA_PATH/bin/julia$SUFFIX
set -x OPT $LLVM_PATH/opt
set -x OPTFLAGS -load=$JULIA_PATH/lib/libjulia$SUFFIX.so

# This list of pass should reflect `addOptimizationPasses`:
# https://github.com/JuliaLang/julia/blob/ae53238c45a0cd6dafc6e121f4daaa93143bf627/src/aotcompile.cpp#L621-L806
set -x JLPASSES \
    --PropagateJuliaAddrspaces \
    --scoped-noalias \
    --tbaa \
    --basic-aa \
    --simplifycfg \
    --dce \
    --sroa \
    --always-inline \
    --AllocOpt \
    --instcombine \
    --simplifycfg \
    --sroa \
    --instsimplify \
    --jump-threading \
    --reassociate \
    --early-cse \
    --AllocOpt \
    --loop-idiom \
    --LowerSIMDLoop \
    --licm \
    --JuliaLICM \
    --loop-unswitch \
    --licm \
    --JuliaLICM \
    --instsimplify \
    --indvars \
    --loop-deletion \
    --loop-unroll \
    --AllocOpt \
    --sroa \
    --instsimplify \
    --gvn \
    --memcpyopt \
    --sccp \
    --instcombine \
    --jump-threading \
    --dse \
    --AllocOpt \
    --simplifycfg \
    --loop-deletion \
    --instcombine \
    --loop-vectorize \
    --loop-load-elim \
    --simplifycfg \
    --slp-vectorizer \
    --adce \
    --barrier \
    --LowerExcHandlers \
    --GCInvariantVerifier \
    --LateLowerGCFrame \
    --FinalLowerGC \
    --gvn \
    --sccp \
    --dce \
    --LowerPTLS \
    --instcombine \
    --simplifycfg \
    --CombineMulAdd \
    --div-rem-pairs

# This one is a truncated pass pipeline I often use to debug the loop vectorizer
set -x JLPASSES_UNTIL_LV -tbaa -PropagateJuliaAddrspaces -simplifycfg -dce -sroa -memcpyopt -always-inline -AllocOpt \
          -instcombine -simplifycfg -sroa -instcombine -jump-threading -instcombine -reassociate \
          -early-cse -AllocOpt -loop-idiom -loop-rotate -LowerSIMDLoop -licm -loop-unswitch \
          -instcombine -indvars -loop-deletion -loop-unroll -AllocOpt -sroa -instcombine -gvn \
          -memcpyopt -sccp -sink -instsimplify -instcombine -jump-threading -dse -AllocOpt \
          -simplifycfg -loop-idiom -loop-deletion -jump-threading -slp-vectorizer -adce \
          -instcombine
