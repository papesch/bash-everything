#!/bin/bash
# Compare AccruePoints RQ XMLs from AAEv1 and AAEv2.
# XML data should have been extracted from AAE logs by "get-accrual-rq.sh"
# and massaged a bit by "prep-accrual-rq.sh"
# 1. get-accrual-rq.sh
# 2. prep-accrual-rq.sh
# 3. compare-accrual-rq.sh
# Design notes: https://jira.redacted.com/browse/LSB-1030
#set -e #causes script to exit if diff returns -1!!!
#set -x #debug
set -u #warn if unbound variable found

# input checks - need to work on "prep" files
print_usage(){
  echo "Usage: $0 <prep.AAEv1-base.xml prep.AAEv2-test.xml>"
  echo "Compares AccruePointsRQ XML from AAEv1 and AAEv2 log extracts."
}
[ $2 ] || { print_usage ; exit ; }
[ -f $1 ] || { ls $1 ; exit ; }
[ -f $2 ] || { ls $2 ; exit ; }
[ "$( echo $1|grep "prep"|grep "base" )" == "" ] && { echo "\$1 not prep/base" ; exit ; }
[ "$( echo $2|grep "prep"|grep "test" )" == "" ] && { echo "\$2 not prep/test" ; exit ; }
time64=$( date +%s|xargs printf %x|xxd -r -p|base64|tr -cd [:alnum:] )
basefile=$1
testfile=$2

main(){
  create_working_dir
  get_baseline_rq
  get_newtest_rq
  compare_accruals
}

create_working_dir(){
  # Create directory for accrual XMLs, e.g. "split-Wuffg"
  splitdir="split-$time64"
  mkdir $splitdir
  echo "working-dir: $splitdir"
}

get_baseline_rq(){
  # split baseline accruals line-by-line into individual files
  # filenames are based on the prefixes inserted by the "prep" script
  # e.g. 76497LG6JJHAVAL0862520201159_base.I2c
  echo "AAE-v1-data: $(wc -l $basefile | awk '{print $1}' )"
  while read rq; do
    rqxml=$( echo "$rq" | awk '{ print $1 }' | sed 's/_pre/_base/' )
    rqfile=$( mktemp $splitdir/$rqxml.XXX ) || exit 1
    echo "$rq" | awk -F'_pre ' '{ print $2 }' > $rqfile
  done < $basefile
}

get_newtest_rq(){
  # split test accruals line-by-line into individual files
  # e.g. 76497LG6JJHAVAL0862520201159_test.JHR
  echo "AAE-v2-data: $(wc -l $testfile | awk '{print $1}' )"
  while read rq; do
    rqxml=$( echo "$rq" | awk '{ print $1 }' | sed 's/_pre/_test/' )
    rqfile=$( mktemp $splitdir/$rqxml.XXX ) || exit 1
    echo "$rq" | awk -F'_pre ' '{ print $2 }' > $rqfile
  done < $testfile
}

compare_accruals(){
  # iterate over the "baseline" accruals "$rqb"
  cd $splitdir
  while read rqbase
  do
    echo
    echo "..testing $rqbase"
    find_possible_matches $rqbase
  done < <( ls -1 *_base* )
}

find_possible_matches(){
  rqbase=$1
  # identify possible matches from the "test" accruals that have the same prefix info
  possible=$( echo $rqbase | sed 's/base/test/' | awk -F. '{print $1}' )
  possible_count=$( ls $possible* 2>/dev/null | wc -l | awk '{print $1}' )
  if [ $possible_count -gt 0 ]
  then    # there are some possible matches. iterate thru the list.
    compare_base_to_matches $rqbase $possible
  else    # perhaps a script error, or you didn't retrieve enough data, or there's a bug
    echo "..has no match"
  fi
}

compare_base_to_matches(){
  rqbase=$1
  possible=$2
  while read rqtest
  do
    #if match is found, diff exit status is 0, so stop iterating & break
    diff -sq $rqbase $rqtest
    if [ $? -eq 0 ]; then echo "..matches $rqtest"
    fi
  done < <( ls -1 $possible* )
}

main | tee -a results-$time64.txt
exit
