#import <UIKit/UIKit.h>

// A compass card: N/E/S/W at the ring's edge with intercardinal dots.
// Rotate the whole view (like the dart) so the letters ride the card,
// exactly as on a physical compass. Letters upright when facing north.
@interface RoseView : UIView
@property (nonatomic) BOOL live;    // heading valid: N red, rest dim green
@end
