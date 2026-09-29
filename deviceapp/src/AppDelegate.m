#import "AppDelegate.h"
#import "DeviceViewController.h"

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application
        didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.rootViewController = [[DeviceViewController alloc] init];
    [self.window makeKeyAndVisible];
    // Same rule as the other instruments: never sleep while on screen.
    application.idleTimerDisabled = YES;
    return YES;
}

@end
