#import "RootViewController.h"

#import <CoreLocation/CoreLocation.h>

#import "ArrowView.h"
#import "Geo.h"
#import "RoseView.h"
#import "StatusWriter.h"
#import "WaypointListViewController.h"
#import "WaypointStore.h"

typedef NS_ENUM(NSInteger, CoordFormat) {
    CoordFormatDecimal,
    CoordFormatDMS,
    CoordFormatMGRS,
    CoordFormatCount
};

static NSString *const kTargetKey = @"targetWaypoint";
static NSString *const kFormatKey = @"coordFormat";

@interface RootViewController () <CLLocationManagerDelegate>
@property (nonatomic, strong) CLLocationManager *locationManager;
@property (nonatomic, strong) CLLocation *lastFix;
@property (nonatomic, strong) CLHeading *lastHeading;
@property (nonatomic, strong) UITextView *posView;
@property (nonatomic, strong) UILabel *navLabel;
@property (nonatomic, strong) ArrowView *arrow;
@property (nonatomic, strong) RoseView *rose;
@property (nonatomic, strong) UILabel *infoLabel;
@property (nonatomic, strong) UIButton *markButton;
@property (nonatomic, strong) UIButton *targetButton;
@property (nonatomic, strong) NSTimer *refreshTimer;
@property (nonatomic, copy) NSString *statusLine;
@property (nonatomic) CoordFormat format;
@property (nonatomic, strong) Waypoint *target;
@property (nonatomic) NSUInteger tick;
// Continuous (unwrapped) arrow angle so rotation always takes the short arc;
// snapping across ~180 deg makes an affine rotation collapse through zero,
// which reads as a 3D flip.
@property (nonatomic) double shownAngleRad;
@property (nonatomic) double roseAngleRad;
@end

@implementation RootViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];
    // iOS may silently add a status-bar-high contentInset to the first
    // scroll view (the UITextView), shifting text down 20pt and clipping
    // the last line. We lay out explicitly.
    self.automaticallyAdjustsScrollViewInsets = NO;
    UIColor *green = [UIColor colorWithRed:0.25 green:1.0 blue:0.35 alpha:1];

    self.posView = [[UITextView alloc] init];
    self.posView.backgroundColor = [UIColor blackColor];
    self.posView.textColor = green;
    self.posView.font = [UIFont fontWithName:@"Menlo" size:16];
    self.posView.editable = NO;
    self.posView.selectable = NO;
    self.posView.scrollEnabled = NO;
    // No hidden padding: the frame math below counts on line height alone
    // (8 lines of Menlo 16 at ~19 pt each).
    self.posView.textContainerInset = UIEdgeInsetsZero;
    [self.posView addGestureRecognizer:[[UITapGestureRecognizer alloc]
        initWithTarget:self action:@selector(cycleFormat)]];
    [self.view addSubview:self.posView];

    self.rose = [[RoseView alloc] initWithFrame:CGRectZero];
    [self.view addSubview:self.rose];
    self.arrow = [[ArrowView alloc] initWithFrame:CGRectZero];
    [self.view addSubview:self.arrow];        // dart rides above the card

    self.navLabel = [[UILabel alloc] init];
    self.navLabel.font = [UIFont fontWithName:@"Menlo" size:15];
    self.navLabel.textColor = green;
    self.navLabel.numberOfLines = 3;
    self.navLabel.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:self.navLabel];

    self.infoLabel = [[UILabel alloc] init];
    self.infoLabel.font = [UIFont fontWithName:@"Menlo" size:12];
    self.infoLabel.textColor = [UIColor grayColor];
    self.infoLabel.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:self.infoLabel];

    self.markButton = [self buttonTitled:@"MARK" action:@selector(markTapped)];
    self.targetButton = [self buttonTitled:@"PINS" action:@selector(pinsTapped)];

    self.statusLine = @"starting";
    self.format = (CoordFormat)([[NSUserDefaults standardUserDefaults]
                                 integerForKey:kFormatKey] % CoordFormatCount);
    [self restoreTarget];

    [UIDevice currentDevice].batteryMonitoringEnabled = YES;

    self.locationManager = [[CLLocationManager alloc] init];
    self.locationManager.delegate = self;
    self.locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation;
    self.locationManager.distanceFilter = kCLDistanceFilterNone;
    self.locationManager.headingFilter = 2;
    [self.locationManager requestWhenInUseAuthorization];
    [self.locationManager startUpdatingLocation];
    [self.locationManager startUpdatingHeading];

    // 1 Hz redraw so fix age counts up even without new fixes; the root VC
    // lives for the whole process, so the timer's strong ref is fine.
    self.refreshTimer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                         target:self
                                                       selector:@selector(refresh)
                                                       userInfo:nil
                                                        repeats:YES];

    // Map Bag (or an SSH session) may edit the waypoints file while we are
    // in the background; pick up the changes on return.
    [[NSNotificationCenter defaultCenter]
        addObserver:self selector:@selector(reloadFromDisk)
               name:UIApplicationWillEnterForegroundNotification object:nil];
    [self refresh];
}

