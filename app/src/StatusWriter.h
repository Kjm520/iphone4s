#import <Foundation/Foundation.h>

// Drops the live fix as JSON where SSH can read it:
//   ssh iphone cat /var/mobile/Library/GPSBag/status.json
@interface StatusWriter : NSObject
+ (void)write:(NSDictionary *)status;
@end
