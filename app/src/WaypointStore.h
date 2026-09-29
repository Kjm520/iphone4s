#import <Foundation/Foundation.h>

@interface Waypoint : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic) double lat;
@property (nonatomic) double lon;
@property (nonatomic) double alt;
@property (nonatomic, strong) NSDate *created;
@end

// Persistent waypoint list. Lives at /var/mobile/Library/GPSBag/ so it is
// also readable/editable over SSH (e.g. renaming waypoints from a PC).
@interface WaypointStore : NSObject
+ (instancetype)shared;
@property (nonatomic, readonly) NSArray *waypoints;   // of Waypoint
- (Waypoint *)addWaypointNamed:(NSString *)name
                           lat:(double)lat lon:(double)lon alt:(double)alt;
- (void)reload;                     // pick up Map Bag's or SSH-side edits
@end
