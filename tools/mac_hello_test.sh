#!/bin/bash
# End-to-end armv7 pipeline test, run on the Mac build server.
set -e
cd ~/ios/build
SDK="$HOME/ios/sdks/iPhoneOS9.3.sdk"

echo '=== TEST 1: Apple ld64 links the Windows-compiled armv7 object ==='
ld -arch armv7 -platform_version ios 8.0 9.3 -syslibroot "$SDK" -lSystem hello.o -o hello_ld
otool -hv hello_ld | tail -2
echo LINK-OK

echo '=== TEST 2: Apple clang 14 compiles armv7 directly ==='
if clang -target armv7-apple-ios8.0 -isysroot "$SDK" -O2 -c hello.c -o hello_mac.o 2>&1; then
    echo COMPILE-OK
    ld -arch armv7 -platform_version ios 8.0 9.3 -syslibroot "$SDK" -lSystem hello_mac.o -o hello_allmac \
        && echo ALLMAC-LINK-OK || echo ALLMAC-LINK-FAILED
else
    echo COMPILE-REFUSED
fi

echo '=== Load commands of the linked binary ==='
otool -l hello_ld | grep -A3 -E 'LC_VERSION_MIN|LC_MAIN|LC_ENCRYPT' || true
