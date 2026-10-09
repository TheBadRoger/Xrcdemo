// © 雾月星辰 & MLXC · github@XingChenRS
// XRCPracticePanel.m — 练习面板（v3）。
// 设计稿：ui-mock/panel_mock.html（v3）。结构：
//   固定标题栏（拖动 + ⓘ说明 + ✕；标题=版本号）+ 可滚动内容区（上限 72% 屏高）；分区 =
//   播放（时间轴/±5s/速度/音乐变速/重置成绩）｜循环（设 A/B + 开关 + 重置）
//   ｜判定窗口（四档 + 应用 + 自动演奏）｜解锁（构建期功能集逐项显隐）｜网络（私域改写，地址折叠）
//   ｜存储（cb 外置）｜诊断（状态两行 + 开发构建专属工具区）。
// 交互约定（与设计稿对齐）：开关=「名称+状态点」（XRCSwitchRow，tone 控色）；
//   动作=灰底按钮；破坏性=红字靠右；状态数字只进只读行；控件一律属性引用；
//   长按任一开关看该项说明；面板位置/日志档位等全部经 XRCConfig（单一事实源）。
// 控件在 XRCTimelineView.h/.m、XRCSwitchRow.h/.m。

#import "XRCPracticePanel.h"
#include <string.h>
#import "XRCFloatButton.h"
#import "WHToast/WHToast.h"
#import "XRCLog.h"
#include "XRCConfig.h"
#include "XRCGameplay.h"
#include "XRCClock.h"
#include "XRCPlayer.h"
#include "XRCJudge.h"
#include "XRCProbe.h"
#include "XRCProfile.h"
#include "XRCDump.h"
#include "XRCOMLog.h"
#include "XRCNet.h"
#include "XRCHook.h"
#include "XRCStore.h"
#include "XRCAudio.h"
#include "XRCReplay.h"
#include "XRCRateAdapt.h"
#include "XRCRateMath.h"
#include "XRCKonzetsu.h"
#include "XRCKonzetsuMath.h"
#include "XRCPracticeMath.h"
#import "XRCTimelineView.h"
#import "XRCSwitchRow.h"

// 说明文本（ⓘ 展开时逐区展示；开关各自的说明在 XRCSwitchRow.note，长按弹出）
static NSString *const kNotePlayback =
    @"时间轴拖动=跳转；−5s/+5s 按当前速度缩放（5000×speed）；滑杆=速度。\n"
    @"音乐变速=让 BGM 跟着速度走并保持音高（FMOD 源时钟 + 实时高质量拉伸 补偿延迟）；"
    @"关掉则只改谱面时钟，速度快时音画会逐渐错开。\n"
    @"每次回拖都会恢复音符。重置成绩=开启时回拖清空成绩，关闭时保留成绩。";
static NSString *const kNoteLoop =
    @"设起点 A=把当前位置记为 A；设终点 B=把当前位置记为 B（需 >A+1s）；循环开=播放到 B 自动回 A。";
static NSString *const kNoteJudge =
    @"四档 ±ms 阈值，只改本地判定宽容度，不动谱面；数值需递增（提交时自动夹取）。\n"
    @"锁定判定区间=变速时保持现实毫秒窗口；关闭则窗口随播放倍率变化。\n"
    @"自动演奏=所有判定强制 Pure（含漏扫路径），演示/练习用。";
static NSString *const kNoteResetScore =
    @"每次回拖都会恢复音符。开启：回拖时重置成绩；关闭：保留成绩。循环回位遵循同一设置。";
static NSString *const kNoteNet =
    @"只改 API 请求的域名（路径与参数原样、不动 TLS）；关掉走官方域。";
static NSString *const kNoteStore =
    @"把 cb 内容根从 Library/Application Support 搬到 Documents/cb（同一分区，瞬间完成，不拷贝）。"
    @"之后：① cb/active 是游戏**最优先**的资源查找层，把同名文件按相同相对路径丢进去就覆盖包内"
    @"（例：cb/active/img/1080/xxx.png）；② cb 下载也落在这里。免越狱下 Documents 是唯一能被"
    @"「文件」App / 电脑看到的位置（需 Info.plist 开 UIFileSharingEnabled，inject.py 会写）。"
    @"关闭开关 = 停止迁移；已建好的软链不会自动撤销（手动删 Library/Application Support/cb 即恢复原状）。";
static NSString *const kNoteDiag =
    @"日志档位：默认=只记要点；详细=全量 DEBUG；网络=只放开网络/下载/内容。"
    @"日志在 Documents/xrcdemo.log。";
static NSString *const kNoteDev =
    @"转储 → Documents/xrcdemo-net/mem/；强制 applog 需二次确认。"
    @"日志档位写入配置、重启保持。";

// 开发构建专属工具区（release 下整段编译为空）
#define XRC_DEV_SECTION (XRC_DEBUG_BUILD)

@interface XRCPracticePanel ()
// 结构
@property (nonatomic, strong) UIView *titleBar;
@property (nonatomic, strong) UIScrollView *body;
@property (nonatomic, assign) CGFloat contentHeight;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, strong) UIView *frozenFrame;
@property (nonatomic, assign) uint64_t frozenUpdateSequence;
@property (nonatomic, assign) BOOL infoOn;         // ⓘ 说明模式
@property (nonatomic, assign) NSInteger lowTick;   // 低频刷新分频计数
// 播放
@property (nonatomic, strong) XRCTimelineView *timeline;
@property (nonatomic, strong) XRCSwitchRow *swSpeedAudio;
@property (nonatomic, strong) XRCSwitchRow *swResetScore;
@property (nonatomic, strong) UILabel *timeLabel;
@property (nonatomic, strong) UILabel *speedLabel;
@property (nonatomic, strong) UISlider *speedSlider;
@property (nonatomic, strong) XRCSwitchRow *swRateOffset;
@property (nonatomic, strong) XRCSwitchRow *swRateFlow;
@property (nonatomic, strong) XRCSwitchRow *swHideDuringPlay;
@property (nonatomic, strong) UITextField *flowField;
@property (nonatomic, strong) UIButton *flowApplyBtn;
@property (nonatomic, strong) UIButton *flowNativeBtn;
// 循环
@property (nonatomic, strong) UIButton *fromBtn;
@property (nonatomic, strong) UIButton *toBtn;
@property (nonatomic, strong) XRCSwitchRow *loopSwitch;
@property (nonatomic, assign) BOOL pendingTo;
// 判定
@property (nonatomic, strong) NSMutableArray<UITextField *> *judgeFields;
@property (nonatomic, strong) UIButton *judgeApplyBtn;
@property (nonatomic, strong) UILabel *judgeHdr;
@property (nonatomic, strong) XRCSwitchRow *swAutoplay;
@property (nonatomic, strong) XRCSwitchRow *swJudgeTimeLock;
@property (nonatomic, strong) UIButton *konzetsuSelect;
@property (nonatomic, strong) XRCSwitchRow *swKonzetsuEnabled;
@property (nonatomic, strong) XRCSwitchRow *swKonzetsuChallenge;
// 解锁
@property (nonatomic, strong) XRCSwitchRow *swOwn;
@property (nonatomic, strong) XRCSwitchRow *swCb;
// 网络
@property (nonatomic, strong) XRCSwitchRow *swNet;
@property (nonatomic, strong) UIButton *netFoldBtn;
@property (nonatomic, strong) UITextField *netField;
@property (nonatomic, strong) UILabel *netStat;
@property (nonatomic, assign) BOOL netExpanded;
// 存储（外置）
@property (nonatomic, strong) XRCSwitchRow *swStore;
@property (nonatomic, strong) UILabel *storeStat;
// 诊断
@property (nonatomic, strong) UILabel *capsLabel;
@property (nonatomic, strong) UILabel *patchLine;
#if XRC_DEV_SECTION
@property (nonatomic, strong) UISegmentedControl *logSeg;
@property (nonatomic, strong) XRCSwitchRow *swStubsLite;
#endif

// 内部方法前置声明（老工具链不依赖 @implementation 的"先用后定义"查找）
- (CGFloat)contentW;
- (void)buildIfNeeded;
- (void)buildContent;
- (void)rebuildContent;
- (void)relayoutScroll;
- (void)toggleInfo;
- (void)updateKonzetsuMenu;
- (void)cycleKonzetsu;
- (void)toggleHideDuringPlay;
- (void)commitFlow;
- (void)restoreNativeFlow;
- (void)toggleKonzetsuEnabled;
- (void)toggleKonzetsuChallenge;
- (CGFloat)note:(NSString *)text at:(CGFloat)x y:(CGFloat)y w:(CGFloat)w;
- (CGFloat)note:(NSString *)text afterCard:(UIView *)card x:(CGFloat)x y:(CGFloat)y w:(CGFloat)w;
- (void)sectionLabel:(NSString *)title hint:(NSString *)hint x:(CGFloat)x y:(CGFloat)y w:(CGFloat)w;
- (UIView *)cardAt:(CGFloat)x y:(CGFloat)y w:(CGFloat)w;
- (UIButton *)makeActionButton:(NSString *)title;
- (CGPoint)savedOrigin;
- (void)saveOrigin:(CGPoint)o;
- (void)onDragPanel:(UIPanGestureRecognizer *)g;
- (void)toggleRepeat;
- (void)setFrom;
- (void)setTo;
- (void)resetLoop;
- (void)jumpBack;
- (void)jumpForward;
- (void)jump:(int)dir;
- (void)speedChanged:(UISlider *)s;
- (void)speedCommit:(UISlider *)s;
- (void)toggleSpeedAudio;
- (void)toggleResetScore;
- (void)commitJudge;
- (void)toggleJudgeTimeLock;
- (void)toggleRateOffset;
- (void)toggleRateFlow;
- (void)toggleOwn;
- (void)toggleAutoplay;
- (void)toggleCb;
- (void)toggleNet;
- (void)toggleNetFold;
- (void)toggleStore;
- (void)logSegChanged:(UISegmentedControl *)s;
#if XRC_DEV_SECTION
- (void)dumpMemory;
- (void)cleanDump;
- (void)omProbe;
- (void)forceApplog;
- (void)toggleStubsLite;
#endif
- (void)refreshFast;
- (void)refreshSlow;
- (void)refresh;
@end

