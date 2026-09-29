// Jailbreak-only sensor access (ambient light, battery internals) via
// IOKit, loaded with dlopen/dlsym at runtime: no SDK stubs or link-time
// symbols involved, and every call degrades gracefully when denied.
#ifndef PRIVATE_SENSORS_H
#define PRIVATE_SENSORS_H

#include <CoreFoundation/CoreFoundation.h>
#include <stdbool.h>

// Loads IOKit and resolves symbols. Safe to call repeatedly.
bool private_sensors_init(void);

// Ambient light sensor reading (raw lux-ish level), or -1 if unavailable.
long private_als_level(void);

// Board temperature sensors (the 4S has ~15). Fills out[] with deg C
// readings, returns how many. 2026 survey: typical 26-35, charge-circuit
// hot spot ~51.
int private_temps(long *out, int max_count);

// Diagnostic (probe only): print every AppleVendor HID sensor service and
// which event types it currently answers, with their primary values.
void private_hid_scan(void);

// Raw property dictionary of the IOPMPowerSource service (battery), or NULL.
// Caller releases.
CFDictionaryRef private_battery_copy_props(void);

// Convenience: integer property from a CF dictionary, or fallback.
long cf_dict_long(CFDictionaryRef d, const char *key, long fallback);
bool cf_dict_bool(CFDictionaryRef d, const char *key, bool fallback);

#endif
