#include "PrivateSensors.h"

#include <dlfcn.h>
#include <stdio.h>              // private_hid_scan prints its survey

// --- minimal private IOKit surface, resolved at runtime ---------------------

typedef void *IOHIDEventSystemClientRef;
typedef void *IOHIDEventRef;
typedef uint32_t io_object_t_;

// Constants verified against this device by `probe hid` (2026-09-29):
// usage 4 = ALS (event type 12), usage 5 = temperature (event type 15).
// The proximity sensor exists but stays powered down unless the OS's
// screen-blanking machinery enables it, so it is deliberately not read.
enum {
    kHIDPage_AppleVendor = 0xff00,
    kHIDUsage_AppleVendor_ALS = 4,
    kHIDUsage_AppleVendor_Temperature = 5,
    kIOHIDEventTypeAmbientLightSensor = 12,
    kIOHIDEventTypeTemperature = 15,
    // field = (type << 16) | offset
    kIOHIDEventFieldALSLevel = kIOHIDEventTypeAmbientLightSensor << 16,
    kIOHIDEventFieldTemperatureLevel = kIOHIDEventTypeTemperature << 16,
};

static IOHIDEventSystemClientRef (*pClientCreate)(CFAllocatorRef);
static void (*pClientSetMatching)(IOHIDEventSystemClientRef, CFDictionaryRef);
static CFArrayRef (*pClientCopyServices)(IOHIDEventSystemClientRef);
static IOHIDEventRef (*pServiceCopyEvent)(const void *, int64_t, int32_t, int64_t);
static CFIndex (*pEventGetIntegerValue)(IOHIDEventRef, int32_t);
static CFTypeRef (*pServiceCopyProperty)(const void *, CFStringRef);
static CFMutableDictionaryRef (*pServiceMatching)(const char *);
static io_object_t_ (*pGetMatchingService)(uint32_t, CFDictionaryRef);
static int (*pEntryCreateCFProperties)(io_object_t_, CFMutableDictionaryRef *,
                                       CFAllocatorRef, uint32_t);
static int (*pObjectRelease)(io_object_t_);

static bool resolved;

bool private_sensors_init(void) {
    if (resolved) return true;
    void *iokit = dlopen(
        "/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY);
    if (!iokit) return false;
#define RESOLVE(var, name) do { \
        *(void **)&(var) = dlsym(iokit, name); \
        if (!(var)) return false; \
    } while (0)
    RESOLVE(pClientCreate, "IOHIDEventSystemClientCreate");
    RESOLVE(pClientSetMatching, "IOHIDEventSystemClientSetMatching");
    RESOLVE(pClientCopyServices, "IOHIDEventSystemClientCopyServices");
    RESOLVE(pServiceCopyEvent, "IOHIDServiceClientCopyEvent");
    RESOLVE(pEventGetIntegerValue, "IOHIDEventGetIntegerValue");
    RESOLVE(pServiceCopyProperty, "IOHIDServiceClientCopyProperty");
    RESOLVE(pServiceMatching, "IOServiceMatching");
    RESOLVE(pGetMatchingService, "IOServiceGetMatchingService");
    RESOLVE(pEntryCreateCFProperties, "IORegistryEntryCreateCFProperties");
    RESOLVE(pObjectRelease, "IOObjectRelease");
#undef RESOLVE
    resolved = true;
    return true;
}

// --- HID sensor services ----------------------------------------------------