@implementation XRCPracticePanel

+ (instancetype)shared {
    static XRCPracticePanel *s = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[XRCPracticePanel alloc] init]; });
    return s;
}

- (UIWindow *)keyWindow {
    for (UIScene *sc in UIApplication.sharedApplication.connectedScenes) {
        if (![sc isKindOfClass:[UIWindowScene class]]) continue;
        for (UIWindow *w in ((UIWindowScene *)sc).windows) if (w.isKeyWindow) return w;
    }
    return UIApplication.sharedApplication.windows.firstObject;
}

- (BOOL)isVisible { return self.superview != nil; }
- (CGFloat)contentW { return MIN(440.0, [self keyWindow].bounds.size.width - 16); }

- (void)show {
    UIWindow *w = [self keyWindow];
    if (!w) { xrc_logw(XRCLC_UI, @"panel show: no key window"); return; }
    if (!self.superview) { [w addSubview:self]; [w bringSubviewToFront:self]; }
    [self buildIfNeeded];

    CGFloat panelW = [self contentW];
    CGFloat maxH = w.bounds.size.height * 0.72;
    CGFloat h = MIN(self.contentHeight + 34 + 8, maxH);
    CGPoint o = [self savedOrigin];
    if (o.x != CGFLOAT_MAX) {
        self.frame = CGRectMake(o.x, o.y, panelW, h);
        self.autoresizingMask = UIViewAutoresizingNone;
    } else {
        self.frame = CGRectMake((w.bounds.size.width - panelW) / 2.0,
                                w.bounds.size.height - h - 24 - w.safeAreaInsets.bottom,
                                panelW, h);
        self.autoresizingMask = UIViewAutoresizingFlexibleTopMargin;
    }
    [self relayoutScroll];
    if (!self.timer) {
        self.timer = [NSTimer scheduledTimerWithTimeInterval:0.1 target:self
                                                    selector:@selector(tick) userInfo:nil repeats:YES];
    }
    [self refresh];
    xrc_logd(XRCLC_UI, @"panel shown %.0fx%.0f (content %.0f, info=%d)",
             panelW, h, self.contentHeight, (int)self.infoOn);
}

- (void)releaseFrozenFrame {
    [self.frozenFrame removeFromSuperview]; self.frozenFrame=nil;
}
- (void)captureFrozenFrame {
    if (self.frozenFrame || !self.superview) return;
    UIView *parent=self.superview;
    // Capture the last submitted GPU frame before gameplay stops drawing.
    UIView *source=self.window.rootViewController.view ?: parent;
    UIView *frame=[source snapshotViewAfterScreenUpdates:NO];
    if (!frame) return;
    frame.frame=[source convertRect:source.bounds toView:parent];
    frame.autoresizingMask=UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    frame.userInteractionEnabled=NO;
    [parent insertSubview:frame belowSubview:self]; self.frozenFrame=frame;
    self.frozenUpdateSequence=xrc_gameplay_update_sequence();
}
- (void)hide {
    [self releaseFrozenFrame];
    xrc_gameplay_scrub_cancel();
    [self.timer invalidate]; self.timer = nil;
    [self removeFromSuperview];
    xrc_logd(XRCLC_UI, @"panel hidden");
}

// 分频刷新：高频（位置/时长/速度）10Hz；低频（开关镜像/状态行/判定/能力）1Hz。
- (void)tick {
    if (!xrc_gameplay_seek_active() &&
        xrc_gameplay_update_sequence()>self.frozenUpdateSequence) [self releaseFrozenFrame];
    [self refreshFast];
    if (++self.lowTick >= 10) { self.lowTick = 0; [self refreshSlow]; }
}

- (void)relayoutScroll {
    CGFloat barH = CGRectGetHeight(self.titleBar.frame);
    self.body.frame = CGRectMake(0, barH, self.bounds.size.width, self.bounds.size.height - barH);
    self.body.contentSize = CGSizeMake(self.bounds.size.width, self.contentHeight + 10);
}

// ---------------- 构建 ----------------
- (void)buildIfNeeded {
    if (self.subviews.count) return;
    self.backgroundColor = [UIColor colorWithWhite:0.04 alpha:0.94];
    self.layer.cornerRadius = 12;
    self.layer.masksToBounds = YES;

    self.titleBar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, [self contentW], 34)];
    self.titleBar.backgroundColor = [UIColor colorWithWhite:0.10 alpha:1.0];
    self.titleBar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    self.titleBar.userInteractionEnabled = YES;
    [self.titleBar addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self
                                                                               action:@selector(onDragPanel:)]];
    UILabel *t = [[UILabel alloc] initWithFrame:CGRectMake(12, 0, 260, 34)];
    // 标题=显示版本（单一来源 XRCVersion.h）；构建戳常显在悬浮球底部。
    t.text = [NSString stringWithFormat:@"xrcdemo %@", XRC_VERSION];
    t.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    t.textColor = [UIColor whiteColor];
    [self.titleBar addSubview:t];

    UIButton *info = [self makeActionButton:@"ⓘ"];
    info.titleLabel.font = [UIFont systemFontOfSize:14];
    info.frame = CGRectMake(self.titleBar.bounds.size.width - 68, 4, 26, 26);
    [info setTitleColor:[UIColor colorWithRed:0.56 green:0.83 blue:0.83 alpha:1.0] forState:UIControlStateNormal];
    info.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [info addTarget:self action:@selector(toggleInfo) forControlEvents:UIControlEventTouchUpInside];
    [self.titleBar addSubview:info];

    UIButton *x = [self makeActionButton:@"✕"];
    x.titleLabel.font = [UIFont systemFontOfSize:13];
    x.frame = CGRectMake(self.titleBar.bounds.size.width - 36, 4, 26, 26);
    [x setTitleColor:[UIColor colorWithWhite:0.8 alpha:1.0] forState:UIControlStateNormal];
    x.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [x addTarget:self action:@selector(hide) forControlEvents:UIControlEventTouchUpInside];
    [self.titleBar addSubview:x];
    [self addSubview:self.titleBar];

    self.body = [[UIScrollView alloc] initWithFrame:CGRectZero];
    self.body.showsVerticalScrollIndicator = YES;
    [self addSubview:self.body];

    [self buildContent];
}

- (void)toggleInfo {
    self.infoOn = !self.infoOn;
    [self rebuildContent];
    [WHToast showMessage:self.infoOn ? @"说明已展开（长按任一项看单项说明）" : @"说明已收起"
                duration:1.2 finishHandler:^{}];
}

- (void)rebuildContent {
    for (UIView *v in [self.body.subviews copy]) [v removeFromSuperview];
    self.contentHeight = 0;
    [self buildContent];
    [self relayoutScroll];
    [self refresh];
}

