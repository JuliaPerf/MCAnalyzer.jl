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

set -x JLPASSES \
    -tbaa \
    -PropagateJuliaAddrspaces \
    -simplifycfg \
    -dce \
    -sroa \
    -memcpyopt \
    -always-inline \
    -AllocOpt \
    -instcombine \
    -simplifycfg \
    -sroa \
    -instcombine \
    -jump-threading \
    -instcombine \
    -reassociate \
    -early-cse \
    -AllocOpt \
    -loop-idiom \
    -loop-rotate \
    -LowerSIMDLoop \
    -licm \
    -loop-unswitch \
    -instcombine \
    -indvars \
    -loop-deletion \
    -loop-unroll \
    -AllocOpt \
    -sroa \
    -instcombine \
    -gvn \
    -memcpyopt \
    -sccp \
    -sink \
    -instsimplify \
    -instcombine \
    -jump-threading \
    -dse \
    -AllocOpt \
    -simplifycfg \
    -loop-idiom \
    -loop-deletion \
    -jump-threading \
    -slp-vectorizer \
    -adce \
    -instcombine \
    -loop-vectorize \
    -instcombine \
    -barrier \
    -LowerExcHandlers \
    -GCInvariantVerifier \
    -LateLowerGCFrame \
    -dce \
    -LowerPTLS \
    -simplifycfg \
    -CombineMulAdd

# This one is a truncated pass pipeline I often use to debug the loop vectorizer
set -x JLPASSES_UNTIL_LV -tbaa -PropagateJuliaAddrspaces -simplifycfg -dce -sroa -memcpyopt -always-inline -AllocOpt \
          -instcombine -simplifycfg -sroa -instcombine -jump-threading -instcombine -reassociate \
          -early-cse -AllocOpt -loop-idiom -loop-rotate -LowerSIMDLoop -licm -loop-unswitch \
          -instcombine -indvars -loop-deletion -loop-unroll -AllocOpt -sroa -instcombine -gvn \
          -memcpyopt -sccp -sink -instsimplify -instcombine -jump-threading -dse -AllocOpt \
          -simplifycfg -loop-idiom -loop-deletion -jump-threading -slp-vectorizer -adce \
          -instcombine
