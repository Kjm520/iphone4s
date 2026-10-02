// Probe that calls MGCopyAnswer via the LINKED symbol (not dlsym), so a
// fishhook rebind of that symbol takes effect here - used to validate the
// hook dylib before it goes anywhere near the boot daemon.
#include <CoreFoundation/CoreFoundation.h>
#include <stdio.h>

extern CFPropertyListRef MGCopyAnswer(CFStringRef key);

int main(void) {
    const char *keys[] = {"DeviceClass", "ProductType", "TelephonyCapability", NULL};
    for (int i = 0; keys[i]; i++) {
        CFStringRef k = CFStringCreateWithCString(NULL, keys[i], kCFStringEncodingUTF8);
        CFPropertyListRef v = MGCopyAnswer(k);
        printf("%-22s = ", keys[i]);
        if (!v) {
            printf("(null)\n");
        } else if (CFGetTypeID(v) == CFStringGetTypeID()) {
            char b[128];
            CFStringGetCString((CFStringRef)v, b, sizeof(b), kCFStringEncodingUTF8);
            printf("\"%s\"\n", b);
        } else if (CFGetTypeID(v) == CFBooleanGetTypeID()) {
            printf("%s\n", CFBooleanGetValue((CFBooleanRef)v) ? "true" : "false");
        } else {
            printf("(other CF type)\n");
        }
        if (v) CFRelease(v);
        CFRelease(k);
    }
    return 0;
}