- (void)buildContent {
    const CGFloat pad = 12, gap = 8, rowH = 30, secH = 14, secGap = 10, cardPad = 8;
    UIScrollView *B = self.body;
    CGFloat W = [self contentW] - pad * 2;
    CGFloat x0 = pad;
    CGFloat y = 6;
    __weak typeof(self) weakSelf = self;

    // ============ ① 播放（含重置成绩） ============
    [self sectionLabel:@"播放" hint:@"拖动时间轴 = 跳转" x:x0 y:y w:W];
    y += secH + 4;
    UIView *c1 = [self cardAt:x0 y:y w:W];
    self.timeline = [[XRCTimelineView alloc] initWithFrame:CGRectMake(cardPad, cardPad, W - cardPad * 2, 34)];
    self.timeline.onScrubBegin = ^BOOL {
        [self captureFrozenFrame];
        BOOL started=xrc_gameplay_scrub_begin();
        if (!started) [self releaseFrozenFrame];
        return started;
    };
    self.timeline.onScrubCancel = ^{
        xrc_gameplay_scrub_cancel();
        // The timer removes the snapshot after the next native drawing update.
    };
    self.timeline.onScrub = ^(uint32_t ms, BOOL finished) {
        if (finished && !xrc_gameplay_request(XRC_OP_SEEK, ms)) {
            xrc_gameplay_scrub_cancel();
            [self releaseFrozenFrame];
            [WHToast showMessage:@"当前场景不能跳转，请进入谱面后重试" duration:1.6 finishHandler:^{}];
        }
    };
    [c1 addSubview:self.timeline];
    self.timeLabel = [[UILabel alloc] initWithFrame:CGRectMake(cardPad, cardPad + 42, 160, rowH)];
    self.timeLabel.font = [UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightRegular];
    self.timeLabel.textColor = [UIColor colorWithWhite:0.92 alpha:1.0];
    [c1 addSubview:self.timeLabel];
    UIButton *back = [self makeActionButton:@"−5s"];
    back.frame = CGRectMake(W - cardPad - 120, cardPad + 43, 56, 28);
    [back addTarget:self action:@selector(jumpBack) forControlEvents:UIControlEventTouchUpInside];
    [c1 addSubview:back];
    UIButton *fwd = [self makeActionButton:@"+5s"];
    fwd.frame = CGRectMake(W - cardPad - 56, cardPad + 43, 56, 28);
    [fwd addTarget:self action:@selector(jumpForward) forControlEvents:UIControlEventTouchUpInside];
    [c1 addSubview:fwd];
    self.speedLabel = [[UILabel alloc] initWithFrame:CGRectMake(cardPad, cardPad + 42 + rowH + 2, 56, rowH)];
    self.speedLabel.font = [UIFont monospacedDigitSystemFontOfSize:14 weight:UIFontWeightMedium];
    self.speedLabel.textColor = [UIColor whiteColor];
    [c1 addSubview:self.speedLabel];
    self.speedSlider = [[UISlider alloc] initWithFrame:CGRectMake(70, cardPad + 42 + rowH + 2, W - 78, rowH)];
    self.speedSlider.minimumValue = 0.05f;
    self.speedSlider.maximumValue = 2.0f;
    self.speedSlider.continuous = YES;   // Preview while dragging; apply once on release.
    [self.speedSlider addTarget:self action:@selector(speedChanged:) forControlEvents:UIControlEventValueChanged];
    [self.speedSlider addTarget:self action:@selector(speedCommit:)
               forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside |
                                UIControlEventTouchCancel];
    [c1 addSubview:self.speedSlider];
    // 能力门控：时间轴/±5s 依赖播放器与 gp 钩子；变速是纯 dylib 能力，始终可用
    BOOL canSeek = xrc_cap_player() && xrc_cap_gp();
    self.timeline.userInteractionEnabled = canSeek;
    self.timeline.alpha = canSeek ? 1.0 : 0.4;
    back.enabled = fwd.enabled = canSeek;
    back.alpha = fwd.alpha = canSeek ? 1.0 : 0.4;

    CGFloat rowY = cardPad + 42 + 2 * rowH + 8;
    self.swSpeedAudio = [[XRCSwitchRow alloc] initWithTitle:@"音乐变速"];
    self.swSpeedAudio.note = kNotePlayback;
    {
        xrc_config_t c; xrc_config_load(&c);
        self.swSpeedAudio.on = c.speed_audio;
    }
    self.swSpeedAudio.frame = CGRectMake(cardPad, rowY, W - cardPad * 2, rowH);
    [self.swSpeedAudio addTarget:self action:@selector(toggleSpeedAudio) forControlEvents:UIControlEventTouchUpInside];
    [c1 addSubview:self.swSpeedAudio];

    // 分隔线（卡内）
    UIView *sep = [[UIView alloc] initWithFrame:CGRectMake(cardPad, rowY + rowH + 8, W - cardPad * 2, 1)];
    sep.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.06];
    [c1 addSubview:sep];

    self.swResetScore = [[XRCSwitchRow alloc] initWithTitle:@"重置成绩"];
    self.swResetScore.note = kNoteResetScore;
    {
        xrc_config_t c; xrc_config_load(&c);
        self.swResetScore.on = c.reset_score;
    }
    self.swResetScore.frame = CGRectMake(cardPad, rowY + rowH + 17, W - cardPad * 2, rowH);
    [self.swResetScore addTarget:self action:@selector(toggleResetScore) forControlEvents:UIControlEventTouchUpInside];
    [c1 addSubview:self.swResetScore];

    CGFloat adaptY = rowY + 2 * rowH + 26;
    self.swRateOffset = [[XRCSwitchRow alloc] initWithTitle:@"倍率适应偏移"];
    self.swRateOffset.note = @"内部偏移乘倍率，设置显示值不变；游玩中可切换，跳转期间暂缓。";
    self.swRateOffset.frame = CGRectMake(cardPad, adaptY, W - cardPad * 2, rowH);
    [self.swRateOffset addTarget:self action:@selector(toggleRateOffset) forControlEvents:UIControlEventTouchUpInside];
    [c1 addSubview:self.swRateOffset];
    self.swRateFlow = [[XRCSwitchRow alloc] initWithTitle:@"倍率适应流速"];
    self.swRateFlow.note = @"内部流速乘倍率倒数，设置显示值不变；游玩中可切换。";
    self.swRateFlow.frame = CGRectMake(cardPad, adaptY + rowH + 8, W - cardPad * 2, rowH);
    [self.swRateFlow addTarget:self action:@selector(toggleRateFlow) forControlEvents:UIControlEventTouchUpInside];
    [c1 addSubview:self.swRateFlow];
    self.swHideDuringPlay = [[XRCSwitchRow alloc] initWithTitle:@"游玩时隐藏图标"];
    self.swHideDuringPlay.note = @"游玩期间隐藏悬浮图标，退出后自动恢复。";
    self.swHideDuringPlay.frame = CGRectMake(cardPad, adaptY + 2 * (rowH + 8), W - cardPad * 2, rowH);
    [self.swHideDuringPlay addTarget:self action:@selector(toggleHideDuringPlay) forControlEvents:UIControlEventTouchUpInside];
    [c1 addSubview:self.swHideDuringPlay];
    CGFloat flowY = adaptY + 3 * rowH + 24;
    UILabel *flowTitle = [[UILabel alloc] initWithFrame:CGRectMake(cardPad, flowY, W - cardPad * 2, 16)];
    flowTitle.text = @"下落流速（实时设置）";
    flowTitle.textColor = UIColor.whiteColor;
    flowTitle.font = [UIFont systemFontOfSize:12];
    [c1 addSubview:flowTitle];
    self.flowField = [[UITextField alloc] initWithFrame:CGRectMake(cardPad, flowY + 20, W - cardPad * 2 - 128, rowH)];
    self.flowField.borderStyle = UITextBorderStyleRoundedRect;
    self.flowField.keyboardType = UIKeyboardTypeDecimalPad;
    self.flowField.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightRegular];
    self.flowField.placeholder = @"0.1–214748364.7";
    [c1 addSubview:self.flowField];
    self.flowApplyBtn = [self makeActionButton:@"设置"];
    self.flowApplyBtn.frame = CGRectMake(W - cardPad - 122, flowY + 20, 58, rowH);
    [self.flowApplyBtn addTarget:self action:@selector(commitFlow) forControlEvents:UIControlEventTouchUpInside];
    [c1 addSubview:self.flowApplyBtn];
    self.flowNativeBtn = [self makeActionButton:@"原生"];
    self.flowNativeBtn.frame = CGRectMake(W - cardPad - 58, flowY + 20, 58, rowH);
    [self.flowNativeBtn addTarget:self action:@selector(restoreNativeFlow) forControlEvents:UIControlEventTouchUpInside];
    [c1 addSubview:self.flowNativeBtn];
    c1.frame = CGRectMake(x0, y, W, flowY + 20 + rowH + cardPad);
    y = [self note:kNotePlayback afterCard:c1 x:x0 y:y w:W] + secGap;

    // ============ ② 循环 ============
    // 能力：gp 钩子 + 播放器；缺则整段隐藏
    if (xrc_cap_gp() && xrc_cap_player()) {
    [self sectionLabel:@"循环" hint:@"到 B 回 A" x:x0 y:y w:W];
    y += secH + 4;
    UIView *c2 = [self cardAt:x0 y:y w:W];
    CGFloat halfW = (W - cardPad * 2 - gap) / 2.0;
    self.fromBtn = [self makeActionButton:@"设起点 A"];
    self.fromBtn.frame = CGRectMake(cardPad, cardPad, halfW, rowH);
    [self.fromBtn addTarget:self action:@selector(setFrom) forControlEvents:UIControlEventTouchUpInside];
    [c2 addSubview:self.fromBtn];
    self.toBtn = [self makeActionButton:@"设终点 B"];
    self.toBtn.frame = CGRectMake(cardPad + halfW + gap, cardPad, halfW, rowH);
    [self.toBtn addTarget:self action:@selector(setTo) forControlEvents:UIControlEventTouchUpInside];
    [c2 addSubview:self.toBtn];
    self.loopSwitch = [[XRCSwitchRow alloc] initWithTitle:@"循环"];
    self.loopSwitch.note = kNoteLoop;
    self.loopSwitch.frame = CGRectMake(cardPad, cardPad + rowH + gap, W - cardPad * 2 - 92 - gap, rowH);
    [self.loopSwitch addTarget:self action:@selector(toggleRepeat) forControlEvents:UIControlEventTouchUpInside];
    [c2 addSubview:self.loopSwitch];
    UIButton *reset = [self makeActionButton:@"重置区间"];
    reset.frame = CGRectMake(W - cardPad - 92, cardPad + rowH + gap, 92, rowH);
    [reset setTitleColor:[UIColor colorWithRed:0.88 green:0.40 blue:0.40 alpha:1.0] forState:UIControlStateNormal];
    reset.backgroundColor = [UIColor colorWithRed:0.23 green:0.16 blue:0.16 alpha:1.0];
    reset.titleLabel.font = [UIFont systemFontOfSize:12];
    [reset addTarget:self action:@selector(resetLoop) forControlEvents:UIControlEventTouchUpInside];
    [c2 addSubview:reset];
    c2.frame = CGRectMake(x0, y, W, cardPad + 2 * rowH + gap + cardPad);
    y = [self note:kNoteLoop afterCard:c2 x:x0 y:y w:W] + secGap;

    }   // 循环段（能力不足则不建）

    // ============ ③ 判定窗口（含自动演奏） ============
    {   // Keep controls visible; refresh disables them and explains missing capabilities.
    [self sectionLabel:@"判定窗口" hint:nil x:x0 y:y w:W - 76];
    self.judgeApplyBtn = [self makeActionButton:@"应用"];
    self.judgeApplyBtn.frame = CGRectMake(x0 + W - 64, y - 5, 64, 26);
    self.judgeApplyBtn.titleLabel.font = [UIFont systemFontOfSize:12];
    [self.judgeApplyBtn addTarget:self action:@selector(commitJudge) forControlEvents:UIControlEventTouchUpInside];
    [B addSubview:self.judgeApplyBtn];
    y += secH + 4;
    UIView *c3 = [self cardAt:x0 y:y w:W];
    int vals[4];
    xrc_judge_get_windows(&vals[0], &vals[1], &vals[2], &vals[3]);
    const char *kn[4] = { "Max", "Pure", "Far", "Lost" };
    CGFloat cellW = (W - cardPad * 2 - gap) / 2.0;
    self.judgeFields = [NSMutableArray array];
    for (int i = 0; i < 4; i++) {
        CGFloat cx = cardPad + (i % 2) * (cellW + gap);
        CGFloat cy = cardPad + (i / 2) * (rowH + 11);
        UILabel *k = [[UILabel alloc] initWithFrame:CGRectMake(cx, cy, cellW, 11)];
        k.text = @(kn[i]);
        k.font = [UIFont systemFontOfSize:9];
        k.textColor = [UIColor colorWithWhite:0.62 alpha:1.0];
        [c3 addSubview:k];
        UITextField *tf = [[UITextField alloc] initWithFrame:CGRectMake(cx, cy + 12, cellW, 26)];
        tf.borderStyle = UITextBorderStyleRoundedRect;
        tf.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightRegular];
        tf.textAlignment = NSTextAlignmentCenter;
        tf.keyboardType = UIKeyboardTypeNumberPad;
        tf.text = [NSString stringWithFormat:@"%d", vals[i]];
        tf.delegate = (id<UITextFieldDelegate>)self;
        [c3 addSubview:tf];
        [self.judgeFields addObject:tf];
    }
    self.swAutoplay = [[XRCSwitchRow alloc] initWithTitle:@"自动演奏"];
    self.swAutoplay.note = kNoteJudge;
    {
        xrc_config_t c; xrc_config_load(&c);
        self.swAutoplay.on = c.autoplay;
    }
    CGFloat apY = cardPad + 2 * (rowH + 11) + 6;
    self.swAutoplay.frame = CGRectMake(cardPad, apY, W - cardPad * 2, rowH);
    [self.swAutoplay addTarget:self action:@selector(toggleAutoplay) forControlEvents:UIControlEventTouchUpInside];
    [c3 addSubview:self.swAutoplay];
    self.swJudgeTimeLock = [[XRCSwitchRow alloc] initWithTitle:@"锁定判定区间"];
    self.swJudgeTimeLock.note = @"按现实毫秒判定：例如 ±25 ms 在 0.5x 和 2x 下仍是 ±25 ms。新判定预筛选桩齐全时可用。";
    self.swJudgeTimeLock.on = xrc_judge_time_lock();
    self.swJudgeTimeLock.frame = CGRectMake(cardPad, apY + rowH + 8, W - cardPad * 2, rowH);
    [self.swJudgeTimeLock addTarget:self action:@selector(toggleJudgeTimeLock) forControlEvents:UIControlEventTouchUpInside];
    [c3 addSubview:self.swJudgeTimeLock];
    c3.frame = CGRectMake(x0, y, W, apY + 2 * rowH + 8 + cardPad);
    y += c3.frame.size.height + 2;
    self.judgeHdr = [[UILabel alloc] initWithFrame:CGRectMake(x0 + 2, y, W - 4, 12)];
    self.judgeHdr.font = [UIFont systemFontOfSize:10];
    self.judgeHdr.textColor = [UIColor colorWithWhite:0.55 alpha:1.0];
    [B addSubview:self.judgeHdr];
    y += 12;
    y = [self note:kNoteJudge at:x0 y:y w:W] + secGap;

    }   // 判定段（无桩时显示禁用原因）

    // Konzetsu practice: menu choices and two persistent toggle buttons.
    [self sectionLabel:@"Konzetsu 练习" hint:@"下次开局生效" x:x0 y:y w:W];
    y += secH + 4;
    UIView *kc = [self cardAt:x0 y:y w:W];
    self.konzetsuSelect = [self makeActionButton:@"选择挑战"];
    self.konzetsuSelect.frame = CGRectMake(cardPad, cardPad, W - cardPad * 2, rowH);
    [self.konzetsuSelect addTarget:self action:@selector(cycleKonzetsu) forControlEvents:UIControlEventTouchUpInside];
    [kc addSubview:self.konzetsuSelect];
    [self updateKonzetsuMenu];
    CGFloat kw = (W - cardPad * 2 - gap) / 2;
    self.swKonzetsuEnabled = [[XRCSwitchRow alloc] initWithTitle:@"启用"];
    self.swKonzetsuEnabled.note = @"把选中的效果应用于下一次加载的谱面。游玩中更改不会修改本局；退出选曲再开局应用新设置。";
    self.swKonzetsuEnabled.frame = CGRectMake(cardPad, cardPad + rowH + gap, kw, rowH);
    [self.swKonzetsuEnabled addTarget:self action:@selector(toggleKonzetsuEnabled) forControlEvents:UIControlEventTouchUpInside];
    [kc addSubview:self.swKonzetsuEnabled];
    self.swKonzetsuChallenge = [[XRCSwitchRow alloc] initWithTitle:@"挑战"];
    self.swKonzetsuChallenge.note = @"与启用同时打开时使用挑战血条；只打开启用则使用普通橘色 HARD 血条。挑战开关会记住选择，但单独开启不会改变游戏。";
    self.swKonzetsuChallenge.frame = CGRectMake(cardPad + kw + gap, cardPad + rowH + gap, kw, rowH);
    [self.swKonzetsuChallenge addTarget:self action:@selector(toggleKonzetsuChallenge) forControlEvents:UIControlEventTouchUpInside];
    [kc addSubview:self.swKonzetsuChallenge];
    kc.frame = CGRectMake(x0, y, W, cardPad * 2 + rowH * 2 + gap);
    y = [self note:@"选项：下隐、变速、上下反、点血条、综合。普通歌曲的综合按谱面时长生成练习时间表；点血条配合挑战开关使用。" afterCard:kc x:x0 y:y w:W] + secGap;

    // ============ ④ 解锁 ============
    // 解锁：按构建期功能集显示；一项都没有则整段隐藏
    {
    int present = 0;
    for (NSString *f in @[@"unlock_own", @"cb_free"])
        if (xrc_feature_present(f.UTF8String)) present++;
    if (present > 0) {
    [self sectionLabel:@"解锁" hint:@"离线/未授予时才有意义" x:x0 y:y w:W];
    y += secH + 4;
    UIView *c4 = [self cardAt:x0 y:y w:W];
    {
        NSArray *titles = @[@"拥有链", @"cb 自由化"];
        NSArray *sels  = @[@"toggleOwn", @"toggleCb"];
        // 构建期功能集：只建本构建注入了的项；判断见 xrc_feature_present
        NSArray *feats = @[@"unlock_own", @"cb_free"];
        NSArray *notes = @[
            @"把\"这歌我有没有\"的三层判定都当成立。归属由 cb 三清单(songlist/packlist/unlocks)+服务器授予共同决定，本项覆盖\"未授予但本地有内容\"的情形。",
            @"内容包校验恒通过（文件哈希与三清单比对恒等），校验失败不清树。离线改谱面/删文件的前提。"];
        CGFloat bw = (W - cardPad * 2 - gap) / 2.0;
        int shown = 0;
        for (NSUInteger i = 0; i < titles.count; i++) {
            if (!xrc_feature_present([feats[i] UTF8String])) continue;   // 本构建未含该功能
            XRCSwitchRow *row = [[XRCSwitchRow alloc] initWithTitle:titles[i]];
            row.note = notes[i];
            BOOL fullRow = NO;
            row.frame = fullRow ? CGRectMake(cardPad, cardPad + (shown / 2) * (rowH + gap),
                                             W - cardPad * 2, rowH)
                                : CGRectMake(cardPad + (shown % 2) * (bw + gap),
                                             cardPad + (shown / 2) * (rowH + gap), bw, rowH);
            [row addTarget:self action:NSSelectorFromString(sels[i]) forControlEvents:UIControlEventTouchUpInside];
            [c4 addSubview:row];
            switch (i) {
                case 0: self.swOwn = row; break;
                case 1: self.swCb = row; break;
            }
            shown++;
        }
        int rows = shown ? (shown + 1) / 2 : 1;
        c4.frame = CGRectMake(x0, y, W, cardPad + rows * rowH + (rows - 1) * gap + cardPad);
        NSString *legend = @"长按任一项看该项说明。";
        y = [self note:[legend stringByAppendingString:
                          @"\n拥有链=三层判定恒真｜cb 自由化=校验恒通过且内容树保留。"]
                  afterCard:c4 x:x0 y:y w:W] + secGap;
    }
    }        // present>0
    }        // 解锁段外层

    // ============ ⑤ 网络（地址折叠） ============
    [self sectionLabel:@"网络" hint:@"只改 API 域名，不动 TLS" x:x0 y:y w:W];
    y += secH + 4;
    UIView *c5 = [self cardAt:x0 y:y w:W];
    self.swNet = [[XRCSwitchRow alloc] initWithTitle:@"私服"];
    self.swNet.tone = 1;                                 // 1 = 网络色（青）
    self.swNet.note = kNoteNet;
    self.swNet.frame = CGRectMake(cardPad, cardPad, 96, rowH);
    [self.swNet addTarget:self action:@selector(toggleNet) forControlEvents:UIControlEventTouchUpInside];
    [c5 addSubview:self.swNet];
    self.netFoldBtn = [self makeActionButton:(self.netExpanded ? @"服务端地址 ▾" : @"服务端地址 ▸")];
    self.netFoldBtn.titleLabel.font = [UIFont systemFontOfSize:11];
    self.netFoldBtn.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    self.netFoldBtn.frame = CGRectMake(cardPad + 96 + gap, cardPad + 2, W - cardPad * 2 - 96 - gap, 26);
    [self.netFoldBtn addTarget:self action:@selector(toggleNetFold) forControlEvents:UIControlEventTouchUpInside];
    [c5 addSubview:self.netFoldBtn];
    CGFloat ny = cardPad + rowH + 6;
    if (self.netExpanded) {
        self.netField = [[UITextField alloc] initWithFrame:CGRectMake(cardPad, ny, W - cardPad * 2, 26)];
        self.netField.borderStyle = UITextBorderStyleRoundedRect;
        self.netField.font = [UIFont monospacedDigitSystemFontOfSize:11 weight:UIFontWeightRegular];
        self.netField.placeholder = @"http://192.168.1.10:8080";
        self.netField.autocapitalizationType = UITextAutocapitalizationTypeNone;
        self.netField.autocorrectionType = UITextAutocorrectionTypeNo;
        self.netField.keyboardType = UIKeyboardTypeURL;
        self.netField.returnKeyType = UIReturnKeyDone;
        self.netField.delegate = (id<UITextFieldDelegate>)self;
        {
            xrc_config_t c; xrc_config_load(&c);
            self.netField.text = c.net_base ?: @"";
        }
        [c5 addSubview:self.netField];
        ny += 26 + 6;
    } else {
        self.netField = nil;
    }
    self.netStat = [[UILabel alloc] initWithFrame:CGRectMake(cardPad, ny, W - cardPad * 2, 12)];
    self.netStat.font = [UIFont systemFontOfSize:10];
    self.netStat.textColor = [UIColor colorWithWhite:0.55 alpha:1.0];
    [c5 addSubview:self.netStat];
    c5.frame = CGRectMake(x0, y, W, ny + 12 + cardPad);
    y = [self note:kNoteNet afterCard:c5 x:x0 y:y w:W] + secGap;

    // ============ ⑥ 存储（外置）============
    // 纯 dylib 功能：不依赖任何二进制补丁，注入未打桩的二进制也照常可用（能力模型）。
    {
    [self sectionLabel:@"存储" hint:@"免越狱自用通道" x:x0 y:y w:W];
    y += secH + 4;
    UIView *c6 = [self cardAt:x0 y:y w:W];
    self.swStore = [[XRCSwitchRow alloc] initWithTitle:@"cb 外置"];
    self.swStore.note = kNoteStore;
    {
        xrc_config_t c; xrc_config_load(&c);
        self.swStore.on = c.external_cb;
    }
    self.swStore.frame = CGRectMake(cardPad, cardPad, 120, rowH);
    [self.swStore addTarget:self action:@selector(toggleStore) forControlEvents:UIControlEventTouchUpInside];
    [c6 addSubview:self.swStore];
    self.storeStat = [[UILabel alloc] initWithFrame:CGRectMake(cardPad, cardPad + rowH + 4,
                                                              W - cardPad * 2, 12)];
    self.storeStat.font = [UIFont systemFontOfSize:10];
    self.storeStat.textColor = [UIColor colorWithWhite:0.55 alpha:1.0];
    [c6 addSubview:self.storeStat];
    c6.frame = CGRectMake(x0, y, W, cardPad + rowH + 4 + 12 + cardPad);
    y = [self note:kNoteStore afterCard:c6 x:x0 y:y w:W] + secGap;
    }

    // ============ ⑦ 诊断（状态两行 + 开发构建专属工具区） ============
    [self sectionLabel:@"诊断" hint:@"日志 xrcdemo.log" x:x0 y:y w:W];
    y += secH + 4;
    UIView *c7 = [self cardAt:x0 y:y w:W];
    self.capsLabel = [[UILabel alloc] initWithFrame:CGRectMake(cardPad, cardPad, W - cardPad * 2, 12)];
    self.capsLabel.font = [UIFont systemFontOfSize:10];
    self.capsLabel.textColor = [UIColor colorWithWhite:0.62 alpha:1.0];
    [c7 addSubview:self.capsLabel];
    self.patchLine = [[UILabel alloc] initWithFrame:CGRectMake(cardPad, cardPad + 14, W - cardPad * 2, 12)];
    self.patchLine.font = [UIFont systemFontOfSize:10];
    self.patchLine.textColor = [UIColor colorWithWhite:0.62 alpha:1.0];
    [c7 addSubview:self.patchLine];
    CGFloat cy = cardPad + 30;

