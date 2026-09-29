#import "MapViewController.h"

#import <CoreLocation/CoreLocation.h>
#import <MapKit/MapKit.h>

#import "Geo.h"
#import "MBTilesOverlay.h"

static NSString *spacedMGRS(CLLocationCoordinate2D c);

static NSString *const kTilesPath = @"/var/mobile/Media/MapBag/tiles.mbtiles";
static NSString *const kWaypointsPath = @"/var/mobile/Library/GPSBag/waypoints.plist";
static NSString *const kStatusPath = @"/var/mobile/Library/GPSBag/status.json";

@interface MapViewController () <MKMapViewDelegate>
@property (nonatomic, strong) MKMapView *map;
@property (nonatomic, strong) MBTilesOverlay *tiles;
@property (nonatomic, strong) CLLocationManager *locationManager;
@property (nonatomic, strong) UIButton *locateButton;
@property (nonatomic, strong) UIButton *enterButton;
@property (nonatomic, strong) NSArray *waypointAnnotations;
@property (nonatomic, strong) MKPointAnnotation *inspectPin;
@end

@implementation MapViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];

    self.map = [[MKMapView alloc] initWithFrame:self.view.bounds];
    self.map.autoresizingMask = UIViewAutoresizingFlexibleWidth
                              | UIViewAutoresizingFlexibleHeight;
    self.map.delegate = self;
    self.map.showsUserLocation = YES;
    self.map.pitchEnabled = NO;
    self.map.rotateEnabled = NO;         // north-up, like a paper map
    [self.view addSubview:self.map];

    self.tiles = [[MBTilesOverlay alloc] initWithPath:kTilesPath];
    [self.map addOverlay:self.tiles level:MKOverlayLevelAboveLabels];

    self.locationManager = [[CLLocationManager alloc] init];
    [self.locationManager requestWhenInUseAuthorization];

    // Hold a spot to read its coordinates (and optionally save a waypoint).
    UILongPressGestureRecognizer *hold = [[UILongPressGestureRecognizer alloc]
        initWithTarget:self action:@selector(mapHeld:)];
    [self.map addGestureRecognizer:hold];

    self.locateButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.locateButton setTitle:@"◎" forState:UIControlStateNormal];  // ◎
    self.locateButton.titleLabel.font = [UIFont systemFontOfSize:28];
    [self.locateButton setTitleColor:[UIColor colorWithRed:0.25 green:1.0 blue:0.35 alpha:1]
                            forState:UIControlStateNormal];
    self.locateButton.backgroundColor = [UIColor colorWithWhite:0 alpha:0.65];
    self.locateButton.layer.cornerRadius = 24;
    [self.locateButton addTarget:self action:@selector(locateTapped)
                forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.locateButton];

    self.enterButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.enterButton setTitle:@"ENTER" forState:UIControlStateNormal];
    self.enterButton.titleLabel.font = [UIFont fontWithName:@"Menlo-Bold" size:14];
    [self.enterButton setTitleColor:[UIColor colorWithRed:0.25 green:1.0 blue:0.35 alpha:1]
                           forState:UIControlStateNormal];
    self.enterButton.backgroundColor = [UIColor colorWithWhite:0 alpha:0.65];
    self.enterButton.layer.cornerRadius = 8;
    [self.enterButton addTarget:self action:@selector(enterTapped)
               forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.enterButton];

    [self centerOnLastKnownPosition];
    [self reloadWaypoints];
    [[NSNotificationCenter defaultCenter]
        addObserver:self selector:@selector(reloadWaypoints)
               name:UIApplicationWillEnterForegroundNotification object:nil];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGRect b = self.view.bounds;
    self.locateButton.frame = CGRectMake(b.size.width - 60, b.size.height - 60, 48, 48);
    self.enterButton.frame = CGRectMake(12, b.size.height - 60, 84, 48);
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

