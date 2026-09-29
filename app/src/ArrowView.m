#import "ArrowView.h"

@implementation ArrowView

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = [UIColor clearColor];
        self.opaque = NO;
        _color = [UIColor darkGrayColor];
    }
    return self;
}

- (void)setColor:(UIColor *)color {
    _color = color;
    [self setNeedsDisplay];
}

- (void)drawRect:(CGRect)rect {
    (void)rect;
    CGFloat w = self.bounds.size.width, h = self.bounds.size.height;
    UIBezierPath *p = [UIBezierPath bezierPath];
    [p moveToPoint:CGPointMake(w * 0.50, h * 0.02)];     // tip
    [p addLineToPoint:CGPointMake(w * 0.82, h * 0.88)];  // right wing
    [p addLineToPoint:CGPointMake(w * 0.50, h * 0.64)];  // tail notch
    [p addLineToPoint:CGPointMake(w * 0.18, h * 0.88)];  // left wing
    [p closePath];
    [self.color setFill];
    [p fill];
}

@end