#if XRC_DEV_SECTION
    // ---- 开发构建专属区（发布构建整段编出） ----
    UIView *div = [[UIView alloc] initWithFrame:CGRectMake(cardPad, cy, W - cardPad * 2, 1)];
    div.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.10];
    [c7 addSubview:div];
    cy += 9;
    UILabel *dev = [[UILabel alloc] initWithFrame:CGRectMake(cardPad, cy, W - cardPad * 2, 12)];
    dev.text = @"开发构建专属 —— 工具仅存在于开发构建";
    dev.font = [UIFont systemFontOfSize:10];
    dev.textColor = [UIColor colorWithRed:0.18 green:0.64 blue:0.64 alpha:1.0];
    [c7 addSubview:dev];
    cy += 16;
    self.logSeg = [[UISegmentedControl alloc] initWithItems:@[@"默认", @"详细", @"网络"]];
    self.logSeg.frame = CGRectMake(cardPad, cy, W - cardPad * 2, 28);
    self.logSeg.selectedSegmentIndex = [self logPresetIndex];
    [self.logSeg addTarget:self action:@selector(logSegChanged:) forControlEvents:UIControlEventValueChanged];
    [c7 addSubview:self.logSeg];
    cy += 28 + 8;
    {
        CGFloat bw2 = (W - cardPad * 2 - gap) / 2.0;
        UIButton *b1 = [self makeActionButton:@"转储内存"];
        b1.titleLabel.font = [UIFont systemFontOfSize:11];
        b1.frame = CGRectMake(cardPad, cy, bw2, 26);
        [b1 addTarget:self action:@selector(dumpMemory) forControlEvents:UIControlEventTouchUpInside];
        [c7 addSubview:b1];
        UIButton *b2 = [self makeActionButton:@"清理转储"];
        b2.titleLabel.font = [UIFont systemFontOfSize:11];
        b2.frame = CGRectMake(cardPad + bw2 + gap, cy, bw2, 26);
        [b2 addTarget:self action:@selector(cleanDump) forControlEvents:UIControlEventTouchUpInside];
        [c7 addSubview:b2];
        cy += 26 + 8;
        UIButton *b3 = [self makeActionButton:@"OM 探针"];
        b3.titleLabel.font = [UIFont systemFontOfSize:11];
        b3.frame = CGRectMake(cardPad, cy, bw2, 26);
        [b3 addTarget:self action:@selector(omProbe) forControlEvents:UIControlEventTouchUpInside];
        [c7 addSubview:b3];
        UIButton *b4 = [self makeActionButton:@"强制 applog"];
        b4.titleLabel.font = [UIFont systemFontOfSize:11];
        b4.frame = CGRectMake(cardPad + bw2 + gap, cy, bw2, 26);
        [b4 addTarget:self action:@selector(forceApplog) forControlEvents:UIControlEventTouchUpInside];
        [c7 addSubview:b4];
        cy += 26 + 8;
    }
    self.swStubsLite = [[XRCSwitchRow alloc] initWithTitle:@"观测桩轻量"];
    self.swStubsLite.note = @"观测桩重活停摆、只推进 PC（仍保留 SIGTRAP 成本）。";
    {
        xrc_config_t c; xrc_config_load(&c);
        self.swStubsLite.on = c.stubs_lite;
    }
    self.swStubsLite.frame = CGRectMake(cardPad, cy, W - cardPad * 2, rowH);
    [self.swStubsLite addTarget:self action:@selector(toggleStubsLite) forControlEvents:UIControlEventTouchUpInside];
    [c7 addSubview:self.swStubsLite];
    cy += rowH + 6;
    UILabel *dn = [[UILabel alloc] initWithFrame:CGRectMake(cardPad, cy, W - cardPad * 2, 26)];
    dn.font = [UIFont systemFontOfSize:10];
    dn.numberOfLines = 0;
    dn.textColor = [UIColor colorWithWhite:0.48 alpha:1.0];
    dn.text = kNoteDev;
    [c7 addSubview:dn];
    cy += 26;