// First AppleVendor service with the given primary usage. The backing client
// and services array are intentionally kept alive for the process lifetime.
static const void *find_service(int usage) {
    IOHIDEventSystemClientRef client = pClientCreate(kCFAllocatorDefault);
    if (!client) return NULL;
    int page = kHIDPage_AppleVendor;
    CFNumberRef pageN = CFNumberCreate(NULL, kCFNumberIntType, &page);
    CFNumberRef usageN = CFNumberCreate(NULL, kCFNumberIntType, &usage);
    CFStringRef keys[] = { CFSTR("PrimaryUsagePage"), CFSTR("PrimaryUsage") };
    CFTypeRef vals[] = { pageN, usageN };
    CFDictionaryRef match = CFDictionaryCreate(NULL,
        (const void **)keys, (const void **)vals, 2,
        &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    pClientSetMatching(client, match);
    CFRelease(match);
    CFRelease(pageN);
    CFRelease(usageN);

    CFArrayRef services = pClientCopyServices(client);
    if (services && CFArrayGetCount(services) > 0)
        return CFArrayGetValueAtIndex(services, 0);
    return NULL;
}

long private_als_level(void) {
    static const void *svc;
    if (!private_sensors_init()) return -1;
    if (!svc) svc = find_service(kHIDUsage_AppleVendor_ALS);
    if (!svc) return -1;
    IOHIDEventRef ev = pServiceCopyEvent(svc, kIOHIDEventTypeAmbientLightSensor, 0, 0);
    if (!ev) return -1;
    long level = pEventGetIntegerValue(ev, kIOHIDEventFieldALSLevel);
    CFRelease(ev);
    return level;
}

int private_temps(long *out, int max_count) {
    static CFArrayRef services;      // kept alive for the process lifetime
    if (!private_sensors_init()) return 0;
    if (!services) {
        IOHIDEventSystemClientRef client = pClientCreate(kCFAllocatorDefault);
        if (!client) return 0;
        int page = kHIDPage_AppleVendor, usage = kHIDUsage_AppleVendor_Temperature;
        CFNumberRef pageN = CFNumberCreate(NULL, kCFNumberIntType, &page);
        CFNumberRef usageN = CFNumberCreate(NULL, kCFNumberIntType, &usage);
        CFStringRef keys[] = { CFSTR("PrimaryUsagePage"), CFSTR("PrimaryUsage") };
        CFTypeRef vals[] = { pageN, usageN };
        CFDictionaryRef match = CFDictionaryCreate(NULL,
            (const void **)keys, (const void **)vals, 2,
            &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        pClientSetMatching(client, match);
        CFRelease(match);
        CFRelease(pageN);
        CFRelease(usageN);
        services = pClientCopyServices(client);
    }
    long n = services ? CFArrayGetCount(services) : 0;
    int filled = 0;
    for (long i = 0; i < n && filled < max_count; i++) {
        IOHIDEventRef ev = pServiceCopyEvent(
            CFArrayGetValueAtIndex(services, i),
            kIOHIDEventTypeTemperature, 0, 0);
        if (!ev) continue;
        out[filled++] = pEventGetIntegerValue(ev, kIOHIDEventFieldTemperatureLevel);
        CFRelease(ev);
    }
    return filled;
}

void private_hid_scan(void) {
    if (!private_sensors_init()) return;
    IOHIDEventSystemClientRef client = pClientCreate(kCFAllocatorDefault);
    if (!client) return;
    int page = kHIDPage_AppleVendor;
    CFNumberRef pageN = CFNumberCreate(NULL, kCFNumberIntType, &page);
    CFStringRef keys[] = { CFSTR("PrimaryUsagePage") };
    CFTypeRef vals[] = { pageN };
    CFDictionaryRef match = CFDictionaryCreate(NULL,
        (const void **)keys, (const void **)vals, 1,
        &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    pClientSetMatching(client, match);
    CFRelease(match);
    CFRelease(pageN);

    CFArrayRef services = pClientCopyServices(client);
    long n = services ? CFArrayGetCount(services) : 0;
    for (long i = 0; i < n; i++) {
        const void *svc = CFArrayGetValueAtIndex(services, i);
        long usage = -1;
        CFTypeRef u = pServiceCopyProperty(svc, CFSTR("PrimaryUsage"));
        if (u && CFGetTypeID(u) == CFNumberGetTypeID())
            CFNumberGetValue((CFNumberRef)u, kCFNumberLongType, &usage);
        if (u) CFRelease(u);
        printf("service[%ld] usage=%ld :", i, usage);
        for (int type = 0; type <= 30; type++) {
            IOHIDEventRef ev = pServiceCopyEvent(svc, type, 0, 0);
            if (!ev) continue;
            printf(" t%d=%ld", type,
                   (long)pEventGetIntegerValue(ev, type << 16));
            CFRelease(ev);
        }
        printf("\n");
    }
    if (services) CFRelease(services);
    CFRelease(client);
    fflush(stdout);
}

// --- battery ----------------------------------------------------------------

CFDictionaryRef private_battery_copy_props(void) {
    if (!private_sensors_init()) return NULL;
    io_object_t_ svc = pGetMatchingService(0, pServiceMatching("IOPMPowerSource"));
    if (!svc) return NULL;
    CFMutableDictionaryRef props = NULL;
    pEntryCreateCFProperties(svc, &props, kCFAllocatorDefault, 0);
    pObjectRelease(svc);
    return props;
}

long cf_dict_long(CFDictionaryRef d, const char *key, long fallback) {
    if (!d) return fallback;
    CFStringRef k = CFStringCreateWithCString(NULL, key, kCFStringEncodingUTF8);
    CFTypeRef v = CFDictionaryGetValue(d, k);
    CFRelease(k);
    long out = fallback;
    if (v && CFGetTypeID(v) == CFNumberGetTypeID())
        CFNumberGetValue((CFNumberRef)v, kCFNumberLongType, &out);
    return out;
}

bool cf_dict_bool(CFDictionaryRef d, const char *key, bool fallback) {
    if (!d) return fallback;
    CFStringRef k = CFStringCreateWithCString(NULL, key, kCFStringEncodingUTF8);
    CFTypeRef v = CFDictionaryGetValue(d, k);
    CFRelease(k);
    if (v && CFGetTypeID(v) == CFBooleanGetTypeID())
        return CFBooleanGetValue((CFBooleanRef)v);
    return fallback;
}
