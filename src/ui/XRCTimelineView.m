// © 雾月星辰 & MLXC · github@XingChenRS
// XRCTimelineView.m — 时间轴控件实现。
#import "XRCTimelineView.h"

@implementation XRCTimelineView {
    UITapGestureRecognizer *_tap;
    UIPanGestureRecognizer *_pan;
    BOOL _dragging;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor colorWithWhite:0.12 alpha:1.0];
        self.layer.cornerRadius = 6;
        self.layer.masksToBounds = YES;
        _tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(onTap:)];
        [self addGestureRecognizer:_tap];
        _pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(onPan:)];
        [self addGestureRecognizer:_pan];
        [_tap requireGestureRecognizerToFail:_pan];
    }
    return self;
}

- (uint32_t)msAtX:(CGFloat)x {
    CGFloat w = self.bounds.size.width;
    if (w <= 0 || self.lengthMs == 0) return 0;
    CGFloat t = MAX(0.0, MIN(1.0, x / w));
    return (uint32_t)(t * self.lengthMs);
}

- (void)onTap:(UITapGestureRecognizer *)g {
    CGPoint p = [g locationInView:self];
    if (self.onScrub) self.onScrub([self msAtX:p.x], YES);
}

- (void)onPan:(UIPanGestureRecognizer *)g {
    CGPoint p = [g locationInView:self];
    if (g.state == UIGestureRecognizerStateBegan) _dragging = YES;
    // 拖动 = 纯 seek 预览，松手执行。
    // 循环区间只由「设起点/设终点」按钮写入。
    if (g.state == UIGestureRecognizerStateChanged) {
        _positionMs = [self msAtX:p.x];
        [self setNeedsDisplay];
    }
    if (g.state == UIGestureRecognizerStateEnded) {
        _dragging = NO;
        if (self.onScrub) self.onScrub([self msAtX:p.x], YES);
    }
    if (g.state == UIGestureRecognizerStateCancelled || g.state == UIGestureRecognizerStateFailed)
        _dragging = NO;
}

- (void)drawRect:(CGRect)rect {
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGFloat w = rect.size.width;
    CGFloat h = rect.size.height;
    if (self.lengthMs == 0) return;

    // 循环区间高亮
    if (self.loopVisible && self.loopToMs > self.loopFromMs) {
        CGFloat x0 = w * ((CGFloat)self.loopFromMs / self.lengthMs);
        CGFloat x1 = w * ((CGFloat)self.loopToMs / self.lengthMs);
        CGContextSetFillColorWithColor(ctx, [UIColor colorWithRed:0.3 green:0.7 blue:1.0 alpha:0.35].CGColor);
        CGContextFillRect(ctx, CGRectMake(x0, 0, x1 - x0, h));
        CGContextSetStrokeColorWithColor(ctx, [UIColor colorWithRed:0.5 green:0.85 blue:1.0 alpha:0.9].CGColor);
        CGContextSetLineWidth(ctx, 1.5);
        CGContextStrokeRect(ctx, CGRectMake(x0, 0.75, x1 - x0, h - 1.5));
    }

    // 中心线（无波形数据，用中线示意）
    CGContextSetStrokeColorWithColor(ctx, [UIColor colorWithWhite:0.45 alpha:0.8].CGColor);
    CGContextSetLineWidth(ctx, 1);
    CGContextMoveToPoint(ctx, 0, h / 2);
    CGContextAddLineToPoint(ctx, w, h / 2);
    CGContextStrokePath(ctx);

    // 当前进度指针
    if (self.lengthMs > 0) {
        CGFloat px = w * ((CGFloat)self.positionMs / self.lengthMs);
        CGContextSetFillColorWithColor(ctx, [UIColor whiteColor].CGColor);
        CGContextFillRect(ctx, CGRectMake(px - 1, 0, 2, h));
    }
}

- (void)setPositionMs:(uint32_t)positionMs {
    if (_dragging) return;
    _positionMs = positionMs;
    [self setNeedsDisplay];
}
- (void)setLoopFromMs:(uint32_t)from to:(uint32_t)to visible:(BOOL)visible {
    _loopFromMs = from; _loopToMs = to; _loopVisible = visible;
    [self setNeedsDisplay];
}
- (void)setLengthMs:(uint32_t)lengthMs {
    _lengthMs = lengthMs;
    [self setNeedsDisplay];
}
@end