#endif

    c7.frame = CGRectMake(x0, y, W, cy + cardPad);
    y = [self note:kNoteDiag afterCard:c7 x:x0 y:y w:W] + 10;

    // 页脚：长按提示 + 版权行（常显）
    UILabel *foot = [[UILabel alloc] initWithFrame:CGRectMake(x0, y, W, 12)];
    foot.font = [UIFont systemFontOfSize:10];
    foot.textColor = [UIColor colorWithWhite:0.42 alpha:1.0];
    foot.text = @"长按任一项 = 查看说明；单击 = 切换。";
    [B addSubview:foot];
    y += 14;
    UILabel *copy = [[UILabel alloc] initWithFrame:CGRectMake(x0, y, W, 12)];
    copy.font = [UIFont systemFontOfSize:10];
    copy.textAlignment = NSTextAlignmentCenter;
    copy.textColor = [UIColor colorWithWhite:0.36 alpha:1.0];
    copy.text = @"© 雾月星辰&MLXC/github@XingChenRS";
    [B addSubview:copy];
    y += 14;

    self.contentHeight = y;
}

// 说明行（仅在 ⓘ 模式）；返回新的 y
- (CGFloat)note:(NSString *)text at:(CGFloat)x y:(CGFloat)y w:(CGFloat)w {
    if (!self.infoOn || !text.length) return y;
    UIFont *f = [UIFont systemFontOfSize:10];
    CGRect r = [text boundingRectWithSize:CGSizeMake(w - 4, 600)
                                  options:NSStringDrawingUsesLineFragmentOrigin
                               attributes:@{ NSFontAttributeName: f } context:nil];
    CGFloat h = ceil(r.size.height) + 6;
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(x + 2, y, w - 4, h)];
    l.font = f;
    l.numberOfLines = 0;
    l.textColor = [UIColor colorWithWhite:0.56 alpha:1.0];
    l.text = text;
    [self.body addSubview:l];
    return y + h;
}
- (CGFloat)note:(NSString *)text afterCard:(UIView *)card x:(CGFloat)x y:(CGFloat)y w:(CGFloat)w {
    return [self note:text at:x y:CGRectGetMaxY(card.frame) w:w];
}

