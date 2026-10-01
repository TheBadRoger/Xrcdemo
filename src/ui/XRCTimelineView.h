// © 雾月星辰 & MLXC · github@XingChenRS
// XRCTimelineView.h — 面板时间轴控件（点击/拖动 = seek 预览，松手执行；循环区间可视化）。
// 自 XRCPracticePanel.m 拆出（重构方案 §9）。
#pragma once

#import <UIKit/UIKit.h>

@interface XRCTimelineView : UIView
@property (nonatomic, copy) void (^onScrub)(uint32_t ms, BOOL finished);
@property (nonatomic, assign) uint32_t lengthMs;
@property (nonatomic, assign) uint32_t positionMs;
@property (nonatomic, assign) uint32_t loopFromMs;
@property (nonatomic, assign) uint32_t loopToMs;
@property (nonatomic, assign) BOOL loopVisible;
- (void)setLoopFromMs:(uint32_t)from to:(uint32_t)to visible:(BOOL)visible;
@end
