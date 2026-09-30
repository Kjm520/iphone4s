// Read-only probe: what does MobileGestalt report for the capability keys
// mobactivationd uses to decide has_telephony / should_hactivate? Runs on
// the phone from the home screen; changes nothing.
#include <CoreFoundation/CoreFoundation.h>
#include <dlfcn.h>
#include <stdio.h>

typedef CFPropertyListRef (*MGCopyAnswer_t)(CFStringRef);

static void show(MGCopyAnswer_t MGCopyAnswer, const char *key) {
    CFStringRef k = CFStringCreateWithCString(NULL, key, kCFStringEncodingUTF8);
    CFPropertyListRef v = MGCopyAnswer(k);
    printf("%-28s = ", key);
    if (!v) {
        printf("(null)\n");
    } else if (CFGetTypeID(v) == CFBooleanGetTypeID()) {
        printf("%s\n", CFBooleanGetValue((CFBooleanRef)v) ? "true" : "false");
    } else if (CFGetTypeID(v) == CFStringGetTypeID()) {
        char buf[256];
        CFStringGetCString((CFStringRef)v, buf, sizeof(buf), kCFStringEncodingUTF8);
        printf("\"%s\"\n", buf);
    } else if (CFGetTypeID(v) == CFNumberGetTypeID()) {
        long n = 0; CFNumberGetValue((CFNumberRef)v, kCFNumberLongType, &n);
        printf("%ld\n", n);
    } else {
        printf("(other CF type)\n");
    }
    if (v) CFRelease(v);
    CFRelease(k);
}

int main(void) {
    void *h = dlopen("/usr/lib/libMobileGestalt.dylib", RTLD_NOW);
    if (!h) { printf("dlopen failed: %s\n", dlerror()); return 1; }
    MGCopyAnswer_t MGCopyAnswer = (MGCopyAnswer_t)dlsym(h, "MGCopyAnswer");
    if (!MGCopyAnswer) { printf("no MGCopyAnswer\n"); return 1; }

    const char *keys[] = {
        "TelephonyCapability", "DeviceClass", "ProductType",
        "CarrierInstallCapability", "GasGaugeBatteryCapability",
        "ExternalChargeCapability", "green-tea", NULL
    };
    for (int i = 0; keys[i]; i++) show(MGCopyAnswer, keys[i]);
    return 0;
}
