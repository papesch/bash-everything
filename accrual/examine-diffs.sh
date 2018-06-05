#!/bin/bash
print_usage(){
  echo "Usage: $0 <results-XXXXX.txt>"
  echo "Examines exactly where XML files differ, based on results of compare-accrual-rq.sh"
}
[ $1 ] || { print_usage ; exit ; }
[ -f $1 ] || { ls $1 ; exit ; }
dfile=$1
dbase=$( echo $dfile | sed 's/results-//;s/.txt//' )
ddir=split-$dbase
odir=results-diff-$dbase
echo "writing diffs: $odir"
mkdir $odir
i=0
main(){
  while read z baserq zz testrq zzz
  do
    ((i++))
    padi=$( printf "%04d\n" $i )
    ddiff=$odir/diff-$dbase-$padi.txt
    echo "DIFF $baserq || $testrq" >> $ddiff
    sdiff -w220 <( xmllint --format $ddir/$baserq ) <( xmllint --format $ddir/$testrq ) >> $ddiff
  done < <( grep differ $dfile )
}

main
exit