- (void)reloadFromDisk {
    [[WaypointStore shared] reload];
    [self restoreTarget];              // re-resolve by name; nil if deleted
    [self refresh];
}

- (UIButton *)buttonTitled:(NSString *)title action:(SEL)action {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    [b setTitle:title forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont fontWithName:@"Menlo-Bold" size:16];
    [b setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    b.backgroundColor = [UIColor colorWithRed:0.25 green:1.0 blue:0.35 alpha:1];
    b.layer.cornerRadius = 6;
    [b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:b];
    return b;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat w = self.view.bounds.size.width;
    CGFloat h = self.view.bounds.size.height;
    // The info line and buttons are pinned to the bottom; everything above
    // flows from the MEASURED height of the text, so a wrapped line pushes
    // the arrow down into the slack instead of clipping the last line.
    self.infoLabel.frame = CGRectMake(8, h - 88, w - 16, 16);
    CGFloat bw = (w - 24) / 2;
    self.markButton.frame = CGRectMake(8, h - 64, bw, 56);
    self.targetButton.frame = CGRectMake(16 + bw, h - 64, bw, 56);

    CGFloat posH = ceil([self.posView sizeThatFits:
                         CGSizeMake(w - 16, CGFLOAT_MAX)].height);
    // 150pt rose card + 6 gap + 60 nav + 4 minimum pad; keep it all visible.
    CGFloat maxPosH = (h - 88) - (150 + 6 + 60 + 4) - 22;
    posH = fmin(posH, maxPosH);
    self.posView.frame = CGRectMake(8, 22, w - 16, posH);

    // Center the rose + nav group in the leftover space so the gaps stay
    // balanced as the text block grows or shrinks a line.
    CGFloat groupH = 150 + 6 + 60;
    CGFloat groupTop = 22 + posH;
    CGFloat y = groupTop + fmax(4, ((h - 88) - groupTop - groupH) / 2);
    // Position via bounds + center, never frame: setting a frame on a
    // rotated view is undefined and shears the shape into a sliver.
    self.rose.bounds = CGRectMake(0, 0, 150, 150);
    self.rose.center = CGPointMake(w / 2, y + 75);
    self.arrow.bounds = CGRectMake(0, 0, 96, 96);
    self.arrow.center = self.rose.center;
    self.navLabel.frame = CGRectMake(8, y + 150 + 6, w - 16, 60);
}

#pragma mark - formatting

- (NSString *)coordBlockFor:(CLLocation *)fix {
    CLLocationCoordinate2D c = fix.coordinate;
    switch (self.format) {
        case CoordFormatDecimal:
            return [NSString stringWithFormat:
                    @"LAT %+11.6f°\nLON %+11.6f°", c.latitude, c.longitude];
        case CoordFormatDMS: {
            char la[20], lo[20];
            geo_format_dms(c.latitude, true, la);
            geo_format_dms(c.longitude, false, lo);
            // Never %s: NSString reads those bytes as Mac Roman, turning
            // the UTF-8 degree sign (C2 B0) into a literal "¬∞".
            return [NSString stringWithFormat:@"LAT %@\nLON %@",
                    [NSString stringWithUTF8String:la],
                    [NSString stringWithUTF8String:lo]];
        }
        case CoordFormatMGRS: {
            char m[16];
            geo_to_mgrs(c.latitude, c.longitude, m);
            NSString *s = [NSString stringWithUTF8String:m];
            // spaced for reading aloud / writing down
            return [NSString stringWithFormat:@"MGRS %@ %@ %@\n     %@ %@",
                    [s substringToIndex:3],
                    [s substringWithRange:NSMakeRange(3, 2)],
                    [s substringWithRange:NSMakeRange(5, 5)],
                    [s substringWithRange:NSMakeRange(10, 5)],
                    @"(1 m grid)"];
        }
        default:
            return @"";
    }
}

- (void)refresh {
    CLLocation *fix = self.lastFix;
    NSMutableString *s = [NSMutableString string];
    [s appendFormat:@"TRACK BAG v%@  %@\n",
        [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"],
        self.statusLine];

    if (fix) {
        [s appendFormat:@"\n%@\n\n", [self coordBlockFor:fix]];
        [s appendFormat:@"ALT %5.0fm", fix.altitude];
        if (fix.verticalAccuracy > 0)
            [s appendFormat:@" ±%.0f", fix.verticalAccuracy];
        [s appendFormat:@"   ACC ±%.0fm\n", fix.horizontalAccuracy];
        if (fix.speed >= 0)
            [s appendFormat:@"SPD %5.1fkm/h", fix.speed * 3.6];
        if (fix.course >= 0)
            [s appendFormat:@"  CRS %3.0f°", fix.course];
        [s appendString:@"\n(tap coords = format)"];
    } else {
        [s appendString:@"\nwaiting for fix…\n\ncold start can take\nminutes under open sky"];
    }
    if (![s isEqualToString:self.posView.text]) {
        self.posView.text = s;
        [self.view setNeedsLayout];      // content height may have changed
    }

    [self refreshNav:fix];
    [self refreshInfo:fix];
    if (++self.tick % 5 == 0) [self writeStatus:fix];
}

// Rotate a layer along the shortest arc to the target angle, animating the
// scalar angle (transform.rotation.z), never the matrix: matrix
// interpolation across a ~180 degree turn passes through a degenerate
// transform that squashes the shape into a line. Returns the new
// continuous (unwrapped) angle for the caller to keep.
- (double)spinLayer:(CALayer *)layer shownAngle:(double)prev
          toDegrees:(double)deg {
    double target = deg * M_PI / 180.0;
    double delta = fmod(target - prev, 2.0 * M_PI);
    if (delta > M_PI) delta -= 2.0 * M_PI;
    if (delta < -M_PI) delta += 2.0 * M_PI;
    double next = prev + delta;

    CABasicAnimation *spin =
        [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
    spin.fromValue = @(prev);
    spin.toValue = @(next);
    spin.duration = 0.25;
    spin.timingFunction =
        [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
    layer.transform = CATransform3DMakeRotation(next, 0, 0, 1);
    [layer addAnimation:spin forKey:@"spin"];
    return next;
}

- (void)pointArrowTo:(double)deg live:(BOOL)live {
    self.shownAngleRad = [self spinLayer:self.arrow.layer
                              shownAngle:self.shownAngleRad toDegrees:deg];
    self.arrow.color = live
        ? [UIColor colorWithRed:0.25 green:1.0 blue:0.35 alpha:1]
        : [UIColor darkGrayColor];
}

- (void)refreshNav:(CLLocation *)fix {
    // The compass card tracks heading whenever the compass is alive,
    // target or not: N on the ring always points at real north.
    double heading = -1;
    if (self.lastHeading) {
        heading = self.lastHeading.trueHeading >= 0
                ? self.lastHeading.trueHeading : self.lastHeading.magneticHeading;
    }
    if (heading >= 0) {
        self.roseAngleRad = [self spinLayer:self.rose.layer
                                 shownAngle:self.roseAngleRad
                                  toDegrees:-heading];
        self.rose.live = YES;
    } else {
        [self.rose.layer removeAnimationForKey:@"spin"];
        self.rose.layer.transform = CATransform3DIdentity;
        self.roseAngleRad = 0;
        self.rose.live = NO;
    }

    Waypoint *t = self.target;
    if (!t || !fix) {
        [self.arrow.layer removeAnimationForKey:@"spin"];
        self.arrow.layer.transform = CATransform3DIdentity;
        self.shownAngleRad = 0;
        self.arrow.color = [UIColor darkGrayColor];
        self.navLabel.text = t
            ? [NSString stringWithFormat:@"→ %@ (no fix)", t.name]
            : @"no target — pick from PINS\n(Map Bag adds & edits pins)";
        return;
    }
    CLLocation *dest = [[CLLocation alloc] initWithLatitude:t.lat longitude:t.lon];
    double dist = [fix distanceFromLocation:dest];
    double brg = geo_initial_bearing(fix.coordinate.latitude, fix.coordinate.longitude,
                                     t.lat, t.lon);
    NSString *distStr = dist < 1000
        ? [NSString stringWithFormat:@"%.0f m", dist]
        : [NSString stringWithFormat:@"%.2f km", dist / 1000.0];

    if (heading >= 0) {
        // Arrow points at the target when the phone's top edge points
        // where the user is facing.
        [self pointArrowTo:brg - heading live:YES];
    } else {
        [self pointArrowTo:brg live:NO];
    }
    self.navLabel.text = [NSString stringWithFormat:@"→ %@\n%@   BRG %03.0f°T",
                          t.name, distStr, brg];
}

- (void)refreshInfo:(CLLocation *)fix {
    UIDevice *dev = [UIDevice currentDevice];
    NSString *charge = dev.batteryLevel >= 0
        ? [NSString stringWithFormat:@"%.0f%%", dev.batteryLevel * 100] : @"?";
    if (dev.batteryState == UIDeviceBatteryStateCharging ||
        dev.batteryState == UIDeviceBatteryStateFull) charge = [charge stringByAppendingString:@"+"];
    NSString *age = fix
        ? [NSString stringWithFormat:@"%.0fs", -[fix.timestamp timeIntervalSinceNow]] : @"-";
    NSString *hdg = self.lastHeading
        ? [NSString stringWithFormat:@"%.0f°", self.lastHeading.magneticHeading] : @"-";
    self.infoLabel.text = [NSString stringWithFormat:@"batt %@ | fix %@ | hdg %@M",
                           charge, age, hdg];
}

- (void)writeStatus:(CLLocation *)fix {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    d[@"time"] = @([[NSDate date] timeIntervalSince1970]);
    d[@"battery"] = @([UIDevice currentDevice].batteryLevel);
    if (fix) {
        char m[16];
        geo_to_mgrs(fix.coordinate.latitude, fix.coordinate.longitude, m);
        d[@"lat"] = @(fix.coordinate.latitude);
        d[@"lon"] = @(fix.coordinate.longitude);
        d[@"alt_m"] = @(fix.altitude);
        d[@"acc_m"] = @(fix.horizontalAccuracy);
        d[@"speed_kmh"] = @(fix.speed >= 0 ? fix.speed * 3.6 : -1);
        d[@"course"] = @(fix.course);
        d[@"fix_age_s"] = @(-[fix.timestamp timeIntervalSinceNow]);
        d[@"mgrs"] = [NSString stringWithUTF8String:m];
    }
    Waypoint *t = self.target;
    if (t && fix) {
        CLLocation *dest = [[CLLocation alloc] initWithLatitude:t.lat longitude:t.lon];
        d[@"target"] = @{ @"name": t.name,
                          @"dist_m": @([fix distanceFromLocation:dest]),
                          @"bearing": @(geo_initial_bearing(
                              fix.coordinate.latitude, fix.coordinate.longitude,
                              t.lat, t.lon)) };
    }
    [StatusWriter write:d];
}

#pragma mark - actions

- (void)cycleFormat {
    self.format = (self.format + 1) % CoordFormatCount;
    [[NSUserDefaults standardUserDefaults] setInteger:self.format forKey:kFormatKey];
    [self refresh];
}

- (void)markTapped {
    CLLocation *fix = self.lastFix;
    if (!fix) {
        [self alert:@"No fix yet" message:@"Wait for GPS before marking."];
        return;
    }
    NSString *suggested = [NSString stringWithFormat:@"W%02lu",
                           (unsigned long)[WaypointStore shared].waypoints.count + 1];
    UIAlertController *a = [UIAlertController
        alertControllerWithTitle:@"Mark waypoint"
                         message:[self coordBlockFor:fix]
                  preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.text = suggested;
        tf.autocapitalizationType = UITextAutocapitalizationTypeAllCharacters;
    }];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                          style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    [a addAction:[UIAlertAction actionWithTitle:@"Save"
                                          style:UIAlertActionStyleDefault
                                        handler:^(UIAlertAction *__unused action) {
        NSString *name = [a.textFields.firstObject.text
            stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        [[WaypointStore shared] addWaypointNamed:name
                                             lat:fix.coordinate.latitude
                                             lon:fix.coordinate.longitude
                                             alt:fix.altitude];
        [weakSelf refresh];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)pinsTapped {
    WaypointListViewController *list = [[WaypointListViewController alloc] init];
    list.fromFix = self.lastFix;
    list.currentTargetName = self.target.name;
    __weak typeof(self) weakSelf = self;
    list.onPick = ^(Waypoint *w) {
        typeof(self) self = weakSelf;
        self.target = w;
        NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
        if (w.name.length) {
            [d setObject:w.name forKey:kTargetKey];
        } else {
            [d removeObjectForKey:kTargetKey];
        }
    };
    list.onDone = ^{
        typeof(self) self = weakSelf;
        [self dismissViewControllerAnimated:YES completion:nil];
        [self refresh];
    };
    [self presentViewController:list animated:YES completion:nil];
}

- (void)restoreTarget {
    self.target = nil;
    NSString *saved = [[NSUserDefaults standardUserDefaults] stringForKey:kTargetKey];
    if (!saved) return;
    for (Waypoint *w in [WaypointStore shared].waypoints) {
        if ([w.name isEqualToString:saved]) {
            self.target = w;
            return;
        }
    }
}

- (void)alert:(NSString *)title message:(NSString *)msg {
    UIAlertController *a = [UIAlertController
        alertControllerWithTitle:title message:msg
                  preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK"
                                          style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

#pragma mark - CLLocationManagerDelegate

- (void)locationManager:(CLLocationManager *)manager
     didUpdateLocations:(NSArray *)locations {
    self.lastFix = [locations lastObject];
    self.statusLine = @"tracking";
}

- (void)locationManager:(CLLocationManager *)manager
       didUpdateHeading:(CLHeading *)newHeading {
    self.lastHeading = newHeading;
    // Drive the arrow from compass events, not just the 1 Hz tick, so it
    // tracks a turning user like a needle instead of stepping.
    [self refreshNav:self.lastFix];
}

- (void)locationManager:(CLLocationManager *)manager
       didFailWithError:(NSError *)error {
    // kCLErrorLocationUnknown is the normal "no signal yet" condition
    // (indoors, cold start) - not worth an alarming multi-line message.
    if (error.code == kCLErrorLocationUnknown) {
        self.statusLine = @"searching…";
    } else if (error.code == kCLErrorDenied) {
        self.statusLine = @"auth: DENIED";
    } else {
        self.statusLine = [NSString stringWithFormat:@"error %ld",
                           (long)error.code];
    }
}

- (void)locationManager:(CLLocationManager *)manager
        didChangeAuthorizationStatus:(CLAuthorizationStatus)status {
    static NSString *const names[] = {
        @"auth: not determined", @"auth: restricted", @"auth: DENIED",
        @"auth: always", @"auth: when in use"
    };
    self.statusLine = status <= kCLAuthorizationStatusAuthorizedWhenInUse
                    ? names[status] : @"auth: ?";
}

@end
