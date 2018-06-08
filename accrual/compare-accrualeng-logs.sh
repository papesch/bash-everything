#!/bin/bash
# Compare AccruePoints RQ XMLs from AAEv1 and AAEv2.
#set -e #causes script to exit if diff returns -1!!! DO NOT USE
#set -x #debug
set -u #warn if unbound variable found

# input checks - need to work on "prep" files
print_usage(){
  echo "Usage: $0 <airaccrualengine.log file name>"
  echo "Searches subdirectories of current dir for AAEv1 and AAEv2 logs, then extracts"
  echo "and compares AccruePointsRQ XMLs."
  echo "Example: $0 <airaccrualengine.log.2018-05-24-07>"
  echo "Results are output to accrualdiffs.2018052407.XXXXXX/"
}
[ $1 ] || { print_usage ; exit ; }
[ -f */$1 ] || { ls */$1 ; exit ; }
time64=$( date +%s|xargs printf %x|xxd -r -p|base64|tr -cd [:alnum:]|cut -c 2- )

################################################################################
#   __  __       _
#  |  \/  | __ _(_)_ __
#  | |\/| |/ _` | | '_ \
#  | |  | | (_| | | | | |
#  |_|  |_|\__,_|_|_| |_|
#
# AccruePointsRQ comparisons are applied by processing AAE logs in stages:
# 1. Extract XML
# 2. Prepare data for comparison
# 3. Find applicable matches
# 4. Detailed XML diffs
# Design notes: https://jira.redacted.com/browse/LSB-1030
# <== Input: (e.g.)
#     airaccrualengine.log.2018-05-24-15

main(){
  logpattern=$1                # e.g. airaccrualengine.log.2018-05-24-15
  make_diff_dir $logpattern    # Creates $diffdir
  do_extracts $logpattern      # 1. Outputs collated XML files for each matching AAE log
  cd $diffdir
  do_prepfiles                 # 2. Outputs $baseprep, $testprep (intermediate format)
  do_comparisons               # 3. Outputs $matchreport (text file with diff results)
                               #    Attempts to match on APMembershipId, PNRReference,
                               #    CreationDateTime, TransactionType, TicketNumber
                               #    (using many individual AccruePointsRQ XMLs in $splitdir)
  examine_diffs $matchreport   # 4. Outputs side-by-side diffs of AccruePointsRQs that
                               #    "match" on above elements but otherwise differ
}

make_diff_dir(){
  # All results go under directory $diffdir, e.g.
  # ==> accrualdiffs.2018052415.Ey80/
  logpattern=$1
  diffdir=accrualdiffs.$( echo $logpattern | tr -cd [:digit:] ).$time64
  mkdir $diffdir
  echo "..output dir: $diffdir"
}



################################################################################
#   _____      _                  _
#  | ____|_  _| |_ _ __ __ _  ___| |_ ___
#  |  _| \ \/ / __| '__/ _` |/ __| __/ __|
#  | |___ >  <| |_| | | (_| | (__| |_\__ \
#  |_____/_/\_\\__|_|  \__,_|\___|\__|___/
#
# Search subdirectories of CWD for files matching $logpattern
# <== Inputs: (e.g.)
#     airaccrualengine.log.2018-05-24-15
# ==> Outputs: (e.g.)
#     $diffdir/T0_APP02_11.airaccrualengine.log.2018-05-24-15.base.Ey80.xml
#     $diffdir/T0_APP24_11.airaccrualengine.log.2018-05-24-15.test.Ey80.xml

do_extracts(){
  logpattern=$1
  while read aaelog
  do
    echo "..extracting from $aaelog"
    get_accrual_rq $aaelog
  done < <( ls -1 */$logpattern )
}

