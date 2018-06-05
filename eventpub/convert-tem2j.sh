#!/bin/bash
# Converts TEMv1 xml to json format
#   uses “yq” (based on jq), ref: https://yq.readthedocs.io
# NB: to transform the resulting json, try "jolt"
#   https://github.com/bazaarvoice/jolt
set -xeu
[ $1 ] || { echo "Usage: convert-tem2j.sh <tem-v1x4-xml-file>"; exit; }
temx=$1
temj=$temx.xq.$$.json

# delete unused bits
sed 's,\( xmlns[^>]*\),,g; s,\( xsi:type[^>]*\),,g; s,ns:,,g' $temx \
  | xq . \
  | grep -v TicketBE \
  | grep -v MessageTime \
  | grep -v ChannelInstance \
  | grep -v "EventTime.*T00:00:00.000" \
  > $temj
echo "converted json file: $temj"
