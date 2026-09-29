#import "StatusWriter.h"

static NSString *const kDir = @"/var/mobile/Library/GPSBag";
static NSString *const kFile = @"/var/mobile/Library/GPSBag/status.json";

@implementation StatusWriter

+ (void)write:(NSDictionary *)status {
    if (![NSJSONSerialization isValidJSONObject:status]) return;
    NSData *json = [NSJSONSerialization dataWithJSONObject:status
                                                   options:NSJSONWritingPrettyPrinted
                                                     error:NULL];
    if (!json) return;
    [[NSFileManager defaultManager] createDirectoryAtPath:kDir
                              withIntermediateDirectories:YES
                                               attributes:nil error:NULL];
    [json writeToFile:kFile atomically:YES];
}

@end
