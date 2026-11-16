#!/usr/bin/env bash
# Build Apogee from the command line (the VS Code "Monkey C" extension does
# the same thing with a click - see the README).
#
#   tools/build.sh          -> bin/Apogee.prg   copy this to GARMIN/APPS on the watch
#   tools/build.sh store    -> bin/Apogee.iq    upload this to the Connect IQ Store
#
# Needs two environment variables:
#   CIQ_SDK   folder of the Connect IQ SDK (the one containing bin/monkeybrains.jar)
#   CIQ_KEY   your developer key (.der file)
set -euo pipefail
cd "$(dirname "$0")/.."

: "${CIQ_SDK:?Set CIQ_SDK to your Connect IQ SDK folder}"
: "${CIQ_KEY:?Set CIQ_KEY to your developer key (.der)}"

mkdir -p bin
if [ "${1:-}" = "store" ]; then
    java -jar "$CIQ_SDK/bin/monkeybrains.jar" -o bin/Apogee.iq -f monkey.jungle -y "$CIQ_KEY" -e -r -w
    echo "Built bin/Apogee.iq"
else
    java -jar "$CIQ_SDK/bin/monkeybrains.jar" -o bin/Apogee.prg -f monkey.jungle -y "$CIQ_KEY" -d fr55 -r -w
    echo "Built bin/Apogee.prg"
fi