// ---------------- 小组件 ----------------
- (void)sectionLabel:(NSString *)title hint:(NSString *)hint x:(CGFloat)x y:(CGFloat)y w:(CGFloat)w {
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(x + 2, y + 1, 160, 12)];
    l.text = title.uppercaseString;
    l.font = [UIFont systemFontOfSize:10 weight:UIFontWeightMedium];
    l.textColor = [UIColor colorWithWhite:0.55 alpha:1.0];
    [self.body addSubview:l];
    if (hint.length && w > 60) {
        UILabel *h = [[UILabel alloc] initWithFrame:CGRectMake(x + w - 240, y + 1, 240, 12)];
        h.text = hint;
        h.textAlignment = NSTextAlignmentRight;
        h.font = [UIFont systemFontOfSize:10];
        h.textColor = [UIColor colorWithWhite:0.40 alpha:1.0];
        [self.body addSubview:h];
    }
}

- (UIView *)cardAt:(CGFloat)x y:(CGFloat)y w:(CGFloat)w {
    UIView *c = [[UIView alloc] initWithFrame:CGRectMake(x, y, w, 10)];
    c.backgroundColor = [UIColor colorWithWhite:0.10 alpha:1.0];
    c.layer.cornerRadius = 10;
    [self.body addSubview:c];
    return c;
}

