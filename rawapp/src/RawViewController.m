// GPS Raw: every position and compass number the hardware offers, as plain
// text, updating once a second. Deliberately zero interaction - nothing to
// tap, nothing to break, nothing to learn.
#import "RawViewController.h"

#import <CoreLocation/CoreLocation.h>

#import "Geo.h"

@interface RawViewController () <CLLocationManagerDelegate>
@property (nonatomic, strong) CLLocationManager *locationManager;
@property (nonatomic, strong) CLLocation *fix;
@property (nonatomic, strong) CLHeading *heading;
@property (nonatomic, strong) UITextView *readout;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, copy) NSString *statusLine;
@end

@implementation RawViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];

    self.readout = [[UITextView alloc] init];
    self.readout.backgroundColor = [UIColor blackColor];
    self.readout.textColor = [UIColor colorWithRed:0.25 green:1.0 blue:0.35 alpha:1];
    self.readout.font = [UIFont fontWithName:@"Menlo" size:15];
    self.readout.editable = NO;
    self.readout.selectable = NO;
    self.readout.scrollEnabled = NO;
    self.readout.textContainerInset = UIEdgeInsetsZero;
    [self.view addSubview:self.readout];

    self.statusLine = @"starting";
    self.locationManager = [[CLLocationManager alloc] init];
    self.locationManager.delegate = self;
    self.locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation;
    self.locationManager.distanceFilter = kCLDistanceFilterNone;
    self.locationManager.headingFilter = 1;
    [self.locationManager requestWhenInUseAuthorization];
    [self.locationManager startUpdatingLocation];
    [self.locationManager startUpdatingHeading];

    self.timer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                  target:self
                                                selector:@selector(refresh)
                                                userInfo:nil
                                                 repeats:YES];
    [self refresh];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGRect area = self.view.bounds;
    area.origin.y += 22;
    area.size.height -= 22;
    self.readout.frame = CGRectInset(area, 8, 4);
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
    [s appendFormat:@"GPS BAG  %@\n\n", self.statusLine];

    CLLocation *fix = self.fix;
    if (fix) {
        CLLocationCoordinate2D c = fix.coordinate;
        char la[20], lo[20], mgrs[16];
        geo_format_dms(c.latitude, true, la);
        geo_format_dms(c.longitude, false, lo);
        geo_to_mgrs(c.latitude, c.longitude, mgrs);
        NSString *m = [NSString stringWithUTF8String:mgrs];

        [s appendFormat:@"LAT  %+11.6f°\n", c.latitude];
        [s appendFormat:@"LON  %+11.6f°\n\n", c.longitude];
        // Never %s for these: NSString reads C strings as Mac Roman, which
        // renders the UTF-8 degree sign as "¬∞".
        [s appendFormat:@"     %@\n     %@\n\n",
            [NSString stringWithUTF8String:la],
            [NSString stringWithUTF8String:lo]];
        [s appendFormat:@"MGRS %@ %@ %@ %@\n\n",
            [m substringToIndex:3],
            [m substringWithRange:NSMakeRange(3, 2)],
            [m substringWithRange:NSMakeRange(5, 5)],
            [m substringWithRange:NSMakeRange(10, 5)]];
        [s appendFormat:@"ALT  %.0f m", fix.altitude];
        if (fix.verticalAccuracy > 0)
            [s appendFormat:@" ±%.0f", fix.verticalAccuracy];
        [s appendString:@"\n"];
        [s appendFormat:@"ACC  ±%.0f m\n", fix.horizontalAccuracy];
        [s appendFormat:@"SPD  %@\n", fix.speed >= 0
            ? [NSString stringWithFormat:@"%.1f km/h", fix.speed * 3.6] : @"---"];
        [s appendFormat:@"CRS  %@\n", fix.course >= 0
            ? [NSString stringWithFormat:@"%03.0f°", fix.course] : @"---"];
        [s appendFormat:@"FIX  %.0f s\n\n", -[fix.timestamp timeIntervalSinceNow]];
    } else {
        [s appendString:@"waiting for fix…\n\n\n\n\n\n\n\n\n\n\n"];
    }

    CLHeading *h = self.heading;
    if (h) {
        [s appendFormat:@"HDG  %03.0f°M", h.magneticHeading];
        if (h.trueHeading >= 0)
            [s appendFormat:@"  %03.0f°T", h.trueHeading];
        [s appendFormat:@"  %@\n", wind16(h.magneticHeading)];
        if (h.headingAccuracy >= 0)
            [s appendFormat:@"     ±%.0f°\n", h.headingAccuracy];
        [s appendFormat:@"MAG  %+5.1f %+5.1f %+5.1f µT\n", h.x, h.y, h.z];
    } else {
        [s appendString:@"HDG  ---\n"];
    }
    self.readout.text = s;
}

#pragma mark - CLLocationManagerDelegate

- (void)locationManager:(CLLocationManager *)manager
     didUpdateLocations:(NSArray *)locations {
    self.fix = [locations lastObject];
    self.statusLine = @"tracking";
}

- (void)locationManager:(CLLocationManager *)manager
       didUpdateHeading:(CLHeading *)newHeading {
    self.heading = newHeading;
}

- (void)locationManager:(CLLocationManager *)manager
       didFailWithError:(NSError *)error {
    if (error.code == kCLErrorLocationUnknown) {
        self.statusLine = @"searching…";
    } else if (error.code == kCLErrorDenied) {
        self.statusLine = @"auth: DENIED";
    } else {
        self.statusLine = [NSString stringWithFormat:@"error %ld", (long)error.code];
    }
}

- (void)locationManager:(CLLocationManager *)manager
        didChangeAuthorizationStatus:(CLAuthorizationStatus)status {
    if (status == kCLAuthorizationStatusNotDetermined)
        self.statusLine = @"auth: not determined";
}

@end
