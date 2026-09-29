#import "RoseView.h"

@implementation RoseView

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = [UIColor clearColor];
        self.opaque = NO;
    }
    return self;
}

- (void)setLive:(BOOL)live {
    if (_live == live) return;
    _live = live;
    [self setNeedsDisplay];
}

- (void)drawRect:(CGRect)rect {
    (void)rect;
    CGFloat cx = self.bounds.size.width / 2, cy = self.bounds.size.height / 2;
    CGFloat r = fmin(cx, cy) - 12;

    UIFont *font = [UIFont fontWithName:@"Menlo-Bold" size:14];
    UIColor *north = self.live
        ? [UIColor colorWithRed:1.0 green:0.35 blue:0.3 alpha:1]
        : [UIColor darkGrayColor];
    UIColor *rest = self.live
        ? [UIColor colorWithRed:0.15 green:0.55 blue:0.25 alpha:1]
        : [UIColor darkGrayColor];

    static NSString *const letters[] = { @"N", @"E", @"S", @"W" };
    for (int i = 0; i < 4; i++) {
        double a = i * M_PI_2;
        CGPoint p = CGPointMake(cx + r * sin(a), cy - r * cos(a));
        NSDictionary *attrs = @{ NSFontAttributeName: font,
                                 NSForegroundColorAttributeName: i ? rest : north };
        CGSize sz = [letters[i] sizeWithAttributes:attrs];
        [letters[i] drawAtPoint:CGPointMake(p.x - sz.width / 2, p.y - sz.height / 2)
                 withAttributes:attrs];
    }

    [[UIColor colorWithWhite:0.3 alpha:1] setFill];
    for (int i = 0; i < 4; i++) {
        double a = M_PI_4 + i * M_PI_2;                  // NE SE SW NW
        CGPoint p = CGPointMake(cx + r * sin(a), cy - r * cos(a));
        [[UIBezierPath bezierPathWithArcCenter:p radius:1.5
                                    startAngle:0 endAngle:2 * M_PI
                                     clockwise:YES] fill];
    }
}

@end