- (UIButton *)makeActionButton:(NSString *)title {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    [b setTitle:title forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    b.backgroundColor = [UIColor colorWithWhite:0.23 alpha:1.0];
    b.layer.cornerRadius = 6;
    return b;
}

// ---------------- 拖动 + 位置持久化（经 XRCConfig 单一通道） ----------------
- (CGPoint)savedOrigin {
    NSDictionary *p = xrc_config_dict();
    double x = [p[@"panelX"] doubleValue], y = [p[@"panelY"] doubleValue];
    if (x == 0 && y == 0) return CGPointMake(CGFLOAT_MAX, CGFLOAT_MAX);   // 0,0 = 未设置
    return CGPointMake(x, y);
}
- (void)saveOrigin:(CGPoint)o {
    NSMutableDictionary *p = xrc_config_dict();
    p[@"panelX"] = @(o.x); p[@"panelY"] = @(o.y);
    xrc_config_write_dict(p);
}
- (void)onDragPanel:(UIPanGestureRecognizer *)g {
    UIView *w = self.superview;
    if (!w) return;
    CGPoint t = [g translationInView:w];
    CGRect f = self.frame;
    f.origin.x += t.x; f.origin.y += t.y;
    f.origin.x = MIN(MAX(f.origin.x, -f.size.width + 60), w.bounds.size.width - 60);
    f.origin.y = MIN(MAX(f.origin.y, 0), MAX(0, w.bounds.size.height - 40));
    self.frame = f;
    [g setTranslation:CGPointZero inView:w];
    if (g.state == UIGestureRecognizerStateEnded || g.state == UIGestureRecognizerStateCancelled) {
        self.autoresizingMask = UIViewAutoresizingNone;
        [self saveOrigin:f.origin];
    }
}

// ---------------- 动作 ----------------
- (void)toggleRepeat {
    if (xrc_loop_get_enabled()) {
        xrc_loop_set_enabled(false);
    } else {
        uint32_t from = 0, to = 0;
        xrc_loop_get_range(&from, &to);
        if (to <= from + 1000) {
            [WHToast showMessage:@"请先设置循环起点和终点" duration:1.4 finishHandler:^{}];
            return;
        }
        xrc_loop_set_enabled(true);
    }
    [self refresh];
}

- (void)setFrom {
    uint32_t pos = xrc_player_position_ms();
    xrc_loop_set_enabled(false);
    xrc_loop_set_range(pos, 0);
    self.pendingTo = YES;
    uint32_t s = pos / 1000;
    [WHToast showMessage:[NSString stringWithFormat:@"起点 %02u:%02u，播放到终点再按 设终点 B",
                          s / 60, s % 60] duration:1.4 finishHandler:^{}];
    [self refresh];
}

- (void)setTo {
    uint32_t from = 0, oldTo = 0;
    xrc_loop_get_range(&from, &oldTo);
    BOOL hasFrom = self.pendingTo || (oldTo > from + 1000) || (from > 0);
    if (!hasFrom) {
        [WHToast showMessage:@"请先播放到起点位置按 设起点 A" duration:1.4 finishHandler:^{}];
        return;
    }
    uint32_t pos = xrc_player_position_ms();
    if (pos < from + 1000) {
        [WHToast showMessage:@"终点需在起点 1 秒之后" duration:1.4 finishHandler:^{}];
        return;
    }
    xrc_loop_set_enabled(false);
    xrc_loop_set_range(from, pos);
    self.pendingTo = NO;
    uint32_t fs = from / 1000, ts = pos / 1000;
    [WHToast showMessage:[NSString stringWithFormat:@"循环区间 %02u:%02u - %02u:%02u，可开循环",
                          fs / 60, fs % 60, ts / 60, ts % 60] duration:1.4 finishHandler:^{}];
    [self refresh];
}

- (void)resetLoop {
    xrc_loop_reset_all();
    self.pendingTo = NO;
    [WHToast showMessage:@"循环区间已重置" duration:1.0 finishHandler:^{}];
    [self refresh];
}

- (void)jumpBack    { [self jump:-1]; }
- (void)jumpForward { [self jump:+1]; }
- (void)jump:(int)dir {
    uint32_t pos = xrc_player_position_ms();
    uint32_t dur = (uint32_t)(5000 * xrc_clock_get_rate());
    uint32_t target = (dir < 0) ? (pos > dur ? pos - dur : 0) : pos + dur;
    uint32_t len = xrc_player_song_length_ms();
    if (dir > 0 && len && target > len) target = len;
    xrc_gameplay_request(XRC_OP_SEEK, target);
}

// Preview only during drag; commit the rate and resynchronise once on release.
- (void)speedChanged:(UISlider *)s {
    float snap = roundf(s.value / 0.05f) * 0.05f;
    if (snap < 0.05f) snap = 0.05f;
    self.speedLabel.text = [NSString stringWithFormat:@"%.2fx", snap];
}
- (void)speedCommit:(UISlider *)s {
    float snap = roundf(s.value / 0.05f) * 0.05f;
    if (snap < 0.05f) snap = 0.05f;
    xrc_gameplay_set_rate((double)snap);
    xrc_config_set_current_speed(snap);
}

- (void)commitJudge {
    if (!self.judgeFields.count) return;   // 无桩时不建该区（能力门控）
    int v[4];
    for (int i = 0; i < 4 && i < (int)self.judgeFields.count; i++)
        v[i] = MAX(1, [self.judgeFields[i].text intValue]);
    if (v[1] <= v[0]) v[1] = v[0] + 1;
    if (v[2] <= v[1]) v[2] = v[1] + 1;
    if (v[3] <= v[2]) v[3] = v[2] + 1;
    for (int i = 0; i < 4 && i < (int)self.judgeFields.count; i++)
        self.judgeFields[i].text = [NSString stringWithFormat:@"%d", v[i]];
    xrc_judge_set_windows(v[0], v[1], v[2], v[3]);
    xrc_config_t cfg; xrc_config_load(&cfg);
    cfg.judge_max_ms = v[0]; cfg.judge_pure_ms = v[1];
    cfg.judge_far_ms = v[2]; cfg.judge_lost_ms = v[3];
    xrc_config_save(&cfg);
    [self.judgeFields.firstObject resignFirstResponder];
    if (cfg.toast) {
        [WHToast showMessage:[NSString stringWithFormat:@"判定窗口 ±%d/%d/%d/%d", v[0], v[1], v[2], v[3]]
                    duration:1.0 finishHandler:^{}];
    }
    [self refresh];
}

- (void)commitFlow {
    if (!xrc_rate_adapt_flow_available() || !xrc_cap_gp()) return;
    NSString *text = [self.flowField.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSScanner *scanner = [NSScanner scannerWithString:text ?: @""];
    double speed = 0; uint64_t units = 0;
    if (![scanner scanDouble:&speed] || !scanner.isAtEnd || !xrc_live_flow_units(speed, &units)) {
        [WHToast showMessage:@"请输入 0.1–214748364.7 的流速；保留一位小数" duration:1.8 finishHandler:^{}];
        return;
    }
    if (!xrc_rate_adapt_set_manual_flow(speed)) {
        [WHToast showMessage:@"原生流速写入未确认，请查看 [flow-native] 日志" duration:1.8 finishHandler:^{}];
        return;
    }
    xrc_config_t config; xrc_config_load(&config);
    config.manual_note_flow = xrc_rate_adapt_manual_flow();
    xrc_config_save(&config);
    [self.flowField resignFirstResponder];
    [self refresh];
    [WHToast showMessage:@"流速已写入游戏设置；本局下一安全帧应用" duration:1.6 finishHandler:^{}];
}
- (void)restoreNativeFlow {
    xrc_rate_adapt_set_manual_flow(0);
    xrc_config_t config; xrc_config_load(&config);
    config.manual_note_flow = 0;
    xrc_config_save(&config);
    [self.flowField resignFirstResponder];
    [self refresh];
    [WHToast showMessage:@"取消插件覆盖，沿用当前游戏流速" duration:1.6 finishHandler:^{}];
}

- (void)toggleJudgeTimeLock {
    if (!xrc_judge_is_active() || !xrc_feature_complete("judge_time_lock")) return;
    xrc_config_t cfg; xrc_config_load(&cfg);
    cfg.judge_time_lock = !cfg.judge_time_lock;
    xrc_config_save(&cfg);
    xrc_judge_set_time_lock(cfg.judge_time_lock);
    [self refresh];
}

- (void)updateKonzetsuMenu {
    xrc_config_t config; xrc_config_load(&config);
    NSArray<NSString *> *names = @[@"下隐", @"变速", @"上下反", @"点血条", @"综合"];
    NSArray<NSNumber *> *ids = @[@1, @2, @3, @4, @6];
    NSUInteger index = [ids indexOfObject:@(config.konzetsu_id)];
    if (index == NSNotFound) index = 0;
    [self.konzetsuSelect setTitle:[NSString stringWithFormat:@"选择挑战：%@", names[index]] forState:UIControlStateNormal];
}
- (void)cycleKonzetsu {
    if (!xrc_konzetsu_available()) return;
    xrc_config_t config; xrc_config_load(&config);
    NSArray<NSNumber *> *ids = @[@1, @2, @3, @4, @6];
    NSUInteger index = [ids indexOfObject:@(config.konzetsu_id)];
    config.konzetsu_id = ids[index == NSNotFound ? 0 : (index + 1) % ids.count].intValue;
    xrc_config_save(&config);
    xrc_konzetsu_configure(config.konzetsu_id, config.konzetsu_enabled, config.konzetsu_challenge);
    [self refresh];
}
- (void)toggleHideDuringPlay {
    xrc_config_t config; xrc_config_load(&config);
    config.hide_button_during_play = !config.hide_button_during_play;
    xrc_config_save(&config);
    [[XRCFloatButton shared] setHideDuringGameplay:config.hide_button_during_play];
    [self refresh];
}
- (void)toggleKonzetsuEnabled {
    if (!xrc_konzetsu_available()) return;
    xrc_config_t config; xrc_config_load(&config);
    config.konzetsu_enabled = !config.konzetsu_enabled;
    xrc_config_save(&config);
    xrc_konzetsu_configure(config.konzetsu_id, config.konzetsu_enabled, config.konzetsu_challenge);
    [self refresh];
    [WHToast showMessage:@"效果开关已保存，下一次开局生效" duration:1.4 finishHandler:^{}];
}
- (void)toggleKonzetsuChallenge {
    if (!xrc_konzetsu_available()) return;
    xrc_config_t config; xrc_config_load(&config);
    config.konzetsu_challenge = !config.konzetsu_challenge;
    xrc_config_save(&config);
    xrc_konzetsu_configure(config.konzetsu_id, config.konzetsu_enabled, config.konzetsu_challenge);
    [self refresh];
    [WHToast showMessage:@"血条开关已保存，下一次开局生效" duration:1.4 finishHandler:^{}];
}

// 开关：统一"读配置 → 翻转 → 保存 → 即时生效 → 刷新"路径
#define XRC_TOGGLE_SWITCH(KEY, SETTER, ONMSG, OFFMSG)                                   \
    do {                                                                                \
        xrc_config_t c; xrc_config_load(&c);                                            \
        c.KEY = !c.KEY; xrc_config_save(&c);                                            \
        SETTER(c.KEY);                                                                  \
        [WHToast showMessage:(c.KEY ? ONMSG : OFFMSG) duration:1.4 finishHandler:^{}];  \
        [self refresh];                                                                 \
    } while (0)

- (void)toggleRateOffset { XRC_TOGGLE_SWITCH(rate_adapt_offset, xrc_rate_adapt_set_offset, @"偏移适配：开，下个安全帧生效", @"偏移适配：关，恢复原偏移"); }
- (void)toggleRateFlow { XRC_TOGGLE_SWITCH(rate_adapt_flow, xrc_rate_adapt_set_flow, @"流速适配：开，下个安全帧生效", @"流速适配：关，恢复原流速"); }
- (void)toggleOwn      { XRC_TOGGLE_SWITCH(unlock_own, xrc_brk_set_unlock_own, @"拥有链：三层恒真（覆盖未授予场景）", @"拥有链：恢复原判定"); }
- (void)toggleCb       { XRC_TOGGLE_SWITCH(cb_bypass,  xrc_brk_set_cb_bypass,  @"cb 自由化：校验恒通过 + 清树禁用", @"cb 校验：恢复原行为"); }
- (void)toggleResetScore   { XRC_TOGGLE_SWITCH(reset_score, xrc_replay_set_reset_score, @"回拖时重置成绩", @"回拖时保留成绩"); }

// 自动演奏：走判定链（不依赖补丁站点集之外的开关组）
- (void)toggleAutoplay {
    xrc_config_t c; xrc_config_load(&c);
    c.autoplay = !c.autoplay;
    xrc_config_save(&c);
    xrc_judge_set_autoplay(c.autoplay);
    self.swAutoplay.on = c.autoplay;
    if (c.toast) {
        [WHToast showMessage:(c.autoplay ? @"自动演奏：全部判定 → Pure" : @"自动演奏：关")
                    duration:1.4 finishHandler:^{}];
    }
    [self refresh];
}

// 存储外置：开 = 立刻做一次迁移（幂等）；关 = 只停用迁移，已建软链不动。
// 状态行由 refresh 从文件系统实读（软链在不在），所以这里的 toast 只说动作结果。
- (void)toggleStore {
    xrc_config_t c; xrc_config_load(&c);
    c.external_cb = !c.external_cb;
    xrc_config_save(&c);
    self.swStore.on = c.external_cb;
    if (c.external_cb) {
        int r = xrc_store_install();
        if (c.toast) {
            [WHToast showMessage:(r == 0 ? @"cb 已搬到 Documents（瞬间完成）"
                                    : (r == 1 ? @"cb 已是外置态" : @"迁移失败，看日志"))
                        duration:1.6 finishHandler:^{}];
        }
    } else if (c.toast) {
        [WHToast showMessage:@"cb 外置已关（已建软链不会自动撤销）" duration:1.8 finishHandler:^{}];
    }
    self.storeStat.text = xrc_store_cb_status();
    xrc_logd(XRCLC_UI, @"cb 外置 → %s ｜ %@", c.external_cb ? "on" : "off", xrc_store_cb_status());
}

// 音乐变速：开 = BGM 跟着速度走且保音高（FMOD 源时钟 + 实时高质量拉伸）；
// 关 = 立刻把音高复位到 1.0（只 warp 谱面时钟）。
- (void)toggleSpeedAudio {
    xrc_config_t c; xrc_config_load(&c);
    c.speed_audio = !c.speed_audio;
    xrc_config_save(&c);
    xrc_audio_speed_set_enabled(c.speed_audio);
    self.swSpeedAudio.on = c.speed_audio;
    if (c.toast) {
        [WHToast showMessage:(c.speed_audio ? @"音乐变速：开（BGM 跟随速度，保音高）"
                                            : @"音乐变速：关（BGM 恒 1.0x，音画会错开）")
                    duration:1.6 finishHandler:^{}];
    }
    xrc_logd(XRCLC_UI, @"音乐变速 → %s ｜ %@", c.speed_audio ? "on" : "off", xrc_audio_speed_status());
}

- (void)toggleNet {
    xrc_config_t c; xrc_config_load(&c);
    if (!c.net_enabled) {
        NSString *base = self.netField ? [self.netField.text stringByTrimmingCharactersInSet:
                                              [NSCharacterSet whitespaceCharacterSet]]
                                       : @"";
        if (!base.length) base = c.net_base ?: @"";
        if (!base.length) {
            self.netExpanded = YES;   // 没地址就先展开输入区
            [self rebuildContent];
            [WHToast showMessage:@"请先填服务端地址（如 http://192.168.1.10:8080）"
                        duration:1.6 finishHandler:^{}];
            return;
        }
        c.net_base = base;
    }
    c.net_enabled = !c.net_enabled;
    xrc_config_save(&c);
    xrc_net_set_base(c.net_base ? c.net_base.UTF8String : NULL);
    xrc_net_set_enabled(c.net_enabled);
    [WHToast showMessage:c.net_enabled ? [NSString stringWithFormat:@"私服 开 → %@", c.net_base]
                                      : @"私服 关（走官方域）"
                duration:1.4 finishHandler:^{}];
    [self refresh];
}

- (void)toggleNetFold {
    self.netExpanded = !self.netExpanded;
    [self rebuildContent];
}

// 日志档位：三选分段（默认/详细/网络）→ 应用运行期预设 + 持久化 level/cats（重启保持）
- (NSInteger)logPresetIndex {
    int lv = xrc_log_level();
    uint32_t cats = xrc_log_cats();
    if (lv >= 3) return (cats == (XRCLC_NET | XRCLC_DL | XRCLC_BOOT | XRCLC_CB)) ? 2 : 1;
    return 0;
}
- (void)logSegChanged:(UISegmentedControl *)s {
    xrc_config_t c; xrc_config_load(&c);
    switch (s.selectedSegmentIndex) {
        case 1:
            xrc_log_preset_verbose();
            c.log_level = 3; c.log_cats = 0;
            break;
        case 2:
            xrc_log_preset_net();
            c.log_level = 3;
            c.log_cats = (XRCLC_NET | XRCLC_DL | XRCLC_BOOT | XRCLC_CB);
            break;
        default:
            xrc_log_preset_default();
            c.log_level = 2; c.log_cats = 0;
            break;
    }
    xrc_config_save(&c);
    [WHToast showMessage:(s.selectedSegmentIndex == 0 ? @"日志档位：默认"
                                  : (s.selectedSegmentIndex == 1 ? @"日志档位：详细" : @"日志档位：网络"))
                duration:1.0 finishHandler:^{}];
}

#if XRC_DEV_SECTION
- (void)dumpMemory {
    if (xrc_dump_running()) {
        [WHToast showMessage:[NSString stringWithFormat:@"转储进行中 %d/%d",
                              xrc_dump_regions_done(), xrc_dump_regions_total()]
                    duration:1.2 finishHandler:^{}];
        return;
    }
    xrc_dump_start();
    [WHToast showMessage:@"开始转储内存（后台）" duration:1.5 finishHandler:^{}];
}

- (void)cleanDump {
    NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSString *mem = [docs stringByAppendingPathComponent:@"xrcdemo-net/mem"];
    NSError *err = nil;
    [[NSFileManager defaultManager] removeItemAtPath:mem error:&err];
    [WHToast showMessage:(err ? @"清理转储失败（看日志）" : @"转储目录已清理")
                duration:1.2 finishHandler:^{}];
    if (err) xrc_logw(XRCLC_PROBE, @"clean dump failed: %@", err);
}

- (void)omProbe {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        @try { xrc_om_probe(); } @catch (NSException *e) { xrc_logw(XRCLC_OM, @"probe EX: %@", e); }
    });
    [WHToast showMessage:@"OM 探针已派发（后台，看日志）" duration:1.5 finishHandler:^{}];
}

