#import "AppDelegate.h"
#import "MapViewController.h"

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application
        didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.rootViewController = [[MapViewController alloc] init];
    [self.window makeKeyAndVisible];
    // Same rule as GPS Bag: a nav display must not sleep while in use.
    application.idleTimerDisabled = YES;
    return YES;
}

@end
