#!/bin/bash
# Extract AccruePoints RQ XML from AAE log
#set -x #debug
#set -u #warn if unbound variable found
set -e

print_usage(){
  echo "Usage: $0 <airaccrualengine.log* filename>"
  echo "Extract AccruePointsRQ XML from AAE log"
}

[ $1 ] || { print_usage ; exit ; }
[ -f $1 ] || { ls $1 ; exit ; }
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
[ $accrual_events -gt 0 ] || { echo "nothing to extract -- exiting" ; exit 1 ; }
outputfile="$aaelog.$tag.$$.xml"
echo "extracting to $outputfile"

# Now extract the XML
# Tweak output slightly to improve matching between Baseline and Test XML
grep -h -A999 "${match_top}" $aaelog \
  | awk "/${match_top}/,/${match_bot}/" \
  | sed 's/^[ \t]*//g' \
  | tr -d '\n' \
  | sed 's/AirNZ_AccruePointsRQ>2018/AirNZ_AccruePointsRQ>\n2018/g' \
  | sed 's/^2018.*AccruePointsWSV1x8Operation - About to send request to AccruePoints Web Service V1x8 ://g' \
  | sed 's/^2018.*AccruePointsWSV1x8Operation - Sending request to/\n/g' \
  > $outputfile

  #| sed 's/--/\n/g;s/\[/</g;s/\]/>/g' \
#  | awk -F'ns3:BusinessEventId' '{print $1 FS substr($2,1,20) "....</" FS $3 }' \
#  | awk -F'ns3:MessageTime' '{print $1 FS substr($2,1,11) "....</" FS $3 }' \