- (void)forceApplog {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"强制 applog"
                                                              message:@"将直调 vtable 槽 72 真实发送一次上报。继续？"
                                                       preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"发送" style:UIAlertActionStyleDestructive
                                       handler:^(UIAlertAction *act) {
        @try { xrc_om_force_applog(); } @catch (NSException *e) { xrc_logw(XRCLC_OM, @"force EX: %@", e); }
    }]];
    UIViewController *root = [self keyWindow].rootViewController;
    [root presentViewController:a animated:YES completion:nil];
}

- (void)toggleStubsLite {
    xrc_config_t c; xrc_config_load(&c);
    c.stubs_lite = !c.stubs_lite;
    xrc_config_save(&c);
    xrc_arc_stubs_lite_set(c.stubs_lite);
    self.swStubsLite.on = c.stubs_lite;
    [WHToast showMessage:(c.stubs_lite ? @"观测桩：轻量模式" : @"观测桩：全量") duration:1.2 finishHandler:^{}];
}
#endif

// ---------------- 刷新 ----------------
// 高频（10Hz）：位置/时长/进度条/速度
- (void)refreshFast {
    static uint64_t lastSeekResult = 0;
    bool seekOK = false;
    uint64_t result = xrc_gameplay_seek_result(&seekOK);
    if (result && result != lastSeekResult) {
        lastSeekResult = result;
        if (!seekOK) [WHToast showMessage:@"跳转未完成或场景已变化，请重试" duration:1.6 finishHandler:^{}];
    }
    uint32_t len = xrc_player_song_length_ms();
    uint32_t pos = xrc_player_position_ms();
    if (len == 0) len = MAX(pos, 1000);
    self.timeline.lengthMs = len;
    self.timeline.positionMs = pos;

    uint32_t from = 0, to = 0;
    BOOL loopOn = xrc_loop_get_enabled();
    xrc_loop_get_range(&from, &to);
    [self.timeline setLoopFromMs:from to:to visible:loopOn];

    if (!xrc_cap_player()) {
        self.timeLabel.text = @"--:-- / --:--";   // 无播放器钩子：位置/时长不可读（能力门控）
    } else {
        uint32_t cs = pos / 1000, ts = len / 1000;
        self.timeLabel.text = [NSString stringWithFormat:@"%02u:%02u / %02u:%02u",
                               cs / 60, cs % 60, ts / 60, ts % 60];
    }

    float rate = (float)xrc_clock_get_rate();
    if (!self.speedSlider.tracking) {
        self.speedLabel.text = [NSString stringWithFormat:@"%.2fx", rate];
        if (fabs(self.speedSlider.value - rate) > 0.001f) self.speedSlider.value = rate;
    }
    self.swSpeedAudio.on = xrc_audio_speed_enabled();
}

// 低频（1Hz）：开关镜像 / 状态行 / 判定门控 / 能力行
- (void)refreshSlow {
    uint32_t from = 0, to = 0;
    BOOL loopOn = xrc_loop_get_enabled();
    xrc_loop_get_range(&from, &to);
    BOOL rangeOk = (to > from + 1000);
    self.loopSwitch.on = loopOn;
    BOOL loopAvail = xrc_cap_gp() && (rangeOk || loopOn);
    self.loopSwitch.enabled = loopAvail;
    self.loopSwitch.alpha = loopAvail ? 1.0 : 0.45;
    uint32_t fs = from / 1000, ts2 = to / 1000;
    [self.fromBtn setTitle:(from > 0 ? [NSString stringWithFormat:@"设起点 A  %02u:%02u", fs / 60, fs % 60]
                                     : @"设起点 A")
                  forState:UIControlStateNormal];
    [self.toBtn setTitle:(rangeOk ? [NSString stringWithFormat:@"设终点 B  %02u:%02u", ts2 / 60, ts2 % 60]
                                  : (self.pendingTo ? @"设终点 B（播放中）" : @"设终点 B"))
                forState:UIControlStateNormal];

    self.swResetScore.on     = xrc_replay_reset_score_enabled();
    self.swAutoplay.on   = xrc_judge_autoplay();
    self.swJudgeTimeLock.on = xrc_judge_time_lock();
    xrc_config_t kc; xrc_config_load(&kc);
    BOOL konzetsuAvailable = xrc_konzetsu_available();
    self.konzetsuSelect.enabled = konzetsuAvailable;
    self.swKonzetsuEnabled.enabled = self.swKonzetsuChallenge.enabled = konzetsuAvailable;
    self.swKonzetsuEnabled.on = kc.konzetsu_enabled;
    self.swKonzetsuChallenge.on = kc.konzetsu_challenge;
    [self updateKonzetsuMenu];
    self.swHideDuringPlay.on = kc.hide_button_during_play;
    self.swHideDuringPlay.enabled = xrc_cap_gp();
    self.swJudgeTimeLock.enabled = xrc_judge_is_active() && xrc_feature_complete("judge_time_lock");
    self.swRateOffset.on = xrc_rate_adapt_offset_enabled();
    self.swRateOffset.enabled = xrc_cap_gp();
    self.swRateFlow.on = xrc_rate_adapt_flow_enabled();
    self.swRateFlow.enabled = xrc_cap_gp() && xrc_rate_adapt_flow_available();
    self.swRateFlow.note = xrc_rate_adapt_flow_available() ?
        @"内部流速乘倍率倒数，设置显示值不变；游玩中可切换。" :
        @"当前主程序缺少完整流速钩子或版本校验失败，请更新配套主程序。";
    self.flowField.enabled = self.flowApplyBtn.enabled = self.flowNativeBtn.enabled = xrc_cap_gp() && xrc_rate_adapt_flow_available();
    if (!self.flowField.isFirstResponder) {
        double flow = xrc_rate_adapt_native_flow();
        self.flowField.text = flow > 0 ? [NSString stringWithFormat:@"%.1f", flow] : @"";
    }
    self.swOwn.on      = xrc_brk_unlock_own();
    self.swCb.on       = xrc_brk_cb_bypass();
    self.swNet.on      = xrc_net_enabled();

    self.netStat.text = [NSString stringWithFormat:@"改写 %llu/%llu 请求 ｜ 下载任务 %u 建 / %u 完",
                         xrc_net_rewritten(), xrc_net_requests(),
                         xrc_net_dl_created(), xrc_net_dl_done()];
    self.storeStat.text = xrc_store_cb_status();   // 实读软链状态（不依赖内存标记）

    BOOL judgeOK = g_caps.stub_present && g_caps.judge_handler_live;
    for (UITextField *tf in self.judgeFields) {
        tf.enabled = judgeOK;
        tf.alpha = judgeOK ? 1.0 : 0.5;
    }
    self.judgeApplyBtn.enabled = judgeOK;
    self.judgeApplyBtn.alpha = judgeOK ? 1.0 : 0.5;
    if (judgeOK) {
        self.judgeHdr.text = @"";
    } else if (!g_caps.stub_present) {
        self.judgeHdr.text = @"判定：主程序未打桩（仅 dylib？）";
        self.judgeHdr.textColor = [UIColor colorWithRed:1.0 green:0.63 blue:0.35 alpha:1.0];
    } else if (!g_caps.stub_v2) {
        self.judgeHdr.text = @"判定：桩为 v1 形态，请重新注入（inject.py --stub）";
        self.judgeHdr.textColor = [UIColor colorWithRed:1.0 green:0.63 blue:0.35 alpha:1.0];
    } else {
        self.judgeHdr.text = @"判定：handler 未安装（看日志）";
        self.judgeHdr.textColor = [UIColor colorWithRed:1.0 green:0.63 blue:0.35 alpha:1.0];
    }

    self.capsLabel.text = [NSString stringWithFormat:@"stub=%d v2=%d judge=%d gp=%d mtp=%d",
                           g_caps.stub_present, g_caps.stub_v2, g_caps.judge_handler_live,
                           g_caps.gp_hook_live, g_caps.mtp_hook_live];
    {
        NSArray *all = @[@"unlock_own", @"chain_guard",
                         @"cb_free", @"autoplay", @"applog_capture"];
        NSMutableArray *absent = [NSMutableArray array];
        for (NSString *ft in all)
            if (!xrc_feature_present(ft.UTF8String)) [absent addObject:ft];
        self.patchLine.text = [NSString stringWithFormat:
            @"能力：桩%@ 播放器%@ gp%@ 变速✓ 网络✓ ｜ 未含：%@",
            xrc_cap_stub() ? @"✓" : @"✗", xrc_cap_player() ? @"✓" : @"✗",
            xrc_cap_gp() ? @"✓" : @"✗",
            absent.count ? [absent componentsJoinedByString:@","] : @"(无)"];
    }
#if XRC_DEV_SECTION
    NSInteger idx = [self logPresetIndex];
    if (self.logSeg.selectedSegmentIndex != idx) self.logSeg.selectedSegmentIndex = idx;
#endif
}

- (void)refresh {
    [self refreshFast];
    [self refreshSlow];
}

// ---------------- 文本框 ----------------
- (void)textFieldDidEndEditing:(UITextField *)tf {
    if ([self.judgeFields containsObject:tf]) { [self commitJudge]; return; }
    if (tf == self.netField) {
        NSString *base = [tf.text stringByTrimmingCharactersInSet:
                              [NSCharacterSet whitespaceCharacterSet]];
        xrc_config_t c; xrc_config_load(&c);
        c.net_base = base.length ? base : nil;
        xrc_config_save(&c);
        xrc_net_set_base(c.net_base ? c.net_base.UTF8String : NULL);
        if (c.toast) {
            [WHToast showMessage:[NSString stringWithFormat:@"服务端地址: %@", base.length ? base : @"(空)"]
                        duration:1.0 finishHandler:^{}];
        }
    }
}
- (BOOL)textFieldShouldReturn:(UITextField *)tf { [tf resignFirstResponder]; return YES; }

@end
