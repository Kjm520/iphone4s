// Field probe: run on the phone over SSH to learn what the private sensor
// interfaces actually return on this device/OS before the app relies on them.
//
//   /tmp/probe            original ALS + battery survey
//   /tmp/probe hid        enumerate HID sensor services, scan event types
#include <stdio.h>
#include <string.h>
#include <unistd.h>

#include "../src/PrivateSensors.h"

static void hid_survey(void) {
    printf("uid=%d init=%s\n", (int)getuid(),
           private_sensors_init() ? "ok" : "FAILED");
    // 12 samples over ~6 s: cover / uncover the sensor while this runs.
    for (int i = 0; i < 12; i++) {
        private_hid_scan();
        usleep(500 * 1000);
    }
}

int main(int argc, char **argv) {
    if (argc > 1 && strcmp(argv[1], "hid") == 0) {
        hid_survey();
        return 0;
    }

    printf("probe uid=%d\n", (int)getuid());
    printf("init: %s\n", private_sensors_init() ? "ok" : "FAILED");

    for (int i = 0; i < 5; i++) {
        printf("als[%d] = %ld\n", i, private_als_level());
        usleep(300 * 1000);
    }

    CFDictionaryRef bat = private_battery_copy_props();
    if (!bat) {
        printf("battery: no IOPMPowerSource\n");
        return 0;
    }
    printf("battery properties:\n");
    CFShow(bat);            // full dump to stderr
    CFRelease(bat);
    return 0;
}