// Open where GPS Bag last saw us (its status.json), else mid-Alabama.
- (void)centerOnLastKnownPosition {
    CLLocationCoordinate2D c = CLLocationCoordinate2DMake(32.8, -86.7);
    double span = 3.0;
    NSData *json = [NSData dataWithContentsOfFile:kStatusPath];
    if (json) {
        NSDictionary *d = [NSJSONSerialization JSONObjectWithData:json
                                                          options:0 error:NULL];
        if ([d[@"lat"] isKindOfClass:[NSNumber class]] &&
            [d[@"lon"] isKindOfClass:[NSNumber class]]) {
            c = CLLocationCoordinate2DMake([d[@"lat"] doubleValue],
                                           [d[@"lon"] doubleValue]);
            span = 0.05;
        }
    }
    [self.map setRegion:MKCoordinateRegionMake(c, MKCoordinateSpanMake(span, span))
               animated:NO];
}

- (void)reloadWaypoints {
    [self.map removeAnnotations:self.waypointAnnotations];
    NSMutableArray *pins = [NSMutableArray array];
    for (NSDictionary *d in [NSArray arrayWithContentsOfFile:kWaypointsPath]) {
        if (![d isKindOfClass:[NSDictionary class]]) continue;
        MKPointAnnotation *p = [[MKPointAnnotation alloc] init];
        p.coordinate = CLLocationCoordinate2DMake([d[@"lat"] doubleValue],
                                                  [d[@"lon"] doubleValue]);
        p.title = [d[@"name"] description];
        p.subtitle = spacedMGRS(p.coordinate);
        [pins addObject:p];
    }
    self.waypointAnnotations = pins;
    [self.map addAnnotations:pins];
}

- (void)writeWaypoints:(NSArray *)list {
    [[NSFileManager defaultManager]
        createDirectoryAtPath:[kWaypointsPath stringByDeletingLastPathComponent]
          withIntermediateDirectories:YES attributes:nil error:NULL];
    [list writeToFile:kWaypointsPath atomically:YES];
    [self reloadWaypoints];
}

static NSString *spacedMGRS(CLLocationCoordinate2D c) {
    char m[16];
    geo_to_mgrs(c.latitude, c.longitude, m);
    NSString *s = [NSString stringWithUTF8String:m];
    return [NSString stringWithFormat:@"%@ %@ %@ %@",
            [s substringToIndex:3],
            [s substringWithRange:NSMakeRange(3, 2)],
            [s substringWithRange:NSMakeRange(5, 5)],
            [s substringWithRange:NSMakeRange(10, 5)]];
}

- (void)inspectCoordinate:(CLLocationCoordinate2D)c {
    if (!self.inspectPin) {
        self.inspectPin = [[MKPointAnnotation alloc] init];
        [self.map addAnnotation:self.inspectPin];
    }
    [self.map deselectAnnotation:self.inspectPin animated:NO];
    self.inspectPin.coordinate = c;
    self.inspectPin.title = spacedMGRS(c);
    self.inspectPin.subtitle = [NSString stringWithFormat:@"%+.6f, %+.6f",
                                c.latitude, c.longitude];
    [self.map selectAnnotation:self.inspectPin animated:YES];
}

- (void)mapHeld:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;
    [self inspectCoordinate:[self.map convertPoint:[gesture locationInView:self.map]
                              toCoordinateFromView:self.map]];
}

