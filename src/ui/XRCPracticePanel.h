// © 雾月星辰 & MLXC · github@XingChenRS
// XRCPracticePanel.h — 练习面板（设计稿：ui-mock/panel_mock.html v3）。
// 结构：固定标题栏（拖动 + 说明 + 关闭；标题 = 版本号）+ 可滚动内容区（上限 72% 屏高）。
// 分区：播放（时间轴 / ±5s / 速度 / 音乐变速 / 回跳重播）｜循环（设 A/B + 开关 + 重置）
//       ｜判定窗口（四档 + 应用 + 自动演奏）｜解锁｜网络｜存储｜诊断。
#pragma once

#import <UIKit/UIKit.h>

@interface XRCPracticePanel : UIView

+ (instancetype)shared;
- (void)show;
- (void)hide;
- (BOOL)isVisible;

// 面板显示时的每帧刷新（外部 0.1s 定时器驱动）。
- (void)tick;

@end
