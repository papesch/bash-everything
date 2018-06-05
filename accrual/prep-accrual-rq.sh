#!/bin/bash
# Prep AccruePointsRQ XML for comparison
# Adds unique prefix to each line of the file, to facilitate sorting and comparison.
# e.g. 64832926KBXUHAVAL0862520300404_pre
#
# 1. get-accrual-rq.sh
# 2. prep-accrual-rq.sh
# 3. compare-accrual-rq.sh
#
# Design notes: https://jira.airnz.co.nz/browse/LSB-1030

#set -x #debug
#set -u #warn if unbound variable found
set -e

# input checks
print_usage(){
  echo "Usage: $0 <airaccrualengine.log* filename>"
  echo "Prepare AccruePointsRQ XML file for comparison"
}
[ $1 ] || { print_usage ; exit ; }
[ -f $1 ] || { ls $1 ; exit ; }
[ "$( echo $1|grep "xml" )" == "" ] && { echo "Error: is \$1 an xml-extract?" ; exit ; }
xmldata=$1
preppedfile=$( mktemp ./prep.${xmldata}.XXX ) || exit 1
path_expr="//AirNZ_AccruePointsRQ/Ticket[1]/TicketNumber/text()"
path_expr="$path_expr | //AirNZ_AccruePointsRQ/PNRHeader/PNRReference/text()"
path_expr="$path_expr | //AirNZ_AccruePointsRQ/PNRHeader/CreationDateTime/text()"
path_expr="$path_expr | //AirNZ_AccruePointsRQ/PNRHeader/TransactionType/text()"
path_expr="$path_expr | //AirNZ_AccruePointsRQ/MemberDetails/APMembershipId/text()"

main(){
  grep . ${xmldata} | while read accrualRQ; do
    # strip namespace and known diffs
    thisRQ=$( echo "${accrualRQ}" \
      | sed 's,\( xmlns[^>]*\),,g; s,\( xsi:type[^>]*\),,g; s,ns:,,g' \
      | awk -F'TimeStamp' '{print $1 FS substr($2,1,11) "....</" FS $3 }' \
      | awk -F'TransactionIdentifier' '{print $1 FS substr($2,1,13) "....</" FS $3 }' \
      | awk -F'CreationDateTime' '{print $1 FS substr($2,1,17) "</" FS $3 }' \
      | sed 's,<OfficeOfIssue>.*</AgentsInitials>,,g' \
      | sed 's/<Coupon><CouponNumber>.<\/CouponNumber><CouponStatus>[^F3G9].*<\/Coupon>//' \
      | sed 's,<ScheduledArrivalDateTime>.............................</ScheduledArrivalDateTime>,,g' \
      | sed 's,<ProductCode>...</ProductCode>,,g' )
    uniqueID=$( echo "$thisRQ" | xmllint --xpath "$path_expr" - | tr -cd [:alnum:] )
    echo "${uniqueID}_pre $thisRQ"
  done
  echo
}

echo "extracting to $preppedfile"
main $@ > $preppedfile
