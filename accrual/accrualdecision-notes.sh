#!/bin/bash
# Trace AAE log, correlate ticket event type and AccruePoints call
#set -x #debug
#set -u #warn if unbound variable found
set -e

print_usage(){
  echo "Usage: $0 <airaccrualengine.log* filename>"
  echo "Traces AAE log, correlates ticket event type and AccruePoints call"
}

[ $1 ] || { print_usage ; exit ; }
[ -f $1 ] || { ls $1 ; exit ; }
aae_log=$1
parsed_in_event=$( mktemp /tmp/aae-in.$$.XXXXX ) || exit 1
parsed_out_call=$( mktemp /tmp/aae-out.$$.XXXXX ) || exit 1
joined_proc_trace=$( mktemp `echo $aae_log | sed 's/.gz/.joined-results/'`.XXX-$$ ) || exit 1

# step i � get AAE event_id, and EventType from input TEM
echo "step 1: parse TEM input > $parsed_in_event"
zgrep -h -A99 "Retrieved TicketEvent Message From queue(LQ.ACRP.ACCRUAL.TKTSALES)" $aae_log \
    | sed 's/^ *//' \
    | grep -e "--" -e AAE -e EventType -e TicketNumber \
    | sed -e :a -e '$!N; s/\n//; ta' \
    | sed 's/--/\n/g;s/\[/</g;s/\]/>/g' \
    | awk -F '<|>' '{print $4,$11,$15}' \
    > $parsed_in_event

# step ii � get exit message from AirAccrualsProcessor
echo "step 2: parse AAE processor result > $parsed_out_call"
zgrep "AirAccrualsProcessorImpl" $aae_log \
    | grep -e AccruePoints -e Ignoring | tr -d '[]' | cut -d' ' -f6- \
    > $parsed_out_call

# step iii � join the files from (i) and (ii) using AAE event_id
echo "step 3: join input+result using process id > $joined_proc_trace"
join -j 1 <(sort $parsed_in_event) <(sort $parsed_out_call) \
    > $joined_proc_trace

echo
exit