// Accepts MGRS in any spacing/case ("16S EA 65793 82518") or a decimal
// pair ("32.3777, -86.3006").
- (BOOL)parseCoords:(NSString *)text lat:(double *)lat lon:(double *)lon {
    NSString *t = [text stringByTrimmingCharactersInSet:
                   [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!t.length) return NO;
    NSString *compact = [[t.uppercaseString
        stringByReplacingOccurrencesOfString:@" " withString:@""]
        stringByReplacingOccurrencesOfString:@"," withString:@""];
    if (geo_from_mgrs(compact.UTF8String, lat, lon)) return YES;
    NSString *pair = [t stringByReplacingOccurrencesOfString:@"," withString:@" "];
    double la, lo;
    if (sscanf(pair.UTF8String, "%lf %lf", &la, &lo) == 2
        && fabs(la) <= 90 && fabs(lo) <= 180) {
        *lat = la;
        *lon = lo;
        return YES;
    }
    return NO;
}

// Type coordinates -> the inspect pin drops there, visibly, before any
// save: a typo lands in the wrong county instead of silently in a file.
- (void)enterTapped {
    UIAlertController *a = [UIAlertController
        alertControllerWithTitle:@"Show coordinates"
                         message:@"MGRS: 16S EA 65793 82518\ndecimal: 32.3777, -86.3006"
                  preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"coordinates";
        tf.autocapitalizationType = UITextAutocapitalizationTypeAllCharacters;
        tf.autocorrectionType = UITextAutocorrectionTypeNo;
    }];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                          style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    [a addAction:[UIAlertAction actionWithTitle:@"Show"
                                          style:UIAlertActionStyleDefault
                                        handler:^(UIAlertAction *__unused act) {
        typeof(self) self = weakSelf;
        double lat, lon;
        NSString *typed = a.textFields.firstObject.text;
        if (![self parseCoords:typed lat:&lat lon:&lon]) {
            UIAlertController *bad = [UIAlertController
                alertControllerWithTitle:@"Could not parse"
                                 message:[NSString stringWithFormat:
                                          @"“%@”\n\nUse MGRS like 16SEA6579382518\n"
                                          @"or decimal like 32.3777 -86.3006", typed]
                          preferredStyle:UIAlertControllerStyleAlert];
            [bad addAction:[UIAlertAction actionWithTitle:@"OK"
                                                    style:UIAlertActionStyleDefault
                                                  handler:nil]];
            [self presentViewController:bad animated:YES completion:nil];
            return;
        }
        CLLocationCoordinate2D c = CLLocationCoordinate2DMake(lat, lon);
        [self.map setRegion:MKCoordinateRegionMake(c, MKCoordinateSpanMake(0.02, 0.02))
                   animated:YES];
        [self inspectCoordinate:c];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)mapView:(MKMapView *)mapView
        annotationView:(MKAnnotationView *)view
        calloutAccessoryControlTapped:(UIControl *)control {
    (void)mapView; (void)control;
    if (view.annotation == self.inspectPin) {
        [self saveInspectPin];
    } else {
        NSUInteger i = [self.waypointAnnotations indexOfObject:view.annotation];
        if (i != NSNotFound) [self managePinAtIndex:i];
    }
}

// The (+) on the inspect pin's callout: save the spot into the same pins
// file Track Bag uses, so it shows up in its PINS list.
- (void)saveInspectPin {
    CLLocationCoordinate2D c = self.inspectPin.coordinate;
    NSArray *existing = [NSArray arrayWithContentsOfFile:kWaypointsPath] ?: @[];
    NSString *suggested = [NSString stringWithFormat:@"M%02lu",
                           (unsigned long)existing.count + 1];

    UIAlertController *a = [UIAlertController
        alertControllerWithTitle:@"Save pin"
                         message:self.inspectPin.title
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
                                        handler:^(UIAlertAction *__unused act) {
        typeof(self) self = weakSelf;
        NSString *name = [a.textFields.firstObject.text stringByTrimmingCharactersInSet:
                          [NSCharacterSet whitespaceCharacterSet]];
        NSMutableArray *list =
            [([NSArray arrayWithContentsOfFile:kWaypointsPath] ?: @[]) mutableCopy];
        [list addObject:@{ @"name": name.length ? name : suggested,
                           @"lat": @(c.latitude), @"lon": @(c.longitude),
                           @"alt": @0, @"created": [NSDate date] }];
        [self.map removeAnnotation:self.inspectPin];
        self.inspectPin = nil;
        [self writeWaypoints:list];    // the new green pin takes its place
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

// The (i) on a green pin: rename or delete it, in place.
- (void)managePinAtIndex:(NSUInteger)i {
    NSArray *list = [NSArray arrayWithContentsOfFile:kWaypointsPath] ?: @[];
    MKPointAnnotation *pin = self.waypointAnnotations[i];
    if (i >= list.count ||
        ![[list[i][@"name"] description] isEqualToString:pin.title]) {
        [self reloadWaypoints];        // file changed under us; resync
        return;
    }

    UIAlertController *sheet = [UIAlertController
        alertControllerWithTitle:pin.title
                         message:pin.subtitle
                  preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    [sheet addAction:[UIAlertAction actionWithTitle:@"Rename"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *__unused a) {
        [weakSelf renamePinAtIndex:i];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Delete"
                                              style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction *__unused a) {
        typeof(self) self = weakSelf;
        NSMutableArray *fresh =
            [([NSArray arrayWithContentsOfFile:kWaypointsPath] ?: @[]) mutableCopy];
        if (i < fresh.count) [fresh removeObjectAtIndex:i];
        [self writeWaypoints:fresh];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                              style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)renamePinAtIndex:(NSUInteger)i {
    MKPointAnnotation *pin = self.waypointAnnotations[i];
    UIAlertController *a = [UIAlertController
        alertControllerWithTitle:@"Rename pin" message:nil
                  preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.text = pin.title;
        tf.autocapitalizationType = UITextAutocapitalizationTypeAllCharacters;
    }];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                          style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    [a addAction:[UIAlertAction actionWithTitle:@"Save"
                                          style:UIAlertActionStyleDefault
                                        handler:^(UIAlertAction *__unused act) {
        typeof(self) self = weakSelf;
        NSString *name = [a.textFields.firstObject.text stringByTrimmingCharactersInSet:
                          [NSCharacterSet whitespaceCharacterSet]];
        if (!name.length) return;
        NSMutableArray *fresh =
            [([NSArray arrayWithContentsOfFile:kWaypointsPath] ?: @[]) mutableCopy];
        if (i < fresh.count) {
            NSMutableDictionary *d = [fresh[i] mutableCopy];
            d[@"name"] = name;
            fresh[i] = d;
        }
        [self writeWaypoints:fresh];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)locateTapped {
    // Toggle follow mode; falls back to plain recenter if no fix yet.
    if (self.map.userTrackingMode == MKUserTrackingModeNone) {
        [self.map setUserTrackingMode:MKUserTrackingModeFollow animated:YES];
    } else {
        [self.map setUserTrackingMode:MKUserTrackingModeNone animated:YES];
    }
}

#pragma mark - MKMapViewDelegate

- (MKOverlayRenderer *)mapView:(MKMapView *)mapView
            rendererForOverlay:(id<MKOverlay>)overlay {
    return [[MKTileOverlayRenderer alloc] initWithTileOverlay:overlay];
}

- (MKAnnotationView *)mapView:(MKMapView *)mapView
            viewForAnnotation:(id<MKAnnotation>)annotation {
    if ([annotation isKindOfClass:[MKUserLocation class]]) return nil;

    if (annotation == self.inspectPin) {
        MKPinAnnotationView *pin = (MKPinAnnotationView *)
            [mapView dequeueReusableAnnotationViewWithIdentifier:@"inspect"];
        if (!pin) {
            pin = [[MKPinAnnotationView alloc] initWithAnnotation:annotation
                                                  reuseIdentifier:@"inspect"];
            pin.pinColor = MKPinAnnotationColorPurple;
            pin.canShowCallout = YES;
            pin.rightCalloutAccessoryView =
                [UIButton buttonWithType:UIButtonTypeContactAdd];
        } else {
            pin.annotation = annotation;
        }
        return pin;
    }

    MKPinAnnotationView *pin = (MKPinAnnotationView *)
        [mapView dequeueReusableAnnotationViewWithIdentifier:@"wp"];
    if (!pin) {
        pin = [[MKPinAnnotationView alloc] initWithAnnotation:annotation
                                              reuseIdentifier:@"wp"];
        pin.pinColor = MKPinAnnotationColorGreen;
        pin.canShowCallout = YES;
        pin.rightCalloutAccessoryView =
            [UIButton buttonWithType:UIButtonTypeDetailDisclosure];
    } else {
        pin.annotation = annotation;
    }
    return pin;
}

@end
