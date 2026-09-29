#import <UIKit/UIKit.h>

#import "WaypointStore.h"

@class CLLocation;

// Full-screen pin picker in the same bare terminal style. Tap a row to
// target it; CLEAR drops the target. Creating, renaming and deleting pins
// is Map Bag's job (plus MARK on the main screen).
@interface WaypointListViewController : UIViewController
@property (nonatomic, strong) CLLocation *fromFix;        // for distance/bearing
@property (nonatomic, copy) NSString *currentTargetName;
@property (nonatomic, copy) void (^onPick)(Waypoint *w);  // nil w = clear target
@property (nonatomic, copy) void (^onDone)(void);
@end
