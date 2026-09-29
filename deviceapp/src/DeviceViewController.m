#import "DeviceViewController.h"

#import <CoreLocation/CoreLocation.h>
#import <CoreMotion/CoreMotion.h>
#import <mach/mach.h>
#import <sys/sysctl.h>

#import "PrivateSensors.h"

@interface DeviceViewController () <CLLocationManagerDelegate>
@property (nonatomic, strong) UITextView *readout;
@property (nonatomic, strong) CMMotionManager *motion;
@property (nonatomic, strong) CLLocationManager *compass;
@property (nonatomic, strong) CLHeading *heading;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic) NSUInteger tick;
@property (nonatomic) CFDictionaryRef battery;
@end

@implementation DeviceViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];
    // Same status-bar inset opt-out as the main page (see RootViewController).
    self.automaticallyAdjustsScrollViewInsets = NO;

    self.readout = [[UITextView alloc] initWithFrame:CGRectZero];
    self.readout.backgroundColor = [UIColor blackColor];
    self.readout.textColor = [UIColor colorWithRed:0.25 green:1.0 blue:0.35 alpha:1];
    self.readout.font = [UIFont fontWithName:@"Menlo" size:14];
    self.readout.editable = NO;
    self.readout.selectable = NO;
    self.readout.scrollEnabled = NO;
    [self.view addSubview:self.readout];

    self.motion = [[CMMotionManager alloc] init];
    self.motion.deviceMotionUpdateInterval = 0.05;

    self.compass = [[CLLocationManager alloc] init];
    self.compass.delegate = self;
    self.compass.headingFilter = 1;
    // True heading needs the declination, which needs location permission.
    [self.compass requestWhenInUseAuthorization];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGRect area = self.view.bounds;
    area.origin.y += 20;
    area.size.height -= 20;
    self.readout.frame = CGRectInset(area, 8, 4);
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.motion startDeviceMotionUpdates];
    [self.compass startUpdatingHeading];
    self.timer = [NSTimer scheduledTimerWithTimeInterval:0.25
                                                  target:self
                                                selector:@selector(refresh)
                                                userInfo:nil
                                                 repeats:YES];
    [self refresh];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.timer invalidate];
    self.timer = nil;
    [self.motion stopDeviceMotionUpdates];
    [self.compass stopUpdatingHeading];
}

- (void)dealloc {
    if (_battery) CFRelease(_battery);
}

- (void)locationManager:(CLLocationManager *)manager
       didUpdateHeading:(CLHeading *)newHeading {
    self.heading = newHeading;
}

static NSString *wind16(double deg) {
    static NSString *const names[] = {
        @"N", @"NNE", @"NE", @"ENE", @"E", @"ESE", @"SE", @"SSE",
        @"S", @"SSW", @"SW", @"WSW", @"W", @"WNW", @"NW", @"NNW"
    };
    return names[(int)((deg + 11.25) / 22.5) % 16];
}

