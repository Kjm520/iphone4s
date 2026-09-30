// Scoped MobileGestalt shim for mobactivationd only (loaded via
// DYLD_INSERT_LIBRARIES in that one daemon's launchd plist). It makes the
// activation daemon see a non-cellular DeviceClass so it takes its own
// built-in offline ("hactivate") path instead of fetching a baseband
// activation ticket from Apple every boot. Nothing else on the system is
// affected, and removing the plist line fully reverts it.
//
// Uses fishhook (rebind in a constructor, after dyld init) rather than a
// dyld interpose, because CoreFoundation queries MobileGestalt extremely
// early and a global interpose crashes before the process is ready.
#include <CoreFoundation/CoreFoundation.h>
#include <stdio.h>

#include "fishhook.h"

static CFPropertyListRef (*orig_MGCopyAnswer)(CFStringRef);

static CFPropertyListRef my_MGCopyAnswer(CFStringRef key) {
    // The daemon reads MobileGestalt "ShouldHactivate" to decide whether to
    // activate offline. Force it true so a baseband device takes the same
    // no-server path Wi-Fi-only devices use. Scoped to this daemon only.
    if (key && CFGetTypeID(key) == CFStringGetTypeID() &&
        CFEqual(key, CFSTR("ShouldHactivate"))) {
        return (CFPropertyListRef)CFRetain(kCFBooleanTrue);
    }
    return orig_MGCopyAnswer ? orig_MGCopyAnswer(key) : NULL;
}

__attribute__((constructor))
static void actfix_init(void) {
    // Proof-of-load marker (also confirms DYLD_INSERT is honored here).
    FILE *f = fopen("/tmp/actfix_loaded", "w");
    if (f) { fputs("loaded\n", f); fclose(f); }
    struct rebinding r = {"MGCopyAnswer", (void *)my_MGCopyAnswer,
                          (void **)&orig_MGCopyAnswer};
    rebind_symbols(&r, 1);
}