get_accrual_rq(){
  #Extract AccruePointsRQ XML from AAE logs
  aaelog=$1
  # determine input type and output file name
  inputxml="ProcessingUtil - Message successfully parsed into TicketEventMessage V1x4."
  inputjson="ProcessingUtil - Json Message successfully parsed into TicketEventMessage."
  match_top="AccruePointsWSV1x8Operation - About to send request to AccruePoints Web Service V1x8 :"
  match_bot="AccruePointsWSV1x8Operation - Sending request"
  baseline_events=`zgrep -m 1 "$inputxml" $aaelog|wc -l|awk '{print $1}'`
  parallel_events=`zgrep -m 1 "$inputjson" $aaelog|wc -l|awk '{print $1}'`
  accrual_events=`zgrep -m 1 "$match_top" $aaelog|wc -l|awk '{print $1}'`

  tag=""
  [ $baseline_events -gt 0 ] && { tag="base" ; }
  [ $parallel_events -gt 0 ] && { tag="test" ; }
  [ $accrual_events -gt 0 ] || { echo "nothing to extract from $aaelog"; }
  jvm=$( grep -m1 airaccrualengine.properties $aaelog|awk -F'/opt/was/|/AirAccrualEngine' '{print $2}' )
  outputfile=$jvm.$( basename $aaelog ).$tag.$time64.xml
  echo "..extracting to $diffdir/$outputfile"

  # Now extract the XML
  # Tweak output slightly to improve matching between Baseline and Test XML
  grep -h -A999 "${match_top}" $aaelog \
    | awk "/${match_top}/,/${match_bot}/" \
    | sed 's/^[ \t]*//g' \
    | tr -d '\n' \
    | sed 's/AirNZ_AccruePointsRQ>2018/AirNZ_AccruePointsRQ>\n2018/g' \
    | sed 's/^2018.*AccruePointsWSV1x8Operation - About to send request to AccruePoints Web Service V1x8 ://g' \
    | sed 's/^2018.*AccruePointsWSV1x8Operation - Sending request to/\n/g' \
    > $diffdir/$outputfile
}



################################################################################
#   ____                      _                             _
#  |  _ \ _ __ ___ _ __      / \   ___ ___ _ __ _   _  __ _| |___
#  | |_) | '__/ _ \ '_ \    / _ \ / __/ __| '__| | | |/ _` | / __|
#  |  __/| | |  __/ |_) |  / ___ \ (_| (__| |  | |_| | (_| | \__ \
#  |_|   |_|  \___| .__/  /_/   \_\___\___|_|   \__,_|\__,_|_|___/
#                 |_|
# Prepare extracted XML data for efficient comparisons
# <== Inputs: (e.g.)
#     $diffdir/*base*xml, $diffdir/*test*xml
# ==> Outputs: (e.g.)
#     baseprep = $diffdir/prep.airaccrualengine.log.2018-05-24-15.base.Ey80
#     testprep = $diffdir/prep.airaccrualengine.log.2018-05-24-15.test.Ey80

do_prepfiles(){
  # Working directory is now $diffdir
  # Exit if we can't find both XML data files
  [ -f *base*xml ] || { ls *base*xml ; exit ; }
  [ -f *test*xml ] || { ls *test*xml ; exit ; }
  # Iterate over the extracted XML files
  while read xmldata
  do
    echo "..processing $xmldata"
    ptmp=$( mktemp ptmp.${xmldata}.XXX ) || exit 1
    echo "..to prepfile: $ptmp"
    prep_accruals $xmldata > $ptmp
  done < <( ls -1 *base*xml *test*xml )
  # Merge files (if needed) and rename
  baseprep=prep.$logpattern.base.$time64
  testprep=prep.$logpattern.test.$time64
  cat ptmp*base* > $prepbase
  cat ptmp*test* > $preptest
}

prep_accruals(){
  # Input: Extracted file containing an Accrual RQ on each line
  # Output: A similar file with unique prefixes on each line. Prefixes are based
  #         on contents of the XML (i.e. $pathexpr)
  xmldata=$1
  path_expr="//AirNZ_AccruePointsRQ/Ticket[1]/TicketNumber/text()"
  path_expr="$path_expr | //AirNZ_AccruePointsRQ/PNRHeader/PNRReference/text()"
  path_expr="$path_expr | //AirNZ_AccruePointsRQ/PNRHeader/CreationDateTime/text()"
  path_expr="$path_expr | //AirNZ_AccruePointsRQ/PNRHeader/TransactionType/text()"
  path_expr="$path_expr | //AirNZ_AccruePointsRQ/MemberDetails/APMembershipId/text()"
  echo "extracting to $preppedfile"

  grep . ${xmldata} | while read accrualRQ; do
    # strip namespace and known diffs
    #      | sed 's/<Coupon><CouponNumber>.<\/CouponNumber><CouponStatus>[^F3G9].*<\/Coupon>//' \
    thisRQ=$( echo "${accrualRQ}" \
      | sed 's,\( xmlns[^>]*\),,g; s,\( xsi:type[^>]*\),,g; s,ns:,,g' \
      | awk -F'TimeStamp' '{print $1 FS substr($2,1,11) "....</" FS $3 }' \
      | awk -F'TransactionIdentifier' '{print $1 FS substr($2,1,13) "....</" FS $3 }' \
      | awk -F'CreationDateTime' '{print $1 FS substr($2,1,17) "</" FS $3 }' \
      | sed 's,<OfficeOfIssue>.*</AgentsInitials>,,g' \
      | sed 's,<ScheduledDepartureDateTime>.............................</ScheduledDepartureDateTime>,,g' \
      | sed 's,<ScheduledArrivalDateTime>.............................</ScheduledArrivalDateTime>,,g' \
      | sed 's,<ProductCode>...</ProductCode>,,g' )
    uniqueID=$( echo "$thisRQ" | xmllint --xpath "$path_expr" - | tr -cd [:alnum:] )
    # add unique prefix to the line
    echo "  ${uniqueID}_pre $thisRQ"
  done
}



