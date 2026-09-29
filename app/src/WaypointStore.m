#import "WaypointStore.h"

static NSString *const kDir = @"/var/mobile/Library/GPSBag";
static NSString *const kFile = @"/var/mobile/Library/GPSBag/waypoints.plist";

@implementation Waypoint
@end

@interface WaypointStore ()
@property (nonatomic, strong) NSMutableArray *list;
@end

@implementation WaypointStore

+ (instancetype)shared {
    static WaypointStore *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        s = [[WaypointStore alloc] init];
        [s reload];
    });
    return s;
}

- (NSArray *)waypoints {
    return [self.list copy];
}

- (void)reload {
    self.list = [NSMutableArray array];
    for (NSDictionary *d in [NSArray arrayWithContentsOfFile:kFile]) {
        if (![d isKindOfClass:[NSDictionary class]]) continue;
        Waypoint *w = [[Waypoint alloc] init];
        w.name = [d[@"name"] description] ?: @"?";
        w.lat = [d[@"lat"] doubleValue];
        w.lon = [d[@"lon"] doubleValue];
        w.alt = [d[@"alt"] doubleValue];
        w.created = [d[@"created"] isKindOfClass:[NSDate class]] ? d[@"created"] : nil;
        [self.list addObject:w];
    }
}

- (Waypoint *)addWaypointNamed:(NSString *)name
                           lat:(double)lat lon:(double)lon alt:(double)alt {
    Waypoint *w = [[Waypoint alloc] init];
    w.name = name.length ? name : [NSString stringWithFormat:@"W%02lu",
                                   (unsigned long)self.list.count + 1];
    w.lat = lat;
    w.lon = lon;
    w.alt = alt;
    w.created = [NSDate date];
    [self.list addObject:w];
    [self save];
    return w;
}

- (void)save {
    [[NSFileManager defaultManager] createDirectoryAtPath:kDir
                              withIntermediateDirectories:YES
                                               attributes:nil error:NULL];
    NSMutableArray *plist = [NSMutableArray array];
    for (Waypoint *w in self.list) {
        [plist addObject:@{ @"name": w.name, @"lat": @(w.lat), @"lon": @(w.lon),
                            @"alt": @(w.alt), @"created": w.created ?: [NSDate date] }];
    }
    [plist writeToFile:kFile atomically:YES];
}

@end