- (void)refresh {
    NSMutableString *s = [NSMutableString string];
    [s appendFormat:@"DEVICE BAG v%@\n\n",
        [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"]];

    CLHeading *h = self.heading;
    [s appendString:@"COMPASS\n"];
    if (h) {
        [s appendFormat:@"HDG %3.0f°M", h.magneticHeading];
        if (h.trueHeading >= 0)
            [s appendFormat:@"  %3.0f°T", h.trueHeading];
        [s appendFormat:@"  ±%.0f°  %@\n", h.headingAccuracy,
            wind16(h.magneticHeading)];
        [s appendFormat:@"MAG %+5.1f %+5.1f %+5.1f µT\n", h.x, h.y, h.z];
    } else {
        [s appendString:@"warming up…\n\n"];
    }

    CMDeviceMotion *m = self.motion.deviceMotion;
    [s appendString:@"\nMOTION\n"];
    if (m) {
        double gx = m.gravity.x, gy = m.gravity.y, gz = m.gravity.z;
        double pitch = m.attitude.pitch * 180 / M_PI;
        double roll = m.attitude.roll * 180 / M_PI;
        double tilt = acos(fmax(-1.0, fmin(1.0, -gz))) * 180 / M_PI;
        double ax = m.userAcceleration.x + gx, ay = m.userAcceleration.y + gy,
               az = m.userAcceleration.z + gz;
        [s appendFormat:@"PITCH %+6.1f°  ROLL %+6.1f°\n", pitch, roll];
        [s appendFormat:@"TILT  %5.1f°   G %.2f\n",
            tilt, sqrt(ax * ax + ay * ay + az * az)];
        [s appendFormat:@"ROT %+5.2f %+5.2f %+5.2f r/s\n",
            m.rotationRate.x, m.rotationRate.y, m.rotationRate.z];
    } else {
        [s appendString:@"warming up…\n\n\n"];
    }

    [s appendString:@"\nLIGHT / TEMPERATURES\n"];
    long als = private_als_level();
    if (als >= 0) [s appendFormat:@"ALS %ld\n", als];
    else [s appendString:@"ALS n/a\n"];
    long temps[24];
    int nt = private_temps(temps, 24);
    if (nt > 0) {
        long lo = temps[0], hi = temps[0];
        for (int i = 1; i < nt; i++) {
            if (temps[i] < lo) lo = temps[i];
            if (temps[i] > hi) hi = temps[i];
        }
        [s appendFormat:@"BOARD %ld-%ld°C (%d sensors)\n", lo, hi, nt];
    } else {
        [s appendString:@"BOARD n/a\n"];
    }

    // Registry query throttled to 1 Hz; the rest of the page runs at 4 Hz.
    if (self.tick++ % 4 == 0) {
        if (self.battery) CFRelease(self.battery);
        self.battery = private_battery_copy_props();
    }
    CFDictionaryRef b = self.battery;
    [s appendString:@"\nBATTERY\n"];
    UIDevice *dev = [UIDevice currentDevice];
    dev.batteryMonitoringEnabled = YES;
    [s appendFormat:@"%3.0f%%", dev.batteryLevel * 100];
    if (b) {
        [s appendFormat:@"  %.3fV  %.1f°C  %+ldmA\n",
            cf_dict_long(b, "Voltage", 0) / 1000.0,
            cf_dict_long(b, "Temperature", 0) / 100.0,
            cf_dict_long(b, "InstantAmperage", 0)];
        long design = cf_dict_long(b, "DesignCapacity", 0);
        long raw_max = cf_dict_long(b, "AppleRawMaxCapacity", 0);
        if (design > 0 && raw_max > 0)
            [s appendFormat:@"HEALTH %ld/%ldmAh  %ld%%\n",
                raw_max, design, raw_max * 100 / design];
        [s appendFormat:@"CYCLES %ld   %@\n",
            cf_dict_long(b, "CycleCount", 0),
            cf_dict_bool(b, "IsCharging", false)
                ? @"charging"
                : (cf_dict_bool(b, "ExternalConnected", false) ? @"on power" : @"on battery")];
    } else {
        [s appendString:@"  internals n/a\n\n"];
    }

    [s appendString:@"\nSYSTEM\n"];
    vm_statistics_data_t vm;
    mach_msg_type_number_t count = HOST_VM_INFO_COUNT;
    vm_size_t pagesize = 0;
    host_page_size(mach_host_self(), &pagesize);
    if (host_statistics(mach_host_self(), HOST_VM_INFO,
                        (host_info_t)&vm, &count) == KERN_SUCCESS) {
        uint64_t total = 0;
        size_t len = sizeof(total);
        sysctlbyname("hw.memsize", &total, &len, NULL, 0);
        [s appendFormat:@"RAM  %llu/%llu MB free\n",
            (uint64_t)(vm.free_count + vm.inactive_count) * pagesize / (1024 * 1024),
            total / (1024 * 1024)];
    }
    NSDictionary *fs = [[NSFileManager defaultManager]
        attributesOfFileSystemForPath:@"/var" error:NULL];
    [s appendFormat:@"DISK %.2f GB free\n",
        [fs[NSFileSystemFreeSize] doubleValue] / 1e9];
    double up = [NSProcessInfo processInfo].systemUptime;
    [s appendFormat:@"UP   %dd %02dh %02dm\n",
        (int)(up / 86400), (int)fmod(up / 3600, 24), (int)fmod(up / 60, 60)];

    self.readout.text = s;
}

@end
