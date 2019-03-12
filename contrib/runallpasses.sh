#!/bin/fish
set DIR (dirname (status -f))
source $DIR/perfenv.sh

set WORKDIR $argv[1]
set FILE $argv[2]

echo "Working on $FILE in $WORKDIR"

rm -rf $WORKDIR
mkdir $WORKDIR
cp $FILE $WORKDIR/input.ll
pushd $WORKDIR

git init
git add input.ll
git commit -m "original file"
$OPT -instnamer -S -o input.ll input.ll
git add input.ll
git commit -m "after instnamer"
cp input.ll perminput.ll

set N (count $JLPASSES)
for i in (seq 1 $N)
    $OPT $OPTFLAGS $JLPASSES[1..$i] -S -o input.ll perminput.ll
    git add input.ll
    git commit -m "after $i passes $JLPASSES[$i]"
end
popd
