#!/bin/bash
# Probe: what the 9.3 SDK is missing, and what else this Mac has on hand.
SDK="$HOME/ios/sdks/iPhoneOS9.3.sdk"

echo '=== other Xcodes / SDKs on this Mac ==='
ls /Applications | grep -i xcode
ls /Library/Developer/CommandLineTools/SDKs 2>/dev/null
mdfind -name iPhoneOS.sdk 2>/dev/null | head -5

echo '=== sub-libraries libSystem re-exports ==='
grep -o '/usr/lib/system/[a-zA-Z_0-9.]*\.dylib' "$SDK/usr/lib/libSystem.B.tbd" | sort -u > /tmp/want.txt
wc -l < /tmp/want.txt

echo '=== which are missing from the SDK ==='
while read -r d; do
    tbd="$SDK${d%.dylib}.tbd"
    [ -f "$tbd" ] || echo "MISSING: $d"
done < /tmp/want.txt

echo '=== does Apple clang 14 compile armv7? ==='
cd ~/ios/build
clang -target armv7-apple-ios8.0 -isysroot "$SDK" -O2 -c hello.c -o hello_mac.o 2>&1 \
    && echo COMPILE-OK || echo COMPILE-REFUSED