################################################################################
#    ____                                 _
#   / ___|___  _ __ ___  _ __   __ _ _ __(_)___  ___  _ __  ___
#  | |   / _ \| '_ ` _ \| '_ \ / _` | '__| / __|/ _ \| '_ \/ __|
#  | |__| (_) | | | | | | |_) | (_| | |  | \__ \ (_) | | | \__ \
#   \____\___/|_| |_| |_| .__/ \__,_|_|  |_|___/\___/|_| |_|___/
#                       |_|

do_comparisons(){
  echo "..finding matches for prep-baseline data"
  matchreport=results-$time64.txt
  echo "..match report: $matchreport"
  make_split_dir
  get_baseline_rq
  get_newtest_rq
  compare_accruals > $matchreport
}

make_split_dir(){
  # Create directory for accrual XMLs, e.g. "split-Wuffg" under $diffdir
  splitdir=$diffdir/split-$time64
  mkdir $splitdir
  echo "..split-dir: $splitdir"
}

get_baseline_rq(){
  # split baseline accruals line-by-line into individual files
  # filenames are based on the prefixes inserted by the "prep" script
  # e.g. 76497LG6JJHAVAL0862520201159_base.I2c
  echo "AAE-v1-data: $(wc -l $baseprep | awk '{print $1}' )"
  while read rq; do
    rqxml=$( echo "$rq" | awk '{ print $1 }' | sed 's/_pre/_base/' )
    rqfile=$( mktemp $splitdir/$rqxml.XXX ) || exit 1
    echo "$rq" | awk -F'_pre ' '{ print $2 }' > $rqfile
  done < $baseprep
}

get_newtest_rq(){
  # split test accruals line-by-line into individual files
  # e.g. 76497LG6JJHAVAL0862520201159_test.JHR
  echo "AAE-v2-data: $(wc -l $testprep | awk '{print $1}' )"
  while read rq; do
    rqxml=$( echo "$rq" | awk '{ print $1 }' | sed 's/_pre/_test/' )
    rqfile=$( mktemp $splitdir/$rqxml.XXX ) || exit 1
    echo "$rq" | awk -F'_pre ' '{ print $2 }' > $rqfile
  done < $testprep
}

compare_accruals(){
  # iterate over the "baseline" accruals "$rqbase"
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
  set +e #prevent exit on first mismatch
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



################################################################################
#  __  ____  __ _           _ _  __  __
#  \ \/ /  \/  | |       __| (_)/ _|/ _|___
#   \  /| |\/| | |      / _` | | |_| |_/ __|
#   /  \| |  | | |___  | (_| | |  _|  _\__ \
#  /_/\_\_|  |_|_____|  \__,_|_|_| |_| |___/

examine_diffs(){
  # input: <results-XXXXX.txt>"
  # examines exactly where XML files differ, based on results of "run_comparisons"
  # working directory is $diffdir
  set +e #prevent exit on first mismatch
  dfile=$1
  ddir=$splitdir
  odir=results-diff-$time64
  echo "..writing XML diffs: $odir"
  mkdir $odir
  i=0
  while read z baserq zz testrq zzz
  do
    ((i++))
    padi=$( printf "%04d\n" $i )
    ddiff=$odir/diff-$time64-$padi.txt
    echo "DIFF $baserq || $testrq" >> $ddiff
    sdiff -w220 <( xmllint --format $ddir/$baserq ) <( xmllint --format $ddir/$testrq ) >> $ddiff
  done < <( grep differ $dfile )
}

################################################################################

main $@
exit
