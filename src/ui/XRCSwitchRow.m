// © 雾月星辰 & MLXC · github@XingChenRS
// XRCSwitchRow.m — 开关行实现（tone 控色）。
#import "XRCSwitchRow.h"
#import "WHToast/WHToast.h"

@interface XRCSwitchRow ()
- (void)onLongPress:(UILongPressGestureRecognizer *)g;
- (void)_restyle;
@end

@implementation XRCSwitchRow {
    UILabel *_t;
    UIView  *_dot;
}
- (instancetype)initWithTitle:(NSString *)title {
    if ((self = [super initWithFrame:CGRectZero])) {
        _title = [title copy];
        self.layer.cornerRadius = 6;
        _t = [[UILabel alloc] init];
        _t.text = title;
        _t.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
        [self addSubview:_t];
        _dot = [[UIView alloc] init];
        _dot.layer.cornerRadius = 4;
        _dot.layer.borderWidth = 1.5;
        [self addSubview:_dot];
        UILongPressGestureRecognizer *lp =
            [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(onLongPress:)];
        lp.minimumPressDuration = 0.5;
        [self addGestureRecognizer:lp];
        [self _restyle];
    }
    return self;
}
- (void)onLongPress:(UILongPressGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateBegan || !self.note.length) return;
    [WHToast showMessage:[NSString stringWithFormat:@"%@：%@", self.title, self.note]
                duration:2.6 finishHandler:^{}];
}
- (void)setTitle:(NSString *)title { _title = [title copy]; _t.text = title; }
- (void)setOn:(BOOL)on { _on = on; [self _restyle]; }
- (void)setTone:(NSInteger)tone { _tone = tone; [self _restyle]; }
- (void)_restyle {
    BOOL on = _on;
    UIColor *fill = (self.tone == 1) ? [UIColor colorWithRed:0.06 green:0.48 blue:0.48 alpha:1.0]   // 网络用青
                                     : [UIColor colorWithRed:0.60 green:0.13 blue:0.36 alpha:1.0];
    self.backgroundColor = on ? fill : [UIColor colorWithWhite:0.17 alpha:1.0];
    _t.textColor = on ? [UIColor whiteColor] : [UIColor colorWithWhite:0.62 alpha:1.0];
    if (on) {
        _dot.backgroundColor = [UIColor whiteColor];
        _dot.layer.borderColor = [UIColor whiteColor].CGColor;
    } else {
        _dot.backgroundColor = [UIColor clearColor];
        _dot.layer.borderColor = [UIColor colorWithWhite:0.62 alpha:1.0].CGColor;
    }
}
- (void)setHighlighted:(BOOL)h { self.alpha = h ? 0.65 : 1.0; }
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.bounds.size.width, h = self.bounds.size.height;
    _dot.frame = CGRectMake(w - 10 - 8, (h - 8) / 2.0, 8, 8);
    _t.frame = CGRectMake(10, 0, w - 10 - 26, h);
}
@end
